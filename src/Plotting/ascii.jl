# === ASCII Circuit Visualization ===

"""
    build_template_groups_ascii(circuit; n_steps::Int=1) -> Vector{Vector{Vector{ExpandedOp}}}

Build operation groups for ASCII rendering by iterating `circuit.operations` directly,
showing ALL outcomes of stochastic operations unconditionally (circuit template).

For deterministic ops: one group per apply! call (same as expand_circuit_grouped).
For stochastic ops: one group per outcome (ALL outcomes shown, no random selection).

Returns the same steps → groups → ops structure as expand_circuit_grouped.
"""
function build_template_groups_ascii(circuit; n_steps::Int=1)
    result = Vector{Vector{Vector{ExpandedOp}}}()

    for step in 1:n_steps
        step_groups = Vector{Vector{ExpandedOp}}()

        for op in circuit.operations
            if op.type == :deterministic
                group_ops = ExpandedOp[]
                if is_compound_geometry(op.geometry)
                    elements = get_compound_elements(op.geometry, circuit.L, circuit.bc)
                    for sites in elements
                        push!(group_ops, ExpandedOp(step, op.gate, sites, gate_label(op.gate)))
                    end
                else
                    sites = compute_sites_dispatch(op.geometry, op.gate, step, circuit.L, circuit.bc)
                    push!(group_ops, ExpandedOp(step, op.gate, sites, gate_label(op.gate)))
                end
                if !isempty(group_ops)
                    push!(step_groups, group_ops)
                end

            elseif op.type == :stochastic
                # Template: show ALL outcomes unconditionally (no random selection)
                for outcome in op.outcomes
                    outcome_ops = ExpandedOp[]
                    # Annotate label with probability so template view distinguishes from deterministic ops
                    p = outcome.probability
                    base_label = gate_label(outcome.gate)
                    label = p == 1.0 ? base_label : string(base_label, "(", round(p; digits=2), ")")
                    if is_compound_geometry(outcome.geometry)
                        elements = get_compound_elements(outcome.geometry, circuit.L, circuit.bc)
                        for sites in elements
                            push!(outcome_ops, ExpandedOp(step, outcome.gate, sites, label))
                        end
                    else
                        sites = compute_sites_dispatch(outcome.geometry, outcome.gate, step, circuit.L, circuit.bc)
                        push!(outcome_ops, ExpandedOp(step, outcome.gate, sites, label))
                    end
                    if !isempty(outcome_ops)
                        push!(step_groups, outcome_ops)
                    end
                end

            elseif op.type == :record_mark
                # record!(c[, names...]) marker pseudo-op: own group, no sites
                push!(step_groups, [_record_mark_op(step, op)])
            end
            # Unknown op types: skipped (forward-compatible)
        end

        push!(result, step_groups)
    end
    return result
end

"""
    print_circuit(circuit::Circuit; n_steps::Int=1, gates_spacetime::Int=0, io::IO=stdout, unicode::Bool=true)

Print an ASCII visualization of a quantum circuit realization.

Shows the stochastic realization determined by `gates_spacetime` RNG seed,
matching what `expand_circuit(circuit; seed=gates_spacetime)` produces.

# Arguments
- `circuit::Circuit`: Circuit to visualize
- `n_steps::Int=1`: Number of circuit steps to visualize (default: 1)
- `gates_spacetime::Int=0`: RNG seed controlling which stochastic branches fire.
- `io::IO`: Output stream (default: stdout)
- `unicode::Bool`: Use Unicode box-drawing characters (default: true)

# Character Sets
- Unicode mode (default): Uses `─` (wire), `┤` (left box), `├` (right box)
- ASCII mode: Uses `-' (wire), `|` (both box edges)

# Record Markers
`record!(c[, names...])` markers appear as their own row with the marker
glyph on every wire: `▽` in Unicode mode, `[R]` in ASCII mode. Named markers
print their names after the wires (e.g. `▽ ... ▽  [R:entropy]`).

# Layout Algorithm
1. Expands the circuit with `expand_circuit_grouped` (one group per `apply!` call)
2. For each group, packs ops into non-overlapping layers with `pack_ops_into_layers`;
   each layer becomes one visual row, and the group label is printed only on the
   first row of the group
3. Letters identify groups (not sub-rows): single-group steps are labeled `"1:"`,
   multi-group steps `"1a:"`, `"1b:"`, etc.; empty steps → one wire-only row
4. Calculates fixed column width based on longest gate label (+2 for box chars)
5. Renders header row with qubit labels (e.g., "q1", "q2", "q3", "q4")
6. Renders time step rows with gate boxes or wire segments

# Multi-Qubit Gates
For gates spanning multiple sites (e.g., CZ on sites [2, 3]):
- Gate label appears ONCE in a box on the minimum site
- Other sites show continuation boxes (box edges without label)

# Examples
```julia
# Basic usage
circuit = Circuit(L=4, bc=:periodic) do c
    apply!(c, Reset(), StaircaseRight(1))
end
print_circuit(circuit; n_steps=4)

# Output to file
open("circuit.txt", "w") do io
    print_circuit(io, circuit; n_steps=4)
end

# ASCII mode (no Unicode)
print_circuit(circuit; n_steps=4, unicode=false)
```

# See Also
- `expand_circuit`: Get a concrete stochastic realization
- `ExpandedOp`: Concrete operation representation
"""
function print_circuit(io::IO, circuit::Circuit; n_steps::Int=1, gates_spacetime::Int=0, unicode::Bool=true)
    # Character sets
    WIRE = unicode ? '─' : '-'
    LEFT_BOX = unicode ? '┤' : '|'
    RIGHT_BOX = unicode ? '├' : '|'
    
    # 1. Expand circuit with the given RNG seed
    expanded = expand_circuit_grouped(circuit; n_steps=n_steps, seed=gates_spacetime)
    
    # 2. Build row list: (label_text, is_first, ops_list)
    # ops_list is a Vector{ExpandedOp} of gates rendered on the same row.
    # Each group (apply! call) is packed into non-overlapping layers; the label
    # is printed only on the first layer of each group. Letters identify groups,
    # not packed sub-rows: single-group steps get "1:", multi-group "1a:", "1b:", ...
    rows = Tuple{String, Bool, Vector{ExpandedOp}}[]
    for (step_idx, step_groups) in enumerate(expanded)
        groups = [g for g in step_groups if !isempty(g)]
        if isempty(groups)
            push!(rows, ("$(step_idx)", true, ExpandedOp[]))
        else
            for (g_idx, group_ops) in enumerate(groups)
                label_text = length(groups) == 1 ? "$(step_idx)" :
                             "$(step_idx)$(Char('a' + g_idx - 1))"
                layers = pack_ops_into_layers(group_ops)
                for (layer_idx, layer_ops) in enumerate(layers)
                    push!(rows, (label_text, layer_idx == 1, layer_ops))
                end
            end
        end
    end
    
    # 3. Calculate fixed column width (marker pseudo-ops excluded — they are
    # rendered as a fixed glyph per wire, not as gate boxes)
    max_label_len = 1  # Minimum width
    for (_, _, ops) in rows
        for op in ops
            is_record_mark(op) && continue
            max_label_len = max(max_label_len, length(op.label))
        end
    end
    COL_WIDTH = max_label_len + 2  # +2 for box characters
    
    # 4. Print header
    println(io, "Circuit (L=$(circuit.L), bc=$(circuit.bc))")
    println(io)
    
    # Calculate row label width (for alignment)
    max_row_label_len = 0
    for (label_text, is_first, _) in rows
        if is_first
            max_row_label_len = max(max_row_label_len, length(label_text) + 1)  # +1 for ':'
        end
    end
    ROW_LABEL_WIDTH = max(max_row_label_len + 2, 5)  # +2 for padding, min 5
    
    # Qubit header row (q1, q2, q3...)
    print(io, lpad("", ROW_LABEL_WIDTH))  # Empty space for row label column
    for q in 1:circuit.L
        print(io, lpad("q$q", COL_WIDTH))
    end
    println(io)
    
    # 5. Print time step rows
    for (label_text, is_first, ops) in rows
        # Row label printed only on first layer of each group; blank otherwise
        if is_first
            print(io, lpad(label_text * ":", ROW_LABEL_WIDTH - 1), " ")
        else
            print(io, lpad("", ROW_LABEL_WIDTH))
        end
        
        # Record-marker row: render the marker glyph centered on every wire
        # (▽ in Unicode mode, [R] in ASCII mode); named markers append their
        # names after the wires.
        if length(ops) == 1 && is_record_mark(ops[1])
            glyph = unicode ? "▽" : "[R]"
            pad = max(COL_WIDTH - length(glyph), 0)
            left_pad = pad ÷ 2
            right_pad = pad - left_pad
            for q in 1:circuit.L
                print(io, repeat(WIRE, left_pad), glyph, repeat(WIRE, right_pad))
            end
            ops[1].label != "[R]" && print(io, "  ", ops[1].label)
            println(io)
            continue
        end

        # For each qubit column, find the active op (if any)
        for q in 1:circuit.L
            active_op = nothing
            for op in ops
                if q in op.sites
                    active_op = op
                    break
                end
            end
            
            if active_op !== nothing
                if length(active_op.sites) == 1
                    # Single-qubit gate
                    label = active_op.label
                    padding = COL_WIDTH - length(label) - 2
                    left_pad = padding ÷ 2
                    right_pad = padding - left_pad
                    print(io, LEFT_BOX, repeat(WIRE, left_pad), label, repeat(WIRE, right_pad), RIGHT_BOX)
                else
                    # Multi-qubit gate - spanning box logic
                    min_site = minimum(active_op.sites)
                    if q == min_site
                        label = active_op.label
                        padding = COL_WIDTH - length(label) - 2
                        left_pad = padding ÷ 2
                        right_pad = padding - left_pad
                        print(io, LEFT_BOX, repeat(WIRE, left_pad), label, repeat(WIRE, right_pad), RIGHT_BOX)
                    else
                        # Continuation qubit - box without label
                        print(io, LEFT_BOX, repeat(WIRE, COL_WIDTH - 2), RIGHT_BOX)
                    end
                end
            else
                # Wire segment only
                print(io, repeat(WIRE, COL_WIDTH))
            end
        end
        println(io)
    end
end

"""
    print_circuit(circuit::Circuit; n_steps::Int=1, gates_spacetime::Int=0, io::IO=stdout, unicode::Bool=true)

Convenience form. Calls `print_circuit(io, circuit; ...)`.
"""
function print_circuit(circuit::Circuit; n_steps::Int=1, gates_spacetime::Int=0, io::IO=stdout, unicode::Bool=true)
    print_circuit(io, circuit; n_steps=n_steps, gates_spacetime=gates_spacetime, unicode=unicode)
end
