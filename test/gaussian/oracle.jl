# =============================================================================
# test/gaussian/oracle.jl — TEST-ONLY exact-diagonalization oracle
# =============================================================================
# Self-contained Julia port of GTN.py's ED machinery (GTN.py:1411-1516):
#   _pfaffian            <- GTN.py:1490-1516
#   _majorana_perm_phase <- GTN.py:1411-1430 (realized here as dense matrices,
#                           see majorana_matrices)
#   _bit_reverse_perm    <- GTN.py:1478-1488
#   density_matrix       <- GTN.py:1432-1476 (here: oracle_density_matrix)
#
# Pure functions on plain arrays. NO dependency on QuantumCircuitsMPS,
# GaussianBackend, or SimulationState. Exponential cost — L ≤ 5 enforced.
#
# CONVENTIONS (must match src/Gaussian/kernel.jl, verified in T2):
#   * Mode i (1-indexed) ↔ Majorana indices (2i−1, 2i).
#   * γ_{2i−1} = c_i + c_i†,   γ_{2i} = i(c_i† − c_i), with Jordan-Wigner
#     string on modes < i.
#   * Vacuum covariance block for mode i: Γ[2i−1,2i] = +1 (⟨c†c⟩ = 0);
#     occupied: Γ[2i−1,2i] = −1 (⟨c†c⟩ = 1). Same as T2's vacuum_covariance /
#     occupation_covariance.
#   * BASIS ORDERING: default order = :msb, i.e. SITE 1 IS THE MOST
#     SIGNIFICANT BIT of the computational-basis index. Basis state
#     |n₁ n₂ … n_L⟩ has (0-based) index n₁·2^(L−1) + n₂·2^(L−2) + … + n_L.
#     This matches GTN.py density_matrix(order="msb") default (Python site 0
#     = Julia site 1). Pass order = :lsb for site 1 = least significant bit.
# =============================================================================

using LinearAlgebra

# -----------------------------------------------------------------------------
# Pfaffian via O(n³) skew-symmetric row/column reduction (port of GTN.py:1490)
# -----------------------------------------------------------------------------
function _pfaffian(A::AbstractMatrix; tol::Real = 1e-12)
    M = Matrix{ComplexF64}(A)
    n = size(M, 1)
    size(M, 2) == n || throw(ArgumentError("A must be square"))
    n == 0 && return 1.0 + 0im
    isodd(n) && return 0.0 + 0im
    pf = 1.0 + 0im
    for k in 1:2:(n - 1)
        # find pivot in row k, columns k+1..n
        pivot = 0
        for i in (k + 1):n
            if abs(M[k, i]) > tol
                pivot = i
                break
            end
        end
        pivot == 0 && return 0.0 + 0im
        if pivot != k + 1
            M[[k + 1, pivot], :] = M[[pivot, k + 1], :]
            M[:, [k + 1, pivot]] = M[:, [pivot, k + 1]]
            pf *= -1
        end
        val = M[k, k + 1]
        pf *= val
        if k + 2 <= n
            a = M[k, (k + 2):n]
            b = M[k + 1, (k + 2):n]
            # skew-symmetric Schur complement update (NOT conjugating: use transpose)
            M[(k + 2):n, (k + 2):n] .-= (a * transpose(b) .- b * transpose(a)) ./ val
        end
    end
    return pf
end

# -----------------------------------------------------------------------------
# Bit-reversal permutation (port of GTN.py:1478). Returns 1-based permutation
# vector p such that A[p, p] converts internal LSB ordering to MSB ordering.
# -----------------------------------------------------------------------------
function _bit_reverse_perm(n_modes::Int)
    dim = 1 << n_modes
    perm = Vector{Int}(undef, dim)
    for i in 0:(dim - 1)
        x = i
        r = 0
        for _ in 1:n_modes
            r = (r << 1) | (x & 1)
            x >>= 1
        end
        perm[i + 1] = r + 1
    end
    return perm
end

# -----------------------------------------------------------------------------
# Dense many-body Majorana matrices γ̂₁ … γ̂_{2L}, each 2^L × 2^L.
# Equivalent to GTN.py's _majorana_perm_phase perm/phase tables, materialized
# as matrices: ⟨flip(b)|γ̂|b⟩ entries with Jordan-Wigner sign.
# Reusable helper for independent many-body evolution (e.g. parity projectors
# P_s = (I + s·im·γ̂_a*γ̂_b)/2 applied to ρ).
# -----------------------------------------------------------------------------
function majorana_matrices(L::Int; order::Symbol = :msb)
    order in (:msb, :lsb) || throw(ArgumentError("order must be :msb or :lsb"))
    1 <= L <= 5 ||
        throw(ArgumentError("majorana_matrices: require 1 ≤ L ≤ 5 (exponential cost), got L=$L"))
    dim = 1 << L
    gammas = Vector{Matrix{ComplexF64}}(undef, 2L)
    for j in 0:(L - 1)  # 0-based mode index (Julia site j+1)
        g1 = zeros(ComplexF64, dim, dim)  # γ_{2j+1} = c + c†
        g2 = zeros(ComplexF64, dim, dim)  # γ_{2j+2} = i(c† − c)
        for b in 0:(dim - 1)
            flip = b ⊻ (1 << j)
            parity = count_ones(b & ((1 << j) - 1)) & 1
            sgn = 1 - 2 * parity              # JW string over lower bits
            nj = (b >> j) & 1
            g1[flip + 1, b + 1] = sgn
            g2[flip + 1, b + 1] = sgn * (1 - 2 * nj) * im
        end
        gammas[2j + 1] = g1
        gammas[2j + 2] = g2
    end
    if order === :msb
        p = _bit_reverse_perm(L)
        for k in eachindex(gammas)
            gammas[k] = gammas[k][p, p]
        end
    end
    return gammas
end

# -----------------------------------------------------------------------------
# Exact many-body density matrix from a 2L×2L Majorana covariance matrix
# (port of GTN.py density_matrix, GTN.py:1432-1476):
#   ρ = 2^{-L} Σ_{S ⊆ {1..2L}, |S| even} (−i)^{|S|/2} pf(Γ_S) ∏_{i∈S, ascending} γ̂_i
# -----------------------------------------------------------------------------
function oracle_density_matrix(Γ::AbstractMatrix; tol::Real = 1e-12, order::Symbol = :msb)
    order in (:msb, :lsb) || throw(ArgumentError("order must be :msb or :lsb"))
    n_majorana = size(Γ, 1)
    size(Γ, 2) == n_majorana || throw(ArgumentError("Γ must be a square matrix"))
    iseven(n_majorana) || throw(ArgumentError("Γ must have even dimension"))
    L = n_majorana ÷ 2
    @assert L <= 5 "oracle_density_matrix: L=$L > 5 refused (exponential cost)"
    dim = 1 << L
    γ = majorana_matrices(L; order = order)
    ρ = zeros(ComplexF64, dim, dim)
    # enumerate subsets of {1..2L} via bitmasks; even-size subsets only
    for mask in 0:((1 << n_majorana) - 1)
        iseven(count_ones(mask)) || continue
        if mask == 0
            ρ += Matrix{ComplexF64}(I, dim, dim)
            continue
        end
        idx = [i for i in 1:n_majorana if (mask >> (i - 1)) & 1 == 1]  # ascending
        sz = length(idx)
        coeff = ((-im)^(sz ÷ 2)) * _pfaffian(Γ[idx, idx]; tol = tol)
        abs(coeff) < tol && continue
        # product γ̂_{i1} γ̂_{i2} … γ̂_{ik}, i1 < i2 < … < ik (left to right)
        G = γ[idx[1]]
        for i in idx[2:end]
            G = G * γ[i]
        end
        ρ .+= coeff .* G
    end
    ρ ./= 2^L
    ρ = (ρ + ρ') / 2
    return ρ
end

# -----------------------------------------------------------------------------
# Reference-state builders (same conventions as src/Gaussian/kernel.jl, T2)
# -----------------------------------------------------------------------------

"""Vacuum covariance matrix: ⊕ᵢ [[0,1],[-1,0]] (all modes unoccupied)."""
function oracle_vacuum_covariance(L::Int)
    Γ = zeros(Float64, 2L, 2L)
    for i in 1:L
        Γ[2i - 1, 2i] = 1.0
        Γ[2i, 2i - 1] = -1.0
    end
    return Γ
end

"""Covariance matrix for a product occupation pattern (bits[i]=true ↔ mode i occupied)."""
function oracle_occupation_covariance(bits::AbstractVector{Bool})
    L = length(bits)
    Γ = oracle_vacuum_covariance(L)
    for i in 1:L
        if bits[i]
            Γ[2i - 1, 2i] = -1.0
            Γ[2i, 2i - 1] = 1.0
        end
    end
    return Γ
end

"""
Reference projector |n₁…n_L⟩⟨n₁…n_L| for an occupation pattern.
order=:msb (default): site 1 is the most significant bit of the basis index.
"""
function oracle_basis_projector(bits::AbstractVector{Bool}; order::Symbol = :msb)
    order in (:msb, :lsb) || throw(ArgumentError("order must be :msb or :lsb"))
    L = length(bits)
    dim = 1 << L
    idx0 = 0
    for i in 1:L
        if bits[i]
            shift = order === :msb ? (L - i) : (i - 1)
            idx0 |= 1 << shift
        end
    end
    P = zeros(ComplexF64, dim, dim)
    P[idx0 + 1, idx0 + 1] = 1.0
    return P
end
