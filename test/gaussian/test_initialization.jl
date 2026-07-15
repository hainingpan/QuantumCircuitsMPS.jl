# test/gaussian/test_initialization.jl
# Tests for initialize!(::SimulationState{GaussianBackend}, ::ProductState)
# and initialize!(::SimulationState{GaussianBackend}, ::RandomGaussianState)
# (src/Gaussian/initialization.jl).
#
# Run directly:
#   julia --project=. -e 'include("test/gaussian/test_initialization.jl")'

using Test
using QuantumCircuitsMPS
using LinearAlgebra

# QA shorthand (see .sisyphus/notepads/gaussian-backend/learnings.md):
# RNGRegistry has NO seed kwarg.
function _rng(k)
    RNGRegistry(gates_spacetime = k, gates_realization = k + 10,
        born_measurement = k + 20, state_init = k + 30)
end

function _gaussian_state(L, k)
    SimulationState(L = L, bc = :open, backend = :gaussian, rng = _rng(k))
end

@testset "Gaussian initialize!" begin
    @testset "vacuum ProductState(binary_int=0)" begin
        L = 4
        state = _gaussian_state(L, 1)
        ret = initialize!(state, ProductState(binary_int = 0))
        @test ret === state

        Γ = state.backend.corr
        @test Γ isa Matrix{Float64}
        @test size(Γ) == (2L, 2L)

        # Antisymmetry: Γᵀ = −Γ
        @test maximum(abs.(Γ .+ transpose(Γ))) < 1e-14
        # Purity: Γ² = −I
        @test maximum(abs.(Γ * Γ + I)) < 1e-12
        # VERIFIED unoccupied sign convention: Γ[2i−1,2i] = +1 ⇔ ⟨c†c⟩ = 0
        @test Γ[1, 2] == 1.0
        for i in 1:L
            @test Γ[2i - 1, 2i] == 1.0
            @test Γ[2i, 2i - 1] == -1.0
        end

        # Scratch buffer allocated alongside corr
        @test state.backend.scratch isa Matrix{Float64}
        @test size(state.backend.scratch) == (2L, 2L)
    end

    @testset "pattern ProductState(binary_int) for \"0101\" (L=4)" begin
        L = 4
        state = _gaussian_state(L, 2)
        # binary_int=5 → lpad("101", 4, "0") = "0101"; MSB convention:
        # leftmost bit = site 1, so sites 2 and 4 are occupied.
        initialize!(state, ProductState(binary_int = 5))

        Γ = state.backend.corr
        @test Γ[1, 2] == 1.0    # site 1: bit '0' → unoccupied
        @test Γ[3, 4] == -1.0   # site 2: bit '1' → occupied (flipped block)
        @test Γ[5, 6] == 1.0    # site 3: bit '0' → unoccupied
        @test Γ[7, 8] == -1.0   # site 4: bit '1' → occupied (flipped block)

        # Only the intra-mode blocks are nonzero
        for i in 1:L, j in 1:L

            if i != j
                @test all(Γ[(2i - 1):(2i), (2j - 1):(2j)] .== 0.0)
            end
        end

        @test maximum(abs.(Γ .+ transpose(Γ))) < 1e-14
        @test maximum(abs.(Γ * Γ + I)) < 1e-12
    end

    @testset "RandomGaussianState: purity + antisymmetry" begin
        L = 6
        state = _gaussian_state(L, 3)
        ret = initialize!(state, RandomGaussianState())
        @test ret === state

        Γ = state.backend.corr
        @test Γ isa Matrix{Float64}
        @test size(Γ) == (2L, 2L)
        @test maximum(abs.(Γ .+ transpose(Γ))) < 1e-10
        @test maximum(abs.(Γ * Γ + I)) < 1e-10
        @test state.backend.scratch isa Matrix{Float64}
        @test size(state.backend.scratch) == (2L, 2L)

        # Genuinely rotated: not the bare vacuum
        @test !(Γ ≈ QuantumCircuitsMPS.vacuum_covariance(L))
    end

    @testset "RandomGaussianState: seed reproducibility" begin
        L = 4
        # Same :state_init seed → bitwise-identical Γ
        s1 = _gaussian_state(L, 7)
        s2 = _gaussian_state(L, 7)
        initialize!(s1, RandomGaussianState())
        initialize!(s2, RandomGaussianState())
        @test s1.backend.corr == s2.backend.corr   # bitwise equality

        # Different :state_init seed → different Γ
        s3 = _gaussian_state(L, 8)
        initialize!(s3, RandomGaussianState())
        @test s1.backend.corr != s3.backend.corr
    end

    @testset "re-initialize! on an already-initialized state" begin
        L = 4
        state = _gaussian_state(L, 4)
        initialize!(state, RandomGaussianState())
        Γ_random = copy(state.backend.corr)

        # Re-initialize with the vacuum: fresh Γ replaces the random one
        initialize!(state, ProductState(binary_int = 0))
        Γ = state.backend.corr
        @test Γ == QuantumCircuitsMPS.vacuum_covariance(L)
        @test Γ != Γ_random

        # And back to a pattern state
        initialize!(state, ProductState(bitstring = "1000"))
        @test state.backend.corr[1, 2] == -1.0   # site 1 occupied
        @test state.backend.corr[3, 4] == 1.0    # site 2 unoccupied
    end

    @testset "spin_state ProductState spec → ArgumentError" begin
        L = 4
        state = _gaussian_state(L, 5)
        err = nothing
        try
            initialize!(state, ProductState(spin_state = "Z0"))
        catch e
            err = e
        end
        @test err isa ArgumentError
        @test occursin("spin_state", err.msg)
        @test occursin("Gaussian", err.msg)
    end
end
