# === Staircase Geometry Types ===
# Geometries with internal state (mutable pointer)

"""
    AbstractStaircase <: AbstractGeometry

Base type for staircase geometries with internal pointer.
"""
abstract type AbstractStaircase <: AbstractGeometry end

"""
    StaircaseRight(start_position::Int)

Staircase that moves right: applies at (pos, pos+1), then advances pos.
At pos=L (PBC), pair is (L, 1), then wraps to pos=1.
For OBC, stops at L-1 (pair is (L-1, L)).
"""
mutable struct StaircaseRight <: AbstractStaircase
    _position::Int  # internal, use current_position() to read
    
    StaircaseRight(start::Int) = new(start)
end

"""
    StaircaseLeft(start_position::Int)

Staircase that moves left: applies at (pos, pos+1), then decrements pos.
At pos=1 (PBC), pair is (1, 2), then wraps to pos=L.
For OBC, wraps to L-1 (pair is (L-1, L)).
"""
mutable struct StaircaseLeft <: AbstractStaircase
    _position::Int  # internal, use current_position() to read
    
    StaircaseLeft(start::Int) = new(start)
end

"""
    current_position(geo::AbstractStaircase) -> Int

Get the current position of the staircase (READ-ONLY accessor).
"""
current_position(geo::AbstractStaircase) = geo._position

"""
    get_sites(geo::AbstractStaircase, state) -> Vector{Int}

Get current pair of physical sites for the staircase.
Returns [pos, pos+1] or [L, 1] for PBC wrap.
"""
function get_sites(geo::AbstractStaircase, state)
    pos = geo._position
    L = state.L
    second = (pos == L && state.bc == :periodic) ? 1 : pos + 1
    return [pos, second]
end

"""
    advance!(geo::StaircaseRight, L::Int, bc::Symbol)

Advance staircase right by one position. Internal use by apply!.
- StaircaseRight: pos += 1, wraps L → 1 (PBC) or L-1 → 1 (OBC)
"""
function advance!(geo::StaircaseRight, L::Int, bc::Symbol)
    if bc == :periodic
        # PBC: position cycles 1 → 2 → ... → L → 1
        geo._position = (geo._position % L) + 1
    else
        # OBC: position cycles 1 → 2 → ... → L-1 → 1 (can't apply at L since no L+1)
        max_pos = L - 1
        geo._position = (geo._position % max_pos) + 1
    end
end

"""
    advance!(geo::StaircaseLeft, L::Int, bc::Symbol)

Advance staircase left by one position. Internal use by apply!.
- StaircaseLeft: pos -= 1, wraps 1 → L (PBC) or 1 → L-1 (OBC)
"""
function advance!(geo::StaircaseLeft, L::Int, bc::Symbol)
    if bc == :periodic
        # PBC: position cycles L → L-1 → ... → 1 → L
        geo._position = geo._position == 1 ? L : geo._position - 1
    else
        # OBC: position cycles L-1 → L-2 → ... → 1 → L-1
        max_pos = L - 1
        geo._position = geo._position == 1 ? max_pos : geo._position - 1
    end
end
