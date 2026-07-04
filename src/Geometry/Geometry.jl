"""
Geometry types for specifying where gates are applied.

Provides abstractions for:
- Static geometries: SingleSite, AdjacentPair, Bricklayer, AllSites
- Dynamic geometries: StaircaseLeft, StaircaseRight (with internal pointer)
- v0.1 vocabulary: broadcast geometries (AllSites, Bricklayer, EachSite) vs
  set geometries (SingleSite, AdjacentPair, Sites, staircases, Pointer);
  canonical element enumeration via `elements(geo, L, bc)`
"""

"""
Abstract base type for all geometry specifications.
"""
abstract type AbstractGeometry end

"""
    get_sites(geo::AbstractGeometry, state) -> Vector{Int}

Get the physical sites for this geometry. Returns physical site indices.
For iterating geometries (Bricklayer, AllSites), returns the first/next set.
For staircases, returns current position pair.
"""
function get_sites end

# Include implementations
include("static.jl")
include("staircase.jl")
include("pointer.jl")
include("compute_sites.jl")
include("elements.jl")   # canonical elements() + EachSite/Sites + traits (needs types above)
include("compound.jl")   # legacy delegates to elements() (needs EachSite from elements.jl)
