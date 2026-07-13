# test/gaussian/test_measurement.jl
# Unit tests for Gaussian measurement (T8):
#   born_probability(SimulationState{GaussianBackend}, site, outcome) —
#     non-destructive direct covariance read, P(0) = (1+Γ[2i−1,2i])/2;
#   _measure_single_site!(...) — REDUNDANT-DRAW contract (exactly one
#     :born_measurement scalar per measured site, drawn unconditionally
#     FIRST) + parity-projection collapse via gaussian_contraction!;
#   Measure(:Z) / Reset flowing through the generic execute! protocol.
#
# NOTE: not yet wired into test/runtests.jl (T13's job) — run directly:
#   julia --project=. -e 'include("test/gaussian/test_measurement.jl")'

using Test
using LinearAlgebra
using QuantumCircuitsMPS
using Random: MersenneTwister

# Vacuum-initialized Gaussian state. Seed convention (notepad):
# RNG(k) = k / k+10 / k+20 / k+30 per stream; born seed overridable.
function make_state(L::Int; bc::Symbol = :open, seed::Int = 1,
        born_measurement::Union{Int, Nothing} = nothing,
        gates_realization::Union{Int, Nothing} = nothing)
    state = SimulationState(L = L, bc = bc, backend = :gaussian,
        rng = RNGRegistry(gates_spacetime = seed,
            gates_realization = gates_realization === nothing ? seed + 10 : gates_realization,
            born_measurement = born_measurement === nothing ? seed + 20 : born_measurement,
            state_init = seed + 30))
    initialize!(state, ProductState(binary_int = 0))
    return state
end

# A few brick-layer GaussianHaar layers → genuinely entangled Gaussian state.
function entangle!(state, L; layers = 4)
    for layer in 1:layers
        for i in (isodd(layer) ? (1:2:(L - 1)) : (2:2:(L - 1)))
            apply!(state, GaussianHaar(), [i, i + 1])
        end
    end
    return state
end

@testset "Gaussian Measurement (born_probability, _measure_single_site!, Reset)" begin

    # ═══════════════════════════════════════════════════════════════════════
    # 1. born_probability on product states
    # ═══════════════════════════════════════════════════════════════════════
    @testset "vacuum: P(0)=1, P(1)=0 exactly, all sites" begin
        L = 6
        s = make_state(L)
        for i in 1:L
            @test born_probability(s, i, 0) ≈ 1.0 atol = 1e-14
            @test born_probability(s, i, 1) ≈ 0.0 atol = 1e-14
        end
        # non-destructive: covariance untouched by the reads
        @test s.backend.corr == QuantumCircuitsMPS.vacuum_covariance(L)
    end

    @testset "after PauliX on site 1: probabilities reversed" begin
        s = make_state(4)
        apply!(s, PauliX(), SingleSite(1))
        @test born_probability(s, 1, 0) ≈ 0.0 atol = 1e-14
        @test born_probability(s, 1, 1) ≈ 1.0 atol = 1e-14
        # other sites unaffected
        @test born_probability(s, 2, 0) ≈ 1.0 atol = 1e-14
    end

    @testset "input validation" begin
        s = make_state(4)
        @test_throws ArgumentError born_probability(s, 1, 2)
        @test_throws ArgumentError born_probability(s, 1, -1)
        @test_throws ArgumentError born_probability(s, 0, 0)
        @test_throws ArgumentError born_probability(s, 5, 0)
    end

    # ═══════════════════════════════════════════════════════════════════════
    # 2. Collapse: outcome → post-measurement covariance (sign mapping)
    # ═══════════════════════════════════════════════════════════════════════
    @testset "vacuum measure → outcome 0, Γ[2i-1,2i] stays +1" begin
        s = make_state(4)
        o = QuantumCircuitsMPS._measure_single_site!(s, 2)
        @test o == 0
        @test s.backend.corr[3, 4] == 1.0
    end

    @testset "occupied measure → outcome 1, Γ[2i-1,2i] = -1" begin
        s = make_state(4)
        apply!(s, PauliX(), SingleSite(2))
        o = QuantumCircuitsMPS._measure_single_site!(s, 2)
        @test o == 1
        @test s.backend.corr[3, 4] == -1.0
    end

    # ═══════════════════════════════════════════════════════════════════════
    # 3. Redundant-draw contract (mirror of test/audit/born_measurement.jl (e))
    # ═══════════════════════════════════════════════════════════════════════
    @testset "deterministic measurement consumes exactly ONE :born_measurement draw" begin
        born_seed = 33
        L = 4

        # State A: measure the DETERMINISTIC vacuum site 1 first (draw #1,
        # redundant — discarded), entangle 2-3, then measure the RANDOM
        # site 2 (draw #2).
        sA = make_state(L; born_measurement = born_seed)
        oA_det = QuantumCircuitsMPS._measure_single_site!(sA, 1)
        @test oA_det == 0                                # certain outcome
        entangle!(sA, L)
        p0 = born_probability(sA, 2, 0)
        @test 0.0 < p0 < 1.0                             # genuinely random
        oA_rand = QuantumCircuitsMPS._measure_single_site!(sA, 2)

        # Twin RNG (Clifford audit pattern): draw #1 is the redundant
        # deterministic one; draw #2 decides the random outcome via the
        # shared `r < p₀ ? 0 : 1` threshold convention.
        twin = MersenneTwister(born_seed)
        rand(twin)                                       # the discarded draw
        @test oA_rand == (rand(twin) < p0 ? 0 : 1)

        # State B (same seeds): skip the deterministic measurement but burn
        # ONE draw manually — trajectories must then coincide, proving the
        # deterministic measurement advanced the stream by exactly one.
        sB = make_state(L; born_measurement = born_seed)
        rand(QuantumCircuitsMPS.get_rng(sB.rng_registry, :born_measurement))
        entangle!(sB, L)
        oB_rand = QuantumCircuitsMPS._measure_single_site!(sB, 2)
        @test oB_rand == oA_rand
    end

    # ═══════════════════════════════════════════════════════════════════════
    # 4. Entangled state: probabilities, purity, idempotence
    # ═══════════════════════════════════════════════════════════════════════
    @testset "entangled state: p₀∈[0,1], post-collapse Γ²=-I, re-measure idempotent" begin
        L = 8
        s = make_state(L; seed = 7)
        entangle!(s, L)
        for site in 1:L
            p0 = born_probability(s, site, 0)
            @test 0.0 - 1e-14 <= p0 <= 1.0 + 1e-14
            @test born_probability(s, site, 0) + born_probability(s, site, 1) ≈ 1.0 atol = 1e-14
        end
        site = 4
        o = QuantumCircuitsMPS._measure_single_site!(s, site)
        Γ = s.backend.corr
        @test norm(Γ * Γ + I) < 1e-10                    # purity after collapse
        @test norm(Γ + transpose(Γ)) < 1e-10             # antisymmetry
        # post-measurement: outcome is now certain
        @test born_probability(s, site, o) ≈ 1.0 atol = 1e-12
        # immediate re-measurement returns the same outcome with probability 1
        @test QuantumCircuitsMPS._measure_single_site!(s, site) == o
    end

    # ═══════════════════════════════════════════════════════════════════════
    # 5. Measure(:Z) + Reset through the generic execute! protocol
    # ═══════════════════════════════════════════════════════════════════════
    @testset "Measure(:Z) via apply! collapses to ±1 block" begin
        L = 6
        s = make_state(L; seed = 9)
        entangle!(s, L)
        apply!(s, Measure(:Z), SingleSite(3))
        g = s.backend.corr[5, 6]
        @test isapprox(abs(g), 1.0; atol = 1e-10)        # collapsed to a definite occupation
    end

    @testset "Reset on occupied site → unoccupied" begin
        for seed in 1:20
            s = make_state(2; born_measurement = seed)
            apply!(s, PauliX(), SingleSite(1))
            @test born_probability(s, 1, 1) ≈ 1.0 atol = 1e-14
            apply!(s, Reset(), SingleSite(1))
            @test born_probability(s, 1, 0) ≈ 1.0 atol = 1e-14
        end
    end

    @testset "Reset on vacuum stays unoccupied" begin
        s = make_state(2)
        apply!(s, Reset(), SingleSite(1))
        @test born_probability(s, 1, 0) ≈ 1.0 atol = 1e-14
    end

    @testset "Reset forces unoccupied regardless of prior entangled state" begin
        L = 6
        for seed in (3, 4, 5)
            s = make_state(L; seed = seed)
            entangle!(s, L)
            for site in 1:L
                apply!(s, Reset(), SingleSite(site))
                @test born_probability(s, site, 0) ≈ 1.0 atol = 1e-10
            end
            Γ = s.backend.corr
            @test norm(Γ * Γ + I) < 1e-10
        end
    end

    # ═══════════════════════════════════════════════════════════════════════
    # 6. Seed reproducibility of measurement outcomes
    # ═══════════════════════════════════════════════════════════════════════
    @testset "same seeds ⇒ identical outcome sequence; different born seed ⇒ differs" begin
        L = 8
        function run_traj(; born_seed)
            s = make_state(L; seed = 21, born_measurement = born_seed)
            outcomes = Int[]
            for round in 1:3
                entangle!(s, L; layers = 2)
                for site in 1:L
                    push!(outcomes, QuantumCircuitsMPS._measure_single_site!(s, site))
                end
            end
            return outcomes
        end
        t1 = run_traj(born_seed = 101)
        t2 = run_traj(born_seed = 101)
        @test t1 == t2                                    # identical Int sequence
        t3 = run_traj(born_seed = 102)
        @test t3 != t1                                    # 24 draws — collision ~impossible
    end
end
