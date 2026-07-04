using ITensors
using LinearAlgebra

"""
Abstract base type for all quantum gates.
"""
abstract type AbstractGate end

"""
    support(gate::AbstractGate) -> Int

Return the number of sites this gate acts on (1 for single-qubit, 2 for two-qubit).
"""
function support end

"""
    build_operator(gate, site_or_sites, local_dim; kwargs...) -> ITensor

Build the operator tensor for a gate acting on given site(s).
"""
function build_operator end

# === Gate traits (v0.1 execute! protocol) ===
# Method-based traits replace hardcoded gate-type checks in the engine.
# User-defined gates opt in by adding a method, e.g.:
#     QuantumCircuitsMPS.needs_normalization(::MyGate) = true

"""
    needs_normalization(gate::AbstractGate) -> Bool

Trait: does applying this gate require renormalizing (and truncating) the MPS
afterwards? Default `false` (unitaries preserve the norm).

`true` for projective/collapsing gates (`Projection`, `SpinSectorProjection`,
`SpinSectorMeasurement`). User-defined non-unitary gates opt in with:

```julia
QuantumCircuitsMPS.needs_normalization(::MyProjectiveGate) = true
```
"""
needs_normalization(::AbstractGate) = false

"""
    is_measurement(gate::AbstractGate) -> Bool

Trait: does this gate perform a Born-rule measurement (consuming the
`:born_measurement` RNG stream and collapsing the state)? Default `false`.

`true` for `Measurement` and `SpinSectorMeasurement`. Note `Reset` is a
derived operation (measure + conditional flip) implemented via its own
`execute!` method; it reports `false` here because the gate as a whole is a
deterministic-outcome channel, not an outcome-reporting measurement.
"""
is_measurement(::AbstractGate) = false

# Include gate implementations
include("single_qubit.jl")
include("two_qubit.jl")
include("matrix_gate.jl")    # defines gate_matrix (used by parametrized.jl)
include("parametrized.jl")
include("composite.jl")
include("feedback.jl")       # Measure + AbstractFeedback/OnOutcome/CallbackFeedback (v0.1)
include("spin_projectors.jl")
include("spin_measurement.jl")
