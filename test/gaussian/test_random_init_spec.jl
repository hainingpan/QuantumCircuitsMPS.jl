using Test
using QuantumCircuitsMPS

@testset "RandomGaussianState spec type" begin
    @testset "type exists and is AbstractInitialState" begin
        init = RandomGaussianState()
        @test init isa QuantumCircuitsMPS.AbstractInitialState
        @test RandomGaussianState <: QuantumCircuitsMPS.AbstractInitialState
    end

    @testset "generic rejection on MPS backend" begin
        state = SimulationState(L = 4, bc = :open,
            rng = RNGRegistry(gates_spacetime = 1, gates_realization = 11,
                born_measurement = 21, state_init = 31))
        err = nothing
        try
            initialize!(state, RandomGaussianState())
        catch e
            err = e
        end
        @test err isa ArgumentError
        @test occursin("RandomGaussianState is only supported on backend=:gaussian", err.msg)
    end
end
