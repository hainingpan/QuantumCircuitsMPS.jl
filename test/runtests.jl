using Test
using QuantumCircuitsMPS

@testset "QuantumCircuitsMPS Tests" begin
    include("circuit_test.jl")
    include("recording_test.jl")
end
