# test/gaussian/test_construction.jl
# Unit tests for GaussianBackend construction wiring: struct type,
# backend=:gaussian branch validation (local_dim, site_type rejection),
# and identity phy_ram/ram_phy mapping.
#
# NOTE: not yet wired into test/runtests.jl — run directly:
#   julia --project=. -e 'include("test/gaussian/test_construction.jl")'

using Test
using QuantumCircuitsMPS

@testset "Gaussian Backend Construction" begin

    @testset "Construction succeeds, correct backend type" begin
        @testset "L=$L" for L in [2, 4, 8]
            state = SimulationState(L = L, bc = :open, backend = :gaussian,
                rng = RNGRegistry(gates_spacetime = 1, gates_realization = 11,
                    born_measurement = 21, state_init = 31))
            @test state.backend isa GaussianBackend
            @test state.phy_ram == collect(1:L)
            @test state.ram_phy == collect(1:L)
        end
    end

    @testset "Rejects local_dim != 2" begin
        err = nothing
        try
            SimulationState(L = 4, bc = :open, backend = :gaussian, local_dim = 3,
                rng = RNGRegistry(gates_spacetime = 1, gates_realization = 11,
                    born_measurement = 21, state_init = 31))
        catch e
            err = e
        end
        @test err isa ArgumentError
        @test occursin("local_dim", err.msg)

        @test_throws ArgumentError SimulationState(L = 4, bc = :open, backend = :gaussian,
            local_dim = 3,
            rng = RNGRegistry(gates_spacetime = 1, gates_realization = 11,
                born_measurement = 21, state_init = 31))
    end

    @testset "Rejects spin site_type" begin
        err = nothing
        try
            SimulationState(L = 4, bc = :open, backend = :gaussian, site_type = "S=1",
                rng = RNGRegistry(gates_spacetime = 1, gates_realization = 11,
                    born_measurement = 21, state_init = 31))
        catch e
            err = e
        end
        @test err isa ArgumentError
        @test occursin("local_dim", err.msg)

        @test_throws ArgumentError SimulationState(L = 4, bc = :open, backend = :gaussian,
            site_type = "S=1",
            rng = RNGRegistry(gates_spacetime = 1, gates_realization = 11,
                born_measurement = 21, state_init = 31))
    end

end
