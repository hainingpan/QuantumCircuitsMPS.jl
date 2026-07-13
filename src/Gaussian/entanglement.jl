# === EntanglementEntropy for GaussianBackend ===
# Von Neumann entropy of a fermionic Gaussian state from the Majorana
# covariance matrix Γ (port of GTN.py `von_Neumann_entropy_m` +
# `c_subregion_m`, lines 753-773): the reduced state of a subsystem A is
# fully characterized by the covariance submatrix Γ_A = Γ[idx_A, idx_A]
# (idx_A = the 2|A| Majorana indices of A's sites), whose "entanglement
# spectrum" is the eigenvalues ξ of the Hermitian matrix i·Γ_A. NO
# imaginary-epsilon regularization (Python's `+1e-18j` hack) — exact zeros
# are handled by `_xlogx` instead.
#
# LOG-BASE CONVENTION (matches MPS/StateVector/Clifford EXACTLY): the raw
# entropy is computed in nats (natural log) and converted to the caller's
# requested base via division by `log(ee.base)` — the same
# `log_fn = x -> log(x)/log(base)` factorization used in
# src/Observables/entanglement.jl (MPS), src/StateVector/entanglement.jl,
# and the `k * log(2) / log(ee.base)` conversion in
# src/Clifford/entanglement.jl. The struct default is `base=2` (bits).

using LinearAlgebra: Hermitian, eigvals

"""
    _xlogx(x::Real) -> Float64

`x * log(x)` with the exact limit `0 · log(0) = 0` (returns `0.0` for any
`x <= 0`). Natural log. Used by [`subsystem_entropy`](@ref) so that exactly
(un)occupied modes (λ ∈ {0, 1}) contribute zero entropy with no NaN/Inf and
no imaginary-epsilon regularization.
"""
_xlogx(x::Real) = x <= 0 ? 0.0 : x * log(x)

"""
    subsystem_entropy(Γ::AbstractMatrix{<:Real}, majorana_idx::AbstractVector{Int}) -> Float64

Von Neumann entropy IN NATS (natural log) of the reduced state of a
fermionic Gaussian state on the subsystem spanned by the Majorana indices
`majorana_idx`, computed from the full 2L×2L covariance matrix `Γ`.

Port of `von_Neumann_entropy_m` (GTN.py:753-759):

1. `Γ_A = Γ[majorana_idx, majorana_idx]` — covariance submatrix (plain fancy
   indexing; `majorana_idx` need not be contiguous, which is what makes this
   helper reusable for `MutualInformation` on disjoint regions).
2. `ξ = eigvals(Hermitian(im .* Γ_A))` — real spectrum in [−1, 1]
   (i·Γ_A is exactly Hermitian since Γ is exactly antisymmetric).
3. `λ = clamp.((1 .- ξ) ./ 2, 0.0, 1.0)` — occupation eigenvalues in [0, 1]
   (clamped: float noise can push ξ marginally outside [−1, 1]).
4. `S = -Σ [λ log λ + (1−λ) log(1−λ)] / 2` — the division by 2 compensates
   the double-counting of the 2|A| Majorana eigenvalues (they come in ±ξ
   pairs; Python divides the full sum by 2 the same way).

Callers wanting a different log base divide the result by `log(base)`.
"""
function subsystem_entropy(Γ::AbstractMatrix{<:Real}, majorana_idx::AbstractVector{Int})
    Γ_A = Γ[majorana_idx, majorana_idx]
    ξ = eigvals(Hermitian(im .* Γ_A))          # real, in [-1, 1]
    λ = clamp.((1 .- ξ) ./ 2, 0.0, 1.0)        # λ = (1 - ξ)/2
    return -sum(_xlogx.(λ) .+ _xlogx.(1 .- λ)) / 2
end

"""
    (ee::EntanglementEntropy)(state::SimulationState{GaussianBackend}) -> Float64

Compute the von Neumann entanglement entropy of a fermionic Gaussian state
at bipartition `ee.cut`: subsystem A = physical sites `1..cut` (the same
prefix-bipartition semantics as the Clifford and state-vector backends),
mapped through `state.phy_ram` to RAM sites and then to Majorana indices
`(2r-1, 2r)` per site (identity mapping on the Gaussian backend, kept for
protocol uniformity).

The entropy is computed by [`subsystem_entropy`](@ref) (nats) and converted
to base `ee.base` via `/ log(ee.base)` — identical convention to the other
backends (default `base=2`, i.e. bits; pass `base=ℯ` for nats).

Only von Neumann entropy is available on the Gaussian backend:
`renyi_index != 1` throws an `ArgumentError` (NEVER silently falls back to
von Neumann — unlike stabilizer states, a Gaussian state's entanglement
spectrum is not flat, so Rényi-n genuinely differs from von Neumann).
`ee.threshold` is not used (the `_xlogx` form handles exact zeros without a
singular-value floor).
"""
function (ee::EntanglementEntropy)(state::SimulationState{GaussianBackend})
    1 <= ee.cut < state.L || throw(ArgumentError("cut must satisfy 1 <= cut < L"))
    ee.renyi_index == 1 || throw(ArgumentError(
        "EntanglementEntropy on the Gaussian backend only supports von Neumann entropy " *
        "(renyi_index=1), got renyi_index=$(ee.renyi_index). Rényi entropies are not " *
        "implemented for the covariance-matrix representation — use backend=:mps or " *
        "backend=:statevector for Rényi-n."))
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

    return subsystem_entropy(Γ, idx) / log(ee.base)
end
