#=
Style C: Fully Named Parameters
===============================

Philosophy: Completely self-documenting with named parameters everywhere

Pros:
- Completely self-documenting - no memorization of argument order
- Named fields make intent crystal clear
- Compile-time field name checking

Cons:
- More verbose, especially for simple binary branching
- Requires more typing for common cases

When to Use:
Choose this if code readability and self-documentation are your top priority

See also: examples/ct_model_styles.jl for side-by-side comparison
=#

# Style C: Fully Named Parameters
# Part of the Probabilistic API (Contract 4.4)

"""
    apply_branch!(state; rng=:ctrl, outcomes)

Execute one action from outcomes with fully named parameters.

Each outcome is a NamedTuple with fields:
- probability: Float64 (required)
- gate: AbstractGate (required)
- geometry: AbstractGeometry (required)

Example:
    apply_branch!(state;
        rng = :ctrl,
        outcomes = [
            (probability=p_ctrl, gate=Reset(), geometry=left),
            (probability=1-p_ctrl, gate=HaarRandom(), geometry=right)
        ]
    )

Example (3-way):
    apply_branch!(state;
        outcomes = [
            (probability=0.25, gate=PauliX(), geometry=site),
            (probability=0.25, gate=PauliY(), geometry=site),
            (probability=0.50, gate=Identity(), geometry=site)
        ]
    )
"""
function apply_branch!(
    state::SimulationState;
    rng::Symbol = :ctrl,
    outcomes::Vector{<:NamedTuple{(:probability, :gate, :geometry)}}
)
    probs = [o.probability for o in outcomes]
    @assert abs(sum(probs) - 1.0) < 1e-10 "Probabilities must sum to 1"
    
    # CRITICAL: Draw BEFORE checking
    actual_rng = get_rng(state.rng_registry, rng)
    r = rand(actual_rng)
    
    cumulative = 0.0
    for outcome in outcomes
        cumulative += outcome.probability
        if r < cumulative
            apply!(state, outcome.gate, outcome.geometry)
            return nothing
        end
    end
    
    last_outcome = last(outcomes)
    apply!(state, last_outcome.gate, last_outcome.geometry)
    return nothing
end
