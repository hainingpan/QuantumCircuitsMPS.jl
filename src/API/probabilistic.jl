"""
    apply_with_prob!(state, gate, geo, prob; rng=:ctrl, else_branch=nothing)

Conditionally apply a gate with probability `prob`, with optional else branch.

CRITICAL: Per Contract 4.4, this function ALWAYS draws a random number from the 
specified RNG stream BEFORE checking the probability. This ensures deterministic 
RNG advancement regardless of which branch is taken.

Arguments:
- state: SimulationState
- gate: AbstractGate to apply if rand < prob
- geo: AbstractGeometry where to apply the gate
- prob: Probability of application (0.0 to 1.0)
- rng: Symbol identifying the RNG stream in state.rng_registry (default :ctrl)
- else_branch: Optional tuple (gate, geo) to apply if rand >= prob

Examples:
    # Simple probabilistic application (original behavior)
    apply_with_prob!(state, Reset(), site, 0.3)
    
    # Either/or branching (new behavior)
    apply_with_prob!(state, Reset(), left, p_ctrl;
                    else_branch=(HaarRandom(), right))
"""
function apply_with_prob!(
    state::SimulationState,
    gate::AbstractGate,
    geo::AbstractGeometry,
    prob::Float64;
    rng::Symbol = :ctrl,
    else_branch::Union{Nothing, Tuple{AbstractGate, AbstractGeometry}} = nothing
)
    # Get the actual RNG from state's registry
    actual_rng = get_rng(state.rng_registry, rng)
    
    # CRITICAL: ALWAYS draw random number BEFORE checking prob
    # This ensures deterministic RNG advancement
    r = rand(actual_rng)
    
    # Conditionally apply based on drawn value
    if r < prob
        apply!(state, gate, geo)
    elseif else_branch !== nothing
        # Apply the else branch if provided
        else_gate, else_geo = else_branch
        apply!(state, else_gate, else_geo)
    end
    return nothing
end
