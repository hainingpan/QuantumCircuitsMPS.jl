# === CircuitBuilder (Internal, Do-Block API) ===
# Not exported - users interact via Circuit(f::Function; kwargs...) do-block

"""
    CircuitBuilder

Internal mutable structure for recording circuit operations during do-block construction.

Users never see this type directly - they interact via:

```julia
circuit = Circuit(L=4, bc=:periodic) do c
    apply!(c, Reset(), SingleSite(1))
    apply_with_prob!(c; outcomes=[
        (probability=0.5, gate=PauliX(), geometry=SingleSite(1))
    ])
end
```

The builder records operations as NamedTuples which are then passed to the Circuit constructor.

# Fields
- `L::Int`: Number of physical sites
- `bc::Symbol`: Boundary conditions (`:periodic` or `:open`)
- `operations::Vector{NamedTuple}`: Accumulated operation records
- `params::Dict{Symbol,Any}`: User-defined parameters passed from outer constructor
"""
mutable struct CircuitBuilder
    L::Int
    bc::Symbol
    operations::Vector{NamedTuple}
    params::Dict{Symbol, Any}
end

function CircuitBuilder(L::Int, bc::Symbol, params::Dict{Symbol, Any} = Dict{Symbol, Any}())
    CircuitBuilder(L, bc, NamedTuple[], params)
end

"""
    apply!(builder::CircuitBuilder, gate, geometry)

Record a deterministic gate operation in the circuit builder.

Stores operation as: `(type=:deterministic, gate=gate, geometry=geometry)`

# Example
```julia
Circuit(L=4, bc=:periodic) do c
    apply!(c, Hadamard(), SingleSite(1))
    apply!(c, CNOT(), StaircaseRight(1))
end
```
"""
function apply!(builder::CircuitBuilder, gate, geometry)
    push!(builder.operations, (type = :deterministic, gate = gate, geometry = geometry))
    return nothing
end

"""
    apply_with_prob!(builder::CircuitBuilder; outcomes)

Record a stochastic operation in the circuit builder (v0.1 unified rule).

Stores operation as: `(type=:stochastic, rng=:gates_spacetime, outcomes=collect(outcomes))`

All stochastic coins are drawn from the `:gates_spacetime` stream — the
pre-v0.1 `rng=` keyword was REMOVED (passing it throws an `ArgumentError`
with a migration message).

# Arguments
- `outcomes`: Vector of NamedTuples with keys `(:probability, :gate, :geometry)`

# Semantics (v0.1 unified stochastic rule)
Each outcome's geometry expands to elements (`elements(geo, L, bc)`); all
outcomes must expand to the SAME element count K. Per element k = 1..K, the
engine draws ONE `:gates_spacetime` coin and makes a categorical selection
among the outcomes; the remainder `1 - Σp` selects identity (nothing applied).

# Build-time validations (all `ArgumentError`)
- `outcomes` must be non-empty
- Σp must be ≤ 1 (tolerance `1e-10`)
- Equal-K: every outcome's geometry must expand to the same element count
  (the error names each outcome's geometry and K)
- Staircase/Pointer physics guard: if any outcome uses a staircase or
  `Pointer` geometry, Σp must equal 1. The CIPT random walk advances via the
  selected staircase every step; an identity remainder (`Σp < 1`) would
  silently stall the walk.
- The removed `rng=` keyword (or any other keyword) throws with a migration
  message

# Example
```julia
Circuit(L=4, bc=:periodic) do c
    apply_with_prob!(c; outcomes=[
        (probability=0.3, gate=PauliX(), geometry=SingleSite(1)),
        (probability=0.2, gate=PauliZ(), geometry=SingleSite(1))
    ])
end
```
"""
function apply_with_prob!(
        builder::CircuitBuilder;
        outcomes::Vector{<:NamedTuple{(:probability, :gate, :geometry)}},
        kwargs...
)
    # (iv) rng= kwarg was hard-removed in v0.1 — fail loudly, never ignore
    if haskey(kwargs, :rng)
        throw(ArgumentError(
            "apply_with_prob! no longer accepts the rng= keyword (removed in v0.1.0). " *
            "All stochastic coins are drawn from the :gates_spacetime stream — " *
            "remove `rng=$(repr(kwargs[:rng]))` from the call."))
    end
    if !isempty(kwargs)
        throw(ArgumentError(
            "apply_with_prob! got unsupported keyword argument(s): " *
            join(keys(kwargs), ", ")))
    end

    # Must provide at least one outcome
    if isempty(outcomes)
        throw(ArgumentError("outcomes cannot be empty"))
    end

    # (ii) Validate probabilities sum to ≤ 1.0
    probs = Float64[Float64(o.probability) for o in outcomes]
    total_prob = sum(probs)
    if total_prob > 1.0 + 1e-10
        throw(ArgumentError("Probabilities sum to $total_prob (must be ≤ 1)"))
    end

    op = (type = :stochastic, rng = :gates_spacetime, outcomes = collect(outcomes))

    # (i) Equal-K rule: every outcome must expand to the same element count.
    # _op_element_count (Circuit/draws.jl) throws an ArgumentError naming
    # each outcome's geometry and K on violation.
    _op_element_count(op, builder.L, builder.bc)

    # (iii) Staircase/Pointer physics guard: the walk must advance EVERY
    # step. With Σp < 1 the identity remainder would sometimes be selected,
    # and identity does not advance staircases — silently freezing the CIPT
    # random walk. Make that a build-time error.
    has_walker = any(o -> (o.geometry isa AbstractStaircase) || (o.geometry isa Pointer),
        outcomes)
    if has_walker && total_prob < 1.0 - 1e-10
        throw(ArgumentError(
            "Stochastic operation with staircase/Pointer geometry requires Σp = 1 " *
            "(got Σp = $total_prob). The identity remainder (probability $(1 - total_prob)) " *
            "does not advance staircases, which would silently stall the random walk " *
            "(CIPT physics requires the walk to advance every step). Either make the " *
            "probabilities sum to 1 (e.g. add an explicit identity-like outcome) or use " *
            "a non-walking geometry."))
    end

    # Record stochastic operation
    push!(builder.operations, op)
    return nothing
end

"""
    record!(builder::CircuitBuilder)
    record!(builder::CircuitBuilder, names::Symbol...)

Insert a recording MARKER into the circuit at this position (v0.1).

Stores a pseudo-operation: `(type=:record_mark, names=Symbol[names...])`.

Markers are pure annotations: they never draw from any RNG stream, never
advance the `gate_idx` element-slot counter, and never touch staircase
positions. They fire only under `record_when=:marks` (which records the
tracked observables exactly at each marker position) or inside custom
predicates (which receive `RecordingContext`s with `at_mark=true`).

With no `names`, ALL tracked observables are recorded at the marker. With
explicit `names` (e.g. `record!(c, :entropy)`), only the named observables
are recorded there — each observable's vector grows at its own cadence.
Naming an observable that is not tracked on the state raises an
`ArgumentError` at `simulate!` time.

`simulate!` refuses (ArgumentError) to run a marker-containing circuit under
`record_when ∈ (:every_step, :every_gate, :final_only)` — those policies
would silently ignore the markers.

# Example
```julia
circuit = Circuit(L=L, bc=:periodic) do c
    apply!(c, HaarRandom(), Bricklayer(:even))
    apply_with_prob!(c; outcomes=[(probability=p, gate=Measure(:Z), geometry=EachSite(2:L-1))])
    record!(c)              # record all tracked observables here
    apply!(c, HaarRandom(), Bricklayer(:odd))
    record!(c, :entropy)    # record only :entropy here
end
simulate!(circuit, state; n_steps=25, record_when=:marks)
```
"""
function record!(builder::CircuitBuilder, names::Symbol...)
    push!(builder.operations, (type = :record_mark, names = Symbol[names...]))
    return nothing
end

"""
    Circuit(f::Function; L::Int, bc::Symbol, kwargs...)

Construct a Circuit using do-block syntax with a CircuitBuilder.

A `Circuit` represents ONE time step. To repeat execution, pass `n_steps` to
`simulate!(circuit, state; n_steps=...)`.

The function `f` receives a `CircuitBuilder` instance and can call:
- `apply!(builder, gate, geometry)` - for deterministic operations
- `apply_with_prob!(builder; outcomes)` - for stochastic operations

# Arguments
- `f::Function`: Builder function that receives CircuitBuilder
- `L::Int`: Number of physical sites
- `bc::Symbol`: Boundary conditions (`:periodic` or `:open`)
- `kwargs...`: Additional keyword arguments stored in circuit.params Dict

# Deprecated
Passing `n_steps` to the constructor is no longer supported. Use
`simulate!(circuit, state; n_steps=...)` instead.

# Example
```julia
circuit = Circuit(L=10, bc=:periodic) do c
    apply!(c, Hadamard(), SingleSite(1))
    apply!(c, CNOT(), StaircaseRight(1))
    apply_with_prob!(c; outcomes=[
        (probability=0.5, gate=PauliX(), geometry=SingleSite(2))
    ])
end
```
"""
function Circuit(f::Function; L::Int, bc::Symbol, kwargs...)
    haskey(kwargs, :n_steps) && throw(ArgumentError(
        "Circuit no longer accepts n_steps. Pass it to simulate!(circuit, state; n_steps=...) instead."
    ))
    params = Dict{Symbol, Any}(kwargs)
    builder = CircuitBuilder(L, bc, NamedTuple[], params)
    f(builder)
    return Circuit(L = L, bc = bc, operations = builder.operations, params = params)
end
