# Golden comparison harness — the bit-exact pre/post-v0.1-refactor regression
# gate. KEPT deliberately (T28 decision): it is gated behind EXTENDED_TESTS=true
# in runtests.jl (not part of the default suite) and is the only check that
# pins today's engine bit-exactly against the pristine PRE-refactor goldens.
# Its companion generator, test/golden/generate_goldens.jl, is dev-only and is
# never included by runtests (see that file's header).
#
# (History: Task 1 skeleton, completed in Task 16.)
#
# Re-runs the pre-refactor golden circuits (test/golden/generate_goldens.jl,
# captured BEFORE any src/ change) on the CURRENT (post-refactor v0.1) engine
# with the exact same seeds, and compares against the pristine goldens in
# test/golden/*.json.
#
# Verdict lines printed (consumed by QA):
#   CASE-A: PASS/FAIL        single-outcome compound (MIPT)   — must be bit-exact
#   CASE-C: PASS/FAIL        K=1 categorical (CIPT staircase)  — must be bit-exact
#   CASE-D: PASS/FAIL        deterministic (Bricklayer Haar)   — must be bit-exact
#   AKLT-DEGEN: PASS/FAIL    degenerate Case B (p_nn = 1.0)    — physics bit-exact
#   AKLT-AUDIT: PASS/FAIL    event-by-event reference_select audit of the engine
#   CASEB-TEST4-AUDIT: PASS/FAIL  audit of circuit_test.jl "Test 4" Case B circuit
#
# ============================ CASE-B DIVERGENCE NOTE ==========================
# The AKLT golden is a MULTI-OUTCOME COMPOUND stochastic op (Case B in the plan's
# migration case analysis): two outcomes with geometries Bricklayer(:nn) (K=12)
# and Bricklayer(:nnn) (K=12) at L=12 PBC.
#
#   * OLD engine: independent Bernoulli loop PER OUTCOME → ΣKᵢ = 12+12 = 24
#     scalar draws from :gates_spacetime per step (288 over 12 steps).
#   * NEW unified rule: ONE categorical coin per element slot → K = 12 draws
#     per step (144 over 12 steps).
#
# Because p_nn = 1.0 the SELECTIONS are identical (every slot picks the NN
# outcome in both engines — "degenerate Case B"), so `final_entropy` and
# `string_order` reproduce BIT-EXACTLY and the born/realization/state_init
# fingerprints match the golden exactly. Only the :gates_spacetime stream is
# consumed at a different rate, so its post-run fingerprint LEGITIMATELY
# changes from the golden 0.6539347077753881 to the re-goldened value below.
# This is the sanctioned Case B consumption change (plan §Oracle review,
# verified by twin-burn proof in Task 9); it is NOT a failure, and the pristine
# pre-refactor JSON is intentionally left untouched as the historical baseline.
# The officially accepted (re-goldened) v0.1 value is pinned HERE:
const AKLT_GATES_SPACETIME_FINGERPRINT_V01 = 0.10031542999150234
# and is additionally recomputed below from first principles (burn 144 scalar
# draws off MersenneTwister(42), then draw the fingerprint) so the pin can
# never silently drift from the documented consumption contract.
# ==============================================================================

using QuantumCircuitsMPS
using QuantumCircuitsMPS: events, measurements, GateApplied
using JSON
using Random
using Test

# reference_select — the semantic oracle (test/testutils.jl, no testsets
# there). Guarded include so this file works both standalone
# (`julia --project=. test/golden_compare.jl`) and under the suite, where
# runtests.jl has already loaded testutils.jl before the EXTENDED_TESTS gate
# includes this file.
@isdefined(reference_select) || include("testutils.jl")

const GOLDEN_DIR = joinpath(@__DIR__, "golden")

load_golden(name) = JSON.parsefile(joinpath(GOLDEN_DIR, name))

"""
    compare_case(name, produced, golden; atol=1e-14) -> Bool

Compare produced values against golden values element-wise at `atol`.
`produced`/`golden` are Dicts with matching keys of scalars or Float64 vectors.
RNG fingerprints (nested Dicts) require EXACT equality.
"""
function compare_case(name::String, produced::AbstractDict, golden::AbstractDict; atol = 1e-14)
    pass = true
    for (key, gval) in golden
        key == "params" && continue
        haskey(produced, key) ||
            (println("  [$name] MISSING key: $key"); pass = false; continue)
        pval = produced[key]
        ok = if gval isa AbstractVector
            length(pval) == length(gval) &&
                all(abs.(Float64.(pval) .- Float64.(gval)) .<= atol)
        elseif gval isa AbstractDict  # rng_fingerprints: exact match required
            all(get(pval, k, NaN) == v for (k, v) in gval)
        else
            abs(Float64(pval) - Float64(gval)) <= atol
        end
        ok || (println("  [$name] MISMATCH at key: $key"); pass = false)
    end
    println("CASE-ACD-EXACT: $(pass ? "PASS" : "FAIL") ($name)")
    return pass
end

const STREAMS = [:born_measurement, :gates_realization, :gates_spacetime, :state_init]  # sorted

# Draw one Float64 from each stream AFTER the run (mutates RNGs — call last).
rng_fingerprints(registry) = Dict(String(s) => rand(get_rng(registry, s)) for s in STREAMS)

# ---------- Case A rerun: MIPT (single-outcome compound) ----------
function rerun_case_a()
    L, p, n_steps = 8, 0.15, 20
    circuit = Circuit(L = L, bc = :periodic) do c
        apply!(c, HaarRandom(), Bricklayer(:even))
        apply_with_prob!(c; outcomes = [
            (probability = p, gate = Measure(:Z), geometry = AllSites())])
        apply!(c, HaarRandom(), Bricklayer(:odd))
        apply_with_prob!(c; outcomes = [
            (probability = p, gate = Measure(:Z), geometry = AllSites())])
    end
    registry = RNGRegistry(gates_spacetime = 42, born_measurement = 1, gates_realization = 2)
    state = SimulationState(L = L, bc = :periodic, maxdim = 64, rng = registry)
    initialize!(state, ProductState(binary_int = 0))
    track!(state, :entropy => EntanglementEntropy(; cut = 4))
    simulate!(circuit, state; n_steps = n_steps, record_when = :every_step)
    Dict(
        "entropy" => Float64.(state.observables[:entropy]),
        "z_expectation" => [2 * born_probability(state, i, 0) - 1 for i in 1:L],
        "rng_fingerprints" => rng_fingerprints(registry)
    )
end

# ---------- Case C rerun: CIPT (K=1 categorical) ----------
function rerun_case_c()
    L, p_ctrl = 8, 0.5
    n_steps = 2 * L^2
    left, right = StaircaseLeft(1), StaircaseRight(1)
    circuit = Circuit(L = L, bc = :periodic, p_ctrl = p_ctrl) do c
        apply_with_prob!(c;
            outcomes = [
                (probability = c.params[:p_ctrl], gate = Reset(), geometry = left),
                (probability = 1-c.params[:p_ctrl], gate = HaarRandom(), geometry = right)])
    end
    registry = RNGRegistry(gates_spacetime = 42, born_measurement = 1, gates_realization = 2)
    state = SimulationState(L = L, bc = :periodic, maxdim = 64, rng = registry)
    initialize!(state, ProductState(binary_int = 0))
    track!(state, :Mz => Magnetization(:Z))
    simulate!(circuit, state; n_steps = n_steps, record_when = :every_gate)
    Dict(
        "Mz" => Float64.(state.observables[:Mz]),
        "rng_fingerprints" => rng_fingerprints(registry)
    )
end

# ---------- Case D rerun: deterministic Bricklayer Haar ----------
function rerun_case_d()
    L, n_steps = 8, 10
    circuit = Circuit(L = L, bc = :periodic) do c
        apply!(c, HaarRandom(), Bricklayer(:even))
        apply!(c, HaarRandom(), Bricklayer(:odd))
    end
    registry = RNGRegistry(gates_spacetime = 42, born_measurement = 1, gates_realization = 2)
    state = SimulationState(L = L, bc = :periodic, maxdim = 64, rng = registry)
    initialize!(state, ProductState(binary_int = 0))
    track!(state, :entropy => EntanglementEntropy(; cut = 4))
    simulate!(circuit, state; n_steps = n_steps, record_when = :every_step)
    Dict(
        "entropy" => Float64.(state.observables[:entropy]),
        "born_probability_0" => [born_probability(state, i, 0) for i in 1:L],
        "rng_fingerprints" => rng_fingerprints(registry)
    )
end

# ---------- AKLT rerun (degenerate Case B) + event-by-event audit ----------
function rerun_case_aklt()
    L, bc, p_nn = 12, :periodic, 1.0
    P0, P1 = total_spin_projector(0), total_spin_projector(1)
    proj_gate = SpinSectorProjection(P0 + P1)
    circuit = Circuit(L = L, bc = bc) do c
        apply_with_prob!(c;
            outcomes = [
                (probability = p_nn, gate = proj_gate, geometry = Bricklayer(:nn)),
                (probability = 1-p_nn, gate = proj_gate, geometry = Bricklayer(:nnn))])
    end
    registry = RNGRegistry(gates_spacetime = 42, gates_realization = 2, born_measurement = 3)
    state = SimulationState(
        L = L, bc = bc, site_type = "S=1", maxdim = 128, rng = registry,
        log_events = true)
    initialize!(state, ProductState(spin_state = "Z0"))
    track!(state, :entropy => EntanglementEntropy(cut = L÷2, renyi_index = 1, base = 2))
    track!(state, :string_order => StringOrder(1, L÷2+1, order = 1))
    simulate!(circuit, state; n_steps = L, record_when = :every_step)

    produced = Dict(
        "final_entropy" => Float64(state.observables[:entropy][end]),
        "string_order" => Float64(state.observables[:string_order][end]),
        "rng_fingerprints" => rng_fingerprints(registry)
    )

    # --- Event-by-event audit vs reference_select (the migration audit) ---
    # Engine coins come from :gates_spacetime = MersenneTwister(42); replay the
    # exact same categorical walk with the oracle and demand identical picks.
    K = element_count(Bricklayer(:nn), L, bc)          # 12 element slots/step
    nn_elems = elements(Bricklayer(:nn), L, bc)
    nnn_elems = elements(Bricklayer(:nnn), L, bc)
    gas = [e for e in events(state) if e isa GateApplied]
    twin = MersenneTwister(42)
    audit_ok, checked = true, 0
    for step in 1:L
        sel = reference_select(twin, [p_nn, 1 - p_nn], K)
        for (k, s) in enumerate(sel)
            s == 0 && continue           # identity remainder: no event expected
            checked += 1
            checked > length(gas) && (audit_ok = false; break)
            ev = gas[checked]
            expected_sites = s == 1 ? nn_elems[k] : nnn_elems[k]
            audit_ok &= (ev.step == step && ev.element_idx == k &&
                         ev.sites == expected_sites)
        end
    end
    audit_ok &= (checked == length(gas))   # no unexplained extra events
    return produced, audit_ok, checked
end

# ---------- Case B audit for circuit_test.jl "Test 4" (odd/even mixing) ----------
# The only other Case B instance in the pre-refactor test suite (v0.1 migration
# triage): apply_with_prob! with 2 outcomes on Bricklayer(:odd)
# and Bricklayer(:even). expand_circuit delegates to the engine's shared
# select_outcome_index (Task 15), so auditing the expansion audits the rule.
function audit_caseb_test4(; seed = 42, n_steps = 20)
    L = 8
    c = Circuit(L = L, bc = :periodic) do b
        apply_with_prob!(b;
            outcomes = [
                (probability = 0.5, gate = Measure(:Z), geometry = Bricklayer(:odd)),
                (probability = 0.5, gate = Measure(:Z), geometry = Bricklayer(:even))])
    end
    odd_e = elements(Bricklayer(:odd), L, :periodic)   # 4 pairs
    even_e = elements(Bricklayer(:even), L, :periodic)   # 4 pairs
    K = length(odd_e)
    ops = expand_circuit(c; seed = seed, n_steps = n_steps)
    twin = MersenneTwister(seed)
    ok = true
    for step in 1:n_steps
        sel = reference_select(twin, [0.5, 0.5], K)
        expected = [s == 1 ? odd_e[k] : even_e[k] for (k, s) in enumerate(sel) if s != 0]
        actual = [op.sites for op in ops[step]]
        ok &= (actual == expected)
    end
    return ok
end

# ============================== RUN + VERDICTS ================================
@testset "golden bit-exact regressions (Task 16)" begin

    # Cases A/C/D: bit-exact or it's an engine bug — NEVER re-golden these.
    okA = compare_case("case_a_mipt", rerun_case_a(), load_golden("case_a_mipt.json"))
    println("CASE-A: ", okA ? "PASS" : "FAIL")
    @test okA

    okC = compare_case("case_c_cipt", rerun_case_c(), load_golden("case_c_cipt.json"))
    println("CASE-C: ", okC ? "PASS" : "FAIL")
    @test okC

    okD = compare_case("case_d_haar", rerun_case_d(), load_golden("case_d_haar.json"))
    println("CASE-D: ", okD ? "PASS" : "FAIL")
    @test okD

    # AKLT (degenerate Case B): physics + 3 fingerprints bit-exact vs golden;
    # gates_spacetime fingerprint compared against the RE-GOLDENED v0.1 value.
    golden_aklt = load_golden("case_aklt_pnn1.json")
    produced, audit_ok, n_audited = rerun_case_aklt()

    phys_ok = abs(produced["final_entropy"] - golden_aklt["final_entropy"]) <= 1e-14 &&
              abs(produced["string_order"] - golden_aklt["string_order"]) <= 1e-14
    fps_ok = all(produced["rng_fingerprints"][k] == golden_aklt["rng_fingerprints"][k]
    for k in ("born_measurement", "gates_realization", "state_init"))

    # Recompute the expected v0.1 gates_spacetime fingerprint from the RNG
    # contract: 12 steps × K=12 slots × 1 scalar coin = 144 draws, then the
    # fingerprint draw. (Old engine: 12 × ΣKᵢ=24 = 288 draws → 0.6539347077753881.)
    burn = MersenneTwister(42)
    for _ in 1:144
        ;
        rand(burn);
    end
    expected_fp = rand(burn)
    fp_new = produced["rng_fingerprints"]["gates_spacetime"]
    fp_ok = (fp_new == AKLT_GATES_SPACETIME_FINGERPRINT_V01) && (fp_new == expected_fp)

    okAKLT = phys_ok && fps_ok && fp_ok
    println("AKLT final_entropy / string_order vs pre-refactor golden: ",
        phys_ok ? "bit-exact (atol=1e-14)" : "MISMATCH")
    println("AKLT born/realization/state_init fingerprints vs golden: ",
        fps_ok ? "exact" : "MISMATCH")
    println("AKLT gates_spacetime fingerprint: $(fp_new)")
    println("  golden (old engine, ΣKᵢ=24 coins/step): $(golden_aklt["rng_fingerprints"]["gates_spacetime"])")
    println("  re-goldened v0.1 (unified rule, K=12 coins/step): $(AKLT_GATES_SPACETIME_FINGERPRINT_V01)")
    println("  → divergence is the SANCTIONED Case B consumption change (see header note);")
    println("    selections audit-verified against reference_select below — NOT a failure.")
    println("AKLT-DEGEN: ", okAKLT ? "PASS" : "FAIL")
    @test okAKLT

    println("AKLT-AUDIT: ", audit_ok ? "PASS" : "FAIL",
        " ($(n_audited)/144 engine selections match reference_select event-by-event)")
    @test audit_ok
    @test n_audited == 144

    okT4 = audit_caseb_test4()
    println("CASEB-TEST4-AUDIT: ", okT4 ? "PASS" : "FAIL",
        " (circuit_test.jl Test 4 odd/even mixing: expansion matches reference_select, 20 steps)")
    @test okT4
end
