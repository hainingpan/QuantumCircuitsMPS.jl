# === Task 15: Visualization rewire tests (v0.1) ===
# expand_circuit/expand_circuit_grouped delegate stochastic selection to the
# ENGINE's select_outcome_index (single source of truth); validate_geometry
# accepts the v0.1 geometries (EachSite, Sites); record!-marker pseudo-ops
# render in print_circuit / plot_circuit.

using Test
using QuantumCircuitsMPS
using QuantumCircuitsMPS: events, is_record_mark, expand_circuit_grouped, GateApplied

# Collect (label, sites) sequence of engine gate applications from the event log
function _engine_gate_sequence(circuit; L, bc, gates_spacetime, n_steps)
    state = SimulationState(L=L, bc=bc,
        rng=RNGRegistry(gates_spacetime=gates_spacetime, gates_realization=7, born_measurement=11),
        log_events=true)
    initialize!(state, ProductState(binary_int=0))
    simulate!(circuit, state; n_steps=n_steps, record_when=:final_only)
    return [(e.gate_label, e.sites) for e in events(state) if e isa GateApplied]
end

_expand_gate_sequence(circuit; seed, n_steps) =
    [(op.label, op.sites) for step_ops in expand_circuit(circuit; seed=seed, n_steps=n_steps)
                          for op in step_ops if !is_record_mark(op)]

@testset "Visualization rewire (Task 15)" begin

    @testset "SINGLE SOURCE: expand selections == engine selections (same seed)" begin
        @testset "multi-outcome compound (categorical per element, Σp=1)" begin
            L = 8
            circuit = Circuit(L=L, bc=:periodic) do c
                apply_with_prob!(c; outcomes=[
                    (probability=0.5, gate=HaarRandom(), geometry=Bricklayer(:even)),
                    (probability=0.5, gate=CZ(), geometry=Bricklayer(:even))
                ])
            end
            for seed in (9, 42, 123)
                exp_seq = _expand_gate_sequence(circuit; seed=seed, n_steps=3)
                eng_seq = _engine_gate_sequence(circuit; L=L, bc=:periodic,
                                                gates_spacetime=seed, n_steps=3)
                @test exp_seq == eng_seq
                # Σp = 1 → every element slot fires exactly one gate: K=4 per step
                @test length(exp_seq) == 3 * 4
                # exclusive choice: labels only from the two outcomes
                @test all(lbl in ("Haar", "CZ") for (lbl, _) in exp_seq)
            end
        end

        @testset "single-outcome compound with identity remainder (Σp<1)" begin
            L = 6
            circuit = Circuit(L=L, bc=:open) do c
                apply!(c, HaarRandom(), Bricklayer(:even))
                apply_with_prob!(c; outcomes=[
                    (probability=0.3, gate=Measurement(:Z), geometry=AllSites())
                ])
            end
            for seed in (1, 42)
                exp_seq = _expand_gate_sequence(circuit; seed=seed, n_steps=5)
                eng_seq = _engine_gate_sequence(circuit; L=L, bc=:open,
                                                gates_spacetime=seed, n_steps=5)
                @test exp_seq == eng_seq
            end
        end

        @testset "K=1 staircase CIPT branch (bit-compat path)" begin
            L = 8
            left = StaircaseLeft(L)
            right = StaircaseRight(L)
            circuit = Circuit(L=L, bc=:periodic) do c
                apply_with_prob!(c; outcomes=[
                    (probability=0.5, gate=Reset(), geometry=left),
                    (probability=0.5, gate=HaarRandom(), geometry=right)
                ])
            end
            exp_seq = _expand_gate_sequence(circuit; seed=42, n_steps=10)
            eng_seq = _engine_gate_sequence(circuit; L=L, bc=:periodic,
                                            gates_spacetime=42, n_steps=10)
            @test exp_seq == eng_seq
            @test length(exp_seq) == 10   # Σp=1, K=1 → one gate per step
        end

        @testset "select_branch is gone (no duplicate selection logic)" begin
            @test !isdefined(QuantumCircuitsMPS, :select_branch)
        end
    end

    @testset "validate_geometry accepts v0.1 geometries" begin
        @test QuantumCircuitsMPS.validate_geometry(Sites(1:3)) === nothing
        @test QuantumCircuitsMPS.validate_geometry(EachSite(2:5)) === nothing
        @test QuantumCircuitsMPS.validate_geometry(AllSites()) === nothing
        # Pointer remains unsupported (position depends on runtime outcomes)
        @test_throws ArgumentError QuantumCircuitsMPS.validate_geometry(Pointer(1))
    end

    @testset "Sites geometry visualizes (Task 11 flagged gap)" begin
        circuit = Circuit(L=6, bc=:open) do c
            apply!(c, HaarRandom(), Sites(2:3))
        end
        out = sprint(io -> print_circuit(circuit; gates_spacetime=0, io=io))
        @test !isempty(out)
        @test contains(out, "Haar")

        ops = expand_circuit(circuit; seed=0)[1]
        @test length(ops) == 1
        @test ops[1].sites == [2, 3]
    end

    @testset "ProductGate circuit visualizes without throwing" begin
        circuit = Circuit(L=8, bc=:periodic) do c
            apply!(c, ProductGate(HaarRandom(), Bricklayer(:even)))
        end
        out = sprint(io -> print_circuit(circuit; gates_spacetime=0, io=io))
        @test !isempty(out)
        @test contains(out, "∏Haar")
    end

    @testset "EachSite (SRN bulk eligibility) visualizes" begin
        L = 8
        circuit = Circuit(L=L, bc=:open) do c
            apply!(c, HaarRandom(), Bricklayer(:even))
            apply_with_prob!(c; outcomes=[
                (probability=1.0, gate=Measurement(:Z), geometry=EachSite(2:L-1))
            ])
        end
        out = sprint(io -> print_circuit(circuit; gates_spacetime=0, io=io))
        @test contains(out, "Haar")
        @test contains(out, "Meas")   # p=1 → all bulk sites measured
        # engine/expand agreement holds for EachSite too
        @test _expand_gate_sequence(circuit; seed=5, n_steps=2) ==
              _engine_gate_sequence(circuit; L=L, bc=:open, gates_spacetime=5, n_steps=2)
    end

    @testset "record_mark pseudo-ops (Task 13 forward-compat)" begin
        # Hand-built circuit: Task 13's builder is not required for these ops
        # to render (markers are (type=:record_mark, ...) NamedTuples).
        operations = NamedTuple[
            (type=:deterministic, gate=PauliX(), geometry=SingleSite(1)),
            (type=:record_mark,),
            (type=:record_mark, names=(:entropy,)),
        ]
        circuit = Circuit(L=4, bc=:open, operations=operations)

        grouped = expand_circuit_grouped(circuit; n_steps=2, seed=0)
        @test length(grouped) == 2
        @test length(grouped[1]) == 3          # gate group + 2 marker groups
        m1, m2 = grouped[1][2][1], grouped[1][3][1]
        @test is_record_mark(m1) && is_record_mark(m2)
        @test m1.gate === nothing && isempty(m1.sites)
        @test m1.label == "[R]"
        @test m2.label == "[R:entropy]"

        # print_circuit renders the marker glyph
        out_uni = sprint(io -> print_circuit(circuit; gates_spacetime=0, io=io))
        @test contains(out_uni, "▽")
        @test contains(out_uni, "[R:entropy]")   # named marker annotated
        out_ascii = sprint(io -> print_circuit(circuit; gates_spacetime=0, io=io, unicode=false))
        @test contains(out_ascii, "[R]")

        # non-marker ops are untouched
        @test contains(out_uni, "X")
    end

    @testset "Unknown op types are skipped, never crash (forward-compat)" begin
        operations = NamedTuple[
            (type=:deterministic, gate=PauliZ(), geometry=SingleSite(2)),
            (type=:some_future_op, payload=1),
        ]
        circuit = Circuit(L=4, bc=:open, operations=operations)
        ops = expand_circuit(circuit; seed=0)[1]
        @test length(ops) == 1
        @test ops[1].label == "Z"
        out = sprint(io -> print_circuit(circuit; gates_spacetime=0, io=io))
        @test contains(out, "Z")
    end

    @testset "Luxor plot_circuit with markers + Sites" begin
        operations = NamedTuple[
            (type=:deterministic, gate=HaarRandom(), geometry=Sites(2:3)),
            (type=:record_mark, names=(:entropy,)),
        ]
        circuit = Circuit(L=4, bc=:open, operations=operations)
        try
            Base.require(Main, :Luxor)
            svg_path = tempname() * ".svg"
            plot_circuit(circuit; gates_spacetime=0, filename=svg_path)
            svg = read(svg_path, String)
            rm(svg_path)
            @test contains(svg, "<svg")
        catch e
            if e isa ArgumentError && contains(string(e), "Package Luxor not found")
                @test_skip "Luxor not available - skipping SVG marker test"
            else
                rethrow(e)
            end
        end
    end
end
