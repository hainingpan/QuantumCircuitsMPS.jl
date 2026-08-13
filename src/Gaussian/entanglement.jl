# === EntanglementEntropy for GaussianBackend ===
# Rényi-n entropy (real n > 0; von Neumann at n = 1) of a fermionic Gaussian
# state from the Majorana covariance matrix Γ (port of GTN.py
# `von_Neumann_entropy_m` + `c_subregion_m`, lines 753-773): the reduced
# state of a subsystem A is fully characterized by the covariance submatrix
# Γ_A = Γ[idx_A, idx_A] (idx_A = the Majorana indices of A's sites), whose
# "entanglement spectrum" is the eigenvalues ξ of the Hermitian matrix i·Γ_A.
# NO imaginary-epsilon regularization (Python's `+1e-18j` hack) — exact zeros
# are handled by `_xlogx` at n = 1, and for n ≠ 1 by explicit zero-weight
# skipping (near-1 branch) and by the scale-before-overflow log-domain form
# (general branch), which never evaluates `log(0)` against a nonzero weight.
#
# LOG-BASE CONVENTION (matches MPS/StateVector/Clifford EXACTLY): the raw
# entropy is computed in nats (natural log) and converted to the caller's
# requested base via division by `log(ee.base)` — the same
# `log_fn = x -> log(x)/log(base)` factorization used in
# src/Observables/entanglement.jl (MPS), src/StateVector/entanglement.jl,
# and the `k * log(2) / log(ee.base)` conversion in
# src/Clifford/entanglement.jl. The struct default is `base=2` (bits).

using LinearAlgebra: Hermitian, eigvals

@doc raw"""
    _xlogx(x::Real) -> Float64

`x * log(x)` with the exact limit ``0 \cdot \log(0) = 0`` (returns `0.0` for any
`x <= 0`). Natural log. Used by [`subsystem_entropy`](@ref) so that exactly
(un)occupied modes (``\lambda \in \{0, 1\}``) contribute zero entropy with no NaN/Inf and
no imaginary-epsilon regularization.
"""
_xlogx(x::Real) = x <= 0 ? 0.0 : x * log(x)

@doc raw"""
    subsystem_entropy(Γ::AbstractMatrix{<:Real}, majorana_idx::AbstractVector{Int};
                      renyi_index::Real = 1) -> Float64

Rényi-n entropy IN NATS (natural log) of the reduced state of a fermionic
Gaussian state on the subsystem spanned by the Majorana indices
`majorana_idx`, computed from the full 2L×2L covariance matrix `Γ`. The
default `renyi_index = 1` is the von Neumann entropy.

Port of `von_Neumann_entropy_m` (GTN.py:753-759):

1. `Γ_A = Γ[majorana_idx, majorana_idx]` — covariance submatrix (plain fancy
   indexing; `majorana_idx` need not be contiguous, which is what makes this
   helper reusable for `MutualInformation` on disjoint regions).
2. `ξ = eigvals(Hermitian(im .* Γ_A))` — real spectrum in [−1, 1]
   (i·Γ_A is exactly Hermitian since Γ is exactly antisymmetric).
3. `λ = clamp.((1 .- ξ) ./ 2, 0.0, 1.0)` — occupation eigenvalues in [0, 1]
   (clamped: float noise can push ξ marginally outside [−1, 1]).
4. ``S = -\sum \left[\lambda \log \lambda + (1-\lambda)\log(1-\lambda)\right] / 2`` at n = 1, and generally
   ``S_n = \sum \log(\lambda^n + (1-\lambda)^n) / (1-n) / 2`` — the division by 2 compensates
   the double-counting of the Majorana eigenvalues (they come in ±ξ
   pairs; Python divides the full sum by 2 the same way).

Equivalently, over the PAIRED part of ``\mathrm{spec}(i\Gamma_A) = \{\pm\xi_k\}`` (each pair gives
the occupation pair ``\{\lambda, 1-\lambda\} = \{(1-\xi_k)/2, (1+\xi_k)/2\}`` from step 3),

```math
S_n = \frac{1}{1-n} \sum_k \ln\!\left[\left(\frac{1+\xi_k}{2}\right)^n + \left(\frac{1-\xi_k}{2}\right)^n\right]
```

and an ODD-dimensional `Γ_A` (a Majorana-chain region) carries one extra
UNPAIRED ξ = 0 mode contributing exactly `ln(2)/2` to Sₙ for EVERY n — the
per-eigenvalue sum above produces that with no special-casing.

`renyi_index` is evaluated in three branches of ``\delta = n - 1``, at the SAME
thresholds as the MPS / state-vector / mutual-information kernels
(`_RENYI_SHUNT`, `_RENYI_NEAR1`): the exact n = 1 body, a cancellation-safe
`expm1`/`log1p` near-1 form, and a scale-before-overflow log-domain form that
stays finite at n = 2048 or n = floatmax(Float64).

Callers wanting a different log base divide the result by `log(base)`.
"""
function subsystem_entropy(Γ::AbstractMatrix{<:Real}, majorana_idx::AbstractVector{Int};
        renyi_index::Real = 1)
    Γ_A = Γ[majorana_idx, majorana_idx]
    ξ = eigvals(Hermitian(im .* Γ_A))          # real, in [-1, 1]
    λ = clamp.((1 .- ξ) ./ 2, 0.0, 1.0)        # λ = (1 - ξ)/2
    n = Float64(renyi_index)
    δ = n - 1
    if abs(δ) <= _RENYI_SHUNT
        return -sum(_xlogx.(λ) .+ _xlogx.(1 .- λ)) / 2
    end
    # Both n ≠ 1 branches accumulate PER EIGENVALUE with plain integer
    # indexing (`λ` is a plain `Vector{Float64}` from `eigvals`, but integer
    # indexing is the convention shared with `_renyi_scaled_tails`), and are
    # naturally empty-spectrum safe (`total` stays 0.0).
    total = 0.0
    if abs(δ) <= _RENYI_NEAR1
        # Cancellation-safe near-1 Rényi. λⁿ + (1−λ)ⁿ = λ·λ^δ + (1−λ)·(1−λ)^δ
        # = 1 + t with t = λ·expm1(δ·ln λ) + (1−λ)·expm1(δ·ln(1−λ)), so the
        # per-eigenvalue contribution is ln(1+t)/(1−n) = −log1p(t)/δ. expm1
        # keeps full relative precision for the tiny δ·ln λ exponents here,
        # which a plain `λ^n` would lose to cancellation against 1. A
        # ZERO-WEIGHT term is SKIPPED EXPLICITLY: its true contribution is
        # exactly 0, but `0 * expm1(δ * log(0))` evaluates to `0 * Inf` = NaN
        # for δ < 0.
        @inbounds for k in 1:length(λ)
            w = λ[k]
            wc = 1 - w
            t = 0.0
            w > 0 && (t += w * expm1(δ * log(w)))
            wc > 0 && (t += wc * expm1(δ * log(wc)))
            total += -log1p(t) / δ
        end
        return total / 2
    end
    # General real n: NORMALIZATION-AWARE, SCALE-BEFORE-OVERFLOW log domain.
    # With wmax = max(λ, 1−λ), wmin = min(λ, 1−λ) and s = wmin/wmax, the pair
    # normalizes exactly (wmax + wmin = 1 ⇒ wmax = 1/(1+s)), so factoring the
    # dominant ln(wmax) out BEFORE multiplying by n gives
    #   ln(λⁿ + (1−λ)ⁿ)/(1−n) = log1p(sⁿ)/(1−n) − n/(1−n)·log1p(s).
    # Every exponent is ≤ 0, so `exp` cannot overflow at ANY accepted n, and
    # the 1/(1−n) division is applied PER TERM — never as
    # `sum(raw_terms)/(2(1−n))`, whose numerator and denominator both overflow
    # to NaN at n = floatmax. Edges: wmin = 0 ⇒ sⁿ = s = 0 ⇒ contribution 0;
    # λ = 1/2 (flat) ⇒ sⁿ = s = 1 ⇒ contribution ln 2 for every n, including
    # floatmax where n/(1−n) rounds to exactly −1. Direct powers (λ^2048
    # underflows) and un-scaled logsumexp (every n·ln λ is already −Inf at
    # n = floatmax) both fail here.
    @inbounds for k in 1:length(λ)
        w = λ[k]
        wmax = max(w, 1 - w)
        wmin = min(w, 1 - w)
        t_n = wmin == 0 ? 0.0 : exp(n * (log(wmin) - log(wmax)))
        s = wmin / wmax
        total += log1p(t_n) / (1 - n) - (n / (1 - n)) * log1p(s)
    end
    return total / 2
end

"""
    (ee::EntanglementEntropy)(state::SimulationState{GaussianBackend}) -> Float64

Compute the Rényi-`ee.renyi_index` entanglement entropy (von Neumann at
`renyi_index = 1`) of a fermionic Gaussian state at bipartition `ee.cut`:
subsystem A = physical sites `1..cut` (the same prefix-bipartition semantics
as the Clifford and state-vector backends), mapped through `state.phy_ram` to
RAM sites and then to Majorana indices `(2r-1, 2r)` per site (identity
mapping on the Gaussian backend, kept for protocol uniformity).

The entropy is computed by [`subsystem_entropy`](@ref) (nats) and converted
to base `ee.base` via `/ log(ee.base)` — identical convention to the other
backends (default `base=2`, i.e. bits; pass `base=ℯ` for nats).

Any real `renyi_index` is supported (normalized to `Float64` at construction;
the normalized value must be finite and `> 0`): Sₙ comes from the SAME
covariance-spectrum reduction as the von Neumann case, so Rényi-n is computed
exactly and is NEVER silently replaced by von Neumann (unlike stabilizer
states, a Gaussian state's entanglement spectrum is not flat, so Rényi-n
genuinely differs).

`ee.threshold` is not used because both branches are floor-free: at n = 1 the
`_xlogx` form supplies the exact `0·log 0 = 0` limit, and for n ≠ 1 each
eigenvalue's log-domain term `ln(λⁿ + (1−λ)ⁿ)` lies between
`min(0, (1−n)·ln 2)` and `max(0, (1−n)·ln 2)` — the min/max form is what makes
the bound correct in BOTH regimes n > 1 and 0 < n < 1 — hence finite for every
accepted `n`, with the quotient by `(1−n)` landing in `[0, ln 2]`. No
singular-value floor is needed.
"""
function (ee::EntanglementEntropy)(state::SimulationState{GaussianBackend})
    1 <= ee.cut < state.L || throw(ArgumentError("cut must satisfy 1 <= cut < L"))
    Γ = state.backend.corr
    Γ === nothing && throw(ArgumentError(
        "Gaussian state is not initialized — call initialize!(state, ...) before computing observables."))

    # Granularity-aware site → Majorana index mapping (fermionic: (2r−1, 2r)
    # per site; Majorana chain: the site index itself).
    idx = Int[]
    for site in 1:ee.cut
        append!(idx, site_majoranas(state, site))
    end
    sort!(idx)

    return subsystem_entropy(Γ, idx; renyi_index = ee.renyi_index) / log(ee.base)
end

# === Region form: (ee::EntanglementEntropy{Vector{Int}})(::SimulationState{GaussianBackend}) ===
#
# Rényi-`ee.renyi_index` entanglement entropy (von Neumann at
# `renyi_index = 1`) of an ARBITRARY region of PHYSICAL sites
# `ee.cut` against its complement, for a fermionic Gaussian state.
# (Deliberately a comment, not a docstring: for callable structs Julia keys docs
# on the argument tuple WITHOUT the functor's own type, so a second docstring here
# would shadow the bipartition method's docs above. The user-facing documentation
# of both `cut` forms lives on the `EntanglementEntropy` type in
# src/Observables/entanglement.jl.)
#
# Reduction to a mode subset is plain fancy indexing of the covariance matrix
# `Γ[idx, idx]`, so non-contiguous regions (`[1, 3]`) and PBC-wrapped regions
# (`[L, 1]`) cost exactly the same as a prefix and need no special handling.
# Sites are mapped to their Majorana indices by `_gaussian_region_majoranas`
# (granularity-aware, applies `state.phy_ram` via `site_majoranas`), then fed to
# `subsystem_entropy` and converted from nats to base `ee.base` — the same
# `/ log(ee.base)` convention as the bipartition method above.
#
# Region sites are physical sites under both `bc = :open` and
# `bc = :periodic` (the Gaussian backend stores modes in physical order,
# `phy_ram` is the identity), so wrapped regions are unambiguous. For a
# prefix region `1:k` this agrees with `EntanglementEntropy(cut = k)`.
#
# Exactly like the bipartition path, any real `renyi_index` is supported
# (normalized to `Float64` at construction; the normalized value must be
# finite and > 0): Sₙ is read off the SAME covariance spectrum, so Rényi-n is
# exact and is NEVER silently substituted by von Neumann. `ee.threshold` is
# not used because both branches are floor-free: `_xlogx` gives the exact
# `0·log 0 = 0` limit at n = 1, and for n ≠ 1 each eigenvalue's log-domain
# term `ln(λⁿ + (1−λ)ⁿ)` lies between `min(0, (1−n)·ln 2)` and
# `max(0, (1−n)·ln 2)` (the min/max form keeps the bound correct in BOTH
# regimes n > 1 and 0 < n < 1), hence finite for every accepted `n`.
function (ee::EntanglementEntropy{Vector{Int}})(state::SimulationState{GaussianBackend})
    _ee_validate_region(ee.cut, state.L)
    Γ = state.backend.corr
    Γ === nothing && throw(ArgumentError(
        "Gaussian state is not initialized — call initialize!(state, ...) before computing observables."))

    idx = _gaussian_region_majoranas(state, ee.cut)
    return subsystem_entropy(Γ, idx; renyi_index = ee.renyi_index) / log(ee.base)
end
