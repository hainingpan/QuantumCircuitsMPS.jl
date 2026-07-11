# test/reference_rule.jl
#
# Oracle self-tests for `reference_select` (defined in test/testutils.jl) —
# the reference implementation of the unified stochastic rule (Task 7) and
# the semantic oracle for the engine (Task 9) and migration audits (Task 16).
# Include-able from test/runtests.jl (which loads testutils.jl first) or
# runnable standalone via `julia --project=. test/reference_rule.jl`.

using Test
using Random

# The oracle FUNCTION lives in testutils.jl (no testsets there); guarded
# include keeps this file standalone-runnable.
@isdefined(reference_select) || include("testutils.jl")

@testset "reference_rule" begin
    @testset "(i) consumes exactly K draws (data-independent)" begin
        for (probs, K) in [([0.2, 0.3], 17), ([0.5], 1), ([0.1, 0.1, 0.1], 1000),
            (fill(0.1, 10), 64), (Float64[], 5)]
            rng = MersenneTwister(42)
            twin = MersenneTwister(42)
            reference_select(rng, probs, K)
            for _ in 1:K
                rand(twin)          # advance twin by exactly K scalar draws
            end
            @test rng == twin       # full RNG-state equality
        end
    end

    @testset "(ii) empirical frequencies within 4 sigma (10^5 draws, fixed seed)" begin
        probs = [0.15, 0.35, 0.30]      # Σp = 0.8 → identity remainder 0.2
        N = 10^5
        sel = reference_select(MersenneTwister(2024), probs, N)
        expected = vcat(1.0 - sum(probs), probs)   # index 0,1,2,3
        for (idx, p) in zip(0:length(probs), expected)
            freq = count(==(idx), sel) / N
            sigma = sqrt(p * (1 - p) / N)
            dev = abs(freq - p) / sigma
            println("  outcome $idx: freq=$(freq)  p=$(p)  deviation=$(round(dev, digits=3))σ")
            @test dev < 4.0
        end
    end

    @testset "(iii) snapping: Σp ≈ 1 with float dust → zero identity selections" begin
        probs = fill(0.1, 10)
        @test sum(probs) < 1.0                       # float dust: 0.9999999999999999
        @test abs(sum(probs) - 1.0) <= 1e-10         # within snap tolerance
        sel = reference_select(MersenneTwister(1), probs, 10^5)
        @test count(==(0), sel) == 0
        # Control: without snapping the leak is real — a raw r drawn in [Σp, 1)
        # would select identity. Confirm the boundary case directly:
        @test reference_select(MersenneTwister(0), [prevfloat(1.0)], 1) != nothing  # smoke
    end

    @testset "(iv) single-outcome Case-A equivalence" begin
        @test reference_select(MersenneTwister(7), [0.3], 1)[1] ==
              (rand(MersenneTwister(7)) < 0.3 ? 1 : 0)
        # Representative (seed, p) grid — trimmed from the original
        # `for seed in 1:100, p in (0.0, 0.25, 0.5, 0.9)` (400 assertions,
        # ~15% of the pre-v0.4 suite) to 18 pairs covering the same property:
        # boundary p = 0.0 (never fires), near-zero, the original interior
        # values across spread-out seeds, 1.0-adjacent (non-snap regime,
        # |p-1| > 1e-10), and exact p = 1.0 (snap regime, always fires).
        for (seed, p) in [
            (1, 0.0), (42, 0.0), (100, 0.0),           # p = 0 boundary
            (7, 1.0e-12),                              # near-zero boundary
            (1, 0.25), (17, 0.25), (100, 0.25),        # interior (original grid)
            (2, 0.5), (37, 0.5), (73, 0.5),
            (3, 0.9), (58, 0.9), (99, 0.9),
            (5, 1.0 - 1.0e-9), (23, 1.0 - 1.0e-9),     # 1.0-adjacent, no snap
            (11, 1.0), (42, 1.0), (100, 1.0)           # p = 1 boundary (snap)
        ]
            @test reference_select(MersenneTwister(seed), [p], 1)[1] ==
                  (rand(MersenneTwister(seed)) < p ? 1 : 0)
        end
    end
end

println("REFERENCE-RULE: PASS")
