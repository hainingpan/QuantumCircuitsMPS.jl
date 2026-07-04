using Random

"""
    RNGRegistry

Container for named RNG streams for reproducible randomness.

Streams:
- :gates_spacetime - decisions about whether to apply control operations (p_ctrl)
- :gates_realization - Haar random unitary generation
- :born_measurement - Born rule measurement outcomes
- :state_init - random initial state generation (optional)

# Fixed-draw contract (v0.1)
The `:gates_spacetime` stream has a FIXED, data-independent consumption: each
stochastic circuit operation draws exactly K scalar coins per step (K = its
outcomes' element count), regardless of which outcomes are selected. All coin
draws are SCALAR (`rand(rng)`, never `rand(rng, K)` — array fast paths may
diverge from K scalar draws). See [`expected_draws`](@ref) for the invariant
helper and [`with_guarded_stream`](@ref) for the feedback-time guard.

# ct_compat exemption
`RNGRegistry(Val(:ct_compat); ...)` aliases `:gates_spacetime` ≡
`:gates_realization` (the SAME RNG object, matching CT.jl's single-RNG
design). Under aliasing, Haar-realization draws interleave with coin draws,
so the fixed-draw invariant CANNOT hold — this is faithful to CT.jl, not a
bug. Detect aliased registries with [`is_aliased`](@ref); `expected_draws`
draw-count checks and the `with_guarded_stream` sentinel guard must be (and
are) bypassed for them.
"""
# TODO: The stream name :gates_spacetime is currently hardcoded in the engine
# (see src/API/probabilistic.jl and src/Circuit/execute.jl). If a future protocol
# needs multiple independent spacetime streams, generalize by storing the stream
# name in the operation tuple and passing it to with_guarded_stream.
struct RNGRegistry
    streams::Dict{Symbol, AbstractRNG}
end

"""
    RNGRegistry(; gates_spacetime, gates_realization, born_measurement, state_init=0)

Create RNG registry with seeds for each stream.
First 3 arguments (gates_spacetime, gates_realization, born_measurement) are REQUIRED.
"""
function RNGRegistry(;
    gates_spacetime::Int,
    gates_realization::Int,
    born_measurement::Int,
    state_init::Int = 0
)
    streams = Dict{Symbol, AbstractRNG}(
        :gates_spacetime => MersenneTwister(gates_spacetime),
        :gates_realization => MersenneTwister(gates_realization),
        :born_measurement => MersenneTwister(born_measurement),
        :state_init => MersenneTwister(state_init)
    )
    return RNGRegistry(streams)
end

"""
    RNGRegistry(::Val{:ct_compat}; circuit, measurement)

Create CT.jl-compatible RNG registry where :gates_spacetime, :gates_realization share the SAME RNG.
This matches CT.jl's interleaved consumption pattern for verification.

Used ONLY for Task 8 CT.jl verification with p_proj=0.

!!! note "Invariant exemption"
    Because the two gate streams are the SAME object, the fixed-draw
    invariant on `:gates_spacetime` does not hold for this registry
    (see `RNGRegistry` docstring). `is_aliased(registry)` returns `true`
    here; draw-count tests and `with_guarded_stream` detect this and bypass.
"""
function RNGRegistry(::Val{:ct_compat}; circuit::Int, measurement::Int)
    # Shared RNG for circuit operations (matches CT.jl's rng_C)
    shared_circuit_rng = MersenneTwister(circuit)
    
    streams = Dict{Symbol, AbstractRNG}(
        :gates_spacetime => shared_circuit_rng,      # ALIAS - same RNG object
        :gates_realization => shared_circuit_rng,     # ALIAS
        :born_measurement => MersenneTwister(measurement),
        :state_init => MersenneTwister(0)
    )
    return RNGRegistry(streams)
end

"""
    get_rng(registry::RNGRegistry, stream::Symbol) -> AbstractRNG

Get the raw RNG object for a stream. Low-level API.
"""
function get_rng(registry::RNGRegistry, stream::Symbol)
    haskey(registry.streams, stream) || throw(ArgumentError("Unknown RNG stream: $stream"))
    return registry.streams[stream]
end

"""
    rand(registry::RNGRegistry, stream::Symbol) -> Float64

Draw a random Float64 from the specified stream. Mid-level API.
"""
function Base.rand(registry::RNGRegistry, stream::Symbol)
    return rand(get_rng(registry, stream))
end

"""
    randn(registry::RNGRegistry, stream::Symbol) -> Float64

Draw a random normal Float64 from the specified stream.
"""
function Base.randn(registry::RNGRegistry, stream::Symbol)
    return randn(get_rng(registry, stream))
end

"""
    randn(registry::RNGRegistry, stream::Symbol, dims...) -> Array{Float64}

Draw random normal array from the specified stream. For Haar random matrices.
"""
function Base.randn(registry::RNGRegistry, stream::Symbol, dims...)
    return randn(get_rng(registry, stream), dims...)
end

# === Package-owned draw (replaces pirated Base.rand(state, stream)) ===

# The former `Base.rand(state::Any, stream::Symbol)` method was TYPE PIRACY
# (extending a Base function on a signature the package does not own). It is
# replaced by the package-owned `draw`. A second `draw` method for
# `SimulationState` lives in `State/State.jl` (the type is defined after this
# file is included).

"""
    draw(registry::RNGRegistry, stream::Symbol) -> Float64
    draw(state::SimulationState, stream::Symbol) -> Float64

Draw ONE scalar uniform `Float64` from the named RNG stream. This is the
canonical way to consume a stream (replaces the removed, type-pirating
`rand(state, stream)` extension; behavior is identical).

All engine coin draws are scalar — see the SCALAR-DRAW CONTRACT note in the
`RNGRegistry` docstring.

Example:
    if draw(state, :gates_spacetime) < p_ctrl
        # control branch
    end
"""
function draw(registry::RNGRegistry, stream::Symbol)
    # SCALAR-DRAW CONTRACT: exactly one scalar rand() per call; never rand(rng, K)
    return rand(get_rng(registry, stream))
end

# === Sentinel guard (feedback-time protection of coin streams) ===

"""
    SentinelRNG <: Random.AbstractRNG

Poison-pill RNG installed by [`with_guarded_stream`](@ref) in place of a
guarded stream. Any attempt to draw from it throws an `ErrorException`
explaining that the stream is forbidden in the current context (e.g.
`:gates_spacetime` during measurement feedback, whose draw count must stay
data-independent — see the fixed-draw contract in `RNGRegistry`).
"""
struct SentinelRNG <: Random.AbstractRNG
    stream::Symbol
end

function _sentinel_error(rng::SentinelRNG)
    throw(ErrorException(
        "$(rng.stream) stream is forbidden during feedback: the " *
        ":gates_spacetime coin stream has a fixed, data-independent draw " *
        "count, and consuming it inside feedback would desynchronize " *
        "trajectories. Draw feedback randomness from :gates_realization " *
        "instead (e.g. get_rng(registry, :gates_realization))."))
end

# Entry-level Random API overrides so ANY draw attempt errors with the
# prescriptive message above (instead of an obscure MethodError deep in the
# sampler machinery). Method signatures mirror Random's entry points to avoid
# dispatch ambiguities.
Random.rand(rng::SentinelRNG) = _sentinel_error(rng)
Random.rand(rng::SentinelRNG, X) = _sentinel_error(rng)
Random.rand(rng::SentinelRNG, ::Type{T}) where {T} = _sentinel_error(rng)
Random.rand(rng::SentinelRNG, d::Integer, dims::Integer...) = _sentinel_error(rng)
Random.rand(rng::SentinelRNG, ::Type{T}, d::Integer, dims::Integer...) where {T} = _sentinel_error(rng)
Random.randn(rng::SentinelRNG) = _sentinel_error(rng)
Random.randn(rng::SentinelRNG, dims::Integer...) = _sentinel_error(rng)
Random.randn(rng::SentinelRNG, ::Type{T}, dims::Integer...) where {T} = _sentinel_error(rng)

"""
    is_aliased(registry::RNGRegistry) -> Bool

`true` when the `:gates_spacetime` and `:gates_realization` streams are the
SAME RNG object (`===`), as in `RNGRegistry(Val(:ct_compat); ...)`. Aliased
registries are exempt from the fixed-draw invariant and from the
[`with_guarded_stream`](@ref) sentinel guard (guarding one alias would also
block the other; interleaved consumption is CT.jl-faithful by design).
"""
function is_aliased(registry::RNGRegistry)
    haskey(registry.streams, :gates_spacetime) || return false
    haskey(registry.streams, :gates_realization) || return false
    return registry.streams[:gates_spacetime] === registry.streams[:gates_realization]
end

"""
    with_guarded_stream(f, registry::RNGRegistry, stream::Symbol)

Run `f()` with `registry`'s `stream` temporarily replaced by a
[`SentinelRNG`](@ref): any draw from the guarded stream inside `f` throws an
`ErrorException` ("... forbidden ..."), while all other streams remain fully
usable. The original stream object is ALWAYS restored (try/finally), even if
`f` throws. Returns `f()`'s value.

Used by the feedback system to guarantee that measurement feedback cannot
consume `:gates_spacetime` coins (fixed-draw contract).

!!! note "ct_compat exemption"
    For aliased registries (`is_aliased(registry) == true`, i.e.
    `RNGRegistry(Val(:ct_compat); ...)`), the guard is a documented NO-OP:
    `:gates_spacetime` and `:gates_realization` are the same RNG object, so
    installing a sentinel would also block legitimate realization draws.
    CT.jl-compat interleaves the two by design.
"""
function with_guarded_stream(f::Function, registry::RNGRegistry, stream::Symbol)
    haskey(registry.streams, stream) || throw(ArgumentError("Unknown RNG stream: $stream"))
    if is_aliased(registry)
        # ct_compat exemption (see docstring): do not install the sentinel.
        return f()
    end
    original = registry.streams[stream]
    registry.streams[stream] = SentinelRNG(stream)
    try
        return f()
    finally
        registry.streams[stream] = original
    end
end
