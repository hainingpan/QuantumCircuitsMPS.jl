# test/gaussian/test_apply.jl
# Unit tests for the Gaussian gate-application engine:
# _apply_single!(SimulationState{GaussianBackend}, ...) for GaussianHaar
# (Haar-SO(4) Majorana conjugation, :gates_realization stream), the
# rejecting AbstractGate fallback, and the PauliX/Reset rejections (no
# parity-odd occupation flip exists for fermions).
#
# NOTE: states are initialized by setting the covariance matrix directly via
# the kernel (`vacuum_covariance`) instead of `initialize!`, so this file
# does not depend on the Gaussian `initialize!` task (developed in
# parallel).
#
# NOTE: not yet wired into test/runtests.jl — run directly:
#   julia --project=. -e 'include("test/gaussian/test_apply.jl")'

using Test
using LinearAlgebra
using QuantumCircuitsMPS
using Random: MersenneTwister

# Vacuum-initialized Gaussian state without going through initialize!.
# Seed convention: RNG(k) = k / k+10 / k+20 / k+30 per stream.
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

    @testset "PauliX and Reset rejected before any state change" begin
        # A fermionic occupation flip would be a single-Majorana reflection —
        # parity-odd, not a Gaussian operation — so neither gate exists on
        # this backend. Reset must throw BEFORE its Born draw: the generic
        # Reset would otherwise measure first and only fail on outcome 1.
        s = make_vacuum_state(4; seed = 3)
        for bond in ([1, 2], [3, 4], [2, 3])        # an entangled state, so a draw would matter
            apply!(s, GaussianHaar(), bond)
        end
        Γ_before = copy(s.backend.corr)
        born_before = copy(QuantumCircuitsMPS.get_rng(s.rng_registry, :born_measurement))
        @test_throws ArgumentError apply!(s, PauliX(), [1])
        @test_throws ArgumentError apply!(s, Reset(), [1])
        @test s.backend.corr == Γ_before                       # bitwise untouched
        @test rand(copy(QuantumCircuitsMPS.get_rng(s.rng_registry, :born_measurement))) ==
              rand(copy(born_before))                           # no Born draw consumed
        err = try
            apply!(s, Reset(), [1])
        catch e
            e
        end
        @test err isa ArgumentError
        @test occursin("Reset", err.msg)
        @test occursin("parity-odd", err.msg)
        @test occursin("Measure(:Z)", err.msg)                 # points at the supported alternative
    end

    @testset "uninitialized state rejected" begin
        s = SimulationState(L = 4, bc = :open, backend = :gaussian,
            rng = RNGRegistry(gates_spacetime = 1, gates_realization = 11,
                born_measurement = 21, state_init = 31))
        @test s.backend.corr === nothing
        @test_throws ArgumentError apply!(s, GaussianHaar(), [1, 2])
    end

    @testset "$(nameof(typeof(gate))) rejected on backend=:gaussian" for gate in [
        Hadamard(), CNOT(), HaarRandom(), RandomClifford(), SWAP(),
        PhaseGate(), PauliX(), PauliY(), PauliZ(), CZ(), Projection(0), Reset()
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
