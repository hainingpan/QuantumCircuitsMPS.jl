# Design Philosophy

Quantum-circuit research is usually described in terms of states, gates,
measurements, geometry, and observables. Simulation libraries, however, often
require the researcher to work directly with tensors, dense matrices, or
backend-specific data structures. `QuantumCircuitsMPS.jl` is designed to keep
those two levels separate: users describe the physics, while the package
selects and operates the numerical representation.

The result is one simulation vocabulary that can be used for exploratory
small-system state vector simulation, scalable matrix product states, and large-scale
Clifford-gate simulations.

## One Model, Three Backends

```@raw html
<pre class="mermaid">
flowchart TB
    subgraph UserAPI["User-Facing API"]
        A["SimulationState and Circuit"]
        B["Gates and Geometry"]
        C["Observables and Records"]
    end

    A --> D["Shared Simulation Engine"]
    B --> D
    C --> D

    D --> E["MPS Backend<br/>ITensors.jl and ITensorMPS.jl"]
    D --> F["State-Vector Backend<br/>Exact dense wavefunction"]
    D --> G["Clifford Backend<br/>QuantumClifford.jl tableau"]

    E --> H["Updated state and recorded observables"]
    F --> H
    G --> H
</pre>
<script type="module">
  import mermaid from "https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.esm.min.mjs";
  mermaid.initialize({ startOnLoad: true, theme: "neutral" });
</script>
```

The upper layer contains the concepts used to define an experiment. The
shared engine expands geometries, schedules operations, manages random-number
streams, and dispatches each operation to the selected backend. The backend
owns the numerical representation and the algorithms needed to update it.

The three backends serve different purposes:

- The [MPS Backend](@ref) is the default for general circuits at large system
  sizes, with controlled truncation through `cutoff` and `maxdim`, applied to area-law entangled states.
- The [State Vector Backend](@ref) is an exact reference for small systems,
  where storing the full wavefunction is practical.
- The [Clifford Backend](@ref) uses a stabilizer tableau to reach hundreds or
  thousands of qubits when the circuit contains only supported Clifford
  operations.

Changing `backend` changes the representation, not the language used to
describe the simulation. Shared operations such as `apply!`, `track!`,
`record!`, and `simulate!` retain the same role. Backend-specific limitations
remain explicit: for example, the Clifford backend rejects non-Clifford gates
rather than silently approximating them.

Implementation details belong on the individual backend pages. Developers
adding or extending a backend should instead consult the
[Backend Interface Contract](@ref).

## Physics Objects, Not Numerical Plumbing

The public API separates the ingredients of an experiment:

- A `SimulationState` holds the state representation, boundary conditions,
  random-number streams, and recorded data.
- A gate describes **what physical operation** should occur.
- A geometry describes **where that operation** should occur.
- A circuit describes **when operations and records** should occur.
- An observable describes **what quantity** should be extracted from the
  state.

This separation lets the same gate be reused with different geometries and
the same circuit structure be tested across compatible backends. It also keeps
backend implementation objects—such as ITensors, dense gate kernels, and
stabilizer tableaux—out of research scripts.

## Explicit and Reproducible Randomness

Randomness is part of the physical model, not an incidental implementation
detail. Independent named streams distinguish choices such as where a random
operation occurs, which random gate is realized, and which measurement outcome
is sampled. As a result, changing one kind of random choice does not
unnecessarily perturb the others.

Probabilistic operations follow one shared rule through `apply_with_prob!`.
At each geometry element, the engine makes one categorical choice among the
listed outcomes; any remaining probability corresponds to doing nothing. For
this comparison to be well defined, the outcome geometries in one call must
expand to the same number of elements. For example,

```julia
apply_with_prob!(c; outcomes=[
    (probability=0.5, gate=HaarRandom(), geometry=Bricklayer(:even)),
    (probability=0.5, gate=CZ(), geometry=Bricklayer(:even)),
])
```

chooses exactly one of the two gates on every even bond. It never applies both
gates to the same bond. Using one rule for measurements, random gates, and
control protocols makes stochastic trajectories easier to reason about and
reproduce.

## Geometry Expresses Intent

A geometry is more than a list of site indices: it states whether an operation
is repeated over independent locations or applied once to a region.

- **Broadcast geometries**, such as `AllSites()`, `Bricklayer(:even)`, and
  `EachSite(sites)`, expand into multiple elements. The gate is applied once
  per element, and a probabilistic operation makes a separate choice for each
  element.
- **Set geometries**, such as `SingleSite(i)`, `AdjacentPair(i)`, and
  `Sites(sites)`, describe one element. The sites together form the support of
  a single gate application and receive one probabilistic choice.

For example, `EachSite(2:L-1)` applies a one-site gate independently at every
interior site, whereas `Sites(2:L-1)` treats all interior sites as one region
for a gate with matching support. This distinction keeps spatial intent
visible in the circuit definition instead of hiding it inside loops.

Together, these choices—one physics-facing API, explicit backend dispatch,
controlled randomness, and semantic geometries—make simulations easier to
read, compare, and extend without tying the research code to one numerical
method.
