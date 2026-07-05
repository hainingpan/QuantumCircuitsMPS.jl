module QuantumCircuitsMPS

using ITensors
using ITensorMPS
using Random
using LinearAlgebra

# Core
include("Core/basis.jl")
include("Core/rng.jl")

# Backend
include("Backend/Backend.jl")

# State
include("State/events.jl")  # CircuitEvent types (needed by SimulationState field)
include("State/State.jl")
include("State/initialization.jl")

# StateVector (state-vector backend initialization; needs AbstractInitialState/
# ProductState from State and StateVectorBackend from Backend, both already
# loaded above — first file of a growing multi-file src/StateVector/ component)
include("StateVector/initialization.jl")

# Clifford (stabilizer-tableau backend initialization; needs
# AbstractInitialState/ProductState from State and CliffordBackend from
# Backend, both already loaded above)
include("Clifford/initialization.jl")

# Gates
include("Gates/Gates.jl")

# Geometry
include("Geometry/Geometry.jl")

# StateVector gate-application engine (Tier 1 / vanilla): needs gate_matrix,
# support, needs_normalization, AbstractGate, HaarRandom (all from Gates,
# included above) and SimulationState{StateVectorBackend} (from State +
# StateVector/initialization.jl, included earlier). Must come before
# Core/apply.jl only for ordering clarity — no hard dependency either way
# since _apply_single! dispatch is resolved at call time, but keeping gate
# application code together is clearer.
include("StateVector/StateVector.jl")

# StateVector gate-application engine (Tier 2 / optimized): stride-loop
# kernel, dispatches via `_apply_single!` (defined above in StateVector.jl)
# checking `state.backend.engine`. Must come after StateVector.jl since
# _apply_single! references `apply_gate_sv_optimized!` by name.
include("StateVector/optimized.jl")

# Clifford gate-application engine: _apply_single! methods for
# SimulationState{CliffordBackend}, dispatched per gate type onto a
# QuantumClifford.jl MixedDestabilizer tableau. Needs AbstractGate/gate
# structs (from Gates, included above), CliffordBackend (from Backend), and
# get_rng (from Core/rng.jl). Placed alongside the other backends' gate-
# application engines, before Core/apply.jl (whose default execute!/apply!
# dispatch chain routes to _apply_single! once defined here).
include("Clifford/Clifford.jl")

# Core apply! (after State, Gates, Geometry)
include("Core/apply.jl")

# Observables
include("Observables/Observables.jl")

# StateVector observable/measurement implementations (backend-specific dispatch
# methods added to already-exported names: born_probability, EntanglementEntropy,
# Magnetization, StringOrder — plus the unexported domain_wall function)
include("StateVector/measurement.jl")
include("StateVector/entanglement.jl")
include("StateVector/magnetization.jl")
include("StateVector/domain_wall.jl")
include("StateVector/string_order.jl")

# API
include("API/probabilistic.jl")

# Circuit (lazy mode API)
include("Circuit/Circuit.jl")

# ProductGate (late include: adds methods to the execute! protocol
# (Core/apply.jl), gate_label (Circuit/expand.jl) and the CircuitBuilder
# apply! form (Circuit/builder.jl), so it must come after Circuit)
include("Gates/product_gate.jl")

# Plotting
include("Plotting/Plotting.jl")

# === PUBLIC API EXPORTS ===
# State
export SimulationState, initialize!, ProductState, RandomMPS
# Event log (opt-in via SimulationState(...; log_events=true)).
# Event TYPES (CircuitEvent, GateApplied, MeasurementOutcome) and log_event! are
# internal — use qualified names (manifest KEEP+ADD tables list only the accessors).
export events, measurements
# RNG
export RNGRegistry, get_rng
export expected_draws  # v0.1 fixed-draw contract (see docs/api_surface_v0.1.md ADD table)
# NOTE: draw, with_guarded_stream, SentinelRNG, is_aliased are internal —
# use qualified (QuantumCircuitsMPS.draw, ...). The type-pirating
# Base.rand(state, stream) extension was removed in v0.1 (use draw).
# Gates
export AbstractGate, PauliX, PauliY, PauliZ, Projection, HaarRandom, Measurement, Reset, CZ
export MatrixGate, Rx, Ry, Rz, Hadamard, ProductGate  # v0.1 gates
export Measure, OnOutcome  # v0.1 feedback system (AbstractFeedback/CallbackFeedback internal — use qualified)
export total_spin_projector, verify_spin_projectors
export SpinSectorProjection, SpinSectorMeasurement
# Geometry
export AbstractGeometry, SingleSite, AdjacentPair, Bricklayer, AllSites
export StaircaseLeft, StaircaseRight
export Pointer, move!
export EachSite, Sites, elements, element_count, is_broadcast  # v0.1 geometry vocabulary
# Observables
export AbstractObservable, DomainWall, BornProbability, EntanglementEntropy, StringOrder, Magnetization
export track!, record!, list_observables
# API — legacy entry points (simulate, simulate_circuits, run_circuit!,
# CircuitSimulation, with_state, current_state, record_every, record_at_circuits,
# record_always, get_state, get_observables, circuits_run) were REMOVED in v0.1.0;
# unexported migration stubs remain in src/API/ (docs/api_surface_v0.1.md REMOVE table).
export apply!, apply_with_prob!
# Circuit (lazy mode API)
export Circuit, expand_circuit, expand_circuit_grouped, simulate!, ExpandedOp
export RecordingContext, every_n_gates, every_n_steps
# ASCII Plotting
export print_circuit
# Visualization (provided by Luxor extension)
# _plot_circuit_impl is defined in ext/QuantumCircuitsMPSLuxorExt.jl when Luxor is loaded
function _plot_circuit_impl end
function plot_circuit(circuit::Circuit; n_steps::Int=1, gates_spacetime::Int=0, filename::Union{String,Nothing}=nothing)
    Base.invokelatest(_plot_circuit_impl, circuit; n_steps=n_steps, gates_spacetime=gates_spacetime, filename=filename)
end
export plot_circuit

# === INTERNAL EXPORTS (for CT.jl parity/debugging) ===
# These are exported for testing/verification but not public API
export advance!, get_sites, current_position, reset!  # Geometry internals
export compute_site_staircase_right, compute_site_staircase_left, compute_pair_staircase  # Pure geometry computation
export apply_op_internal!                      # Apply internals  
export born_probability                       # Observable internals
export compute_basis_mapping, physical_to_ram, ram_to_physical # Basis internals

end # module
