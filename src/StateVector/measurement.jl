# === State-Vector Born Probability ===
# More-specific dispatch method for SimulationState{StateVectorBackend}.
# The existing _measure_single_site! (src/Core/apply.jl) and BornProbability
# observable (src/Observables/born.jl) both call the unparameterized
# born_probability(state, site, outcome) — Julia's dispatch automatically
# routes to this method for SV states.

"""
    born_probability(state::SimulationState{StateVectorBackend}, physical_site::Int, outcome::Int) -> Float64

Compute Born probability P(outcome | ψ) at `physical_site` for the state-vector backend.

For a state vector `ψ` of length `d^L`, sums `|ψ_n|²` over all basis integers `n`
(0-indexed, 0 to `d^L - 1`) whose base-`d` digit at position `physical_site` equals
`outcome`. Site 1 is MSB (slowest index).

Digit extraction: for 0-indexed basis integer `n`, physical site `s` (1-indexed, site 1 = MSB),
and local dimension `d`: `digit = (n ÷ d^(L-s)) % d` (see [`_sv_digit`](@ref); the
loop-invariant stride `d^(L-s)` is hoisted out of the loop).
"""
function born_probability(state::SimulationState{StateVectorBackend}, physical_site::Int, outcome::Int)
    ψ = state.backend.ψ
    L = state.L
    d = state.local_dim
    stride = d^(L - physical_site)
    total = 0.0
    for n0 in 0:(length(ψ) - 1)
        digit = _sv_digit(n0, stride, d)
        if digit == outcome
            total += abs2(ψ[n0 + 1])
        end
    end
    return total
end
