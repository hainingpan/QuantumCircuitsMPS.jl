using Test
using QuantumCircuitsMPS

@testset "QuantumCircuitsMPS Tests" begin
    include("geometry_v01.jl")
    include("gates_v01.jl")
    include("rng_v01.jl")
    include("execute_protocol.jl")
    include("circuit_test.jl")
    include("recording_test.jl")
    include("entanglement_test.jl")
    include("qudit_test.jl")
    include("mipt_regressions.jl")
    include("event_log.jl")
    include("unified_rule_engine.jl")
    include("feedback.jl")
    include("eager_probabilistic.jl")
    include("recording_v01.jl")
    include("legacy_removal.jl")
    include("visualization_v01.jl")
    if get(ENV, "EXTENDED_TESTS", "false") == "true"
        include("golden_compare.jl")
    end
    include("cross_cutting_v01.jl")
    include("statevector/cross_validation.jl")
    include("statevector/integration.jl")
    include("gates/test_new_gates.jl")
end
