using Test
using QuantumCircuitsMPS

# Shared test utilities (plain definitions, no @testset) — provides the
# reference_select oracle to every file below.
include("testutils.jl")

@testset "QuantumCircuitsMPS Tests" begin
    include("geometry.jl")
    include("gates_api.jl")
    include("rng.jl")
    include("execute_protocol.jl")
    include("circuit_test.jl")
    include("recording.jl")
    include("entanglement_test.jl")
    include("qudit_test.jl")
    include("mipt_regressions.jl")
    include("event_log.jl")
    include("reference_rule.jl")
    include("unified_rule_engine.jl")
    include("feedback.jl")
    include("eager_probabilistic.jl")
    include("legacy_removal.jl")
    include("visualization.jl")
    if get(ENV, "EXTENDED_TESTS", "false") == "true"
        include("golden_compare.jl")
    end
    include("cross_cutting.jl")
    include("statevector/cross_validation.jl")
    include("statevector/integration.jl")
    include("gates/test_new_gates.jl")
    include("clifford/test_clifford.jl")
    include("clifford/cross_validation.jl")
    for dir in ("audit", "regression", "features", "quality")
        d = joinpath(@__DIR__, dir)
        isdir(d) || continue
        for f in sort(readdir(d))
            endswith(f, ".jl") && include(joinpath(d, f))
        end
    end
end
