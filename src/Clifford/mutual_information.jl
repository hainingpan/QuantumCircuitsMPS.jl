# === MutualInformation — Clifford (stabilizer-tableau) Backend ===
#
# GENERALIZATION DECISION (T25): implemented. QuantumClifford's
# `entanglement_entropy(tableau, subsystem, Val(:rref))` — the same GF(2)
# rank routine already used by `src/Clifford/entanglement.jl` for prefix
# cuts — natively accepts ARBITRARY site subsets (verified empirically:
# GHZ(4) gives S({1}) = S({4}) = S({1,4}) = S({1,3}) = 1 bit, S(all) = 0),
# so the three subsystem entropies of I(A:B) need no new rank code at all.
#
# For stabilizer states every Rényi-n entropy is identical (flat spectrum),
# so `renyi_index` and `threshold` need no special handling here.
#
# NAMESPACE NOTE (same as Clifford.jl / entanglement.jl): bare
# `import QuantumClifford` + fully-qualified calls only.
import QuantumClifford

"""
    (mi::MutualInformation)(state::SimulationState{CliffordBackend}) -> Float64

Clifford implementation of `MutualInformation`: the three subsystem
entropies S(A), S(B), S(A∪B) are each computed in poly-time via
`QuantumClifford.entanglement_entropy(tableau, subsystem, Val(:rref))`
(GF(2) rank), which supports arbitrary — including non-contiguous —
subsystems. Results are in bits and converted to `mi.base` via
`k * log(2) / log(base)`, mirroring the Clifford `EntanglementEntropy`.

`entanglement_entropy` mutates its input's internal row representation, so
each call operates on a fresh `copy(...)` of the tableau (same precaution
as `src/Clifford/entanglement.jl`).
"""
function (mi::MutualInformation)(state::SimulationState{CliffordBackend})
    _validate_mutual_information(mi, state)

    ramA = sort!([state.phy_ram[s] for s in mi.regionA])
    ramB = sort!([state.phy_ram[s] for s in mi.regionB])
    ramAB = sort!(vcat(ramA, ramB))

    tableau = state.backend.tableau
    kA = QuantumClifford.entanglement_entropy(copy(tableau), ramA, Val(:rref))
    kB = QuantumClifford.entanglement_entropy(copy(tableau), ramB, Val(:rref))
    kAB = QuantumClifford.entanglement_entropy(copy(tableau), ramAB, Val(:rref))

    return (kA + kB - kAB) * log(2) / log(mi.base)
end
