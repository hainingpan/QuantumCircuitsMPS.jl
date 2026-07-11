module QuantumCircuitsMPS

# Explicit imports (ExplicitImports.jl-verified, T29): every name this module
# uses from its dependencies is imported by name — no implicit `using X`
# reliance. The standing gate lives in test/quality/explicit_imports.jl.
using ITensorMPS: ITensorMPS, @OpName_str, @SiteType_str, @StateName_str,
                  @ValName_str, MPO, MPS, OpName, SiteType, StateName, ValName,
                  expect, inner, linkind, op, ops, orthogonalize,
                  orthogonalize!, random_mps, siteind, siteinds, truncate!
using ITensors: ITensors, ITensor, Index, dag, delta, dim, dims, findindex,
                inds, noprime, noprime!, plev, prime, scalar, tags
using LinearAlgebra: LinearAlgebra, Diagonal, I, diag, diagm, mul!, norm,
                     normalize!, qr, svd, tr
using Random: Random, AbstractRNG, MersenneTwister

# Core
include("Core/basis.jl")
include("Core/rng.jl")
include("Core/spin_sites.jl")  # arbitrary spin-S SiteType extension + spin_operators

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
include("StateVector/pauli_string.jl")
include("StateVector/mutual_information.jl")

# Clifford observable/measurement implementations (backend-specific dispatch
# methods added to already-exported names: born_probability, Magnetization.
# Overrides _measure_single_site! since Clifford measurement does not go
# through the default Projection-based path.)
include("Clifford/measurement.jl")
include("Clifford/entanglement.jl")
include("Clifford/magnetization.jl")
include("Clifford/observables.jl")
include("Clifford/pauli_string.jl")
include("Clifford/mutual_information.jl")

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
export SimulationState, initialize!, ProductState, RandomMPS, RandomStateVector
# Event log (opt-in via SimulationState(...; log_events=true)).
# Event TYPES (CircuitEvent, GateApplied, MeasurementOutcome) and log_event! are
# internal — use qualified names (manifest KEEP+ADD tables list only the accessors).
export events, measurements
# RNG
export RNGRegistry, get_rng
export expected_draws  # v0.1 fixed-draw contract
# NOTE: draw, with_guarded_stream, SentinelRNG, is_aliased are internal —
# use qualified (QuantumCircuitsMPS.draw, ...). The type-pirating
# Base.rand(state, stream) extension was removed in v0.1 (use draw).
# Gates
export AbstractGate, PauliX, PauliY, PauliZ, Projection, HaarRandom, Reset, CZ
export MatrixGate, Rx, Ry, Rz, Hadamard, ProductGate  # v0.1 gates
export CNOT, PhaseGate, SWAP, RandomClifford  # Clifford backend gates (also usable on MPS/SV)
export Measure, OnOutcome  # v0.1 feedback system (AbstractFeedback/CallbackFeedback internal — use qualified)
export total_spin_projector, verify_spin_projectors
export SpinSectorProjection, SpinSectorMeasurement
# Geometry
export AbstractGeometry, SingleSite, AdjacentPair, Bricklayer, AllSites
export StaircaseLeft, StaircaseRight
export Pointer, move!
export EachSite, Sites, elements, element_count, is_broadcast  # v0.1 geometry vocabulary
# Observables
export AbstractObservable, DomainWall, BornProbability, EntanglementEntropy, StringOrder,
       Magnetization, PauliString,  # PauliString added v0.4.0 (T24)
       MutualInformation,  # MutualInformation added v0.4.0 (T25)
       Correlator, EntropyProfile, TripartiteMutualInformation,
       MagnetizationFluctuations  # composed common observables added v0.4.0 (T38)
export born_probability  # functional form of BornProbability (used in README/Quick Start)
export track!, record!, list_observables
# API — legacy entry points (simulate, simulate_circuits, run_circuit!,
# CircuitSimulation, with_state, current_state, record_every, record_at_circuits,
# record_always, get_state, get_observables, circuits_run) were REMOVED in v0.1.0;
# unexported migration stubs remain in src/API/.
export apply!, apply_with_prob!
# Circuit (lazy mode API)
export Circuit, expand_circuit, expand_circuit_grouped, simulate!, ExpandedOp
export RecordingContext, every_n_gates, every_n_steps
# ASCII Plotting
export print_circuit
# Visualization (provided by Luxor extension)
# _plot_circuit_impl is defined in ext/QuantumCircuitsMPSLuxorExt.jl when Luxor is loaded
function _plot_circuit_impl end

"""
    plot_circuit(circuit::Circuit; n_steps=1, gates_spacetime=0, filename=nothing)

Export an SVG diagram of `circuit`'s deterministic template (all stochastic
branches, with probability annotations), resolved for `n_steps` repetitions
using the `gates_spacetime` seed for stochastic-branch layout — matching
`expand_circuit(circuit; seed=gates_spacetime)`.

Requires `using Luxor` to be loaded first (the implementation lives in the
Luxor package extension, `ext/QuantumCircuitsMPSLuxorExt.jl`); calling this
without Luxor loaded throws a `MethodError` from the un-implemented
`_plot_circuit_impl`. When `filename` is `nothing`, the SVG is written to a
temporary file and its path returned; otherwise it is written to `filename`.

See also [`print_circuit`](@ref) for a Luxor-free ASCII/Unicode terminal
visualization of the same circuit template.

# Example
```julia
using QuantumCircuitsMPS, Luxor

circuit = Circuit(L=4, bc=:periodic) do c
    apply!(c, Reset(), StaircaseRight(1))
end
plot_circuit(circuit; gates_spacetime=42, filename="diagram.svg")
```
"""
function plot_circuit(circuit::Circuit; n_steps::Int = 1, gates_spacetime::Int = 0,
        filename::Union{String, Nothing} = nothing)
    Base.invokelatest(_plot_circuit_impl, circuit; n_steps = n_steps,
        gates_spacetime = gates_spacetime, filename = filename)
end
export plot_circuit

# NOTE (v0.4.0): the former "INTERNAL EXPORTS (for CT.jl parity/debugging)"
# block was removed — these remain available via qualified access
# (e.g. `QuantumCircuitsMPS.advance!`), but are NOT public API:
#   advance!, get_sites, current_position, reset!          (Geometry internals)
#   compute_site_staircase_right, compute_site_staircase_left,
#   compute_pair_staircase                                 (pure geometry computation)
#   apply_op_internal!                                     (apply internals)
#   compute_basis_mapping, physical_to_ram, ram_to_physical (basis internals)
# born_probability was promoted to the public Observables exports above.

end # module
