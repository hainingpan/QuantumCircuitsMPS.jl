# test/recording_test.jl
# Comprehensive tests for the record_when recording API in simulate!()

using Test
using QuantumCircuitsMPS

@testset "Recording API Tests" begin
    # Helper function to create fresh state for each test
    function make_state()
        state = SimulationState(L=4, bc=:open; rng=RNGRegistry(ctrl=42, proj=43, haar=44, born=45))
        initialize!(state, ProductState(binary_int=1))
        track!(state, :dw => DomainWall(order=1, i1_fn=() -> 1))
        return state
    end
    
    # Standard test circuit (4 gates per circuit)
    # Operations per timestep: 2 (HaarRandom+StaircaseRight, Reset+SingleSite)
    # Total gates per circuit: 2 steps × 2 ops = 4 gates
    function make_circuit()
        Circuit(L=4, bc=:open, n_steps=2) do c
            apply!(c, HaarRandom(), StaircaseRight(1))
            apply!(c, Reset(), SingleSite(2))
        end
    end
    
    @testset "Test 1: :every_step" begin
        # Records once per circuit (at step boundary of last step)
        # With n_circuits=2: expect 2 records
        state = make_state()
        circuit = make_circuit()
        simulate!(circuit, state; n_circuits=2, record_when=:every_step)
        @test length(state.observables[:dw]) == 2
    end
    
    @testset "Test 2: :every_gate" begin
        # Records after each gate
        # With n_circuits=2 and 4 gates per circuit: expect 8 records
        state = make_state()
        circuit = make_circuit()
        simulate!(circuit, state; n_circuits=2, record_when=:every_gate)
        @test length(state.observables[:dw]) == 8  # 2 circuits × 4 gates
    end
    
    @testset "Test 3: :final_only" begin
        # Records once at the very end
        # With n_circuits=2: expect 1 record
        state = make_state()
        circuit = make_circuit()
        simulate!(circuit, state; n_circuits=2, record_when=:final_only)
        @test length(state.observables[:dw]) == 1
    end
    
    @testset "Test 4: every_n_gates(4)" begin
        # Records at gate indices divisible by 4
        # With n_circuits=3 and 4 gates per circuit: 12 total gates
        # Triggers at gates 4, 8, 12 → 3 records
        state = make_state()
        circuit = make_circuit()
        simulate!(circuit, state; n_circuits=3, record_when=every_n_gates(4))
        @test length(state.observables[:dw]) == 3
    end
    
    @testset "Test 5: every_n_steps(2)" begin
        # Records at step boundaries where step_idx % 2 == 0
        # With n_circuits=4: steps complete at circuit ends (circuits 1, 2, 3, 4)
        # Divisible by 2: circuits 2, 4 → 2 records
        state = make_state()
        circuit = make_circuit()
        simulate!(circuit, state; n_circuits=4, record_when=every_n_steps(2))
        @test length(state.observables[:dw]) == 2
    end
    
    @testset "Test 6: Custom lambda" begin
        # Custom lambda: records only when gate_idx == 1
        # With n_circuits=2: gate_idx=1 happens once → 1 record
        state = make_state()
        circuit = make_circuit()
        simulate!(circuit, state; n_circuits=2, record_when=ctx -> ctx.gate_idx == 1)
        @test length(state.observables[:dw]) == 1
    end
    
    @testset "Test 7: DEFAULT (no kwarg)" begin
        # When record_when not provided, defaults to :every_step
        # With n_circuits=2: expect 2 records (same as :every_step)
        state = make_state()
        circuit = make_circuit()
        simulate!(circuit, state; n_circuits=2)  # No record_when - uses default
        @test length(state.observables[:dw]) == 2
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
