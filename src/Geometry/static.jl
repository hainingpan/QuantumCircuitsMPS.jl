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

Next-nearest-neighbor (NNN) modes (4 sublayers covering all 12 NNN pairs for L=12):
- `:nnn_odd_1` parity → pairs (1,3), (5,7), (9,11), ... (stride 4, offset 1)
- `:nnn_odd_2` parity → pairs (3,5), (7,9), (11,1), ... (stride 4, offset 3, PBC wrap)
- `:nnn_even_1` parity → pairs (2,4), (6,8), (10,12), ... (stride 4, offset 2)
- `:nnn_even_2` parity → pairs (4,6), (8,10), (12,2), ... (stride 4, offset 4, PBC wrap)

apply! loops internally over all pairs.
"""
struct Bricklayer <: AbstractGeometry
    parity::Symbol
    
    function Bricklayer(parity::Symbol)
        parity in (:odd, :even, :nnn_odd_1, :nnn_odd_2, :nnn_even_1, :nnn_even_2) || throw(ArgumentError("Bricklayer parity must be :odd, :even, :nnn_odd_1, :nnn_odd_2, :nnn_even_1, or :nnn_even_2, got $parity"))
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
    elseif geo.parity == :even
        # Even pairs: (2,3), (4,5), ...
        for i in 2:2:L-1
            push!(pairs, (i, i+1))
        end
        # For PBC, also include (L, 1)
        if bc == :periodic
            push!(pairs, (L, 1))
        end
    elseif geo.parity == :nnn_odd_1
        # NNN odd sublayer 1: (1,3), (5,7), (9,11), ... (stride 4, offset 1)
        for i in 1:4:L-2
            push!(pairs, (i, i+2))
        end
    elseif geo.parity == :nnn_odd_2
        # NNN odd sublayer 2: (3,5), (7,9), (11,1), ... (stride 4, offset 3)
        for i in 3:4:L-2
            push!(pairs, (i, i+2))
        end
        if bc == :periodic && L >= 4
            push!(pairs, (L-1, 1))  # Wrap: (11,1) for L=12
        end
    elseif geo.parity == :nnn_even_1
        # NNN even sublayer 1: (2,4), (6,8), (10,12), ... (stride 4, offset 2)
        for i in 2:4:L-2
            push!(pairs, (i, i+2))
        end
    elseif geo.parity == :nnn_even_2
        # NNN even sublayer 2: (4,6), (8,10), (12,2), ... (stride 4, offset 4)
        for i in 4:4:L-2
            push!(pairs, (i, i+2))
        end
        if bc == :periodic && L >= 4
            push!(pairs, (L, 2))  # Wrap: (12,2) for L=12
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
