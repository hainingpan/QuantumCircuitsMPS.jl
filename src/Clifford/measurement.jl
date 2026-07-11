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
in the Z basis, mutating `state.backend.tableau` in place.

**Draw contract (REDUNDANT-DRAW, cross-backend lockstep):** exactly ONE
scalar `:born_measurement` draw is consumed per measured site — always,
unconditionally — matching the generic MPS/SV `_measure_single_site!`
(Core/apply.jl) draw-for-draw:

- Deterministic case (`anticom_index == 0`): the outcome is read directly
  off the returned phase byte. The draw is REDUNDANT here (the stabilizer
  formalism already fixes the outcome) and its value is DISCARDED — it is
  consumed purely to keep the `:born_measurement` stream position identical
  to the MPS/SV backends, where the (equally ignored) draw is structurally
  unavoidable.
- Undetermined case (`anticom_index > 0`): the outcome is genuinely random
  (50/50) and uses the same draw via the shared `rand(rng) < p₀ ? 0 : 1`
  threshold convention (`p₀ = 0.5` exactly for a stabilizer state); the
  phase of the anticommuting stabilizer row is set accordingly.

This deliberate redundant draw is what guarantees ABSOLUTE cross-backend
reproducibility: same seeds ⇒ same measurement record on MPS, state-vector,
and Clifford alike (audit T7 + T11, `test/audit/cross_backend.jl` (b),
`test/audit/born_measurement.jl` (e)).

!!! note "History"
    Before v0.4.0's release audit, this override consumed ZERO draws for
    deterministic outcomes, so Clifford trajectories diverged from MPS/SV
    under the same seed after the first deterministic measurement
    (entropies still agreed — Pauli-frame invariant). The contract was
    resolved to "always draw, discard if deterministic"; seeded Clifford
    trajectories produced by earlier versions are NOT reproducible under
    the new contract (one-time break, see CHANGELOG 0.4.0).

Logs a `MeasurementOutcome` event exactly like the default implementation
(Core/apply.jl) does, and returns the outcome (0 or 1).
"""
function _measure_single_site!(state::SimulationState{CliffordBackend}, site::Int)
    ram_site = state.phy_ram[site]
    # REDUNDANT-DRAW CONTRACT: draw BEFORE the determinism check, exactly one
    # scalar per measured site (mirrors Core/apply.jl line-for-line), so the
    # :born_measurement stream advances identically on all three backends.
    born_measurement_rng = get_rng(state.rng_registry, :born_measurement)
    r = rand(born_measurement_rng)
    _, anticom_index, result = QuantumClifford.projectZ!(state.backend.tableau, ram_site)
    outcome = if anticom_index == 0
        # Deterministic: outcome fixed by the tableau; `r` is discarded on
        # purpose (see docstring — cross-backend stream-position lockstep).
        result == 0x00 ? 0 : 1
    else
        o = r < 0.5 ? 0 : 1
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
