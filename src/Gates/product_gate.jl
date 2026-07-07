# === ProductGate (v0.1) ===
#
# A "product layer as ONE gate": ProductGate(inner, geo) bundles the
# element-wise application of `inner` over a broadcast geometry into a single
# AbstractGate, so the whole layer can be one categorical branch (K = 1) in
# `apply_with_prob!` (the correlated-layer use case: per step, ONE coin decides
# which ENTIRE layer is applied — never a per-element mixture).
#
# NOTE ON INCLUDE ORDER: this file is included from QuantumCircuitsMPS.jl
# AFTER Circuit/Circuit.jl because it adds methods for the `execute!` protocol
# (Core/apply.jl), `elements`/`is_broadcast` (Geometry), `gate_label`
# (Circuit/expand.jl) and the CircuitBuilder `apply!` form (Circuit/builder.jl).

"""
    ProductGate(inner::AbstractGate, region_geometry::AbstractGeometry)

A Set-like composite gate: applying it applies `inner` once per element of
`region_geometry` (a BROADCAST geometry: `AllSites`, `Bricklayer`, or
`EachSite`), in the canonical [`elements`](@ref) order. The whole product
counts as ONE gate — in `apply_with_prob!` outcomes it is ONE categorical
branch (K = 1), so a single `:gates_spacetime` coin governs the entire layer.

# RNG semantics
Each element application is an independent call of `inner`'s own
`execute!`/`build_operator` path, so random inner gates (e.g. `HaarRandom()`)
draw ONE FRESH realization per element from `:gates_realization` — exactly as
if the layer had been applied with `apply!(state, inner, region_geometry)`.

For "the SAME unitary on every element", do NOT use `ProductGate` — spell it
`MatrixGate(U)` applied to a broadcast geometry:
`apply!(state, MatrixGate(U), Bricklayer(:even))`.

# Calling convention (v0.1 API contract)
`ProductGate` carries its target geometry itself; its region argument, where
one is syntactically required, must be `Sites(u)` where `u` covers EXACTLY the
union of `elements(region_geometry, L, bc)` — any other region throws an
`ArgumentError`. The accepted spellings:

```julia
pg = ProductGate(HaarRandom(), Bricklayer(:even))

# Deterministic, in a circuit (geometry omitted — RECOMMENDED):
Circuit(L=8, bc=:periodic) do c
    apply!(c, pg)                      # records geometry = Sites(union)
    apply!(c, pg, Sites(1:8))          # equivalent explicit form
end

# Eager, on a state:
apply!(state, pg)                      # geometry omitted — RECOMMENDED
apply!(state, pg, Sites(1:8))          # equivalent explicit form

# Stochastic outcome (K = 1; the outcome tuple REQUIRES a geometry key, so
# the explicit Sites(union) spelling is the ONLY valid one here):
apply_with_prob!(c; outcomes=[
    (probability=0.5, gate=ProductGate(HaarRandom(), Bricklayer(:even)),
     geometry=Sites(1:8)),
    (probability=0.5, gate=ProductGate(CZ(), Bricklayer(:even)),
     geometry=Sites(1:8)),
])
```

Erroneous spellings (all `ArgumentError`): passing the inner broadcast
geometry again (`apply!(state, pg, Bricklayer(:even))` or
`geometry=Bricklayer(:even)` in an outcome — that would multiply the product
per element), a `Sites` region that is not exactly the union, or a
staircase/`Pointer` geometry. Deterministic builder forms error at BUILD time;
outcome-tuple misuse errors at run time (the builder's outcome validation is
gate-agnostic).

# Event log
With `log_events=true`, each element application is logged as a `GateApplied`
with the INNER gate's label (element_idx = position within the product); the
engine additionally logs one wrapper `GateApplied` with this gate's label
(`"∏" * gate_label(inner)`, e.g. `"∏Haar"`).

# Restrictions
- `region_geometry` must be a broadcast geometry (`is_broadcast(geo) == true`).
  For a single region, apply `inner` directly: `apply!(x, inner, geometry)`.
- Nesting (`ProductGate` inside `ProductGate`) is not supported.
- `support(pg)` is undefined (throws): the site count depends on `L`/`bc`.
"""
struct ProductGate <: AbstractGate
    inner::AbstractGate
    region_geometry::AbstractGeometry

    function ProductGate(inner::AbstractGate, region_geometry::AbstractGeometry)
        inner isa ProductGate && throw(ArgumentError(
            "Nested ProductGate is not supported: the inner gate of a " *
            "ProductGate must be a plain gate, got ProductGate."))
        is_broadcast(region_geometry) || throw(ArgumentError(
            "ProductGate requires a broadcast geometry (AllSites, Bricklayer, " *
            "or EachSite), got $(typeof(region_geometry)). For a single " *
            "region, apply the gate directly: apply!(x, gate, geometry)."))
        new(inner, region_geometry)
    end
end

function support(pg::ProductGate)
    throw(ArgumentError(
        "ProductGate has no fixed support: it expands to the union of " *
        "elements($(typeof(pg.region_geometry)), L, bc), which depends on the " *
        "system size. Apply it via apply!(x, pg) (geometry omitted) or with " *
        "Sites(union) — see the ProductGate docstring."))
end

# The product is a measurement iff its inner gate is (each element Born-samples).
is_measurement(pg::ProductGate) = is_measurement(pg.inner)

# Normalization is handled per element by the INNER gate's own execute! path
# (needs_normalization(inner) applies inside each element application), so the
# wrapper itself keeps the default needs_normalization(::AbstractGate) = false.

gate_label(pg::ProductGate) = "∏" * gate_label(pg.inner)

"""
    _product_region(pg::ProductGate, L::Int, bc::Symbol) -> Vector{Int}

Canonical region of a `ProductGate`: the sorted union of
`elements(pg.region_geometry, L, bc)`. This is the ONLY region a
`ProductGate` may be applied to (API contract; see the `ProductGate`
docstring).
"""
function _product_region(pg::ProductGate, L::Int, bc::Symbol)
    elems = elements(pg.region_geometry, L, bc)
    isempty(elems) && throw(ArgumentError(
        "ProductGate geometry $(typeof(pg.region_geometry)) expands to zero " *
        "elements for L=$L, bc=$bc"))
    return sort!(unique(reduce(vcat, elems)))
end

"""
    execute!(state::SimulationState, pg::ProductGate, region::Vector{Int})

Execute a `ProductGate`: validate that `region` covers exactly the union of
`elements(pg.region_geometry, state.L, state.bc)`, then apply `pg.inner` to
each element in canonical order via the uniform `execute!` protocol (one
fresh `:gates_realization` draw per element for random inner gates). Logs one
`GateApplied` per element (inner gate's label) when the event log is enabled.
"""
function execute!(state::SimulationState, pg::ProductGate, region::Vector{Int})
    elems = elements(pg.region_geometry, state.L, state.bc)
    isempty(elems) && throw(ArgumentError(
        "ProductGate geometry $(typeof(pg.region_geometry)) expands to zero " *
        "elements for L=$(state.L), bc=$(state.bc)"))
    expected = sort!(unique(reduce(vcat, elems)))
    given = sort(unique(region))
    given == expected || throw(ArgumentError(
        "ProductGate already carries its target geometry " *
        "($(typeof(pg.region_geometry))); it must be applied to exactly the " *
        "union of that geometry's elements. Expected region $(expected) — " *
        "spell it Sites($(expected)), or use apply!(x, pg) which fills it " *
        "in — got $(given). In particular, do NOT pass the broadcast " *
        "geometry itself as the application geometry."))
    n = support(pg.inner)
    for (i, elem) in enumerate(elems)
        n == length(elem) || throw(ArgumentError(
            "ProductGate inner gate $(typeof(pg.inner)) has support $n but " *
            "element $i of $(typeof(pg.region_geometry)) has " *
            "$(length(elem)) site(s): $elem"))
        execute!(state, pg.inner, elem)
        if state.event_log !== nothing
            log_event!(state, GateApplied(state.event_step, state.event_op_idx,
                i, gate_label(pg.inner), elem))
        end
    end
    return nothing
end

# The canonical-region check lives in execute! (needs state.L/state.bc there
# anyway, and the engine's stochastic path never calls validate_support);
# make the eager apply!(state, pg, Sites(u)) path defer to it instead of
# comparing against the (undefined) fixed support of the wrapper.
validate_support(pg::ProductGate, geo::Sites, L::Int, bc::Symbol) = nothing

"""
    apply!(state::SimulationState, pg::ProductGate)

Apply a `ProductGate` eagerly with its geometry omitted (recommended form):
equivalent to `apply!(state, pg, Sites(u))` with `u` the union of
`elements(pg.region_geometry, state.L, state.bc)`.
"""
function apply!(state::SimulationState, pg::ProductGate)
    execute!(state, pg, _product_region(pg, state.L, state.bc))
end

"""
    apply!(builder::CircuitBuilder, pg::ProductGate)

Record a deterministic `ProductGate` operation with its geometry omitted
(recommended form): the canonical region `Sites(union)` is filled in from the
builder's `L`/`bc`.
"""
function apply!(builder::CircuitBuilder, pg::ProductGate)
    apply!(builder, pg, Sites(_product_region(pg, builder.L, builder.bc)))
end

"""
    apply!(builder::CircuitBuilder, pg::ProductGate, geometry)

Explicit form of recording a deterministic `ProductGate`: `geometry` MUST be
`Sites(u)` with `u` exactly the union of the product's elements (validated at
BUILD time; any other geometry throws an `ArgumentError`).
"""
function apply!(builder::CircuitBuilder, pg::ProductGate, geometry)
    geometry isa Sites || throw(ArgumentError(
        "ProductGate already carries its target geometry " *
        "($(typeof(pg.region_geometry))). Record it with apply!(c, pg) " *
        "(geometry omitted) or apply!(c, pg, Sites(union)); got " *
        "$(typeof(geometry))."))
    expected = _product_region(pg, builder.L, builder.bc)
    given = sort(unique(geometry.sites))
    given == expected || throw(ArgumentError(
        "ProductGate region mismatch: expected Sites($(expected)) (the union " *
        "of elements($(typeof(pg.region_geometry)), L=$(builder.L), " *
        "bc=$(builder.bc))), got Sites with sites $(given). " *
        "Use apply!(c, pg) to fill the region in automatically."))
    push!(builder.operations, (type = :deterministic, gate = pg, geometry = geometry))
    return nothing
end

# --- Engine plumbing: Sites as a stochastic-outcome (set) geometry ---
# The unified engine resolves set-geometry outcomes via
# compute_sites_dispatch → compute_sites(geo, step, L, bc). Sites gained
# engine-set-path support here (additive; needed for ProductGate outcomes,
# valid for any gate): its region is position/step-independent.
compute_sites(geo::Sites, step::Int, L::Int, bc::Symbol) = elements(geo, L, bc)[1]
