# Probabilistic Branching API
# ==========================
# 
# This is the finalized probabilistic API using fully named parameters (Style C).
# Selected for: self-documenting code, no position memorization, idiomatic Julia.
#
# For historical context on alternative styles that were considered, see:
# - examples/ct_model_styles.jl (comparison of 4 styles)
# - src/_deprecated/probabilistic_styles/ (alternative implementations)

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
