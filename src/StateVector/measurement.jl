# === State-Vector Born Probability ===
# More-specific dispatch method for SimulationState{StateVectorBackend}.
# The existing _measure_single_site! (src/Core/apply.jl) and BornProbability
# observable (src/Observables/born.jl) both call the unparameterized
# born_probability(state, site, outcome) — Julia's dispatch automatically
# routes to this method for SV states.

@doc raw"""
    born_probability(state::SimulationState{StateVectorBackend}, physical_site::Int, outcome::Int) -> Float64

Compute Born probability ``P(\text{outcome} \mid \psi)`` at `physical_site` for the state-vector backend.

For a state vector `ψ` of length `d^L`, sums `|ψ_n|²` over all basis integers `n`
(0-indexed, 0 to `d^L - 1`) whose base-`d` digit at position `physical_site` equals
`outcome`. Site 1 is MSB (slowest index).

Digit extraction: for 0-indexed basis integer `n`, physical site `s` (1-indexed, site 1 = MSB),
and local dimension `d`: `digit = (n ÷ d^(L-s)) % d` (see [`_sv_digit`](@ref)). The
amplitudes with that digit equal to `outcome` form runs of `stride = d^(L-s)`
consecutive entries, one per block of `stride*d`, so the loop walks those runs
directly (no per-amplitude division) in ascending index order — the same
summation order as a digit test over all `n`, hence the same `Float64` result.
This is also the ``\lVert P\psi\rVert^2`` of the `Projection` postselection
guard (`_sv_projected_norm2`), so `Measure`/`Reset` call it twice per site.
"""
function born_probability(state::SimulationState{StateVectorBackend}, physical_site::Int, outcome::Int)
    ψ = state.backend.ψ
    L = state.L
    d = state.local_dim
    1 <= physical_site <= L || throw(ArgumentError(
        "born_probability: physical_site must be in 1:$L, got $physical_site"))
    0 <= outcome < d || throw(ArgumentError(
        "born_probability: outcome must be a level index in 0:$(d - 1) " *
        "(local_dim=$d), got $outcome"))
    stride = d^(L - physical_site)
    block = stride * d
    total = 0.0
    @inbounds for j in 0:block:(length(ψ) - 1)
        base = j + outcome * stride
        for i in 1:stride
            total += abs2(ψ[base + i])
        end
    end
    return total
end
