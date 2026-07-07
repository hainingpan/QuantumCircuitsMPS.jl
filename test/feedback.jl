# === Task 10: Feedback system tests ===
# Measure(:Z; feedback=...), OnOutcome, CallbackFeedback auto-wrap, Reset sugar
# equivalence, sentinel guard on :gates_spacetime during feedback.

using Test
using Random
using QuantumCircuitsMPS
using QuantumCircuitsMPS: events, measurements  # ITensorMPS also exports `measurements`
using QuantumCircuitsMPS: GateApplied  # internal since Task 14 (not in manifest)
using ITensorMPS: norm

# Fresh state helper: L sites, |0...0>, independent streams
function _fb_state(; L::Int = 4, seeds = (11, 22, 33), maxdim::Int = 32, log_events::Bool = false)
    st = SimulationState(L = L, bc = :periodic, maxdim = maxdim,
        rng = RNGRegistry(gates_spacetime = seeds[1], gates_realization = seeds[2],
            born_measurement = seeds[3]),
        log_events = log_events)
    initialize!(st, ProductState(binary_int = 0))
    return st
end

@testset "Feedback system (Measure/OnOutcome/CallbackFeedback)" begin
    @testset "Constructors and traits" begin
        m = Measure()
        @test m.basis == :Z
        @test m.feedback === nothing
        @test Measure(:Z).basis == :Z
        @test_throws ArgumentError Measure(:X)

        # OnOutcome typed feedback
        fb = OnOutcome(1 => PauliX())
        @test fb isa QuantumCircuitsMPS.AbstractFeedback
        m2 = Measure(:Z; feedback = fb)
        @test m2.feedback === fb
        # multiple pairs
        fb2 = OnOutcome(0 => Rz(0.3), 1 => HaarRandom(1))
        @test length(fb2.actions) == 2
        @test fb2.actions[0] isa Rz
        @test fb2.actions[1] isa HaarRandom
        # duplicate outcome keys rejected
        @test_throws ArgumentError OnOutcome(1 => PauliX(), 1 => PauliY())
        # empty rejected
        @test_throws ArgumentError OnOutcome()

        # raw function auto-wrapped as CallbackFeedback
        f = (st, s, o) -> nothing
        m3 = Measure(:Z; feedback = f)
        @test m3.feedback isa QuantumCircuitsMPS.CallbackFeedback
        @test m3.feedback.f === f

        # invalid feedback value → informative error
        @test_throws ArgumentError Measure(:Z; feedback = 42)

        # gate traits
        @test QuantumCircuitsMPS.support(Measure()) == 1
        @test QuantumCircuitsMPS.is_measurement(Measure()) == true
        @test QuantumCircuitsMPS.needs_normalization(Measure()) == false
        @test QuantumCircuitsMPS.gate_label(Measure()) == "Meas"
    end

    @testset "Measure without feedback == Measurement (bit-identical)" begin
        for seed in (1, 7, 42)
            st1 = _fb_state(seeds = (seed, seed + 100, seed + 200))
            st2 = _fb_state(seeds = (seed, seed + 100, seed + 200))
            apply!(st1, HaarRandom(), Bricklayer(:odd))
            apply!(st2, HaarRandom(), Bricklayer(:odd))
            apply!(st1, Measurement(:Z), SingleSite(2))
            apply!(st2, Measure(:Z), SingleSite(2))
            for i in 1:4
                @test born_probability(st1, i, 0) == born_probability(st2, i, 0)
            end
        end
    end

    @testset "Measure consumes exactly one :born_measurement draw" begin
        st = _fb_state(seeds = (11, 22, 33))
        apply!(st, Hadamard(), SingleSite(1))
        twin = MersenneTwister(33)
        apply!(st, Measure(:Z), SingleSite(1))
        rand(twin)  # the one Born draw
        @test rand(copy(get_rng(st.rng_registry, :born_measurement))) == rand(copy(twin))
    end

    @testset "OnOutcome dispatch" begin
        # |1⟩ measured → outcome 1 → PauliX flips back to |0⟩
        st = _fb_state()
        apply!(st, PauliX(), SingleSite(2))
        apply!(st, Measure(:Z; feedback = OnOutcome(1 => PauliX())), SingleSite(2))
        @test born_probability(st, 2, 0) ≈ 1.0 atol=1e-12

        # |0⟩ measured → outcome 0 → no action registered for 0 → stays |0⟩
        st = _fb_state()
        apply!(st, Measure(:Z; feedback = OnOutcome(1 => PauliX())), SingleSite(2))
        @test born_probability(st, 2, 0) ≈ 1.0 atol=1e-12

        # action on outcome 0: |0⟩ → measured 0 → PauliX → |1⟩
        st = _fb_state()
        apply!(st, Measure(:Z; feedback = OnOutcome(0 => PauliX())), SingleSite(3))
        @test born_probability(st, 3, 1) ≈ 1.0 atol=1e-12
    end

    @testset "Reset() == Measure(:Z; feedback=OnOutcome(1 => PauliX())) (20 seeds)" begin
        for seed in 1:20
            seeds = (seed, seed + 1000, seed + 2000)
            st1 = _fb_state(seeds = seeds)
            st2 = _fb_state(seeds = seeds)
            # identical preparation (entangle everything)
            for st in (st1, st2)
                apply!(st, HaarRandom(), Bricklayer(:odd))
                apply!(st, HaarRandom(), Bricklayer(:even))
            end
            apply!(st1, Reset(), SingleSite(2))
            apply!(st2, Measure(:Z; feedback = OnOutcome(1 => PauliX())), SingleSite(2))
            for i in 1:4
                @test isapprox(born_probability(st1, i, 0),
                    born_probability(st2, i, 0); atol = 1e-14)
            end
        end
    end

    @testset "Closure feedback receives (state, sites::Vector{Int}, outcome)" begin
        captured = Ref{Any}(nothing)
        st = _fb_state()
        apply!(st, PauliX(), SingleSite(3))
        m = Measure(:Z; feedback = (s, sites, o) -> (captured[] = (s, sites, o)))
        apply!(st, m, SingleSite(3))
        s, sites, o = captured[]
        @test s === st
        @test sites isa Vector{Int}
        @test sites == [3]
        @test o == 1  # site was deterministically |1⟩
    end

    @testset "Random-unitary feedback (user's motivating case)" begin
        st = _fb_state()
        apply!(st, PauliX(), SingleSite(1))  # force outcome 1
        m = Measure(:Z; feedback = (s, sites, o) -> o == 1 &&
                                                    apply!(s, HaarRandom(1), SingleSite(sites[1])))
        apply!(st, m, SingleSite(1))
        @test abs(norm(st.mps) - 1) < 1e-10
        # feedback Haar must NOT have touched :gates_spacetime
        @test rand(copy(get_rng(st.rng_registry, :gates_spacetime))) ==
              rand(copy(MersenneTwister(11)))
        # but it DID consume :gates_realization
        @test rand(copy(get_rng(st.rng_registry, :gates_realization))) !=
              rand(copy(MersenneTwister(22)))
    end

    @testset "Sentinel: feedback cannot consume :gates_spacetime" begin
        bad = Measure(:Z; feedback = (s, sites, o) -> QuantumCircuitsMPS.draw(s, :gates_spacetime))
        st = _fb_state()
        err = try
            apply!(st, bad, SingleSite(1))
            nothing
        catch e
            e
        end
        @test err isa ErrorException
        @test occursin("forbidden", sprint(showerror, err))
        # stream restored after the throw (try/finally in with_guarded_stream)
        @test QuantumCircuitsMPS.draw(st, :gates_spacetime) isa Float64

        # :gates_realization and :born_measurement remain usable inside feedback
        ok = Measure(:Z; feedback = (s, sites, o) -> QuantumCircuitsMPS.draw(s, :gates_realization))
        st2 = _fb_state()
        apply!(st2, ok, SingleSite(1))  # must not throw
        @test true
    end

    @testset "Recursive feedback (Measure inside feedback) does not crash" begin
        inner = Measure(:Z; feedback = OnOutcome(1 => PauliX()))
        outer = Measure(:Z; feedback = (s, sites, o) -> apply!(s, inner, [sites[1]]))
        st = _fb_state()
        apply!(st, PauliX(), SingleSite(2))
        apply!(st, outer, SingleSite(2))
        # outer collapses to |1⟩; inner re-measures (deterministic 1) then flips → |0⟩
        @test born_probability(st, 2, 0) ≈ 1.0 atol=1e-12
    end

    @testset "Geometry dispatch: Measure works via SingleSite/AllSites/Sites" begin
        st = _fb_state()
        apply!(st, PauliX(), SingleSite(1))
        apply!(st, PauliX(), SingleSite(3))
        apply!(st, Measure(:Z; feedback = OnOutcome(1 => PauliX())), AllSites())
        for i in 1:4
            @test born_probability(st, i, 0) ≈ 1.0 atol=1e-12
        end
        st2 = _fb_state()
        apply!(st2, PauliX(), SingleSite(2))
        apply!(st2, Measure(:Z; feedback = OnOutcome(1 => PauliX())), Sites([2]))
        @test born_probability(st2, 2, 0) ≈ 1.0 atol=1e-12
    end

    @testset "Engine integration: Measure + feedback inside apply_with_prob!" begin
        haar_fb = (s, sites, o) -> o == 1 && apply!(s, HaarRandom(1), SingleSite(sites[1]))
        build() = Circuit(L = 4, bc = :periodic) do c
            apply!(c, HaarRandom(), Bricklayer(:odd))
            apply_with_prob!(c;
                outcomes = [
                    (probability = 1.0,
                    gate = Measure(:Z; feedback = haar_fb),
                    geometry = EachSite(1:4))
                ])
        end
        mkstate() = _fb_state(log_events = true)

        st = mkstate()
        track!(st, :entropy => EntanglementEntropy(cut = 2))
        simulate!(build(), st; n_steps = 3, record_when = :every_step)
        @test abs(norm(st.mps) - 1) < 1e-10
        meas = measurements(st)
        @test length(meas) == 12  # 4 sites × 3 steps, p=1.0
        @test all(m -> m.step in 1:3, meas)
        @test all(m -> m.op_idx == 2, meas)  # second op in the circuit

        # feedback gates emit NO GateApplied (not engine ops, no counter effect)
        gates = filter(e -> e isa GateApplied, events(st))
        @test all(g -> g.gate_label != "Haar" || g.op_idx == 1, gates)
        # exactly K=4 "Meas" GateApplied per step
        meas_gates = filter(g -> g.gate_label == "Meas", gates)
        @test length(meas_gates) == 12

        # fixed-draw contract: feedback must not perturb :gates_spacetime.
        # Run the same circuit WITHOUT feedback; stream states must match.
        build_nofb() = Circuit(L = 4, bc = :periodic) do c
            apply!(c, HaarRandom(), Bricklayer(:odd))
            apply_with_prob!(c; outcomes = [
                (probability = 1.0, gate = Measure(:Z), geometry = EachSite(1:4))
            ])
        end
        st_a = mkstate();
        simulate!(build(), st_a; n_steps = 3, record_when = :final_only)
        st_b = mkstate();
        simulate!(build_nofb(), st_b; n_steps = 3, record_when = :final_only)
        @test rand(copy(get_rng(st_a.rng_registry, :gates_spacetime))) ==
              rand(copy(get_rng(st_b.rng_registry, :gates_spacetime)))
    end

    @testset "SpinSectorMeasurement + feedback → informative error" begin
        err = try
            SpinSectorMeasurement([0, 1]; feedback = OnOutcome(1 => PauliX()))
            nothing
        catch e
            e
        end
        @test err isa ArgumentError
        @test occursin("feedback", sprint(showerror, err))
        @test occursin("v0.1", sprint(showerror, err))
        # default construction (no feedback) unchanged
        @test SpinSectorMeasurement([0, 1]).sectors == [0, 1]
        @test SpinSectorMeasurement().sectors == [0, 1, 2]
    end

    @testset "build_operator on Measure throws (Born sampling required)" begin
        st = _fb_state()
        site_idx = st.sites[1]
        @test_throws ErrorException QuantumCircuitsMPS.build_operator(Measure(), site_idx, 2)
    end
end
