"""
    apply_with_prob!(state, gate, geo, prob; rng=:ctrl)

Conditionally apply a gate with probability `prob`.

CRITICAL: Per Contract 4.4, this function ALWAYS draws a random number from the 
specified RNG stream BEFORE checking the probability. This ensures deterministic 
RNG advancement regardless of whether the gate is applied.

Arguments:
- state: SimulationState
- gate: AbstractGate to apply
- geo: AbstractGeometry where to apply
- prob: Probability of application (0.0 to 1.0)
- rng: Symbol identifying the RNG stream in state.rng_registry (default :ctrl)
"""
function apply_with_prob!(
    state::SimulationState,
    gate::AbstractGate,
    geo::AbstractGeometry,
    prob::Float64;
    rng::Symbol = :ctrl
)
    # Get the actual RNG from state's registry
    actual_rng = get_rng(state.rng_registry, rng)
    
    # CRITICAL: ALWAYS draw random number BEFORE checking prob
    # This ensures deterministic RNG advancement
    r = rand(actual_rng)
    
    # Conditionally apply based on drawn value
    if r < prob
        apply!(state, gate, geo)
    end
    return nothing
end
