using ITensors
using ITensorMPS

# Forward declaration for RNGRegistry (defined in Task 2)
# For now, use Union{Nothing, Any} to avoid dependency
const RNGRegistryType = Any

"""
    SimulationState

Main simulation state container holding MPS and metadata.

Fields:
- mps: The MPS tensor network (Nothing until initialize! called)
- sites: ITensor site indices
- phy_ram: physical site -> RAM index mapping
- ram_phy: RAM index -> physical site mapping
- L: system size
- bc: boundary condition (:open or :periodic)
- site_type: site index type ("Qubit", "S=1", "Qudit")
- local_dim: local Hilbert space dimension (default 2 for qubits)
- cutoff: SVD truncation cutoff
- maxdim: maximum bond dimension
- rng_registry: RNG streams for reproducibility
- observables: tracked observable values
- observable_specs: observable specifications
- event_log: typed event log (Nothing unless constructed with log_events=true)
- event_step/event_op_idx/event_element_idx: current engine execution context
  (set by simulate! before each execute! call; 0 outside a circuit engine run).
  Used to thread real indices into events emitted from deep call sites
  (e.g. MeasurementOutcome from _measure_single_site!).

Supported site_type values:
- "Qubit": spin-1/2 (local_dim=2, default)
- "S=1": spin-1 (local_dim=3)
- "Qudit": arbitrary dimension (requires local_dim parameter)
"""
mutable struct SimulationState
    mps::Union{MPS, Nothing}
    sites::Vector{Index}
    phy_ram::Vector{Int}
    ram_phy::Vector{Int}
    L::Int
    bc::Symbol
    site_type::String
    local_dim::Int
    cutoff::Float64
    maxdim::Int
    rng_registry::Union{RNGRegistryType, Nothing}
    observables::Dict{Symbol, Vector}
    observable_specs::Dict{Symbol, Any}
    event_log::Union{Nothing, Vector{CircuitEvent}}
    # Engine execution context for event emission (Task 9 real-index
    # threading): simulate! sets these before every execute! call so that
    # deep emission sites (e.g. the Born-measurement primitive) can stamp
    # real (step, op_idx, element_idx) instead of 0 sentinels. They are 0
    # outside an engine run (eager apply! calls have no step context).
    event_step::Int
    event_op_idx::Int
    event_element_idx::Int
end

"""
    SimulationState(; L, bc, site_type="Qubit", local_dim=2, cutoff=1e-10, maxdim=100, rng=nothing, log_events=false)

Create a new simulation state. MPS is created later via initialize!().

Parameters:
- L: system size
- bc: boundary condition (:open or :periodic)
- site_type: site index type ("Qubit", "S=1", "Qudit")
- local_dim: local Hilbert space dimension (default 2)
- cutoff: SVD truncation cutoff
- maxdim: maximum bond dimension
- rng: RNGRegistry for reproducible randomness
- log_events: enable the typed event log (default false; see `events`, `measurements`).
  Off by default to avoid any cost in the hot loop.

For "Qudit" site type, local_dim specifies the dimension (e.g., local_dim=4 for d=4).
"""
function SimulationState(;
    L::Int,
    bc::Symbol,
    site_type::String = "Qubit",
    local_dim::Int = 2,
    cutoff::Float64 = 1e-10,
    maxdim::Int = 100,
    rng = nothing,  # RNGRegistry, attached later or passed here
    log_events::Bool = false
)
    # Validate bc
    bc in (:open, :periodic) || throw(ArgumentError("bc must be :open or :periodic, got $bc"))
    
    # Auto-detect local_dim from site_type if not explicitly set
    if site_type == "S=1" && local_dim == 2  # default not overridden
        local_dim = 3
    end
    
    # Compute basis mapping (OBC works now, PBC throws until Task 4)
    phy_ram, ram_phy = compute_basis_mapping(L, bc)
    
    # Create site indices in RAM order
    if site_type == "Qudit"
        sites = siteinds("Qudit", L; dim=local_dim)
    else
        sites = siteinds(site_type, L)
    end
    
    # Return state with MPS=nothing (deferred to initialize!)
    return SimulationState(
        nothing,  # mps - set by initialize!
        sites,
        phy_ram,
        ram_phy,
        L,
        bc,
        site_type,
        local_dim,
        cutoff,
        maxdim,
        rng,
        Dict{Symbol, Vector}(),  # observables
        Dict{Symbol, Any}(),     # observable_specs
        log_events ? CircuitEvent[] : nothing,  # event_log (opt-in)
        0, 0, 0  # event_step / event_op_idx / event_element_idx (engine context)
    )
end

# === RNG draw (SimulationState method of Core/rng.jl's package-owned draw) ===

"""
    draw(state::SimulationState, stream::Symbol) -> Float64

Draw ONE scalar uniform `Float64` from the named stream of the state's RNG
registry (see `draw(::RNGRegistry, ::Symbol)`). Errors if no registry is
attached.
"""
function draw(state::SimulationState, stream::Symbol)
    isnothing(state.rng_registry) && error("SimulationState has no RNG registry attached.")
    # SCALAR-DRAW CONTRACT: delegates to the registry's single scalar draw
    return draw(state.rng_registry, stream)
end

# === Engine event context (Task 9 real-index threading) ===

"""
    set_event_context!(state::SimulationState, step::Int, op_idx::Int, element_idx::Int)

Record the engine's current execution position on the state. `simulate!`
calls this before every `execute!` invocation so that events emitted from
deep call sites (e.g. `MeasurementOutcome` from the Born-measurement
primitive) carry real `(step, op_idx)` indices. Feedback gates (Task 10)
run inside their measuring gate's `execute!` and inherit its context —
they never advance counters or context themselves.

Costs three integer stores; never allocates.
"""
function set_event_context!(state::SimulationState, step::Int, op_idx::Int, element_idx::Int)
    state.event_step = step
    state.event_op_idx = op_idx
    state.event_element_idx = element_idx
    return nothing
end

# === Typed event log accessors (types defined in State/events.jl) ===

"""
    log_event!(state::SimulationState, ev::CircuitEvent)

Append a `CircuitEvent` to the state's event log. Silent no-op when the log
is disabled (the default), so emission sites can call this unconditionally.
Returns `nothing`.
"""
function log_event!(state::SimulationState, ev::CircuitEvent)
    log = state.event_log
    log === nothing && return nothing
    push!(log, ev)
    return nothing
end

"""
    events(state::SimulationState) -> Vector{CircuitEvent}

Return all recorded circuit events (gate applications and measurement
outcomes) in emission order.

Requires the state to be constructed with `log_events=true`; otherwise throws
an `ArgumentError` (the log is opt-in — an empty return would be
indistinguishable from "nothing happened").

# Post-selection recipe
Run each trajectory with logging enabled, then filter on its measurement
record:

```julia
state = SimulationState(L=L, bc=:periodic, rng=registry, log_events=true)
initialize!(state, ProductState(binary_int=0))
simulate!(circuit, state; n_steps=n)

ms = measurements(state)                # Vector{MeasurementOutcome}
keep = all(m -> m.outcome == 0, ms)     # post-select on all-zero record
keep && push!(accepted_trajectories, state.observables)
```
"""
function events(state::SimulationState)
    log = state.event_log
    log === nothing && throw(ArgumentError(
        "Event log is disabled. Construct the state with " *
        "SimulationState(...; log_events=true) to record circuit events."))
    return log
end

"""
    measurements(state::SimulationState) -> Vector{MeasurementOutcome}

Return only the `MeasurementOutcome` events from the event log (for
post-selection workflows — see `events` for the full recipe).

Throws `ArgumentError` if the state was not constructed with
`log_events=true`.
"""
function measurements(state::SimulationState)
    return MeasurementOutcome[e for e in events(state) if e isa MeasurementOutcome]
end
