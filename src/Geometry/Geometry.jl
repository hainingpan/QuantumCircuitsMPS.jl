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
    AbstractGeometry

Abstract base type for all geometry specifications — the "where" of a gate
application (`apply!(state, gate, geometry)`).

Geometries fall into two families, reported by the `is_broadcast(geo)` trait:

- **Broadcast** ("distribution") geometries expand to `K ≥ 1` independent
  elements, each receiving its own gate application (and, inside
  `apply_with_prob!`, its own coin): `AllSites`, `Bricklayer`, `EachSite`.
- **Set** ("region") geometries denote ONE region of sites, a single
  element: `SingleSite`, `AdjacentPair`, `Sites`, `StaircaseLeft`/
  `StaircaseRight`, `Pointer`.

The canonical enumeration for either family is
`elements(geo, L, bc) -> Vector{Vector{Int}}` (physical site indices).
Dynamic geometries (staircases, `Pointer`) are MUTABLE — staircases advance
after each application, `Pointer` moves only via `move!`.

Geometries always speak PHYSICAL site indices; backends translate to their
internal (RAM) indexing via `state.phy_ram`.
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
