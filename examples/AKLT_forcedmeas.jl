#!/usr/bin/env julia
# ═══════════════════════════════════════════════════════════════════
# AKLT Forced Measurement Protocols (Declarative API)
# ═══════════════════════════════════════════════════════════════════
#
# Demonstrates two approaches to forced measurement on S=1 chains:
# - Protocol A: SpinSectorProjection (coherent, preserves superposition)
# - Protocol B: SpinSectorMeasurement (Born sampling, collapses to S=0 or S=1)
#
# Physics Question: Do they produce the same long-time physics?

using QuantumCircuitsMPS
using ITensorMPS
using Printf

println("═"^70)
println("AKLT Forced Measurement Example (Declarative API)")
println("═"^70)
println()

# ═══════════════════════════════════════════════════════════════════
# System Parameters
# ═══════════════════════════════════════════════════════════════════

L = 8                      # Chain length
n_layers = L               # Number of projection/measurement layers
bc = :open                 # Boundary conditions (required for SpinSectorMeasurement)

println("System Parameters:")
println("  L = $L (chain length)")
println("  n_layers = $n_layers")
println("  bc = $bc")
println()

# ═══════════════════════════════════════════════════════════════════
# Gate Construction (Shared)
# ═══════════════════════════════════════════════════════════════════

# Spin projectors: P₀ (singlet), P₁ (triplet), P₂ (quintet)
P0 = total_spin_projector(0)
P1 = total_spin_projector(1)
P_not_2 = P0 + P1  # Projects out S=2 sector

# Protocol A gate: Coherent projection (preserves S=0/S=1 superposition)
proj_gate = SpinSectorProjection(P_not_2)

# Protocol B gate: Born sampling measurement (collapses to S=0 OR S=1)
meas_gate = SpinSectorMeasurement([0, 1])

println("Gates constructed:")
println("  Protocol A: SpinSectorProjection(P₀+P₁) - coherent")
println("  Protocol B: SpinSectorMeasurement([0,1]) - Born sampling")
println()

# ═══════════════════════════════════════════════════════════════════
# Protocol A: Coherent Projection (SpinSectorProjection)
# ═══════════════════════════════════════════════════════════════════

println("─"^70)
println("Protocol A: SpinSectorProjection (Coherent)")
println("─"^70)

# Define circuit: ONE layer applies to all NN pairs (odd + even bricklayer)
circuit_A = Circuit(L=L, bc=bc, n_steps=1) do c
    apply!(c, proj_gate, Bricklayer(:odd))
    apply!(c, proj_gate, Bricklayer(:even))
end
println("✓ Circuit defined: Bricklayer(:odd) + Bricklayer(:even) per layer")

# Initialize state
state_A = SimulationState(L=L, bc=bc, site_type="S=1", maxdim=128)
state_A.mps = MPS(state_A.sites, ["Z0" for _ in 1:L])
println("✓ Initialized to |Z0⟩⊗$L (m=0 product state)")

# Track observables
track!(state_A, :entropy => EntanglementEntropy(cut=L÷2, order=1))
track!(state_A, :string_order => StringOrder(1, L÷2+1))
println("✓ Tracking: entropy, string_order")

# Run simulation: n_layers iterations of the circuit
println("\nRunning $n_layers layers of NN projections...")
simulate!(circuit_A, state_A; n_circuits=n_layers, record_when=:every_step)

# Report results
for layer in 1:n_layers
    if layer % 2 == 0 || layer == n_layers
        S = state_A.observables[:entropy][layer]
        SO = state_A.observables[:string_order][layer]
        println("  Layer $layer: S=$(round(S, digits=4)), |SO|=$(round(abs(SO), digits=4))")
    end
end

S_final_A = state_A.observables[:entropy][end]
SO_final_A = state_A.observables[:string_order][end]

println("\nProtocol A Results:")
println("  Final entropy: $(round(S_final_A, digits=4))")
println("  Final |string order|: $(round(abs(SO_final_A), digits=4))")
println("  Expected AKLT: |SO| ≈ 0.444 (4/9)")

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

# Define circuit: Same structure, different gate
circuit_B = Circuit(L=L, bc=bc, n_steps=1) do c
    apply!(c, meas_gate, Bricklayer(:odd))
    apply!(c, meas_gate, Bricklayer(:even))
end
println("✓ Circuit defined: Bricklayer(:odd) + Bricklayer(:even) per layer")

# Initialize state with RNG for Born sampling
rng_reg = RNGRegistry(ctrl=1, proj=2, haar=3, born=42)
state_B = SimulationState(L=L, bc=bc, site_type="S=1", maxdim=128, rng=rng_reg)
state_B.mps = MPS(state_B.sites, ["Z0" for _ in 1:L])
println("✓ Initialized to |Z0⟩⊗$L (m=0 product state)")
println("  Using RNGRegistry with born=42 for reproducibility")

# Track observables
track!(state_B, :entropy => EntanglementEntropy(cut=L÷2, order=1))
track!(state_B, :string_order => StringOrder(1, L÷2+1))
println("✓ Tracking: entropy, string_order")

# Run simulation: n_layers iterations with Born sampling
println("\nRunning $n_layers layers of NN measurements (Born sampling)...")
simulate!(circuit_B, state_B; n_circuits=n_layers, record_when=:every_step)

# Report results
for layer in 1:n_layers
    if layer % 2 == 0 || layer == n_layers
        S = state_B.observables[:entropy][layer]
        SO = state_B.observables[:string_order][layer]
        println("  Layer $layer: S=$(round(S, digits=4)), |SO|=$(round(abs(SO), digits=4))")
    end
end

S_final_B = state_B.observables[:entropy][end]
SO_final_B = state_B.observables[:string_order][end]

println("\nProtocol B Results:")
println("  Final entropy: $(round(S_final_B, digits=4))")
println("  Final |string order|: $(round(abs(SO_final_B), digits=4))")
println("  Note: Born sampling introduces stochasticity - results vary with :born seed")
println()

# ═══════════════════════════════════════════════════════════════════
# Summary: Protocol Comparison
# ═══════════════════════════════════════════════════════════════════

println("═"^70)
println("Summary: Protocol Comparison")
println("═"^70)
println()
println("Results Table:")
println("  ┌─────────────┬──────────────┬─────────────────┐")
println("  │   Protocol  │ Final |SO|   │  Final Entropy  │")
println("  ├─────────────┼──────────────┼─────────────────┤")
@printf("  │      A      │    %6.4f    │      %6.4f      │\n", abs(SO_final_A), S_final_A)
@printf("  │      B      │    %6.4f    │      %6.4f      │\n", abs(SO_final_B), S_final_B)
println("  └─────────────┴──────────────┴─────────────────┘")
println()
println("Physics Insights:")
println("  • Protocol A (SpinSectorProjection): Coherent projection preserves")
println("    S=0/S=1 superposition. Converges deterministically to AKLT ground state.")
println()
println("  • Protocol B (SpinSectorMeasurement): Born sampling collapses each pair")
println("    to either S=0 or S=1. Introduces measurement-induced stochasticity.")
println()
println("Research Question:")
println("  Do coherent projection and stochastic measurement produce equivalent")
println("  long-time physics when both constrain to the same subspace {S=0, S=1}?")
println()
println("  Try different :born seeds to explore trajectory statistics!")
println("═"^70)
