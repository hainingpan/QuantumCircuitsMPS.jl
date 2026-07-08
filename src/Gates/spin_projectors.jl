# === Spin Sector Projectors for S=1 Chains ===
#
# Projectors onto total spin sectors for two spin-1 particles.
# Used for AKLT forced measurement simulations.
#
# Basis ordering: |1,1⟩, |1,0⟩, |1,-1⟩, |0,1⟩, |0,0⟩, |0,-1⟩, |-1,1⟩, |-1,0⟩, |-1,-1⟩
# (i.e., m₁ ∈ {1,0,-1}, m₂ ∈ {1,0,-1}, lexicographic order)

using LinearAlgebra

"""
    spin1_operators()

Return the spin-1 operators Sz, S+, S- as 3×3 matrices.
Basis ordering: |+1⟩, |0⟩, |-1⟩ (descending m).
"""
function spin1_operators()
    # Sz = diag(1, 0, -1)
    Sz = [1.0 0.0 0.0;
          0.0 0.0 0.0;
          0.0 0.0 -1.0]

    # S+ raises m by 1: S+|m⟩ = √(s(s+1) - m(m+1)) |m+1⟩
    # For s=1: S+|-1⟩ = √2|0⟩, S+|0⟩ = √2|+1⟩, S+|+1⟩ = 0
    Sp = [0.0 sqrt(2.0) 0.0;
          0.0 0.0 sqrt(2.0);
          0.0 0.0 0.0]

    Sm = Sp'  # S- = (S+)†

    return Sz, Sp, Sm
end

"""
    s1_dot_s2()

Compute the S₁·S₂ operator for two spin-1 particles.
Returns a 9×9 matrix in the tensor product basis.

S₁·S₂ = Sz₁⊗Sz₂ + (1/2)(S+₁⊗S-₂ + S-₁⊗S+₂)
"""
function s1_dot_s2()
    Sz, Sp, Sm = spin1_operators()

    # S₁·S₂ = Sz⊗Sz + (1/2)(S+⊗S- + S-⊗S+)
    S1dotS2 = kron(Sz, Sz) + 0.5 * (kron(Sp, Sm) + kron(Sm, Sp))

    return S1dotS2
end

"""
    _s_dot_s(s::Rational) -> Matrix{Float64}

The S₁·S₂ operator for two spin-`s` particles as a `(2s+1)² × (2s+1)²`
matrix in the descending-m tensor product basis (generic version of
[`s1_dot_s2`](@ref), built from `spin_operators(s)`).
"""
function _s_dot_s(s::Rational)
    Sz, Sp, Sm = spin_operators(s)
    return kron(Sz, Sz) + 0.5 * (kron(Sp, Sm) + kron(Sm, Sp))
end

"""
    total_spin_projector(S::Int; s::Real=1, d::Int=Int(2*Rational(s)+1)) -> Matrix{Float64}

Construct the projector onto total spin sector `S` for two spin-`s`
particles (default `s=1`, the historical spin-1 case).

The tensor product decomposes as s ⊗ s = 0 ⊕ 1 ⊕ ... ⊕ 2s, so valid sectors
are `S ∈ 0:Int(2s)`. Returns a d²×d² projector matrix (d = 2s+1).

# Arguments
- `S`: Total spin sector (0 to 2s)
- `s`: Local spin (positive integer or half-integer; default 1)
- `d`: Local dimension (must equal 2s+1; kept as an explicit kwarg for
  backward compatibility with the historical `total_spin_projector(S; d=3)`)

# Examples
```julia
P0 = total_spin_projector(0)          # spin-1 singlet projector (dim=1)
P2 = total_spin_projector(2)          # spin-1 quintet projector (dim=5)
P0_32 = total_spin_projector(0; s=3//2)  # spin-3/2 singlet (16×16, rank 1)

# Completeness for any s: Σ_S P_S = I
@assert sum(total_spin_projector(S; s=2) for S in 0:4) ≈ I(25)
```

# Physics
For `s=1` the three historical hardcoded Clebsch-Gordan polynomials are used
(byte-identical output to pre-v0.4 releases):
- P₂ = (1/6)(S₁·S₂)² + (1/2)(S₁·S₂) + (1/3)I
- P₁ = -(1/2)(S₁·S₂)² - (1/2)(S₁·S₂) + I
- P₀ = (1/3)(S₁·S₂)² - (1/3)I

For any other `s`, the general Lagrange interpolation in S₁·S₂ is used:
P_S = Π_{S'≠S} (S₁·S₂ − λ_{S'}) / (λ_S − λ_{S'}) with eigenvalues
λ_S = ½[S(S+1) − 2s(s+1)] — no Clebsch-Gordan tables needed.
"""
function total_spin_projector(S::Int; s::Real = 1,
        d::Int = Int(2 * Rational{Int}(s) + 1))
    srat = Rational{Int}(s)
    (srat >= 1 // 2 && denominator(srat) <= 2) ||
        throw(ArgumentError("spin s must be a positive integer or half-integer, got $s"))
    d == Int(2 * srat + 1) || throw(ArgumentError(
        "local dimension d=$d is inconsistent with spin s=$s (expected d=$(Int(2 * srat + 1)))"))

    if srat == 1
        # Historical spin-1 path: hardcoded polynomials, byte-identical to
        # pre-generalization releases (AKLT trajectory regression guarantee).
        S in (0, 1, 2) ||
            throw(ArgumentError("S must be 0, 1, or 2 for spin-1 ⊗ spin-1"))

        S1S2 = s1_dot_s2()
        S1S2_sq = S1S2 * S1S2
        I9 = Matrix{Float64}(I, 9, 9)

        if S == 2
            # P₂ = (1/6)(S₁·S₂)² + (1/2)(S₁·S₂) + (1/3)I
            P = (1 / 6) * S1S2_sq + (1 / 2) * S1S2 + (1 / 3) * I9
        elseif S == 1
            # P₁ = -(1/2)(S₁·S₂)² - (1/2)(S₁·S₂) + I
            P = -(1 / 2) * S1S2_sq - (1 / 2) * S1S2 + I9
        else  # S == 0
            # P₀ = (1/3)(S₁·S₂)² - (1/3)I
            P = (1 / 3) * S1S2_sq - (1 / 3) * I9
        end

        return P
    end

    Smax = Int(2 * srat)
    0 <= S <= Smax || throw(ArgumentError(
        "S must be in 0:$Smax for spin-$s ⊗ spin-$s, got $S"))

    # Lagrange interpolation in S₁·S₂: λ_j = ½[j(j+1) − 2s(s+1)]
    SS = _s_dot_s(srat)
    sf = Float64(srat)
    λ(j) = (j * (j + 1) - 2 * sf * (sf + 1)) / 2
    D = d^2
    P = Matrix{Float64}(I, D, D)
    for k in 0:Smax
        k == S && continue
        P = P * (SS - λ(k) * I) / (λ(S) - λ(k))
    end
    return P
end

"""
    verify_spin_projectors(; s::Real=1, tol::Float64=1e-10)

Verify that the spin-`s` pair projectors satisfy required properties.
Returns true if all checks pass, throws error otherwise.

Checks (over all sectors S = 0..2s):
1. Completeness: Σ_S P_S = I
2. Idempotence: P_S² = P_S for all S
3. Orthogonality: Pᵢ·Pⱼ = 0 for i ≠ j
4. Correct dimensions: tr(P_S) = 2S+1
"""
function verify_spin_projectors(; s::Real = 1, tol::Float64 = 1e-10)
    srat = Rational{Int}(s)
    Smax = Int(2 * srat)
    d = Int(2 * srat + 1)
    Ps = [total_spin_projector(S; s = srat) for S in 0:Smax]
    Id = Matrix{Float64}(I, d^2, d^2)

    # Completeness
    @assert norm(sum(Ps) - Id)<tol "Completeness failed: Σ P_S ≠ I for s=$s"

    for (i, P) in enumerate(Ps)
        S = i - 1
        # Idempotence
        @assert norm(P * P - P)<tol "Idempotence failed for P_$S (s=$s)"
        # Correct dimensions (trace = dimension of sector)
        @assert abs(tr(P) - (2S + 1))<tol "Trace failed: tr(P_$S) ≠ $(2S + 1) (s=$s)"
        # Orthogonality
        for j in (i + 1):length(Ps)
            @assert norm(P * Ps[j])<tol "Orthogonality failed: P_$S·P_$(j - 1) ≠ 0 (s=$s)"
        end
    end

    return true
end
