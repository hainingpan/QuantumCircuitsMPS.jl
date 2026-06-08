using Random

"""
    RNGRegistry

Container for named RNG streams for reproducible randomness.

Streams:
- :gates_spacetime - decisions about whether to apply control operations (p_ctrl)
- :gates_realization - Haar random unitary generation
- :born_measurement - Born rule measurement outcomes
- :state_init - random initial state generation (optional)
"""
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

# === SimulationState Extensions ===

# Note: SimulationState is defined in State/State.jl, which is included after this file.
# We use Any for the state argument to avoid circular dependency during inclusion.

"""
    rand(state, stream::Symbol) -> Float64

Draw a random number from the specified RNG stream.
Convenience wrapper that hides rng_registry internals.

Example:
    if rand(state, :gates_spacetime) < p_ctrl
        # control branch
    end
"""
function Base.rand(state::Any, stream::Symbol)
    # Check if it's a SimulationState without requiring the type at compile time
    if nameof(typeof(state)) == :SimulationState
        isnothing(state.rng_registry) && error("SimulationState has no RNG registry attached.")
        return rand(state.rng_registry, stream)
    end
    # Fallback for other types if necessary, or just throw error
    throw(MethodError(rand, (state, stream)))
end
