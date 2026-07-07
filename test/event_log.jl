# === Typed event log tests (Task 4, plan api-refactor-v0.1.md) ===
using Test
using QuantumCircuitsMPS
# Explicit imports: ITensorMPS (loaded by other test files) also exports
# `measurements`, which makes the bare name ambiguous inside Pkg.test.
using QuantumCircuitsMPS: events, measurements
# Event types + log_event! are internal since Task 14 (not in manifest KEEP/ADD)
using QuantumCircuitsMPS: CircuitEvent, GateApplied, MeasurementOutcome, log_event!

# Helper: standard MIPT-style circuit for event-log tests
function _eventlog_mipt_circuit(L, p)
    Circuit(L = L, bc = :periodic) do c
        apply!(c, HaarRandom(), Bricklayer(:even))
        apply_with_prob!(c; outcomes = [
            (probability = p, gate = Measure(:Z), geometry = AllSites())])
        apply!(c, HaarRandom(), Bricklayer(:odd))
        apply_with_prob!(c; outcomes = [
            (probability = p, gate = Measure(:Z), geometry = AllSites())])
    end
end

function _eventlog_state(L; log_events = false, kwargs...)
    registry = RNGRegistry(gates_spacetime = 42, born_measurement = 1, gates_realization = 2)
    state = SimulationState(L = L, bc = :periodic, maxdim = 32, rng = registry,
        log_events = log_events, kwargs...)
    initialize!(state, ProductState(binary_int = 0))
    state
end

@testset "Typed event log" begin
    @testset "Event types" begin
        @test GateApplied <: CircuitEvent
        @test MeasurementOutcome <: CircuitEvent
        ga = GateApplied(1, 2, 3, "Haar", [4, 5])
        @test ga.step == 1
        @test ga.op_idx == 2
        @test ga.element_idx == 3
        @test ga.gate_label == "Haar"
        @test ga.sites == [4, 5]
        mo = MeasurementOutcome(1, 2, [3], 0)
        @test mo.step == 1
        @test mo.op_idx == 2
        @test mo.sites == [3]
        @test mo.outcome == 0
    end

    @testset "Opt-in construction" begin
        state_off = SimulationState(L = 4, bc = :periodic)
        @test state_off.event_log === nothing

        state_on = SimulationState(L = 4, bc = :periodic, log_events = true)
        @test state_on.event_log isa Vector{CircuitEvent}
        @test isempty(state_on.event_log)
    end

    @testset "log_event! and accessors" begin
        state_on = SimulationState(L = 4, bc = :periodic, log_events = true)
        ev = GateApplied(1, 1, 1, "Haar", [1, 2])
        log_event!(state_on, ev)
        @test length(events(state_on)) == 1
        @test events(state_on)[1] === ev
        @test isempty(measurements(state_on))  # GateApplied filtered out
        mo = MeasurementOutcome(1, 2, [3], 1)
        log_event!(state_on, mo)
        @test length(events(state_on)) == 2
        @test measurements(state_on) == [mo]
        @test measurements(state_on) isa Vector{MeasurementOutcome}

        # Disabled: log_event! is a silent no-op; accessors throw informative error
        state_off = SimulationState(L = 4, bc = :periodic)
        @test log_event!(state_off, ev) === nothing
        @test state_off.event_log === nothing
        @test_throws ArgumentError events(state_off)
        @test_throws ArgumentError measurements(state_off)
        err = try
            ;
            events(state_off);
        catch e
            ;
            e;
        end
        @test occursin("log_events=true", sprint(showerror, err))
    end

    @testset "MIPT run emits GateApplied + MeasurementOutcome" begin
        L, p, n_steps = 6, 0.3, 5
        circuit = _eventlog_mipt_circuit(L, p)
        state = _eventlog_state(L; log_events = true)
        track!(state, :entropy => EntanglementEntropy(; cut = L ÷ 2))
        simulate!(circuit, state; n_steps = n_steps, record_when = :every_step)

        evs = events(state)
        @test !isempty(evs)
        gate_evs = [e for e in evs if e isa GateApplied]
        meas_evs = measurements(state)

        # Deterministic Haar layers: 2 Bricklayer ops * 3 pairs * 5 steps = 30,
        # plus one GateApplied per selected Measurement element
        @test count(e -> e.gate_label == "Haar", gate_evs) == 2 * (L ÷ 2) * n_steps
        @test all(e -> e.gate_label in ("Haar", "Meas"), gate_evs)

        # Measurement outcomes: statistically ~ p * L * 2 ops * n_steps = 18 expected
        @test !isempty(meas_evs)
        expected = p * L * 2 * n_steps
        @test expected / 4 <= length(meas_evs) <= expected * 4  # loose statistical band, fixed seed
        @test all(m -> m.outcome in (0, 1), meas_evs)
        @test all(m -> length(m.sites) == 1 && 1 <= m.sites[1] <= L, meas_evs)

        # Each selected Measurement element emits BOTH a GateApplied("Meas") and a MeasurementOutcome
        @test count(e -> e.gate_label == "Meas", gate_evs) == length(meas_evs)

        # Index sanity: steps within range; op_idx within circuit ops (engine-emitted GateApplied)
        @test all(e -> 1 <= e.step <= n_steps, gate_evs)
        @test all(e -> 1 <= e.op_idx <= 4, gate_evs)
        @test all(e -> e.element_idx >= 1, gate_evs)
    end

    @testset "Zero behavior change when disabled (default)" begin
        L, p, n_steps = 6, 0.3, 5
        c1 = _eventlog_mipt_circuit(L, p)
        s1 = _eventlog_state(L)  # default: log_events=false
        track!(s1, :entropy => EntanglementEntropy(; cut = L ÷ 2))
        simulate!(c1, s1; n_steps = n_steps, record_when = :every_step)

        c2 = _eventlog_mipt_circuit(L, p)
        s2 = _eventlog_state(L; log_events = true)
        track!(s2, :entropy => EntanglementEntropy(; cut = L ÷ 2))
        simulate!(c2, s2; n_steps = n_steps, record_when = :every_step)

        # Identical seeds -> bit-identical trajectories regardless of logging
        @test s1.observables[:entropy] == s2.observables[:entropy]
        @test [born_probability(s1, i, 0) for i in 1:L] ==
              [born_probability(s2, i, 0) for i in 1:L]

        # RNG streams consumed identically
        for stream in (:gates_spacetime, :born_measurement, :gates_realization)
            @test rand(get_rng(s1.rng_registry, stream)) ==
                  rand(get_rng(s2.rng_registry, stream))
        end

        @test s1.event_log === nothing
        @test !isempty(events(s2))
    end

    @testset "Post-selection recipe works" begin
        L, p, n_steps = 6, 0.3, 5
        circuit = _eventlog_mipt_circuit(L, p)
        state = _eventlog_state(L; log_events = true)
        simulate!(circuit, state; n_steps = n_steps)
        ms = measurements(state)
        @test !isempty(ms)
        traj_ok = all(m -> m.outcome == 0, ms)  # keep-trajectory predicate
        @test traj_ok isa Bool
    end
end
