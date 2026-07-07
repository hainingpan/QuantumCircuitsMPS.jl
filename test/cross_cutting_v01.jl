# === Task 17: cross-cutting invariant + integration tests ===
# Fills the gaps NOT owned by earlier task test files (see plan §17 and the
# Metis acceptance-criteria inventory). Grep markers for the Metis audit:
#   THREAD-SAFETY, DRAW-COUNT, EVENT-LOG, EQUAL-K, SENTINEL
# (STUB lives in test/legacy_removal.jl; the golden gate in golden_compare.jl.)
#
# Deliberately NOT duplicated here (already covered elsewhere):
#   * builder/eager equal-K + Σp>1 + staircase-guard basics
#       → unified_rule_engine.jl (builder), eager_probabilistic.jl (eager)
#   * marker-as-last-op :marks no-double-record → recording_v01.jl:185
#   * all 12 deprecation stubs w/ migration text → legacy_removal.jl ("STUB:")
#   * eager-path sentinel (apply! + feedback)    → feedback.jl:149
#   * homogeneous-circuit draw counts            → rng_v01.jl, unified_rule_engine.jl

using Test
using Random
using QuantumCircuitsMPS
using QuantumCircuitsMPS: events, measurements            # ITensorMPS also exports `measurements`
using QuantumCircuitsMPS: GateApplied, MeasurementOutcome # internal since Task 14

# reference_select — the semantic oracle (Task 7); guarded include (the suite
# already loads it via unified_rule_engine.jl / golden_compare.jl).
if !@isdefined(reference_select)
    include("reference_rule.jl")
end

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# CIPT-style staircase circuit: mutable geometries make this the stress test
# for per-trajectory circuit isolation (staircase positions are circuit state).
function _cc_cipt_circuit(L)
    left, right = StaircaseLeft(1), StaircaseRight(1)
    Circuit(L = L, bc = :periodic) do c
        apply_with_prob!(c;
            outcomes = [
                (probability = 0.5, gate = Reset(), geometry = left),
                (probability = 0.5, gate = HaarRandom(), geometry = right)
            ])
    end
end

function _cc_cipt_trajectory(circuit_master, seed; L = 6, n_steps = 72)
    # copy(circuit) = the documented per-trajectory pattern (Task 9):
    # private staircase state, intra-circuit aliasing preserved.
    local_circuit = copy(circuit_master)
    registry = RNGRegistry(gates_spacetime = 3 * (seed - 1) + 1,
        born_measurement = 3 * (seed - 1) + 2,
        gates_realization = 3 * (seed - 1) + 3)
    state = SimulationState(L = L, bc = :periodic, maxdim = 32, rng = registry)
    initialize!(state, ProductState(binary_int = 0))
    track!(state, :Mz => Magnetization(:Z))
    simulate!(local_circuit, state; n_steps = n_steps, record_when = :every_gate)
    return Float64.(state.observables[:Mz])
end

@testset "Cross-cutting invariants (Task 17)" begin

    # -----------------------------------------------------------------------
    # THREAD-SAFETY: parallel copy(circuit) trajectories == sequential rerun.
    # Meaningful parallelism requires JULIA_NUM_THREADS > 1 (the suite gate
    # runs with 2); under 1 thread the equality check still exercises the
    # copy(circuit) isolation, and the parallelism assertion is skipped
    # (guarded on Threads.nthreads(), never hardcoding a thread count).
    # -----------------------------------------------------------------------
    @testset "THREAD-SAFETY: parallel == sequential, 8 seeds, CIPT staircase" begin
        L, n_steps = 6, 72
        seeds = collect(101:108)
        master = _cc_cipt_circuit(L)

        # Sequential reference (fresh copy per trajectory, same seeds)
        sequential = [_cc_cipt_trajectory(master, s; L = L, n_steps = n_steps)
                      for s in seeds]

        # Parallel run. :static schedule → deterministic seed→thread
        # partition, so with nthreads()>1 distinct threads are guaranteed
        # (no timing assumptions).
        parallel = Vector{Vector{Float64}}(undef, length(seeds))
        tids = zeros(Int, length(seeds))
        Threads.@threads :static for i in eachindex(seeds)
            tids[i] = Threads.threadid()
            parallel[i] = _cc_cipt_trajectory(master, seeds[i]; L = L, n_steps = n_steps)
        end

        # Bit-exact equality per seed (same RNG streams → identical floats)
        for i in eachindex(seeds)
            @test parallel[i] == sequential[i]
            @test length(parallel[i]) == n_steps
        end
        # Trajectories are not all identical to each other (seeds matter)
        @test length(unique(parallel)) > 1

        # Master circuit's staircases were never advanced by any trajectory
        for op in master.operations, out in op.outcomes

            @test QuantumCircuitsMPS.current_position(out.geometry) == 1
        end

        # Real parallel execution occurred when threads are available
        if Threads.nthreads() > 1
            @test length(unique(tids)) > 1
        else
            @info "THREAD-SAFETY testset ran with Threads.nthreads() == 1; " *
                  "parallelism assertion trivially skipped (isolation still tested)"
            # All iterations ran on the one default-pool thread. Do NOT
            # assert an absolute threadid — under Pkg.test an interactive
            # threadpool can shift default-pool ids (e.g. to 2).
            @test length(unique(tids)) == 1
        end
    end

    # -----------------------------------------------------------------------
    # DRAW-COUNT: expected_draws vs actual RNG advancement for ONE circuit
    # mixing deterministic + multi-outcome compound + EachSite + staircase
    # + single-site stochastic ops. Earlier tests (rng_v01.jl,
    # unified_rule_engine.jl) only cover homogeneous circuits.
    # -----------------------------------------------------------------------
    @testset "DRAW-COUNT: heterogeneous multi-op circuit matches expected_draws" begin
        L, bc = 8, :periodic
        left, right = StaircaseLeft(1), StaircaseRight(1)
        make_circuit() = Circuit(L = L, bc = bc) do c
            apply!(c, HaarRandom(), Bricklayer(:even))                 # det: 0 coins
            apply_with_prob!(c;
                outcomes = [                             # K = 4
                    (probability = 0.4, gate = HaarRandom(), geometry = Bricklayer(:even)),
                    (probability = 0.6, gate = CZ(), geometry = Bricklayer(:even))
                ])
            apply_with_prob!(c;
                outcomes = [                             # K = L-2 = 6
                    (probability = 0.3, gate = Measure(:Z),
                    geometry = EachSite(2:(L - 1)))
                ])
            apply_with_prob!(c;
                outcomes = [                             # K = 1 (set)
                    (probability = 0.5, gate = Reset(), geometry = left),
                    (probability = 0.5, gate = HaarRandom(), geometry = right)
                ])
            apply_with_prob!(c; outcomes = [                             # K = 1 (set)
                (probability = 0.25, gate = PauliX(), geometry = SingleSite(3))
            ])
        end
        n = 7
        K_per_step = 4 + 6 + 1 + 1
        circuit = make_circuit()
        @test expected_draws(circuit, n) == n * K_per_step

        registry = RNGRegistry(gates_spacetime = 42, born_measurement = 1,
            gates_realization = 2)
        state = SimulationState(L = L, bc = bc, maxdim = 32, rng = registry)
        initialize!(state, ProductState(binary_int = 0))
        simulate!(circuit, state; n_steps = n, record_when = :final_only)

        twin = MersenneTwister(42)
        for _ in 1:expected_draws(make_circuit(), n)
            rand(twin)   # SCALAR-DRAW CONTRACT: scalar burn
        end
        @test rand(get_rng(registry, :gates_spacetime)) == rand(twin)

        # Data-independence in the heterogeneous setting: different Born
        # outcomes must not change :gates_spacetime consumption.
        registry2 = RNGRegistry(gates_spacetime = 42, born_measurement = 999,
            gates_realization = 2)
        state2 = SimulationState(L = L, bc = bc, maxdim = 32, rng = registry2)
        initialize!(state2, ProductState(binary_int = 0))
        simulate!(make_circuit(), state2; n_steps = n, record_when = :final_only)
        twin2 = MersenneTwister(42)
        for _ in 1:(n * K_per_step)
            rand(twin2)  # SCALAR-DRAW CONTRACT: scalar burn
        end
        @test rand(get_rng(registry2, :gates_spacetime)) == rand(twin2)
    end

    # -----------------------------------------------------------------------
    # EVENT-LOG completeness: with log_events=true, EVERY applied gate has a
    # corresponding event — verified by replaying the full coin stream with
    # reference_select and demanding EXACT event-stream equality for a
    # circuit combining deterministic + stochastic (Σp<1, identity possible)
    # + feedback ops (integration across Tasks 4/9/10).
    # -----------------------------------------------------------------------
    @testset "EVENT-LOG completeness: det + stochastic + feedback, exact replay" begin
        L, bc, n_steps, st_seed = 6, :periodic, 4, 20260703
        even_elems = elements(Bricklayer(:even), L, bc)   # 3 pairs
        circuit = Circuit(L = L, bc = bc) do c
            apply!(c, HaarRandom(), Bricklayer(:even))                       # op 1: det, K=3
            apply_with_prob!(c; outcomes = [                                   # op 2: stoch, K=6
                (probability = 0.4, gate = Measure(:Z), geometry = AllSites())
            ])
            apply!(c, Hadamard(), AllSites())                                # op 3: det, K=6
            apply_with_prob!(c;
                outcomes = [                                   # op 4: stoch+feedback, K=4
                    (probability = 0.7,
                    gate = Measure(:Z; feedback = OnOutcome(1 => PauliX())),
                    geometry = EachSite(2:(L - 1)))
                ])
        end
        registry = RNGRegistry(gates_spacetime = st_seed, born_measurement = 7,
            gates_realization = 8)
        state = SimulationState(L = L, bc = bc, maxdim = 32, rng = registry,
            log_events = true)
        initialize!(state, ProductState(binary_int = 0))
        simulate!(circuit, state; n_steps = n_steps, record_when = :final_only)

        # Expected GateApplied stream from first principles (twin replay).
        # PauliX feedback draws nothing from :gates_spacetime, so the twin
        # walk is exact.
        twin = MersenneTwister(st_seed)
        expected = NamedTuple[]   # (step, op_idx, element_idx, label, sites)
        for step in 1:n_steps
            for (k, sites) in enumerate(even_elems)                    # op 1
                push!(expected, (step = step, op_idx = 1, element_idx = k,
                    label = "Haar", sites = sites))
            end
            sel2 = reference_select(twin, [0.4], L)                    # op 2
            for (k, s) in enumerate(sel2)
                s == 0 && continue
                push!(expected, (step = step, op_idx = 2, element_idx = k,
                    label = "Meas", sites = [k]))
            end
            for k in 1:L                                               # op 3
                push!(expected, (step = step, op_idx = 3, element_idx = k,
                    label = "H", sites = [k]))
            end
            sel4 = reference_select(twin, [0.7], L - 2)                # op 4
            for (k, s) in enumerate(sel4)
                s == 0 && continue
                push!(expected, (step = step, op_idx = 4, element_idx = k,
                    label = "Meas", sites = [k + 1]))         # EachSite(2:L-1)
            end
        end

        gas = [e for e in events(state) if e isa GateApplied]
        @test length(gas) == length(expected)   # every applied gate logged, nothing extra
        @test all(1:length(expected)) do i
            e, x = gas[i], expected[i]
            e.step == x.step && e.op_idx == x.op_idx &&
                e.element_idx == x.element_idx &&
                e.gate_label == x.label && e.sites == x.sites
        end
        # Feedback gates emit NO GateApplied (PauliX label "X" absent)
        @test !any(e -> e.gate_label == "X", gas)

        # Every Born sample logged: one MeasurementOutcome per selected
        # Measure application, with matching (step, op_idx).
        mos = [e for e in events(state) if e isa MeasurementOutcome]
        exp_meas = [x for x in expected if x.label == "Meas"]
        @test length(mos) == length(exp_meas)
        @test all(1:length(mos)) do i
            mos[i].step == exp_meas[i].step &&
                mos[i].op_idx == exp_meas[i].op_idx &&
                mos[i].sites == exp_meas[i].sites &&
                mos[i].outcome in (0, 1)
        end
        # Sanity: the Σp<1 op actually exercised both branches over the run
        @test 0 < length([x for x in exp_meas if x.op_idx == 2]) < n_steps * L
    end

    # -----------------------------------------------------------------------
    # EQUAL-K: the strict no-scalar-broadcast guardrail (plan "Must NOT
    # Have": NO scalar-broadcast of K=1 against K>1). Earlier equal-K tests
    # mix K=4 vs K=2; here specifically K=1 vs K>1 — the case a lenient
    # implementation would be tempted to broadcast — on BOTH paths.
    # -----------------------------------------------------------------------
    @testset "EQUAL-K: K=1 vs K>1 never broadcasts (builder AND eager)" begin
        outcomes_set_vs_bcast = [
            (probability = 0.5, gate = PauliX(), geometry = SingleSite(1)),  # K=1 (set)
            (probability = 0.5, gate = Measure(:Z), geometry = AllSites())      # K=4
        ]
        # K=1 BROADCAST geometry against K>1 must error identically
        outcomes_bcast1_vs_bcast = [
            (probability = 0.5, gate = PauliX(), geometry = EachSite(1:1)),  # K=1 (broadcast)
            (probability = 0.5, gate = Measure(:Z), geometry = AllSites())      # K=4
        ]

        for outcomes in (outcomes_set_vs_bcast, outcomes_bcast1_vs_bcast)
            # Builder path
            err = try
                Circuit(L = 4, bc = :periodic) do c
                    apply_with_prob!(c; outcomes = outcomes)
                end
                nothing
            catch e
                e
            end
            @test err isa ArgumentError
            msg = sprint(showerror, err)
            @test occursin("K=1", msg)
            @test occursin("K=4", msg)

            # Eager path (same strictness at call time)
            st = SimulationState(L = 4, bc = :periodic, maxdim = 16,
                rng = RNGRegistry(gates_spacetime = 1,
                    born_measurement = 2,
                    gates_realization = 3))
            initialize!(st, ProductState(binary_int = 0))
            err2 = try
                apply_with_prob!(st; outcomes = outcomes)
                nothing
            catch e
                e
            end
            @test err2 isa ArgumentError
            msg2 = sprint(showerror, err2)
            @test occursin("K=1", msg2)
            @test occursin("K=4", msg2)
        end
    end

    # -----------------------------------------------------------------------
    # SENTINEL: the feedback guard must also fire on the ENGINE path
    # (simulate! → stochastic branch → execute!(::Measure) → feedback), not
    # just the eager apply! path tested in feedback.jl. The error must
    # propagate out of simulate! and the guarded stream must be restored.
    # -----------------------------------------------------------------------
    @testset "SENTINEL: engine-path feedback draw of :gates_spacetime aborts simulate!" begin
        bad_fb = (s, sites, o) -> QuantumCircuitsMPS.draw(s, :gates_spacetime)
        circuit = Circuit(L = 4, bc = :periodic) do c
            apply_with_prob!(c;
                outcomes = [
                    (probability = 1.0,
                    gate = Measure(:Z; feedback = bad_fb),
                    geometry = AllSites())
                ])
        end
        registry = RNGRegistry(gates_spacetime = 11, born_measurement = 12,
            gates_realization = 13)
        state = SimulationState(L = 4, bc = :periodic, maxdim = 16, rng = registry)
        initialize!(state, ProductState(binary_int = 0))
        err = try
            simulate!(circuit, state; n_steps = 1, record_when = :final_only)
            nothing
        catch e
            e
        end
        @test err isa ErrorException
        @test occursin("forbidden", sprint(showerror, err))
        # Guard restored the real stream even though simulate! aborted
        @test QuantumCircuitsMPS.draw(state, :gates_spacetime) isa Float64
        @test !(get_rng(registry, :gates_spacetime) isa QuantumCircuitsMPS.SentinelRNG)
    end
end
