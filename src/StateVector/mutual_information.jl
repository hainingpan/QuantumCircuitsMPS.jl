# === MutualInformation — State-Vector Backend ===
#
# Exact subset entropies via partial trace: reshape ψ into an L-way tensor,
# group the kept sites' dimensions together via permutedims, and take
# svdvals of the (d^m × d^(L-m)) matrix — squared singular values are
# exactly the eigenvalues of the reduced density matrix of the kept sites.
# This generalizes the reshape+svdvals pattern of
# `src/StateVector/entanglement.jl` from prefix cuts to ARBITRARY site
# subsets (in particular the disjoint union A∪B).
#
# Basis convention (matches all other SV code): site 1 = MSB of the basis
# index, i.e. tensor dimension k (column-major, fastest first) corresponds
# to physical site L-k+1.

using LinearAlgebra: svdvals

"""
    _sv_subset_probs(state, phys_sites) -> Vector{Float64}

Schmidt probabilities (RDM eigenvalues) of an arbitrary subset of physical
sites of a dense state vector: permute the kept sites' tensor dimensions to
the front, reshape to (d^m × d^(L-m)), and square the singular values. The
ordering of kept dimensions does not affect the spectrum.
"""
function _sv_subset_probs(state, phys_sites::Vector{Int})
    L = state.L
    d = state.local_dim
    ψ = state.backend.ψ
    sites = sort(phys_sites)
    m = length(sites)

    T = reshape(ψ, ntuple(_ -> d, L))
    keepdims = [L - s + 1 for s in sites]
    restdims = [k for k in L:-1:1 if !(k in keepdims)]
    A = permutedims(T, vcat(reverse(keepdims), restdims))
    M = reshape(A, d^m, d^(L - m))
    return svdvals(M) .^ 2
end

"""
    (mi::MutualInformation)(state::SimulationState{StateVectorBackend}) -> Float64

State-vector implementation of `MutualInformation`: exact reduced density
matrices for A, B, and A∪B via subset partial trace (see
`_sv_subset_probs`), eigenvalues fed to the shared spectrum→entropy helper.

Cost note: dense and exact — memory/time scale with the full Hilbert space
d^L, so this is practical for L ≲ 20 (the state-vector backend's general
operating range); no additional region-size guard is needed beyond that.
"""
function (mi::MutualInformation)(state::SimulationState{StateVectorBackend})
    _validate_mutual_information(mi, state)

    SA = _mi_entropy_from_probs(_sv_subset_probs(state, collect(mi.regionA)),
        mi.renyi_index, mi.base, mi.threshold)
    SB = _mi_entropy_from_probs(_sv_subset_probs(state, collect(mi.regionB)),
        mi.renyi_index, mi.base, mi.threshold)
    SAB = _mi_entropy_from_probs(
        _sv_subset_probs(state, vcat(collect(mi.regionA), collect(mi.regionB))),
        mi.renyi_index, mi.base, mi.threshold)
    return SA + SB - SAB
end
