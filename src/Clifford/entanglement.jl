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

# === Region form: (ee::EntanglementEntropy{Vector{Int}})(::SimulationState{CliffordBackend}) ===
#
# Entanglement entropy of an ARBITRARY region of physical sites `ee.cut` (already
# sorted and duplicate-free by the constructor) for a stabilizer state.
# (Deliberately a comment, not a docstring: for callable structs Julia keys docs
# on the argument tuple WITHOUT the functor's own type, so a second docstring here
# would shadow the bipartition method's docs above. The user-facing documentation
# of both `cut` forms lives on the `EntanglementEntropy` type in
# src/Observables/entanglement.jl.)
#
# `QuantumClifford.entanglement_entropy(tableau, subsystem, Val(:rref))` — the same
# GF(2) rank routine the bipartition method above uses — natively accepts
# non-contiguous subsystems, so a region needs no new rank code: the prefix
# `collect(1:ee.cut)` is simply replaced by the mapped region. Non-contiguous and
# PBC-wrapped regions (e.g. `[L, 1]`) are therefore supported directly; region
# sites are PHYSICAL sites, mapped to tableau indices through `state.phy_ram`
# exactly as `src/Clifford/mutual_information.jl` does (the mapping is the identity
# on this backend, but the indirection is kept for consistency).
#
# Units and options match the bipartition method exactly: the returned rank quantity
# is in BITS and is converted with `k * log(2) / log(ee.base)`, and
# `ee.renyi_index`/`ee.threshold` need no handling because the stabilizer
# entanglement spectrum is flat (every Rényi-n entropy coincides with the von
# Neumann one).
#
# As above, `entanglement_entropy` mutates its input's internal row representation,
# so it is always handed a `copy(...)` of `state.backend.tableau`.
function (ee::EntanglementEntropy{Vector{Int}})(state::SimulationState{CliffordBackend})
    _ee_validate_region(ee.cut, state.L)

    tableau_copy = copy(state.backend.tableau)
    subsystem = sort!([state.phy_ram[s] for s in ee.cut])
    k = QuantumClifford.entanglement_entropy(tableau_copy, subsystem, Val(:rref))

    return k * log(2) / log(ee.base)
end
