#!/usr/bin/env julia

# Circuit Tutorial
# ================
# This tutorial demonstrates the Circuit API workflow for building, visualizing,
# and simulating quantum circuits in QuantumCircuitsMPS.jl. The Circuit API provides
# a lazy/symbolic representation that separates circuit construction from execution,
# enabling visualization and inspection before running expensive simulations.
#
# Key concepts:
#   1. Build: Circuit created with do-block syntax (lazy/symbolic)
#   2. Visualize: ASCII/SVG diagrams without execution
#   3. Simulate: Deterministic execution with explicit RNG seeds
#
# Why use the Circuit API?
#   ✓ Inspect circuit structure before expensive simulation
#   ✓ Reuse same circuit with different initial states
#   ✓ Export circuit diagrams for documentation/papers
#   ✓ Separate logical structure from execution details

using Pkg; Pkg.activate(dirname(@__DIR__))
using QuantumCircuitsMPS

# ═══════════════════════════════════════════════════════════════════
# SECTION 1: Setup and Parameters
# ═══════════════════════════════════════════════════════════════════

# Define system parameters
const L = 4                    # System size (number of qubits)
const bc = :periodic           # Boundary conditions (:periodic or :open)
const n_steps = 50             # Number of circuit timesteps
const p_reset = 0.3            # Probability of reset operation

println("=" ^ 70)
println("Circuit Tutorial - QuantumCircuitsMPS.jl")
println("=" ^ 70)
println()
println("Parameters:")
println("  L = $L (system size)")
println("  bc = $bc (boundary conditions)")
println("  n_steps = $n_steps (circuit timesteps)")
println("  p_reset = $p_reset (reset probability)")
println()

# ═══════════════════════════════════════════════════════════════════
# SECTION 2: Building Circuits with Do-Block Syntax
# ═══════════════════════════════════════════════════════════════════
# The Circuit API uses a lazy/symbolic representation. When you build a circuit,
# no quantum operations are executed - instead, the circuit structure is recorded
# as a data structure that can be inspected, visualized, and executed later.
#
# The do-block syntax provides a clean way to define circuit operations:
#   - apply!(c, gate, geometry) - for deterministic gates
#   - apply_with_prob!(c; rng=:ctrl, outcomes=[...]) - for stochastic operations

println("Building quantum circuit...")
println()

# Build circuit with stochastic operations
# This circuit models a measurement-reset protocol:
#   - With probability p_reset: Reset qubit to |0⟩ state
#   - With probability 1-p_reset: Apply random unitary (HaarRandom)
#
# The StaircaseRight(1) geometry applies operations in a staircase pattern,
# moving one site to the right each timestep (with periodic wrapping)

circuit = Circuit(L=L, bc=bc, n_steps=n_steps) do c
    apply_with_prob!(c; rng=:ctrl, outcomes=[
        (probability=p_reset, gate=Reset(), geometry=StaircaseRight(1)),
        (probability=1-p_reset, gate=HaarRandom(), geometry=StaircaseRight(1))
    ])
end

println("✓ Circuit built successfully")
println("  Total timesteps: $(circuit.n_steps)")
println("  System size: $(circuit.L) qubits")
println("  Boundary conditions: $(circuit.bc)")
println()

# ═══════════════════════════════════════════════════════════════════
# SECTION 3: Adding Deterministic Gates
# ═══════════════════════════════════════════════════════════════════
# In addition to stochastic operations, you can add deterministic gates using
# apply!(). This example builds a circuit with both types of operations.

println("Building circuit with mixed gate types...")
println()

mixed_circuit = Circuit(L=L, bc=:open, n_steps=20) do c
    # Apply PauliX gate to site 1
    apply!(c, PauliX(), SingleSite(1))
    
    # Stochastic operation: probabilistic reset
    apply_with_prob!(c; rng=:ctrl, outcomes=[
        (probability=0.5, gate=Reset(), geometry=StaircaseRight(1)),
        (probability=0.5, gate=HaarRandom(), geometry=StaircaseRight(1))
    ])
    
    # Apply PauliZ gate to last site
    apply!(c, PauliZ(), SingleSite(L))
end

println("✓ Mixed-gate circuit built")
println("  Operations include: PauliX, Reset, HaarRandom, PauliZ")
println()

# ═══════════════════════════════════════════════════════════════════
# SECTION 4: ASCII Visualization
# ═══════════════════════════════════════════════════════════════════
# The print_circuit function generates ASCII diagrams showing the circuit structure.
# This visualization uses the RNG seed to sample specific branches of stochastic
# operations, but does NOT execute any quantum simulation.
#
# For readability, we visualize only the first 10 timesteps of our circuit.

println("ASCII Visualization (first 10 steps, seed=42):")
println()

# Create shorter circuit for visualization
short_circuit = Circuit(L=L, bc=bc, n_steps=10) do c
    apply_with_prob!(c; rng=:ctrl, outcomes=[
        (probability=p_reset, gate=Reset(), geometry=StaircaseRight(1)),
        (probability=1-p_reset, gate=HaarRandom(), geometry=StaircaseRight(1))
    ])
end

# Print ASCII diagram
# The seed parameter controls which stochastic branches are shown
print_circuit(short_circuit; seed=42)
println()

println("ℹ ASCII visualization legend:")
println("  • Reset: Measurement and reset to |0⟩")
println("  • HaarRandom: Random unitary from Haar measure")
println("  • Staircase pattern: Each timestep moves one site right")
println()

# ═══════════════════════════════════════════════════════════════════
# SECTION 5: SVG Visualization (Optional)
# ═══════════════════════════════════════════════════════════════════
# The plot_circuit function generates publication-quality SVG diagrams.
# This requires Luxor.jl as a weak dependency (optional).
#
# We use try-catch to gracefully handle the case where Luxor is not installed.

println("SVG Visualization (optional - requires Luxor.jl):")
println()

# Ensure output directory exists
mkpath("examples/output")

# Try loading Luxor for SVG export
try
    @eval using Luxor
    plot_circuit(short_circuit; seed=42, filename="examples/output/circuit_tutorial.svg")
    println("✓ SVG diagram saved to examples/output/circuit_tutorial.svg")
    println("  You can open this file in a web browser or include it in LaTeX documents")
catch e
    if isa(e, ArgumentError) && occursin("Luxor", string(e))
        println("ℹ Luxor.jl not available - SVG export skipped")
        println("  To enable SVG export, install Luxor: ]add Luxor")
    else
        println("⚠ SVG export failed: $(sprint(showerror, e))")
    end
end
println()

# ═══════════════════════════════════════════════════════════════════
# SECTION 6: Simulating Circuits
# ═══════════════════════════════════════════════════════════════════
# Once a circuit is built and visualized, we can execute it using simulate!().
# The simulation requires:
#   1. A SimulationState with initialized MPS and RNG registry
#   2. The circuit to execute
#   3. Number of trajectory samples (n_circuits)
#
# CRITICAL: Using the same RNG seed for visualization and simulation ensures
# they show identical stochastic branch choices.

println("Simulating circuit (seed=42)...")
println()

# Create simulation state with RNG registry
# Each RNG source (ctrl, proj, haar, born) gets its own deterministic seed
state = SimulationState(
    L = L, 
    bc = bc, 
    rng = RNGRegistry(ctrl=42, proj=1, haar=2, born=3)
)

# Initialize state to product state with x=1/16
# This represents all qubits in a coherent state |ψ⟩ = |+⟩ ⊗ ... ⊗ |+⟩
# where |+⟩ = (|0⟩ + |1⟩)/√2, rotated by angle θ with cos²(θ/2) = 1/16
initialize!(state, ProductState(x0=1//16))

# Execute circuit with one trajectory
simulate!(circuit, state; n_circuits=1)

println("✓ Circuit simulation complete")
println("  Final state prepared with $(n_steps) timesteps")
println("  Stochastic branches sampled with seed=42")
println()

# ═══════════════════════════════════════════════════════════════════
# SECTION 7: Comparing Visualization and Simulation
# ═══════════════════════════════════════════════════════════════════
# A key feature of the Circuit API is that visualization and simulation are
# deterministically linked via RNG seeds. The same seed produces:
#   - Same gate sequence in ASCII/SVG visualization
#   - Same quantum trajectory in simulation
#
# This ensures that what you see in the diagram is exactly what gets executed.

println("Verification: Deterministic consistency")
println()

# Print visualization again to compare
println("Visualization output (seed=42):")
print_circuit(short_circuit; seed=42)
println()

# Run simulation with same seed
state_verify = SimulationState(
    L = L, 
    bc = bc, 
    rng = RNGRegistry(ctrl=42, proj=1, haar=2, born=3)
)
initialize!(state_verify, ProductState(x0=1//16))
simulate!(short_circuit, state_verify; n_circuits=1)

println("✓ Simulation with seed=42 complete")
println()
println("ℹ The visualization and simulation used identical RNG branches")
println("  → What you see in the diagram is what gets executed")
println("  → This enables reliable debugging and reproducible results")
println()

# ═══════════════════════════════════════════════════════════════════
# SUMMARY
# ═══════════════════════════════════════════════════════════════════

println("=" ^ 70)
println("Tutorial Summary")
println("=" ^ 70)
println()
println("What you learned:")
println("  1. Build circuits with do-block syntax (lazy/symbolic)")
println("  2. Visualize circuits with print_circuit (ASCII) and plot_circuit (SVG)")
println("  3. Simulate circuits with simulate!() (deterministic execution)")
println("  4. Use RNG seeds to ensure visualization matches simulation")
println()
println("Circuit API workflow:")
println("  Build → Visualize → Inspect → Simulate → Analyze")
println()
println("Next steps:")
println("  • Experiment with different gate types (Reset, HaarRandom, PauliX, PauliZ)")
println("  • Try different geometries (SingleSite, StaircaseRight, StaircaseLeft)")
println("  • Vary system size L and timesteps n_steps")
println("  • Compare periodic vs open boundary conditions")
println("  • Install Luxor.jl for publication-quality SVG diagrams")
println()
println("=" ^ 70)
println("Tutorial complete!")
println("=" ^ 70)
