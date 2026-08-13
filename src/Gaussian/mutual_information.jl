# === MutualInformation — Gaussian (fermionic covariance-matrix) Backend ===
#
# I(A:B) = S(A) + S(B) − S(A∪B), each subsystem entropy computed by
# `subsystem_entropy` (src/Gaussian/entanglement.jl) on the covariance
# submatrix Γ[idx, idx]. Reduction to a mode subset is plain fancy indexing,
# so ARBITRARY site subsets — non-contiguous, PBC-wrapped — are supported for
# free; only the bounds part of the shared validation applies here
# (`_mi_validate_bounds`), NOT the contiguity check that the MPS /
# state-vector / Clifford paths enforce in `_validate_mutual_information`.
#
# `TripartiteMutualInformation` needs no Gaussian method: its generic
# callable composes three `MutualInformation` evaluations, which dispatch
# to this override automatically.

@doc raw"""
    _gaussian_region_majoranas(state, region) -> Vector{Int}

Map a (sorted, duplicate-free) collection of PHYSICAL sites to the sorted
vector of its Majorana indices, granularity-aware via
[`site_majoranas`](@ref): fermionic-mode granularity — each site `s`
contributes ``(2r-1, 2r)`` with `r = state.phy_ram[s]` (2·|region| indices);
Majorana-chain granularity (`site_type="Majorana"`) — each site contributes
its own single Majorana index (|region| indices).
"""
function _gaussian_region_majoranas(state, region)
    idx = Int[]
    for site in region
        append!(idx, site_majoranas(state, site))
    end
    sort!(idx)
    return idx
end

"""
    (mi::MutualInformation)(state::SimulationState{GaussianBackend}) -> Float64

Gaussian implementation of `MutualInformation`: the three subsystem
entropies S(A), S(B), S(A∪B) are each computed in nats by
[`subsystem_entropy`](@ref) on the covariance submatrix `Γ[idx, idx]`
(sites → Majorana indices via `_gaussian_region_majoranas`) and the result
is converted to `mi.base` via `/ log(mi.base)` — the same log-base
convention as every other backend (`MutualInformation` defaults to
`base=ℯ`, i.e. nats, so a straddling entangled pair gives I = 2·log 2).

The Gaussian backend supports arbitrary (incl. wrapped/non-contiguous) site
subsets: regions like `[7, 8, 1, 2]` at L=8 (a PBC-wrapped antipodal block)
are valid here even though the MPS/state-vector/Clifford paths reject them —
the reduced state of ANY mode subset is just an index selection of Γ.

Any real `renyi_index` is supported (normalized to `Float64` at construction;
the normalized value must be finite and `> 0`), exactly like the Gaussian
`EntanglementEntropy`: the Rényi-MI is the composition
Iₙ = Sₙ(A) + Sₙ(B) − Sₙ(A∪B) of three covariance-spectrum entropies. As on
every other backend, Iₙ for n ≠ 1 is NOT a proper mutual information — it is
not guaranteed non-negative on mixed regions and need not be monotone in `n`;
it is a commonly used diagnostic, documented rather than forbidden.

`mi.threshold` is not used because every branch is floor-free: `_xlogx` gives
the exact `0·log 0 = 0` limit at n = 1, and for n ≠ 1 each eigenvalue's
log-domain term `ln(λⁿ + (1−λ)ⁿ)` lies between `min(0, (1−n)·ln 2)` and
`max(0, (1−n)·ln 2)` (the min/max form keeps the bound correct in BOTH regimes
n > 1 and 0 < n < 1), hence finite for every accepted `n`.
"""
function (mi::MutualInformation)(state::SimulationState{GaussianBackend})
    _mi_validate_bounds(mi, state)
    Γ = state.backend.corr
    Γ === nothing && throw(ArgumentError(
        "Gaussian state is not initialized — call initialize!(state, ...) before computing observables."))

    idxA = _gaussian_region_majoranas(state, mi.regionA)
    idxB = _gaussian_region_majoranas(state, mi.regionB)
    idxAB = sort!(vcat(idxA, idxB))

    SA = subsystem_entropy(Γ, idxA; renyi_index = mi.renyi_index)
    SB = subsystem_entropy(Γ, idxB; renyi_index = mi.renyi_index)
    SAB = subsystem_entropy(Γ, idxAB; renyi_index = mi.renyi_index)
    return (SA + SB - SAB) / log(mi.base)
end
