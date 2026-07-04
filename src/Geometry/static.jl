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

Geometry for bricklayer gate application pattern.

Nearest-neighbor (NN) modes:
- `:odd` parity → pairs (1,2), (3,4), (5,6), ...
- `:even` parity → pairs (2,3), (4,5), ... plus (L,1) for PBC
- `:nn` parity → ALL NN pairs (combines :odd + :even)

Next-nearest-neighbor (NNN) modes (4 sublayers covering all 12 NNN pairs for L=12):
- `:nnn_odd_1` parity → pairs (1,3), (5,7), (9,11), ... (stride 4, offset 1)
- `:nnn_odd_2` parity → pairs (3,5), (7,9), (11,1), ... (stride 4, offset 3, PBC wrap)
- `:nnn_even_1` parity → pairs (2,4), (6,8), (10,12), ... (stride 4, offset 2)
- `:nnn_even_2` parity → pairs (4,6), (8,10), (12,2), ... (stride 4, offset 4, PBC wrap)
- `:nnn` parity → ALL NNN pairs (combines all 4 sublayers)

apply! loops internally over all pairs.
"""
struct Bricklayer <: AbstractGeometry
    parity::Symbol
    
    function Bricklayer(parity::Symbol)
        parity in (:odd, :even, :nn, :nnn, :nnn_odd_1, :nnn_odd_2, :nnn_even_1, :nnn_even_2) || throw(ArgumentError("Bricklayer parity must be :odd, :even, :nn, :nnn, :nnn_odd_1, :nnn_odd_2, :nnn_even_1, or :nnn_even_2, got $parity"))
        new(parity)
    end
end

"""
    get_pairs(geo::Bricklayer, state) -> Vector{Tuple{Int,Int}}

Get all pairs for bricklayer pattern. Returns pairs of physical sites.

Legacy name — delegates to the canonical `elements(geo, L, bc)` (see
`Geometry/elements.jl`); enumeration order is identical (bit-for-bit
API contract).
"""
function get_pairs(geo::Bricklayer, state)
    return [(e[1], e[2]) for e in elements(geo, state.L, state.bc)]
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
