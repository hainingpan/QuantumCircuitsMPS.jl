# === Compound Geometry Helpers (legacy names) ===
# The canonical enumeration lives in elements.jl (`elements(geo, L, bc)`).
# These functions are kept as thin delegates until Tasks 9/15 rewire the
# engine/visualization call sites, after which they can be removed.

"""
    is_compound_geometry(geo::AbstractGeometry) -> Bool

Check if geometry requires element-by-element iteration.

Compound geometries (Bricklayer, AllSites, EachSite) need to be expanded into
multiple individual gate applications, one for each element/site pair.

Equivalent to the v0.1 trait [`is_broadcast`](@ref); kept as a legacy alias
until engine call sites are rewired.
"""
is_compound_geometry(::Bricklayer) = true
is_compound_geometry(::AllSites) = true
is_compound_geometry(::EachSite) = true
is_compound_geometry(::AbstractGeometry) = false

"""
    get_compound_elements(geo::AbstractGeometry, L::Int, bc::Symbol) -> Vector{Vector{Int}}

Get elements for compound geometry iteration.

Legacy name — delegates to the canonical [`elements`](@ref); enumeration
order is identical (bit-for-bit API contract).

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
function get_compound_elements(geo::Union{Bricklayer, AllSites, EachSite}, L::Int, bc::Symbol)
    elements(geo, L, bc)
end
