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

@doc raw"""
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

!!! warning "Odd L under periodic boundary conditions"
    An odd-length ring cannot be tiled by disjoint NN pairs. At odd `L` with
    `bc = :periodic`, no wrap pair is added to either single layer: `:odd`
    leaves site `L` unpaired and `:even` leaves site 1 unpaired, and the wrap
    bond `(L, 1)` is gated by NEITHER layer — an alternating `:odd`/`:even`
    brickwork circuit is effectively open across that bond. A one-time
    warning is emitted at circuit-build / `apply!` time (internal helper
    `_warn_bricklayer_odd_pbc`); double-check the intended pattern with
    `print_circuit`. `:nn` (ALL NN bonds, not a single layer) still
    enumerates all `L` ring bonds and does not warn.

!!! warning "NNN sublayers at L ≡ 2 (mod 4) under periodic boundary conditions"
    The NNN bonds of an even-`L` ring form two rings (odd sites and even
    sites) of length ``L/2``. For ``L \equiv 0 \pmod 4`` each splits into two
    disjoint pair layers, so the four sublayers are proper brickwork layers.
    For ``L \equiv 2 \pmod 4`` (`L = 6, 10, 14, ...`) ``L/2`` is odd and no
    such split exists: the wrap pair `(L-1, 1)` of `:nnn_odd_2` shares site
    `L-1` with its last bulk pair `(L-3, L-1)`, and the wrap pair `(L, 2)` of
    `:nnn_even_2` shares site `L` with `(L-2, L)`. The enumeration is kept
    (every NNN bond is still gated exactly once by `:nnn` / the four
    sublayers together), but the two gates sharing a site are applied
    sequentially in enumeration order, so such a sublayer is not a depth-1
    layer and the result depends on that order for non-commuting gates. A
    one-time warning is emitted at circuit-build / `apply!` time (same
    helper). `:nnn_odd_1`, `:nnn_even_1`, `:nnn`, and open boundaries are
    unaffected.
"""
struct Bricklayer <: AbstractGeometry
    parity::Symbol

    function Bricklayer(parity::Symbol)
        parity in
        (:odd, :even, :nn, :nnn, :nnn_odd_1, :nnn_odd_2, :nnn_even_1, :nnn_even_2) ||
            throw(ArgumentError("Bricklayer parity must be :odd, :even, :nn, :nnn, :nnn_odd_1, :nnn_odd_2, :nnn_even_1, or :nnn_even_2, got $parity"))
        new(parity)
    end
end

"""
    _warn_bricklayer_odd_pbc(geo::Bricklayer, L::Int, bc::Symbol)

Emit a one-time warning (once per `(parity, L)` combination per session, via
`maxlog=1` with a per-combination log `_id`) when a single brickwork layer
under periodic boundary conditions sits on an odd-length ring and therefore
is not a disjoint pair layer. Two cases:

- `:odd` / `:even` with odd `L`. An odd ring has no valid brickwork tiling:
  the layer leaves one site unpaired (`:odd` → site `L`, `:even` → site 1 —
  no wrap pair is added, see `elements(::Bricklayer, ...)`), and the wrap
  bond `(L, 1)` is gated by neither single layer, so an alternating
  `:odd`/`:even` circuit is effectively open across that bond.
- `:nnn_odd_2` / `:nnn_even_2` with `L ≥ 6` and `L % 4 == 2`. The NNN bonds
  of an even ring form two rings of length `L/2` (odd sites, even sites);
  when `L/2` is odd neither ring splits into two disjoint pair layers, and
  the sublayer's wrap pair (`(L-1, 1)` resp. `(L, 2)`) shares its first site
  with the last bulk pair (`(L-3, L-1)` resp. `(L-2, L)`). The two gates on
  that site are applied sequentially in enumeration order, so the sublayer
  is not a depth-1 layer. Bond coverage is unaffected: `:nnn` still gates
  every NNN bond exactly once.

Enumeration behavior is NOT changed by this helper — it only warns.

Called from the circuit-builder recording path (`apply!(builder, ...)`,
`apply_with_prob!(builder; ...)` — fires at circuit-definition time) and the
immediate-mode dispatch path (`_apply_dispatch!(state, gate, ::Bricklayer)`).
Deliberately NOT called inside `elements()` itself, which sits in
performance-critical loops (benchmarks, per-element expansion).

`:nn` and `:nnn` (ALL NN / NNN bonds — bond enumerations, not single layers)
and the wrap-free sublayers `:nnn_odd_1` / `:nnn_even_1` are exempt. At odd
`L` the NNN sublayers are left as they are (odd-`L` NNN coverage policy is a
separate open question).
"""
function _warn_bricklayer_odd_pbc(geo::Bricklayer, L::Int, bc::Symbol)
    bc == :periodic || return nothing
    if isodd(L) && geo.parity in (:odd, :even)
        unpaired = geo.parity == :even ? 1 : L
        msg = "Bricklayer(:$(geo.parity)) with odd L=$L under periodic boundary " *
              "conditions is not a valid brickwork tiling: an odd-length ring cannot " *
              "be partitioned into disjoint nearest-neighbor pairs. This layer leaves " *
              "site $unpaired unpaired (no gate acts on it), and the wrap bond ($L,1) " *
              "is gated by NEITHER the :odd nor the :even layer — an alternating " *
              ":odd/:even brickwork circuit is effectively OPEN across that bond. " *
              "Double-check the intended pattern with print_circuit(circuit) " *
              "(or plot_circuit if Luxor is loaded)."
        @warn msg maxlog=1 _id=Symbol(:bricklayer_odd_pbc_, geo.parity, :_, L)
    elseif L >= 6 && L % 4 == 2 && geo.parity in (:nnn_odd_2, :nnn_even_2)
        # The NNN bonds of an even ring form two rings (odd sites, even sites)
        # of length L/2. At L ≡ 2 (mod 4) that length is odd, so neither ring
        # splits into two disjoint pair layers: the stride-4 wrap pair of this
        # sublayer shares its first site with the sublayer's last bulk pair
        # (see elements(::Bricklayer, ...)). L=2 has no pairs at all.
        shared = geo.parity == :nnn_odd_2 ? L - 1 : L
        wrap_to = geo.parity == :nnn_odd_2 ? 1 : 2
        msg = "Bricklayer(:$(geo.parity)) with L=$L under periodic boundary " *
              "conditions is not a valid brickwork sublayer: the next-nearest-" *
              "neighbor bonds of an even ring form two rings of length " *
              "L/2=$(L ÷ 2) (odd sites and even sites), and for L ≡ 2 (mod 4) " *
              "that length is odd, so an odd-length ring cannot be partitioned " *
              "into two disjoint pair layers. This sublayer applies the pairs " *
              "($(shared - 2),$shared) and ($shared,$wrap_to), which share site " *
              "$shared: the two gates are applied sequentially in enumeration " *
              "order, so the result depends on that order for non-commuting " *
              "gates and the sublayer is not a depth-1 layer. Every NNN bond " *
              "is still gated exactly once by the four sublayers together " *
              "(Bricklayer(:nnn)). Use L ≡ 0 (mod 4) or bc=:open for disjoint " *
              "NNN sublayers, and double-check the intended pattern with " *
              "print_circuit(circuit) (or plot_circuit if Luxor is loaded)."
        @warn msg maxlog=1 _id=Symbol(:bricklayer_nnn_pbc_, geo.parity, :_, L)
    end
    return nothing
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
