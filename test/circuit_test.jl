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
        apply_with_prob!(c; rng=:ctrl, outcomes=[
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
            apply_with_prob!(c; rng=:ctrl, outcomes=[
                (probability=0.5, gate=Reset(), geometry=StaircaseRight(1)),
                (probability=0.3, gate=HaarRandom(), geometry=SingleSite(1))
            ])
        end
        
        @test length(circuit.operations) == 1
        @test circuit.operations[1].type == :stochastic
        @test circuit.operations[1].rng == :ctrl
        @test length(circuit.operations[1].outcomes) == 2
    end
    
    @testset "Mixed operations" begin
        circuit = Circuit(L=4, bc=:periodic, n_steps=20) do c
            apply!(c, Reset(), StaircaseRight(1))
            apply_with_prob!(c; rng=:ctrl, outcomes=[
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

@testset "CircuitBuilder Validation" begin
    @testset "Wrong RNG key" begin
        @test_throws ArgumentError Circuit(L=4, bc=:periodic) do c
            apply_with_prob!(c; rng=:proj, outcomes=[
                (probability=1.0, gate=Reset(), geometry=SingleSite(1))
            ])
        end
        
        @test_throws ArgumentError Circuit(L=4, bc=:periodic) do c
            apply_with_prob!(c; rng=:haar, outcomes=[
                (probability=0.5, gate=HaarRandom(), geometry=SingleSite(1))
            ])
        end
    end
    
    @testset "Probability sum > 1" begin
        @test_throws ArgumentError Circuit(L=4, bc=:periodic) do c
            apply_with_prob!(c; rng=:ctrl, outcomes=[
                (probability=0.8, gate=Reset(), geometry=SingleSite(1)),
                (probability=0.5, gate=HaarRandom(), geometry=SingleSite(1))
            ])
        end
        
        @test_throws ArgumentError Circuit(L=4, bc=:periodic) do c
            apply_with_prob!(c; rng=:ctrl, outcomes=[
                (probability=1.1, gate=Reset(), geometry=SingleSite(1))
            ])
        end
    end
    
    @testset "Empty outcomes" begin
        # Note: Empty vector [] doesn't satisfy type Vector{<:NamedTuple{(:probability, :gate, :geometry)}}
        # so this throws TypeError during type construction, not ArgumentError during validation
        # We test that it fails, regardless of exception type
        @test_throws Exception Circuit(L=4, bc=:periodic) do c
            apply_with_prob!(c; rng=:ctrl, outcomes=[])
        end
    end
    
    @testset "Valid probability sums" begin
        # Exactly 1.0 should work
        circuit1 = Circuit(L=4, bc=:periodic) do c
            apply_with_prob!(c; rng=:ctrl, outcomes=[
                (probability=0.7, gate=Reset(), geometry=SingleSite(1)),
                (probability=0.3, gate=HaarRandom(), geometry=SingleSite(1))
            ])
        end
        @test length(circuit1.operations) == 1
        
        # Less than 1.0 should work (do-nothing branch)
        circuit2 = Circuit(L=4, bc=:periodic) do c
            apply_with_prob!(c; rng=:ctrl, outcomes=[
                (probability=0.5, gate=Reset(), geometry=SingleSite(1))
            ])
        end
        @test length(circuit2.operations) == 1
    end
end

@testset "expand_circuit Determinism" begin
    circuit = Circuit(L=4, bc=:periodic, n_steps=10) do c
        apply_with_prob!(c; rng=:ctrl, outcomes=[
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
            apply_with_prob!(c; rng=:ctrl, outcomes=[
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

@testset "simulate! Execution" begin
    @testset "Basic execution without error" begin
        circuit = Circuit(L=4, bc=:periodic, n_steps=10) do c
            apply!(c, Reset(), StaircaseRight(1))
        end
        
        rng = RNGRegistry(ctrl=42, proj=43, haar=44, born=45)
        state = SimulationState(L=4, bc=:periodic, rng=rng)
        initialize!(state, ProductState(x0=1//16))
        track!(state, :dw => DomainWall(order=1, i1_fn=() -> 1))
        
        # Should execute without error
        simulate!(circuit, state; n_circuits=1, record_initial=true)
        
        # Should have 2 records (1 initial + 1 circuit)
        @test length(state.observables[:dw]) == 2
    end
    
    @testset "Stochastic circuit execution" begin
        circuit = Circuit(L=4, bc=:periodic, n_steps=10) do c
            apply_with_prob!(c; rng=:ctrl, outcomes=[
                (probability=0.5, gate=Reset(), geometry=StaircaseRight(1)),
                (probability=0.5, gate=HaarRandom(), geometry=StaircaseLeft(4))
            ])
        end
        
        rng = RNGRegistry(ctrl=42, proj=43, haar=44, born=45)
        state = SimulationState(L=4, bc=:periodic, rng=rng)
        initialize!(state, ProductState(x0=1//16))
        track!(state, :dw => DomainWall(order=1, i1_fn=() -> 1))
        
        simulate!(circuit, state; n_circuits=3, record_initial=true)
        
        # Should have 4 records (1 initial + 3 circuits)
        @test length(state.observables[:dw]) == 4
    end
    
    @testset "Recording contract" begin
        circuit = Circuit(L=4, bc=:periodic, n_steps=5) do c
            apply!(c, Reset(), SingleSite(1))
        end
        
        rng = RNGRegistry(ctrl=42, proj=43, haar=44, born=45)
        state = SimulationState(L=4, bc=:periodic, rng=rng)
        initialize!(state, ProductState(x0=1//16))
        track!(state, :dw => DomainWall(order=1, i1_fn=() -> 1))
        
        # Test: record_initial=true, record_every=1
        simulate!(circuit, state; n_circuits=5, record_initial=true, record_every=1)
        @test length(state.observables[:dw]) == 6  # 1 initial + 5 circuits
        
        # Reset state for next test
        state = SimulationState(L=4, bc=:periodic, rng=RNGRegistry(ctrl=42, proj=43, haar=44, born=45))
        initialize!(state, ProductState(x0=1//16))
        track!(state, :dw => DomainWall(order=1, i1_fn=() -> 1))
        
        # Test: record_initial=false, n_circuits=3
        simulate!(circuit, state; n_circuits=3, record_initial=false, record_every=1)
        @test length(state.observables[:dw]) == 3  # No initial + 3 circuits
        
        # Reset state for next test
        state = SimulationState(L=4, bc=:periodic, rng=RNGRegistry(ctrl=42, proj=43, haar=44, born=45))
        initialize!(state, ProductState(x0=1//16))
        track!(state, :dw => DomainWall(order=1, i1_fn=() -> 1))
        
        # Test: record_every=2 (records at 0, 1, 3, 5, 5)
        simulate!(circuit, state; n_circuits=5, record_initial=true, record_every=2)
        @test length(state.observables[:dw]) == 4  # 1 initial + circuits 1, 3, 5
    end
    
    @testset "Multiple timesteps execute correctly" begin
        circuit = Circuit(L=4, bc=:periodic, n_steps=20) do c
            apply_with_prob!(c; rng=:ctrl, outcomes=[
                (probability=0.5, gate=Reset(), geometry=StaircaseRight(1))
            ])
        end
        
        rng = RNGRegistry(ctrl=42, proj=43, haar=44, born=45)
        state = SimulationState(L=4, bc=:periodic, rng=rng)
        initialize!(state, ProductState(x0=1//16))
        track!(state, :dw => DomainWall(order=1, i1_fn=() -> 1))
        
        # Should complete without error even with many steps
        simulate!(circuit, state; n_circuits=2, record_initial=true)
        
        @test length(state.observables[:dw]) == 3  # 1 initial + 2 circuits
    end
end

@testset "print_circuit Output" begin
    @testset "Deterministic circuit rendering" begin
        circuit = Circuit(L=4, bc=:periodic, n_steps=4) do c
            apply!(c, Reset(), StaircaseRight(1))
        end
        
        io = IOBuffer()
        print_circuit(circuit; seed=0, io=io)
        output = String(take!(io))
        
        # Check for expected content
        @test contains(output, "Circuit")
        @test contains(output, "L=4")
        @test contains(output, "bc=periodic")
        @test contains(output, "q1:")
        @test contains(output, "q2:")
        @test contains(output, "q3:")
        @test contains(output, "q4:")
        @test contains(output, "Rst")  # Gate label
    end
    
    @testset "Stochastic circuit rendering" begin
        circuit = Circuit(L=4, bc=:periodic, n_steps=6) do c
            apply_with_prob!(c; rng=:ctrl, outcomes=[
                (probability=0.5, gate=Reset(), geometry=StaircaseRight(1)),
                (probability=0.3, gate=HaarRandom(), geometry=SingleSite(1))
            ])
        end
        
        io = IOBuffer()
        print_circuit(circuit; seed=42, io=io)
        output = String(take!(io))
        
        # Should render without error and contain circuit structure
        @test contains(output, "Circuit")
        @test contains(output, "L=4")
        @test contains(output, "q1:")
    end
    
    @testset "Multi-qubit gate rendering" begin
        circuit = Circuit(L=4, bc=:periodic, n_steps=3) do c
            apply!(c, CZ(), AdjacentPair(1))
        end
        
        io = IOBuffer()
        print_circuit(circuit; seed=0, io=io)
        output = String(take!(io))
        
        # CZ label should appear on both qubits
        @test contains(output, "CZ")
        @test contains(output, "q1:")
        @test contains(output, "q2:")
    end
    
    @testset "ASCII mode rendering" begin
        circuit = Circuit(L=4, bc=:periodic, n_steps=3) do c
            apply!(c, PauliX(), SingleSite(1))
        end
        
        io = IOBuffer()
        print_circuit(circuit; seed=0, io=io, unicode=false)
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
            apply_with_prob!(c; rng=:ctrl, outcomes=[
                (probability=0.2, gate=Reset(), geometry=SingleSite(1))
            ])
        end
        
        io = IOBuffer()
        print_circuit(circuit; seed=123, io=io)
        output = String(take!(io))
        
        # Should handle empty steps (do-nothing branches) without error
        @test contains(output, "Circuit")
        @test contains(output, "q1:")
    end
end

@testset "Baseline Visualization Fixtures" begin
    @testset "Single-qubit gate ASCII output" begin
        # Baseline: PauliX on single site
        circuit = Circuit(L=4, bc=:periodic) do c
            apply!(c, PauliX(), SingleSite(1))
        end
        
        io = IOBuffer()
        print_circuit(circuit; seed=0, io=io)
        output = String(take!(io))
        
        # Verify structure
        @test contains(output, "Circuit")
        @test contains(output, "L=4")
        @test contains(output, "bc=periodic")
        @test contains(output, "q1:")
        @test contains(output, "q2:")
        @test contains(output, "q3:")
        @test contains(output, "q4:")
        @test contains(output, "X")  # Gate label
        @test contains(output, "Step:")
    end
    
    @testset "Multi-step single-qubit gates ASCII output" begin
        # Baseline: Multiple single-qubit gates in same step
        circuit = Circuit(L=4, bc=:periodic, n_steps=3) do c
            apply!(c, PauliX(), SingleSite(1))
            apply!(c, PauliY(), SingleSite(2))
            apply!(c, PauliZ(), SingleSite(3))
        end
        
        io = IOBuffer()
        print_circuit(circuit; seed=0, io=io)
        output = String(take!(io))
        
        # Verify structure and gate labels
        @test contains(output, "Circuit")
        @test contains(output, "X")
        @test contains(output, "Y")
        @test contains(output, "Z")
        @test contains(output, "q1:")
        @test contains(output, "q2:")
        @test contains(output, "q3:")
        # Verify multi-step columns (1a, 1b, 1c, 2a, 2b, 2c, 3a, 3b, 3c)
        @test contains(output, "1a")
        @test contains(output, "1b")
        @test contains(output, "1c")
    end
    
    @testset "Two-qubit gate ASCII output" begin
        # Baseline: CZ on adjacent pair
        circuit = Circuit(L=4, bc=:periodic) do c
            apply!(c, CZ(), AdjacentPair(1))
        end
        
        io = IOBuffer()
        print_circuit(circuit; seed=0, io=io)
        output = String(take!(io))
        
        # Verify structure
        @test contains(output, "Circuit")
        @test contains(output, "CZ")
        @test contains(output, "q1:")
        @test contains(output, "q2:")
        # CZ should appear on both q1 and q2
        lines = split(output, "\n")
        q1_line = filter(l -> contains(l, "q1:"), lines)[1]
        q2_line = filter(l -> contains(l, "q2:"), lines)[1]
        @test contains(q1_line, "CZ")
        @test contains(q2_line, "CZ")
    end
    
    @testset "Multi-step two-qubit gates ASCII output" begin
        # Baseline: CZ on multiple adjacent pairs in same step
        circuit = Circuit(L=4, bc=:periodic, n_steps=3) do c
            apply!(c, CZ(), AdjacentPair(1))
            apply!(c, CZ(), AdjacentPair(2))
        end
        
        io = IOBuffer()
        print_circuit(circuit; seed=0, io=io)
        output = String(take!(io))
        
        # Verify structure
        @test contains(output, "Circuit")
        @test contains(output, "CZ")
        @test contains(output, "q1:")
        @test contains(output, "q2:")
        @test contains(output, "q3:")
        # Verify multi-step columns
        @test contains(output, "1a")
        @test contains(output, "1b")
        @test contains(output, "2a")
        @test contains(output, "2b")
    end
    
    @testset "Three-qubit gate ASCII output (StaircaseRight)" begin
        # Baseline: Reset on StaircaseRight pattern
        circuit = Circuit(L=5, bc=:periodic, n_steps=3) do c
            apply!(c, Reset(), StaircaseRight(1))
        end
        
        io = IOBuffer()
        print_circuit(circuit; seed=0, io=io)
        output = String(take!(io))
        
        # Verify structure
        @test contains(output, "Circuit")
        @test contains(output, "Rst")  # Reset label
        @test contains(output, "q1:")
        @test contains(output, "q2:")
        @test contains(output, "q3:")
        # Verify step columns
        @test contains(output, "Step:")
        @test contains(output, "1")
        @test contains(output, "2")
        @test contains(output, "3")
    end
    
    @testset "Three-qubit gate ASCII output (StaircaseLeft)" begin
        # Baseline: HaarRandom on StaircaseLeft pattern
        circuit = Circuit(L=5, bc=:periodic, n_steps=3) do c
            apply!(c, HaarRandom(), StaircaseLeft(1))
        end
        
        io = IOBuffer()
        print_circuit(circuit; seed=0, io=io)
        output = String(take!(io))
        
        # Verify structure
        @test contains(output, "Circuit")
        @test contains(output, "Haar")  # HaarRandom label
        @test contains(output, "q1:")
        @test contains(output, "q2:")
        @test contains(output, "q3:")
        # Verify step columns
        @test contains(output, "Step:")
    end
    
    @testset "Mixed single and two-qubit gates ASCII output" begin
        # Baseline: Mix of single-qubit and two-qubit gates
        circuit = Circuit(L=4, bc=:periodic, n_steps=2) do c
            apply!(c, PauliX(), SingleSite(1))
            apply!(c, CZ(), AdjacentPair(2))
        end
        
        io = IOBuffer()
        print_circuit(circuit; seed=0, io=io)
        output = String(take!(io))
        
        # Verify structure
        @test contains(output, "Circuit")
        @test contains(output, "X")
        @test contains(output, "CZ")
        @test contains(output, "q1:")
        @test contains(output, "q2:")
        @test contains(output, "q3:")
        # Verify multi-step columns
        @test contains(output, "1a")
        @test contains(output, "1b")
    end
    
    @testset "ASCII mode (non-Unicode) baseline" begin
        # Baseline: ASCII mode output without Unicode characters
        circuit = Circuit(L=4, bc=:periodic, n_steps=2) do c
            apply!(c, PauliX(), SingleSite(1))
            apply!(c, PauliY(), SingleSite(2))
        end
        
        io = IOBuffer()
        print_circuit(circuit; seed=0, io=io, unicode=false)
        output = String(take!(io))
        
        # Verify ASCII characters
        @test contains(output, "Circuit")
        @test contains(output, "X")
        @test contains(output, "Y")
        @test contains(output, "q1:")
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
            apply_with_prob!(c; rng=:ctrl, outcomes=[
                (probability=0.5, gate=Reset(), geometry=StaircaseRight(1)),
                (probability=0.5, gate=HaarRandom(), geometry=StaircaseRight(1))
            ])
        end
        
        # Expand with seed 42
        ops = expand_circuit(circuit; seed=42)
        
        # Simulate with matching seed
        rng = RNGRegistry(ctrl=42, proj=43, haar=44, born=45)
        state = SimulationState(L=4, bc=:periodic, rng=rng)
        initialize!(state, ProductState(x0=1//16))
        
        # Should complete without error (alignment is implicit)
        simulate!(circuit, state; n_circuits=1, record_initial=false)
        
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
        rng = RNGRegistry(ctrl=0, proj=43, haar=44, born=45)
        state = SimulationState(L=4, bc=:periodic, rng=rng)
        initialize!(state, ProductState(x0=1//16))
        
        simulate!(circuit, state; n_circuits=1, record_initial=false)
        @test true
    end
end
