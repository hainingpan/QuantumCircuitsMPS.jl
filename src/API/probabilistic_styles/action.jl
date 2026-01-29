# This file is meant to be included in the QuantumCircuitsMPS module context
# where AbstractGate, AbstractGeometry, and SimulationState are already defined.
# It should NOT be loaded standalone.

"""
    Action(gate::AbstractGate, geometry::AbstractGeometry)

Combines a gate with its target geometry into a single "action" concept.
This is the atomic unit for probabilistic branching and circuit construction.

# Examples
```julia
# Reset a site at the current position of a left-moving staircase
reset_left = Action(Reset(), StaircaseLeft(10))

# Apply a Haar random unitary to the current position of a right-moving staircase
haar_right = Action(HaarRandom(), StaircaseRight(10))
```
"""
struct Action
    gate::AbstractGate
    geometry::AbstractGeometry
end

"""
    apply!(state::SimulationState, action::Action)

Convenience method to execute an `Action` on a `SimulationState`.
Delegates to `apply!(state, action.gate, action.geometry)`.
"""
function apply!(state::SimulationState, action::Action)
    apply!(state, action.gate, action.geometry)
end
