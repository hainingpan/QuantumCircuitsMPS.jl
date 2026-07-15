# test/gaussian/test_apply.jl
# Unit tests for the Gaussian gate-application engine (T7):
# _apply_single!(SimulationState{GaussianBackend}, ...) for GaussianHaar
# (Haar-SO(4) Majorana conjugation, :gates_realization stream), PauliX
# (fermionic occupation flip), and the rejecting AbstractGate fallback.
#
# NOTE: states are initialized by setting the covariance matrix directly via
# the T2 kernel (`vacuum_covariance`) instead of `initialize!`, so this file
# does not depend on the Gaussian `initialize!` task (T6, developed in
# parallel).
#
# NOTE: not yet wired into test/runtests.jl — run directly:
#   julia --project=. -e 'include("test/gaussian/test_apply.jl")'

using Test
using LinearAlgebra
using QuantumCircuitsMPS
using Random: MersenneTwister

# Vacuum-initialized Gaussian state without going through initialize! (T6).
# Seed convention (notepad): RNG(k) = k / k+10 / k+20 / k+30 per stream.
function make_vacuum_state(L::Int; bc::Symbol = :open, seed::Int = 1,
        gates_realization::Union{Int, Nothing} = nothing)
    state = SimulationState(L = L, bc = bc, backend = :gaussian,
        rng = RNGRegistry(gates_spacetime = seed,
            gates_realization = gates_realization === nothing ? seed + 10 :
                                gates_realization,
            born_measurement = seed + 20, state_init = seed + 30))
    state.backend.corr = QuantumCircuitsMPS.vacuum_covariance(L)
    state.backend.scratch = zeros(2L, 2L)
    return state
end

@testset "Gaussian Gate Application (GaussianHaar, PauliX, fallback)" begin
    @testset "purity + antisymmetry after 100 GaussianHaar (L=8)" begin
        L = 8
        state = make_vacuum_state(L; seed = 1)
        pair_rng = MersenneTwister(123)  # test scaffolding only, NOT a state stream
        for _ in 1:100
            i = rand(pair_rng, 1:(L - 1))
            apply!(state, GaussianHaar(), [i, i + 1])
        end
        Γ = state.backend.corr
        @test norm(Γ * Γ + I) < 1e-10          # purity: Γ² = -I
        @test norm(Γ + transpose(Γ)) < 1e-10   # antisymmetry: Γᵀ = -Γ
    end

    @testset ":gates_realization seed reproducibility" begin
        L = 6
        pairs = [(1, 2), (3, 4), (5, 6), (2, 3), (4, 5), (1, 2), (3, 4)]
        function run_sequence(; seed, gates_realization)
            s = make_vacuum_state(L; seed = seed, gates_realization = gates_realization)
            for (i, j) in pairs
                apply!(s, GaussianHaar(), [i, j])
            end
            return s.backend.corr
        end
        # Same :gates_realization seed (all OTHER stream seeds different)
        # ⇒ bitwise-identical Γ: proves GaussianHaar draws ONLY from
        # :gates_realization.
        Γ1 = run_sequence(seed = 1, gates_realization = 77)
        Γ2 = run_sequence(seed = 2, gates_realization = 77)
        @test Γ1 == Γ2  # bitwise
        # Different :gates_realization seed ⇒ different Γ.
        Γ3 = run_sequence(seed = 1, gates_realization = 78)
        @test Γ3 != Γ1
    end

    @testset "PauliX = fermionic occupation flip on vacuum site 1" begin
        s = make_vacuum_state(4; seed = 3)
        @test s.backend.corr[1, 2] == 1.0  # vacuum: site 1 unoccupied
        apply!(s, PauliX(), [1])
        Γ = s.backend.corr
        @test Γ[1, 2] == -1.0              # on-site block sign flipped (occupied)
        @test Γ[2, 1] == 1.0
        @test Γ[3, 4] == 1.0               # other sites untouched
        @test norm(Γ * Γ + I) < 1e-14      # exact reflection: purity holds
        @test norm(Γ + transpose(Γ)) == 0.0
        apply!(s, PauliX(), [1])           # involution: flip back to vacuum
        @test s.backend.corr[1, 2] == 1.0
    end

    @testset "uninitialized state rejected" begin
        s = SimulationState(L = 4, bc = :open, backend = :gaussian,
            rng = RNGRegistry(gates_spacetime = 1, gates_realization = 11,
                born_measurement = 21, state_init = 31))
        @test s.backend.corr === nothing
        @test_throws ArgumentError apply!(s, GaussianHaar(), [1, 2])
        @test_throws ArgumentError apply!(s, PauliX(), [1])
    end

    @testset "$(nameof(typeof(gate))) rejected on backend=:gaussian" for gate in [
        Hadamard(), CNOT(), HaarRandom(), RandomClifford(), SWAP(),
        PhaseGate(), PauliY(), PauliZ(), CZ(), Projection(0)
    ]
        s = make_vacuum_state(4; seed = 5)
        sites = QuantumCircuitsMPS.support(gate) == 1 ? [1] : [1, 2]
        err = nothing
        try
            apply!(s, gate, sites)
        catch e
            err = e
        end
        @test err isa ArgumentError
        @test occursin("Gaussian", err.msg)
        @test occursin(string(nameof(typeof(gate))), err.msg)  # names the offender
    end
end
