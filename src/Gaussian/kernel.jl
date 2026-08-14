# src/Gaussian/kernel.jl
# Pure numerical kernel for the Gaussian (free-fermion covariance-matrix)
# backend. Line-by-line port of ~/GTN/GTN.py: P_contraction_2 (L1063-1102),
# purify (L1131-1136), correlation_matrix (L29-55, non-op branch), kraus
# (L105-118). No SimulationState dependency — pure functions on matrices.
#
# Conventions (matching the reference Python implementation get_C_f, GTN.py:1518-1523):
# - Mode i (1-based) ↔ Majorana indices (2i−1, 2i).
# - 2×2 block [[0,1],[−1,0]] on a mode ⇒ ⟨c†c⟩ = 0 (unoccupied / vacuum).
# - 2×2 block [[0,−1],[1,0]] on a mode ⇒ ⟨c†c⟩ = 1 (occupied).
# - kraus n=(s,0,0) projection ⇒ post-measurement Γ[i,j] = −s; the vacuum
#   pair (Γ[2i−1,2i] = +1) is the s = −1 outcome.

using LinearAlgebra: Hermitian, cond, det, eigen, issuccess, lu

"""
    majorana_indices(site::Int) -> (Int, Int)

Majorana indices `(2site-1, 2site)` for 1-based fermionic mode `site`.
"""
majorana_indices(site::Int) = (2site - 1, 2site)

"""
    site_majoranas(state, site::Int) -> NTuple{N,Int}

Majorana indices carried by physical `site` of a Gaussian-backend
`SimulationState`, RAM-mapped through `state.phy_ram` (identity on the
Gaussian backend, kept for protocol uniformity). THE single source of truth
for the site → Majorana index mapping — every Gaussian gate / measurement /
observable resolves sites through this helper:

- fermionic-mode granularity (`state.backend.majoranas_per_site == 2`,
  default): returns `(2r−1, 2r)` — the pair of one fermionic mode.
- Majorana-chain granularity (`majoranas_per_site == 1`,
  `site_type="Majorana"`): returns `(r,)` — the site IS one Majorana mode.

Duck-typed on `state` (needs only `phy_ram` and
`backend.majoranas_per_site`) so this pure-kernel file keeps no
`SimulationState` dependency.
"""
function site_majoranas(state, site::Int)
    r = state.phy_ram[site]
    return state.backend.majoranas_per_site == 1 ? (r,) : (2r - 1, 2r)
end

@doc raw"""
    _kraus(n::NTuple{3,<:Real}) -> Matrix{Float64}

``4\times4`` Gaussian gate tensor ``\Upsilon`` parameterized by ``n = (n_1,n_2,n_3)`` — port of
`GTN.kraus` (`GTN.py:105-118`) with `c = [1,1,1]`. Unitary 2-Majorana rotation for ``\|n\| = 1``; parity projection for ``n = (\pm1,0,0)``.
"""
function _kraus(n::NTuple{3, <:Real})
    n1, n2, n3 = float.(n)
    return [0.0 n1 n2 n3;
            -n1 0.0 -n3 n2;
            -n2 n3 0.0 -n1;
            -n3 -n2 n1 0.0]
end

@doc raw"""
    parity_projection_upsilon(s::Int) -> Matrix{Float64}

4×4 Υ projecting a Majorana pair `(i,j)` onto parity outcome ``s \in \{+1,-1\}``,
i.e. `_kraus((s,0,0))`. Post-measurement state has ``\Gamma[i,j] = -s`` (matching the
Python reference: vacuum `Γ[2i−1,2i] = +1` is the `s = −1` outcome; contracting
the vacuum pair with `s = +1` is the probability-zero outcome and throws).
"""
function parity_projection_upsilon(s::Int)
    s in (-1, 1) || throw(ArgumentError("parity outcome s must be +1 or -1, got $s"))
    return _kraus((s, 0, 0))
end

@doc raw"""
    vacuum_covariance(L::Int) -> Matrix{Float64}

`2L×2L` Majorana covariance matrix ``\Gamma_0 = \bigoplus_i \begin{pmatrix}0&1\\-1&0\end{pmatrix}`` of the all-modes-
unoccupied vacuum (port of `correlation_matrix`, `GTN.py:29-55`, non-op
branch). Matches the Python reference `get_C_f`: every mode has ``\langle c^\dagger c\rangle = 0``.
"""
function vacuum_covariance(L::Int)
    Γ = zeros(Float64, 2L, 2L)
    for i in 1:L
        a, b = majorana_indices(i)
        Γ[a, b] = 1.0
        Γ[b, a] = -1.0
    end
    return Γ
end

@doc raw"""
    occupation_covariance(bits::AbstractVector{Bool}) -> Matrix{Float64}

Product-state covariance matrix for occupations `bits`: mode `i` gets block
[[0,1],[−1,0]] when `bits[i] == false` (``\langle c^\dagger c\rangle = 0``) and the sign-flipped block ``\begin{pmatrix}0&-1\\1&0\end{pmatrix}`` when `bits[i] == true` (``\langle c^\dagger c\rangle = 1``). Sign ↔ occupation mapping
matches the Python reference `get_C_f` (`GTN.py:1518-1523`).
"""
function occupation_covariance(bits::AbstractVector{Bool})
    L = length(bits)
    Γ = zeros(Float64, 2L, 2L)
    for i in 1:L
        a, b = majorana_indices(i)
        sign = bits[i] ? -1.0 : 1.0
        Γ[a, b] = sign
        Γ[b, a] = -sign
    end
    return Γ
end

@doc raw"""
    purify!(Γ::Matrix{Float64}) -> Matrix{Float64}

Project a (numerically drifted) covariance matrix back onto the manifold of
pure Gaussian states (``\Gamma^2 = -I``) — port of `purify` (`GTN.py:1131-1136`, see
App. B2 of PhysRevB.106.134206). Eigendecomposes the Hermitian matrix Γ/i,
clamps eigenvalues to ±1, reconstructs ``-\mathrm{Im}(V\,\mathrm{diag}(\mathrm{vals})\,V^\dagger)``, then
antisymmetrizes. In-place; returns `Γ`.
"""
function purify!(Γ::Matrix{Float64})
    vals, vecs = eigen(Hermitian(Γ ./ im))
    clamped = [v < 0 ? -1.0 : (v > 0 ? 1.0 : 0.0) for v in vals]
    Γ .= .-imag.(vecs * Diagonal(clamped) * vecs')
    Γ .= (Γ .- transpose(Γ)) ./ 2
    return Γ
end

@doc raw"""
    gaussian_contraction!(Γ, Υ, ix; scratch=nothing, purify_tol=1e-10) -> Γ

Contract the Gaussian gate tensor `Υ` (2m×2m for m = length(ix) Majorana
legs) into the covariance matrix `Γ` at Majorana indices `ix` (1-based),
in place — line-by-line port of `P_contraction_2` (`GTN.py:1063-1102`):

```math
C = (\Gamma_{RR}\Upsilon_{LL}+I)^{-1}\\
\Gamma[\bar{ix},\bar{ix}] \mathrel{+}= \Gamma_{LR}(\Upsilon_{LL}C)\Gamma_{LR}^T\\
\Gamma[ix,\bar{ix}] = \Upsilon_{RL}C\Gamma_{LR}^T\\
\Gamma[ix,ix] = \Upsilon_{RR}+\Upsilon_{RL}(\Gamma_{RR}C^T)\Upsilon_{RL}^T\\
\Gamma[\bar{ix},ix] = -\Gamma[ix,\bar{ix}]^T
```

Throws `ArgumentError` when ``\Gamma_{RR}\Upsilon_{LL}+I`` is singular (a probability-zero
measurement outcome) — no least-squares fallback. If the result drifts off
the pure-state manifold beyond `purify_tol` (``\max\lvert\mathrm{diag}(\Gamma^2)+1\rvert``), calls
[`purify!`](@ref) and re-antisymmetrizes. `scratch` (same size as Γ) is an
optional preallocated buffer for the ix̄-block update.
"""
function gaussian_contraction!(Γ::Matrix{Float64}, Υ::AbstractMatrix,
        ix::Vector{Int};
        scratch::Union{Matrix{Float64}, Nothing} = nothing,
        purify_tol::Float64 = 1e-10)
    N = size(Γ, 1)
    m = length(ix)
    size(Υ) == (2m, 2m) ||
        throw(ArgumentError("Upsilon must be $(2m)x$(2m) for length(ix)=$m, got $(size(Υ))"))
    ix_bar = setdiff(1:N, ix)

    Γ_RR = Γ[ix, ix]
    Γ_LR = Γ[ix_bar, ix]
    Υ_LL = @view Υ[1:m, 1:m]
    Υ_RR = @view Υ[(m + 1):(2m), (m + 1):(2m)]
    Υ_RL = @view Υ[(m + 1):(2m), 1:m]

    M = Γ_RR * Υ_LL + I
    F = lu(M; check = false)
    if !issuccess(F) || cond(M, 1) > 1e12
        throw(ArgumentError("contraction would produce a vanishing state (probability-zero outcome)"))
    end
    C = inv(F)

    A = Υ_LL * C
    D = Γ_RR * transpose(C)

    if scratch === nothing
        Γ[ix_bar, ix_bar] .+= Γ_LR * A * transpose(Γ_LR)
    else
        buf = @view scratch[1:(N - m), 1:(N - m)]
        mul!(@view(scratch[1:(N - m), (N - m + 1):N]), Γ_LR, A)
        mul!(buf, @view(scratch[1:(N - m), (N - m + 1):N]), transpose(Γ_LR))
        Γ[ix_bar, ix_bar] .+= buf
    end
    Γ[ix, ix_bar] = Υ_RL * C * transpose(Γ_LR)
    Γ[ix, ix] = Υ_RR + Υ_RL * D * transpose(Υ_RL)
    Γ[ix_bar, ix] = -transpose(Γ[ix, ix_bar])

    if maximum(abs.(diag(Γ * Γ) .+ 1)) > purify_tol
        purify!(Γ)
        Γ .= (Γ .- transpose(Γ)) ./ 2
    end
    return Γ
end

@doc raw"""
    haar_orthogonal(rng::AbstractRNG, n::Int) -> Matrix{Float64}

Exact Haar-random special-orthogonal matrix ``Q \in SO(n)``: QR-decompose a
Ginibre matrix, fix the R-diagonal sign ambiguity (``Q \leftarrow Q\,\mathrm{diag}(\mathrm{sign}(\mathrm{diag}(R)))``,
required for Haar on O(n)), then flip the first column if `det(Q) < 0` to
land in SO(n).
"""
function haar_orthogonal(rng::AbstractRNG, n::Int)
    A = randn(rng, n, n)
    F = qr(A)
    Q = Matrix(F.Q)
    Q .= Q * Diagonal(sign.(diag(F.R)))
    if det(Q) < 0
        Q[:, 1] .= .-Q[:, 1]
    end
    return Q
end
