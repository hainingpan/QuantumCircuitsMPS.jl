# === EntanglementEntropy for CliffordBackend ===
# Computes entanglement entropy at a bipartition cut using QuantumClifford.jl's
# NATIVE `entanglement_entropy` function, which computes the GF(2) rank-deficiency
# quantity directly on the stabilizer tableau (no hand-rolled Gaussian elimination
# needed). Follows Task 6/9's namespace-collision precedent: bare `import
# QuantumClifford` + fully-qualified calls (safer than a selective `using`, since
# this module defines/exports its own generic names like `apply!`).
import QuantumClifford

"""
    (ee::EntanglementEntropy)(state::SimulationState{CliffordBackend}) -> Float64

Compute the entanglement entropy of a stabilizer state at bipartition `ee.cut`.

Uses `QuantumClifford.entanglement_entropy(tableau, subsystem, Val(:rref))`, which
returns the entropy IN UNITS OF BITS (log base 2) — i.e. the integer rank-deficiency
quantity `|A| - (L - rank)`. This is converted to the caller's requested `base` via
`k * log(2) / log(ee.base)`, mirroring the `log_fn` pattern used by the MPS/SV
implementations.

For stabilizer states, ALL Rényi-n entropies (including von Neumann) are identical:
the entanglement spectrum is exactly flat (every nonzero Schmidt coefficient has
equal weight). So `ee.renyi_index` and `ee.threshold` require NO special handling —
the single formula below is correct for every value of `renyi_index`.

NOTE: `QuantumClifford.entanglement_entropy` mutates its input's internal row
representation, so this always operates on a `copy(...)` of `state.backend.tableau`,
never the real tableau directly (confirmed empirically: `copy(d)` gives an
independent tableau — underlying arrays are NOT shared with the original, and the
original is left unmutated after the copy is passed through the function).
"""
function (ee::EntanglementEntropy)(state::SimulationState{CliffordBackend})
    1 <= ee.cut < state.L || throw(ArgumentError("cut must satisfy 1 <= cut < L"))

    tableau_copy = copy(state.backend.tableau)
    subsystem = collect(1:ee.cut)
    k = QuantumClifford.entanglement_entropy(tableau_copy, subsystem, Val(:rref))

    return k * log(2) / log(ee.base)
end
