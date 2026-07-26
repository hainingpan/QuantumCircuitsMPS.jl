# === EntanglementEntropy for StateVectorBackend ===
# Computes entanglement entropy at a bipartition cut via reshape + svdvals.
# NO permutedims needed — SVD is transpose-invariant: svdvals(M) == svdvals(M'),
# so the {1,...,cut} vs {cut+1,...,L} bipartition is correctly captured regardless
# of which side ends up as rows vs columns in the reshaped matrix.

using LinearAlgebra: svdvals

"""
    (ee::EntanglementEntropy)(state::SimulationState{StateVectorBackend}) -> Float64

Compute the entanglement entropy of a state-vector state at bipartition `ee.cut`.

Reshapes the state vector ψ (length d^L) into a (d^(L-cut) × d^cut) matrix and
computes singular values. The squared singular values give the Schmidt spectrum,
from which the entropy is computed (von Neumann for `renyi_index` within `1e-8` of
1, Rényi-n for any other real n > 0).

The entropy formula mirrors `_von_neumann_entropy` from `src/Observables/entanglement.jl`
exactly: same threshold clipping, the same three-branch Rényi structure with the same
shared branch thresholds (`_RENYI_SHUNT`, `_RENYI_NEAR1`), same base conversion — just
fed singular values from `svdvals(reshape(ψ, ...))` instead of from an MPS bond SVD.
It is a deliberately SEPARATE copy of that kernel, not a call into it.
"""
function (ee::EntanglementEntropy)(state::SimulationState{StateVectorBackend})
    1 <= ee.cut < state.L || throw(ArgumentError("cut must satisfy 1 <= cut < L"))
    L = state.L
    d = state.local_dim
    cut = ee.cut
    ψ = state.backend.ψ

    # Reshape into (d^(L-cut), d^cut) — NO permutedims needed.
    # Julia's column-major convention means dim k <-> site L-k+1, so this groups
    # sites {cut+1,...,L} into the first factor and sites {1,...,cut} into the second.
    # But svdvals(M) == svdvals(M') for any matrix, so the singular values correctly
    # reflect the Schmidt spectrum of the {1,...,cut} vs {cut+1,...,L} bipartition.
    M = reshape(ψ, (d^(L - cut), d^cut))
    svals = svdvals(M)

    # Squared singular values = Schmidt probabilities, with threshold clipping
    p = max.(svals, ee.threshold) .^ 2
    p ./= sum(p)

    # Log with specified base: log_b(x) = log(x) / log(b)
    log_fn = x -> log(x) / log(ee.base)

    # Three branches of δ = n − 1, identical in shape to `_von_neumann_entropy`
    # (src/Observables/entanglement.jl) and `_mi_entropy_from_probs`, sharing
    # the branch thresholds so all three agree on where the branches switch.
    n = ee.renyi_index
    δ = n - 1
    if abs(δ) <= _RENYI_SHUNT
        # von Neumann entropy: S₁ = -Σ p log_b(p)
        return -sum(p .* log_fn.(p))
    end
    isempty(p) && return 0.0
    if abs(δ) <= _RENYI_NEAR1
        # Cancellation-safe near-1 Rényi: Σ pⁿ = Σ p·p^δ = 1 + t with
        # t = Σ p·(p^δ − 1), so Sₙ = −log1p(t)/δ. expm1/log1p keep full
        # relative precision for the tiny δ·log(p) exponents.
        t = sum(p .* expm1.(δ .* log.(p)))
        return -log1p(t) / δ / log(ee.base)
    end
    # General real n: scale-before-overflow, normalization-aware log domain.
    # Every exponent is ≤ 0 after rescaling by the largest probability, so
    # `exp` cannot overflow at any accepted n (including floatmax), and the
    # log(pmax) terms cancel algebraically instead of being amplified by
    # 1/(1−n). `_renyi_scaled_tails` is the shared pure tail-sum utility used
    # ONLY by the general-n branches (never by an n = 1 path).
    t_n, s = _renyi_scaled_tails(log.(p), n)
    return (log1p(t_n) / (1 - n) - (n / (1 - n)) * log1p(s)) / log(ee.base)
end

# === Region form: (ee::EntanglementEntropy{Vector{Int}})(::SimulationState{StateVectorBackend}) ===
#
# Entanglement entropy of an arbitrary region of PHYSICAL sites `ee.cut` against its
# complement. (Deliberately a comment, not a docstring: for callable structs Julia keys
# docs on the argument tuple WITHOUT the functor's own type, so a second docstring here
# would shadow the bipartition method's docs above. The user-facing documentation of both
# `cut` forms lives on the `EntanglementEntropy` type in src/Observables/entanglement.jl.)
#
# The region's reduced density matrix spectrum comes from `_sv_subset_probs`
# (src/StateVector/mutual_information.jl): it permutes the region's tensor dimensions to
# the front, reshapes to (d^m × d^(L-m)) and squares the singular values — exactly the RDM
# eigenvalues. The spectrum is fed to the shared spectrum→entropy helper
# `_mi_entropy_from_probs`, so `renyi_index`, `threshold` and `base` follow the same
# conventions as the bipartition method above (von Neumann for renyi_index within 1e-8 of
# 1, Rényi-n for any other real n ≠ 1 — the two kernels use the same three-branch
# structure and the same shared branch thresholds). For a prefix region 1:k this agrees
# with `EntanglementEntropy(cut = k)`.
#
# Region sites are physical sites under both bc=:open and bc=:periodic (the state-vector
# backend stores sites in physical order), so PBC-wrapped regions such as [L, 1] are well
# defined. Qudits are supported: the subset machinery is driven by `state.local_dim` and
# hardcodes no local dimension.
#
# Cost note: dense and exact — `permutedims` materializes a copy of the full d^L tensor,
# so this shares the state-vector backend's L <= 20 operating range and is more expensive
# than the bipartition path, which needs no permutation.
function (ee::EntanglementEntropy{Vector{Int}})(state::SimulationState{StateVectorBackend})
    _ee_validate_region(ee.cut, state.L)
    probs = _sv_subset_probs(state, ee.cut)
    return _mi_entropy_from_probs(probs, ee.renyi_index, ee.base, ee.threshold)
end
