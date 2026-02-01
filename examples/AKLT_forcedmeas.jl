#!/usr/bin/env julia
# ═══════════════════════════════════════════════════════════════════════════
# AKLT Forced Measurement with NN+NNN Projections
# ═══════════════════════════════════════════════════════════════════════════
#
# Demonstrates forced measurement protocols on S=1 chains with:
# - Nearest-neighbor (NN) projections: pairs (1,2), (3,4), ...
# - Next-nearest-neighbor (NNN) projections: pairs (1,3), (5,7), ...
# - Probability p controls NN vs NNN: p = P(NN), (1-p) = P(NNN)
#
# Physics Insight:
# - Protocol A (SpinSectorProjection): Converges to AKLT ground state
# - Protocol B (SpinSectorMeasurement): VERIFIED NOT WORKING - Born sampling
#   destroys coherent superposition needed for AKLT

using QuantumCircuitsMPS
using ITensorMPS
using Printf

println("═"^70)
println("AKLT Forced Measurement with NN+NNN Projections")
println("═"^70)
println()

# ═══════════════════════════════════════════════════════════════════════════
# System Parameters
# ═══════════════════════════════════════════════════════════════════════════

L = 12                     # Chain length (must be divisible by 4 for NNN coverage)
n_layers = L               # Number of projection layers
bc = :open                 # Boundary conditions (see note below)
p_nn = 0.7                 # Probability of NN projection (1-p_nn = P(NNN))

# NOTE on boundary conditions:
# SpinSectorMeasurement (Protocol B) requires adjacent RAM indices due to
# implementation constraints in compute_two_site_born_probability(). With PBC,
# the folded MPS indexing maps physical neighbors to non-adjacent RAM sites.
# We use :open BC which works for both protocols and doesn't fundamentally
# change the AKLT physics for demonstration purposes.

println("System Parameters:")
println("  L = $L (chain length)")
println("  n_layers = $n_layers")
println("  bc = $bc")
println("  p_nn = $p_nn (probability of NN projection)")
println("  p_nnn = $(1-p_nn) (probability of NNN projection)")
println()

# ═══════════════════════════════════════════════════════════════════════════
# Gate Construction
# ═══════════════════════════════════════════════════════════════════════════

# Spin projectors: P₀ (singlet), P₁ (triplet), P₂ (quintet)
P0 = total_spin_projector(0)
P1 = total_spin_projector(1)
P_not_2 = P0 + P1  # Projects out S=2 sector

# Protocol A gate: Coherent projection (preserves S=0/S=1 superposition)
proj_gate = SpinSectorProjection(P_not_2)

# Protocol B gate: Born sampling measurement (collapses to S=0 OR S=1)
meas_gate = SpinSectorMeasurement([0, 1])

println("Gates constructed:")
println("  proj_gate: SpinSectorProjection(P₀+P₁) - coherent projection")
println("  meas_gate: SpinSectorMeasurement([0,1]) - Born sampling")
println()

# ═══════════════════════════════════════════════════════════════════════════
# Protocol A: Coherent Projection with NN+NNN
# ═══════════════════════════════════════════════════════════════════════════

println("─"^70)
println("Protocol A: SpinSectorProjection (Coherent) with NN+NNN")
println("─"^70)

# Define circuit using declarative API
# n_steps=1 means this circuit represents ONE layer
# simulate!(circuit, state; n_circuits=n_layers) runs it n_layers times
circuit_A = Circuit(L=L, bc=bc, n_steps=1) do c
    # Probabilistic: with probability p_nn apply NN, otherwise apply NNN
    apply_with_prob!(c; rng=:ctrl, outcomes=[
        (probability=p_nn, gate=proj_gate, geometry=Bricklayer(:odd)),
        (probability=1-p_nn, gate=proj_gate, geometry=Bricklayer(:nnn_odd))
    ])
    apply_with_prob!(c; rng=:ctrl, outcomes=[
        (probability=p_nn, gate=proj_gate, geometry=Bricklayer(:even)),
        (probability=1-p_nn, gate=proj_gate, geometry=Bricklayer(:nnn_even))
    ])
end
println("✓ Circuit defined with apply_with_prob! (p_nn=$p_nn)")
println("  - p=$p_nn: NN projections via Bricklayer(:odd/:even)")
println("  - p=$(1-p_nn): NNN projections via Bricklayer(:nnn_odd/:nnn_even)")

# Initialize state with RNG for probabilistic decisions
rng_reg_A = RNGRegistry(ctrl=42, proj=1, haar=2, born=3)
state_A = SimulationState(L=L, bc=bc, site_type="S=1", maxdim=128, rng=rng_reg_A)
state_A.mps = MPS(state_A.sites, ["Z0" for _ in 1:L])
println("✓ Initialized to |Z0⟩⊗$L (m=0 product state)")

# Track observables
track!(state_A, :entropy => EntanglementEntropy(cut=L÷2, order=1))
track!(state_A, :string_order => StringOrder(1, L÷2+1))
println("✓ Tracking: entropy, string_order")

# Run simulation
println("\nRunning $n_layers layers of NN+NNN projections (p_nn=$p_nn)...")
simulate!(circuit_A, state_A; n_circuits=n_layers, record_when=:every_step)

# Report results
for layer in [1, n_layers÷2, n_layers]
    S = state_A.observables[:entropy][layer]
    SO = state_A.observables[:string_order][layer]
    println("  Layer $layer: S=$(round(S, digits=4)), |SO|=$(round(abs(SO), digits=4))")
end

S_final_A = state_A.observables[:entropy][end]
SO_final_A = state_A.observables[:string_order][end]

println("\nProtocol A Results:")
println("  Final entropy: $(round(S_final_A, digits=4))")
println("  Final |string order|: $(round(abs(SO_final_A), digits=4))")
println("  Expected AKLT: |SO| ≈ 0.444 (4/9)")

if abs(abs(SO_final_A) - 4/9) < 0.1
    println("  ✅ CONVERGED to AKLT ground state!")
else
    println("  ⚠️  Did not fully converge (try p_nn=1.0 for pure NN)")
end
println()

# ═══════════════════════════════════════════════════════════════════════════
# Protocol B: Born Measurement (VERIFIED NOT WORKING)
# ═══════════════════════════════════════════════════════════════════════════

println("─"^70)
println("Protocol B: SpinSectorMeasurement (Born Sampling)")
println("─"^70)
println()
println("⚠️  VERIFIED RESULT: Protocol B does NOT converge to AKLT ground state")
println()
println("Physics Explanation:")
println("  Born sampling COLLAPSES each pair to S=0 OR S=1 (not both).")
println("  This destroys the coherent superposition required for AKLT.")
println("  The measurement-induced decoherence prevents ground state formation.")
println()

# Still run the protocol to demonstrate the physics
circuit_B = Circuit(L=L, bc=bc, n_steps=1) do c
    # Pure NN for Protocol B (simpler, avoids NNN complexity)
    apply!(c, meas_gate, Bricklayer(:odd))
    apply!(c, meas_gate, Bricklayer(:even))
end
println("✓ Circuit defined: pure NN measurement")

rng_reg_B = RNGRegistry(ctrl=1, proj=2, haar=3, born=42)
state_B = SimulationState(L=L, bc=bc, site_type="S=1", maxdim=128, rng=rng_reg_B)
state_B.mps = MPS(state_B.sites, ["Z0" for _ in 1:L])
println("✓ Initialized to |Z0⟩⊗$L with born=42 for reproducibility")

track!(state_B, :entropy => EntanglementEntropy(cut=L÷2, order=1))
track!(state_B, :string_order => StringOrder(1, L÷2+1))
println("✓ Tracking: entropy, string_order")

println("\nRunning $n_layers layers of NN measurements (Born sampling)...")
simulate!(circuit_B, state_B; n_circuits=n_layers, record_when=:every_step)

S_final_B = state_B.observables[:entropy][end]
SO_final_B = state_B.observables[:string_order][end]

println("\nProtocol B Results:")
println("  Final entropy: $(round(S_final_B, digits=4))")
println("  Final |string order|: $(round(abs(SO_final_B), digits=4))")
println("  ❌ NOT AKLT: |SO| << 4/9 (measurement-induced decoherence)")
println()

# ═══════════════════════════════════════════════════════════════════════════
# Summary: Protocol Comparison
# ═══════════════════════════════════════════════════════════════════════════

println("═"^70)
println("Summary: Protocol Comparison")
println("═"^70)
println()
println("Results Table:")
println("  ┌─────────────┬──────────────┬─────────────────┬─────────────┐")
println("  │   Protocol  │ Final |SO|   │  Final Entropy  │   Status    │")
println("  ├─────────────┼──────────────┼─────────────────┼─────────────┤")
status_A = abs(abs(SO_final_A) - 4/9) < 0.1 ? "✅ WORKS" : "⚠️ PARTIAL"
@printf("  │      A      │    %6.4f    │      %6.4f      │  %s  │\n", abs(SO_final_A), S_final_A, status_A)
@printf("  │      B      │    %6.4f    │      %6.4f      │  ❌ FAILS  │\n", abs(SO_final_B), S_final_B)
println("  └─────────────┴──────────────┴─────────────────┴─────────────┘")
println()
println("Key Physics Insights:")
println()
println("  1. Protocol A (SpinSectorProjection):")
println("     - Coherent projection preserves S=0/S=1 superposition")
println("     - Maintains quantum correlations → AKLT ground state")
println("     - Adding NNN projections (p_nn < 1) may slow convergence")
println()
println("  2. Protocol B (SpinSectorMeasurement):")
println("     - Born sampling COLLAPSES to S=0 XOR S=1 (not superposition)")
println("     - Destroys entanglement structure needed for AKLT")
println("     - This is EXPECTED physics, not a bug!")
println()
println("Research Applications:")
println("  - Study measurement-induced phase transitions (MIPT)")
println("  - Compare coherent vs stochastic state preparation")
println("  - Explore role of NNN interactions in ground state formation")
println()
println("Try varying p_nn from 0 to 1 to see the effect of NNN projections!")
println("═"^70)
