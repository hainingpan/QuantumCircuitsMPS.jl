# CIPT (Control-Induced Phase Transition) - QuantumCircuitsMPS v2
# Physicists code as they speak: Gates + Geometry, no MPS details

using Pkg; Pkg.activate(dirname(@__DIR__))
using QuantumCircuitsMPS
using JSON

function run_dw_t(L::Int, p_ctrl::Float64, p_proj::Float64, seed_C::Int, seed_m::Int)
    # Staircases encapsulate directional movement
    left = StaircaseLeft(1)
    right = StaircaseRight(1)
    
    # Circuit step: physicist speaks "with prob p_ctrl, Reset+left; else HaarRandom+right"
    function circuit_step!(state, t)
        apply_with_prob!(state;
            rng = :ctrl,
            outcomes = [
                (probability=p_ctrl, gate=Reset(), geometry=left),
                (probability=1-p_ctrl, gate=HaarRandom(), geometry=right)
            ]
        )
    end
    
    # i1 for DomainWall depends on current pointer position
    # Note: left and right are synced by the either/or logic
    get_i1(state, t) = (current_position(left) % L) + 1
    
    # Run simulation using functional API
    results = simulate(
        L = L,
        bc = :periodic,
        init = ProductState(x0 = 1//2^L),
        rng = RNGRegistry(Val(:ct_compat), circuit=seed_C, measurement=seed_m),
        steps = 2 * L^2,
        circuit! = circuit_step!,
        observables = [:DW1 => DomainWall(order=1), :DW2 => DomainWall(order=2)],
        i1_fn = get_i1
    )
    
    Dict("L"=>L, "p_ctrl"=>p_ctrl, "p_proj"=>p_proj, "seed_C"=>seed_C,
         "seed_m"=>seed_m, "DW1"=>results[:DW1], "DW2"=>results[:DW2])
end

if abspath(PROGRAM_FILE) == @__FILE__
    result = run_dw_t(10, 0.5, 0.0, 42, 123)
    mkpath(joinpath(dirname(@__DIR__), "examples/output"))
    open(joinpath(dirname(@__DIR__), "examples/output/ct_model_L10_sC42_sm123.json"), "w") do f
        JSON.print(f, result, 4)
    end
    println("Done! DW1[1:5]: ", result["DW1"][1:5])
end
