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
from which the entropy is computed (von Neumann for renyi_index=1, Rényi-n otherwise).

The entropy formula mirrors `_von_neumann_entropy` from `src/Observables/entanglement.jl`
exactly: same threshold clipping, same Rényi cases, same base conversion — just fed
singular values from `svdvals(reshape(ψ, ...))` instead of from an MPS bond SVD.
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

    n = ee.renyi_index
    if n == 1
        # von Neumann entropy: S₁ = -Σ p log_b(p)
        return -sum(p .* log_fn.(p))
    elseif n == 0
        # Hartley entropy: S₀ = log_b(rank)
        return log_fn(length(p))
    else
        # Rényi entropy: Sₙ = log_b(Σ pⁿ) / (1-n)
        return log_fn(sum(p .^ n)) / (1 - n)
    end
end
