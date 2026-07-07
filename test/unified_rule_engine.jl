# === Unified stochastic engine tests (Task 9, plan api-refactor-v0.1.md) ===
# THE core-task test file: builder validation (equal-K, Σp, staircase guard,
# removed rng= kwarg) + engine semantics (reference_select equivalence,
# fixed draws, structural step boundary, counters, event-log real indices).
using Test
using Random
using QuantumCircuitsMPS
using QuantumCircuitsMPS: events, measurements
using QuantumCircuitsMPS: GateApplied  # internal since Task 14 (not in manifest)

# reference_select — the semantic oracle — is provided by test/testutils.jl,
# which runtests.jl includes unconditionally before any test file.

function _ure_registry(; st = 42, born = 1, real = 2)
    RNGRegistry(gates_spacetime = st, born_measurement = born, gates_realization = real)
end

function _ure_state(L; bc = :periodic, log_events = false, st = 42, born = 1, real = 2)
    state = SimulationState(L = L, bc = bc, maxdim = 32,
        rng = _ure_registry(; st = st, born = born, real = real),
        log_events = log_events)
    initialize!(state, ProductState(binary_int = 0))
    return state
end

@testset "Unified stochastic engine (v0.1)" begin
    @testset "builder: equal-K mismatch errors at build time" begin
        err = try
            Circuit(L = 4, bc = :periodic) do c
                apply_with_prob!(c;
                    outcomes = [
                        (probability = 0.3, gate = Measure(:Z), geometry = AllSites()),      # K=4
                        (probability = 0.3, gate = HaarRandom(),
                            geometry = Bricklayer(:odd))    # K=2
                    ])
            end
            nothing
        catch e
            e
        end
        @test err isa ArgumentError
        msg = sprint(showerror, err)
        @test occursin("4", msg)
        @test occursin("2", msg)
        @test occursin("AllSites", msg)
        @test occursin("Bricklayer", msg)
    end

    @testset "builder: Σp > 1 rejected, Σp ≤ 1 accepted" begin
        @test_throws ArgumentError Circuit(L = 4, bc = :periodic) do c
            apply_with_prob!(c;
                outcomes = [
                    (probability = 0.8, gate = PauliX(), geometry = SingleSite(1)),
                    (probability = 0.5, gate = PauliZ(), geometry = SingleSite(1))
                ])
        end
        ok = Circuit(L = 4, bc = :periodic) do c
            apply_with_prob!(c;
                outcomes = [
                    (probability = 0.5, gate = PauliX(), geometry = SingleSite(1)),
                    (probability = 0.5, gate = PauliZ(), geometry = SingleSite(1))
                ])
        end
        @test length(ok.operations) == 1
    end

    @testset "builder: staircase/Pointer with Σp < 1 rejected (CIPT guard)" begin
        err = try
            Circuit(L = 4, bc = :periodic) do c
                apply_with_prob!(c;
                    outcomes = [
                        (probability = 0.3, gate = Reset(), geometry = StaircaseLeft(1))
                    ])
            end
            nothing
        catch e
            e
        end
        @test err isa ArgumentError
        msg = sprint(showerror, err)
        @test occursin("staircase", lowercase(msg))
        @test occursin("advance", lowercase(msg))

        @test_throws ArgumentError Circuit(L = 4, bc = :periodic) do c
            apply_with_prob!(c; outcomes = [
                (probability = 0.9, gate = CZ(), geometry = Pointer(1))
            ])
        end

        # Σp = 1 with staircases is the valid CIPT form
        cipt = Circuit(L = 4, bc = :periodic) do c
            apply_with_prob!(c;
                outcomes = [
                    (probability = 0.5, gate = Reset(), geometry = StaircaseLeft(1)),
                    (probability = 0.5, gate = HaarRandom(), geometry = StaircaseRight(1))
                ])
        end
        @test length(cipt.operations) == 1
    end

    @testset "builder: removed rng= kwarg throws migration error (never ignored)" begin
        for rng_val in (:gates_realization, :gates_spacetime, :invalid)
            err = try
                Circuit(L = 4, bc = :periodic) do c
                    apply_with_prob!(c;
                        rng = rng_val,
                        outcomes = [
                            (probability = 0.5, gate = PauliX(), geometry = SingleSite(1))
                        ])
                end
                nothing
            catch e
                e
            end
            @test err isa ArgumentError
            msg = sprint(showerror, err)
            @test occursin("rng", msg)
            @test occursin("removed", msg)
            @test occursin("gates_spacetime", msg)
        end
        # any other unknown kwarg also fails loudly
        @test_throws ArgumentError Circuit(L = 4, bc = :periodic) do c
            apply_with_prob!(c;
                bogus = 1,
                outcomes = [
                    (probability = 0.5, gate = PauliX(), geometry = SingleSite(1))
                ])
        end
    end

    @testset "engine selections == reference_select (30 random configs, fixed meta-seed)" begin
        # Trimmed from 100 fuzz configs to 30 (v0.4 test consolidation): the
        # fixed meta-seed makes these the SAME first 30 configs as before —
        # deterministic, reproducible, and still spanning 1/2-site gates,
        # both bcs, all geometry pools, and the Σp=1 vs Σp<1 regimes.
        meta = MersenneTwister(20260703)
        one_site_gates = [PauliX(), PauliZ(), PauliY()]   # labels X, Z, Y
        two_site_gates = [CZ(), HaarRandom()]             # labels CZ, Haar
        n_steps = 2

        for cfg in 1:30
            L = rand(meta, (4, 6, 8))
            two_site = rand(meta, Bool)
            if two_site
                bc = :periodic
                geo_pool = [Bricklayer(:odd), Bricklayer(:even)]
                gate_pool = two_site_gates
            else
                bc = rand(meta, (:periodic, :open))
                geo_pool = [AllSites(), EachSite(1:L), EachSite(2:(L - 1))]
                gate_pool = one_site_gates
            end
            geo = rand(meta, geo_pool)
            K = element_count(geo, L, bc)
            n_out = rand(meta, 1:length(gate_pool))
            raw = [rand(meta) for _ in 1:n_out]
            # half the configs: Σp = 1 exactly (snap regime); else Σp < 1
            total = rand(meta, Bool) ? 1.0 : 0.9 * rand(meta)
            probs = raw ./ sum(raw) .* total
            gates = gate_pool[1:n_out]
            labels = [QuantumCircuitsMPS.gate_label(g) for g in gates]
            outcomes = [(probability = probs[i], gate = gates[i], geometry = geo)
                        for i in 1:n_out]

            circuit = Circuit(L = L, bc = bc) do c
                apply_with_prob!(c; outcomes = outcomes)
            end
            seed = 5000 + cfg
            state = _ure_state(L; bc = bc, log_events = true, st = seed)
            simulate!(circuit, state; n_steps = n_steps, record_when = :final_only)

            # observed selection per global element slot (step-major order)
            observed = Dict{Int, String}()
            for e in events(state)
                e isa GateApplied || continue
                observed[(e.step - 1) * K + e.element_idx] = e.gate_label
            end

            expected = reference_select(MersenneTwister(seed),
                collect(Float64, probs), K * n_steps)
            match = true
            for j in 1:(K * n_steps)
                exp_label = expected[j] == 0 ? nothing : labels[expected[j]]
                if get(observed, j, nothing) != exp_label
                    match = false
                    break
                end
            end
            @test match
        end
    end

    @testset "QA: per-bond exclusive gate choice (motivating example)" begin
        circuit = Circuit(L = 8, bc = :periodic) do c
            apply_with_prob!(c;
                outcomes = [
                    (probability = 0.5, gate = HaarRandom(), geometry = Bricklayer(:even)),
                    (probability = 0.5, gate = CZ(), geometry = Bricklayer(:even))
                ])
        end
        state = _ure_state(8; log_events = true)
        simulate!(circuit, state; n_steps = 1, record_when = :final_only)
        evs = [e for e in events(state) if e isa GateApplied]
        @test length(evs) == 4                 # every even bond: EXACTLY one gate
        @test sort([e.element_idx for e in evs]) == [1, 2, 3, 4]
        @test all(e -> e.gate_label in ("Haar", "CZ"), evs)
        bonds = elements(Bricklayer(:even), 8, :periodic)
        @test all(e -> e.sites == bonds[e.element_idx], evs)
    end

    @testset "QA: draw-count invariance across measurement trajectories" begin
        make_circuit() = Circuit(L = 6, bc = :periodic) do c
            apply!(c, HaarRandom(), Bricklayer(:even))
            apply_with_prob!(c; outcomes = [
                (probability = 0.5, gate = Measure(:Z), geometry = AllSites())
            ])
            apply!(c, HaarRandom(), Bricklayer(:odd))
            apply_with_prob!(c; outcomes = [
                (probability = 0.5, gate = Measure(:Z), geometry = AllSites())
            ])
        end
        s1 = _ure_state(6; born = 1)
        s2 = _ure_state(6; born = 99)   # different measurement outcomes
        simulate!(make_circuit(), s1; n_steps = 10)
        simulate!(make_circuit(), s2; n_steps = 10)
        fp1 = rand(get_rng(s1.rng_registry, :gates_spacetime))
        fp2 = rand(get_rng(s2.rng_registry, :gates_spacetime))
        @test fp1 == fp2
    end

    @testset "engine draw count == expected_draws (multi-outcome compound)" begin
        circuit = Circuit(L = 8, bc = :periodic) do c
            apply_with_prob!(c;
                outcomes = [
                    (probability = 0.5, gate = HaarRandom(), geometry = Bricklayer(:even)),
                    (probability = 0.5, gate = CZ(), geometry = Bricklayer(:even))
                ])
        end
        n = 5
        state = _ure_state(8)
        simulate!(circuit, state; n_steps = n, record_when = :final_only)
        twin = MersenneTwister(42)
        for _ in 1:expected_draws(circuit, n)
            rand(twin)   # SCALAR-DRAW CONTRACT: scalar burn
        end
        @test rand(get_rng(state.rng_registry, :gates_spacetime)) == rand(twin)
        @test expected_draws(circuit, n) ==
              n * element_count(Bricklayer(:even), 8, :periodic)
    end

    @testset "REGRESSION: do-nothing skip — :every_step fires every step" begin
        # Last op is stochastic with p=0.01: under the pre-v0.1 engine the
        # step record was silently skipped whenever the coin selected
        # identity, yielding variable-length record vectors.
        N = 25
        circuit = Circuit(L = 4, bc = :periodic) do c
            apply!(c, HaarRandom(), Bricklayer(:even))
            apply_with_prob!(c; outcomes = [
                (probability = 0.01, gate = PauliX(), geometry = SingleSite(1))
            ])
        end
        state = _ure_state(4)
        track!(state, :mz => Magnetization(:Z))
        simulate!(circuit, state; n_steps = N, record_when = :every_step)
        @test length(state.observables[:mz]) == N

        # :final_only on the same shape: exactly one record
        state2 = _ure_state(4)
        track!(state2, :mz => Magnetization(:Z))
        simulate!(circuit, state2; n_steps = N, record_when = :final_only)
        @test length(state2.observables[:mz]) == 1
    end

    @testset "counters: element slots advance regardless of outcome" begin
        # p = 0 → every slot selects identity, yet gate_idx must advance
        # (trajectory-independent recording schedules) and the structural
        # boundary evaluation must still happen.
        circuit = Circuit(L = 4, bc = :periodic) do c
            apply_with_prob!(c; outcomes = [
                (probability = 0.0, gate = PauliX(), geometry = AllSites())
            ])
        end
        state = _ure_state(4)
        track!(state, :mz => Magnetization(:Z))
        seen = Int[]
        boundary_flags = Bool[]
        rec = ctx -> begin
            push!(seen, ctx.gate_idx)
            push!(boundary_flags, ctx.is_step_boundary)
            false
        end
        simulate!(circuit, state; n_steps = 1, record_when = rec)
        @test seen == [1, 2, 3, 4, 4]            # 4 slots + structural boundary
        @test boundary_flags == [false, false, false, false, true]
        @test isempty(state.observables[:mz])    # predicate always false
    end

    @testset "engine-side cumsum snapping: Σp ≈ 1 never selects identity" begin
        # fill(0.1, 10) sums to 0.9999999999999999 — float dust must not
        # leak identity selections (last boundary snapped to 1.0).
        outcomes = [(probability = 0.1, gate = PauliX(), geometry = SingleSite(1))
                    for _ in 1:10]
        circuit = Circuit(L = 4, bc = :periodic) do c
            apply_with_prob!(c; outcomes = outcomes)
        end
        N = 200
        state = _ure_state(4; log_events = true)
        simulate!(circuit, state; n_steps = N, record_when = :final_only)
        @test count(e -> e isa GateApplied, events(state)) == N   # K=1 per step, never identity
    end

    @testset "staircase: identity selection does not advance (no crash)" begin
        # The builder forbids staircase + Σp<1, but hand-built circuits must
        # not crash — identity simply leaves the walker in place.
        left = StaircaseLeft(2)
        circuit = Circuit(L = 4,
            bc = :periodic,
            operations = NamedTuple[
                (type = :stochastic, rng = :gates_spacetime,
                outcomes = [
                    (probability = 0.0, gate = Reset(), geometry = left)
                ])
            ])
        state = _ure_state(4)
        simulate!(circuit, state; n_steps = 3, record_when = :final_only)
        @test QuantumCircuitsMPS.current_position(left) == 2
    end

    @testset "event log carries real (step, op_idx) — no 0 sentinels" begin
        circuit = Circuit(L = 6, bc = :periodic) do c
            apply!(c, HaarRandom(), Bricklayer(:even))                              # op 1
            apply_with_prob!(c; outcomes = [
                (probability = 0.5, gate = Measure(:Z), geometry = AllSites())])      # op 2
            apply!(c, HaarRandom(), Bricklayer(:odd))                               # op 3
            apply_with_prob!(c; outcomes = [
                (probability = 0.5, gate = Reset(), geometry = EachSite(2:5))])           # op 4
        end
        n_steps = 3
        state = _ure_state(6; log_events = true)
        simulate!(circuit, state; n_steps = n_steps, record_when = :final_only)

        ms = measurements(state)
        @test !isempty(ms)
        @test all(m -> 1 <= m.step <= n_steps, ms)     # real step, not 0
        @test all(m -> m.op_idx in (2, 4), ms)         # measurement/reset ops only

        gs = [e for e in events(state) if e isa GateApplied]
        @test all(e -> 1 <= e.step <= n_steps, gs)
        @test all(e -> 1 <= e.op_idx <= 4, gs)
        # element_idx bounded by each op's K
        Ks = Dict(1 => 3, 2 => 6, 3 => 3, 4 => 4)
        @test all(e -> 1 <= e.element_idx <= Ks[e.op_idx], gs)
        # Haar events on op 1/3 only; Meas on op 2; Rst on op 4
        @test all(e -> e.op_idx in (1, 3), [e for e in gs if e.gate_label == "Haar"])
        @test all(e -> e.op_idx == 2, [e for e in gs if e.gate_label == "Meas"])
        @test all(e -> e.op_idx == 4, [e for e in gs if e.gate_label == "Rst"])
        # every engine-level Measure/Reset application Born-samples once
        @test length(ms) == count(e -> e.gate_label in ("Meas", "Rst"), gs)

        # Outside an engine run (eager apply!) the context is 0 — documented
        st2 = _ure_state(4; log_events = true)
        apply!(st2, Measure(:Z), SingleSite(1))
        ms2 = measurements(st2)
        @test length(ms2) == 1
        @test ms2[1].step == 0 && ms2[1].op_idx == 0
    end

    @testset "copy(circuit): private per-trajectory geometry state, aliasing preserved" begin
        left = StaircaseLeft(3)
        circuit = Circuit(L = 6, bc = :periodic) do c
            apply_with_prob!(c; outcomes = [(
                probability = 1.0, gate = Reset(), geometry = left)])
            apply_with_prob!(c; outcomes = [(
                probability = 1.0, gate = HaarRandom(), geometry = left)])
        end
        @test circuit.operations[1].outcomes[1].geometry === left
        c2 = copy(circuit)
        g1 = c2.operations[1].outcomes[1].geometry
        g2 = c2.operations[2].outcomes[1].geometry
        @test g1 === g2          # intra-circuit aliasing preserved
        @test g1 !== left        # ... but independent of the original
        QuantumCircuitsMPS.advance!(g1, 6, :periodic)
        @test QuantumCircuitsMPS.current_position(left) == 3   # original untouched
    end
end
