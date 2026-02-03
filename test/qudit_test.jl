# test/qudit_test.jl
# Comprehensive tests for qudit features (S=1, Qudit, ProductState, AKLT physics)

using Test
using QuantumCircuitsMPS
using LinearAlgebra
using ITensorMPS

@testset "Qudit Features" begin
    
    @testset "S=1 Site Type" begin
        # Test 1: SimulationState creation with S=1
        state = SimulationState(L=4, bc=:open, site_type="S=1")
        @test state.site_type == "S=1"
        @test length(state.sites) == 4
        
        # Test 2: local_dim auto-detection
        @test state.local_dim == 3  # S=1 has 3 levels: m=-1,0,+1
        
        # Test 3: State initialization with |Z0⟩
        state.mps = MPS(state.sites, ["Z0" for _ in 1:4])
        @test maxlinkdim(state.mps) == 1  # Product state has bond dim 1
    end
    
    @testset "Qudit Site Type" begin
        # Test 1: Qudit with explicit local_dim
        state = SimulationState(L=3, bc=:open, site_type="Qudit", local_dim=5)
        @test state.site_type == "Qudit"
        @test state.local_dim == 5
        @test length(state.sites) == 3
        
        # Test 2: Initialization works after calling initialize!
        initialize!(state, ProductState(binary_int=0))
        @test state.mps isa MPS
    end
    
    @testset "ProductState API" begin
        L = 4
        state = SimulationState(L=L, bc=:open)
        
        # Test 1: binary_int format
        initialize!(state, ProductState(binary_int=5))  # 5 = 0b0101 = |0101⟩
        # Check that state is initialized (product state has bond dim 1)
        @test maxlinkdim(state.mps) == 1
        
        # Test 2: binary_decimal format (reversed)
        initialize!(state, ProductState(binary_decimal=0.101))  # 0.101 → "101" → |101⟩ (reversed)
        @test maxlinkdim(state.mps) == 1
        
        # Test 3: bitstring format
        initialize!(state, ProductState(bitstring="0110"))
        @test maxlinkdim(state.mps) == 1
        
        # Test 4: Mutual exclusivity validation
        @test_throws ArgumentError ProductState(binary_int=1, binary_decimal=0.1)
        @test_throws ArgumentError ProductState(binary_int=1, bitstring="01")
        @test_throws ArgumentError ProductState(binary_decimal=0.1, bitstring="01")
        @test_throws ArgumentError ProductState()  # Must provide exactly one
    end
    
    @testset "Spin Projector Properties" begin
        # Create projectors for S=0, S=1, S=2
        P0 = total_spin_projector(0)
        P1 = total_spin_projector(1)
        P2 = total_spin_projector(2)
        
        # Test 1: Traces (dimension of irrep)
        # S=0 singlet: dim=1, S=1 triplet: dim=3, S=2 quintet: dim=5
        @test isapprox(tr(P0), 1, atol=1e-10)
        @test isapprox(tr(P1), 3, atol=1e-10)
        @test isapprox(tr(P2), 5, atol=1e-10)
        
        # Test 2: Completeness (P0 + P1 + P2 = I)
        # 3⊗3 = 9-dimensional space decomposes as 1⊕3⊕5
        I9 = Matrix{Float64}(I, 9, 9)
        @test isapprox(P0 + P1 + P2, I9, atol=1e-10)
        
        # Test 3: Idempotence (P*P = P for projectors)
        @test isapprox(P0 * P0, P0, atol=1e-10)
        @test isapprox(P1 * P1, P1, atol=1e-10)
        @test isapprox(P2 * P2, P2, atol=1e-10)
        
        # Test 4: Orthogonality (P_i * P_j = 0 for i ≠ j)
        zero9 = zeros(9, 9)
        @test isapprox(P0 * P1, zero9, atol=1e-10)
        @test isapprox(P0 * P2, zero9, atol=1e-10)
        @test isapprox(P1 * P2, zero9, atol=1e-10)
        @test isapprox(P1 * P0, zero9, atol=1e-10)
        @test isapprox(P2 * P0, zero9, atol=1e-10)
        @test isapprox(P2 * P1, zero9, atol=1e-10)
    end
    
    @testset "AKLT Physics Sanity Check" begin
        # CRITICAL TEST: Verify Protocol A convergence to AKLT ground state
        # Expected: |string_order| → 4/9 ≈ 0.4444
        
        L = 6
        n_layers = L  # L layers sufficient for convergence
        
        # Initialize state
        state = SimulationState(L=L, bc=:open, site_type="S=1", maxdim=64)
        state.mps = MPS(state.sites, ["Z0" for _ in 1:L])
        
        # Create P0+P1 projector (removes S=2 quintet)
        P0 = total_spin_projector(0)
        P1 = total_spin_projector(1)
        P_not_2 = P0 + P1
        proj_gate = SpinSectorProjection(P_not_2)
        
        # Track string order parameter
        # For open BC, measure between site 1 and middle
        track!(state, :SO => StringOrder(1, L÷2+1))
        
        # Apply n_layers of NN projections
        for layer in 1:n_layers
            # Apply to all adjacent pairs
            for i in 1:(L-1)  # Open BC: no wraparound
                apply!(state, proj_gate, [i, i+1])
            end
            record!(state)
        end
        
        # Check convergence to AKLT ground state
        SO_final = state.observables[:SO][end]
        SO_magnitude = abs(SO_final)
        
        # String order should converge to 4/9 within 5% tolerance
        expected_SO = 4/9
        tolerance = 0.05
        
        @test abs(SO_magnitude - expected_SO) < tolerance  # Within 5% of theoretical value
        
        # Additional sanity checks
        @test SO_magnitude > 0.3  # Should be positive and significant
        @test SO_magnitude < 0.6  # Should be less than 1
        
        # Verify entanglement is present
        track!(state, :entropy => EntanglementEntropy(cut=L÷2, renyi_index=1))
        record!(state)
        S = state.observables[:entropy][end]
        @test S > 0.5  # AKLT ground state should have non-trivial entanglement
    end
end
