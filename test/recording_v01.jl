# === Task 13: Recording rework (v0.1) ===
# record!(c[, names...]) markers, record_when=:marks policy, conflict rules,
# RecordingContext extension (op_idx/element_idx/at_mark/mark_index),
# record_value uniform observable hook (DomainWall special case removed).

using Test
using QuantumCircuitsMPS
using Random

# Top-level (structs cannot be defined inside @testset scope):
# a user observable proving record_value is a uniform extension point.
if !@isdefined(_Task13ConstObs)
    struct _Task13ConstObs <: QuantumCircuitsMPS.AbstractObservable end
    (::_Task13ConstObs)(state) = 1.0
    QuantumCircuitsMPS.record_value(::_Task13ConstObs, state; i1 = nothing) = 42.0
end

@testset "Recording v0.1 (markers, :marks policy, record_value hook)" begin

    # Shared helpers ------------------------------------------------------
    function fresh_state(L; bc = :periodic, seeds = (42, 1, 2))
        st = SimulationState(L = L, bc = bc, maxdim = 64,
            rng = RNGRegistry(gates_spacetime = seeds[1], born_measurement = seeds[2],
                gates_realization = seeds[3]))
        initialize!(st, ProductState(binary_int = 0))
        return st
    end

    srn_circuit(L; with_markers = true) = Circuit(L = L, bc = :periodic) do c
        apply!(c, HaarRandom(), Bricklayer(:even))
        apply_with_prob!(c;
            outcomes = [
                (probability = 0.05, gate = Measurement(:Z),
                geometry = EachSite(2:(L - 1)))
            ])
        with_markers && record!(c)
        apply!(c, HaarRandom(), Bricklayer(:odd))
        apply_with_prob!(c; outcomes = [
            (probability = 0.05, gate = Measurement(:Z), geometry = AllSites())
        ])
        with_markers && record!(c)
    end

    @testset "record!(builder) pushes :record_mark pseudo-ops" begin
        circuit = Circuit(L = 4, bc = :periodic) do c
            apply!(c, HaarRandom(), Bricklayer(:even))
            record!(c)
            record!(c, :entropy)
            record!(c, :a, :b)
        end
        marks = [op for op in circuit.operations if op.type == :record_mark]
        @test length(marks) == 3
        @test marks[1].names == Symbol[]
        @test marks[2].names == Symbol[:entropy]
        @test marks[3].names == Symbol[:a, :b]
        # markers carry no gate/geometry/rng payload
        @test !haskey(marks[1], :gate)
        @test !haskey(marks[1], :geometry)
        # markers do not contribute to the coin budget
        nomark = Circuit(L = 4, bc = :periodic) do c
            apply!(c, HaarRandom(), Bricklayer(:even))
        end
        @test expected_draws(circuit, 10) == expected_draws(nomark, 10) == 0
    end

    @testset ":marks — SRN pattern exact counts under heavy do-nothing" begin
        L = 8
        circuit = srn_circuit(L)
        state = fresh_state(L)
        track!(state, :entropy => EntanglementEntropy(cut = L ÷ 2))
        simulate!(circuit, state; n_steps = 25, record_when = :marks)
        # 2 markers x 25 steps = exactly 50 records, even at p=0.05
        @test length(state.observables[:entropy]) == 50

        # Deterministic: rerun with same seeds -> identical record vector
        circuit2 = srn_circuit(L)
        state2 = fresh_state(L)
        track!(state2, :entropy => EntanglementEntropy(cut = L ÷ 2))
        simulate!(circuit2, state2; n_steps = 25, record_when = :marks)
        @test state2.observables[:entropy] == state.observables[:entropy]
    end

    @testset "markers never touch RNG streams or physics" begin
        L = 8
        n = 10
        # A: marker-less circuit, record only at the very end
        cA = srn_circuit(L; with_markers = false)
        sA = fresh_state(L)
        track!(sA, :entropy => EntanglementEntropy(cut = L ÷ 2))
        simulate!(cA, sA; n_steps = n, record_when = :final_only)
        # B: same circuit body + markers (last marker is the last op)
        cB = srn_circuit(L; with_markers = true)
        sB = fresh_state(L)
        track!(sB, :entropy => EntanglementEntropy(cut = L ÷ 2))
        simulate!(cB, sB; n_steps = n, record_when = :marks)

        # Identical trajectory: B's final-marker record == A's only record
        @test length(sA.observables[:entropy]) == 1
        @test length(sB.observables[:entropy]) == 2n
        @test sB.observables[:entropy][end] == sA.observables[:entropy][1]

        # All four stream fingerprints identical after the runs
        for stream in (:gates_spacetime, :gates_realization, :born_measurement)
            @test rand(get_rng(sA.rng_registry, stream)) ==
                  rand(get_rng(sB.rng_registry, stream))
        end

        # Coin budget unchanged by markers
        @test expected_draws(cA, n) == expected_draws(cB, n)
    end

    @testset "conflict: markers + symbol policy throws prescriptively" begin
        L = 6
        circuit = srn_circuit(L)
        for policy in (:every_step, :every_gate, :final_only)
            state = fresh_state(L)
            track!(state, :entropy => EntanglementEntropy(cut = L ÷ 2))
            err = try
                simulate!(circuit, state; n_steps = 2, record_when = policy)
                nothing
            catch e
                e
            end
            @test err isa ArgumentError
            msg = sprint(showerror, err)
            @test occursin("markers", msg)
            @test occursin(":marks", msg)
            @test occursin(string(policy), msg)
        end
        # The DEFAULT (:every_step) must also trip the conflict
        state = fresh_state(L)
        track!(state, :entropy => EntanglementEntropy(cut = L ÷ 2))
        @test_throws ArgumentError simulate!(circuit, state; n_steps = 2)
    end

    @testset ":marks on a marker-less circuit throws" begin
        L = 6
        circuit = srn_circuit(L; with_markers = false)
        state = fresh_state(L)
        track!(state, :entropy => EntanglementEntropy(cut = L ÷ 2))
        err = try
            simulate!(circuit, state; n_steps = 2, record_when = :marks)
            nothing
        catch e
            e
        end
        @test err isa ArgumentError
        @test occursin("no markers", sprint(showerror, err))
        # unknown symbols still rejected (and :auto stays dead)
        @test_throws ArgumentError simulate!(circuit, state; n_steps = 1, record_when = :auto)
    end

    @testset "selective markers record only the named observables" begin
        L = 6
        circuit = Circuit(L = L, bc = :periodic) do c
            apply!(c, HaarRandom(), Bricklayer(:even))
            record!(c, :entropy)
            record!(c)
        end
        state = fresh_state(L)
        track!(state, :entropy => EntanglementEntropy(cut = L ÷ 2))
        track!(state, :mz => Magnetization(:Z))
        simulate!(circuit, state; n_steps = 5, record_when = :marks)
        # entropy grows at BOTH markers, mz only at the unfiltered one
        @test length(state.observables[:entropy]) == 10
        @test length(state.observables[:mz]) == 5
    end

    @testset "selective marker naming an untracked observable throws" begin
        L = 4
        circuit = Circuit(L = L, bc = :periodic) do c
            apply!(c, HaarRandom(), Bricklayer(:even))
            record!(c, :not_tracked)
        end
        state = fresh_state(L)
        track!(state, :entropy => EntanglementEntropy(cut = L ÷ 2))
        err = try
            simulate!(circuit, state; n_steps = 1, record_when = :marks)
            nothing
        catch e
            e
        end
        @test err isa ArgumentError
        @test occursin("not_tracked", sprint(showerror, err))
    end

    @testset "no double record when marker is the last op (:marks)" begin
        L = 4
        circuit = Circuit(L = L, bc = :periodic) do c
            apply!(c, HaarRandom(), Bricklayer(:even))
            record!(c)
        end
        state = fresh_state(L)
        track!(state, :entropy => EntanglementEntropy(cut = L ÷ 2))
        simulate!(circuit, state; n_steps = 7, record_when = :marks)
        @test length(state.observables[:entropy]) == 7   # never 14
    end

    @testset "predicate mode sees marks (at_mark / mark_index)" begin
        L = 6
        circuit = srn_circuit(L)
        seen = RecordingContext[]
        state = fresh_state(L)
        track!(state, :entropy => EntanglementEntropy(cut = L ÷ 2))
        simulate!(circuit, state; n_steps = 3,
            record_when = ctx -> (push!(seen, ctx); false))
        @test isempty(state.observables[:entropy])

        mark_ctxs = [c for c in seen if c.at_mark]
        @test length(mark_ctxs) == 6                     # 2 markers x 3 steps
        @test sort(unique(c.mark_index for c in mark_ctxs)) == [1, 2]
        @test all(c -> c.gate_type === nothing, mark_ctxs)
        @test all(c -> !c.is_step_boundary, mark_ctxs)

        boundary_ctxs = [c for c in seen if c.is_step_boundary]
        @test length(boundary_ctxs) == 3
        @test all(c -> !c.at_mark && c.mark_index == 0, boundary_ctxs)

        # slot contexts carry populated op_idx/element_idx
        slot_ctxs = [c for c in seen if !c.at_mark && !c.is_step_boundary]
        @test all(c -> c.op_idx >= 1, slot_ctxs)
        @test all(c -> c.element_idx >= 1, slot_ctxs)
        # op 1 = Bricklayer(:even) Haar on L=6 -> elements 1..3
        op1 = [c for c in slot_ctxs if c.op_idx == 1 && c.step_idx == 1]
        @test [c.element_idx for c in op1] == [1, 2, 3]

        # Predicate firing at marks -> flag semantics: ONE record per step
        state2 = fresh_state(L)
        track!(state2, :entropy => EntanglementEntropy(cut = L ÷ 2))
        circuit2 = srn_circuit(L)
        simulate!(circuit2, state2; n_steps = 4, record_when = ctx -> ctx.at_mark)
        @test length(state2.observables[:entropy]) == 4

        # mark_index-selective predicate still one record per step
        state3 = fresh_state(L)
        track!(state3, :entropy => EntanglementEntropy(cut = L ÷ 2))
        circuit3 = srn_circuit(L)
        simulate!(circuit3, state3; n_steps = 4,
            record_when = ctx -> ctx.at_mark && ctx.mark_index == 2)
        @test length(state3.observables[:entropy]) == 4
    end

    @testset "markers do not advance gate_idx" begin
        L = 6
        gmax_marked = Ref(0)
        gmax_plain = Ref(0)
        cM = srn_circuit(L; with_markers = true)
        sM = fresh_state(L)
        simulate!(cM, sM; n_steps = 3,
            record_when = ctx -> (gmax_marked[] = max(gmax_marked[], ctx.gate_idx); false))
        cP = srn_circuit(L; with_markers = false)
        sP = fresh_state(L)
        simulate!(cP, sP; n_steps = 3,
            record_when = ctx -> (gmax_plain[] = max(gmax_plain[], ctx.gate_idx); false))
        @test gmax_marked[] == gmax_plain[]
    end

    @testset ":every_step regression — trailing stochastic do-nothing (marker-less)" begin
        L = 6
        circuit = Circuit(L = L, bc = :periodic) do c
            apply!(c, HaarRandom(), Bricklayer(:even))
            apply_with_prob!(c;
                outcomes = [
                    (probability = 0.01, gate = Measurement(:Z), geometry = AllSites())
                ])
        end
        state = fresh_state(L)
        track!(state, :entropy => EntanglementEntropy(cut = L ÷ 2))
        simulate!(circuit, state; n_steps = 25, record_when = :every_step)
        @test length(state.observables[:entropy]) == 25   # never 24 (old bug)
    end

    @testset "RecordingContext: new fields + 4-arg convenience constructor" begin
        full = RecordingContext(2, 7, 3, 4, :X, false, true, 2)
        @test full.step_idx == 2 && full.gate_idx == 7
        @test full.op_idx == 3 && full.element_idx == 4
        @test full.gate_type == :X && !full.is_step_boundary
        @test full.at_mark && full.mark_index == 2

        legacy = RecordingContext(5, 10, :Reset, true)
        @test legacy.step_idx == 5 && legacy.gate_idx == 10
        @test legacy.gate_type == :Reset && legacy.is_step_boundary
        @test legacy.op_idx == 0 && legacy.element_idx == 0
        @test !legacy.at_mark && legacy.mark_index == 0
    end

    @testset "record_value uniform hook (DomainWall behavior preserved)" begin
        L = 4
        state = fresh_state(L)

        # Default hook == obs(state)
        ent = EntanglementEntropy(cut = L ÷ 2)
        @test QuantumCircuitsMPS.record_value(ent, state) == ent(state)

        # DomainWall with i1_fn: record! works without i1
        dw_fn = DomainWall(order = 1, i1_fn = () -> 1)
        track!(state, :dw => dw_fn)
        record!(state)
        @test length(state.observables[:dw]) == 1
        @test state.observables[:dw][1] == dw_fn(state)

        # DomainWall without i1_fn: explicit i1 required, value preserved
        state2 = fresh_state(L)
        dw = DomainWall(order = 1)
        track!(state2, :dw => dw)
        record!(state2; i1 = 1)
        @test state2.observables[:dw][1] == dw(state2, 1)
        @test state2.observables[:dw][1] == state.observables[:dw][1]
        # and record! without i1 throws (behavior preserved)
        @test_throws ArgumentError record!(state2)

        # record_value dispatch parity with the old special-case branch
        @test QuantumCircuitsMPS.record_value(dw_fn, state) == dw_fn(state)
        @test QuantumCircuitsMPS.record_value(dw, state2; i1 = 1) == dw(state2, 1)
        @test_throws ArgumentError QuantumCircuitsMPS.record_value(dw, state2)
    end

    @testset "user observable can override record_value (uniform extension point)" begin
        L = 4
        state = fresh_state(L)
        obs = _Task13ConstObs()
        track!(state, :c => obs)
        record!(state)
        @test state.observables[:c] == [42.0]   # override wins over obs(state)=1.0
    end

    @testset "record!(state; only=...) selective eager recording" begin
        L = 4
        state = fresh_state(L)
        track!(state, :entropy => EntanglementEntropy(cut = L ÷ 2))
        track!(state, :mz => Magnetization(:Z))
        record!(state; only = [:entropy])
        @test length(state.observables[:entropy]) == 1
        @test isempty(state.observables[:mz])
        record!(state)
        @test length(state.observables[:entropy]) == 2
        @test length(state.observables[:mz]) == 1
        @test_throws ArgumentError record!(state; only = [:nope])
    end
end
