using ITensors
using ITensorMPS

"""
Abstract base type for observable specifications.
"""
abstract type AbstractObservable end

# Include implementations
include("born.jl")
include("domain_wall.jl")
include("entanglement.jl")
include("string_order.jl")
include("magnetization.jl")

# === Observable Tracking API ===

"""
    track!(state::SimulationState, spec::Pair{Symbol, AbstractObservable})

Register an observable to be tracked. Values are stored in state.observables.

Example: track!(state, :dw1 => DomainWall(order=1))
"""
function track!(state, spec::Pair{Symbol, <:AbstractObservable})
    name, obs = spec
    state.observable_specs[name] = obs
    state.observables[name] = Float64[]
    return nothing
end

"""
    record_value(obs::AbstractObservable, state; i1=nothing) -> Float64

Observable-level recording hook (v0.1): compute the value `record!` should
append for `obs`. The default is simply `obs(state)`.

Observables that need extra recording-time context override this method
instead of being special-cased inside `record!` — e.g. `DomainWall` resolves
its sampling site from `i1_fn` (registration-time closure) or the explicit
`i1` keyword. User-defined observables may override it the same way:

```julia
QuantumCircuitsMPS.record_value(obs::MyObs, state; i1=nothing) = ...
```

This is a MECHANISM hook only — it must return the same `Float64` the
observable's `obs(state)` protocol defines.
"""
record_value(obs::AbstractObservable, state; i1::Union{Int,Nothing}=nothing) = obs(state)

function record_value(obs::DomainWall, state; i1::Union{Int,Nothing}=nothing)
    if obs.i1_fn !== nothing
        # i1_fn is set - call observable without i1, it will use i1_fn
        return obs(state)
    elseif i1 !== nothing
        # Explicit i1 passed - use it
        return obs(state, i1)
    else
        throw(ArgumentError(
            "DomainWall requires either i1_fn at registration or i1 at record! call"
        ))
    end
end

"""
    record!(state::SimulationState; i1::Union{Int,Nothing}=nothing, only=nothing)

Compute tracked observables and append values to state.observables.

Each observable's value is obtained through the `record_value` hook
(default `obs(state)`; `DomainWall` uses `i1_fn`/`i1` — see `record_value`).

# Keyword Arguments
- `i1`: Explicit DomainWall sampling site (required when the tracked
  `DomainWall` was registered without an `i1_fn`)
- `only`: Optional collection of tracked-observable names (`Symbol`s). When
  given, ONLY those observables are recorded — the others' vectors do not
  grow. Naming an untracked observable throws an `ArgumentError`. Used by
  selective `record!(c, names...)` circuit markers.
"""
function record!(state; i1::Union{Int,Nothing}=nothing, only=nothing)
    if only !== nothing
        for name in only
            haskey(state.observable_specs, name) || throw(ArgumentError(
                "record! selective name :$name is not a tracked observable. " *
                "Tracked observables: $(sort!(collect(keys(state.observable_specs)))). " *
                "track!(state, :$name => ...) first, or fix the record!(c, ...) marker."))
        end
    end
    for (name, obs) in state.observable_specs
        (only === nothing || name in only) || continue
        push!(state.observables[name], record_value(obs, state; i1=i1))
    end
    return nothing
end

"""
    list_observables() -> Vector{String}

Return a list of available observable type names.

Returns the names of all observable types that can be used with the tracking API.

Example:
```julia
obs_types = list_observables()
# Returns: ["DomainWall", "BornProbability"]
```
"""
function list_observables()::Vector{String}
    return ["DomainWall", "BornProbability", "EntanglementEntropy", "StringOrder", "Magnetization"]
end
