# test/recording_test.jl
# Comprehensive tests for the record_when recording API in simulate!()

using Test
using QuantumCircuitsMPS

@testset "Recording API Tests" begin
    # Helper function to create fresh state for each test
    function make_state()
        state = SimulationState(L = 4,
            bc = :open;
            rng = RNGRegistry(gates_spacetime = 42, gates_realization = 44, born_measurement = 45))
        initialize!(state, ProductState(binary_int = 1))
        track!(state, :dw => DomainWall(order = 1, i1_fn = () -> 1))
        return state
    end

    # Standard test circuit (2 gates per step)
    # Operations per step: 2 (HaarRandom+StaircaseRight, Reset+SingleSite)
    # Total gates per n_steps: n_steps × 2 ops
    function make_circuit()
        Circuit(L = 4, bc = :open) do c
            apply!(c, HaarRandom(), StaircaseRight(1))
            apply!(c, Reset(), SingleSite(2))
        end
    end

    @testset "Test 1: :every_step" begin
        # Records once per step (at step boundary)
        # With n_steps=4: expect 4 records (one per do-block execution)
        state = make_state()
        circuit = make_circuit()
        simulate!(circuit, state; n_steps = 4, record_when = :every_step)
        @test length(state.observables[:dw]) == 4
    end

    @testset "Test 2: :every_gate" begin
        # Records after each gate
        # With n_steps=4 and 2 gates per step: expect 8 records
        state = make_state()
        circuit = make_circuit()
        simulate!(circuit, state; n_steps = 4, record_when = :every_gate)
        @test length(state.observables[:dw]) == 8  # 4 steps × 2 gates
    end

    @testset "Test 3: :final_only" begin
        # Records once at the very end
        # With n_steps=4: expect 1 record (always exactly 1)
        state = make_state()
        circuit = make_circuit()
        simulate!(circuit, state; n_steps = 4, record_when = :final_only)
        @test length(state.observables[:dw]) == 1
    end

    @testset "Test 4: every_n_gates(4)" begin
        # Records at gate indices divisible by 4
        # With n_steps=6 and 2 gates per step: 12 total gates
        # Triggers at gates 4, 8, 12 → 3 records
        state = make_state()
        circuit = make_circuit()
        simulate!(circuit, state; n_steps = 6, record_when = every_n_gates(4))
        @test length(state.observables[:dw]) == 3
    end

    @testset "Test 5: every_n_steps(2)" begin
        # Records at step boundaries where step_idx % 2 == 0
        # With n_steps=8: step_idx goes 1..8, fires at 2, 4, 6, 8 → 4 records
        state = make_state()
        circuit = make_circuit()
        simulate!(circuit, state; n_steps = 8, record_when = every_n_steps(2))
        @test length(state.observables[:dw]) == 4
    end

    @testset "Test 6: Custom lambda" begin
        # Custom lambda: records only when gate_idx == 1
        # gate_idx is cumulative and never resets; fires once → 1 record
        state = make_state()
        circuit = make_circuit()
        simulate!(circuit, state; n_steps = 4, record_when = ctx -> ctx.gate_idx == 1)
        @test length(state.observables[:dw]) == 1
    end

    @testset "Test 7: DEFAULT (no kwarg)" begin
        # When record_when not provided, defaults to :every_step
        # With n_steps=4: expect 4 records (one per step)
        state = make_state()
        circuit = make_circuit()
        simulate!(circuit, state; n_steps = 4)  # No record_when - uses default
        @test length(state.observables[:dw]) == 4
    end

    @testset "RecordingContext struct" begin
        # Test that RecordingContext has expected fields (positional args)
        ctx = RecordingContext(5, 10, :Reset, true)
        @test ctx.step_idx == 5
        @test ctx.gate_idx == 10
        @test ctx.gate_type == :Reset
        @test ctx.is_step_boundary == true
    end

    @testset "every_n_gates preset function" begin
        # Test the helper function behavior
        pred = every_n_gates(5)

        # gate_idx divisible by 5 → true
        @test pred(RecordingContext(1, 5, :X, false)) == true
        @test pred(RecordingContext(2, 10, :X, false)) == true

        # gate_idx NOT divisible by 5 → false
        @test pred(RecordingContext(1, 3, :X, false)) == false
        @test pred(RecordingContext(1, 7, :X, false)) == false
    end

    @testset "every_n_steps preset function" begin
        # Test the helper function behavior
        pred = every_n_steps(3)

        # step_idx divisible by 3 AND is_step_boundary → true
        @test pred(RecordingContext(3, 1, :X, true)) == true
        @test pred(RecordingContext(6, 1, :X, true)) == true

        # step_idx divisible by 3 BUT NOT step boundary → false
        @test pred(RecordingContext(3, 1, :X, false)) == false

        # is_step_boundary BUT step_idx NOT divisible by 3 → false
        @test pred(RecordingContext(4, 1, :X, true)) == false
    end
end
