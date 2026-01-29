# This file is meant to be included in the QuantumCircuitsMPS module context
# where AbstractGate, AbstractGeometry, and SimulationState are already defined.
# It should NOT be loaded standalone.

"""
    apply_stochastic!(state, pairs...; rng=:ctrl)

Probabilistically execute one of N actions based on their probabilities.

CRITICAL: Per Contract 4.4, this function ALWAYS draws ONE random number from the 
specified RNG stream BEFORE checking probabilities. This ensures deterministic 
RNG advancement regardless of which branch is taken.

Arguments:
- state: SimulationState
- pairs...: Pairs of probability => Action (e.g., 0.3 => action1, 0.7 => action2)
- rng: Symbol identifying the RNG stream in state.rng_registry (default :ctrl)

Example (binary):
    apply_stochastic!(state, 
        p_ctrl => Action(Reset(), left),
        (1-p_ctrl) => Action(HaarRandom(), right)
    )

Example (3-way):
    apply_stochastic!(state,
        0.25 => Action(PauliX(), site),
        0.25 => Action(PauliY(), site),
        0.50 => Action(Identity(), site)
    )
"""
function apply_stochastic!(state::SimulationState, pairs::Pair{<:Real, Action}...; rng::Symbol = :ctrl)
    # Validate probabilities sum to ~1
    probs = [p.first for p in pairs]
    @assert abs(sum(probs) - 1.0) < 1e-10 "Probabilities must sum to 1, got $(sum(probs))"
    
    # CRITICAL: Draw random number BEFORE checking
    actual_rng = get_rng(state.rng_registry, rng)
    r = rand(actual_rng)
    
    # Find which action to execute
    cumulative = 0.0
    for (prob, action) in pairs
        cumulative += prob
        if r < cumulative
            apply!(state, action)
            return nothing
        end
    end
    
    # Edge case: r exactly equals 1.0 (extremely rare)
    apply!(state, last(pairs).second)
    return nothing
end
