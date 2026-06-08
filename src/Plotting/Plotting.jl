"""
    Plotting Module

Circuit visualization for quantum circuits.

This module provides visualization tools for inspecting circuit structure
before or after simulation. Visualizations show the circuit template — all
stochastic outcomes with probability annotations.

# Visualization Functions
- [`print_circuit`](@ref): ASCII/Unicode terminal visualization
- [`plot_circuit`](@ref): SVG export (requires `using Luxor`)

# ASCII Visualization
Renders circuits as qubit wires with gate boxes using either Unicode
box-drawing characters (default) or ASCII fallback for compatibility.

```julia
circuit = Circuit(L=4, bc=:periodic, n_steps=4) do c
    apply!(c, Reset(), StaircaseRight(1))
end

print_circuit(circuit; gates_spacetime=42)  # Terminal output
print_circuit(circuit; gates_spacetime=42, unicode=false)  # ASCII mode
```

# SVG Visualization
Exports high-quality vector graphics using Luxor.jl (optional dependency).
Files can be embedded in documentation, presentations, or papers.

```julia
using Luxor  # Load extension
plot_circuit(circuit; gates_spacetime=42, filename="diagram.svg")
```

# Deterministic Rendering
Both methods use the `gates_spacetime` RNG seed for stochastic branch resolution,
matching `expand_circuit(circuit; seed=gates_spacetime)`.

# See Also
- [`Circuit`](@ref): Build circuits for visualization
- [`expand_circuit`](@ref): Get concrete operations (used internally)
- [`simulate!`](@ref): Execute circuits after visualizing
"""

# ASCII circuit visualization
include("ascii.jl")
