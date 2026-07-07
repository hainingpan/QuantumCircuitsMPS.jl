# === Measurement feedback system (v0.1) ===
# Measure gate + typed feedback (OnOutcome) + closure escape hatch
# (CallbackFeedback). Execution lives in the execute! override in
# Core/apply.jl; feedback dispatch (apply_feedback!) is defined here.

"""
    AbstractFeedback

Supertype for measurement-feedback specifications attached to a
[`Measure`](@ref) gate via its `feedback=` keyword.

Concrete subtypes:
- [`OnOutcome`](@ref): declarative outcome → gate map
- [`CallbackFeedback`](@ref): wraps a raw function
  `(state, sites::Vector{Int}, outcome) -> Any` (raw functions passed to
  `Measure(...; feedback=f)` are auto-wrapped)

Feedback runs INSIDE `with_guarded_stream(registry, :gates_spacetime)`: any
attempt to draw from `:gates_spacetime` during feedback throws (fixed-draw
contract — see `RNGRegistry`). Feedback randomness must come from
`:gates_realization` (e.g. `HaarRandom`) or `:born_measurement` (nested
measurements). Feedback gates do NOT advance engine counters (`gate_idx`)
and emit no `GateApplied` events; a nested `Measure` still emits its
`MeasurementOutcome`.
"""
abstract type AbstractFeedback end

"""
    OnOutcome(pairs::Pair{Int,<:AbstractGate}...)

Declarative measurement feedback: maps measurement outcomes to gates applied
on the measured sites.

```julia
OnOutcome(1 => PauliX())                    # flip back on outcome 1 (Reset)
OnOutcome(0 => Rz(0.3), 1 => HaarRandom(1)) # per-outcome actions
```

Outcomes without a registered gate are left untouched. Duplicate outcome
keys and empty argument lists are `ArgumentError`s.
"""
struct OnOutcome <: AbstractFeedback
    actions::Dict{Int, AbstractGate}

    function OnOutcome(pairs::Pair{Int, <:AbstractGate}...)
        isempty(pairs) && throw(ArgumentError(
            "OnOutcome requires at least one `outcome => gate` pair, e.g. OnOutcome(1 => PauliX())"))
        actions = Dict{Int, AbstractGate}()
        for (outcome, gate) in pairs
            haskey(actions, outcome) && throw(ArgumentError(
                "OnOutcome: duplicate action for outcome $outcome"))
            actions[outcome] = gate
        end
        return new(actions)
    end
end

"""
    CallbackFeedback(f)

Closure escape hatch for measurement feedback. `f` is called as
`f(state, sites::Vector{Int}, outcome)` after the Born sample; its return
value is ignored. `sites` is always a `Vector{Int}` (single-site `Measure`
passes `[site]`).

Raw functions passed to `Measure(...; feedback=f)` are wrapped in this type
automatically — you rarely construct it yourself.

Recursion (feedback applying another `Measure`) is allowed and is the user's
responsibility to terminate.
"""
struct CallbackFeedback <: AbstractFeedback
    f::Function
end

_wrap_feedback(::Nothing) = nothing
_wrap_feedback(fb::AbstractFeedback) = fb
_wrap_feedback(f::Function) = CallbackFeedback(f)
function _wrap_feedback(x)
    throw(ArgumentError(
        "feedback must be an AbstractFeedback (e.g. OnOutcome(1 => PauliX())) " *
        "or a function (state, sites, outcome) -> ...; got $(typeof(x))"))
end

"""
    Measure(basis::Symbol=:Z; feedback=nothing)

Projective measurement gate with optional classical feedback (v0.1).

Born-samples the measured site via the `:born_measurement` stream, collapses
the state, records a `MeasurementOutcome` event (when the event log is
enabled), then dispatches `feedback` with the observed outcome:

- `feedback=OnOutcome(1 => PauliX())` — declarative outcome → gate map
  (applied on the measured sites)
- `feedback=(state, sites, outcome) -> ...` — arbitrary closure
  (auto-wrapped as [`CallbackFeedback`](@ref)); `sites::Vector{Int}`
- `feedback=nothing` (default) — plain projective measurement (the legacy
  `Measurement` gate was removed in v0.4.0; `Measure(:Z)` is its replacement)

`Reset()` is semantically `Measure(:Z; feedback=OnOutcome(1 => PauliX()))`
(bit-identical trajectories under the same seeds).

# RNG contract
Feedback executes inside `with_guarded_stream(registry, :gates_spacetime)`:
drawing from `:gates_spacetime` during feedback throws an error, so feedback
can never desynchronize the fixed spacetime coin sequence. Random feedback
gates (`HaarRandom`, ...) draw from `:gates_realization` as usual.

# Example (adaptive random-unitary feedback)
```julia
m = Measure(:Z; feedback=(st, s, o) -> o == 1 && apply!(st, HaarRandom(1), SingleSite(s[1])))
apply!(state, m, AllSites())
```

Only `:Z` basis is supported in v0.1. `SpinSectorMeasurement` does not
support `feedback=` in v0.1 (informative error).
"""
struct Measure <: AbstractGate
    basis::Symbol
    feedback::Union{Nothing, AbstractFeedback}

    function Measure(basis::Symbol = :Z; feedback = nothing)
        basis == :Z ||
            throw(ArgumentError("Only :Z basis supported currently. Got: $basis"))
        return new(basis, _wrap_feedback(feedback))
    end
end

support(::Measure) = 1
is_measurement(::Measure) = true  # Born-samples via :born_measurement

# Measure requires Born sampling — cannot be built as a plain operator.
function build_operator(gate::Measure, site::Index, local_dim::Int; kwargs...)
    error("Measure gate cannot be built as a single operator. Use apply!(state, Measure(:Z), geo) instead.")
end

# === Feedback dispatch ===
# Called from execute!(state, ::Measure, region) in Core/apply.jl, ALWAYS
# inside with_guarded_stream(registry, :gates_spacetime). SimulationState is
# already defined (State/ is included before Gates/); execute! resolves at
# call time.

"""
    apply_feedback!(fb::AbstractFeedback, state, sites::Vector{Int}, outcome)

Internal: dispatch a feedback specification after a measurement. `OnOutcome`
looks up the gate registered for `outcome` (no-op when absent) and executes
it on `sites`; `CallbackFeedback` calls the wrapped function.
"""
function apply_feedback!(fb::OnOutcome, state::SimulationState, sites::Vector{Int}, outcome::Integer)
    gate = get(fb.actions, outcome, nothing)
    gate === nothing || execute!(state, gate, sites)
    return nothing
end

function apply_feedback!(fb::CallbackFeedback, state::SimulationState, sites::Vector{Int}, outcome::Integer)
    fb.f(state, sites, outcome)
    return nothing
end
