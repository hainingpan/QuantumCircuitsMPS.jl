"""
    (m::Magnetization)(state::SimulationState{CliffordBackend}) -> Float64

Clifford (stabilizer-tableau) implementation of the `Magnetization` observable.

For a stabilizer state, ⟨Zᵢ⟩ is exactly +1, -1, or 0 (0 when site `i` is in a
genuine 50/50 superposition along Z, per the stabilizer formalism's Born
probabilities). Computed via `born_probability(state, i, 0) - born_probability(state, i, 1)`,
which gives ⟨Zᵢ⟩ directly (2*P(0) - 1). Magnetization is (1/L) Σᵢ ⟨Zᵢ⟩.

Only the `:Z` axis is currently supported for the Clifford backend;
`:X`/`:Y` throw an informative `ArgumentError` (they are allowed by the
`Magnetization` struct's own validation since it is shared with the MPS
backend, but no Clifford implementation exists for them yet).
"""
function (m::Magnetization)(state::SimulationState{CliffordBackend})
    m.axis == :Z ||
        throw(ArgumentError("Magnetization for the Clifford backend currently only supports :Z axis, got $(m.axis)"))
    L = state.L
    total = 0.0
    for site in 1:L
        total += born_probability(state, site, 0) - born_probability(state, site, 1)
    end
    return total / L
end
