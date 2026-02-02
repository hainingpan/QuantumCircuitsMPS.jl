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
bc = :periodic             # Boundary conditions (less ambiguous than :open)
p_nn = 0.7                 # Probability of NN projection (1-p_nn = P(NNN))

# NOTE on boundary conditions:
# We use bc=:periodic which gives well-defined physics for AKLT:
# - NN AKLT: |SO| ≈ 4/9, S = 2 (in base 2)
# - NNN AKLT: |SO| ≈ (4/9)² ≈ 0.198, S = 4 (in base 2)
# SpinSectorMeasurement (Protocol B) DOES NOT WORK regardless of BC.

println("System Parameters:")
println("  L = $L (chain length)")
println("  n_layers = $n_layers")
println("  bc = $bc")
println("  p_nn = $p_nn (probability of NN projection)")
println("  p_nnn = $(1-p_nn) (probability of NNN projection)")
println()

# Physics Sanity Check (bc=:periodic, base 2 logarithm):
# | p_nn | p_nnn | Ground State | |SO|           | S (von Neumann) |
# |------|-------|--------------|----------------|-----------------|
# |  1   |   0   | NN AKLT      | 4/9 ≈ 0.444    |        2        |
# |  0   |   1   | NNN AKLT     | (4/9)² ≈ 0.198 |        4        |
#
#
# NOTE: NNN AKLT creates TWO decoupled chains (odd sites 1-3-5-7-9-11,
# even sites 2-4-6-8-10-12), each behaving as an independent AKLT chain.
# Total entropy: S = S₁ + S₂ = 2 + 2 = 4 (entropies add).
# String order with order=2: |SO| ≈ (4/9)² ≈ 0.198. This uses paired endpoints
# Sz[n]·Sz[n+1] and Sz[m-1]·Sz[m] which correctly project onto both chains.
# Using order=1 gives ~0.03 (WRONG formula for NNN physics).
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
#
# IMPORTANT: For complete NNN coverage, we need all 4 sublayers:
# - :nnn_odd_1, :nnn_odd_2 (pairs (1,3), (5,7), (9,11) and (3,5), (7,9), (11,1))
# - :nnn_even_1, :nnn_even_2 (pairs (2,4), (6,8), (10,12) and (4,6), (8,10), (12,2))
# This covers all 12 NNN pairs on a 12-site periodic chain.
circuit_A = Circuit(L=L, bc=bc, n_steps=1) do c
    # Single stochastic call: NN vs NNN with automatic pair coverage
    # :nn parity auto-expands to all 12 NN pairs (combines :odd + :even)
    # :nnn parity auto-expands to all 12 NNN pairs (combines 4 sublayers)
    apply_with_prob!(c; rng=:ctrl, outcomes=[
        (probability=p_nn, gate=proj_gate, geometry=Bricklayer(:nn)),
        (probability=1-p_nn, gate=proj_gate, geometry=Bricklayer(:nnn))
    ])
end

# === Alternative: Parameterized Circuit API ===
# Instead of closure-captured variables, store parameters in the circuit itself.
# Access via c.params[:key] - makes circuits fully self-contained.
circuit_A_params = Circuit(L=L, bc=bc, n_steps=1, p_nn=p_nn, proj_gate=proj_gate) do c
    apply_with_prob!(c; rng=:ctrl, outcomes=[
        (probability=c.params[:p_nn], gate=c.params[:proj_gate], geometry=Bricklayer(:nn)),
        (probability=1-c.params[:p_nn], gate=c.params[:proj_gate], geometry=Bricklayer(:nnn))
    ])
end
# Both circuit_A and circuit_A_params are equivalent.

println("✓ Circuit defined with apply_with_prob! (p_nn=$p_nn)")
if p_nn == 1.0
    println("  - Pure NN: Bricklayer(:nn) auto-expands to all 12 NN pairs")
elseif p_nn == 0.0
    println("  - Pure NNN: Bricklayer(:nnn) auto-expands to all 12 NNN pairs")
else
    println("  - Mixed NN/NNN: p=$p_nn uses :nn, p=$(1-p_nn) uses :nnn")
end

# Initialize state with RNG for probabilistic decisions
rng_reg_A = RNGRegistry(ctrl=42, proj=1, haar=2, born=3)
state_A = SimulationState(L=L, bc=bc, site_type="S=1", maxdim=128, rng=rng_reg_A)
state_A.mps = MPS(state_A.sites, ["Z0" for _ in 1:L])
println("✓ Initialized to |Z0⟩⊗$L (m=0 product state)")

# Track observables
track!(state_A, :entropy => EntanglementEntropy(cut=L÷2, order=1, base=2))
# Use order=2 for NNN regime (paired endpoints), order=1 for NN
so_order = p_nn == 1.0 ? 1 : (p_nn == 0.0 ? 2 : 1)
track!(state_A, :string_order => StringOrder(1, L÷2+1, order=so_order))
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

# Expected physics based on p_nn
expected_SO = p_nn == 1.0 ? 4/9 : (p_nn == 0.0 ? 0.198 : NaN)
expected_S = p_nn == 1.0 ? 2.0 : (p_nn == 0.0 ? 4.0 : NaN)

println("  Expected for p_nn=$p_nn: |SO| ≈ $(isnan(expected_SO) ? "mixed" : round(expected_SO, digits=3)), S ≈ $(isnan(expected_S) ? "mixed" : round(expected_S, digits=1))")

if !isnan(expected_SO) && !isnan(expected_S)
    if abs(abs(SO_final_A) - expected_SO) < 0.1 && abs(S_final_A - expected_S) < 1.0
        println("  ✅ CONVERGED to $(p_nn == 1.0 ? "NN" : "NNN") AKLT ground state!")
    else
        println("  ⚠️  Did not fully converge (try increasing n_layers)")
    end
else
    println("  ℹ️  Mixed NN/NNN regime - no simple analytical expectation")
end
println()
