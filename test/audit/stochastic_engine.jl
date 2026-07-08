# === AUDIT (T10, plan industry-standard-v0.4.md): stochastic engine + RNG streams ===
#
# Line-by-line review targets (audited 2026-07, release/v0.4.0):
#   src/API/probabilistic.jl   — eager path: validation (Σp≤1, equal-K,
#                                staircase guard, removed rng= kwarg) BEFORE any
#                                draw/mutation; per-element coin from
#                                :gates_spacetime via select_outcome_index
#   src/Circuit/execute.jl     — builder path: select_outcome_index (single
#                                source of truth, cumsum snapping @1e-10),
#                                record_when policy matrix, structural step
#                                boundary, data-independent gate_idx counter
#   src/Circuit/draws.jl       — expected_draws: K per stochastic op per step
#                                (broadcast: element_count; set: K=1)
#   src/Core/rng.jl            — RNGRegistry named streams, scalar-draw
#                                contract, SentinelRNG feedback guard,
#                                ct_compat aliasing exemption
# AUDIT VERDICT: no discrepancy found between implementation, docstrings, and
# the README "Unified Stochastic Rule" contract. Findings: none.
#
# Plan checklist (a)-(f) — coverage map (existing coverage NOT duplicated):
#   (a) exclusivity invariant (Σp=1 → every element EXACTLY one gate)
#         single-seed/single-step version: test/unified_rule_engine.jl:192
#         ("QA: per-bond exclusive gate choice"); THIS FILE adds the
#         multi-seed, multi-step event-log verification the plan requires.
#   (b) statistical frequency at ENGINE level (p=0.3 over N=2000 elements)
#         oracle-level only in test/reference_rule.jl:55 (10^5 draws on
#         reference_select); THIS FILE adds the engine-level check.
#   (c) eager ≡ builder identical trajectories — ALREADY COVERED:
#         test/eager_probabilistic.jl:143 ("lazy/eager equivalence: MIPT
#         step", entropy match ≤1e-14 + all-stream sync) and
#         test/eager_probabilistic.jl:186 (CIPT staircase, Σp=1, sync +
#         advance). Not duplicated here.
#   (d) expected_draws == actual draws consumed — ALREADY COVERED:
#         test/rng.jl:168-270 (MIPT / deterministic / CIPT staircase /
#         SRN EachSite + engine twin-replay), test/unified_rule_engine.jl:230
#         (multi-outcome compound), test/cross_cutting.jl:119
#         (heterogeneous det+stochastic+staircase circuit, twin burn), and
#         test/gates_api.jl:443-470 (ProductGate: expected_draws == n_steps
#         AND twin-verified actual consumption). Not duplicated here.
#   (e) stream isolation — draw-COUNT invariance is covered
#         (test/unified_rule_engine.jl:210, test/cross_cutting.jl:160);
#         THIS FILE adds the gate-PLACEMENT fingerprint checks: full
#         GateApplied event-sequence invariance under :born_measurement and
#         :gates_realization seed changes, plus the vice-versa direction
#         (measurement outcomes invariant under :gates_spacetime seed change
#         when placement is deterministic).
#   (f) identity remainder statistics (Σp=0.4 → ~60% untouched, event log)
#         — not previously covered at engine level; added here.

using Test
using Random
using QuantumCircuitsMPS
using QuantumCircuitsMPS: events, measurements
using QuantumCircuitsMPS: GateApplied  # internal (not in public manifest)

function _se_state(L; bc = :periodic, st = 42, born = 1, real = 2,
        log_events = true, maxdim = 32)
    state = SimulationState(L = L, bc = bc, maxdim = maxdim,
        rng = RNGRegistry(gates_spacetime = st, born_measurement = born,
            gates_realization = real),
        log_events = log_events)
    initialize!(state, ProductState(binary_int = 0))
    return state
end

# Gate-placement fingerprint: the full ordered GateApplied event sequence.
_se_fingerprint(state) = [(e.step, e.op_idx, e.element_idx, e.gate_label, e.sites)
                          for e in events(state) if e isa GateApplied]

@testset "AUDIT: stochastic engine + RNG stream discipline" begin

    # -----------------------------------------------------------------------
    # (a) EXCLUSIVITY: Σp = 1 → every element gets EXACTLY one gate — never
    # 0, never 2 — verified from the event log over several seeds and steps.
    # -----------------------------------------------------------------------
    @testset "(a) exclusivity: Σp=1, every bond exactly one gate (5 seeds)" begin
        L, n_steps = 8, 5
        bonds = elements(Bricklayer(:even), L, :periodic)
        K = length(bonds)
        for seed in (11, 22, 33, 44, 55)
            circuit = Circuit(L = L, bc = :periodic) do c
                apply_with_prob!(c;
                    outcomes = [
                        (probability = 0.5, gate = HaarRandom(),
                            geometry = Bricklayer(:even)),
                        (probability = 0.5, gate = CZ(),
                            geometry = Bricklayer(:even))
                    ])
            end
            state = _se_state(L; st = seed)
            simulate!(circuit, state; n_steps = n_steps, record_when = :final_only)
            evs = [e for e in events(state) if e isa GateApplied]
            # Exactly one event per (step, element) slot: never 0, never 2.
            slot_counts = Dict{Tuple{Int, Int}, Int}()
            for e in evs
                slot_counts[(e.step, e.element_idx)] =
                    get(slot_counts, (e.step, e.element_idx), 0) + 1
            end
            @test length(evs) == K * n_steps
            @test all(step -> all(k -> get(slot_counts, (step, k), 0) == 1, 1:K),
                1:n_steps)
            @test all(e -> e.gate_label in ("Haar", "CZ"), evs)
            @test all(e -> e.sites == bonds[e.element_idx], evs)
        end
    end

    # -----------------------------------------------------------------------
    # (b) STATISTICAL: engine-level selection frequency. p = 0.3 single
    # outcome over N = 2000 element slots → applied fraction within 3σ of
    # 0.3 (fixed seed → deterministic; σ = sqrt(p(1-p)/N) ≈ 0.0102).
    # -----------------------------------------------------------------------
    @testset "(b) statistical: p=0.3 over N=2000 elements within 3σ" begin
        L, n_steps = 10, 200
        p = 0.3
        N = L * n_steps
        circuit = Circuit(L = L, bc = :open) do c
            apply_with_prob!(c; outcomes = [
                (probability = p, gate = PauliX(), geometry = EachSite(1:L))
            ])
        end
        state = _se_state(L; bc = :open, st = 2024)
        simulate!(circuit, state; n_steps = n_steps, record_when = :final_only)
        n_applied = count(e -> e isa GateApplied, events(state))
        freq = n_applied / N
        sigma = sqrt(p * (1 - p) / N)
        @test abs(freq - p) < 3 * sigma
    end

    # -----------------------------------------------------------------------
    # (e) STREAM ISOLATION — gate-placement fingerprints. Placement coins
    # come ONLY from :gates_spacetime: changing the :born_measurement or
    # :gates_realization seed must leave the full GateApplied event sequence
    # (step, op_idx, element_idx, label, sites) bit-identical; changing the
    # :gates_spacetime seed must change it (sanity direction).
    # -----------------------------------------------------------------------
    @testset "(e) isolation: born/realization seeds do not move gate placement" begin
        L, n_steps, p = 6, 5, 0.3
        make_circuit() = Circuit(L = L, bc = :periodic) do c
            apply!(c, HaarRandom(), Bricklayer(:even))
            apply_with_prob!(c; outcomes = [
                (probability = p, gate = Measure(:Z), geometry = AllSites())
            ])
            apply!(c, HaarRandom(), Bricklayer(:odd))
            apply_with_prob!(c; outcomes = [
                (probability = p, gate = Measure(:Z), geometry = AllSites())
            ])
        end

        run_fp(; st = 42, born = 1, real = 2) = begin
            state = _se_state(L; st = st, born = born, real = real)
            simulate!(make_circuit(), state; n_steps = n_steps,
                record_when = :final_only)
            _se_fingerprint(state)
        end

        fp_base = run_fp()
        @test !isempty(fp_base)
        # Changing the Born seed: identical placements (only outcomes differ)
        @test run_fp(born = 777) == fp_base
        # Changing the Haar-realization seed: identical placements
        @test run_fp(real = 888) == fp_base
        # Sanity: the placement stream itself DOES control placement
        @test run_fp(st = 999) != fp_base
    end

    @testset "(e) isolation vice-versa: gates_spacetime seed does not move Born outcomes" begin
        # Deterministic placement (Σp = 1): every site measured every step.
        # Outcomes are drawn ONLY from :born_measurement, so changing the
        # :gates_spacetime seed must leave the outcome sequence identical.
        L, n_steps = 6, 4
        make_circuit() = Circuit(L = L, bc = :open) do c
            apply!(c, Hadamard(), AllSites())
            apply_with_prob!(c; outcomes = [
                (probability = 1.0, gate = Measure(:Z), geometry = AllSites())
            ])
        end
        run_outcomes(; st = 42, born = 1) = begin
            state = _se_state(L; bc = :open, st = st, born = born)
            simulate!(make_circuit(), state; n_steps = n_steps,
                record_when = :final_only)
            [(m.step, m.sites, m.outcome) for m in measurements(state)]
        end
        out_base = run_outcomes()
        @test length(out_base) == L * n_steps
        @test run_outcomes(st = 999) == out_base          # isolation
        @test run_outcomes(born = 777) != out_base        # sanity: born controls outcomes
    end

    # -----------------------------------------------------------------------
    # (f) IDENTITY REMAINDER: Σp = 0.4 → ≈60% of element slots untouched
    # (event log), each selected outcome at its own frequency, and no slot
    # ever receives two gates.
    # -----------------------------------------------------------------------
    @testset "(f) identity remainder: Σp=0.4 → ~60% untouched (3σ)" begin
        L, n_steps = 10, 200
        p1, p2 = 0.25, 0.15            # Σp = 0.4 → identity remainder 0.6
        N = L * n_steps
        circuit = Circuit(L = L, bc = :open) do c
            apply_with_prob!(c;
                outcomes = [
                    (probability = p1, gate = PauliX(), geometry = EachSite(1:L)),
                    (probability = p2, gate = PauliZ(), geometry = EachSite(1:L))
                ])
        end
        state = _se_state(L; bc = :open, st = 7)
        simulate!(circuit, state; n_steps = n_steps, record_when = :final_only)
        evs = [e for e in events(state) if e isa GateApplied]
        # Exclusivity even under Σp < 1: at most one gate per slot
        slots = Set{Tuple{Int, Int}}()
        for e in evs
            @test (e.step, e.element_idx) ∉ slots
            push!(slots, (e.step, e.element_idx))
        end
        n_x = count(e -> e.gate_label == "X", evs)
        n_z = count(e -> e.gate_label == "Z", evs)
        @test n_x + n_z == length(evs)
        untouched = 1 - length(evs) / N
        for (freq, p) in ((untouched, 1 - p1 - p2), (n_x / N, p1), (n_z / N, p2))
            sigma = sqrt(p * (1 - p) / N)
            @test abs(freq - p) < 3 * sigma
        end
    end
end

println("AUDIT stochastic_engine: PASS")
