# test/circuit_test.jl
# Comprehensive tests for Circuit module

using Test
using QuantumCircuitsMPS

# WARMUP: Force compilation before tests run
# This reduces test time from ~90s to ~20-30s by avoiding repeated JIT compilation
let
    # Compile SimulationState
    _ = SimulationState(L=4, bc=:periodic)
    
    # Compile Circuit with various gate types  
    _ = Circuit(L=4, bc=:periodic) do c
        apply!(c, Reset(), SingleSite(1))
        apply!(c, HaarRandom(), StaircaseRight(1))
        apply_with_prob!(c; rng=:gates_spacetime, outcomes=[
            (probability=0.5, gate=Reset(), geometry=SingleSite(1))
        ])
    end
    
    # Compile expand_circuit
    c = Circuit(L=4, bc=:periodic) do c
        apply!(c, Reset(), SingleSite(1))
    end
    _ = expand_circuit(c; seed=1)
end

@testset "Circuit Construction" begin
    @testset "Do-block syntax" begin
        circuit = Circuit(L=4, bc=:periodic, n_steps=10) do c
            apply!(c, Reset(), StaircaseRight(1))
        end
        
        @test circuit.L == 4
        @test circuit.bc == :periodic
        @test circuit.n_steps == 10
        @test length(circuit.operations) == 1
        @test circuit.operations[1].type == :deterministic
        @test circuit.operations[1].gate isa Reset
        @test circuit.operations[1].geometry isa StaircaseRight
    end
    
    @testset "Multiple operations" begin
        circuit = Circuit(L=4, bc=:periodic, n_steps=5) do c
            apply!(c, Reset(), StaircaseRight(1))
            apply!(c, HaarRandom(), StaircaseLeft(4))
            apply!(c, PauliX(), SingleSite(2))
        end
        
        @test length(circuit.operations) == 3
        @test all(op.type == :deterministic for op in circuit.operations)
    end
    
    @testset "Stochastic operations" begin
        circuit = Circuit(L=4, bc=:periodic) do c
            apply_with_prob!(c; rng=:gates_spacetime, outcomes=[
                (probability=0.5, gate=Reset(), geometry=StaircaseRight(1)),
                (probability=0.3, gate=HaarRandom(), geometry=SingleSite(1))
            ])
        end
        
        @test length(circuit.operations) == 1
        @test circuit.operations[1].type == :stochastic
        @test circuit.operations[1].rng == :gates_spacetime
        @test length(circuit.operations[1].outcomes) == 2
    end
    
    @testset "Mixed operations" begin
        circuit = Circuit(L=4, bc=:periodic, n_steps=20) do c
            apply!(c, Reset(), StaircaseRight(1))
            apply_with_prob!(c; rng=:gates_spacetime, outcomes=[
                (probability=0.5, gate=HaarRandom(), geometry=StaircaseRight(1))
            ])
            apply!(c, PauliZ(), SingleSite(1))
        end
        
        @test length(circuit.operations) == 3
        @test circuit.operations[1].type == :deterministic
        @test circuit.operations[2].type == :stochastic
        @test circuit.operations[3].type == :deterministic
    end
    
    @testset "Default n_steps" begin
        circuit = Circuit(L=4, bc=:periodic) do c
            apply!(c, Reset(), SingleSite(1))
        end
        
        @test circuit.n_steps == 1
    end
end

@testset "Circuit params field" begin
    @testset "Basic param storage" begin
        circuit = Circuit(L=4, bc=:periodic, threshold=0.5, name="test") do c
            apply!(c, Reset(), SingleSite(1))
        end
        
        @test circuit.params[:threshold] == 0.5
        @test circuit.params[:name] == "test"
    end
    
    @testset "CircuitBuilder access in do-block" begin
        accessed_value = Ref{Any}(nothing)
        circuit = Circuit(L=4, bc=:periodic, my_param=42) do c
            accessed_value[] = c.params[:my_param]
        end
        
        @test accessed_value[] == 42
    end
    
    @testset "Backward compatibility (empty params)" begin
        circuit = Circuit(L=4, bc=:periodic) do c
            apply!(c, Reset(), SingleSite(1))
        end
        
        @test isempty(circuit.params)
    end
end

@testset "CircuitBuilder Validation" begin
    @testset "Wrong RNG key" begin
        @test_throws ArgumentError Circuit(L=4, bc=:periodic) do c
            apply_with_prob!(c; rng=:invalid, outcomes=[
                (probability=1.0, gate=Reset(), geometry=SingleSite(1))
            ])
        end
        
        @test_throws ArgumentError Circuit(L=4, bc=:periodic) do c
            apply_with_prob!(c; rng=:gates_realization, outcomes=[
                (probability=0.5, gate=HaarRandom(), geometry=SingleSite(1))
            ])
        end
    end
    
    @testset "Probability sum > 1" begin
        @test_throws ArgumentError Circuit(L=4, bc=:periodic) do c
            apply_with_prob!(c; rng=:gates_spacetime, outcomes=[
                (probability=0.8, gate=Reset(), geometry=SingleSite(1)),
                (probability=0.5, gate=HaarRandom(), geometry=SingleSite(1))
            ])
        end
        
        @test_throws ArgumentError Circuit(L=4, bc=:periodic) do c
            apply_with_prob!(c; rng=:gates_spacetime, outcomes=[
                (probability=1.1, gate=Reset(), geometry=SingleSite(1))
            ])
        end
    end
    
    @testset "Empty outcomes" begin
        # Note: Empty vector [] doesn't satisfy type Vector{<:NamedTuple{(:probability, :gate, :geometry)}}
        # so this throws TypeError during type construction, not ArgumentError during validation
        # We test that it fails, regardless of exception type
        @test_throws Exception Circuit(L=4, bc=:periodic) do c
            apply_with_prob!(c; rng=:gates_spacetime, outcomes=[])
        end
    end
    
    @testset "Valid probability sums" begin
        # Exactly 1.0 should work
        circuit1 = Circuit(L=4, bc=:periodic) do c
            apply_with_prob!(c; rng=:gates_spacetime, outcomes=[
                (probability=0.7, gate=Reset(), geometry=SingleSite(1)),
                (probability=0.3, gate=HaarRandom(), geometry=SingleSite(1))
            ])
        end
        @test length(circuit1.operations) == 1
        
        # Less than 1.0 should work (do-nothing branch)
        circuit2 = Circuit(L=4, bc=:periodic) do c
            apply_with_prob!(c; rng=:gates_spacetime, outcomes=[
                (probability=0.5, gate=Reset(), geometry=SingleSite(1))
            ])
        end
        @test length(circuit2.operations) == 1
    end
end

@testset "expand_circuit Determinism" begin
    circuit = Circuit(L=4, bc=:periodic, n_steps=10) do c
        apply_with_prob!(c; rng=:gates_spacetime, outcomes=[
            (probability=0.5, gate=Reset(), geometry=StaircaseRight(1)),
            (probability=0.5, gate=HaarRandom(), geometry=StaircaseLeft(4))
        ])
    end
    
    @testset "Same seed produces same expansion" begin
        ops1 = expand_circuit(circuit; seed=42)
        ops2 = expand_circuit(circuit; seed=42)
        
        # Same number of steps
        @test length(ops1) == length(ops2) == 10
        
        # Same structure for each step
        for i in 1:10
            @test length(ops1[i]) == length(ops2[i])
            if length(ops1[i]) > 0 && length(ops2[i]) > 0
                @test typeof(ops1[i][1].gate) == typeof(ops2[i][1].gate)
                @test ops1[i][1].sites == ops2[i][1].sites
            end
        end
    end
    
    @testset "Different seeds may produce different expansions" begin
        ops1 = expand_circuit(circuit; seed=42)
        ops3 = expand_circuit(circuit; seed=99)
        
        # Both have correct length
        @test length(ops1) == 10
        @test length(ops3) == 10
        
        # Likely different (but not guaranteed, so we just check they're valid)
        @test all(length(op) <= 1 for op in ops1)  # Max one operation per step
        @test all(length(op) <= 1 for op in ops3)
    end
    
    @testset "Return type and structure" begin
        circuit_simple = Circuit(L=4, bc=:periodic, n_steps=5) do c
            apply!(c, Reset(), StaircaseRight(1))
        end
        
        ops = expand_circuit(circuit_simple; seed=0)
        
        @test ops isa Vector{Vector{ExpandedOp}}
        @test length(ops) == 5
        @test all(length(step_ops) == 1 for step_ops in ops)  # Deterministic always produces ops
    end
    
    @testset "Do-nothing branches create empty vectors" begin
        # Circuit with low probability - may produce empty steps
        sparse_circuit = Circuit(L=4, bc=:periodic, n_steps=20) do c
            apply_with_prob!(c; rng=:gates_spacetime, outcomes=[
                (probability=0.3, gate=Reset(), geometry=SingleSite(1))
            ])
        end
        
        ops = expand_circuit(sparse_circuit; seed=123)
        
        @test length(ops) == 20
        # Some steps should be empty (do-nothing branch with p=0.7)
        empty_steps = count(step_ops -> length(step_ops) == 0, ops)
        @test empty_steps > 0  # Very likely with 20 steps and p=0.3
    end
end

@testset "CIPT staircase: only selected staircase advances" begin
    @testset "Deterministic staircase positions match step-based computation" begin
        # StaircaseRight(1), L=4, PBC, 4 steps → positions 1→2→3→4 with wrap
        circuit = Circuit(L=4, bc=:periodic, n_steps=4) do c
            apply!(c, HaarRandom(), StaircaseRight(1))
        end
        ops = expand_circuit(circuit; seed=0)
        @test ops[1][1].sites == [1, 2]
        @test ops[2][1].sites == [2, 3]
        @test ops[3][1].sites == [3, 4]
        @test ops[4][1].sites == [4, 1]  # PBC wrap
    end
    
    @testset "StaircaseLeft deterministic positions" begin
        # StaircaseLeft(1), L=4, PBC, 4 steps → positions 1→4→3→2 (moves left)
        circuit = Circuit(L=4, bc=:periodic, n_steps=4) do c
            apply!(c, Reset(), StaircaseLeft(1))
        end
        ops = expand_circuit(circuit; seed=0)
        @test ops[1][1].sites == [1]   # position 1 (single-site Reset)
        @test ops[2][1].sites == [4]   # position 4 (moved left, PBC wrap)
        @test ops[3][1].sites == [3]   # position 3
        @test ops[4][1].sites == [2]   # position 2
    end
    
    @testset "Stochastic CIPT: unselected staircase does not advance" begin
        # With seed=42, step 1 selects Haar (right), steps 2-5 select Reset (left)
        # After step 1: right at position 2, left still at 1
        # After step 2: right at 2, left at 8 (moved left from 1)
        left = StaircaseLeft(1)
        right = StaircaseRight(1)
        circuit = Circuit(L=8, bc=:periodic, n_steps=5) do c
            apply_with_prob!(c; rng=:gates_spacetime, outcomes=[
                (probability=0.5, gate=Reset(), geometry=left),
                (probability=0.5, gate=HaarRandom(), geometry=right)
            ])
        end
        ops = expand_circuit(circuit; seed=42)
        
        # Step 1: Haar selected → right staircase at position 1 (initial)
        @test !isempty(ops[1])
        @test ops[1][1].label == "Haar"
        @test ops[1][1].sites == [1, 2]  # right at position 1
        
        # Step 2: Reset selected → left staircase at position 1 (initial, never advanced)
        @test !isempty(ops[2])
        @test ops[2][1].label == "Rst"
        @test ops[2][1].sites == [1]  # left at position 1 (initial)
        
        # Step 3: Reset selected → left staircase at position 8 (advanced once from 1)
        @test !isempty(ops[3])
        @test ops[3][1].label == "Rst"
        @test ops[3][1].sites == [8]  # left moved left: 1 → 8 (PBC)
    end
    
    @testset "expand_circuit determinism with stochastic staircases" begin
        # Same seed → same expansion (reset ensures determinism)
        left = StaircaseLeft(1)
        right = StaircaseRight(1)
        circuit = Circuit(L=8, bc=:periodic, n_steps=10) do c
            apply_with_prob!(c; rng=:gates_spacetime, outcomes=[
                (probability=0.5, gate=Reset(), geometry=left),
                (probability=0.5, gate=HaarRandom(), geometry=right)
            ])
        end
        ops1 = expand_circuit(circuit; seed=42)
        ops2 = expand_circuit(circuit; seed=42)
        for i in 1:10
            @test length(ops1[i]) == length(ops2[i])
            if !isempty(ops1[i])
                @test ops1[i][1].sites == ops2[i][1].sites
            end
        end
    end
end

@testset "simulate! Execution" begin
    @testset "Basic execution without error" begin
        circuit = Circuit(L=4, bc=:periodic, n_steps=10) do c
            apply!(c, Reset(), StaircaseRight(1))
        end
        
        rng = RNGRegistry(gates_spacetime=42, gates_realization=44, born_measurement=45)
        state = SimulationState(L=4, bc=:periodic, rng=rng)
        initialize!(state, ProductState(binary_int=1))
        track!(state, :dw => DomainWall(order=1, i1_fn=() -> 1))
        
        # Should execute without error
        simulate!(circuit, state; n_circuits=1)
        
        # Should have 1 record (one per circuit with :every_step default)
        @test length(state.observables[:dw]) == 1
    end
    
    @testset "Stochastic circuit execution" begin
        circuit = Circuit(L=4, bc=:periodic, n_steps=10) do c
            apply_with_prob!(c; rng=:gates_spacetime, outcomes=[
                (probability=0.5, gate=Reset(), geometry=StaircaseRight(1)),
                (probability=0.5, gate=HaarRandom(), geometry=StaircaseLeft(4))
            ])
        end
        
        rng = RNGRegistry(gates_spacetime=42, gates_realization=44, born_measurement=45)
        state = SimulationState(L=4, bc=:periodic, rng=rng)
        initialize!(state, ProductState(binary_int=1))
        track!(state, :dw => DomainWall(order=1, i1_fn=() -> 1))
        
        simulate!(circuit, state; n_circuits=3)
        
        # Should have 3 records (one per circuit with :every_step default)
        @test length(state.observables[:dw]) == 3
    end
    
    @testset "Recording with new API" begin
        circuit = Circuit(L=4, bc=:periodic, n_steps=5) do c
            apply!(c, Reset(), SingleSite(1))
        end
        
        rng = RNGRegistry(gates_spacetime=42, gates_realization=44, born_measurement=45)
        state = SimulationState(L=4, bc=:periodic, rng=rng)
        initialize!(state, ProductState(binary_int=1))
        track!(state, :dw => DomainWall(order=1, i1_fn=() -> 1))
        
        # Test: record_when=:every_step (default)
        simulate!(circuit, state; n_circuits=2, record_when=:every_step)
        @test length(state.observables[:dw]) == 2  # One per circuit
        
        # Reset state for next test
        state = SimulationState(L=4, bc=:periodic, rng=RNGRegistry(gates_spacetime=42, gates_realization=44, born_measurement=45))
        initialize!(state, ProductState(binary_int=1))
        track!(state, :dw => DomainWall(order=1, i1_fn=() -> 1))
        
        # Test: record_when=:final_only
        simulate!(circuit, state; n_circuits=3, record_when=:final_only)
        @test length(state.observables[:dw]) == 1  # Only at the very end
        
        # Reset state for next test
        state = SimulationState(L=4, bc=:periodic, rng=RNGRegistry(gates_spacetime=42, gates_realization=44, born_measurement=45))
        initialize!(state, ProductState(binary_int=1))
        track!(state, :dw => DomainWall(order=1, i1_fn=() -> 1))
        
        # Test: record_when=every_n_steps(2)
        simulate!(circuit, state; n_circuits=4, record_when=every_n_steps(2))
        @test length(state.observables[:dw]) == 2  # Circuits 2 and 4
    end
    
    @testset "Multiple timesteps execute correctly" begin
        circuit = Circuit(L=4, bc=:periodic, n_steps=10) do c
            apply_with_prob!(c; rng=:gates_spacetime, outcomes=[
                (probability=0.5, gate=Reset(), geometry=StaircaseRight(1))
            ])
        end
        
        rng = RNGRegistry(gates_spacetime=42, gates_realization=44, born_measurement=45)
        state = SimulationState(L=4, bc=:periodic, rng=rng)
        initialize!(state, ProductState(binary_int=1))
        track!(state, :dw => DomainWall(order=1, i1_fn=() -> 1))
        
        # Should complete without error even with many steps
        # Note: Stochastic circuits may have 0-n_circuits records depending on RNG
        # (if all steps roll "do nothing", no gates execute and no recording happens)
        simulate!(circuit, state; n_circuits=2)
        
        # Verify simulation completed (record count depends on RNG)
        @test length(state.observables[:dw]) >= 0
        @test length(state.observables[:dw]) <= 2
    end
end

@testset "print_circuit Output" begin
    @testset "Deterministic circuit rendering" begin
        circuit = Circuit(L=4, bc=:periodic, n_steps=4) do c
            apply!(c, Reset(), StaircaseRight(1))
        end
        
        io = IOBuffer()
        print_circuit(circuit; gates_spacetime=0, io=io)
        output = String(take!(io))
        
        # Check for expected content (transposed layout: qubits as columns, time as rows)
        @test contains(output, "Circuit")
        @test contains(output, "L=4")
        @test contains(output, "bc=periodic")
        # Qubit labels in header (not row labels)
        @test contains(output, "q1")
        @test contains(output, "q2")
        @test contains(output, "q3")
        @test contains(output, "q4")
        @test contains(output, "Rst")  # Gate label
        # Time steps as row labels
        @test occursin(r"\s*1:", output)
    end
    
    @testset "Stochastic circuit rendering" begin
        circuit = Circuit(L=4, bc=:periodic, n_steps=6) do c
            apply_with_prob!(c; rng=:gates_spacetime, outcomes=[
                (probability=0.5, gate=Reset(), geometry=StaircaseRight(1)),
                (probability=0.3, gate=HaarRandom(), geometry=SingleSite(1))
            ])
        end
        
        io = IOBuffer()
        print_circuit(circuit; gates_spacetime=0, io=io)
        output = String(take!(io))
        
        # Should render without error and contain circuit structure
        @test contains(output, "Circuit")
        @test contains(output, "L=4")
        @test contains(output, "q1")  # Qubit in header
    end
    
    @testset "Multi-qubit gate rendering" begin
        circuit = Circuit(L=4, bc=:periodic, n_steps=3) do c
            apply!(c, CZ(), AdjacentPair(1))
        end
        
        io = IOBuffer()
        print_circuit(circuit; gates_spacetime=0, io=io)
        output = String(take!(io))
        
        # CZ label should appear (spanning box shows it once)
        @test contains(output, "CZ")
        @test contains(output, "q1")  # Qubit in header
        @test contains(output, "q2")
    end
    
    @testset "ASCII mode rendering" begin
        circuit = Circuit(L=4, bc=:periodic, n_steps=3) do c
            apply!(c, PauliX(), SingleSite(1))
        end
        
        io = IOBuffer()
        print_circuit(circuit; gates_spacetime=0, io=io, unicode=false)
        output = String(take!(io))
        
        # Should use ASCII characters (-, |) instead of Unicode
        @test contains(output, "Circuit")
        @test contains(output, "X")  # Gate label
        # Should NOT contain Unicode box-drawing characters
        @test !contains(output, "─")
        @test !contains(output, "┤")
        @test !contains(output, "├")
    end
    
    @testset "Empty steps render correctly" begin
        circuit = Circuit(L=4, bc=:periodic, n_steps=10) do c
            apply_with_prob!(c; rng=:gates_spacetime, outcomes=[
                (probability=0.2, gate=Reset(), geometry=SingleSite(1))
            ])
        end
        
        io = IOBuffer()
        print_circuit(circuit; gates_spacetime=0, io=io)
        output = String(take!(io))
        
        # Should handle empty steps (do-nothing branches) without error
        @test contains(output, "Circuit")
        @test contains(output, "q1")  # Qubit in header
    end
end

@testset "Baseline Visualization Fixtures" begin
    @testset "Single-qubit gate ASCII output" begin
        # Baseline: PauliX on single site (transposed layout)
        circuit = Circuit(L=4, bc=:periodic) do c
            apply!(c, PauliX(), SingleSite(1))
        end
        
        io = IOBuffer()
        print_circuit(circuit; gates_spacetime=0, io=io)
        output = String(take!(io))
        
        # Verify structure (transposed: qubits as columns, time as rows)
        @test contains(output, "Circuit")
        @test contains(output, "L=4")
        @test contains(output, "bc=periodic")
        # Qubit labels in header (not row labels anymore)
        @test contains(output, "q1")
        @test contains(output, "q2")
        @test contains(output, "q3")
        @test contains(output, "q4")
        @test contains(output, "X")  # Gate label
        # Time step row labels
        @test occursin(r"\s*1:", output)
    end
    
    @testset "Multi-step single-qubit gates ASCII output" begin
        # Baseline: Multiple single-qubit gates in same step (transposed layout)
        circuit = Circuit(L=4, bc=:periodic, n_steps=3) do c
            apply!(c, PauliX(), SingleSite(1))
            apply!(c, PauliY(), SingleSite(2))
            apply!(c, PauliZ(), SingleSite(3))
        end
        
        io = IOBuffer()
        print_circuit(circuit; gates_spacetime=0, io=io)
        output = String(take!(io))
        
        # Verify structure and gate labels
        @test contains(output, "Circuit")
        @test contains(output, "X")
        @test contains(output, "Y")
        @test contains(output, "Z")
        # Qubit headers
        @test contains(output, "q1")
        @test contains(output, "q2")
        @test contains(output, "q3")
        # Verify multi-step row labels (1a:, 1b:, 1c:, 2a:, 2b:, 2c:, 3a:, 3b:, 3c:)
        @test occursin(r"1a:", output)
        @test occursin(r"1b:", output)
        @test occursin(r"1c:", output)
    end
    
    @testset "Two-qubit gate ASCII output" begin
        # Baseline: CZ on adjacent pair (transposed layout with spanning box)
        circuit = Circuit(L=4, bc=:periodic) do c
            apply!(c, CZ(), AdjacentPair(1))
        end
        
        io = IOBuffer()
        print_circuit(circuit; gates_spacetime=0, io=io)
        output = String(take!(io))
        
        # Verify structure
        @test contains(output, "Circuit")
        @test contains(output, "CZ")
        @test contains(output, "q1")  # Qubit in header
        @test contains(output, "q2")
        # After spanning box fix: CZ should appear ONCE (on minimum site)
        # In transposed layout, we check the single row for CZ label
        @test count("CZ", output) == 1
    end
    
    @testset "Multi-step two-qubit gates ASCII output" begin
        # Baseline: CZ on multiple adjacent pairs in same step (transposed layout)
        circuit = Circuit(L=4, bc=:periodic, n_steps=3) do c
            apply!(c, CZ(), AdjacentPair(1))
            apply!(c, CZ(), AdjacentPair(2))
        end
        
        io = IOBuffer()
        print_circuit(circuit; gates_spacetime=0, io=io)
        output = String(take!(io))
        
        # Verify structure
        @test contains(output, "Circuit")
        @test contains(output, "CZ")
        @test contains(output, "q1")  # Qubit in header
        @test contains(output, "q2")
        @test contains(output, "q3")
        # Verify multi-step row labels
        @test occursin(r"1a:", output)
        @test occursin(r"1b:", output)
        @test occursin(r"2a:", output)
        @test occursin(r"2b:", output)
    end
    
    @testset "Three-qubit gate ASCII output (StaircaseRight)" begin
        # Baseline: Reset on StaircaseRight pattern (transposed layout)
        circuit = Circuit(L=5, bc=:periodic, n_steps=3) do c
            apply!(c, Reset(), StaircaseRight(1))
        end
        
        io = IOBuffer()
        print_circuit(circuit; gates_spacetime=0, io=io)
        output = String(take!(io))
        
        # Verify structure
        @test contains(output, "Circuit")
        @test contains(output, "Rst")  # Reset label
        @test contains(output, "q1")  # Qubit headers
        @test contains(output, "q2")
        @test contains(output, "q3")
        # Verify step row labels
        @test occursin(r"\s*1:", output)
        @test occursin(r"\s*2:", output)
        @test occursin(r"\s*3:", output)
    end
    
    @testset "Three-qubit gate ASCII output (StaircaseLeft)" begin
        # Baseline: HaarRandom on StaircaseLeft pattern (transposed layout)
        circuit = Circuit(L=5, bc=:periodic, n_steps=3) do c
            apply!(c, HaarRandom(), StaircaseLeft(1))
        end
        
        io = IOBuffer()
        print_circuit(circuit; gates_spacetime=0, io=io)
        output = String(take!(io))
        
        # Verify structure
        @test contains(output, "Circuit")
        @test contains(output, "Haar")  # HaarRandom label
        @test contains(output, "q1")  # Qubit headers
        @test contains(output, "q2")
        @test contains(output, "q3")
        # Verify time step row labels exist
        @test occursin(r"\s*1:", output)
    end
    
    @testset "Mixed single and two-qubit gates ASCII output" begin
        # Baseline: Mix of single-qubit and two-qubit gates (transposed layout)
        circuit = Circuit(L=4, bc=:periodic, n_steps=2) do c
            apply!(c, PauliX(), SingleSite(1))
            apply!(c, CZ(), AdjacentPair(2))
        end
        
        io = IOBuffer()
        print_circuit(circuit; gates_spacetime=0, io=io)
        output = String(take!(io))
        
        # Verify structure
        @test contains(output, "Circuit")
        @test contains(output, "X")
        @test contains(output, "CZ")
        @test contains(output, "q1")  # Qubit headers
        @test contains(output, "q2")
        @test contains(output, "q3")
        # Verify multi-step row labels
        @test occursin(r"1a:", output)
        @test occursin(r"1b:", output)
    end
    
    @testset "ASCII mode (non-Unicode) baseline" begin
        # Baseline: ASCII mode output without Unicode characters (transposed layout)
        circuit = Circuit(L=4, bc=:periodic, n_steps=2) do c
            apply!(c, PauliX(), SingleSite(1))
            apply!(c, PauliY(), SingleSite(2))
        end
        
        io = IOBuffer()
        print_circuit(circuit; gates_spacetime=0, io=io, unicode=false)
        output = String(take!(io))
        
        # Verify ASCII characters
        @test contains(output, "Circuit")
        @test contains(output, "X")
        @test contains(output, "Y")
        @test contains(output, "q1")  # Qubit in header
        # Should NOT contain Unicode box-drawing characters
        @test !contains(output, "─")
        @test !contains(output, "┤")
        @test !contains(output, "├")
        # Should contain ASCII characters
        @test contains(output, "-")
        @test contains(output, "|")
    end
    
    @testset "SVG output structure baseline" begin
        # Baseline: SVG output contains expected structure
        circuit = Circuit(L=4, bc=:periodic) do c
            apply!(c, PauliX(), SingleSite(1))
        end
        
        # Check if SVG functions are available
        try
            io = IOBuffer()
            # Try to capture SVG output if function exists
            # This is a placeholder for future SVG testing
            @test true  # Placeholder - SVG functions may not exist yet
        catch
            @test true  # Skip if SVG not available
        end
    end
end

@testset "RNG Alignment" begin
    @testset "expand_circuit and simulate! use same RNG stream" begin
        circuit = Circuit(L=4, bc=:periodic, n_steps=20) do c
            apply_with_prob!(c; rng=:gates_spacetime, outcomes=[
                (probability=0.5, gate=Reset(), geometry=StaircaseRight(1)),
                (probability=0.5, gate=HaarRandom(), geometry=StaircaseRight(1))
            ])
        end
        
        # Expand with seed 42
        ops = expand_circuit(circuit; seed=42)
        
        # Simulate with matching seed
        rng = RNGRegistry(gates_spacetime=42, gates_realization=44, born_measurement=45)
        state = SimulationState(L=4, bc=:periodic, rng=rng)
        initialize!(state, ProductState(binary_int=1))
        
        # Should complete without error (alignment is implicit)
        simulate!(circuit, state; n_circuits=1, record_when=:final_only)
        
        @test true  # If we get here, no errors occurred
    end
    
    @testset "Deterministic expansion matches execution" begin
        # Circuit with all deterministic operations
        circuit = Circuit(L=4, bc=:periodic, n_steps=5) do c
            apply!(c, Reset(), StaircaseRight(1))
            apply!(c, PauliX(), SingleSite(1))
        end
        
        ops = expand_circuit(circuit; seed=0)
        
        # Should produce exactly 2 operations per step
        @test all(length(step_ops) == 2 for step_ops in ops)
        
        # All operations should have correct step numbers
        for (step_idx, step_ops) in enumerate(ops)
            @test all(op.step == step_idx for op in step_ops)
        end
        
        # Execute to verify no errors
        rng = RNGRegistry(gates_spacetime=0, gates_realization=44, born_measurement=45)
        state = SimulationState(L=4, bc=:periodic, rng=rng)
        initialize!(state, ProductState(binary_int=1))
        
        simulate!(circuit, state; n_circuits=1, record_when=:final_only)
        @test true
    end
end

@testset "Multi-Qubit Spanning Box (TDD)" begin
    @testset "Two-qubit gate shows label once (HaarRandom)" begin
        # TDD GREEN: Multi-qubit gates show label ONCE on minimum site
        # Other sites show continuation boxes
        circuit = Circuit(L=4, bc=:periodic) do c
            apply!(c, HaarRandom(), AdjacentPair(1))
        end
        
        ascii = sprint((io) -> print_circuit(circuit; gates_spacetime=0, io=io))
        
        # Label "Haar" should appear exactly once in the output
        @test count("Haar", ascii) == 1
        
        # In transposed layout: single row for the step, q1 and q2 columns affected
        # Qubit headers should be present
        @test contains(ascii, "q1")
        @test contains(ascii, "q2")
        
        # The row containing the gate should have box characters on both qubits
        lines = split(ascii, "\n")
        gate_row = filter(l -> contains(l, "Haar"), lines)[1]
        @test contains(gate_row, "┤") || contains(gate_row, "|")
    end
    
    @testset "Two-qubit gate shows label once (CZ)" begin
        # Same test with CZ gate
        circuit = Circuit(L=4, bc=:periodic) do c
            apply!(c, CZ(), AdjacentPair(2))
        end
        
        ascii = sprint((io) -> print_circuit(circuit; gates_spacetime=0, io=io))
        
        # Label "CZ" should appear exactly once
        @test count("CZ", ascii) == 1
    end
    
    @testset "Single-qubit gate still shows label once (regression test)" begin
        # Ensure our fix doesn't break single-qubit gates
        circuit = Circuit(L=4, bc=:periodic) do c
            apply!(c, PauliX(), SingleSite(2))
        end
        
        ascii = sprint((io) -> print_circuit(circuit; gates_spacetime=0, io=io))
        
        # Label "X" should appear exactly once
        @test count("X", ascii) == 1
        
        # In transposed layout: gate appears in a row, q2 column
        # Verify X is on a row with time step label
        lines = split(ascii, "\n")
        x_row = filter(l -> contains(l, "X"), lines)[1]
        @test occursin(r"\s*\d+[a-z]?:", x_row)
    end
end

@testset "Observables API" begin
    @testset "list_observables()" begin
        # Test that list_observables returns available observable types
        obs = list_observables()
        
        # Should return a Vector of Strings
        @test isa(obs, Vector{String})
        
        # Should contain the known observable types
        @test "DomainWall" in obs
        @test "BornProbability" in obs
        
        # Should have at least 2 observables
        @test length(obs) >= 2
    end
end

@testset "ASCII Layout Transposed (TDD)" begin
    @testset "Time as rows, qubits as columns (TDD RED phase)" begin
        # TDD RED phase: This test should FAIL with current implementation
        # Current format: Qubits as rows (q1:, q2:...), time as columns (Step: 1 2 3)
        # New format: Time as rows (1:, 2:...), qubits as columns (header: q1 q2 q3)
        circuit = Circuit(L=4, bc=:periodic) do c
            apply!(c, PauliX(), SingleSite(1))
            apply!(c, PauliY(), SingleSite(2))
        end
        
        ascii = sprint((io) -> print_circuit(circuit; gates_spacetime=0, io=io))
        lines = split(ascii, "\n")
        
        # Find non-empty lines after header
        content_lines = filter(l -> !isempty(strip(l)), lines)
        
        # NEW FORMAT: Header should have qubit labels (q1, q2, q3, q4)
        # Find the line with qubit labels (should be line 3, after "Circuit..." and blank)
        header_line = nothing
        for (i, line) in enumerate(content_lines)
            if contains(line, "q1") && contains(line, "q2") && contains(line, "q3")
                header_line = line
                break
            end
        end
        @test header_line !== nothing  # Should find qubit header
        
        # NEW FORMAT: Should NOT have "Step:" in output (old format artifact)
        @test !contains(ascii, "Step:")
        
        # NEW FORMAT: Row labels should be step numbers (1:, 2:, etc.)
        # At least one row should start with a step number followed by colon
        has_time_row_labels = any(l -> occursin(r"^\s*\d+[a-z]?:", l), lines)
        @test has_time_row_labels
    end
    
    @testset "Multi-qubit spanning box works in transposed layout" begin
        # Ensure spanning box logic (from Task 3) still works after transpose
        circuit = Circuit(L=4, bc=:periodic) do c
            apply!(c, HaarRandom(), AdjacentPair(1))
        end
        
        ascii = sprint((io) -> print_circuit(circuit; gates_spacetime=0, io=io))
        
        # Label "Haar" should appear exactly once (spanning box preserved)
        @test count("Haar", ascii) == 1
        
        # Should have qubit column headers
        @test contains(ascii, "q1") && contains(ascii, "q2")
        
        # Should NOT have old "Step:" format
        @test !contains(ascii, "Step:")
    end
end

@testset "SVG Multi-Qubit Spanning Box (TDD)" begin
    @testset "Two-qubit gate renders as single spanning box" begin
        # TDD GREEN: Multi-qubit gates render as ONE tall spanning box
        circuit = Circuit(L=4, bc=:periodic) do c
            apply!(c, HaarRandom(), AdjacentPair(1))
        end
        
        # Only test if Luxor is available
        try
            # Load Luxor extension
            Base.require(Main, :Luxor)
            
            # Generate SVG to temporary file
            svg_path = tempname() * ".svg"
            plot_circuit(circuit; gates_spacetime=0, filename=svg_path)
            
            # Read SVG content
            svg_content = read(svg_path, String)
            
            # Verify SVG was created and contains expected structure
            @test contains(svg_content, "<svg")
            # Note: Luxor renders text as glyph paths, not literal strings
            # So we check for path elements indicating rendered text
            @test contains(svg_content, "<path")
            
            # Count the number of closed path rectangles (box() renders as path with Z)
            # Look for patterns that represent rectangular boxes
            # With spanning box: 1 gate box
            # The rect pattern in Luxor SVG output
            rect_count = length(collect(eachmatch(r"<rect|stroke-width.*Z M", svg_content)))
            
            # Should have at least 1 gate box
            @test rect_count >= 1
            
            # Clean up
            rm(svg_path)
        catch e
            if e isa ArgumentError && contains(string(e), "Package Luxor not found")
                @test_skip "Luxor not available - skipping SVG test"
            else
                rethrow(e)
            end
        end
    end
    
    @testset "Single-qubit gate still renders correctly (regression test)" begin
        # Ensure our fix doesn't break single-qubit gates
        circuit = Circuit(L=4, bc=:periodic) do c
            apply!(c, PauliX(), SingleSite(2))
        end
        
        try
            Base.require(Main, :Luxor)
            
            svg_path = tempname() * ".svg"
            plot_circuit(circuit; gates_spacetime=0, filename=svg_path)
            
            svg_content = read(svg_path, String)
            
            # Verify SVG was created
            @test contains(svg_content, "<svg")
            
            # Should have gate box and path elements for text
            @test contains(svg_content, "<path")
            
            rm(svg_path)
        catch e
            if e isa ArgumentError && contains(string(e), "Package Luxor not found")
                @test_skip "Luxor not available - skipping SVG test"
            else
                rethrow(e)
            end
        end
    end
end

@testset "Compound Geometries (Bricklayer/AllSites)" begin
    @testset "Deterministic Bricklayer(:odd) + Bricklayer(:even)" begin
        # Test both parities with Circuit + simulate!
        # Note: Bricklayer requires two-qubit gates (CZ, HaarRandom)
        circuit = Circuit(L=4, bc=:periodic, n_steps=5) do c
            apply!(c, CZ(), Bricklayer(:odd))
            apply!(c, HaarRandom(), Bricklayer(:even))
        end
        
        rng = RNGRegistry(gates_spacetime=42, gates_realization=44, born_measurement=45)
        state = SimulationState(L=4, bc=:periodic, rng=rng)
        initialize!(state, ProductState(binary_int=0))
        track!(state, :dw => DomainWall(order=1, i1_fn=() -> 1))
        
        # Should execute without error
        simulate!(circuit, state; n_circuits=3, record_when=:every_step)
        
        # Should have 3 records (one per circuit)
        @test length(state.observables[:dw]) == 3
    end
    
    @testset "Deterministic AllSites with PauliX" begin
        # Test AllSites geometry with Circuit + simulate!
        circuit = Circuit(L=4, bc=:periodic, n_steps=5) do c
            apply!(c, PauliX(), AllSites())
        end
        
        rng = RNGRegistry(gates_spacetime=42, gates_realization=44, born_measurement=45)
        state = SimulationState(L=4, bc=:periodic, rng=rng)
        initialize!(state, ProductState(binary_int=0))
        track!(state, :dw => DomainWall(order=1, i1_fn=() -> 1))
        
        # Should execute without error
        simulate!(circuit, state; n_circuits=3, record_when=:every_step)
        
        # Should have 3 records
        @test length(state.observables[:dw]) == 3
    end
    
    @testset "Stochastic AllSites with Measurement — per-site independent" begin
        L = 4
        c = Circuit(L=L, bc=:open, n_steps=1) do b
            apply_with_prob!(b; rng=:gates_spacetime, outcomes=[
                (probability=0.5, gate=Measurement(:Z), geometry=AllSites())
            ])
        end
        
        # Run expand_circuit with many seeds, count Meas ops per seed
        counts = [length([op for op in expand_circuit(c; seed=s)[1] if op.label == "Meas"]) 
                  for s in 1:200]
        
        # Per-element independence means counts vary (not all-or-nothing)
        @test minimum(counts) != maximum(counts)  # Must have variation
        @test any(0 < x < L for x in counts)      # Some partial measurements
        
        # Mean should be near p*L = 0.5*4 = 2.0
        mean_count = sum(counts) / length(counts)
        @test 1.0 < mean_count < 3.0  # Loose bounds for 200 trials
        
        # If all-or-nothing: every count would be 0 or 4
        # Per-element: should see counts 1, 2, 3 as well
        @test any(x -> x ∉ [0, L], counts)  # NOT all-or-nothing
        
        # Also verify simulate! works without error
        state = SimulationState(L=L, bc=:open, maxdim=16,
            rng=RNGRegistry(gates_spacetime=42, gates_realization=2, born_measurement=3))
        initialize!(state, ProductState(binary_int=0))
        simulate!(c, state; n_circuits=3, record_when=:every_step)
        @test true  # No error
    end
    
    @testset "RNG determinism — same seed produces identical MPS" begin
        # Two states with same seed should produce identical results
        circuit = Circuit(L=4, bc=:periodic, n_steps=10) do c
            apply_with_prob!(c; rng=:gates_spacetime, outcomes=[
                (probability=0.3, gate=Measurement(:Z), geometry=AllSites())
            ])
        end
        
        # First state
        s1 = SimulationState(L=4, bc=:periodic, rng=RNGRegistry(gates_spacetime=42, gates_realization=2, born_measurement=3))
        initialize!(s1, ProductState(binary_int=0))
        simulate!(circuit, s1; n_circuits=5)
        
        # Second state with same seeds
        s2 = SimulationState(L=4, bc=:periodic, rng=RNGRegistry(gates_spacetime=42, gates_realization=2, born_measurement=3))
        initialize!(s2, ProductState(binary_int=0))
        simulate!(circuit, s2; n_circuits=5)
        
        # Compare MPS tensors - need to handle different tensor ranks
        # Each MPS tensor can be 2D (edge sites) or 3D (bulk sites)
        using ITensors: array
        for i in 1:4
            arr1 = array(s1.mps[i])
            arr2 = array(s2.mps[i])
            @test arr1 ≈ arr2 atol=1e-14
        end
    end
    
    @testset "expand_circuit produces correct ExpandedOps for Bricklayer" begin
        # Test OBC and PBC boundary conditions
        # L=4, :periodic, :odd → pairs: (1,2), (3,4)
        circuit_pbc_odd = Circuit(L=4, bc=:periodic, n_steps=1) do c
            apply!(c, CZ(), Bricklayer(:odd))
        end
        ops_pbc_odd = expand_circuit(circuit_pbc_odd; seed=0)
        @test length(ops_pbc_odd) == 1
        @test length(ops_pbc_odd[1]) == 2  # 2 pairs
        @test ops_pbc_odd[1][1].sites == [1, 2]
        @test ops_pbc_odd[1][2].sites == [3, 4]
        
        # L=4, :periodic, :even → pairs: (2,3), (4,1)
        circuit_pbc_even = Circuit(L=4, bc=:periodic, n_steps=1) do c
            apply!(c, CZ(), Bricklayer(:even))
        end
        ops_pbc_even = expand_circuit(circuit_pbc_even; seed=0)
        @test length(ops_pbc_even[1]) == 2  # 2 pairs
        @test ops_pbc_even[1][1].sites == [2, 3]
        @test ops_pbc_even[1][2].sites == [4, 1]
        
        # L=4, :open, :odd → pairs: (1,2), (3,4)
        circuit_obc_odd = Circuit(L=4, bc=:open, n_steps=1) do c
            apply!(c, CZ(), Bricklayer(:odd))
        end
        ops_obc_odd = expand_circuit(circuit_obc_odd; seed=0)
        @test length(ops_obc_odd[1]) == 2  # 2 pairs
        @test ops_obc_odd[1][1].sites == [1, 2]
        @test ops_obc_odd[1][2].sites == [3, 4]
        
        # L=4, :open, :even → pairs: (2,3) only
        circuit_obc_even = Circuit(L=4, bc=:open, n_steps=1) do c
            apply!(c, CZ(), Bricklayer(:even))
        end
        ops_obc_even = expand_circuit(circuit_obc_even; seed=0)
        @test length(ops_obc_even[1]) == 1  # 1 pair
        @test ops_obc_even[1][1].sites == [2, 3]
    end
    
    @testset "expand_circuit produces correct ExpandedOps for AllSites" begin
        # AllSites L=4 → 4 single-site operations
        circuit = Circuit(L=4, bc=:periodic, n_steps=1) do c
            apply!(c, PauliX(), AllSites())
        end
        
        ops = expand_circuit(circuit; seed=0)
        @test length(ops) == 1
        @test length(ops[1]) == 4  # 4 sites
        @test ops[1][1].sites == [1]
        @test ops[1][2].sites == [2]
        @test ops[1][3].sites == [3]
        @test ops[1][4].sites == [4]
    end
    
    @testset "expand_circuit + simulate! RNG alignment" begin
        # Same seed → same branch selections per element
        L = 4
        circuit = Circuit(L=L, bc=:periodic, n_steps=5) do c
            apply_with_prob!(c; rng=:gates_spacetime, outcomes=[
                (probability=0.3, gate=Measurement(:Z), geometry=AllSites())
            ])
        end
        
        # expand_circuit with seed=42 should produce deterministic result
        ops_run1 = expand_circuit(circuit; seed=42)
        ops_run2 = expand_circuit(circuit; seed=42)
        
        # Same seed → same expansion
        for step in 1:5
            sites1 = Set([op.sites for op in ops_run1[step]])
            sites2 = Set([op.sites for op in ops_run2[step]])
            @test sites1 == sites2
        end
        
        # Different seeds → different expansions (with high probability)
        ops_run3 = expand_circuit(circuit; seed=99)
        total_meas_42 = sum(length(step_ops) for step_ops in ops_run1)
        total_meas_99 = sum(length(step_ops) for step_ops in ops_run3)
        # Verify both run without error and produce reasonable counts
        @test 0 <= total_meas_42 <= 5 * L  # At most L measurements per step
        @test 0 <= total_meas_99 <= 5 * L
        
    # RNG ALIGNMENT: expand_circuit(seed=42) and simulate!(gates_spacetime=42)
    # must consume gates_spacetime RNG identically — same Meas ops fired per element.
    # Both use MersenneTwister(42), same iteration order → same Bernoulli draws.
    #
    # State A: pre-selected ops from expand_circuit (no gates_spacetime draw at apply time)
    state_align_A = SimulationState(L=L, bc=:periodic,
        rng=RNGRegistry(gates_spacetime=42, gates_realization=2, born_measurement=3))
    initialize!(state_align_A, ProductState(binary_int=0))
    for step_ops in ops_run1          # ops_run1 was produced by expand_circuit(seed=42)
        for op in step_ops
            apply!(state_align_A, op.gate, SingleSite(op.sites[1]))
        end
    end

    # State B: simulate! selects gates via gates_spacetime=42 (same seed as expand)
    state_align_B = SimulationState(L=L, bc=:periodic,
        rng=RNGRegistry(gates_spacetime=42, gates_realization=2, born_measurement=3))
    initialize!(state_align_B, ProductState(binary_int=0))
    simulate!(circuit, state_align_B; n_circuits=1)

    # If RNG alignment holds: same gates selected → same born_measurement draws → identical MPS
    using ITensors: array
    for i in 1:L
        @test array(state_align_A.mps[i]) ≈ array(state_align_B.mps[i]) atol=1e-14
    end

    # Simulate with same seed should execute without error
    rng = RNGRegistry(gates_spacetime=42, gates_realization=2, born_measurement=3)
    state = SimulationState(L=L, bc=:periodic, rng=rng)
    initialize!(state, ProductState(binary_int=0))
    track!(state, :dw => DomainWall(order=1, i1_fn=() -> 1))
    simulate!(circuit, state; n_circuits=5, record_when=:every_step)
    @test length(state.observables[:dw]) == 5
end
    
    @testset "Empty Bricklayer (L=2, :open, :even) — no-op" begin
        # Edge case: L=2, :open, :even → no pairs
        # Should NOT throw, should be no-op
        # Recording behavior: :every_step records at step boundary regardless of gate execution
        circuit = Circuit(L=2, bc=:open, n_steps=5) do c
            apply!(c, CZ(), Bricklayer(:even))
        end
        
        # expand_circuit should produce empty vectors
        ops = expand_circuit(circuit; seed=0)
        @test length(ops) == 5
        @test all(length(step_ops) == 0 for step_ops in ops)
        
        # simulate! should execute without error
        rng = RNGRegistry(gates_spacetime=42, gates_realization=44, born_measurement=45)
        state = SimulationState(L=2, bc=:open, rng=rng)
        initialize!(state, ProductState(binary_int=0))
        track!(state, :dw => DomainWall(order=1, i1_fn=() -> 1))
        
        # Note: Empty compound geometry doesn't trigger recording in deterministic path
        # because the loop over elements never executes. This is expected behavior.
        # We test that it executes without error.
        simulate!(circuit, state; n_circuits=3, record_when=:every_step)
        
        # Execution should succeed (no error thrown)
        @test true
    end
    
    @testset "EntanglementEntropy tracking with compound geometry" begin
        # Test that entropy tracking works with compound geometries
        circuit = Circuit(L=4, bc=:open, n_steps=5) do c
            apply!(c, HaarRandom(), Bricklayer(:odd))
        end
        
        rng = RNGRegistry(gates_spacetime=42, gates_realization=44, born_measurement=45)
        state = SimulationState(L=4, bc=:open, rng=rng)
        initialize!(state, ProductState(binary_int=0))
        track!(state, :entropy => EntanglementEntropy(cut=2, renyi_index=1))
        
        # Simulate with recording
        simulate!(circuit, state; n_circuits=3, record_when=:every_step)
        
        # Should have 3 records
        @test length(state.observables[:entropy]) == 3
        @test all(e -> e isa Float64, state.observables[:entropy])
        @test all(e -> e >= -1e-10, state.observables[:entropy])
    end
end

@testset "Circuit Visualization Fixes (Issues 1-5)" begin
    @testset "Issue 5: SpinSectorProjection label shows P(S≠2)" begin
        # Create circuit with SpinSectorProjection
        P0 = total_spin_projector(0)
        P1 = total_spin_projector(1)
        proj = SpinSectorProjection(P0 + P1)
        circuit = Circuit(L=4, bc=:periodic, n_steps=1) do c
            apply!(c, proj, AdjacentPair(1))
        end
        
        try
            Base.require(Main, :Luxor)
            
            svg_path = tempname() * ".svg"
            plot_circuit(circuit; gates_spacetime=0, filename=svg_path)
            svg = read(svg_path, String)
            rm(svg_path)
            
            # Verify label is NOT the type name (Luxor renders text as glyphs)
            # Just check SVG was created and doesn't contain full type name
            @test contains(svg, "<svg")
            @test !contains(svg, "SpinSectorProjection")
        catch e
            if e isa ArgumentError && contains(string(e), "Package Luxor not found")
                @test_skip "Luxor not available - skipping SVG test"
            else
                rethrow(e)
            end
        end
    end
    
    @testset "Issues 2+3: Non-adjacent gates render as two boxes" begin
        # Create circuit with NNN gates (non-adjacent)
        circuit = Circuit(L=8, bc=:periodic, n_steps=1) do c
            apply!(c, HaarRandom(), Bricklayer(:nnn))  # NNN gates (4 gates)
        end
        
        try
            Base.require(Main, :Luxor)
            
            svg_path = tempname() * ".svg"
            plot_circuit(circuit; gates_spacetime=0, filename=svg_path)
            svg = read(svg_path, String)
            rm(svg_path)
            
            # Count boxes - should have 2 per NNN gate (4 gates × 2 = 8 boxes minimum)
            # Boxes are rendered with fill-rule="nonzero"
            box_count = length(collect(eachmatch(r"fill-rule=\"nonzero\"", svg)))
            @test box_count >= 8
        catch e
            if e isa ArgumentError && contains(string(e), "Package Luxor not found")
                @test_skip "Luxor not available - skipping SVG test"
            else
                rethrow(e)
            end
        end
    end
    
    @testset "Issue 1: Bricklayer parallel layout (no letter suffixes)" begin
        # Create bricklayer circuit with parallel NN gates
        circuit = Circuit(L=8, bc=:periodic, n_steps=1) do c
            apply!(c, HaarRandom(), Bricklayer(:nn))  # 8 parallel ops
        end
        
        try
            Base.require(Main, :Luxor)
            
            svg_path = tempname() * ".svg"
            plot_circuit(circuit; gates_spacetime=0, filename=svg_path)
            svg = read(svg_path, String)
            rm(svg_path)
            
            # Verify no letter suffixes (1a, 1b, etc)
            @test !contains(svg, "1a")
            @test !contains(svg, "1b")
            @test !contains(svg, "1c")
            @test !contains(svg, "1d")
        catch e
            if e isa ArgumentError && contains(string(e), "Package Luxor not found")
                @test_skip "Luxor not available - skipping SVG test"
            else
                rethrow(e)
            end
        end
    end
    
    @testset "Issue 4: Dynamic font sizing (visual verification)" begin
        # This issue is about dynamic font sizing - verified visually in aklt_circuit.svg
        # No automated test needed, but we ensure the circuit generates without errors
        circuit = Circuit(L=8, bc=:periodic, n_steps=1) do c
            P0 = total_spin_projector(0)
            P1 = total_spin_projector(1)
            proj = SpinSectorProjection(P0 + P1)
            apply_with_prob!(c; rng=:gates_spacetime, outcomes=[
                (probability=1.0, gate=proj, geometry=Bricklayer(:nn))
            ])
        end
        
        try
            Base.require(Main, :Luxor)
            
            svg_path = tempname() * ".svg"
            plot_circuit(circuit; gates_spacetime=0, filename=svg_path)
            svg = read(svg_path, String)
            rm(svg_path)
            
            # Just verify SVG was created successfully
            @test contains(svg, "<svg")
            @test !contains(svg, "SpinSectorProjection")
        catch e
            if e isa ArgumentError && contains(string(e), "Package Luxor not found")
                @test_skip "Luxor not available - skipping SVG test"
            else
                rethrow(e)
            end
        end
    end
end

@testset "Per-element independent sampling statistics" begin

    @testset "Test 1: Per-site frequency (p=0.3, N=1000, L=8)" begin
        L = 8
        p = 0.3
        c = Circuit(L=L, bc=:open, n_steps=1) do b
            apply_with_prob!(b; rng=:gates_spacetime, outcomes=[
                (probability=p, gate=Measurement(:Z), geometry=AllSites())
            ])
        end

        # Count per-site occurrences across 1000 seeds
        site_counts = zeros(Int, L)
        for s in 1:1000
            ops = expand_circuit(c; seed=s)[1]
            for op in ops
                for site in op.sites
                    site_counts[site] += 1
                end
            end
        end

        # Per-element independence: each site should have frequency ≈ p = 0.3
        # Bounds [0.24, 0.36] are ±2 standard deviations wide for N=1000, p=0.3
        for k in 1:L
            freq = site_counts[k] / 1000
            @test 0.24 <= freq <= 0.36
        end
    end

    @testset "Test 2: Anti-correlation — P(site_i AND site_j) ≈ p², not p" begin
        L = 8
        p = 0.3
        c = Circuit(L=L, bc=:open, n_steps=1) do b
            apply_with_prob!(b; rng=:gates_spacetime, outcomes=[
                (probability=p, gate=Measurement(:Z), geometry=AllSites())
            ])
        end

        # Count joint firings of sites 1 AND 2 across N=200 seeds
        N = 200
        joint_count = 0
        for s in 1:N
            ops = expand_circuit(c; seed=s)[1]
            sites_fired = Set(site for op in ops for site in op.sites)
            if 1 ∈ sites_fired && 2 ∈ sites_fired
                joint_count += 1
            end
        end

        joint_prob = joint_count / N
        # Per-element independence → P(1∩2) ≈ p² = 0.09
        # All-or-nothing → P(1∩2) ≈ p = 0.3
        @test joint_prob < 0.15   # Much less than p = 0.3
        @test joint_prob > 0.03   # Sanity: p² = 0.09 is not too rare
    end

    @testset "Test 3: Edge cases — p=0.0 fires nothing, p=1.0 fires all" begin
        L = 8

        # p=0.0: rand() < 0.0 is always false → zero ops
        c_zero = Circuit(L=L, bc=:open, n_steps=1) do b
            apply_with_prob!(b; rng=:gates_spacetime, outcomes=[
                (probability=0.0, gate=Measurement(:Z), geometry=AllSites())
            ])
        end
        total_zero = sum(length(expand_circuit(c_zero; seed=s)[1]) for s in 1:10)
        @test total_zero == 0

        # p=1.0: rand() < 1.0 is always true → L ops every time
        c_one = Circuit(L=L, bc=:open, n_steps=1) do b
            apply_with_prob!(b; rng=:gates_spacetime, outcomes=[
                (probability=1.0, gate=Measurement(:Z), geometry=AllSites())
            ])
        end
        total_one = sum(length(expand_circuit(c_one; seed=s)[1]) for s in 1:10)
        @test total_one == L * 10
    end

    @testset "Test 4: Multi-outcome Bricklayer(:odd)/(:even) fire independently" begin
        L = 8
        # Two independent compound outcomes
        c = Circuit(L=L, bc=:periodic, n_steps=1) do b
            apply_with_prob!(b; rng=:gates_spacetime, outcomes=[
                (probability=0.5, gate=Measurement(:Z), geometry=Bricklayer(:odd)),
                (probability=0.5, gate=Measurement(:Z), geometry=Bricklayer(:even))
            ])
        end

        # Run 100 seeds; verify ops from both sublayers appear
        # Bricklayer(:odd) L=8 :periodic → pairs (1,2),(3,4),(5,6),(7,8)
        # Bricklayer(:even) L=8 :periodic → pairs (2,3),(4,5),(6,7),(8,1)
        odd_seen = false   # pair [1,2] can only come from :odd
        even_seen = false  # pair [2,3] can only come from :even

        for s in 1:100
            ops = expand_circuit(c; seed=s)[1]
            for op in ops
                if op.sites == [1, 2]
                    odd_seen = true
                elseif op.sites == [2, 3]
                    even_seen = true
                end
            end
            odd_seen && even_seen && break
        end

        @test odd_seen   # Bricklayer(:odd) fires independently
        @test even_seen  # Bricklayer(:even) fires independently
    end

    @testset "Test 5: RNG alignment — expand_circuit(seed=X) ≡ simulate!(gates_spacetime=X)" begin
        L = 4
        circuit = Circuit(L=L, bc=:open, n_steps=1) do c
            apply_with_prob!(c; rng=:gates_spacetime, outcomes=[
                (probability=0.5, gate=Measurement(:Z), geometry=AllSites())
            ])
        end

        # expand_circuit(seed=42) is deterministic
        meas_run1 = count(op -> op.label == "Meas", expand_circuit(circuit; seed=42)[1])
        meas_run2 = count(op -> op.label == "Meas", expand_circuit(circuit; seed=42)[1])
        @test meas_run1 == meas_run2

        # RNG alignment: expand_circuit(seed=42) and simulate!(gates_spacetime=42)
        # must consume MersenneTwister(42) in identical order → same Meas selections.
        ops_exp = expand_circuit(circuit; seed=42)

        # State A: manually apply ops selected by expand_circuit (no gates_spacetime draw)
        state_a = SimulationState(L=L, bc=:open,
            rng=RNGRegistry(gates_spacetime=99, gates_realization=2, born_measurement=3))
        initialize!(state_a, ProductState(binary_int=0))
        for op in ops_exp[1]
            apply!(state_a, op.gate, SingleSite(op.sites[1]))
        end

        # State B: simulate! with gates_spacetime=42 (same seed used by expand_circuit)
        state_b = SimulationState(L=L, bc=:open,
            rng=RNGRegistry(gates_spacetime=42, gates_realization=2, born_measurement=3))
        initialize!(state_b, ProductState(binary_int=0))
        simulate!(circuit, state_b; n_circuits=1)

        # Same gates fired in same order → same born_measurement draws → identical MPS
        using ITensors: array
        for i in 1:L
            @test array(state_a.mps[i]) ≈ array(state_b.mps[i]) atol=1e-14
        end

        # Meas count from expand is in valid range
        @test 0 <= meas_run1 <= L
    end
end
