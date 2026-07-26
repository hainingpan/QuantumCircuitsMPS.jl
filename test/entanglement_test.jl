# test/entanglement_test.jl
# Tests for EntanglementEntropy observable

using Test
using QuantumCircuitsMPS

@testset "EntanglementEntropy" begin
    @testset "Product state entropy" begin
        # Product state |0⟩⊗L should have zero entanglement entropy
        state = SimulationState(L = 4, bc = :open)
        initialize!(state, ProductState(binary_int = 0))  # All qubits in |0⟩

        ee = EntanglementEntropy(cut = 2, renyi_index = 1)
        entropy = ee(state)

        @test entropy ≈ 0.0 atol=1e-10
    end

    @testset "Observable registration" begin
        # EntanglementEntropy should appear in list_observables()
        observables = list_observables()
        @test "EntanglementEntropy" ∈ observables
    end

    @testset "Track/record integration" begin
        # Test that track!/record! workflow works correctly
        state = SimulationState(L = 4,
            bc = :open;
            rng = RNGRegistry(gates_spacetime = 1, gates_realization = 3, born_measurement = 4))
        initialize!(state, ProductState(binary_int = 0))

        # Track entanglement entropy at cut=2
        track!(state, :ee => EntanglementEntropy(cut = 2, renyi_index = 1))

        # Record initial entropy
        record!(state)

        # Apply entangling gate and record again
        circuit = Circuit(L = 4, bc = :open) do c
            apply!(c, HaarRandom(), StaircaseRight(1))
        end
        simulate!(circuit, state; n_steps = 1, record_when = :final_only)

        # Should have 2 records now
        @test length(state.observables[:ee]) == 2
        @test all(e -> e isa Float64, state.observables[:ee])
        @test all(e -> e >= 0, state.observables[:ee])
    end

    @testset "Cut validation" begin
        # Test that cut validation works correctly
        state = SimulationState(L = 4, bc = :open)
        initialize!(state, ProductState(binary_int = 0))

        # cut=1 should work (minimum valid cut)
        ee1 = EntanglementEntropy(cut = 1, renyi_index = 1)
        @test ee1(state) isa Float64

        # cut=L-1 should work (maximum valid cut)
        ee_max = EntanglementEntropy(cut = 3, renyi_index = 1)
        @test ee_max(state) isa Float64

        # cut=0 should fail at construction
        @test_throws ArgumentError EntanglementEntropy(cut = 0, renyi_index = 1)

        # cut=L should fail at call time
        ee_invalid = EntanglementEntropy(cut = 4, renyi_index = 1)
        @test_throws ArgumentError ee_invalid(state)
    end
end

@testset "EntanglementEntropy region construction" begin
    @testset "Parametric type dispatch" begin
        # cut::Int -> EntanglementEntropy{Int} (historical form, unchanged)
        ee_int = EntanglementEntropy(cut = 1)
        @test ee_int isa EntanglementEntropy{Int}
        @test ee_int.cut == 1
        @test ee_int.renyi_index == 1
        @test ee_int.threshold == 1e-16
        @test ee_int.base == 2.0

        # region -> EntanglementEntropy{Vector{Int}}
        @test EntanglementEntropy(cut = 2:5) isa EntanglementEntropy{Vector{Int}}
        @test EntanglementEntropy(cut = [1, 2]) isa EntanglementEntropy{Vector{Int}}
    end

    @testset "Region normalization" begin
        # Ranges are INCLUSIVE site sets: 2:5 == {2,3,4,5}
        ee = EntanglementEntropy(cut = 2:5)
        @test ee.cut == [2, 3, 4, 5]
        @test ee.cut isa Vector{Int}

        # Unsorted / PBC-wrapped input is canonicalized by sorting
        @test EntanglementEntropy(cut = [8, 1, 2, 7]).cut == [1, 2, 7, 8]
        @test EntanglementEntropy(cut = [4, 2, 3]).cut == [2, 3, 4]

        # Single-site region
        @test EntanglementEntropy(cut = [3]).cut == [3]
        @test EntanglementEntropy(cut = 3:3).cut == [3]

        # Non-cut parameters are honored on the region path too
        ee2 = EntanglementEntropy(cut = 1:2, renyi_index = 2, threshold = 1e-12, base = ℯ)
        @test ee2.renyi_index == 2
        @test ee2.threshold == 1e-12
        @test ee2.base == Float64(ℯ)
    end

    @testset "Region validation at construction" begin
        @test_throws ArgumentError EntanglementEntropy(cut = Int[])   # empty vector
        @test_throws ArgumentError EntanglementEntropy(cut = 1:0)     # empty range
        @test_throws ArgumentError EntanglementEntropy(cut = [1, 1, 2])  # duplicates
        @test_throws ArgumentError EntanglementEntropy(cut = [0, 2])     # nonpositive
        @test_throws ArgumentError EntanglementEntropy(cut = [-3, 1])    # nonpositive
        @test_throws ArgumentError EntanglementEntropy(cut = [1, 2], renyi_index = 0)
        @test_throws ArgumentError EntanglementEntropy(cut = [1, 2], threshold = 0.0)
        @test_throws ArgumentError EntanglementEntropy(cut = [1, 2], base = 0)

        # Regression pin: the Int path's cut=0 construction throw is unchanged
        @test_throws ArgumentError EntanglementEntropy(cut = 0)
        @test_throws ArgumentError EntanglementEntropy(cut = -1)
    end

    @testset "MPS backend rejects regions" begin
        state = SimulationState(L = 4, bc = :open)
        initialize!(state, ProductState(binary_int = 0))

        @test_throws ArgumentError EntanglementEntropy(cut = [1, 2])(state)
        @test_throws ArgumentError EntanglementEntropy(cut = 2:3)(state)

        # The Int path still works on MPS, unchanged
        @test EntanglementEntropy(cut = 2)(state) isa Float64
    end
end

# ======================================================================
# Real-valued `renyi_index` contract + three-branch Rényi kernel (MPS).
#
# Appended for the package-wide `renyi_index::Real` change: the field is now
# a normalized `Float64`, the accepted set is "any Real whose Float64
# normalization is finite and > 0", and the Rényi kernel evaluates general
# real n in a scale-before-overflow log domain with a von Neumann shunt near
# n = 1. Everything below is a permanent regression pin.
# ======================================================================

# The rejection set shared by all four renyi_index-carrying observables.
# `true`/`false` are `Real` in Julia and `Float64(true) == 1.0`, so a missing
# Bool guard would SILENTLY accept `true` as von Neumann. The two BigFloats
# are finite reals > 0 BEFORE conversion but normalize to `Inf` / `0.0`,
# which is why the contract is stated on the NORMALIZED value.
const _RENYI_REJECTED = (0, 0.0, -1, -0.5, Inf, NaN, true, false,
    BigFloat("1e400"), BigFloat("1e-400"))

@testset "EntanglementEntropy renyi_index: real-valued contract" begin
    @testset "accepted values are stored as normalized Float64" begin
        ee = EntanglementEntropy(cut = 2, renyi_index = 1.5)
        @test ee.renyi_index == 1.5
        @test ee.renyi_index isa Float64

        # 0 < n < 1 is now accepted (it used to require n >= 1)
        @test EntanglementEntropy(cut = 2, renyi_index = 0.5).renyi_index == 0.5

        # Int input is NORMALIZED, not stored as an Int
        ee_int = EntanglementEntropy(cut = 2, renyi_index = 2)
        @test ee_int.renyi_index == 2
        @test ee_int.renyi_index isa Float64

        # The region path stores the same normalized Float64
        ee_reg = EntanglementEntropy(cut = [1, 3], renyi_index = 3//2)
        @test ee_reg.renyi_index == 1.5
        @test ee_reg.renyi_index isa Float64

        # Extreme-but-accepted indices construct fine
        @test EntanglementEntropy(cut = 2, renyi_index = 2048).renyi_index == 2048.0
        @test EntanglementEntropy(cut = 2,
            renyi_index = floatmax(Float64)).renyi_index == floatmax(Float64)
    end

    @testset "rejection matrix (never MethodError, never silent acceptance)" begin
        for bad in _RENYI_REJECTED
            @test_throws ArgumentError EntanglementEntropy(cut = 2, renyi_index = bad)
            @test_throws ArgumentError EntanglementEntropy(cut = [1, 3], renyi_index = bad)
        end
    end

    @testset "catch-all _ee_from_cut accepts a non-Int renyi_index" begin
        # Regression pin: the catch-all method's second argument was relaxed
        # from `::Int` to `::Real`. With `::Int` this combination fell off the
        # method table and raised a MethodError instead of the informative
        # ArgumentError about `cut`.
        @test_throws ArgumentError EntanglementEntropy(cut = :bad, renyi_index = 1.5)
        @test_throws ArgumentError EntanglementEntropy(cut = "bad", renyi_index = 0.5)
        # ... and still throws for the historical Int case
        @test_throws ArgumentError EntanglementEntropy(cut = :bad, renyi_index = 1)
    end
end

@testset "EntanglementEntropy Rényi kernel (MPS backend)" begin
    _ee_mps_rng(s) = RNGRegistry(gates_spacetime = s, gates_realization = s + 1,
        born_measurement = s + 2)

    function _ee_mps_bell()
        st = SimulationState(L = 4, bc = :open, maxdim = 64, rng = _ee_mps_rng(5))
        initialize!(st, ProductState(binary_int = 0))
        apply!(st, Hadamard(), SingleSite(1))
        apply!(st, CNOT(), Sites([1, 2]))
        return st
    end

    @testset "Bell (flat spectrum) = 1 bit at extreme Rényi indices" begin
        st = _ee_mps_bell()
        # A flat spectrum is n-INDEPENDENT, so every index must give 1 bit.
        # n = 2048 kills a direct-power implementation (0.5^2048 underflows to
        # 0.0 → log(0) → -Inf); n = floatmax kills an un-scaled logsumexp
        # (floatmax * log(0.5) overflows to -Inf for EVERY element).
        for n in (1.5, 2048, floatmax(Float64))
            S = EntanglementEntropy(cut = 1, renyi_index = n, base = 2)(st)
            @test isfinite(S)
            @test S≈1.0 rtol=1e-9
        end
    end

    @testset "von Neumann shunt: |n-1| <= 1e-8 is bit-identical to n = 1" begin
        st = _ee_mps_bell()
        S1 = EntanglementEntropy(cut = 1, renyi_index = 1, base = 2)(st)
        for n in (prevfloat(1.0), nextfloat(1.0), 1.0 - 1e-8, 1.0 + 1e-8)
            @test EntanglementEntropy(cut = 1, renyi_index = n, base = 2)(st) == S1
        end
        # The decimal literal 1.0 - 1e-8 sits at Float64 distance
        # ≈ 1.0000000050e-8 from 1.0, i.e. STRICTLY ABOVE 1e-8 — the shunt
        # half-width must be widened by eps(1.0) or this pin fails.
        @test abs((1.0 - 1e-8) - 1.0) > 1e-8
    end

    @testset "near-1 continuity and monotonicity (Haar-evolved MPS)" begin
        st = SimulationState(L = 6, bc = :open, maxdim = 64, rng = _ee_mps_rng(31))
        initialize!(st, ProductState(binary_int = 0))
        for _ in 1:4
            apply!(st, HaarRandom(), Bricklayer(:odd))
            apply!(st, HaarRandom(), Bricklayer(:even))
        end
        S(n) = EntanglementEntropy(cut = 3, renyi_index = n, base = 2)(st)
        S1 = S(1)
        @test S1 > 0.5                          # non-vacuous
        @test abs(S(1 + 1e-6) - S1) < 1e-4
        @test abs(S(1 - 1e-6) - S1) < 1e-4
        @test S(1 + 1e-6) > 0
        @test S(1 - 1e-6) > 0
        # Rényi entropy is non-increasing in n; require a real margin so the
        # test cannot pass on three numerically-equal values.
        @test S(0.5) - S1 > 1e-6
        @test S1 - S(2) > 1e-6
        @test S(2) - S(3) > 1e-6
    end

    @testset "MPS ≡ state vector for general real n (kernel regression)" begin
        # The MPS kernel is fed `diag(S)` of the bond SVD, an
        # `NDTensors.DenseTensor` whose `eachindex` yields `CartesianIndex{1}`
        # while `argmax` returns an `Int64`. An index-convention-dependent
        # "drop the largest entry" filter silently drops NOTHING there, which
        # inflated a flat rank-2 spectrum's Rényi entropy from log 2 to log 3
        # while leaving n = 1 correct. Cross-checking against the state-vector
        # kernel (plain `Vector{Float64}`, same math) pins that class of bug.
        L = 6
        sv = SimulationState(L = L, bc = :open, backend = :statevector,
            rng = _ee_mps_rng(31))
        mps = SimulationState(L = L, bc = :open, maxdim = 64, rng = _ee_mps_rng(31))
        for st in (sv, mps)
            initialize!(st, ProductState(binary_int = 0))
            for _ in 1:4
                apply!(st, HaarRandom(), Bricklayer(:odd))
                apply!(st, HaarRandom(), Bricklayer(:even))
            end
        end
        for n in (0.5, 1.5, 2, 3, 2048, floatmax(Float64)), cut in 1:(L - 1)

            a = EntanglementEntropy(cut = cut, renyi_index = n, base = 2)(sv)
            b = EntanglementEntropy(cut = cut, renyi_index = n, base = 2)(mps)
            @test isfinite(b)
            @test b≈a atol=1e-8
        end
    end
end
