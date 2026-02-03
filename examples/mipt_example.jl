#!/usr/bin/env julia

# MIPT (Measurement-Induced Phase Transition) Example
# ====================================================
# This example demonstrates the measurement-induced phase transition (MIPT) in a
# 1D quantum circuit with random unitary gates and projective measurements.
#
# MIPT Physics Background:
# =========================
# The Measurement-Induced Phase Transition (MIPT) arises from competition between:
# - Unitary evolution (Bricklayer Haar gates): Creates entanglement between qubits
# - Projective measurements (Z-basis): Destroys entanglement locally
#
# CRITICAL: We use Measurement(:Z), NOT Reset()!
# - Measurement(:Z): Pure projective measurement - qubit stays in measured state
# - Reset(): Measurement + reset to |0⟩ - WRONG for MIPT physics!
#
# Circuit structure per step:
# 1. Bricklayer(:even) - Haar random gates on pairs (2,3), (4,5), (L,1)...
# 2. Z-measurements    - Each site measured with probability p
# 3. Bricklayer(:odd)  - Haar random gates on pairs (1,2), (3,4), (5,6), ...
# 4. Z-measurements    - Each site measured with probability p
#
# Phase diagram (at late times):
# - p < p_c ≈ 0.16: Volume-law phase (S ~ L, highly entangled)
# - p > p_c ≈ 0.16: Area-law phase (S ~ const, weakly entangled)
# - p = p_c: Critical point with logarithmic scaling (S ~ log(L))
#
# This example uses p=0.15 (near criticality) to show non-trivial entropy evolution.

using Pkg; Pkg.activate(dirname(@__DIR__))
using QuantumCircuitsMPS
using Printf

# ═══════════════════════════════════════════════════════════════════
# SECTION 1: Setup and Parameters
# ═══════════════════════════════════════════════════════════════════

# Define system parameters
const L = 12                   # System size (number of qubits)
const bc = :periodic           # Boundary conditions
const n_steps = 50             # Number of circuit timesteps
const p = 0.15                 # Measurement probability (near critical p_c ≈ 0.16)
const cut = L ÷ 2              # Entanglement cut position
const maxdim = 64              # Maximum bond dimension

println("=" ^ 70)
println("MIPT Example - Measurement-Induced Phase Transition")
println("=" ^ 70)
println()
println("Parameters:")
println("  L = $L (system size)")
println("  bc = $bc (boundary conditions)")
println("  n_steps = $n_steps (circuit timesteps)")
println("  p = $p (measurement probability)")
println("  cut = $cut (entanglement cut position)")
println("  maxdim = $maxdim (maximum bond dimension)")
println()

# ═══════════════════════════════════════════════════════════════════
# SECTION 2: Circuit Construction
# ═══════════════════════════════════════════════════════════════════
# Build circuit with do-block API. Each circuit represents ONE timestep:
#   1. Bricklayer(:even) - Random unitaries on even pairs
#   2. Z-measurements    - Each site measured with probability p
#   3. Bricklayer(:odd)  - Random unitaries on odd pairs  
#   4. Z-measurements    - Each site measured with probability p

println("Building MIPT circuit...")
println()

# Build circuit with n_steps=1 (one timestep per circuit)
# Using parameterized circuit API: parameters stored in c.params[:key]
circuit = Circuit(L=L, bc=bc, n_steps=1, p=p) do c
    # Even pairs + measure
    apply!(c, HaarRandom(), Bricklayer(:even))
    apply_with_prob!(c; rng=:ctrl, outcomes=[
        (probability=c.params[:p], gate=Measurement(:Z), geometry=AllSites())
    ])
    # Odd pairs + measure  
    apply!(c, HaarRandom(), Bricklayer(:odd))
    apply_with_prob!(c; rng=:ctrl, outcomes=[
        (probability=c.params[:p], gate=Measurement(:Z), geometry=AllSites())
    ])
end

println("✓ Circuit built successfully")
println("  Circuit represents 1 timestep")
println("  Will run $n_steps times for full simulation")
println()

# ═══════════════════════════════════════════════════════════════════
# SECTION 3: Simulation State Setup
# ═══════════════════════════════════════════════════════════════════
# Create simulation state and initialize to product state |0⟩⊗L

println("Setting up simulation state...")
println()

# Create simulation state
state = SimulationState(
    L=L,
    bc=bc,
    cutoff=1e-10,
    maxdim=maxdim,
    rng = RNGRegistry(ctrl=42, born=1, haar=2, proj=3)
)

# Initialize to product state |0⟩⊗L
initialize!(state, ProductState(binary_int=0))

# Track entanglement entropy
track!(state, :entropy => EntanglementEntropy(; cut=cut))

println("✓ State initialized")
println("  System size: $L qubits")
println("  Boundary conditions: $bc")
println("  Initial state: |0⟩⊗L")
println()

# ═══════════════════════════════════════════════════════════════════
# SECTION 4: Run Simulation
# ═══════════════════════════════════════════════════════════════════
# Execute circuit n_steps times (once per timestep)
# Recording occurs automatically after each circuit execution

println("Running MIPT simulation ($n_steps steps)...")
println()

simulate!(circuit, state; n_circuits=n_steps, record_when=:every_step)

println("✓ Simulation complete")
println()

# ═══════════════════════════════════════════════════════════════════
# SECTION 5: Results and Analysis
# ═══════════════════════════════════════════════════════════════════

# Access entropy values from state.observables
entropy_vals = state.observables[:entropy]

println("Entanglement Entropy Evolution:")
println("-" ^ 70)

# Print entropy at every 10 steps
for t in 1:n_steps
    if t % 10 == 0 || t == n_steps
        println("Step $t: Entanglement entropy = $(Printf.@sprintf("%.6f", entropy_vals[t]))")
    end
end

println()
println("=" ^ 70)
println("Simulation complete!")
println()
println("Physical Interpretation:")
println("  - At p=0.15 (near critical p_c ≈ 0.16), entropy shows non-trivial dynamics")
println("  - Volume-law phase (p < p_c): S ~ L (high entanglement)")
println("  - Area-law phase (p > p_c): S ~ const (low entanglement)")
println("  - Critical point (p ≈ p_c): S ~ log(L)")
println("=" ^ 70)
