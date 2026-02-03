# test/entanglement_test.jl
# Tests for EntanglementEntropy observable

using Test
using QuantumCircuitsMPS

@testset "EntanglementEntropy" begin
    @testset "Product state entropy" begin
        # Product state |0⟩⊗L should have zero entanglement entropy
        state = SimulationState(L=4, bc=:open)
        initialize!(state, ProductState(binary_int=0))  # All qubits in |0⟩
        
        ee = EntanglementEntropy(cut=2, renyi_index=1)
        entropy = ee(state)
        
        @test entropy ≈ 0.0 atol=1e-10
    end
    
    @testset "Observable registration" begin
        # EntanglementEntropy should appear in list_observables()
        observables = list_observables()
        @test "EntanglementEntropy" ∈ observables
    end
    
    @testset "Track/record integration" begin
        # Test that track!/record! workflow works correctly
        state = SimulationState(L=4, bc=:open; rng=RNGRegistry(ctrl=1, proj=2, haar=3, born=4))
        initialize!(state, ProductState(binary_int=0))
        
        # Track entanglement entropy at cut=2
        track!(state, :ee => EntanglementEntropy(cut=2, renyi_index=1))
        
        # Record initial entropy
        record!(state)
        
        # Apply entangling gate and record again
        circuit = Circuit(L=4, bc=:open, n_steps=1) do c
            apply!(c, HaarRandom(), StaircaseRight(1))
        end
        simulate!(circuit, state; n_circuits=1, record_when=:final_only)
        
        # Should have 2 records now
        @test length(state.observables[:ee]) == 2
        @test all(e -> e isa Float64, state.observables[:ee])
        @test all(e -> e >= 0, state.observables[:ee])
    end
    
    @testset "Cut validation" begin
        # Test that cut validation works correctly
        state = SimulationState(L=4, bc=:open)
        initialize!(state, ProductState(binary_int=0))
        
        # cut=1 should work (minimum valid cut)
        ee1 = EntanglementEntropy(cut=1, renyi_index=1)
        @test ee1(state) isa Float64
        
        # cut=L-1 should work (maximum valid cut)
        ee_max = EntanglementEntropy(cut=3, renyi_index=1)
        @test ee_max(state) isa Float64
        
        # cut=0 should fail at construction
        @test_throws ArgumentError EntanglementEntropy(cut=0, renyi_index=1)
        
        # cut=L should fail at call time
        ee_invalid = EntanglementEntropy(cut=4, renyi_index=1)
        @test_throws ArgumentError ee_invalid(state)
    end
end
