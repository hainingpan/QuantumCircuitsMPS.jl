# test/statevector/engine_agreement.jl
#
# === The two state-vector engines agree to rounding ===
#
# `engine=:optimized` (the default) applies gates with in-place stride-loop
# kernels (src/StateVector/optimized.jl); `engine=:builtin` is the Tier 1
# reshape/permutedims/matmul reference (src/StateVector/StateVector.jl). The
# kernels sum the same products in a different order, so the engines agree
# to rounding, not bitwise. Pinned here:
#
#   1. Kernel level: 1-site, 2-site (adjacent, non-adjacent, both argument
#      orders), the n≥3 fallback, unitary and non-unitary matrices, d = 2, 3, 4,
#      L down to 1 — max |diff| ≤ 1e-14 against Tier 1.
#   2. `:optimized` is the default engine; `:builtin` is still selectable.
#   3. Trajectory level: a Reset/HaarRandom staircase circuit (the CIPT
#      pattern, every gate type the hot loop sees) gives the same measurement
#      record and observables to 1e-12 on both engines.
#   4. The Projection fast path: `_sv_projected_norm2` equals ‖Pψ‖² of the
#      reference engine, is `nothing` for every other gate, and an accepted
#      Projection mutates ψ in place (no copy) while a rejected one leaves the
#      stored vector untouched — the same object, same contents.

using Test
using QuantumCircuitsMPS
using LinearAlgebra
using Random

const _EA_QC = QuantumCircuitsMPS

function _ea_rng(seed)
    RNGRegistry(gates_spacetime = seed, gates_realization = seed + 1,
        born_measurement = seed + 2)
end

@testset "State-vector engine agreement (:optimized vs :builtin)" begin

    # ------------------------------------------------------------------
    # 1. Kernel level, random (L, d, sites, U)
    # ------------------------------------------------------------------
    @testset "kernels match Tier 1 on random inputs" begin
        rng = MersenneTwister(2024)
        tol = 1e-14
        for (L, d) in ((1, 2), (2, 2), (3, 2), (6, 2), (8, 2), (2, 3), (5, 3), (4, 4)),
            trial in 1:10

            ψ = normalize!(randn(rng, ComplexF64, d^L))
            # 1-site, unitary
            s = rand(rng, 1:L)
            U1 = Matrix(qr(randn(rng, ComplexF64, d, d)).Q)
            ref = _EA_QC.apply_gate_sv!(ψ, U1, [s], L, d)
            got = _EA_QC.apply_gate_sv_optimized!(copy(ψ), U1, [s], L, d)
            @test maximum(abs, ref - got) <= tol
            L >= 2 || continue
            # 2-site: random pair in random order (covers adjacent, non-adjacent,
            # and the "first site = most-significant digit" convention)
            s1, s2 = randperm(rng, L)[1:2]
            U2 = Matrix(qr(randn(rng, ComplexF64, d^2, d^2)).Q)
            ref = _EA_QC.apply_gate_sv!(ψ, U2, [s1, s2], L, d)
            got = _EA_QC.apply_gate_sv_optimized!(copy(ψ), U2, [s1, s2], L, d)
            @test maximum(abs, ref - got) <= tol
            # swapping the argument order is NOT a no-op for a generic U, and
            # both engines must agree on each order
            ref_sw = _EA_QC.apply_gate_sv!(ψ, U2, [s2, s1], L, d)
            got_sw = _EA_QC.apply_gate_sv_optimized!(copy(ψ), U2, [s2, s1], L, d)
            @test maximum(abs, ref_sw - got_sw) <= tol
            # 2-site, non-unitary (a projector-like Hermitian matrix): the
            # kernel is linear algebra, not unitary-specific
            A = randn(rng, ComplexF64, d^2, d^2)
            P = A * A' / (d^2)
            ref = _EA_QC.apply_gate_sv!(ψ, P, [s1, s2], L, d)
            got = _EA_QC.apply_gate_sv_optimized!(copy(ψ), P, [s1, s2], L, d)
            @test maximum(abs, ref - got) <= tol
            L >= 3 || continue
            # n = 3 goes through the permutedims fallback: identical by construction
            ss = randperm(rng, L)[1:3]
            U3 = Matrix(qr(randn(rng, ComplexF64, d^3, d^3)).Q)
            ref = _EA_QC.apply_gate_sv!(ψ, U3, ss, L, d)
            got = _EA_QC.apply_gate_sv_optimized!(copy(ψ), U3, ss, L, d)
            @test ref == got
        end
    end

    # ------------------------------------------------------------------
    # 2. Default engine
    # ------------------------------------------------------------------
    @testset "default engine is :optimized, :builtin selectable" begin
        st = SimulationState(L = 3, bc = :open, backend = :statevector, rng = _ea_rng(1))
        @test st.backend.engine == :optimized
        st_b = SimulationState(L = 3, bc = :open, backend = :statevector,
            engine = :builtin, rng = _ea_rng(1))
        @test st_b.backend.engine == :builtin
        @test_throws ArgumentError SimulationState(L = 3, bc = :open,
            backend = :statevector, engine = :fastest, rng = _ea_rng(1))
    end

    # ------------------------------------------------------------------
    # 3. Trajectory level: CIPT-style staircase (Reset + HaarRandom), periodic
    # ------------------------------------------------------------------
    @testset "Reset/HaarRandom staircase trajectories agree" begin
        L = 8
        circuit = Circuit(L = L, bc = :periodic) do c
            apply_with_prob!(c;
                outcomes = [
                    (probability = 0.5, gate = Reset(), geometry = StaircaseLeft(1)),
                    (probability = 0.5, gate = HaarRandom(), geometry = StaircaseRight(1))
                ])
            apply_with_prob!(c; outcomes = [
                (probability = 0.2, gate = Measure(:Z), geometry = AllSites())
            ])
        end
        function run(engine, seed)
            s = SimulationState(L = L, bc = :periodic, backend = :statevector,
                engine = engine, log_events = true, rng = _ea_rng(seed))
            initialize!(s, ProductState(binary_int = 0))
            track!(s, :Mz => Magnetization(:Z))
            track!(s, :S => EntanglementEntropy(cut = L ÷ 2))
            simulate!(circuit, s; n_steps = 3L, record_when = :every_step)
            record = [(m.sites, m.outcome) for m in measurements(s)]
            return s.observables[:Mz], s.observables[:S], copy(s.backend.ψ), record
        end
        for seed in (11, 23)
            Mz_o, S_o, ψ_o, rec_o = run(:optimized, seed)
            Mz_b, S_b, ψ_b, rec_b = run(:builtin, seed)
            @test rec_o == rec_b               # same Born outcomes, same draw count
            @test length(rec_o) > 0            # non-vacuous
            @test maximum(abs, Mz_o .- Mz_b) < 1e-12
            @test maximum(abs, S_o .- S_b) < 1e-12
            @test norm(ψ_o - ψ_b) < 1e-12
            @test norm(ψ_o) ≈ 1.0 atol = 1e-12
        end
    end

    # ------------------------------------------------------------------
    # 4. Projection fast path (no copy, guard before the in-place apply)
    # ------------------------------------------------------------------
    @testset "Projection: closed-form ‖Pψ‖², in place, untouched on rejection" begin
        L = 5
        # (closure-local `s`, not `st`: an inner-function assignment to `st`
        # would bind to this testset's `st` below)
        function entangled(engine)
            s = SimulationState(L = L, bc = :open, backend = :statevector,
                engine = engine, rng = _ea_rng(3))
            initialize!(s, ProductState(binary_int = 0))
            apply!(s, HaarRandom(), Bricklayer(:odd))
            apply!(s, HaarRandom(), Bricklayer(:even))
            return s
        end
        st = entangled(:optimized)
        ref = entangled(:builtin)
        for site in 1:L, k in 0:1

            n2 = _EA_QC._sv_projected_norm2(Projection(k), st, [site])
            @test n2 isa Float64
            # the reference engine's ‖Pψ‖²: apply the projector on a copy
            Pψ = _EA_QC.apply_gate_sv!(ref.backend.ψ, _EA_QC._projection_matrix(k, 2),
                [site], L, 2)
            @test n2 ≈ norm(Pψ)^2 atol = 1e-14
        end
        # every other gate has no closed form → copy path
        for g in (Hadamard(), PauliX(), HaarRandom(), CZ(),
            SpinSectorProjection(total_spin_projector(0; s = 1 // 2)))
            @test _EA_QC._sv_projected_norm2(g, st, [1, 2]) === nothing
        end

        # accepted Projection mutates the stored vector in place: same object
        ψ_obj = st.backend.ψ
        p1 = born_probability(st, 2, 1)
        @test 0.01 < p1 < 0.99                 # genuinely stochastic site
        apply!(st, Projection(1), SingleSite(2))
        @test st.backend.ψ === ψ_obj
        @test born_probability(st, 2, 1) ≈ 1.0 atol = 1e-12
        @test norm(st.backend.ψ) ≈ 1.0 atol = 1e-12
        # ... and matches the reference engine
        apply!(ref, Projection(1), SingleSite(2))
        @test norm(st.backend.ψ - ref.backend.ψ) < 1e-12

        # rejected Projection (probability 0 now that site 2 is |1⟩): throws
        # BEFORE the kernel runs, so the stored vector is the same object
        # with the same contents
        snapshot = copy(st.backend.ψ)
        @test_throws ArgumentError apply!(st, Projection(0), SingleSite(2))
        @test st.backend.ψ === ψ_obj
        @test st.backend.ψ == snapshot
        # Reset and Measure (the hot path) go through the same fast path
        apply!(st, Reset(), SingleSite(2))
        @test st.backend.ψ === ψ_obj
        @test born_probability(st, 2, 0) ≈ 1.0 atol = 1e-12
        apply!(st, Measure(:Z), SingleSite(3))
        @test st.backend.ψ === ψ_obj
        @test norm(st.backend.ψ) ≈ 1.0 atol = 1e-12
    end
end
