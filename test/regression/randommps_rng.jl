# test/regression/randommps_rng.jl
#
# REGRESSION (T13): RandomMPS / RandomStateVector must draw from the
# RNGRegistry's :state_init stream — never from the global RNG.
#
# Bug being pinned (v0.3.x): `initialize!(state, RandomMPS(...))`
# (src/State/initialization.jl) validated that an RNGRegistry was attached but
# then called `randomMPS(sites; linkdims=...)`, which uses
# `Random.default_rng()` internally. Result: two states with IDENTICAL
# RNGRegistry seeds produced DIFFERENT random MPSs, breaking the package's
# headline reproducibility contract ("same seed => same trajectory").
#
# The state-vector twin `RandomStateVector` (src/StateVector/initialization.jl)
# always had the correct pattern (`rng = get_rng(registry, :state_init)`);
# its determinism is pinned here too so it can never regress.
#
# Technique: the global default RNG is re-seeded DIFFERENTLY before each of the
# two same-seed initializations. Under the bug the two states then differ (test
# fails); with the fix they are identical draws from :state_init, bitwise —
# which simultaneously proves independence from the global RNG.

using Test
using Random
using QuantumCircuitsMPS

function _t13_registry(state_init_seed::Int)
    return RNGRegistry(gates_spacetime = 1, gates_realization = 2,
        born_measurement = 3, state_init = state_init_seed)
end

# RNGRegistry with the :state_init stream REMOVED (the keyword constructor
# always creates one, so build via the raw streams Dict).
function _t13_registry_without_state_init()
    return RNGRegistry(Dict{Symbol, Random.AbstractRNG}(
        :gates_spacetime => MersenneTwister(1),
        :gates_realization => MersenneTwister(2),
        :born_measurement => MersenneTwister(3)))
end

function _t13_random_mps_state(state_init_seed::Int; global_scramble::Int, L::Int = 6)
    Random.seed!(global_scramble)  # bug detector: global RNG must NOT matter
    state = SimulationState(L = L, bc = :open, maxdim = 16,
        rng = _t13_registry(state_init_seed))
    initialize!(state, RandomMPS(bond_dim = 8))
    return state
end

function _t13_random_sv_state(state_init_seed::Int; global_scramble::Int, L::Int = 4)
    Random.seed!(global_scramble)
    state = SimulationState(L = L, bc = :open, backend = :statevector,
        rng = _t13_registry(state_init_seed))
    initialize!(state, RandomStateVector())
    return state
end

@testset "REGRESSION randommps_rng: :state_init determinism (T13)" begin
    @testset "RandomMPS: same :state_init seed => identical MPS" begin
        L = 6
        s1 = _t13_random_mps_state(7; global_scramble = 1111, L = L)
        s2 = _t13_random_mps_state(7; global_scramble = 2222, L = L)
        for i in 1:L, outcome in (0, 1)

            @test born_probability(s1, i, outcome) ==
                  born_probability(s2, i, outcome)
        end
    end

    @testset "RandomMPS: different :state_init seed => different state" begin
        L = 6
        s7 = _t13_random_mps_state(7; global_scramble = 1111, L = L)
        s8 = _t13_random_mps_state(8; global_scramble = 1111, L = L)
        deltas = [abs(born_probability(s7, i, 0) - born_probability(s8, i, 0))
                  for i in 1:L]
        @test maximum(deltas) > 1e-6
    end

    @testset "RandomMPS: missing RNG => documented validation error" begin
        # (i) No registry at all: the documented ArgumentError, not a silent
        # global-RNG fallback.
        state = SimulationState(L = 4, bc = :open, maxdim = 8)
        @test_throws ArgumentError initialize!(state, RandomMPS(bond_dim = 4))

        # (ii) Registry present but WITHOUT a :state_init stream: must raise
        # (get_rng's "Unknown RNG stream") — under the bug this silently
        # succeeded via the global RNG.
        state_nostream = SimulationState(L = 4, bc = :open, maxdim = 8,
            rng = _t13_registry_without_state_init())
        @test_throws ArgumentError initialize!(state_nostream, RandomMPS(bond_dim = 4))
    end

    @testset "RandomStateVector: same :state_init seed => identical vector" begin
        L = 4
        s1 = _t13_random_sv_state(7; global_scramble = 1111, L = L)
        s2 = _t13_random_sv_state(7; global_scramble = 2222, L = L)
        @test s1.backend.ψ == s2.backend.ψ  # bitwise-identical draws
        for i in 1:L, outcome in (0, 1)

            @test born_probability(s1, i, outcome) ==
                  born_probability(s2, i, outcome)
        end
    end

    @testset "RandomStateVector: different :state_init seed => different vector" begin
        L = 4
        s7 = _t13_random_sv_state(7; global_scramble = 1111, L = L)
        s8 = _t13_random_sv_state(8; global_scramble = 1111, L = L)
        @test maximum(abs.(s7.backend.ψ .- s8.backend.ψ)) > 1e-6
    end

    @testset "RandomStateVector: missing RNG => documented validation error" begin
        state = SimulationState(L = 4, bc = :open, backend = :statevector)
        @test_throws ArgumentError initialize!(state, RandomStateVector())

        state_nostream = SimulationState(L = 4, bc = :open, backend = :statevector,
            rng = _t13_registry_without_state_init())
        @test_throws ArgumentError initialize!(state_nostream, RandomStateVector())
    end

    @testset "RandomStateVector is exported (v0.4.0)" begin
        @test :RandomStateVector in names(QuantumCircuitsMPS)
    end
end
