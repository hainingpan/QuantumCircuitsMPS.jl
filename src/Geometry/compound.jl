# === Compound Geometry Helpers ===

"""
    is_compound_geometry(geo::AbstractGeometry) -> Bool

Check if geometry requires element-by-element iteration.

Compound geometries (Bricklayer, AllSites) need to be expanded into
multiple individual gate applications, one for each element/site pair.
"""
is_compound_geometry(::Bricklayer) = true
is_compound_geometry(::AllSites) = true
is_compound_geometry(::AbstractGeometry) = false

"""
    get_compound_elements(geo::AbstractGeometry, L::Int, bc::Symbol) -> Vector{Vector{Int}}

Get elements for compound geometry iteration.

Returns a vector of site vectors, where each inner vector represents the sites
for one gate application.

# Arguments
- `geo`: The geometry object (Bricklayer or AllSites)
- `L`: System size (number of sites)
- `bc`: Boundary condition (:open or :periodic)

# Returns
- `Vector{Vector{Int}}`: Each inner vector is the sites for one gate application

# Examples
```julia
# Bricklayer with odd parity on L=4 system
geo = Bricklayer(:odd)
get_compound_elements(geo, 4, :open)  # [[1, 2], [3, 4]]

# AllSites on L=3 system
geo = AllSites()
get_compound_elements(geo, 3, :open)  # [[1], [2], [3]]
```
"""
function get_compound_elements(geo::Bricklayer, L::Int, bc::Symbol)
    pairs = Tuple{Int,Int}[]
    if geo.parity == :odd
        for i in 1:2:L-1
            push!(pairs, (i, i+1))
        end
    else
        for i in 2:2:L-1
            push!(pairs, (i, i+1))
        end
        if bc == :periodic
            push!(pairs, (L, 1))
        end
    end
    return [[p1, p2] for (p1, p2) in pairs]
end

function get_compound_elements(geo::AllSites, L::Int, bc::Symbol)
    return [[site] for site in 1:L]
end
