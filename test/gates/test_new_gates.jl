# test/gates/test_new_gates.jl
# Unit tests for the 4 new Clifford-family gate types (CNOT, PhaseGate, SWAP,
# RandomClifford) on MPS and SV backends, plus cross-validation that both
# backends agree on born_probability values for the same circuit.

using Test
using QuantumCircuitsMPS
using LinearAlgebra
using Random: MersenneTwister

const QCM = QuantumCircuitsMPS

# ── Helpers ─────────────────────────────────────────────────────────────────
# _mps_state/_sv_state/_mps_state_bin/_sv_state_bin (matching the gates_api.jl
# convention) live in test/testutils.jl (T28 DRY).
@isdefined(make_backend_state) || include(joinpath(@__DIR__, "..", "testutils.jl"))

@testset "New gates (CNOT, PhaseGate, SWAP, RandomClifford)" begin

    # ═══════════════════════════════════════════════════════════════════════
    # 1. support() returns correct values
    # ═══════════════════════════════════════════════════════════════════════
    @testset "support()" begin
        @test QCM.support(CNOT()) == 2
        @test QCM.support(PhaseGate()) == 1
        @test QCM.support(SWAP()) == 2
        @test QCM.support(RandomClifford()) == 2     # default n=2
        @test QCM.support(RandomClifford(1)) == 1
        @test QCM.support(RandomClifford(3)) == 3
    end

    # ═══════════════════════════════════════════════════════════════════════
    # 1b. gate_label: RandomClifford renders as "Cl" (not the fallback type name)
    # ═══════════════════════════════════════════════════════════════════════
    @testset "gate_label" begin
        @test QCM.gate_label(RandomClifford()) == "Cl"
        @test QCM.gate_label(RandomClifford(1)) == "Cl"
        @test QCM.gate_label(ProductGate(RandomClifford(), Bricklayer(:even))) == "∏Cl"
    end

    # ═══════════════════════════════════════════════════════════════════════
    # 2. gate_matrix() returns correct matrices
    # ═══════════════════════════════════════════════════════════════════════
    @testset "gate_matrix() exact values" begin
        @test QCM.gate_matrix(CNOT()) == ComplexF64[1 0 0 0; 0 1 0 0; 0 0 0 1; 0 0 1 0]
        @test QCM.gate_matrix(PhaseGate()) == ComplexF64[1 0; 0 im]
        @test QCM.gate_matrix(SWAP()) == ComplexF64[1 0 0 0; 0 0 1 0; 0 1 0 0; 0 0 0 1]
    end

    # ═══════════════════════════════════════════════════════════════════════
    # 3. CNOT on MPS backend
    # ═══════════════════════════════════════════════════════════════════════
    @testset "CNOT on MPS backend" begin
        # |00⟩ → |00⟩ (control=0 ⇒ target unchanged)
        s = _mps_state_bin(2, 0)   # |00⟩
        apply!(s, CNOT(), AdjacentPair(1))
        @test born_probability(s, 1, 0) ≈ 1.0 atol=1e-12
        @test born_probability(s, 2, 0) ≈ 1.0 atol=1e-12

        # |10⟩ → |11⟩ (control=1 ⇒ target flipped)
        s = _mps_state_bin(2, 2)   # |10⟩ (MSB at site 1: binary_int=2 → "10")
        apply!(s, CNOT(), AdjacentPair(1))
        @test born_probability(s, 1, 1) ≈ 1.0 atol=1e-12
        @test born_probability(s, 2, 1) ≈ 1.0 atol=1e-12
    end

    # ═══════════════════════════════════════════════════════════════════════
    # 4. CNOT on SV backend
    # ═══════════════════════════════════════════════════════════════════════
    @testset "CNOT on SV backend" begin
        # |00⟩ → |00⟩
        s = _sv_state_bin(2, 0)
        apply!(s, CNOT(), AdjacentPair(1))
        @test born_probability(s, 1, 0) ≈ 1.0 atol=1e-12
        @test born_probability(s, 2, 0) ≈ 1.0 atol=1e-12

        # |10⟩ → |11⟩
        s = _sv_state_bin(2, 2)
        apply!(s, CNOT(), AdjacentPair(1))
        @test born_probability(s, 1, 1) ≈ 1.0 atol=1e-12
        @test born_probability(s, 2, 1) ≈ 1.0 atol=1e-12
    end

    # ═══════════════════════════════════════════════════════════════════════
    # 5. SWAP on MPS backend
    # ═══════════════════════════════════════════════════════════════════════
    @testset "SWAP on MPS backend" begin
        # |10⟩ → |01⟩
        s = _mps_state_bin(2, 2)   # |10⟩
        apply!(s, SWAP(), AdjacentPair(1))
        @test born_probability(s, 1, 0) ≈ 1.0 atol=1e-12
        @test born_probability(s, 2, 1) ≈ 1.0 atol=1e-12
    end

    # ═══════════════════════════════════════════════════════════════════════
    # 6. SWAP on SV backend
    # ═══════════════════════════════════════════════════════════════════════
    @testset "SWAP on SV backend" begin
        # |10⟩ → |01⟩
        s = _sv_state_bin(2, 2)
        apply!(s, SWAP(), AdjacentPair(1))
        @test born_probability(s, 1, 0) ≈ 1.0 atol=1e-12
        @test born_probability(s, 2, 1) ≈ 1.0 atol=1e-12
    end

    # ═══════════════════════════════════════════════════════════════════════
    # 7. PhaseGate: S²=Z identity via H;S;S;H on |0⟩ → |1⟩
    #    Algebraic proof:
    #      S = diag(1, i)  ⇒  S² = diag(1, -1) = Z
    #      H|0⟩ = |+⟩
    #      Z|+⟩ = |−⟩
    #      H|−⟩ = |1⟩
    #    So H S² H |0⟩ = |1⟩ deterministically.
    # ═══════════════════════════════════════════════════════════════════════
    @testset "PhaseGate S²=Z identity (MPS)" begin
        s = _mps_state(2)  # |00⟩, test on site 1
        apply!(s, Hadamard(), SingleSite(1))
        apply!(s, PhaseGate(), SingleSite(1))
        apply!(s, PhaseGate(), SingleSite(1))
        apply!(s, Hadamard(), SingleSite(1))
        # Site 1 should be |1⟩ deterministically
        @test born_probability(s, 1, 1) ≈ 1.0 atol=1e-12
        @test born_probability(s, 1, 0) ≈ 0.0 atol=1e-12
        # Site 2 untouched, still |0⟩
        @test born_probability(s, 2, 0) ≈ 1.0 atol=1e-12
    end

    @testset "PhaseGate S²=Z identity (SV)" begin
        s = _sv_state(2)
        apply!(s, Hadamard(), SingleSite(1))
        apply!(s, PhaseGate(), SingleSite(1))
        apply!(s, PhaseGate(), SingleSite(1))
        apply!(s, Hadamard(), SingleSite(1))
        @test born_probability(s, 1, 1) ≈ 1.0 atol=1e-12
        @test born_probability(s, 1, 0) ≈ 0.0 atol=1e-12
        @test born_probability(s, 2, 0) ≈ 1.0 atol=1e-12
    end

    # ═══════════════════════════════════════════════════════════════════════
    # 8. RandomClifford: unitarity, seed reproducibility, apply! on both
    # ═══════════════════════════════════════════════════════════════════════
    @testset "RandomClifford unitarity" begin
        for n in [1, 2, 3]
            rng = MersenneTwister(42)
            U = QCM.gate_matrix(RandomClifford(n), rng; local_dim = 2)
            @test size(U) == (2^n, 2^n)
            @test norm(U' * U - I) < 1e-12
        end
    end

    @testset "RandomClifford seed reproducibility" begin
        rng1 = MersenneTwister(42)
        rng2 = MersenneTwister(42)
        U1 = QCM.gate_matrix(RandomClifford(2), rng1; local_dim = 2)
        U2 = QCM.gate_matrix(RandomClifford(2), rng2; local_dim = 2)
        @test U1 ≈ U2 atol=0   # bitwise identical
    end

    @testset "RandomClifford apply! on MPS backend" begin
        seeds = (gates_spacetime = 11, gates_realization = 55, born_measurement = 33)
        s = _mps_state(4; seeds = seeds)
        # Should not throw
        apply!(s, RandomClifford(2), AdjacentPair(1))
        apply!(s, RandomClifford(1), SingleSite(3))
        # State remains normalized
        @test abs(1.0 - sum(born_probability(s, 1, o) for o in 0:1)) < 1e-12
    end

    @testset "RandomClifford apply! on SV backend" begin
        seeds = (gates_spacetime = 11, gates_realization = 55, born_measurement = 33)
        s = _sv_state(4; seeds = seeds)
        apply!(s, RandomClifford(2), AdjacentPair(1))
        apply!(s, RandomClifford(1), SingleSite(3))
        @test abs(1.0 - sum(born_probability(s, 1, o) for o in 0:1)) < 1e-12
    end

    # ═══════════════════════════════════════════════════════════════════════
    # 9. Cross-validation: MPS vs SV with CNOT/PhaseGate/SWAP/RandomClifford
    #    Same circuit + same seeds → identical born_probability at every site
    # ═══════════════════════════════════════════════════════════════════════
    @testset "Cross-validation MPS vs SV" begin
        L = 4
        seeds = (gates_spacetime = 42, gates_realization = 7, born_measurement = 99)

        mps_s = SimulationState(L = L, bc = :open, maxdim = 256,
            rng = RNGRegistry(; seeds...))
        initialize!(mps_s, ProductState(binary_int = 0))

        sv_s = SimulationState(L = L, bc = :open, backend = :statevector,
            rng = RNGRegistry(; seeds...))
        initialize!(sv_s, ProductState(binary_int = 0))

        # Mixed circuit using all 4 new gate types + Hadamard
        for site in 1:L
            apply!(mps_s, Hadamard(), SingleSite(site))
            apply!(sv_s, Hadamard(), SingleSite(site))
        end

        # CNOT on adjacent pairs
        for site in 1:(L - 1)
            apply!(mps_s, CNOT(), AdjacentPair(site))
            apply!(sv_s, CNOT(), AdjacentPair(site))
        end

        # PhaseGate on each site
        for site in 1:L
            apply!(mps_s, PhaseGate(), SingleSite(site))
            apply!(sv_s, PhaseGate(), SingleSite(site))
        end

        # SWAP on adjacent pairs
        for site in 1:(L - 1)
            apply!(mps_s, SWAP(), AdjacentPair(site))
            apply!(sv_s, SWAP(), AdjacentPair(site))
        end

        # RandomClifford on adjacent pairs (uses :gates_realization RNG)
        for site in 1:(L - 1)
            apply!(mps_s, RandomClifford(2), AdjacentPair(site))
            apply!(sv_s, RandomClifford(2), AdjacentPair(site))
        end

        # Compare born_probability at every site for outcomes 0 and 1
        for site in 1:L
            for outcome in 0:1
                p_mps = born_probability(mps_s, site, outcome)
                p_sv = born_probability(sv_s, site, outcome)
                @test p_mps ≈ p_sv atol=1e-12
            end
        end

        # Guard: state is non-trivial (not all probabilities at 0 or 1)
        @test 0.01 < born_probability(mps_s, 1, 0) < 0.99
    end
end  # top-level @testset
