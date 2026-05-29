module QuantumCircuitsMPSLuxorExt

using Luxor
using QuantumCircuitsMPS
using QuantumCircuitsMPS: Circuit, expand_circuit_grouped, ExpandedOp,
    gate_label, is_compound_geometry, get_compound_elements, compute_sites_dispatch

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
    apply_with_prob!(c; rng=:gates_spacetime, outcomes=[
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
function QuantumCircuitsMPS._plot_circuit_impl(circuit::Circuit; seed::Int=0, filename::Union{String, Nothing}=nothing)
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
        text(display_label, Point(x, y + 5), halign=:center, valign=:center)
    end
    
    # Helper: Draw connecting line between two points (optional dashed style)
    function render_connecting_line(pt1, pt2; dashed=false)
        if dashed
            setdash("dashed")
        end
        line(pt1, pt2, :stroke)
        if dashed
            setdash("solid")  # Reset to solid
        end
    end
    
    # seed parameter is kept for backward compatibility but is no longer used;
    # visualization always shows the circuit template (all operation layers unconditionally).

    # Build template groups: steps → groups → ops (same format as expand_circuit_grouped,
    # but ALL stochastic outcomes are included unconditionally instead of sampling with seed)
    function build_template_groups(circ)
        res = Vector{Vector{Vector{ExpandedOp}}}()

        for step in 1:circ.n_steps
            step_groups = Vector{Vector{ExpandedOp}}()

            for op in circ.operations
                if op.type == :deterministic
                    group_ops = ExpandedOp[]
                    if is_compound_geometry(op.geometry)
                        elements = get_compound_elements(op.geometry, circ.L, circ.bc)
                        for sites in elements
                            push!(group_ops, ExpandedOp(step, op.gate, sites, gate_label(op.gate)))
                        end
                    else
                        sites = compute_sites_dispatch(op.geometry, op.gate, step, circ.L, circ.bc)
                        push!(group_ops, ExpandedOp(step, op.gate, sites, gate_label(op.gate)))
                    end
                    if !isempty(group_ops)
                        push!(step_groups, group_ops)
                    end

                elseif op.type == :stochastic
                    # Show ALL outcomes unconditionally — this is the circuit template
                    for outcome in op.outcomes
                        outcome_ops = ExpandedOp[]
                        if is_compound_geometry(outcome.geometry)
                            elements = get_compound_elements(outcome.geometry, circ.L, circ.bc)
                            for sites in elements
                                push!(outcome_ops, ExpandedOp(step, outcome.gate, sites, gate_label(outcome.gate)))
                            end
                        else
                            sites = compute_sites_dispatch(outcome.geometry, outcome.gate, step, circ.L, circ.bc)
                            push!(outcome_ops, ExpandedOp(step, outcome.gate, sites, gate_label(outcome.gate)))
                        end
                        if !isempty(outcome_ops)
                            push!(step_groups, outcome_ops)
                        end
                    end
                end
            end

            push!(res, step_groups)
        end
        return res
    end

    # Build groups from circuit template (all ops shown, no stochastic sampling)
    expanded = build_template_groups(circuit)
    
    # Helper: check if two ops overlap (share any qubits)
    function ops_overlap(op1, op2)
        return !isempty(intersect(op1.sites, op2.sites))
    end
    
    # Helper: check if any ops in the list overlap with each other
    function any_ops_overlap(ops)
        for i in 1:length(ops), j in (i+1):length(ops)
            if ops_overlap(ops[i], ops[j])
                return true
            end
        end
        return false
    end
    
    # Build row list with visual row position tracking
    # Each row is: (step_idx, letter, ops_list, row_pos)
    # ops_list is a Vector{ExpandedOp} of gates to render on the same visual row
    rows = []
    visual_row = 0
    for (step_idx, step_groups) in enumerate(expanded)
        if isempty(step_groups)
            # Empty step - still render one row
            visual_row += 1
            push!(rows, (step_idx, "", ExpandedOp[], visual_row))
        else
            # Build batches: each batch is a set of ops on the same visual row.
            # Within a group (same apply! call), non-overlapping ops share a row.
            # Different groups always get separate rows.
            batches = Vector{ExpandedOp}[]
            for group_ops in step_groups
                if isempty(group_ops)
                    continue
                elseif !any_ops_overlap(group_ops)
                    # All ops in this group can share one row
                    push!(batches, group_ops)
                else
                    # Overlapping within group - each op gets its own row
                    for op in group_ops
                        push!(batches, [op])
                    end
                end
            end
            
            if isempty(batches)
                visual_row += 1
                push!(rows, (step_idx, "", ExpandedOp[], visual_row))
            elseif length(batches) == 1
                # Single batch - no letter suffix
                visual_row += 1
                push!(rows, (step_idx, "", batches[1], visual_row))
            else
                # Multiple batches - letter suffixes
                for (batch_idx, batch) in enumerate(batches)
                    visual_row += 1
                    letter = string(Char('a' + batch_idx - 1))
                    push!(rows, (step_idx, letter, batch, visual_row))
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
        text("q$q", Point(x, wire_length + 20), halign=:center)
    end
    
    # Draw step headers on left side (was top)
    # For parallel ops (same row_pos), only render header once
    rendered_headers = Set{Int}()
    for (step, letter, _, row_pos) in rows
        if row_pos ∉ rendered_headers
            push!(rendered_headers, row_pos)
            y = wire_length - (row_pos - 0.5) * ROW_HEIGHT  # was x
            header = letter == "" ? string(step) : "$(step)$(letter)"
            text(header, Point(-10, y + 5), halign=:right, valign=:center)
        end
    end
    
    # Draw gate boxes with transposed coordinates
    for (_, _, ops, row_pos) in rows
        y = wire_length - (row_pos - 0.5) * ROW_HEIGHT  # time position
        for op in ops
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
                    render_connecting_line(Point(line_start_x, y), Point(line_end_x, y); dashed=is_periodic_wrap)
                    
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
                    text(display_label, Point(center_x, y + 5), halign=:center, valign=:center)
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
