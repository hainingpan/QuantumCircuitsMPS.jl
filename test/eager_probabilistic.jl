# === Eager-mode apply_with_prob! (Task 12: v0.1 unified rule alignment) ===
# The eager form apply_with_prob!(state; outcomes) must be the SAME engine as
# the lazy Circuit + simulate! path: same select_outcome_index selection, same
# validation (at call time instead of build time), same coin consumption.

using Test
using QuantumCircuitsMPS
using QuantumCircuitsMPS: events, measurements
using QuantumCircuitsMPS: GateApplied  # internal since Task 14 (not in manifest)
using Random

# Fresh scrambled state helper (identical seeds across lazy/eager twins)
function _eager_test_state(;
        L = 8, bc = :periodic, gs = 42, born = 1, real = 2, log_events = false)
    st = SimulationState(L = L, bc = bc, maxdim = 64,
        rng = RNGRegistry(gates_spacetime = gs, born_measurement = born, gates_realization = real),
        log_events = log_events)
    initialize!(st, ProductState(binary_int = 0))
    return st
end

@testset "Eager apply_with_prob! (v0.1 unified rule)" begin
    @testset "rng= kwarg hard-removed (migration error)" begin
        st = _eager_test_state(L = 4)
        err = try
            apply_with_prob!(st;
                rng = :gates_realization,
                outcomes = [
                    (probability = 0.5, gate = PauliX(), geometry = SingleSite(1))])
            nothing
        catch e
            e
        end
        @test err isa ArgumentError
        msg = sprint(showerror, err)
        @test occursin("gates_spacetime", msg)
        @test occursin("v0.1.0", msg)
        # Legacy default value is rejected too (no accept-and-ignore)
        @test_throws ArgumentError apply_with_prob!(st; rng = :gates_spacetime,
            outcomes = [
                (probability = 0.5, gate = PauliX(), geometry = SingleSite(1))])
    end

    @testset "unknown kwargs rejected" begin
        st = _eager_test_state(L = 4)
        err = try
            apply_with_prob!(st;
                bogus = 1,
                outcomes = [
                    (probability = 0.5, gate = PauliX(), geometry = SingleSite(1))])
            nothing
        catch e
            e
        end
        @test err isa ArgumentError
        @test occursin("bogus", sprint(showerror, err))
    end

    @testset "empty outcomes rejected" begin
        st = _eager_test_state(L = 4)
        @test_throws ArgumentError apply_with_prob!(st;
            outcomes = NamedTuple{(:probability, :gate, :geometry)}[])
    end

    @testset "Σp > 1 throws before any draw or mutation" begin
        st = _eager_test_state(L = 4)
        # Scramble so the state is non-trivial
        apply!(st, HaarRandom(), Bricklayer(:even))
        p_before = [born_probability(st, i, 0) for i in 1:4]
        rng_before = copy(get_rng(st.rng_registry, :gates_spacetime))
        err = try
            apply_with_prob!(st;
                outcomes = [
                    (probability = 0.7, gate = PauliX(), geometry = SingleSite(1)),
                    (probability = 0.7, gate = PauliZ(), geometry = SingleSite(1))])
            nothing
        catch e
            e
        end
        @test err isa ArgumentError
        @test occursin("must be ≤ 1", sprint(showerror, err))
        # No state mutation, no coin consumed
        @test [born_probability(st, i, 0) for i in 1:4] == p_before
        @test rand(copy(get_rng(st.rng_registry, :gates_spacetime))) ==
              rand(copy(rng_before))
    end

    @testset "equal-K mismatch throws before any draw or mutation" begin
        st = _eager_test_state(L = 4)
        apply!(st, HaarRandom(), Bricklayer(:even))
        p_before = [born_probability(st, i, 0) for i in 1:4]
        rng_before = copy(get_rng(st.rng_registry, :gates_spacetime))
        born_before = copy(get_rng(st.rng_registry, :born_measurement))
        err = try
            apply_with_prob!(st;
                outcomes = [
                    (probability = 0.3, gate = Measure(:Z), geometry = AllSites()),      # K=4
                    (probability = 0.3, gate = HaarRandom(), geometry = Bricklayer(:odd))])  # K=2
            nothing
        catch e
            e
        end
        @test err isa ArgumentError
        msg = sprint(showerror, err)
        @test occursin("K=4", msg)
        @test occursin("K=2", msg)
        @test occursin("AllSites", msg)
        @test occursin("Bricklayer", msg)
        # State untouched, no coins consumed on ANY stream
        @test [born_probability(st, i, 0) for i in 1:4] == p_before
        @test rand(copy(get_rng(st.rng_registry, :gates_spacetime))) ==
              rand(copy(rng_before))
        @test rand(copy(get_rng(st.rng_registry, :born_measurement))) ==
              rand(copy(born_before))
    end

    @testset "staircase Σp < 1 physics guard" begin
        st = _eager_test_state(L = 4)
        err = try
            apply_with_prob!(st; outcomes = [
                (probability = 0.5, gate = Reset(), geometry = StaircaseLeft(1))])
            nothing
        catch e
            e
        end
        @test err isa ArgumentError
        msg = sprint(showerror, err)
        @test occursin("Σp = 1", msg)
        @test occursin("staircase", lowercase(msg))
        # Pointer triggers the same guard
        @test_throws ArgumentError apply_with_prob!(
            st; outcomes = [
                (probability = 0.5, gate = PauliX(), geometry = Pointer(1))])
        # Σp = 1 staircase is fine
        left = StaircaseLeft(1)
        right = StaircaseRight(1)
        @test apply_with_prob!(st;
            outcomes = [
                (probability = 0.5, gate = Reset(), geometry = left),
                (probability = 0.5, gate = HaarRandom(), geometry = right)]) === nothing
    end

    @testset "lazy/eager equivalence: MIPT step (5 steps, 1e-14)" begin
        L, p, n_steps = 8, 0.15, 5

        # Lazy: Circuit + simulate!
        circuit = Circuit(L = L, bc = :periodic) do c
            apply!(c, HaarRandom(), Bricklayer(:even))
            apply_with_prob!(c; outcomes = [
                (probability = p, gate = Measure(:Z), geometry = AllSites())])
            apply!(c, HaarRandom(), Bricklayer(:odd))
            apply_with_prob!(c; outcomes = [
                (probability = p, gate = Measure(:Z), geometry = AllSites())])
        end
        st_lazy = _eager_test_state(L = L)
        track!(st_lazy, :entropy => EntanglementEntropy(cut = L ÷ 2))
        simulate!(circuit, st_lazy; n_steps = n_steps, record_when = :every_step)

        # Eager: same protocol as an imperative loop, same seeds
        st_eager = _eager_test_state(L = L)
        track!(st_eager, :entropy => EntanglementEntropy(cut = L ÷ 2))
        for _ in 1:n_steps
            apply!(st_eager, HaarRandom(), Bricklayer(:even))
            apply_with_prob!(st_eager;
                outcomes = [
                    (probability = p, gate = Measure(:Z), geometry = AllSites())])
            apply!(st_eager, HaarRandom(), Bricklayer(:odd))
            apply_with_prob!(st_eager;
                outcomes = [
                    (probability = p, gate = Measure(:Z), geometry = AllSites())])
            record!(st_eager)
        end

        e_lazy = st_lazy.observables[:entropy]
        e_eager = st_eager.observables[:entropy]
        @test length(e_lazy) == n_steps
        @test length(e_eager) == n_steps
        @test all(abs.(e_lazy .- e_eager) .<= 1e-14)
        # Streams fully in sync afterwards (same total consumption)
        for stream in (:gates_spacetime, :gates_realization, :born_measurement)
            @test rand(copy(get_rng(st_lazy.rng_registry, stream))) ==
                  rand(copy(get_rng(st_eager.rng_registry, stream)))
        end
    end

    @testset "lazy/eager equivalence: CIPT staircase (Σp=1, sync + advance)" begin
        L, p_ctrl, n_steps = 8, 0.5, 20

        circuit = Circuit(L = L, bc = :periodic) do c
            apply_with_prob!(c;
                outcomes = [
                    (probability = p_ctrl, gate = Reset(), geometry = StaircaseLeft(1)),
                    (probability = 1 - p_ctrl, gate = HaarRandom(),
                        geometry = StaircaseRight(1))])
        end
        st_lazy = _eager_test_state(L = L)
        track!(st_lazy, :Mz => Magnetization(:Z))
        simulate!(circuit, st_lazy; n_steps = n_steps, record_when = :every_step)

        # Eager twin: fresh staircase instances at the same initial positions
        left = StaircaseLeft(1)
        right = StaircaseRight(1)
        st_eager = _eager_test_state(L = L)
        track!(st_eager, :Mz => Magnetization(:Z))
        for _ in 1:n_steps
            apply_with_prob!(st_eager;
                outcomes = [
                    (probability = p_ctrl, gate = Reset(), geometry = left),
                    (probability = 1 - p_ctrl, gate = HaarRandom(), geometry = right)])
            record!(st_eager)
        end

        m_lazy = st_lazy.observables[:Mz]
        m_eager = st_eager.observables[:Mz]
        @test length(m_lazy) == n_steps
        @test all(abs.(m_lazy .- m_eager) .<= 1e-14)
        # Staircase positions advanced AND synced identically in the eager loop
        @test QuantumCircuitsMPS.current_position(left) == QuantumCircuitsMPS.current_position(right)
    end

    @testset "fixed draw count: K coins per call, data-independent" begin
        L = 6
        st = _eager_test_state(L = L)
        twin = copy(get_rng(st.rng_registry, :gates_spacetime))
        # p tiny → almost all identity selections; coins still consumed
        apply_with_prob!(st; outcomes = [
            (probability = 0.01, gate = Measure(:Z), geometry = AllSites())])
        for _ in 1:L   # exactly K = L scalar coins
            rand(twin)
        end
        @test rand(copy(get_rng(st.rng_registry, :gates_spacetime))) == rand(copy(twin))
    end

    @testset "event log: eager sentinels (step=0, op_idx=0, real element k)" begin
        L = 4
        st = _eager_test_state(L = L, log_events = true)
        apply_with_prob!(st; outcomes = [
            (probability = 1.0, gate = PauliX(), geometry = EachSite(1:L))])
        evs = [e for e in events(st) if e isa GateApplied]
        @test length(evs) == L
        @test all(e -> e.step == 0 && e.op_idx == 0, evs)
        @test [e.element_idx for e in evs] == collect(1:L)
        @test [e.sites for e in evs] == [[i] for i in 1:L]
        # Measurement outcomes carry the same eager sentinels
        st2 = _eager_test_state(L = L, log_events = true)
        apply_with_prob!(st2; outcomes = [
            (probability = 1.0, gate = Measure(:Z), geometry = AllSites())])
        ms = measurements(st2)
        @test length(ms) == L
        @test all(m -> m.step == 0 && m.op_idx == 0, ms)
    end

    @testset "selection matches select_outcome_index element-by-element" begin
        # Behavioral proof of single-source delegation: replay the eager
        # call's selections with select_outcome_index on a twin RNG.
        L = 6
        probs = [0.35, 0.4]   # Σp < 1 → identity possible
        st = _eager_test_state(L = L, log_events = true, gs = 7)
        twin = copy(get_rng(st.rng_registry, :gates_spacetime))
        apply_with_prob!(st;
            outcomes = [
                (probability = probs[1], gate = PauliX(), geometry = EachSite(1:L)),
                (probability = probs[2], gate = PauliZ(), geometry = EachSite(1:L))])
        expected = [QuantumCircuitsMPS.select_outcome_index(twin, probs) for _ in 1:L]
        evs = [e for e in events(st) if e isa GateApplied]
        applied = Dict(e.element_idx => e.gate_label for e in evs)
        for k in 1:L
            if expected[k] == 0
                @test !haskey(applied, k)
            else
                @test applied[k] == (expected[k] == 1 ? "X" : "Z")
            end
        end
    end
end
