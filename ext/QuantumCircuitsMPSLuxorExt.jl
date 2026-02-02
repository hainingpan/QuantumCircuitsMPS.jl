module QuantumCircuitsMPSLuxorExt

using Luxor
using QuantumCircuitsMPS
using QuantumCircuitsMPS: Circuit, expand_circuit, ExpandedOp

"""Wrapper type for SVG data that auto-displays in Jupyter notebooks."""
struct SVGImage
    data::String
end

# MIME display method for IJulia auto-rendering
function Base.show(io::IO, ::MIME"image/svg+xml", img::SVGImage)
    write(io, img.data)
end

"""
    plot_circuit(circuit::Circuit; seed::Int=0, filename::Union{String, Nothing}=nothing)

Export a quantum circuit diagram to SVG using Luxor.jl.

Renders the circuit as a wire diagram with:
- Vertical lines representing qubit wires (labeled q1, q2, ...)
- Boxes with gate labels at sites where gates act
- Row headers showing step numbers (with letter suffixes for multi-op steps)
- Time axis goes upward, qubits spread horizontally

# Arguments
- `circuit::Circuit`: The circuit to visualize
- `seed::Int=0`: RNG seed for stochastic branch resolution (same seed = same diagram)
- `filename::Union{String, Nothing}=nothing`: Output file path (SVG format). If `nothing`, returns `SVGImage` for auto-display in Jupyter.

# Returns
- If `filename === nothing`: Returns `SVGImage` wrapper (auto-displays in Jupyter notebooks)
- If `filename` provided: Writes to file and returns `nothing`

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

# Auto-display in Jupyter (returns SVGImage)
plot_circuit(circuit; seed=42)

# Export to file
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
function QuantumCircuitsMPS.plot_circuit(circuit::Circuit; seed::Int=0, filename::Union{String, Nothing}=nothing)
    # Layout constants
    QUBIT_SPACING = 40.0
    ROW_HEIGHT = 60.0  # Height per time step (was COLUMN_WIDTH)
    GATE_WIDTH = 30.0   # Width along qubit axis
    GATE_HEIGHT = 40.0  # Height along time axis
    MARGIN = 50.0
    MIN_FONT_SIZE = 8.0  # Minimum font size before truncation
    DEFAULT_FONT_SIZE = 11.0  # Default Luxor font size
    
    # Helper: Calculate font size to fit text in box, with truncation fallback
    function calc_font_size(label::String, box_width::Float64, default_size::Float64=DEFAULT_FONT_SIZE)
        # Set default font size to measure
        fontsize(default_size)
        extents = textextents(label)
        text_width = extents[3]  # width is 3rd element
        
        # If fits at default size, return default
        if text_width <= box_width * 0.9  # 90% of box for padding
            return (default_size, label)
        end
        
        # Scale down proportionally
        scale_factor = (box_width * 0.9) / text_width
        scaled_size = default_size * scale_factor
        
        # If scaled size >= minimum, use it
        if scaled_size >= MIN_FONT_SIZE
            return (scaled_size, label)
        end
        
        # At minimum size, check if truncation needed
        fontsize(MIN_FONT_SIZE)
        extents = textextents(label)
        text_width = extents[3]
        
        if text_width <= box_width * 0.9
            return (MIN_FONT_SIZE, label)
        end
        
        # Truncate with "..."
        truncated = label
        extents = textextents(truncated * "...")
        while extents[3] > box_width * 0.9 && length(truncated) > 1
            truncated = truncated[1:end-1]
            extents = textextents(truncated * "...")
        end
        
        return (MIN_FONT_SIZE, truncated * "...")
    end
    
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
    
    # Conditional: in-memory mode vs file mode
    if filename === nothing
        # In-memory mode: create SVG drawing surface
        Drawing(canvas_width, canvas_height, :svg)
    else
        # File mode: create drawing with filename
        Drawing(canvas_width, canvas_height, filename)
    end
    
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
                
                # Apply dynamic font sizing
                (font_sz, display_label) = calc_font_size(op.label, GATE_WIDTH)
                fontsize(font_sz)
                text(display_label, Point(x, y + 5), halign=:center, valign=:center)
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
                
                # Apply dynamic font sizing with span_width
                (font_sz, display_label) = calc_font_size(op.label, span_width)
                fontsize(font_sz)
                text(display_label, Point(center_x, y + 5), halign=:center, valign=:center)
            end
        end
    end
    
    finish()
    
    # Return appropriate value based on mode
    if filename === nothing
        # In-memory mode: extract SVG and return wrapper
        return SVGImage(svgstring())
    else
        # File mode: return nothing (backward compatibility)
        return nothing
    end
end

end # module
