module QuantumCircuitsMPSLuxorExt

using Luxor
using QuantumCircuitsMPS
using QuantumCircuitsMPS: Circuit, expand_circuit, ExpandedOp

"""
    plot_circuit(circuit::Circuit; seed::Int=0, filename::String="circuit.svg")

Export a quantum circuit diagram to SVG using Luxor.jl.

Renders the circuit as a wire diagram with:
- Vertical lines representing qubit wires (labeled q1, q2, ...)
- Boxes with gate labels at sites where gates act
- Row headers showing step numbers (with letter suffixes for multi-op steps)
- Time axis goes upward, qubits spread horizontally

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
    ROW_HEIGHT = 60.0  # Height per time step (was COLUMN_WIDTH)
    GATE_WIDTH = 30.0   # Width along qubit axis
    GATE_HEIGHT = 40.0  # Height along time axis
    MARGIN = 50.0
    
    # Expand circuit to get concrete operations
    expanded = expand_circuit(circuit; seed=seed)
    
    # Build row list (was column list)
    rows = []
    for (step_idx, step_ops) in enumerate(expanded)
        if isempty(step_ops)
            # Empty step - still render one row
            push!(rows, (step_idx, "", nothing))
        elseif length(step_ops) == 1
            # Single op - no letter suffix
            push!(rows, (step_idx, "", step_ops[1]))
        else
            # Multiple ops - letter suffix (a, b, c...)
            for (substep_idx, op) in enumerate(step_ops)
                letter = Char('a' + substep_idx - 1)
                push!(rows, (step_idx, string(letter), op))
            end
        end
    end
    
    # Calculate canvas size (swapped dimensions)
    canvas_width = 2 * MARGIN + circuit.L * QUBIT_SPACING + 100  # qubit dimension
    canvas_height = 2 * MARGIN + length(rows) * ROW_HEIGHT       # time dimension
    
    # Create drawing
    Drawing(canvas_width, canvas_height, filename)
    background("white")
    origin(Point(MARGIN, MARGIN))
    
    # Draw vertical qubit wires (was horizontal)
    wire_length = length(rows) * ROW_HEIGHT
    for q in 1:circuit.L
        x = q * QUBIT_SPACING  # was y
        line(Point(x, 0), Point(x, wire_length), :stroke)
        # Qubit label at bottom
        text("q$q", Point(x, wire_length + 20), halign=:center)
    end
    
    # Draw step headers on left side (was top)
    for (row_idx, (step, letter, _)) in enumerate(rows)
        y = wire_length - (row_idx - 0.5) * ROW_HEIGHT  # was x
        header = letter == "" ? string(step) : "$(step)$(letter)"
        text(header, Point(-10, y + 5), halign=:right, valign=:center)
    end
    
    # Draw gate boxes with transposed coordinates
    for (row_idx, (_, _, op)) in enumerate(rows)
        if op !== nothing
            y = wire_length - (row_idx - 0.5) * ROW_HEIGHT  # time position (was x)
            
            # Check if single-qubit or multi-qubit gate
            if length(op.sites) == 1
                # Single-qubit gate
                x = op.sites[1] * QUBIT_SPACING  # qubit position (was y)
                
                # Draw filled white box first, then black stroke
                setcolor("white")
                box(Point(x, y), GATE_WIDTH, GATE_HEIGHT, :fill)
                setcolor("black")
                box(Point(x, y), GATE_WIDTH, GATE_HEIGHT, :stroke)
                text(op.label, Point(x, y + 5), halign=:center, valign=:center)
            else
                # Multi-qubit gate - render single spanning box
                min_site = minimum(op.sites)
                max_site = maximum(op.sites)
                center_x = ((min_site + max_site) / 2) * QUBIT_SPACING  # was center_y
                span_width = (max_site - min_site) * QUBIT_SPACING + GATE_WIDTH  # was span_height
                
                # Draw one wide box spanning all sites
                setcolor("white")
                box(Point(center_x, y), span_width, GATE_HEIGHT, :fill)
                setcolor("black")
                box(Point(center_x, y), span_width, GATE_HEIGHT, :stroke)
                # Label centered horizontally in spanning box
                text(op.label, Point(center_x, y + 5), halign=:center, valign=:center)
            end
        end
    end
    
    finish()
end

end # module
