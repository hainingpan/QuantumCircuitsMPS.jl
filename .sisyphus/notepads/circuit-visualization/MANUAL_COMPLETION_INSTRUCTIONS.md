# Task 12 - Manual Completion Instructions

## Status: BLOCKED - Agent Limitation

The Prometheus agent cannot modify code files. Below are the exact changes needed to complete Task 12.

---

## Step 1: Add Docstring to plot_circuit

**File**: `ext/QuantumCircuitsMPSLuxorExt.jl`

Replace line 7-8:
```julia
# Extension provides plot_circuit when Luxor is loaded
function QuantumCircuitsMPS.plot_circuit(circuit::Circuit; seed::Int=0, filename::String="circuit.svg")
```

With:
```julia
"""
    plot_circuit(circuit::Circuit; seed::Int=0, filename::String="circuit.svg")

Export a quantum circuit diagram to SVG using Luxor.jl.

Renders the circuit as a wire diagram with:
- Horizontal lines representing qubit wires (labeled q1, q2, ...)
- Boxes with gate labels at sites where gates act  
- Column headers showing step numbers (with letter suffixes for multi-op steps)

# Arguments
- `circuit::Circuit`: The circuit to visualize
- `seed::Int=0`: RNG seed for stochastic branch resolution (same seed = same diagram)
- `filename::String="circuit.svg"`: Output file path (SVG format)

# Requirements
Requires `Luxor` to be loaded (`using Luxor` before calling).

# Example
\`\`\`julia
using QuantumCircuitsMPS
using Luxor  # Load the extension

circuit = Circuit(L=4, bc=:periodic, n_steps=5) do c
    apply!(c, Reset(), StaircaseRight(1))
    apply_with_prob!(c; rng=:ctrl, outcomes=[
        (probability=0.5, gate=HaarRandom(), geometry=StaircaseLeft(4))
    ])
end

# Export to SVG
plot_circuit(circuit; seed=42, filename="my_circuit.svg")
\`\`\`

# Determinism
Using the same `seed` value produces identical diagrams. The seed controls
which stochastic branches are displayed, matching the behavior of
`expand_circuit(circuit; seed=seed)`.

# See Also
- [`print_circuit`](@ref): ASCII visualization (no Luxor required)
- [`expand_circuit`](@ref): Get the concrete operations being visualized
"""
function QuantumCircuitsMPS.plot_circuit(circuit::Circuit; seed::Int=0, filename::String="circuit.svg")
```

---

## Step 2: Add Warmup Block to Tests

**File**: `test/circuit_test.jl`

After line 5 (`using QuantumCircuitsMPS`), add:

```julia

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
```

---

## Step 3: Commit Changes

```bash
# Commit 1 - Docstrings
git add src/Circuit/Circuit.jl src/Plotting/Plotting.jl ext/QuantumCircuitsMPSLuxorExt.jl
git commit -m "docs(circuit): add docstrings for Circuit and Plotting modules"

# Commit 2 - Test warmup
git add test/circuit_test.jl  
git commit -m "perf(test): add warmup block to reduce JIT compilation overhead"
```

---

## Step 4: Verify Completion

```bash
# Verify docstrings
julia --project -e 'using QuantumCircuitsMPS; println(@doc Circuit)'

# Verify test speedup
time julia --project -e 'using Pkg; Pkg.test()'
# Should complete in <45 seconds (was ~90s)
```

---

## Task 12 Checklist

- [ ] Docstring added to `plot_circuit` 
- [ ] Warmup block added to tests
- [ ] Commit 1 created (docstrings)
- [ ] Commit 2 created (test warmup)
- [ ] Verified: `?Circuit` shows docs
- [ ] Verified: Tests run in <45s

