using ITensors
using ITensorMPS

"""
Abstract base type for observable specifications.
"""
abstract type AbstractObservable end

# Include implementations
include("born.jl")
include("domain_wall.jl")

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
    record!(state::SimulationState; i1::Union{Int,Nothing}=nothing)

Compute all tracked observables and append values to state.observables.
The i1 parameter is required for DomainWall observables.
"""
function record!(state; i1::Union{Int,Nothing}=nothing)
    for (name, obs) in state.observable_specs
        if obs isa DomainWall
            i1 === nothing && throw(ArgumentError(
                "DomainWall requires i1 parameter (the CT sampling site). " *
                "Use: record!(state; i1=sampling_site)"
            ))
            value = obs(state, i1)
        else
            value = obs(state)
        end
        push!(state.observables[name], value)
    end
    return nothing
end
