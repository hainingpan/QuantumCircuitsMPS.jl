#!/usr/bin/env julia

# CT Model - Circuit Style
# ========================
# This example demonstrates the new Circuit API for building, visualizing, and simulating
# quantum circuits. The Circuit API provides a lazy/symbolic representation that separates
# circuit construction from execution, enabling visualization before simulation.
#
# Key concepts:
#   1. Build: Circuit created with do-block syntax (lazy/symbolic)
#   2. Visualize: ASCII diagram via print_circuit (no execution)
#   3. Simulate: Concrete execution via simulate! (deterministic with seed)
#
# This example verifies that circuit-style and imperative-style produce IDENTICAL MPS states
# when given the same RNG seeds, confirming they represent the same underlying physics.

using Pkg; Pkg.activate(dirname(@__DIR__))
using QuantumCircuitsMPS
using ITensors  # For MPS inner product (fidelity calculation)

# ═══════════════════════════════════════════════════════════════════
# MODEL PARAMETERS
# ═══════════════════════════════════════════════════════════════════

const L = 4
const bc = :periodic
const n_steps = 50
const p_ctrl = 0.3

println("=" ^ 70)
println("CT Model - Circuit Style vs Imperative Style Comparison")
println("=" ^ 70)
println()
println("Parameters:")
println("  L = $L (system size)")
println("  bc = $bc (boundary conditions)")
println("  n_steps = $n_steps (circuit timesteps)")
println("  p_ctrl = $p_ctrl (control measurement probability)")
println()

# ═══════════════════════════════════════════════════════════════════
# IMPERATIVE STYLE (existing approach)
# ═══════════════════════════════════════════════════════════════════
# In imperative style, we:
#   - Create a mutable SimulationState
#   - Create a mutable Geometry object
#   - Apply gates in a loop, advancing geometry after each step
#   - Gates execute immediately when apply_with_prob! is called

println("Running imperative style...")

state_imperative = SimulationState(
    L = L, 
    bc = bc, 
    rng = RNGRegistry(ctrl=42, proj=1, haar=2, born=3)
)
initialize!(state_imperative, ProductState(x0=1//16))

geo = StaircaseRight(1)
for step in 1:n_steps
    apply_with_prob!(state_imperative; rng=:ctrl, outcomes=[
        (probability=p_ctrl, gate=Reset(), geometry=geo),
        (probability=1-p_ctrl, gate=HaarRandom(), geometry=geo)
    ])
end

println("✓ Imperative execution complete")
println()

# ═══════════════════════════════════════════════════════════════════
# CIRCUIT STYLE (new API)
# ═══════════════════════════════════════════════════════════════════
# In circuit style, we:
#   - Build a Circuit object with do-block syntax (lazy/symbolic)
#   - Visualize the circuit structure with print_circuit (no execution)
#   - Execute via simulate! with explicit seed (deterministic)
#   - Circuit stores operations symbolically, geometry is pure computation

println("Building circuit...")

# Step 1: Build circuit (lazy/symbolic representation)
# Note: StaircaseRight(1) is NOT mutated - each step computes site purely
circuit = Circuit(L=L, bc=bc, n_steps=n_steps) do c
    apply_with_prob!(c; rng=:ctrl, outcomes=[
        (probability=p_ctrl, gate=Reset(), geometry=StaircaseRight(1)),
        (probability=1-p_ctrl, gate=HaarRandom(), geometry=StaircaseRight(1))
    ])
end

println("✓ Circuit built with $(circuit.n_steps) steps")
println()

# Step 2: Visualize circuit (ASCII diagram)
# We show only first 10 steps for readability
println("Circuit visualization (first 10 steps, seed=42):")
println()
short_circuit = Circuit(L=L, bc=bc, n_steps=10) do c
    apply_with_prob!(c; rng=:ctrl, outcomes=[
        (probability=p_ctrl, gate=Reset(), geometry=StaircaseRight(1)),
        (probability=1-p_ctrl, gate=HaarRandom(), geometry=StaircaseRight(1))
    ])
end
print_circuit(short_circuit; seed=42)
println()

# Step 3: Execute circuit
# CRITICAL: Same RNG seed (ctrl=42) ensures same stochastic branches are taken
println("Simulating circuit (seed=42)...")
state_circuit = SimulationState(
    L = L, 
    bc = bc, 
    rng = RNGRegistry(ctrl=42, proj=1, haar=2, born=3)
)
initialize!(state_circuit, ProductState(x0=1//16))
simulate!(circuit, state_circuit; n_circuits=1)

println("✓ Circuit execution complete")
println()

# ═══════════════════════════════════════════════════════════════════
# VERIFICATION: Same Physics (MPS Fidelity)
# ═══════════════════════════════════════════════════════════════════
# We verify the two approaches produce IDENTICAL quantum states by computing
# the fidelity (inner product) of their MPS representations.
#
# Fidelity = |<ψ_imperative|ψ_circuit>|
#
# Expected: fidelity ≈ 1.0 (same physics)

println("Verifying MPS states...")

fidelity = abs(inner(state_imperative.mps, state_circuit.mps))

println("MPS Fidelity: $fidelity")
println()

if fidelity > 1 - 1e-10
    println("✅ SUCCESS: MPS states are identical (fidelity ≈ 1.0)")
    println("   → Circuit style produces same physics as imperative style")
else
    error("❌ FAILURE: MPS states differ! Fidelity = $fidelity (expected ~1.0)")
end

println()
println("=" ^ 70)
println("Demonstration complete!")
println("=" ^ 70)
println()
println("Key takeaways:")
println("  • Circuit API workflow: build → visualize → simulate")
println("  • Same RNG seed → same physics (verified via MPS fidelity)")
println("  • Circuit style is lazy: no execution until simulate!()")
println("  • print_circuit shows structure without running simulation")
println()
println("Why use circuit style?")
println("  ✓ Inspect circuit structure before expensive simulation")
println("  ✓ Reuse same circuit with different initial states")
println("  ✓ Export circuit diagrams for documentation/papers")
println("  ✓ Separate logical structure from execution details")
println()
println("=" ^ 70)
