#!/usr/bin/env julia
# ═══════════════════════════════════════════════════════════════════
# AKLT Forced Measurement Protocols
# ═══════════════════════════════════════════════════════════════════
#
# Demonstrates two approaches to forced measurement on S=1 chains:
# - Protocol A: SpinSectorProjection (coherent, preserves superposition)
# - Protocol B: SpinSectorMeasurement (Born sampling, collapses)
#
# Physics Question: Do they produce the same physics?

using QuantumCircuitsMPS
using LinearAlgebra

println("═"^70)
println("AKLT Forced Measurement Example")
println("═"^70)
println()

# ═══════════════════════════════════════════════════════════════════
# System Parameters
# ═══════════════════════════════════════════════════════════════════

L = 8                      # Chain length
n_layers = L               # Number of projection layers
bc = :periodic            # Boundary conditions

println("System Parameters:")
println("  L = $L (chain length)")
println("  n_layers = $n_layers")
println("  bc = $bc")
println()

# ═══════════════════════════════════════════════════════════════════
# Protocol A: Coherent Projection (SpinSectorProjection)
# ═══════════════════════════════════════════════════════════════════

println("─"^70)
println("Protocol A: SpinSectorProjection (Coherent)")
println("─"^70)

# Initialize state
state_A = SimulationState(L=L, bc=bc, site_type="S=1", maxdim=128)
# Use |Z0⟩ (m=0) initial state - has nonzero overlap with S≤1 subspace
using ITensorMPS
state_A.mps = MPS(state_A.sites, ["Z0" for _ in 1:L])
println("✓ Initialized to |Z0⟩⊗$L (m=0 state)")

# Create projector: P₀ + P₁ (removes S=2 quintet)
P0 = total_spin_projector(0)
P1 = total_spin_projector(1)
P_not_2 = P0 + P1
proj_gate = SpinSectorProjection(P_not_2)
println("✓ Created projector P₀+P₁ (removes S=2)")

# Track observables
track!(state_A, :entropy => EntanglementEntropy(cut=L÷2, order=1))
track!(state_A, :string_order => StringOrder(1, L÷2+1))
println("✓ Tracking: entropy, string_order")

# Apply n_layers of NN projections
println("\nApplying $n_layers layers of NN projections...")
for layer in 1:n_layers
    # Apply to all adjacent pairs
    for i in 1:L
        j = (i % L) + 1  # Next site (with PBC)
        apply!(state_A, proj_gate, [i, j])
    end
    
    # Record after each layer
    record!(state_A)
    
    if layer % 2 == 0 || layer == n_layers
        S = state_A.observables[:entropy][end]
        SO = state_A.observables[:string_order][end]
        println("  Layer $layer: S=$(round(S, digits=4)), |SO|=$(round(abs(SO), digits=4))")
    end
end

# Final results
S_final_A = state_A.observables[:entropy][end]
SO_final_A = state_A.observables[:string_order][end]

println("\nProtocol A Results:")
println("  Final entropy: $(round(S_final_A, digits=4))")
println("  Final |string order|: $(round(abs(SO_final_A), digits=4))")
println("  Expected AKLT: |SO| ≈ 0.444 (4/9)")

# Check if close to AKLT
if abs(abs(SO_final_A) - 4/9) < 0.05
    println("  ✅ CONVERGED to AKLT ground state!")
else
    println("  ⚠️  Did not converge (need more layers or higher maxdim)")
end

println()

# ═══════════════════════════════════════════════════════════════════
# Protocol B: Born Measurement (SpinSectorMeasurement)
# ═══════════════════════════════════════════════════════════════════

println("─"^70)
println("Protocol B: SpinSectorMeasurement (Born Sampling)")
println("─"^70)
println("⚠️  NOTE: Born sampling not yet fully implemented")
println("   Placeholder: always projects to first allowed sector")
println("   This is a research question to explore!")
println()

# ═══════════════════════════════════════════════════════════════════
# Summary
# ═══════════════════════════════════════════════════════════════════

println("═"^70)
println("Summary")
println("═"^70)
println()
println("Physics Insight:")
println("  SpinSectorProjection (coherent) should converge to AKLT ground state")
println("  after L layers of NN projections (proven result).")
println()
println("Research Question:")
println("  Does SpinSectorMeasurement (Born sampling to S∈{0,1}) produce")
println("  the same physics, or different entanglement structure?")
println()
println("Next Steps:")
println("  1. Verify Protocol A converges: |SO| → 4/9")
println("  2. Implement proper Born sampling for Protocol B")
println("  3. Compare entanglement scaling")
println("  4. Study measurement-induced effects")
println()
println("═"^70)
