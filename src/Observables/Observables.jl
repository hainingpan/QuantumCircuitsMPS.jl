using ITensors
using ITensorMPS

"""
    AbstractObservable

Abstract base type for observable specifications.

Observables are CALLABLE STRUCTS: an instance holds the observable's
parameters (e.g. the entanglement cut) and is invoked on a state as
`obs(state) -> Float64`. Register one for recording with
`track!(state, :name => obs)`; `record!` then appends `obs(state)` (via the
`record_value` hook) to `state.observables[:name]`.

Backend support is per-method multiple dispatch: the generic call
`(obs::MyObs)(state)` implements the MPS path, and backend-specific methods
`(obs::MyObs)(state::SimulationState{StateVectorBackend})` /
`(obs::MyObs)(state::SimulationState{CliffordBackend})` override it. An
observable that cannot be computed on a backend defines a method throwing an
informative `ArgumentError` instead (e.g. `StringOrder` on the Clifford
backend) — see `docs/src/devdocs/backend_interface.md` for the full
support matrix.

User-defined observables subtype `AbstractObservable`, implement
`(obs::MyObs)(state) -> Float64`, and are then accepted by `track!` and
recorded like the built-ins. Observables needing extra recording-time
context override the `record_value` hook (see `DomainWall`).

Subtyping is OPTIONAL for custom observables: `track!` accepts ANY callable
`f(state) -> Number | AbstractVector` (a closure, a function, or a callable
struct) — see `track!` for the full callable contract. Subtype
`AbstractObservable` when you want the built-in scalar `Float64` storage
and the ability to override `record_value`.
"""
abstract type AbstractObservable end

# Include implementations
include("born.jl")
include("domain_wall.jl")
include("entanglement.jl")
include("string_order.jl")
include("magnetization.jl")
include("pauli_string.jl")
include("mutual_information.jl")

# === Observable Tracking API ===

"""
    track!(state::SimulationState, spec::Pair{Symbol, <:Any})

Register an observable to be tracked. Values are stored in
`state.observables[name]`, one entry per record point.

The pair's value may be a built-in observable instance (any
[`AbstractObservable`](@ref), e.g. `EntanglementEntropy`, `Magnetization`,
`PauliString`) — or **any callable** `f(state)`: a closure, a plain
function, or a user-defined callable struct.

# The callable contract

At every record point (an eager `record!(state)` call, or the points
selected by `simulate!`'s `record_when` policy), each tracked observable is
invoked as `f(state)` (through the [`record_value`](@ref) hook) and the
returned value is appended to `state.observables[name]`:

- `f` MUST be side-effect-free with respect to the quantum state: it may
  freely READ `state` (e.g. via `born_probability`, `PauliString`,
  `EntanglementEntropy`, `measurements(state)`), but must not apply gates,
  measure, or consume RNG draws.
- `f` may return a scalar (`Number`) or a vector (`AbstractVector`), e.g.
  a per-site profile. Each record point appends exactly ONE entry (a
  returned vector is stored as a single element, not splatted).
- Errors thrown by `f` propagate out of `record!`. For non-`AbstractObservable`
  callables the error is wrapped in an `ErrorException` naming the observable
  key, with the underlying exception attached as `caused by:`.

# Storage

- `AbstractObservable` specs record into a `Vector{Float64}` (the built-in
  scalar contract). Should such an observable return a non-scalar value,
  the storage is transparently widened to `Vector{Any}` at that record.
- Generic callables record into a `Vector{Any}` (their returns are not
  constrained to `Float64`).

# Examples
```julia
track!(state, :dw1 => DomainWall(order=1))            # built-in observable
track!(state, :p1 => s -> born_probability(s, 1, 0))  # custom closure
track!(state, :zprofile =>
    s -> [PauliString(i => :Z)(s) for i in 1:s.L])    # vector-valued closure
```

See the "Custom Observables" documentation page for worked examples and
the public building blocks to compose.
"""
function track!(state, spec::Pair{Symbol, <:AbstractObservable})
    name, obs = spec
    state.observable_specs[name] = obs
    state.observables[name] = Float64[]
    return nothing
end

function track!(state, spec::Pair{Symbol})
    name, obs = spec
    state.observable_specs[name] = obs
    state.observables[name] = Any[]
    return nothing
end

"""
    record_value(obs, state; i1=nothing) -> Number | AbstractVector

Observable-level recording hook: compute the value `record!` should append
for `obs`. The default is simply `obs(state)` — both for `AbstractObservable`
instances and for generic callables (the untyped fallback), so ANY callable
registered via `track!` is recorded without further ceremony.

Observables that need extra recording-time context override this method
instead of being special-cased inside `record!` — e.g. `DomainWall` resolves
its sampling site from `i1_fn` (registration-time closure) or the explicit
`i1` keyword. User-defined observables may override it the same way:

```julia
QuantumCircuitsMPS.record_value(obs::MyObs, state; i1=nothing) = ...
```

This is a MECHANISM hook only — it must return the value the observable's
call protocol defines: a `Float64` for the built-in scalar observables, or
more generally any `Number` or `AbstractVector` (see `track!` for the
storage contract).
"""
record_value(obs, state; i1::Union{Int, Nothing} = nothing) = obs(state)

record_value(obs::AbstractObservable, state; i1::Union{Int, Nothing} = nothing) = obs(state)

function record_value(obs::DomainWall, state; i1::Union{Int, Nothing} = nothing)
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
Errors thrown by a tracked observable propagate; for generic callables
(non-`AbstractObservable` specs, see `track!`) they are wrapped in an
`ErrorException` naming the observable key.

# Keyword Arguments
- `i1`: Explicit DomainWall sampling site (required when the tracked
  `DomainWall` was registered without an `i1_fn`)
- `only`: Optional collection of tracked-observable names (`Symbol`s). When
  given, ONLY those observables are recorded — the others' vectors do not
  grow. Naming an untracked observable throws an `ArgumentError`. Used by
  selective `record!(c, names...)` circuit markers.
"""
function record!(state; i1::Union{Int, Nothing} = nothing, only = nothing)
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
        val = try
            record_value(obs, state; i1 = i1)
        catch
            # Built-in observables throw informative, typed errors of their
            # own (pinned by tests) — propagate those untouched. A generic
            # callable's error, however, would be anonymous: name the key.
            obs isa AbstractObservable && rethrow()
            throw(ErrorException(
                "record!: custom observable :$name ($(typeof(obs))) threw while " *
                "recording — see the underlying exception below (`caused by:`)."))
        end
        store = state.observables[name]
        if store isa Vector{Float64} && !(val isa Real)
            # Vector-returning AbstractObservable (e.g. an entropy profile):
            # widen the scalar container once, preserving prior records.
            store = state.observables[name] = Vector{Any}(store)
        end
        push!(store, val)
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
    return ["DomainWall", "BornProbability",
        "EntanglementEntropy", "StringOrder", "Magnetization", "PauliString",
        "MutualInformation"]
end
