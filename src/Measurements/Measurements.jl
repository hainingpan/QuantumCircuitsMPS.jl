module Measurements

using ITensors
using Random

using ..Core: AbstractMeasurement, current_state
using ..Gates: apply_op!
using ITensorMPS: expect, normalize!, truncate!

export ZMeasurement,
       ZMeasure,
       measure!,
       control_step!,
       projection_checks!

struct ZMeasurement <: AbstractMeasurement
    reset::Bool
end

ZMeasure(; reset::Bool=true) = ZMeasurement(reset)

function _projector(state, n::Int, i::Int)
    ram = state._phy_ram[i]
    proj_op = emptyITensor(state._qubit_sites[ram], state._qubit_sites[ram]')
    idx = n + 1
    proj_op[idx, idx] = 1 + 0im
    return proj_op
end

function _inner_prob(state, n::Int, i::Int)
    proj_op = array(_projector(state, n, i))
    return only(expect(state._mps, proj_op, sites=state._phy_ram[i]))
end

function _project!(state, n::Int, i::Int)
    proj_op = _projector(state, n, i)
    apply_op!(state._mps, proj_op, state._cutoff, state._maxdim)
    normalize!(state._mps)
    truncate!(state._mps, cutoff=state._cutoff)
    return
end

function _apply_x!(state, i::Int)
    ram = state._phy_ram[i]
    X_op = ITensor([0 1 + 0im; 1 + 0im 0], state._qubit_sites[ram], state._qubit_sites[ram]')
    apply_op!(state._mps, X_op, state._cutoff, state._maxdim)
    return
end

function measure!(meas::ZMeasurement, i::Int)
    state = current_state()
    p0 = _inner_prob(state, 0, i)
    n = rand(state._rng_meas) < p0 ? 0 : 1
    _project!(state, n, i)
    if meas.reset && n == 1
        _apply_x!(state, i)
    end
    return n
end

function control_step!(meas::ZMeasurement)
    state = current_state()
    i = state.current_site
    measure!(meas, i)
    state.current_site = mod(i - 2, state.L) + 1
    return
end

function projection_checks!(p_proj::Float64, meas::AbstractMeasurement)
    state = current_state()
    i = state.current_site
    for offset in (-1, 0)
        pos = mod(i + offset - 1, state.L) + 1
        if rand(state._rng_circuit) < p_proj
            measure!(meas, pos)
        end
    end
    return
end

end
