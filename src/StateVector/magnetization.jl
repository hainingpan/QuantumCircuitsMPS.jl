"""
    (m::Magnetization)(state::SimulationState{StateVectorBackend}) -> Float64

State-vector implementation of the `Magnetization` observable.

Computes Mz = (1/L) Σᵢ ⟨Zᵢ⟩ via direct basis-state summation over the dense
state vector `state.backend.ψ`. For each physical site `j` (1-indexed, site 1
is the most-significant digit of the basis index), ⟨Zⱼ⟩ = P(bit_j=0) -
P(bit_j=1) = 2*P(bit_j=0) - 1.

Only the `:Z` axis is currently supported for the state-vector backend;
`:X`/`:Y` throw an informative `ArgumentError` (they are allowed by the
`Magnetization` struct's own validation since it is shared with the MPS
backend, but no state-vector implementation exists for them yet).
"""
function (m::Magnetization)(state::SimulationState{StateVectorBackend})
    m.axis == :Z ||
        throw(ArgumentError("Magnetization for the state-vector backend currently only supports :Z axis, got $(m.axis)"))
    L = state.L
    d = state.local_dim
    ψ = state.backend.ψ
    total = 0.0
    for site in 1:L
        stride = d^(L - site)
        p0 = 0.0
        for n0 in 0:(length(ψ) - 1)
            digit = _sv_digit(n0, stride, d)
            if digit == 0
                p0 += abs2(ψ[n0 + 1])
            end
        end
        total += (2 * p0 - 1)   # <Z> = P(0) - P(1) = 2*P(0) - 1
    end
    return total / L
end
