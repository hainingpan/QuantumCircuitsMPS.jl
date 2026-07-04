# === Typed circuit event log (Task 4, api-refactor-v0.1) ===
# Event TYPES only — accessors (log_event!, events, measurements) live in
# State.jl below the SimulationState definition, since they dispatch on it.

"""
    CircuitEvent

Abstract supertype for all typed circuit events recorded in a
`SimulationState`'s opt-in event log (see `SimulationState(...; log_events=true)`).

Concrete subtypes:
- [`GateApplied`](@ref): a gate was executed on specific sites
- [`MeasurementOutcome`](@ref): a Born-sampled measurement produced an outcome

Access recorded events via [`events`](@ref) and [`measurements`](@ref).
"""
abstract type CircuitEvent end

"""
    GateApplied(step, op_idx, element_idx, gate_label, sites) <: CircuitEvent

Recorded when a gate is applied during circuit execution.

Fields:
- `step::Int`: circuit step index (1-based; `0` if unavailable at emission site)
- `op_idx::Int`: index of the operation within `circuit.operations`
- `element_idx::Int`: index of the geometry element within the operation (1-based)
- `gate_label::String`: human-readable gate label (see `gate_label`)
- `sites::Vector{Int}`: physical sites the gate acted on
"""
struct GateApplied <: CircuitEvent
    step::Int
    op_idx::Int
    element_idx::Int
    gate_label::String
    sites::Vector{Int}
end

"""
    MeasurementOutcome(step, op_idx, sites, outcome) <: CircuitEvent

Recorded when a Born-sampled projective measurement produces an outcome.

Fields:
- `step::Int`: circuit step index (`0` when emitted from the low-level
  measurement primitive, which has no step context — Task 9 engine rewire
  threads real indices)
- `op_idx::Int`: operation index (`0` when unavailable, see above)
- `sites::Vector{Int}`: measured physical sites
- `outcome::Int`: measurement outcome (0 or 1 for qubits)
"""
struct MeasurementOutcome <: CircuitEvent
    step::Int
    op_idx::Int
    sites::Vector{Int}
    outcome::Int
end
