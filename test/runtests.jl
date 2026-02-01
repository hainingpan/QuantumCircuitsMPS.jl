using Test
using QuantumCircuitsMPS

@testset "QuantumCircuitsMPS Tests" begin
    include("circuit_test.jl")
    include("recording_test.jl")
    include("entanglement_test.jl")
    include("qudit_test.jl")
end
