# === Static Geometry Types ===
# Geometries where sites are known at construction time

"""
    SingleSite(site::Int)

Geometry specifying a single physical site.
Used for single-qubit gates like PauliX, Projection.
"""
struct SingleSite <: AbstractGeometry
    site::Int
end

get_sites(geo::SingleSite, state) = [geo.site]

"""
    AdjacentPair(first::Int)

Geometry specifying an adjacent pair of physical sites: (first, first+1).
For PBC, wraps: (L, 1) when first=L.
"""
struct AdjacentPair <: AbstractGeometry
    first::Int
end

function get_sites(geo::AdjacentPair, state)
    L = state.L
    second = (geo.first == L && state.bc == :periodic) ? 1 : geo.first + 1
    return [geo.first, second]
end

"""
    Bricklayer(parity::Symbol)

Geometry for bricklayer (even/odd) gate application pattern.
- `:odd` parity → pairs (1,2), (3,4), (5,6), ...
- `:even` parity → pairs (2,3), (4,5), ... plus (L,1) for PBC

apply! loops internally over all pairs.
"""
struct Bricklayer <: AbstractGeometry
    parity::Symbol
    
    function Bricklayer(parity::Symbol)
        parity in (:odd, :even) || throw(ArgumentError("Bricklayer parity must be :odd or :even, got $parity"))
        new(parity)
    end
end

"""
    get_pairs(geo::Bricklayer, state) -> Vector{Tuple{Int,Int}}

Get all pairs for bricklayer pattern. Returns pairs of physical sites.
"""
function get_pairs(geo::Bricklayer, state)
    L = state.L
    bc = state.bc
    pairs = Tuple{Int,Int}[]
    
    if geo.parity == :odd
        # Odd pairs: (1,2), (3,4), (5,6), ...
        for i in 1:2:L-1
            push!(pairs, (i, i+1))
        end
    else
        # Even pairs: (2,3), (4,5), ...
        for i in 2:2:L-1
            push!(pairs, (i, i+1))
        end
        # For PBC, also include (L, 1)
        if bc == :periodic
            push!(pairs, (L, 1))
        end
    end
    
    return pairs
end

"""
    AllSites

Geometry for applying single-site gates to all sites.
apply! loops internally over all L sites.
"""
struct AllSites <: AbstractGeometry end

"""
    get_all_sites(geo::AllSites, state) -> Vector{Int}

Get all physical sites (1:L).
"""
get_all_sites(geo::AllSites, state) = collect(1:state.L)
