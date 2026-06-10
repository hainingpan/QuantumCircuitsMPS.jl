"""
    pack_ops_into_layers(ops::Vector{ExpandedOp}) -> Vector{Vector{ExpandedOp}}

Greedily pack a flat list of expanded operations into non-overlapping layers.

Each layer contains operations that act on disjoint sets of qubits. Operations
are placed using a first-fit strategy: each op is assigned to the first existing
layer where it does not conflict with any already-placed op, or a new layer is
opened if no such layer exists.

Conflict detection uses set intersection on `op.sites`, so wrapped pairs like
`[8, 1]` are handled correctly.

# Arguments
- `ops`: Flat list of `ExpandedOp` values to pack (e.g., from `expand_circuit`).

# Returns
A `Vector{Vector{ExpandedOp}}` where each inner vector is one non-overlapping
layer. Returns an empty vector when `ops` is empty.

# Examples
```julia
# Bricklayer(:nn) on L=8 periodic → 2 layers of 4 ops each
ops = [ExpandedOp(1, HaarRandom(), [1,2], "Haar"),
       ExpandedOp(1, HaarRandom(), [3,4], "Haar"),
       ExpandedOp(1, HaarRandom(), [5,6], "Haar"),
       ExpandedOp(1, HaarRandom(), [7,8], "Haar"),
       ExpandedOp(1, HaarRandom(), [2,3], "Haar"),
       ExpandedOp(1, HaarRandom(), [4,5], "Haar"),
       ExpandedOp(1, HaarRandom(), [6,7], "Haar"),
       ExpandedOp(1, HaarRandom(), [8,1], "Haar")]
layers = pack_ops_into_layers(ops)
length(layers)       # 2
length(layers[1])    # 4
length(layers[2])    # 4
```
"""
function pack_ops_into_layers(ops::Vector{ExpandedOp})::Vector{Vector{ExpandedOp}}
    layers = Vector{Vector{ExpandedOp}}()
    occupied = Vector{Set{Int}}()  # sites occupied in each layer
    for op in ops
        placed = false
        for (i, layer_sites) in enumerate(occupied)
            if isempty(intersect(Set(op.sites), layer_sites))
                push!(layers[i], op)
                union!(layer_sites, op.sites)
                placed = true
                break
            end
        end
        if !placed
            push!(layers, [op])
            push!(occupied, Set(op.sites))
        end
    end
    return layers
end
