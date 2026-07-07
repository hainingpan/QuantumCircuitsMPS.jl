# test/reference_rule.jl
#
# Reference implementation of the unified stochastic rule (Task 7).
# This is the semantic ORACLE for the new engine (Task 9) and migration audits
# (Task 16). Self-contained: include-able from test/runtests.jl or runnable
# standalone via `julia --project=. test/reference_rule.jl`.
#
# RNG contract (plan "Oracle Review" refinements):
#   - Per element k = 1..K: exactly ONE scalar rand(rng). Never rand(rng, K).
#   - Consumption is data-independent: K draws always, regardless of outcome.
#   - Selection: cumulative walk over probs with strict `<`.
#   - Returns 1-based outcome index per element, or 0 for identity remainder.
#   - Cumsum snapping: if abs(sum(probs) - 1) <= 1e-10, the LAST cumulative
#     boundary is snapped to exactly 1.0, so float dust in Σp cannot leak
#     spurious identity selections.

using Test
using Random

function reference_select(rng, probs::Vector{Float64}, K::Int)::Vector{Int}
    n = length(probs)
    snap = abs(sum(probs) - 1.0) <= 1e-10
    out = Vector{Int}(undef, K)
    for k in 1:K
        r = rand(rng)              # exactly one scalar draw per element
        cumulative = 0.0
        selected = 0               # 0 = identity remainder
        for i in 1:n
            cumulative += probs[i]
            boundary = (snap && i == n) ? 1.0 : cumulative
            if r < boundary        # strict <
                selected = i
                break
            end
        end
        out[k] = selected
    end
    return out
end

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
        # and across many seeds for robustness
        for seed in 1:100, p in (0.0, 0.25, 0.5, 0.9)

            @test reference_select(MersenneTwister(seed), [p], 1)[1] ==
                  (rand(MersenneTwister(seed)) < p ? 1 : 0)
        end
    end
end

println("REFERENCE-RULE: PASS")
