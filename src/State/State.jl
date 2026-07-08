# Forward declaration for RNGRegistry (defined in Task 2)
# For now, use Union{Nothing, Any} to avoid dependency
const RNGRegistryType = Any

"""
    SimulationState{B<:AbstractBackend}

Main simulation state container holding the numerical backend and metadata.

Fields:
- backend: the numerical backend (`MPSBackend`, `StateVectorBackend`, or
  `CliffordBackend`), holding backend-specific state such as the
  MPS/statevector/tableau, site indices, and SVD truncation parameters.
  When `B == MPSBackend`, the property names `state.mps`, `state.sites`,
  `state.cutoff`, and `state.maxdim` are SUPPORTED API: they forward
  transparently (read and write) to `state.backend.<name>` via
  `getproperty`/`setproperty!` (see
  `Base.getproperty(::SimulationState{MPSBackend}, ::Symbol)`).
- phy_ram: physical site -> RAM index mapping
- ram_phy: RAM index -> physical site mapping
- L: system size
- bc: boundary condition (:open or :periodic)
- site_type: site index type ("Qubit", "S=1", "Qudit")
- local_dim: local Hilbert space dimension (default 2 for qubits)
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
mutable struct SimulationState{B <: AbstractBackend}
    backend::B
    phy_ram::Vector{Int}
    ram_phy::Vector{Int}
    L::Int
    bc::Symbol
    site_type::String
    local_dim::Int
    rng_registry::Union{RNGRegistryType, Nothing}
    observables::Dict{Symbol, Vector}
    observable_specs::Dict{Symbol, Any}
    event_log::Union{Nothing, Vector{CircuitEvent}}
    event_step::Int
    event_op_idx::Int
    event_element_idx::Int
end

# === MPS-backend property forwarding: state.mps/sites/cutoff/maxdim ===
# SUPPORTED API (v0.4.0 decision, T19): a usage census found 42 call sites
# (36 `.mps` + 6 `.sites`, all in test/) against the plan's ≤25 retirement
# threshold, so the forwarding layer is KEPT and declared supported rather
# than retired. src/ internals use `state.backend.<field>` directly.
const _MPS_BACKEND_COMPAT_FIELDS = (:mps, :sites, :cutoff, :maxdim)

"""
    Base.getproperty(state::SimulationState{MPSBackend}, name::Symbol)

Property forwarding for the MPS backend — SUPPORTED API (not a deprecation
shim). For `state::SimulationState{MPSBackend}`, the four property names

- `state.mps`     → `state.backend.mps`
- `state.sites`   → `state.backend.sites`
- `state.cutoff`  → `state.backend.cutoff`
- `state.maxdim`  → `state.backend.maxdim`

forward transparently to the `MPSBackend` fields, for both reads and writes
(`Base.setproperty!` forwards the same four names). All other property names
resolve to `SimulationState`'s own fields.

This convenience is MPS-only by design: `SimulationState{StateVectorBackend}`
and `SimulationState{CliffordBackend}` have no such forwarding (their payloads
are reached explicitly via `state.backend.ψ` / `state.backend.tableau`), so
accessing `state.mps` on them raises a `FieldError` — a loud signal that
MPS-specific code received a non-MPS state.
"""
function Base.getproperty(s::SimulationState{MPSBackend}, name::Symbol)
    if name in _MPS_BACKEND_COMPAT_FIELDS
        return getfield(getfield(s, :backend), name)
    end
    return getfield(s, name)
end

function Base.setproperty!(s::SimulationState{MPSBackend}, name::Symbol, val)
    if name in _MPS_BACKEND_COMPAT_FIELDS
        return setfield!(getfield(s, :backend), name, val)
    end
    return setfield!(s, name, val)
end

"""
    SimulationState(; L, bc, site_type="Qubit", local_dim=2, cutoff=1e-10, maxdim=100, rng=nothing, log_events=false, backend=:mps)

Create a new simulation state. MPS/statevector is created later via initialize!().

Parameters:
- L: system size
- bc: boundary condition (:open or :periodic)
- site_type: site index type ("Qubit", "S=1", "Qudit")
- local_dim: local Hilbert space dimension (default 2)
- cutoff: SVD truncation cutoff (only meaningful for `backend=:mps`; ignored for `backend=:statevector`/`:clifford`)
- maxdim: maximum bond dimension (only meaningful for `backend=:mps`; ignored for `backend=:statevector`/`:clifford`)
- rng: RNGRegistry for reproducible randomness
- log_events: enable the typed event log (default false; see `events`, `measurements`).
  Off by default to avoid any cost in the hot loop.
- backend: `:mps` (default, builds an `MPSBackend` with ITensor site indices),
  `:statevector` (builds a `StateVectorBackend`; no site indices, identity
  phy_ram/ram_phy mapping), or `:clifford` (builds a `CliffordBackend` for
  stabilizer-formalism simulation; qubit-only, identity phy_ram/ram_phy
  mapping, tableau initialized later via `initialize!`).
- pbc_fold_start: physical site the PBC zig-zag fold starts from (default `L÷4+1`).
  Only meaningful for `backend=:mps` with `bc=:periodic`; ignored for `backend=:statevector`/`:clifford`.
- engine: gate-application engine for `backend=:statevector` only — `:builtin`
  (default, Tier 1 reshape/permutedims engine, ground truth) or `:optimized`
  (Tier 2 hand-written stride-loop engine, numerically verified to match
  `:builtin` bitwise/to <1e-13, faster especially for 1-site gates). Accepted
  (but ignored) when `backend=:mps` or `backend=:clifford`, for API
  consistency across backends.

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
        log_events::Bool = false,
        backend::Symbol = :mps,
        engine::Symbol = :builtin,
        pbc_fold_start::Int = L÷4+1
)
    # Validate L (added in v0.4.0 — previously L=0 / negative L were silently
    # accepted and produced empty, unusable states)
    L >= 1 ||
        throw(ArgumentError("L must be a positive integer (L >= 1), got L=$L"))

    # Validate bc
    bc in (:open, :periodic) ||
        throw(ArgumentError("bc must be :open or :periodic, got $bc"))
    engine in (:builtin, :optimized) ||
        throw(ArgumentError("engine must be :builtin or :optimized, got $engine"))

    # Auto-detect local_dim from site_type if not explicitly set.
    # Any spin site type "S=<n>" / "S=<k>/2" (e.g. "S=1", "S=3/2", "S=2")
    # maps to local_dim = 2S+1; "S=1/2" yields 2 (no-op vs the default).
    spin_s = _parse_spin_site_type(site_type)
    if spin_s !== nothing && local_dim == 2  # default not overridden
        local_dim = Int(2 * spin_s + 1)
    end

    if backend == :mps
        # Compute basis mapping (OBC works now, PBC throws until Task 4)
        phy_ram, ram_phy = compute_basis_mapping(L, bc; pbc_fold_start = pbc_fold_start)

        # Create site indices in RAM order
        if site_type == "Qudit"
            sites = siteinds("Qudit", L; dim = local_dim)
        else
            sites = siteinds(site_type, L)
        end

        backend_obj = MPSBackend(nothing, sites, cutoff, maxdim)
    elseif backend == :statevector
        # No MPS bond-dimension folding concept for state vectors: identity mapping.
        phy_ram = collect(1:L)
        ram_phy = collect(1:L)
        backend_obj = StateVectorBackend(nothing, engine)
    elseif backend == :clifford
        # Stabilizer formalism is qubit-only.
        if local_dim != 2
            throw(ArgumentError("Clifford backend only supports qubits (local_dim=2). Got site_type=$site_type, local_dim=$local_dim. Use backend=:mps or backend=:statevector for qudit systems."))
        end
        # No MPS bond-dimension folding concept for stabilizer tableaus: identity mapping.
        phy_ram = collect(1:L)
        ram_phy = collect(1:L)
        backend_obj = CliffordBackend(nothing)
    else
        throw(ArgumentError("backend must be :mps, :statevector, or :clifford, got $backend"))
    end

    # Return state with backend's underlying state = nothing (deferred to initialize!)
    return SimulationState(
        backend_obj,
        phy_ram,
        ram_phy,
        L,
        bc,
        site_type,
        local_dim,
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
