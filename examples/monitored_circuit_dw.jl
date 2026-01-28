using QuantumCircuitsMPS

struct MonitoredCircuitDW <: AbstractCircuit
    L::Int
    p_ctrl::Float64
    p_proj::Float64
    T::Int
end

function run_dw_t(L::Int, p_ctrl::Float64, p_proj::Float64, seed_circuit::Int, seed_meas::Int)
    circuit = MonitoredCircuitDW(L, p_ctrl, p_proj, 2 * L^2)
    state = simulate(circuit, seed_circuit=seed_circuit, seed_meas=seed_meas, x0=1 // big(2)^L)
    return state
end

function QuantumCircuitsMPS.forward(c::MonitoredCircuitDW)
    state = current_state()
    dw_list = zeros(c.T + 1, 2)
    dw_list[1, 1] = domain_wall(1; order=1)
    dw_list[1, 2] = domain_wall(1; order=2)

    for t in 1:c.T
        if rand(state._rng_circuit) < c.p_ctrl
            control_step!(ZMeasure(; reset=true))
        else
            staircase_step!(HaarGate())
            projection_checks!(c.p_proj, ZMeasure(; reset=false))
        end

        i1 = mod(state.current_site, state.L) + 1
        dw_list[t + 1, 1] = domain_wall(i1; order=1)
        dw_list[t + 1, 2] = domain_wall(i1; order=2)
    end

    state.observables[:DW] = [dw_list]
    return
end

if abspath(PROGRAM_FILE) == @__FILE__
    results = run_dw_t(10, 0.5, 0.0, 0, 0)
    dw = results.observables[:DW][1]
    println("Recorded $(size(dw, 1)) DW snapshots")
end
