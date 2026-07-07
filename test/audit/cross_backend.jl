# test/audit/cross_backend.jl
# ═══════════════════════════════════════════════════════════════════════════
# T11 AUDIT: Cross-backend trajectory equivalence suite
# ═══════════════════════════════════════════════════════════════════════════
#
# This suite is THE regression guard for all Wave-5 efficiency work: it pins
# full seeded TRAJECTORIES (not just final values) across the MPS,
# state-vector, and Clifford backends. It complements (does not duplicate):
#   - test/statevector/cross_validation.jl  — per-gate state-level parity
#   - test/clifford/cross_validation.jl     — eager-apply! Clifford parity
#   - test/gates/test_new_gates.jl          — per-gate born_probability checks
# by exercising the full Circuit-builder → simulate! → track!/record! path.
#
# Scenarios (per plan T11):
#   (a) MIPT circuit (Haar + stochastic measure), MPS vs SV trajectory parity
#   (b) Clifford circuit (RandomClifford + Measure), Clifford vs SV vs MPS
#   (c) S=1 AKLT projection protocol, MPS vs SV  [closes the known S=1 gap]
#   (d) CIPT feedback circuit (Reset staircase), MPS vs SV Mz trajectory
#   (e) same-seed determinism: identical reruns are bitwise identical
#
# ── AUDIT VERDICT SUMMARY (2026-07-07, Julia 1.12.6) ────────────────────────
# 1. MPS-vs-SV parity is TOLERANCE-LEVEL, NOT bitwise: same seeds produce the
#    same measurement outcomes and the same trajectory branch, but observables
#    differ at float-roundoff level (max |Δ| ≈ 3e-15; different contraction
#    orders). The README's "bit-identical trajectories" claim is therefore
#    REFUTED in the strict bitwise sense — encoded below as @test_broken.
#    (Same-BACKEND same-seed reruns ARE bitwise identical — scenario (e).)
# 2. FINDING (FIXED in T17): SpinSectorProjection was BROKEN on the SV
#    backend — `gate_matrix(::SpinSectorProjection)` had no method, so the SV
#    `_apply_single!` path (src/StateVector/StateVector.jl:59) threw a
#    MethodError. T17 added the method (src/Gates/spin_measurement.jl); the
#    S=1 MPS-vs-SV cross-check below additionally validates the equivalent
#    MatrixGate(P01) + renormalize route against MPS.
# 3. FINDING: the Clifford backend VIOLATES the one-Born-draw-per-measurement
#    contract (src/Core/apply.jl:105-106): Core `_measure_single_site!`
#    always consumes exactly one `:born_measurement` draw, while the Clifford
#    override (src/Clifford/measurement.jl:59-72) consumes a draw ONLY for
#    undetermined outcomes. After the first deterministic measurement the
#    stream positions diverge, so subsequent random outcomes differ from
#    MPS/SV under the same seed. Entropy trajectories still agree exactly
#    (Pauli-frame invariant), but outcome sequences and Mz trajectories do
#    not. Encoded as @test_broken.
# ─────────────────────────────────────────────────────────────────────────────

using Test
using QuantumCircuitsMPS
using LinearAlgebra

const _CB_QCM = QuantumCircuitsMPS

# ── Shared circuit runners (prefixed _cb_ — runtests.jl includes all test
#    files into one shared scope; avoid name collisions) ─────────────────────

# Scenario (a)/(e): MIPT — Haar bricklayers + stochastic Z measurement.
# bc=:open deliberately: under PBC the MPS `cut` is a RAM-bond index of the
# folded chain, which for a generic circuit need not be the same physical
# bipartition as the SV prefix cut. Open BC removes that confound so any
# mismatch here is a genuine backend-parity failure, not a cut-semantics one.
# (PBC cut alignment is separately covered by
# test/statevector/cross_validation.jl "PBC EntanglementEntropy".)
function _cb_run_mipt(backend; L = 6, n_steps = 10, p = 0.15)
    circuit = Circuit(L = L, bc = :open) do c
        apply!(c, HaarRandom(), Bricklayer(:even))
        apply_with_prob!(c;
            outcomes = [(probability = p, gate = Measure(:Z), geometry = AllSites())])
        apply!(c, HaarRandom(), Bricklayer(:odd))
        apply_with_prob!(c;
            outcomes = [(probability = p, gate = Measure(:Z), geometry = AllSites())])
    end
    kwargs = backend == :mps ? (maxdim = 256,) : (backend = backend,)
    state = SimulationState(; L = L, bc = :open, kwargs...,
        rng = RNGRegistry(gates_spacetime = 42, gates_realization = 7, born_measurement = 99))
    initialize!(state, ProductState(binary_int = 0))
    track!(state, :S => EntanglementEntropy(cut = L ÷ 2))
    track!(state, :Mz => Magnetization(:Z))
    simulate!(circuit, state; n_steps = n_steps, record_when = :every_step)
    return state.observables[:S], state.observables[:Mz]
end

# Scenario (b)/(e): Clifford-compatible MIPT — RandomClifford bricklayers +
# stochastic Z measurement, via the Circuit-builder/simulate! path.
function _cb_run_clifford_mipt(backend; L = 6, n_steps = 6, p = 0.3)
    circuit = Circuit(L = L, bc = :open) do c
        apply!(c, RandomClifford(2), Bricklayer(:odd))
        apply!(c, RandomClifford(2), Bricklayer(:even))
        apply_with_prob!(c;
            outcomes = [(probability = p, gate = Measure(:Z), geometry = AllSites())])
    end
    kwargs = backend == :mps ? (maxdim = 256,) : (backend = backend,)
    state = SimulationState(; L = L, bc = :open, kwargs..., log_events = true,
        rng = RNGRegistry(gates_spacetime = 17, gates_realization = 23, born_measurement = 5))
    initialize!(state, ProductState(binary_int = 0))
    track!(state, :S => EntanglementEntropy(cut = L ÷ 2))
    track!(state, :Mz => Magnetization(:Z))
    simulate!(circuit, state; n_steps = n_steps, record_when = :every_step)
    born = [born_probability(state, s, 0) for s in 1:L]
    return state, born
end

# Scenario (d): CIPT — Reset (measure + feedback) staircase vs Haar staircase.
# NOTE: StaircaseLeft/StaircaseRight are MUTABLE geometries (they advance as
# the circuit runs), so each backend gets a FRESH Circuit. bc=:periodic is
# safe here: only Magnetization is compared (no entropy cut involved).
function _cb_run_cipt(backend; L = 6, n_steps = 20, p_ctrl = 0.5)
    circuit = Circuit(L = L, bc = :periodic, p_ctrl = p_ctrl) do c
        apply_with_prob!(c;
            outcomes = [
                (probability = c.params[:p_ctrl], gate = Reset(),
                    geometry = StaircaseLeft(1)),
                (probability = 1 - c.params[:p_ctrl], gate = HaarRandom(),
                    geometry = StaircaseRight(1))
            ])
    end
    kwargs = backend == :mps ? (maxdim = 256,) : (backend = backend,)
    state = SimulationState(; L = L, bc = :periodic, kwargs...,
        rng = RNGRegistry(gates_spacetime = 11, gates_realization = 22, born_measurement = 33))
    initialize!(state, ProductState(binary_int = 0))
    track!(state, :Mz => Magnetization(:Z))
    simulate!(circuit, state; n_steps = n_steps, record_when = :every_step)
    return state.observables[:Mz]
end

@testset "AUDIT: cross-backend trajectory equivalence" begin

    # ═══════════════════════════════════════════════════════════════════════
    # (a) MIPT: MPS(maxdim=256) vs SV — Magnetization + EntanglementEntropy
    #     trajectories over 10 seeded steps.
    # ═══════════════════════════════════════════════════════════════════════
    @testset "(a) MIPT MPS-vs-SV trajectory parity" begin
        S_mps, Mz_mps = _cb_run_mipt(:mps)
        S_sv, Mz_sv = _cb_run_mipt(:statevector)

        @test length(S_mps) == length(S_sv) == 10
        # Tolerance-level parity (measured max |Δ| ≈ 3e-15, well inside 1e-10)
        @test maximum(abs.(S_mps .- S_sv)) ≤ 1e-10
        @test maximum(abs.(Mz_mps .- Mz_sv)) ≤ 1e-10
        # Guard against trivially-passing all-zero trajectories
        @test maximum(S_mps) > 0.01
        @test maximum(S_sv) > 0.01

        # FINDING (README claim REFUTED): parity is NOT bitwise — observables
        # differ at float-roundoff level (~3e-15) from differing contraction
        # orders, even though the trajectory branch (measurement outcomes) is
        # identical. README's "bit-identical trajectories across backends"
        # wording must be corrected in T31. Do NOT "fix" this by weakening —
        # if these ever become bitwise-equal, flip @test_broken → @test.
        @test_broken S_mps == S_sv
        @test_broken Mz_mps == Mz_sv
    end

    # ═══════════════════════════════════════════════════════════════════════
    # (b) Clifford circuit: Clifford vs SV vs MPS agreement.
    # ═══════════════════════════════════════════════════════════════════════
    @testset "(b) Clifford-vs-SV-vs-MPS agreement" begin
        st_mps, born_mps = _cb_run_clifford_mipt(:mps)
        st_sv, born_sv = _cb_run_clifford_mipt(:statevector)
        st_cl, born_cl = _cb_run_clifford_mipt(:clifford)

        S_mps, S_sv, S_cl = (st.observables[:S] for st in (st_mps, st_sv, st_cl))
        Mz_mps, Mz_sv, Mz_cl = (st.observables[:Mz] for st in (st_mps, st_sv, st_cl))

        # Entropy trajectories agree across ALL THREE backends. For stabilizer
        # circuits entanglement is invariant under the Pauli-frame difference
        # induced by divergent measurement outcomes (see finding below), so
        # this holds exactly even though outcome sequences diverge.
        @test maximum(abs.(S_mps .- S_sv)) ≤ 1e-10
        @test maximum(abs.(S_mps .- S_cl)) ≤ 1e-10
        @test maximum(abs.(S_sv .- S_cl)) ≤ 1e-10
        @test maximum(S_cl) > 0.01   # non-trivial trajectory guard

        # MPS vs SV: full agreement (Mz trajectory, final Born, outcomes)
        @test maximum(abs.(Mz_mps .- Mz_sv)) ≤ 1e-10
        @test maximum(abs.(born_mps .- born_sv)) ≤ 1e-10

        m_mps = _CB_QCM.measurements(st_mps)
        m_sv = _CB_QCM.measurements(st_sv)
        m_cl = _CB_QCM.measurements(st_cl)
        @test length(m_mps) == length(m_sv) == length(m_cl)
        @test [m.outcome for m in m_mps] == [m.outcome for m in m_sv]
        # The `:gates_spacetime` coin stream is shared correctly by all three
        # backends: the measured-site sequence is identical everywhere.
        @test [m.sites for m in m_mps] == [m.sites for m in m_sv] ==
              [m.sites for m in m_cl]

        # FINDING: Clifford violates the one-Born-draw-per-measurement
        # contract (src/Core/apply.jl:105-106 always draws; the Clifford
        # override src/Clifford/measurement.jl:59-72 draws ONLY when the
        # outcome is undetermined). After the first deterministic measurement
        # the `:born_measurement` stream positions drift, so random outcomes
        # diverge from MPS/SV under the same seed (with these pinned seeds:
        # measurements #6, #8, #9 flip), and the Mz trajectory differs by
        # O(1/L) at intermediate steps. Final Born probabilities happen to
        # re-converge for these seeds; that is NOT guaranteed in general.
        # T17: deliberately NOT fixed — genuine design question; see the
        # "DECISION NEEDED: Clifford Born-draw-count contract" block in
        # .sisyphus/notepads/v04-findings.md and the note in
        # src/Clifford/measurement.jl. These stay @test_broken until decided.
        @test_broken [m.outcome for m in m_mps] == [m.outcome for m in m_cl]
        @test_broken maximum(abs.(Mz_mps .- Mz_cl)) ≤ 1e-10
    end

    # ═══════════════════════════════════════════════════════════════════════
    # (c) S=1 AKLT: MPS vs SV — closes the known S=1 cross-backend gap.
    #     L=6 open, 10 projection steps (P0+P1 on every NN bond per step),
    #     compare StringOrder + EntanglementEntropy at ±1e-8.
    # ═══════════════════════════════════════════════════════════════════════
    @testset "(c) S=1 AKLT MPS-vs-SV" begin
        L = 6
        n_steps = 10
        P01 = total_spin_projector(0) + total_spin_projector(1)

        # cutoff=1e-16: with the DEFAULT cutoff (1e-10) the SpinSectorProjection
        # path (needs_normalization=true → normalize + truncate! per apply)
        # accumulates ~6.6e-8 of truncation error over the 50 projections,
        # which is truncation noise, not a backend discrepancy (max bond dim
        # here is 3^3 = 27 < maxdim, so maxdim never truncates). A tight
        # cutoff makes the ±1e-8 tolerance test PHYSICS, not truncation.
        _make_s1(backend) = begin
            kwargs = backend == :mps ? (maxdim = 64, cutoff = 1e-16) :
                     (backend = backend,)
            s = SimulationState(; L = L, bc = :open, site_type = "S=1", kwargs...,
                rng = RNGRegistry(
                    gates_spacetime = 1, gates_realization = 2, born_measurement = 3))
            initialize!(s, ProductState(spin_state = "Z0"))
            s
        end

        # FINDING (fixed in T17): SpinSectorProjection had NO gate_matrix
        # method, so the SV backend could not apply it —
        # `_resolve_gate_matrix_sv` (fallback `gate_matrix(gate)`,
        # src/StateVector/StateVector.jl:59) threw a MethodError. T17 added
        # `gate_matrix(::SpinSectorProjection)` (src/Gates/spin_measurement.jl),
        # so the README AKLT Quick Start now runs on backend=:statevector.
        sv_ssp_works = try
            s = _make_s1(:statevector)
            apply!(s, SpinSectorProjection(P01), [1, 2])
            true
        catch
            false
        end
        @test sv_ssp_works

        # Gap closure via an EQUIVALENT protocol both backends support:
        # the same 9×9 projector applied as MatrixGate(P01) + explicit
        # renormalization (MatrixGate assumes unitarity and skips the
        # normalize step that SpinSectorProjection's trait provides).
        mg = MatrixGate(P01)

        # (c1) MPS reference via the REAL SpinSectorProjection gate
        mps_ssp = _make_s1(:mps)
        proj = SpinSectorProjection(P01)
        for step in 1:n_steps, i in 1:(L - 1)
            apply!(mps_ssp, proj, [i, i + 1])
        end

        # (c2) MPS via the MatrixGate workaround (validates the workaround)
        mps_mg = _make_s1(:mps)
        for step in 1:n_steps, i in 1:(L - 1)
            apply!(mps_mg, mg, [i, i + 1])
            mps_mg.mps = mps_mg.mps / norm(mps_mg.mps)
        end

        # (c3) SV via the MatrixGate workaround
        sv_mg = _make_s1(:statevector)
        for step in 1:n_steps, i in 1:(L - 1)
            apply!(sv_mg, mg, [i, i + 1])
            normalize!(sv_mg.backend.ψ)
        end

        so = StringOrder(1, L ÷ 2 + 1)
        ee = EntanglementEntropy(cut = L ÷ 2)

        so_ssp, so_mps, so_sv = so(mps_ssp), so(mps_mg), so(sv_mg)
        ee_ssp, ee_mps, ee_sv = ee(mps_ssp), ee(mps_mg), ee(sv_mg)

        # Workaround ≡ real gate on MPS (internal consistency)
        @test so_mps ≈ so_ssp atol=1e-8
        @test ee_mps ≈ ee_ssp atol=1e-8

        # THE gap-closing cross-check: S=1 StringOrder + EntanglementEntropy
        # agree between MPS and SV for the identical projection protocol.
        @test so_sv ≈ so_mps atol=1e-8
        @test ee_sv ≈ ee_mps atol=1e-8
        @test so_sv ≈ so_ssp atol=1e-8
        @test ee_sv ≈ ee_ssp atol=1e-8

        # Physics guard: protocol actually converged toward AKLT
        # (|O¹| → 4/9 ≈ 0.444; open-BC L=6 sits within a few % of it)
        @test abs(abs(so_ssp) - 4 / 9) < 0.05
        @test ee_ssp > 0.5
    end

    # ═══════════════════════════════════════════════════════════════════════
    # (d) CIPT feedback circuit: Reset staircase, MPS vs SV Mz trajectory.
    # ═══════════════════════════════════════════════════════════════════════
    @testset "(d) CIPT feedback MPS-vs-SV Mz trajectory" begin
        Mz_mps = _cb_run_cipt(:mps)
        Mz_sv = _cb_run_cipt(:statevector)

        @test length(Mz_mps) == length(Mz_sv) == 20
        # "Identical" at float-roundoff level (measured max |Δ| ≈ 1e-15)
        @test maximum(abs.(Mz_mps .- Mz_sv)) ≤ 1e-10
        # Non-trivial trajectory guard: Reset/Haar competition moved Mz
        @test maximum(abs.(Mz_mps)) > 0.01
        # FINDING (same as (a)): tolerance-level, not bitwise
        @test_broken Mz_mps == Mz_sv
    end

    # ═══════════════════════════════════════════════════════════════════════
    # (e) Same-seed determinism: rerunning the SAME scenario on the SAME
    #     backend is BITWISE identical. (The reproducibility contract that
    #     DOES hold — per backend, not across backends.)
    # ═══════════════════════════════════════════════════════════════════════
    @testset "(e) same-seed determinism (bitwise)" begin
        for backend in (:mps, :statevector)
            S1, Mz1 = _cb_run_mipt(backend)
            S2, Mz2 = _cb_run_mipt(backend)
            @test S1 == S2      # bitwise
            @test Mz1 == Mz2    # bitwise
        end
        # Clifford backend: full rerun of scenario (b) is bitwise identical
        st1, born1 = _cb_run_clifford_mipt(:clifford)
        st2, born2 = _cb_run_clifford_mipt(:clifford)
        @test st1.observables[:S] == st2.observables[:S]
        @test st1.observables[:Mz] == st2.observables[:Mz]
        @test born1 == born2
        @test [m.outcome for m in _CB_QCM.measurements(st1)] ==
              [m.outcome for m in _CB_QCM.measurements(st2)]
    end
end
