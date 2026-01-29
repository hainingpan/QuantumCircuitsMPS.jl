# === Pure Site Computation Functions ===
# Pure functional versions of geometry site computation without mutation.
# These enable symbolic circuit expansion where step replaces mutable _position.

"""
    compute_site_staircase_right(start::Int, step::Int, L::Int, bc::Symbol) -> Int

Compute the position of a StaircaseRight geometry after `step` iterations.

# Arguments
- `start`: Starting position (1-indexed)
- `step`: Step number (1 = initial position, 2 = after first advance, etc.)
- `L`: System size (number of sites)
- `bc`: Boundary condition (`:periodic` or `:open`)

# Returns
- Position after (step-1) advances

# Wrapping behavior
- **PBC**: Position cycles `1 → 2 → ... → L → 1`
- **OBC**: Position cycles `1 → 2 → ... → (L-1) → 1`

# Example
```julia
# Start at position 3, system size 5, periodic BC
compute_site_staircase_right(3, 1, 5, :periodic)  # Returns 3 (initial)
compute_site_staircase_right(3, 2, 5, :periodic)  # Returns 4 (after 1 advance)
compute_site_staircase_right(3, 3, 5, :periodic)  # Returns 5 (after 2 advances)
compute_site_staircase_right(3, 4, 5, :periodic)  # Returns 1 (after 3 advances, wrapped)
```
"""
function compute_site_staircase_right(start::Int, step::Int, L::Int, bc::Symbol)
    # Validation
    step < 1 && throw(ArgumentError("step must be >= 1, got $step"))
    L < 2 && throw(ArgumentError("L must be >= 2 for staircase geometry, got $L"))
    bc ∉ [:periodic, :open] && throw(ArgumentError("bc must be :periodic or :open, got $bc"))
    (start < 1 || start > L) && throw(ArgumentError("start must be in range 1:$L, got $start"))
    
    # Compute position after (step-1) advances
    # step=1 means 0 advances (initial position)
    advances = step - 1
    
    if bc == :periodic
        # PBC: cycles over 1:L
        # Apply advances: each advance does pos = (pos % L) + 1
        pos = start
        for _ in 1:advances
            pos = (pos % L) + 1
        end
    else
        # OBC: cycles over 1:(L-1)
        # Apply advances: each advance does pos = (pos % (L-1)) + 1
        max_pos = L - 1
        pos = start
        for _ in 1:advances
            pos = (pos % max_pos) + 1
        end
    end
    
    return pos
end

"""
    compute_site_staircase_left(start::Int, step::Int, L::Int, bc::Symbol) -> Int

Compute the position of a StaircaseLeft geometry after `step` iterations.

# Arguments
- `start`: Starting position (1-indexed)
- `step`: Step number (1 = initial position, 2 = after first advance, etc.)
- `L`: System size (number of sites)
- `bc`: Boundary condition (`:periodic` or `:open`)

# Returns
- Position after (step-1) advances

# Wrapping behavior
- **PBC**: Position cycles `L → ... → 2 → 1 → L`
- **OBC**: Position cycles `(L-1) → ... → 2 → 1 → (L-1)`

# Example
```julia
# Start at position 3, system size 5, periodic BC
compute_site_staircase_left(3, 1, 5, :periodic)  # Returns 3 (initial)
compute_site_staircase_left(3, 2, 5, :periodic)  # Returns 2 (after 1 advance)
compute_site_staircase_left(3, 3, 5, :periodic)  # Returns 1 (after 2 advances)
compute_site_staircase_left(3, 4, 5, :periodic)  # Returns 5 (after 3 advances, wrapped)
```
"""
function compute_site_staircase_left(start::Int, step::Int, L::Int, bc::Symbol)
    # Validation
    step < 1 && throw(ArgumentError("step must be >= 1, got $step"))
    L < 2 && throw(ArgumentError("L must be >= 2 for staircase geometry, got $L"))
    bc ∉ [:periodic, :open] && throw(ArgumentError("bc must be :periodic or :open, got $bc"))
    (start < 1 || start > L) && throw(ArgumentError("start must be in range 1:$L, got $start"))
    
    # Compute position after (step-1) advances
    advances = step - 1
    
    if bc == :periodic
        # PBC: cycles over 1:L (backwards)
        # Apply advances: each advance does pos = (pos == 1 ? L : pos - 1)
        pos = start
        for _ in 1:advances
            pos = pos == 1 ? L : pos - 1
        end
    else
        # OBC: cycles over 1:(L-1) (backwards)
        max_pos = L - 1
        pos = start
        for _ in 1:advances
            pos = pos == 1 ? max_pos : pos - 1
        end
    end
    
    return pos
end

"""
    compute_pair_staircase(pos::Int, L::Int, bc::Symbol) -> Vector{Int}

Convert a single staircase position to an adjacent pair [pos, pos+1].

# Arguments
- `pos`: Position (1-indexed)
- `L`: System size (number of sites)
- `bc`: Boundary condition (`:periodic` or `:open`)

# Returns
- Two-element vector `[pos, second]` where second wraps at L→1 for PBC

# Validation
- For OBC, `pos` must be in range 1:(L-1) (cannot form pair at position L)
- For PBC, `pos` can be 1:L (position L pairs with 1)

# Example
```julia
compute_pair_staircase(3, 5, :periodic)  # Returns [3, 4]
compute_pair_staircase(5, 5, :periodic)  # Returns [5, 1] (wrap)
compute_pair_staircase(4, 5, :open)      # Returns [4, 5]
compute_pair_staircase(5, 5, :open)      # Throws error (no site 6)
```
"""
function compute_pair_staircase(pos::Int, L::Int, bc::Symbol)
    # Validation
    L < 2 && throw(ArgumentError("L must be >= 2 for staircase geometry, got $L"))
    bc ∉ [:periodic, :open] && throw(ArgumentError("bc must be :periodic or :open, got $bc"))
    (pos < 1 || pos > L) && throw(ArgumentError("pos must be in range 1:$L, got $pos"))
    
    # OBC-specific validation: cannot form pair at position L
    if bc == :open && pos == L
        throw(ArgumentError("Cannot form adjacent pair at position $pos with open boundary conditions (would require site $(L+1))"))
    end
    
    # Compute second site with PBC wrapping
    second = (pos == L && bc == :periodic) ? 1 : pos + 1
    
    return [pos, second]
end

"""
    compute_sites(geo::SingleSite, step::Int, L::Int, bc::Symbol) -> Vector{Int}

Compute sites for SingleSite geometry (always returns [geo.site]).

# Arguments
- `geo`: SingleSite geometry
- `step`: Step number (unused for static geometry)
- `L`: System size (unused for static geometry)
- `bc`: Boundary condition (unused for static geometry)

# Returns
- Single-element vector `[geo.site]`
"""
function compute_sites(geo::SingleSite, step::Int, L::Int, bc::Symbol)
    return [geo.site]
end

"""
    compute_sites(geo::AdjacentPair, step::Int, L::Int, bc::Symbol) -> Vector{Int}

Compute sites for AdjacentPair geometry.

# Arguments
- `geo`: AdjacentPair geometry
- `step`: Step number (unused for static geometry)
- `L`: System size
- `bc`: Boundary condition (`:periodic` or `:open`)

# Returns
- Two-element vector `[geo.first, second]` where second wraps at L→1 for PBC
"""
function compute_sites(geo::AdjacentPair, step::Int, L::Int, bc::Symbol)
    second = (geo.first == L && bc == :periodic) ? 1 : geo.first + 1
    return [geo.first, second]
end

"""
    compute_sites(geo::StaircaseRight, step::Int, L::Int, bc::Symbol, gate::AbstractGate) -> Vector{Int}

Compute sites for StaircaseRight geometry based on gate support.

# Arguments
- `geo`: StaircaseRight geometry
- `step`: Step number
- `L`: System size
- `bc`: Boundary condition (`:periodic` or `:open`)
- `gate`: Gate to determine support (1-site or 2-site)

# Returns
- For single-site gates (support == 1): `[pos]`
- For two-site gates (support == 2): `[pos, pos+1]` with PBC wrapping
"""
function compute_sites(geo::StaircaseRight, step::Int, L::Int, bc::Symbol, gate::AbstractGate)
    pos = compute_site_staircase_right(geo._position, step, L, bc)
    if support(gate) == 1
        return [pos]
    else  # support(gate) == 2
        return compute_pair_staircase(pos, L, bc)
    end
end

"""
    compute_sites(geo::StaircaseLeft, step::Int, L::Int, bc::Symbol, gate::AbstractGate) -> Vector{Int}

Compute sites for StaircaseLeft geometry based on gate support.

# Arguments
- `geo`: StaircaseLeft geometry
- `step`: Step number
- `L`: System size
- `bc`: Boundary condition (`:periodic` or `:open`)
- `gate`: Gate to determine support (1-site or 2-site)

# Returns
- For single-site gates (support == 1): `[pos]`
- For two-site gates (support == 2): `[pos, pos+1]` with PBC wrapping
"""
function compute_sites(geo::StaircaseLeft, step::Int, L::Int, bc::Symbol, gate::AbstractGate)
    pos = compute_site_staircase_left(geo._position, step, L, bc)
    if support(gate) == 1
        return [pos]
    else  # support(gate) == 2
        return compute_pair_staircase(pos, L, bc)
    end
end
