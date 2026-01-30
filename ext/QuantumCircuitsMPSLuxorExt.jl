module QuantumCircuitsMPSLuxorExt

using Luxor
using QuantumCircuitsMPS
using QuantumCircuitsMPS: Circuit, expand_circuit, ExpandedOp

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
```julia
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
```

# Determinism
Using the same `seed` value produces identical diagrams. The seed controls
which stochastic branches are displayed, matching the behavior of
`expand_circuit(circuit; seed=seed)`.

# See Also
- [`print_circuit`](@ref): ASCII visualization (no Luxor required)
- [`expand_circuit`](@ref): Get the concrete operations being visualized
"""
function QuantumCircuitsMPS.plot_circuit(circuit::Circuit; seed::Int=0, filename::String="circuit.svg")
    # Layout constants
    QUBIT_SPACING = 40.0
    COLUMN_WIDTH = 60.0
    GATE_WIDTH = 40.0
    GATE_HEIGHT = 30.0
    MARGIN = 50.0
    
    # Expand circuit to get concrete operations
    expanded = expand_circuit(circuit; seed=seed)
    
    # Build column list (same logic as ASCII visualization)
    columns = []
    for (step_idx, step_ops) in enumerate(expanded)
        if isempty(step_ops)
            # Empty step - still render one column
            push!(columns, (step_idx, "", nothing))
        elseif length(step_ops) == 1
            # Single op - no letter suffix
            push!(columns, (step_idx, "", step_ops[1]))
        else
            # Multiple ops - letter suffix (a, b, c...)
            for (substep_idx, op) in enumerate(step_ops)
                letter = Char('a' + substep_idx - 1)
                push!(columns, (step_idx, string(letter), op))
            end
        end
    end
    
    # Calculate canvas size
    canvas_width = 2 * MARGIN + length(columns) * COLUMN_WIDTH + 100
    canvas_height = 2 * MARGIN + circuit.L * QUBIT_SPACING
    
    # Create drawing
    Drawing(canvas_width, canvas_height, filename)
    background("white")
    origin(Point(MARGIN, MARGIN))
    
    # Draw horizontal qubit wires
    wire_length = length(columns) * COLUMN_WIDTH
    for q in 1:circuit.L
        y = q * QUBIT_SPACING
        line(Point(0, y), Point(wire_length, y), :stroke)
        # Qubit label
        text("q$q", Point(-30, y + 5))
    end
    
    # Draw step headers
    for (col_idx, (step, letter, _)) in enumerate(columns)
        x = (col_idx - 0.5) * COLUMN_WIDTH
        header = letter == "" ? string(step) : "$(step)$(letter)"
        text(header, Point(x, -10), halign=:center)
    end
    
    # Draw gate boxes
    for (col_idx, (_, _, op)) in enumerate(columns)
        if op !== nothing
            x = (col_idx - 0.5) * COLUMN_WIDTH
            
            # Check if single-qubit or multi-qubit gate
            if length(op.sites) == 1
                # Single-qubit gate - render as before
                y = op.sites[1] * QUBIT_SPACING
                sethue("white")
                box(Point(x, y), GATE_WIDTH, GATE_HEIGHT, :fill)
                sethue("black")
                box(Point(x, y), GATE_WIDTH, GATE_HEIGHT, :stroke)
                text(op.label, Point(x, y + 5), halign=:center, valign=:center)
            else
                # Multi-qubit gate - render single spanning box
                min_site = minimum(op.sites)
                max_site = maximum(op.sites)
                center_y = ((min_site + max_site) / 2) * QUBIT_SPACING
                span_height = (max_site - min_site) * QUBIT_SPACING + GATE_HEIGHT
                
                # Draw one tall box spanning all sites
                sethue("white")
                box(Point(x, center_y), GATE_WIDTH, span_height, :fill)
                sethue("black")
                box(Point(x, center_y), GATE_WIDTH, span_height, :stroke)
                # Label centered vertically in spanning box
                text(op.label, Point(x, center_y + 5), halign=:center, valign=:center)
            end
        end
    end
    
    finish()
end

end # module
