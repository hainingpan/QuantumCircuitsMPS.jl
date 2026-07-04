# === Canonical Element Enumeration (v0.1 API) ===
# Single source of truth for geometry → element expansion.
#
# Vocabulary (v0.1 API contract):
# - BROADCAST geometries ("distribution"): expand to K ≥ 1 independent
#   elements, each receiving its own gate application (and, in stochastic
#   groups, its own coin). Types: AllSites, Bricklayer, EachSite.
# - SET geometries ("region"): denote ONE region of sites — a single
#   element. Types: SingleSite, AdjacentPair, Sites, StaircaseLeft/Right,
#   Pointer.
#
# The enumeration ORDER returned by `elements` is a documented API contract
# (RNG streams consume coins in element order); it must never change.

"""
    EachSite(sites)

Broadcast geometry: apply a single-site gate independently at each site in
`sites` (a range or collection of Ints, kept in the given order).

Expands to `[[i] for i in sites]` — one element per site. Example: SRN bulk
eligibility is `EachSite(2:L-1)`.

See also [`AllSites`](@ref) (all L sites) and [`Sites`](@ref) (one multi-site
region, NOT a broadcast).
"""
struct EachSite <: AbstractGeometry
    sites::Vector{Int}

    function EachSite(sites)
        v = collect(Int, sites)
        isempty(v) && throw(ArgumentError("EachSite requires a non-empty site collection"))
        all(>=(1), v) || throw(ArgumentError("EachSite sites must be >= 1, got $v"))
        new(v)
    end
end

"""
    Sites(sites)

Set geometry: ONE region made of the given sites (a range or collection of
Ints, kept in the given order). A gate applied to `Sites(c)` must have
`support(gate) == length(c)` (see [`validate_support`](@ref)).

Expands to a single element `[collect(sites)]`. For applying a gate
independently at each site, use [`EachSite`](@ref) instead.
"""
struct Sites <: AbstractGeometry
    sites::Vector{Int}

    function Sites(sites)
        v = collect(Int, sites)
        isempty(v) && throw(ArgumentError("Sites requires a non-empty site collection"))
        all(>=(1), v) || throw(ArgumentError("Sites sites must be >= 1, got $v"))
        new(v)
    end
end

get_sites(geo::Sites, state) = copy(geo.sites)

"""
    is_broadcast(geo::AbstractGeometry) -> Bool

Trait: `true` for broadcast ("distribution") geometries that expand to
multiple independent elements (`AllSites`, `Bricklayer`, `EachSite`);
`false` for set ("region") geometries that denote a single region
(`SingleSite`, `AdjacentPair`, `Sites`, `StaircaseLeft`/`StaircaseRight`,
`Pointer`).
"""
is_broadcast(::AbstractGeometry) = false
is_broadcast(::AllSites) = true
is_broadcast(::Bricklayer) = true
is_broadcast(::EachSite) = true

"""
    elements(geo::AbstractGeometry, L::Int, bc::Symbol) -> Vector{Vector{Int}}

Canonical element enumeration for a geometry: each inner vector is the sites
for one gate application. This is the SINGLE source of truth consolidating
the former `get_pairs` / `get_compound_elements` duplicates.

Broadcast geometries return K ≥ 1 elements in their documented canonical
order (API contract — RNG coin consumption follows this order):
- `AllSites()` → `[[1], [2], ..., [L]]`
- `EachSite(c)` → `[[i] for i in c]` (collection order)
- `Bricklayer(parity)` → pairs exactly as documented in the README parity
  table (e.g. `:odd` → `[[1,2],[3,4],...]`; `:even` → `[[2,3],...,[L,1]]`
  for PBC; `:nn` = `:odd` then `:even`; `:nnn` = sublayers 1,2,3,4)

Set geometries return a single element `[[sites...]]`:
- `SingleSite(i)` → `[[i]]`
- `AdjacentPair(i)` → `[[i, i+1]]` (PBC wrap at L)
- `Sites(c)` → `[collect(c)]`
- `StaircaseLeft/Right` → `[[pos, pos+range]]` at the CURRENT position
  (PBC wrap via `mod1`; OBC out-of-bounds throws `ArgumentError`)
- `Pointer` → `[[pos, pos+1]]` at the current position (PBC wrap at L)
"""
function elements end

# --- Broadcast geometries ---

function elements(geo::Bricklayer, L::Int, bc::Symbol)
    # CANONICAL enumeration (moved verbatim from get_compound_elements).
    # Order is an API contract — do not change.
    pairs = Tuple{Int,Int}[]
    if geo.parity == :odd
        # NN odd pairs: (1,2), (3,4), (5,6), ...
        for i in 1:2:L-1
            push!(pairs, (i, i+1))
        end
    elseif geo.parity == :even
        # NN even pairs: (2,3), (4,5), ...
        for i in 2:2:L-1
            push!(pairs, (i, i+1))
        end
        # For PBC, also include (L, 1)
        if bc == :periodic
            push!(pairs, (L, 1))
        end
    elseif geo.parity == :nn
        # All NN pairs: combines :odd and :even
        # For L=12 periodic: 12 pairs covering all bonds
        for i in 1:2:L-1  # Odd pairs: (1,2), (3,4), ...
            push!(pairs, (i, i+1))
        end
        for i in 2:2:L-1  # Even pairs: (2,3), (4,5), ...
            push!(pairs, (i, i+1))
        end
        if bc == :periodic
            push!(pairs, (L, 1))  # Wrap: (12,1) for L=12
        end
    elseif geo.parity == :nnn
        # All NNN pairs: combines 4 sublayers
        # For L=12 periodic: 12 pairs covering all NNN bonds
        # Sublayer 1: (1,3), (5,7), (9,11)
        for i in 1:4:L-2
            push!(pairs, (i, i+2))
        end
        # Sublayer 2: (3,5), (7,9)
        for i in 3:4:L-2
            push!(pairs, (i, i+2))
        end
        if bc == :periodic && L >= 4
            push!(pairs, (L-1, 1))  # (11,1) for L=12
        end
        # Sublayer 3: (2,4), (6,8), (10,12)
        for i in 2:4:L-2
            push!(pairs, (i, i+2))
        end
        # Sublayer 4: (4,6), (8,10)
        for i in 4:4:L-2
            push!(pairs, (i, i+2))
        end
        if bc == :periodic && L >= 4
            push!(pairs, (L, 2))  # (12,2) for L=12
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
    return [[p1, p2] for (p1, p2) in pairs]
end

function elements(geo::AllSites, L::Int, bc::Symbol)
    return [[site] for site in 1:L]
end

function elements(geo::EachSite, L::Int, bc::Symbol)
    _check_sites_in_range(geo.sites, L, "EachSite")
    return [[site] for site in geo.sites]
end

# --- Set geometries: single element ---

elements(geo::SingleSite, L::Int, bc::Symbol) = [[geo.site]]

function elements(geo::AdjacentPair, L::Int, bc::Symbol)
    second = (geo.first == L && bc == :periodic) ? 1 : geo.first + 1
    return [[geo.first, second]]
end

function elements(geo::Sites, L::Int, bc::Symbol)
    _check_sites_in_range(geo.sites, L, "Sites")
    return [copy(geo.sites)]
end

function elements(geo::AbstractStaircase, L::Int, bc::Symbol)
    # Current-position resolution (mirrors get_sites(geo, state))
    pos = geo._position
    range = geo.range
    if bc == :periodic
        second = mod1(pos + range, L)
    else
        second = pos + range
        if second > L
            throw(ArgumentError(
                "Staircase at position $pos with range=$range exceeds system size L=$L (OBC)"
            ))
        end
    end
    return [[pos, second]]
end

function elements(geo::Pointer, L::Int, bc::Symbol)
    # Current-position resolution (mirrors get_sites(geo, state))
    pos = geo._position
    second = (pos == L && bc == :periodic) ? 1 : pos + 1
    return [[pos, second]]
end

function _check_sites_in_range(sites::Vector{Int}, L::Int, name::String)
    bad = filter(s -> s < 1 || s > L, sites)
    isempty(bad) || throw(ArgumentError(
        "$name contains sites $bad outside the system range 1:$L"
    ))
    return nothing
end

"""
    element_count(geo::AbstractGeometry, L::Int, bc::Symbol) -> Int

Number of elements (K) that `geo` expands to via [`elements`](@ref).
Broadcast geometries give K ≥ 1; set geometries always give 1.
Used by builder validation (equal-K rule across stochastic outcomes).
"""
element_count(geo::AbstractGeometry, L::Int, bc::Symbol) = length(elements(geo, L, bc))

"""
    validate_support(gate::AbstractGate, geo::Sites, L::Int, bc::Symbol)

Validate that `support(gate)` equals the region size of a `Sites` geometry;
throws `ArgumentError` naming both numbers on mismatch. For all other
geometries this is a no-op — their regions are resolved from the gate
support itself (staircases) or are fixed-size by construction.
"""
function validate_support(gate::AbstractGate, geo::Sites, L::Int, bc::Symbol)
    n = support(gate)
    m = length(geo.sites)
    n == m || throw(ArgumentError(
        "Gate support ($n site(s)) does not match Sites region size ($m site(s)): " *
        "$(typeof(gate)) cannot be applied to Sites($(geo.sites))"
    ))
    return nothing
end

validate_support(gate::AbstractGate, geo::AbstractGeometry, L::Int, bc::Symbol) = nothing
