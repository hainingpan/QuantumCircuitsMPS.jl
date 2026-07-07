module QuantumCircuitsMPSLuxorExt

using Luxor
using QuantumCircuitsMPS
using QuantumCircuitsMPS: Circuit, expand_circuit_grouped, ExpandedOp,
                          gate_label, is_compound_geometry, get_compound_elements,
                          compute_sites_dispatch,
                          pack_ops_into_layers

"""Wrapper type for SVG data that auto-displays in Jupyter notebooks."""
struct SVGImage
    data::String
end

# MIME display method for IJulia auto-rendering
function Base.show(io::IO, ::MIME"image/svg+xml", img::SVGImage)
    write(io, img.data)
end

"""
    plot_circuit(circuit::Circuit; gates_spacetime::Int=0, filename=nothing)

Export a quantum circuit diagram to SVG using Luxor.jl.

Shows a specific stochastic realization determined by the `gates_spacetime` RNG seed,
matching what `expand_circuit(circuit; seed=gates_spacetime)` produces.

# Arguments
- `circuit::Circuit`: The circuit to visualize
- `gates_spacetime::Int=0`: RNG seed controlling which stochastic branches fire.
  Same seed = same diagram = same realization as `simulate!`.
- `filename::Union{String, Nothing}=nothing`: Output file path (SVG format).
  If `nothing`, returns `SVGImage` for auto-display in Jupyter.

# Example
```julia
using QuantumCircuitsMPS, Luxor

circuit = Circuit(L=8, bc=:periodic, n_steps=1) do c
    apply!(c, HaarRandom(), Bricklayer(:even))
    apply_with_prob!(c; rng=:gates_spacetime, outcomes=[
        (probability=0.15, gate=Measurement(:Z), geometry=AllSites())
    ])
end

plot_circuit(circuit; gates_spacetime=42)
plot_circuit(circuit; gates_spacetime=42, filename="my_circuit.svg")
```

# See Also
- [`print_circuit`](@ref): ASCII visualization (no Luxor required)
- [`expand_circuit`](@ref): Get the concrete operations being visualized
"""
function QuantumCircuitsMPS._plot_circuit_impl(
        circuit::Circuit; n_steps::Int = 1, gates_spacetime::Int = 0,
        filename::Union{String, Nothing} = nothing)
    # TODO: Known bug - non-adjacent gates (e.g., NNN gates) are not rendered correctly.
    # The current implementation assumes gates act on adjacent or contiguous qubit ranges.

    # Layout constants
    QUBIT_SPACING = 40.0
    ROW_HEIGHT = 60.0  # Height per time step (was COLUMN_WIDTH)
    GATE_WIDTH = 30.0   # Width along qubit axis
    GATE_HEIGHT = 40.0  # Height along time axis
    MARGIN = 50.0
    MIN_FONT_SIZE = 8.0  # Minimum font size before truncation
    DEFAULT_FONT_SIZE = 11.0  # Default Luxor font size

    # Helper: Calculate font size to fit text in box, with truncation fallback
    function calc_font_size(label::String, box_width::Float64, default_size::Float64 = DEFAULT_FONT_SIZE)
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
            truncated = truncated[1:(end - 1)]
            extents = textextents(truncated * "...")
        end

        return (MIN_FONT_SIZE, truncated * "...")
    end

    # Helper: Draw a filled white box with black stroke at (x, y) position
    function render_gate_box(x, y, width, height)
        setcolor("white")
        box(Point(x, y), width, height, :fill)
        setcolor("black")
        box(Point(x, y), width, height, :stroke)
    end

    # Helper: Render label with dynamic font sizing, centered at (x, y)
    function render_gate_label(x, y, label, max_width)
        (font_sz, display_label) = calc_font_size(label, max_width)
        fontsize(font_sz)
        text(display_label, Point(x, y + 5), halign = :center, valign = :center)
    end

    # Helper: Draw connecting line between two points (optional dashed style)
    function render_connecting_line(pt1, pt2; dashed = false)
        if dashed
            setdash("dashed")
        end
        line(pt1, pt2, :stroke)
        if dashed
            setdash("solid")  # Reset to solid
        end
    end

    expanded = expand_circuit_grouped(circuit; n_steps = n_steps, seed = gates_spacetime)

    # Build row list with visual row position tracking
    # Each row is: (step_idx, label_text, ops_list, row_pos, render_header::Bool)
    # render_header=true marks the first layer of each group (where label is drawn)
    rows = []
    visual_row = 0
    for (step_idx, step_groups) in enumerate(expanded)
        groups = [g for g in step_groups if !isempty(g)]
        if isempty(groups)
            # Empty step - still render one row
            visual_row += 1
            push!(rows, (step_idx, string(step_idx), ExpandedOp[], visual_row, true))
        else
            for (g_idx, group_ops) in enumerate(groups)
                label_text = length(groups) == 1 ? string(step_idx) :
                             string(step_idx, Char('a' + g_idx - 1))
                layers = pack_ops_into_layers(group_ops)
                for (layer_idx, layer_ops) in enumerate(layers)
                    visual_row += 1
                    push!(rows, (
                        step_idx, label_text, layer_ops, visual_row, layer_idx == 1))
                end
            end
        end
    end
    n_visual_rows = visual_row

    # Calculate canvas size (swapped dimensions)
    canvas_width = 2 * MARGIN + circuit.L * QUBIT_SPACING + 100  # qubit dimension
    canvas_height = 2 * MARGIN + n_visual_rows * ROW_HEIGHT      # time dimension

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
    wire_length = n_visual_rows * ROW_HEIGHT
    for q in 1:circuit.L
        x = q * QUBIT_SPACING  # was y
        line(Point(x, 0), Point(x, wire_length), :stroke)
        # Qubit label at bottom
        text("q$q", Point(x, wire_length + 20), halign = :center)
    end

    # Draw step headers on left side (was top)
    # render_header=true marks the first layer of each group
    # For multi-layer groups, center the label across all layers
    # Collect group spans: for each (step, label_text) combo, find first and last row_pos
    group_spans = Dict{Tuple{Int, String}, Tuple{Int, Int}}()  # (step, label) → (first_row_pos, last_row_pos)
    for (step, label_text, _, row_pos, render_header) in rows
        key = (step, label_text)
        if !haskey(group_spans, key)
            group_spans[key] = (row_pos, row_pos)
        else
            first_pos, _ = group_spans[key]
            group_spans[key] = (first_pos, row_pos)
        end
    end
    rendered_labels = Set{Tuple{Int, String}}()
    for (step, label_text, _, row_pos, render_header) in rows
        key = (step, label_text)
        if render_header && key ∉ rendered_labels
            push!(rendered_labels, key)
            first_pos, last_pos = group_spans[key]
            # Center y across all layers of this group
            y_center = wire_length - ((first_pos + last_pos - 1) / 2) * ROW_HEIGHT
            text(label_text, Point(-10, y_center + 5), halign = :right, valign = :center)
        end
    end

    # Draw gate boxes with transposed coordinates
    for (_, _, ops, row_pos, _) in rows
        y = wire_length - (row_pos - 0.5) * ROW_HEIGHT  # time position
        for op in ops
            # Record-marker pseudo-op (gate === nothing, no sites): render as
            # a dashed rule across all wires with its label to the right.
            if isempty(op.sites)
                setdash("dashed")
                line(Point(QUBIT_SPACING - GATE_WIDTH / 2, y),
                    Point(circuit.L * QUBIT_SPACING + GATE_WIDTH / 2, y), :stroke)
                setdash("solid")
                fontsize(DEFAULT_FONT_SIZE)
                text(
                    op.label, Point(circuit.L * QUBIT_SPACING + GATE_WIDTH / 2 + 5, y + 5),
                    halign = :left, valign = :center)
                continue
            end
            # Check if single-qubit or multi-qubit gate
            if length(op.sites) == 1
                # Single-qubit gate
                x = op.sites[1] * QUBIT_SPACING  # qubit position

                render_gate_box(x, y, GATE_WIDTH, GATE_HEIGHT)
                render_gate_label(x, y, op.label, GATE_WIDTH)
            else
                # Multi-qubit gate
                min_site = minimum(op.sites)
                max_site = maximum(op.sites)
                span = max_site - min_site
                L = circuit.L

                # Calculate wrapped span (for periodic BC, adjacent pairs like [8,1] have span=L-1 not 1)
                # wrapped_span is the "short way around" for periodic BC
                wrapped_span = min(span, L - span)

                # Determine rendering mode:
                # - Adjacent: wrapped_span == 1 (includes periodic wraps like [8,1] → [1,8] → span=7, L-span=1)
                # - Spanning all qubits: length == L (render as single box)
                # - Non-adjacent: wrapped_span > 1 (NNN or larger gaps)
                is_adjacent = (wrapped_span == 1)
                spans_all = (length(op.sites) == L)

                if is_adjacent || spans_all
                    if span == L - 1  # Wrapping adjacent pair (e.g., [4,1] on L=4)
                        # Render as two half-boxes (brackets) at the boundary qubits.
                        # The open side faces the boundary edge, indicating the gate wraps.
                        # No label — it would span empty space between the qubits.
                        x_min = min_site * QUBIT_SPACING
                        x_max = max_site * QUBIT_SPACING
                        hw = GATE_WIDTH / 2
                        hh = GATE_HEIGHT / 2

                        # Half-box at min_site: open on LEFT (gate wraps in from left boundary)
                        setcolor("white")
                        box(Point(x_min, y), GATE_WIDTH, GATE_HEIGHT, :fill)
                        setcolor("black")
                        line(Point(x_min - hw, y - hh), Point(x_min + hw, y - hh), :stroke)  # top
                        line(Point(x_min + hw, y - hh), Point(x_min + hw, y + hh), :stroke)  # right
                        line(Point(x_min + hw, y + hh), Point(x_min - hw, y + hh), :stroke)  # bottom

                        # Half-box at max_site: open on RIGHT (gate wraps out to right boundary)
                        setcolor("white")
                        box(Point(x_max, y), GATE_WIDTH, GATE_HEIGHT, :fill)
                        setcolor("black")
                        line(Point(x_max + hw, y - hh), Point(x_max - hw, y - hh), :stroke)  # top
                        line(Point(x_max - hw, y - hh), Point(x_max - hw, y + hh), :stroke)  # left
                        line(Point(x_max - hw, y + hh), Point(x_max + hw, y + hh), :stroke)  # bottom
                    else
                        # Normal adjacent or all-spanning gate: single spanning box
                        center_x = ((min_site + max_site) / 2) * QUBIT_SPACING
                        span_width = span * QUBIT_SPACING + GATE_WIDTH

                        render_gate_box(center_x, y, span_width, GATE_HEIGHT)
                        render_gate_label(center_x, y, op.label, span_width)
                    end
                else
                    # Non-adjacent gate: render two boxes + connecting line
                    x_min = min_site * QUBIT_SPACING
                    x_max = max_site * QUBIT_SPACING

                    # Draw boxes at both sites
                    render_gate_box(x_min, y, GATE_WIDTH, GATE_HEIGHT)
                    render_gate_box(x_max, y, GATE_WIDTH, GATE_HEIGHT)

                    # Determine line style: dashed for periodic wrapping, solid for NNN
                    is_periodic_wrap = (span > L / 2)

                    # Draw connecting line between boxes
                    line_start_x = x_min + GATE_WIDTH / 2
                    line_end_x = x_max - GATE_WIDTH / 2
                    render_connecting_line(Point(line_start_x, y), Point(line_end_x, y);
                        dashed = is_periodic_wrap)

                    # Draw label centered between the two boxes
                    center_x = (x_min + x_max) / 2
                    label_width = x_max - x_min
                    (font_sz, display_label) = calc_font_size(op.label, label_width)
                    fontsize(font_sz)

                    # Draw white background for label
                    extents = textextents(display_label)
                    label_bg_width = extents[3] + 6
                    label_bg_height = extents[4] + 4
                    setcolor("white")
                    box(Point(center_x, y), label_bg_width, label_bg_height, :fill)
                    setcolor("black")
                    text(display_label, Point(center_x, y + 5), halign = :center, valign = :center)
                end
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
