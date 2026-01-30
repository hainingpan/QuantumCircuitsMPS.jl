module QuantumCircuitsMPSLuxorExt

using Luxor
using QuantumCircuitsMPS
using QuantumCircuitsMPS: Circuit, expand_circuit, ExpandedOp

# Extension provides plot_circuit when Luxor is loaded
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
            for site in op.sites
                y = site * QUBIT_SPACING
                # Box centered at (x, y)
                box(Point(x, y), GATE_WIDTH, GATE_HEIGHT, :stroke)
                # Label centered in box
                text(op.label, Point(x, y + 5), halign=:center, valign=:center)
            end
        end
    end
    
    finish()
end

end # module
