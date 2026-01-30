# === ASCII Circuit Visualization ===

"""
    print_circuit(circuit::Circuit; seed::Int=0, io::IO=stdout, unicode::Bool=true)

Print an ASCII visualization of a circuit showing gate placements on qubit wires.

Renders the circuit as a grid with:
- Step numbers at the top (with letter suffixes for multi-op steps)
- Qubit wires running horizontally
- Gate labels in boxes at operation sites
- Fixed-width columns for alignment

# Arguments
- `circuit::Circuit`: Circuit to visualize
- `seed::Int`: Random seed for stochastic branch selection (default: 0)
- `io::IO`: Output stream (default: stdout)
- `unicode::Bool`: Use Unicode box-drawing characters (default: true)

# Character Sets
- Unicode mode (default): Uses `─` (wire), `┤` (left box), `├` (right box)
- ASCII mode: Uses `-` (wire), `|` (both box edges)

# Layout Algorithm
1. Expands circuit using `expand_circuit(circuit; seed=seed)` to get concrete operations
2. Builds column list handling:
   - Empty steps → one wire-only column
   - Single op → one column with no letter suffix
   - Multiple ops → lettered sub-columns (a, b, c...)
3. Calculates fixed column width based on longest gate label (+2 for box chars)
4. Renders header row with step numbers (e.g., "1", "2a", "2b", "3")
5. Renders qubit rows with gate boxes or wire segments

# Empty Steps
Steps with no operations (do-nothing branch selected) still render as one column
showing only wire segments.

# Multi-Qubit Gates
For gates spanning multiple sites (e.g., CZ on sites [2, 3]):
- Gate label appears ONCE in a box on the minimum site
- Other sites show continuation boxes (box edges without label)
- No vertical connectors drawn (Phase 1 simplification)

# Examples
```julia
# Basic usage
circuit = Circuit(L=4, bc=:periodic, n_steps=4) do c
    apply!(c, Reset(), StaircaseRight(1))
end
print_circuit(circuit; seed=0)

# Output to file
open("circuit.txt", "w") do io
    print_circuit(circuit; seed=0, io=io)
end

# ASCII mode (no Unicode)
print_circuit(circuit; seed=0, unicode=false)
```

# Example Output
```
Circuit (L=4, bc=periodic, seed=0)

Step:      1     2     3     4
q1:   ┤Rst ├────────────┤Haar├
q2:   ──────┤Rst ├────────────
q3:   ────────────┤Rst ├──────
q4:   ┤Haar├────────────┤Rst ├
```

# See Also
- `expand_circuit`: Get concrete operations from symbolic circuit
- `ExpandedOp`: Concrete operation representation
"""
function print_circuit(circuit::Circuit; seed::Int=0, io::IO=stdout, unicode::Bool=true)
    # Character sets
    WIRE = unicode ? '─' : '-'
    LEFT_BOX = unicode ? '┤' : '|'
    RIGHT_BOX = unicode ? '├' : '|'
    
    # 1. Expand circuit to get concrete operations per step
    expanded = expand_circuit(circuit; seed=seed)  # Vector{Vector{ExpandedOp}}
    
    # 2. Build column list: (step_idx, substep_letter, op_or_nothing)
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
    
    # 3. Calculate fixed column width
    max_label_len = 1  # Minimum width
    for (_, _, op) in columns
        if op !== nothing
            max_label_len = max(max_label_len, length(op.label))
        end
    end
    COL_WIDTH = max_label_len + 2  # +2 for box characters
    
    # 4. Print header
    println(io, "Circuit (L=$(circuit.L), bc=$(circuit.bc), seed=$seed)")
    println(io)
    
    # Step header row
    print(io, "Step: ")
    for (step, letter, _) in columns
        header = letter == "" ? string(step) : "$(step)$(letter)"
        print(io, lpad(header, COL_WIDTH))
    end
    println(io)
    
    # 5. Print qubit rows
    for q in 1:circuit.L
        print(io, "q$q:   ")
        for (_, _, op) in columns
            if op !== nothing && q in op.sites
                if length(op.sites) == 1
                    # Single-qubit gate - render box with label as before
                    label = op.label
                    padding = COL_WIDTH - length(label) - 2  # -2 for box chars
                    left_pad = padding ÷ 2
                    right_pad = padding - left_pad
                    print(io, LEFT_BOX, repeat(WIRE, left_pad), label, repeat(WIRE, right_pad), RIGHT_BOX)
                else
                    # Multi-qubit gate - spanning box logic
                    min_site = minimum(op.sites)
                    if q == min_site
                        # First qubit in the span - show label
                        label = op.label
                        padding = COL_WIDTH - length(label) - 2  # -2 for box chars
                        left_pad = padding ÷ 2
                        right_pad = padding - left_pad
                        print(io, LEFT_BOX, repeat(WIRE, left_pad), label, repeat(WIRE, right_pad), RIGHT_BOX)
                    else
                        # Continuation qubit - show box without label
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
