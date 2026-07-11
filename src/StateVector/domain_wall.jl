"""
    domain_wall(state::SimulationState{StateVectorBackend}, i1::Int, order::Int) -> Float64

State-vector implementation of the `domain_wall` function (mirrors the
formula of the existing MPS `domain_wall` in `src/Observables/domain_wall.jl`
exactly: cyclic scan from `i1`, weight `(L-j+1)^order`, term j is
⟨ψ| (∏_{k<j} P0_k) P1_j |ψ⟩ over the cyclic site list).

Implementation: a single O(d^L) pass instead of L independent O(d^L) scans
(one per term j). The L projector-product conditions are mutually exclusive
in the computational basis: basis state `n` satisfies the term-j condition
iff `j` is the FIRST position in the cyclic site list whose digit is nonzero
AND that digit equals 1. So one sweep over the amplitudes finds, for each
basis state, its unique contributing term (if any) by scanning for the first
nonzero digit (amortized O(1) per basis state — a depth-k scan occurs for a
d^-k fraction of basis indices). Each per-term accumulator receives exactly
the same addends in the same ascending basis-index order as the former
per-term scans, and the final weighted sum runs in the same j order, so the
result is bitwise identical to the O(L·d^L) implementation.
"""
function domain_wall(state::SimulationState{StateVectorBackend}, i1::Int, order::Int)
    L = state.L
    d = state.local_dim
    ψ = state.backend.ψ

    # Physical site list starting from i1, wrapping around
    phy_list = [mod(i1 + j - 2, L) + 1 for j in 1:L]
    strides = [d^(L - s) for s in phy_list]

    # probs[j] = ⟨ψ| (∏_{k<j} P0_{phy_list[k]}) P1_{phy_list[j]} |ψ⟩
    probs = zeros(Float64, L)
    @inbounds for n0 in 0:(length(ψ) - 1)
        for j in 1:L
            digit = _sv_digit(n0, strides[j], d)
            if digit != 0
                if digit == 1
                    probs[j] += abs2(ψ[n0 + 1])
                end
                break   # first nonzero digit found — no other term can match
            end
        end
    end

    dw_value = 0.0
    for j in 1:L
        weight = Float64((L - j + 1)^order)
        dw_value += weight * probs[j]
    end

    return dw_value
end
