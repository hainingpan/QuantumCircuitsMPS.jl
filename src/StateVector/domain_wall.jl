"""
    domain_wall(state::SimulationState{StateVectorBackend}, i1::Int, order::Int) -> Float64

State-vector implementation of the `domain_wall` function (mirrors the
outer-loop structure of the existing MPS `domain_wall` in
`src/Observables/domain_wall.jl` exactly: cyclic scan from `i1`, weight
`(L-j+1)^order`). Only the innermost probability computation differs: instead
of an MPO/MPS contraction, it is a direct basis-state sum over the dense
state vector `state.backend.ψ`.
"""
function domain_wall(state::SimulationState{StateVectorBackend}, i1::Int, order::Int)
    L = state.L

    # Physical site list starting from i1, wrapping around
    phy_list = [mod(i1 + j - 2, L) + 1 for j in 1:L]

    dw_value = 0.0

    for j in 1:L
        weight = Float64((L - j + 1)^order)

        sites_zero = phy_list[1:j-1]
        site_one = phy_list[j]

        prob = _projector_product_expectation_sv(state, sites_zero, site_one)
        dw_value += weight * prob
    end

    return dw_value
end

"""
    _projector_product_expectation_sv(state::SimulationState{StateVectorBackend}, sites_zero::Vector{Int}, site_one::Int) -> Float64

Compute ⟨ψ| (∏_k P0_k) P1 |ψ⟩ for the state-vector backend via direct
basis-state summation: sum |ψ_n|² over all basis states where every site in
`sites_zero` has digit 0 and `site_one` has digit 1.
"""
function _projector_product_expectation_sv(state::SimulationState{StateVectorBackend}, sites_zero::Vector{Int}, site_one::Int)
    L = state.L
    d = state.local_dim
    ψ = state.backend.ψ
    total = 0.0
    for n0 in 0:(length(ψ) - 1)
        ok = all(((n0 ÷ d^(L - s)) % d) == 0 for s in sites_zero) && ((n0 ÷ d^(L - site_one)) % d) == 1
        if ok
            total += abs2(ψ[n0 + 1])
        end
    end
    return total
end
