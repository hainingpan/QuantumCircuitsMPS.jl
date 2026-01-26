using QuantumCircuitsMPS

struct MonitoredCircuit <: AbstractCircuit
    L::Int
    p_ctrl::Float64
    p_proj::Float64
    T::Int
end

function QuantumCircuitsMPS.forward(c::MonitoredCircuit)
    MagnetizationZiAll()()
    for _ in 1:c.T
        state = current_state()
        if rand(state._rng_circuit) < c.p_ctrl
            control_step!(ZMeasure(; reset=true))
        else
            staircase_step!(HaarGate())
            projection_checks!(c.p_proj, ZMeasure(; reset=false))
        end
        MagnetizationZiAll()()
    end
    return
end

if abspath(PROGRAM_FILE) == @__FILE__
    results = simulate(
        MonitoredCircuit(10, 0.5, 0.0, 100),
        seed_circuit=42,
        seed_meas=123,
        x0=1 // big(2)^10,
    )
    println("Recorded $(length(results.observables[:Zi])) Zi snapshots")
end
