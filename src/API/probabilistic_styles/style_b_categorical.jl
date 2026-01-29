# This file is meant to be included in the QuantumCircuitsMPS module context
# where AbstractGate, AbstractGeometry, and SimulationState are already defined.
# It should NOT be loaded standalone.

"""
    apply_categorical!(state, outcomes; rng=:ctrl)

Probabilistically execute one of N outcomes based on their probabilities.
Outcomes are provided as a Vector of (probability, gate, geometry) tuples.

CRITICAL: Per Contract 4.4, this function ALWAYS draws ONE random number from the 
specified RNG stream BEFORE checking probabilities. This ensures deterministic 
RNG advancement regardless of which branch is taken.

Arguments:
- state: SimulationState
- outcomes: Vector of Tuple{Real, AbstractGate, AbstractGeometry}
- rng: Symbol identifying the RNG stream in state.rng_registry (default :ctrl)

Example (binary):
    apply_categorical!(state, [
        (0.3, Reset(), left),
        (0.7, HaarRandom(), right)
    ])

Example (3-way):
    apply_categorical!(state, [
        (0.25, PauliX(), site),
        (0.25, PauliY(), site),
        (0.50, Identity(), site)
    ])
"""
function apply_categorical!(
    state::SimulationState, 
    outcomes::Vector{<:Tuple{Real, AbstractGate, AbstractGeometry}};
    rng::Symbol = :ctrl
)
    # Validate probabilities sum to ~1
    probs = [o[1] for o in outcomes]
    @assert abs(sum(probs) - 1.0) < 1e-10 "Probabilities must sum to 1, got \$(sum(probs))"
    
    # CRITICAL: Draw random number BEFORE checking
    actual_rng = get_rng(state.rng_registry, rng)
    r = rand(actual_rng)
    
    # Find which outcome to execute
    cumulative = 0.0
    for (prob, gate, geo) in outcomes
        cumulative += prob
        if r < cumulative
            apply!(state, gate, geo)
            return nothing
        end
    end
    
    # Edge case: r exactly equals 1.0 (extremely rare)
    _, gate, geo = last(outcomes)
    apply!(state, gate, geo)
    return nothing
end
