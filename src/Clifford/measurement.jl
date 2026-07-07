# === Clifford Born Probability + Measurement ===
# Stabilizer-tableau measurement support for SimulationState{CliffordBackend}.
#
# Unlike MPS/StateVector, Clifford measurement does NOT go through the
# generic `Projection`-based `_measure_single_site!` path (Core/apply.jl):
# `Projection` is not a Clifford gate and is rejected by Clifford.jl's
# fallback `_apply_single!`. Instead we override `_measure_single_site!`
# itself, using QuantumClifford.jl's `projectZ!`, which determines
# determinism and updates the tableau in one step.
#
# NAMESPACE NOTE (see .sisyphus/notepads/clifford-backend/learnings.md,
# Task 6/9 precedent): bare `import QuantumClifford` + fully-qualified calls
# (`QuantumClifford.projectZ!`, `QuantumClifford.phases`,
# `QuantumClifford.stabilizerview`) — avoids any risk of colliding with this
# module's own exported names (e.g. `apply!`) via a selective `using`.
import QuantumClifford

"""
    born_probability(state::SimulationState{CliffordBackend}, site::Int, outcome::Int) -> Float64

Compute the Born (Z-measurement) probability of `outcome` (0 or 1) at
physical `site` for a stabilizer state.

For a stabilizer state, a single-qubit Z measurement is either
DETERMINISTIC (probability exactly 0.0 or 1.0) or perfectly UNDETERMINED
(probability exactly 0.5 for either outcome) — no other value is possible,
a mathematical fact of the stabilizer formalism. This function is a
NON-DESTRUCTIVE, read-only query: it operates on a copy of the tableau via
`QuantumClifford.projectZ!`, so `state.backend.tableau` is left unmodified.
"""
function born_probability(state::SimulationState{CliffordBackend}, site::Int, outcome::Int)
    ram_site = state.phy_ram[site]
    tableau_copy = copy(state.backend.tableau)
    _, anticom_index, result = QuantumClifford.projectZ!(tableau_copy, ram_site)
    if anticom_index == 0
        deterministic_outcome = result == 0x00 ? 0 : 1
        return deterministic_outcome == outcome ? 1.0 : 0.0
    else
        return 0.5
    end
end

"""
    _measure_single_site!(state::SimulationState{CliffordBackend}, site::Int) -> Int

Override the default (Projection-based) `_measure_single_site!` for the
Clifford backend. Uses `QuantumClifford.projectZ!` to measure site `site`
in the Z basis, mutating `state.backend.tableau` in place:

- Deterministic case (`anticom_index == 0`): outcome is read directly off
  the returned phase byte; NO randomness is consumed.
- Undetermined case (`anticom_index > 0`): the outcome is genuinely random
  (50/50), drawn from the `:born_measurement` RNG stream, and the phase of
  the anticommuting stabilizer row is set accordingly.

!!! note "DECISION NEEDED — cross-backend Born-draw-count contract"
    The MPS/SV core `_measure_single_site!` (Core/apply.jl) ALWAYS consumes
    exactly one `:born_measurement` draw per measured site, even when the
    outcome is deterministic; this override consumes ZERO draws for
    deterministic outcomes. Consequence: after the first deterministic
    measurement, the `:born_measurement` stream positions drift and Clifford
    trajectories diverge from MPS/SV under the "same seed" (audit T7 + T11;
    entropy trajectories still agree — Pauli-frame invariant). Whether
    Clifford should burn a draw for deterministic outcomes to restore
    cross-backend lockstep (at the cost of changing all existing seeded
    Clifford trajectories) is an open design question — see the
    `DECISION NEEDED: Clifford Born-draw-count contract` block in
    `.sisyphus/notepads/v04-findings.md` (T17). Do NOT change this
    consumption pattern without resolving that decision.

Logs a `MeasurementOutcome` event exactly like the default implementation
(Core/apply.jl) does, and returns the outcome (0 or 1).
"""
function _measure_single_site!(state::SimulationState{CliffordBackend}, site::Int)
    ram_site = state.phy_ram[site]
    _, anticom_index, result = QuantumClifford.projectZ!(state.backend.tableau, ram_site)
    outcome = if anticom_index == 0
        result == 0x00 ? 0 : 1
    else
        born_measurement_rng = get_rng(state.rng_registry, :born_measurement)
        o = rand(born_measurement_rng) < 0.5 ? 0 : 1
        QuantumClifford.phases(QuantumClifford.stabilizerview(state.backend.tableau))[anticom_index] = (o ==
                                                                                                        0 ?
                                                                                                        0x00 :
                                                                                                        0x02)
        o
    end
    if state.event_log !== nothing
        log_event!(state, MeasurementOutcome(state.event_step, state.event_op_idx, [site], outcome))
    end
    return outcome
end
