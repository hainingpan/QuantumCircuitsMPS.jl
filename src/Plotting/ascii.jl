# === ASCII Circuit Visualization ===

"""
    build_template_groups_ascii(circuit) -> Vector{Vector{Vector{ExpandedOp}}}

Build operation groups for ASCII rendering by iterating `circuit.operations` directly,
showing ALL outcomes of stochastic operations unconditionally (circuit template).

For deterministic ops: one group per apply! call (same as expand_circuit_grouped).
For stochastic ops: one group per outcome (ALL outcomes shown, no random selection).

Returns the same steps → groups → ops structure as expand_circuit_grouped.
"""
function build_template_groups_ascii(circuit)
    result = Vector{Vector{Vector{ExpandedOp}}}()

    for step in 1:circuit.n_steps
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
                    if is_compound_geometry(outcome.geometry)
                        elements = get_compound_elements(outcome.geometry, circuit.L, circuit.bc)
                        for sites in elements
                            push!(outcome_ops, ExpandedOp(step, outcome.gate, sites, gate_label(outcome.gate)))
                        end
                    else
                        sites = compute_sites_dispatch(outcome.geometry, outcome.gate, step, circuit.L, circuit.bc)
                        push!(outcome_ops, ExpandedOp(step, outcome.gate, sites, gate_label(outcome.gate)))
                    end
                    if !isempty(outcome_ops)
                        push!(step_groups, outcome_ops)
                    end
                end
            end
        end

        push!(result, step_groups)
    end
    return result
end

"""
    print_circuit(circuit::Circuit; seed::Int=0, io::IO=stdout, unicode::Bool=true)

Print an ASCII visualization of the circuit TEMPLATE showing all operation layers.

Renders the circuit as a grid with:
- Qubit labels as column headers (q1, q2, q3...)
- Time steps as rows (1:, 2a:, 2b:, 3:...)
- Gate labels in boxes at operation sites
- Fixed-width columns for alignment

Stochastic operations (apply_with_prob!) show ALL outcomes as separate rows,
making the circuit structure visible regardless of which branch would be selected.

# Arguments
- `circuit::Circuit`: Circuit to visualize
- `seed::Int`: Kept for backward compatibility; visualization always shows the circuit template
- `io::IO`: Output stream (default: stdout)
- `unicode::Bool`: Use Unicode box-drawing characters (default: true)

# Character Sets
- Unicode mode (default): Uses `─` (wire), `┤` (left box), `├` (right box)
- ASCII mode: Uses `-' (wire), `|` (both box edges)

# Layout Algorithm
1. Builds circuit template from `circuit.operations` directly (all outcomes shown)
2. Builds row list handling:
   - Empty steps → one wire-only row
   - Single op → one row with no letter suffix
   - Multiple ops → lettered sub-rows (a, b, c...)
3. Calculates fixed column width based on longest gate label (+2 for box chars)
4. Renders header row with qubit labels (e.g., "q1", "q2", "q3", "q4")
5. Renders time step rows with gate boxes or wire segments

# Multi-Qubit Gates
For gates spanning multiple sites (e.g., CZ on sites [2, 3]):
- Gate label appears ONCE in a box on the minimum site
- Other sites show continuation boxes (box edges without label)

# Examples
```julia
# Basic usage
circuit = Circuit(L=4, bc=:periodic, n_steps=4) do c
    apply!(c, Reset(), StaircaseRight(1))
end
print_circuit(circuit)

# Output to file
open("circuit.txt", "w") do io
    print_circuit(io, circuit)
end

# ASCII mode (no Unicode)
print_circuit(circuit; unicode=false)
```

# See Also
- `expand_circuit`: Get a concrete stochastic realization
- `ExpandedOp`: Concrete operation representation
"""
function print_circuit(io::IO, circuit::Circuit; seed::Int=0, unicode::Bool=true)
    # seed parameter kept for backward compatibility; visualization always shows circuit template
    # Character sets
    WIRE = unicode ? '─' : '-'
    LEFT_BOX = unicode ? '┤' : '|'
    RIGHT_BOX = unicode ? '├' : '|'
    
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
    
    # 1. Build circuit template groups (ALL outcomes shown unconditionally)
    expanded = build_template_groups_ascii(circuit)
    
    # 2. Build row list: (step_idx, substep_letter, ops_list)
    # ops_list is a Vector{ExpandedOp} of gates rendered on the same row
    rows = []
    for (step_idx, step_groups) in enumerate(expanded)
        if isempty(step_groups)
            push!(rows, (step_idx, "", ExpandedOp[]))
        else
            # Build batches: each batch is a set of ops on the same visual row.
            # Within a group (same apply! call), non-overlapping ops share a row.
            # Different groups always get separate rows.
            batches = Vector{ExpandedOp}[]
            for group_ops in step_groups
                if isempty(group_ops)
                    continue
                elseif !any_ops_overlap(group_ops)
                    push!(batches, group_ops)
                else
                    for op in group_ops
                        push!(batches, [op])
                    end
                end
            end
            
            if isempty(batches)
                push!(rows, (step_idx, "", ExpandedOp[]))
            elseif length(batches) == 1
                push!(rows, (step_idx, "", batches[1]))
            else
                for (batch_idx, batch) in enumerate(batches)
                    letter = string(Char('a' + batch_idx - 1))
                    push!(rows, (step_idx, letter, batch))
                end
            end
        end
    end
    
    # 3. Calculate fixed column width
    max_label_len = 1  # Minimum width
    for (_, _, ops) in rows
        for op in ops
            max_label_len = max(max_label_len, length(op.label))
        end
    end
    COL_WIDTH = max_label_len + 2  # +2 for box characters
    
    # 4. Print header
    println(io, "Circuit (L=$(circuit.L), bc=$(circuit.bc), seed=$seed)")
    println(io)
    
    # Calculate row label width (for alignment)
    max_row_label_len = 0
    for (step, letter, _) in rows
        label = letter == "" ? "$(step):" : "$(step)$(letter):"
        max_row_label_len = max(max_row_label_len, length(label))
    end
    ROW_LABEL_WIDTH = max(max_row_label_len + 2, 5)  # +2 for padding, min 5
    
    # Qubit header row (q1, q2, q3...)
    print(io, lpad("", ROW_LABEL_WIDTH))  # Empty space for row label column
    for q in 1:circuit.L
        print(io, lpad("q$q", COL_WIDTH))
    end
    println(io)
    
    # 5. Print time step rows
    for (step, letter, ops) in rows
        # Row label (step number with optional letter)
        row_label = letter == "" ? "$(step):" : "$(step)$(letter):"
        print(io, lpad(row_label, ROW_LABEL_WIDTH - 1), " ")
        
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
    print_circuit(circuit::Circuit; seed::Int=0, io::IO=stdout, unicode::Bool=true)

Backward-compatible keyword-argument form. Calls `print_circuit(io, circuit; ...)`.
"""
function print_circuit(circuit::Circuit; seed::Int=0, io::IO=stdout, unicode::Bool=true)
    print_circuit(io, circuit; seed=seed, unicode=unicode)
end
