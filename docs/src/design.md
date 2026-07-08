# Design Philosophy

```@raw html
<pre class="mermaid">
flowchart TB
    subgraph "User-Facing API"
        A[SimulationState] --> B[Gates]
        B --> C[Geometry]
        C --> D[Observables]
    end
    subgraph "Internal Engine"
        E[apply!] --> F[build_operator]
        F --> G[apply_op_internal!]
    end
    subgraph "Backend"
        H[ITensors.jl] --> I[ITensorMPS.jl]
    end
    D --> E
    G --> H
</pre>
<script type="module">
  import mermaid from "https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.esm.min.mjs";
  mermaid.initialize({ startOnLoad: true, theme: "neutral" });
</script>
```

## Layered Abstraction

- **User-Facing API**: Physicists work with `SimulationState`, `Gates` (PauliX, HaarRandom, Projection), `Geometry` (Bricklayer, AllSites, StaircaseLeft), and `Observables` (EntanglementEntropy, Magnetization). No tensor network concepts exposed.
- **Internal Engine**: The `apply!` function translates high-level physics operations into ITensor calls. It manages physical-to-RAM index mappings (`phy_ram`/`ram_phy`), operator construction, and MPS updates. Users never interact with this layer.
- **Backend**: ITensors.jl and ITensorMPS.jl handle tensor contractions, SVD truncations, and gauge management. All low-level optimizations (bond dimensions, cutoffs, orthogonality centers) are managed automatically.
- **Key Insight**: Users write physics in three lines of code; the package executes hundreds of tensor operations behind the scenes, enabling rapid prototyping without sacrificing performance or scalability.

This page describes the MPS backend's internal engine specifically (`build_operator` → `apply_op_internal!`); the state-vector and Clifford backends follow the same [User-Facing API → Internal Engine → Backend] layering with their own internal engines — see [MPS Backend](@ref), [State Vector Backend](@ref), and [Clifford Backend](@ref) for backend-specific detail, and [Backend Interface Contract](@ref) for the developer-facing contract every backend must satisfy.

## The Unified Stochastic Rule

Every probabilistic operation in the package, from a single measurement to a multi-outcome control protocol, follows ONE rule: `apply_with_prob!(c; outcomes=[(probability=p, gate=g, geometry=geo), ...])` expands each outcome's `geometry` into a list of elements (site groups), and every outcome must expand to the SAME element count `K`. For each element `k = 1..K`, the engine draws exactly one coin from the `:gates_spacetime` stream and makes a categorical selection among the outcomes at that element; the remainder `1 - Σp` selects identity (nothing applied). There is no separate "independent Bernoulli per outcome" code path and no second RNG scheme hiding in a compound geometry — one rule, one selection function, everywhere.

This single rule is what makes exclusive per-bond gate choices natural: `outcomes=[(probability=0.5, gate=HaarRandom(), geometry=Bricklayer(:even)), (probability=0.5, gate=CZ(), geometry=Bricklayer(:even))]` guarantees every even bond gets EXACTLY one of `HaarRandom()` or `CZ()`, never both and never neither (when `Σp = 1`). Correlated layers (the SAME coin choosing an entire layer, not per-bond) are expressed with `ProductGate`, not with a second probabilistic construct.

## Broadcast vs. Set Geometry

Geometries fall into two families, and knowing which one you're holding tells you exactly how it behaves inside `apply_with_prob!` and `apply!`:

- **Broadcast** ("distribution") geometries expand to `K ≥ 1` independent elements, each getting its own gate application (and, inside a stochastic op, its own coin): `AllSites()`, `Bricklayer(parity)`, `EachSite(collection)`.
- **Set** ("region") geometries denote ONE region of sites, a single element: `SingleSite(i)`, `AdjacentPair(i)`, `Sites(collection)`, `StaircaseLeft`/`StaircaseRight`, `Pointer`.

`is_broadcast(geo)` reports the trait, and `elements(geo, L, bc)` returns the canonical enumeration either way, always `Vector{Vector{Int}}`. This vocabulary is also why `EachSite(2:L-1)` and `Sites(2:L-1)` look similar but mean opposite things: `EachSite` applies a single-site gate independently at each of sites 2 through L-1 (K = L-2 coins, K = L-2 possible applications), while `Sites(2:L-1)` is ONE region spanning sites 2 through L-1 for a single gate whose support equals `L-2`.
