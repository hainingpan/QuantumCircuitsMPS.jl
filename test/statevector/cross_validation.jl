# test/statevector/cross_validation.jl
# Cross-validation: MPS and state-vector backends produce IDENTICAL results
# for the SAME RNG seeds, for every gate type including HaarRandom.

using Test
using QuantumCircuitsMPS
using LinearAlgebra
using Random

# Shared state builders (make_pair) live in test/testutils.jl (T28 DRY).
@isdefined(make_backend_state) || include(joinpath(@__DIR__, "..", "testutils.jl"))

# ─── Helper: extract MPS state as a dense vector ───────────────────────────
# Converts from MPS's internal ITensor representation to the SAME
# "site 1 = MSB" flat-vector convention used by the SV backend.
# Accounts for the non-identity ram_phy mapping that PBC states have
# (e.g. ram_phy = [1,6,2,5,3,4] for L=6 periodic): each MPS tensor
# dimension k corresponds to physical site ram_phy[k], so we permute
# so that Julia's column-major layout gives site 1 as slowest (MSB)
# and site L as fastest (LSB).
function mps_to_dense(s)
    L = s.L
    sites = s.backend.sites
    full = reduce(*, [s.backend.mps[i] for i in 1:L])
    arr = Array(full, sites...)
    # Position p (1=fastest/LSB) → physical site (L-p+1) → RAM dim phy_ram[L-p+1]
    perm = Tuple(s.phy_ram[L - p + 1] for p in 1:L)
    return vec(permutedims(arr, perm))
end

@testset "State Vector Cross-Validation" begin

    # ═══════════════════════════════════════════════════════════════════════
    # 1. Unitary circuit cross-validation (deterministic, no measurement)
    #    Uses ONLY non-HaarRandom gates.
    # ═══════════════════════════════════════════════════════════════════════
    @testset "Unitary circuit (non-HaarRandom) — L=$L" for L in [4, 6, 8]
        mps_s, sv_s = make_pair(L = L, bc = :open)

        # Build a mixed circuit: single-qubit rotations + CZ + Hadamard + MatrixGate
        θ = π / 5
        for site in 1:L
            apply!(mps_s, Rx(θ), SingleSite(site))
            apply!(sv_s, Rx(θ), SingleSite(site))
        end
        for site in 1:L
            apply!(mps_s, Ry(θ * 0.7), SingleSite(site))
            apply!(sv_s, Ry(θ * 0.7), SingleSite(site))
        end
        for site in 1:L
            apply!(mps_s, Rz(θ * 1.3), SingleSite(site))
            apply!(sv_s, Rz(θ * 1.3), SingleSite(site))
        end
        for site in 1:L
            apply!(mps_s, Hadamard(), SingleSite(site))
            apply!(sv_s, Hadamard(), SingleSite(site))
        end
        # PauliX / PauliY / PauliZ on alternating sites
        for site in 1:L
            g = [PauliX(), PauliY(), PauliZ()][mod1(site, 3)]
            apply!(mps_s, g, SingleSite(site))
            apply!(sv_s, g, SingleSite(site))
        end
        # CZ on adjacent pairs
        for site in 1:(L - 1)
            apply!(mps_s, CZ(), AdjacentPair(site))
            apply!(sv_s, CZ(), AdjacentPair(site))
        end
        # MatrixGate: a known 2×2 unitary (iSWAP-like)
        U2 = ComplexF64[cos(0.3) -im*sin(0.3); -im*sin(0.3) cos(0.3)]
        for site in 1:L
            apply!(mps_s, MatrixGate(U2), SingleSite(site))
            apply!(sv_s, MatrixGate(U2), SingleSite(site))
        end

        ψ_mps = mps_to_dense(mps_s)
        ψ_sv = sv_s.backend.ψ

        @test norm(ψ_mps - ψ_sv) < 1e-12
        @test norm(ψ_mps) ≈ 1.0 atol=1e-12
        @test norm(ψ_sv) ≈ 1.0 atol=1e-12
    end

    # ═══════════════════════════════════════════════════════════════════════
    # 2. HaarRandom workaround: explicit Haar unitary via MatrixGate
    #    Generates a random U via _haar_unitary, applies via MatrixGate(U)
    #    identically on both backends → bit-identical results.
    # ═══════════════════════════════════════════════════════════════════════
    @testset "HaarRandom workaround via MatrixGate — L=$L" for L in [4, 6]
        mps_s, sv_s = make_pair(L = L, bc = :open)

        # Generate explicit Haar unitaries (1-site and 2-site)
        rng_test = MersenneTwister(12345)

        # Apply 1-site Haar unitaries on each site
        for site in 1:L
            U1 = QuantumCircuitsMPS._haar_unitary(2, rng_test)
            apply!(mps_s, MatrixGate(U1), SingleSite(site))
            apply!(sv_s, MatrixGate(U1), SingleSite(site))
        end

        # Apply 2-site Haar unitaries on adjacent pairs
        for site in 1:(L - 1)
            U2 = QuantumCircuitsMPS._haar_unitary(4, rng_test)
            apply!(mps_s, MatrixGate(U2), AdjacentPair(site))
            apply!(sv_s, MatrixGate(U2), AdjacentPair(site))
        end

        ψ_mps = mps_to_dense(mps_s)
        ψ_sv = sv_s.backend.ψ

        @test norm(ψ_mps - ψ_sv) < 1e-12
        @test norm(ψ_mps) ≈ 1.0 atol=1e-12
        @test norm(ψ_sv) ≈ 1.0 atol=1e-12
    end

    # ═══════════════════════════════════════════════════════════════════════
    # 3. Measurement circuit cross-validation
    #    Same RNG seeds → same Born outcomes → same final state.
    # ═══════════════════════════════════════════════════════════════════════
    @testset "Measurement circuit — L=$L" for L in [4, 6]
        # Use seeds that produce measurements with deterministic outcomes
        seeds = (gates_spacetime = 42, gates_realization = 7, born_measurement = 123)
        mps_s, sv_s = make_pair(L = L, bc = :open, seeds = seeds)

        # Apply some unitaries first (non-HaarRandom) to create a non-trivial state
        θ = π / 3
        for site in 1:L
            apply!(mps_s, Hadamard(), SingleSite(site))
            apply!(sv_s, Hadamard(), SingleSite(site))
        end
        for site in 1:(L - 1)
            apply!(mps_s, CZ(), AdjacentPair(site))
            apply!(sv_s, CZ(), AdjacentPair(site))
        end
        for site in 1:L
            apply!(mps_s, Rx(θ * site), SingleSite(site))
            apply!(sv_s, Rx(θ * site), SingleSite(site))
        end

        # Now measure each site — both backends should get the same Born outcomes
        # and the same collapsed final state.
        for site in 1:L
            apply!(mps_s, Measure(:Z), SingleSite(site))
            apply!(sv_s, Measure(:Z), SingleSite(site))
        end

        ψ_mps = mps_to_dense(mps_s)
        ψ_sv = sv_s.backend.ψ

        @test norm(ψ_mps - ψ_sv) < 1e-12
        # Post-measurement states should be normalized
        @test norm(ψ_mps) ≈ 1.0 atol=1e-12
        @test norm(ψ_sv) ≈ 1.0 atol=1e-12
    end

    # ═══════════════════════════════════════════════════════════════════════
    # 4. PBC (periodic boundary condition) circuit
    #    Verify gates correctly wrap around (e.g., CZ between site L and 1).
    # ═══════════════════════════════════════════════════════════════════════
    @testset "PBC circuit — L=6" begin
        L = 6
        seeds = (gates_spacetime = 42, gates_realization = 7, born_measurement = 99)
        mps_s = SimulationState(L = L, bc = :periodic, maxdim = 256,
            rng = RNGRegistry(; seeds...))
        initialize!(mps_s, ProductState(binary_int = 0))

        sv_s = SimulationState(L = L, bc = :periodic, backend = :statevector,
            rng = RNGRegistry(; seeds...))
        initialize!(sv_s, ProductState(binary_int = 0))

        # Bricklayer with even parity includes the wrap-around bond (L, 1)
        # Apply non-HaarRandom gates via Bricklayer for PBC test
        apply!(mps_s, Hadamard(), AllSites())
        apply!(sv_s, Hadamard(), AllSites())

        apply!(mps_s, CZ(), Bricklayer(:even))
        apply!(sv_s, CZ(), Bricklayer(:even))

        apply!(mps_s, CZ(), Bricklayer(:odd))
        apply!(sv_s, CZ(), Bricklayer(:odd))

        # Additional rotations
        for site in 1:L
            apply!(mps_s, Ry(π / (site + 1)), SingleSite(site))
            apply!(sv_s, Ry(π / (site + 1)), SingleSite(site))
        end

        # Another round of PBC bricklayer
        apply!(mps_s, CZ(), Bricklayer(:even))
        apply!(sv_s, CZ(), Bricklayer(:even))

        ψ_mps = mps_to_dense(mps_s)
        ψ_sv = sv_s.backend.ψ

        @test norm(ψ_mps - ψ_sv) < 1e-12
        @test norm(ψ_mps) ≈ 1.0 atol=1e-12
        @test norm(ψ_sv) ≈ 1.0 atol=1e-12
    end

    # ═══════════════════════════════════════════════════════════════════════
    # 5. HaarRandom cross-backend parity
    #    Verifies that HaarRandom with a shared seed produces bit-identical
    #    (to float roundoff) MPS/SV trajectories, now that the MPS-internal
    #    index convention matches MatrixGate's convention exactly. Both
    #    backends consume the same random numbers and produce the SAME state.
    # ═══════════════════════════════════════════════════════════════════════
    @testset "HaarRandom cross-backend parity" begin
        L = 4
        seeds = (gates_spacetime = 42, gates_realization = 777, born_measurement = 99)

        mps_s = SimulationState(L = L, bc = :open, maxdim = 256,
            rng = RNGRegistry(; seeds...))
        initialize!(mps_s, ProductState(binary_int = 0))

        sv_s = SimulationState(L = L, bc = :open, backend = :statevector,
            rng = RNGRegistry(; seeds...))
        initialize!(sv_s, ProductState(binary_int = 0))

        # Apply HaarRandom(2) to the same adjacent pair on both backends
        # with THE SAME RNG seed — same seed now produces the same state
        # across backends (the MPS-internal convention mismatch was fixed).
        apply!(mps_s, HaarRandom(2), AdjacentPair(1))
        apply!(sv_s, HaarRandom(2), AdjacentPair(1))

        ψ_mps = mps_to_dense(mps_s)
        ψ_sv = sv_s.backend.ψ

        # ASSERT: the two states MATCH (same seed → same trajectory across backends)
        @test ψ_mps ≈ ψ_sv atol=1e-12

        # ASSERT: both states are independently valid (normalized)
        @test norm(ψ_mps) ≈ 1.0 atol=1e-12
        @test norm(ψ_sv) ≈ 1.0 atol=1e-12

        # ASSERT: both state vectors have the correct dimension
        @test length(ψ_mps) == 2^L
        @test length(ψ_sv) == 2^L
    end

    # ═══════════════════════════════════════════════════════════════════════
    # 6. PBC EntanglementEntropy(cut=L÷2) cross-backend parity
    #    Verifies that, with the new default pbc_fold_start = L÷4+1, the MPS
    #    backend's RAM half-cut aligns with the SAME physical bipartition
    #    {1..L/2} vs {L/2+1..L} that the state-vector backend always used.
    #    Same seeds + same circuit → identical entropy trajectories.
    # ═══════════════════════════════════════════════════════════════════════
    @testset "PBC EntanglementEntropy cross-backend parity (L=$L)" for L in [6, 8]
        circuit = Circuit(L = L, bc = :periodic) do c
            apply!(c, HaarRandom(), Bricklayer(:even))
            apply!(c, HaarRandom(), Bricklayer(:odd))
        end
        ee = EntanglementEntropy(cut = L÷2)
        seeds = (gates_spacetime = 42, gates_realization = 1, born_measurement = 2)

        # MPS backend
        s_mps = SimulationState(L = L, bc = :periodic, maxdim = 64,
            rng = RNGRegistry(; seeds...))
        initialize!(s_mps, ProductState(binary_int = 0))
        track!(s_mps, :entropy => ee)
        simulate!(circuit, s_mps; n_steps = 5, record_when = :every_step)

        # SV backend
        s_sv = SimulationState(L = L, bc = :periodic, backend = :statevector,
            rng = RNGRegistry(; seeds...))
        initialize!(s_sv, ProductState(binary_int = 0))
        track!(s_sv, :entropy => ee)
        simulate!(circuit, s_sv; n_steps = 5, record_when = :every_step)

        # Entropy trajectories must match
        for (e_mps, e_sv) in zip(s_mps.observables[:entropy], s_sv.observables[:entropy])
            @test e_mps ≈ e_sv atol=1e-10
        end
        # Guard against a trivially-passing all-zero test
        @test maximum(s_mps.observables[:entropy]) > 0.01
        @test maximum(s_sv.observables[:entropy]) > 0.01
    end
end  # top-level @testset
