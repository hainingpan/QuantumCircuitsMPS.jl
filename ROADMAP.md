# Roadmap

Directions being considered for future releases. Nothing here is scheduled;
items are ordered roughly by how well-scoped they are, not by priority. If
you're interested in tackling one, open an issue first so the design can be
discussed (see [CONTRIBUTING.md](CONTRIBUTING.md)).

## Feature ideas

### Higher-dimensional (2D+) circuits

Everything today is strictly one-dimensional: sites are indexed `1:L` along a
chain, boundary conditions are `:open`/`:periodic` on that chain, and every
geometry (`Bricklayer`, `AllSites`, `StaircaseLeft`, ...) enumerates chain
sites/bonds. Supporting 2D (or higher) circuit geometries would require a
lattice/coordinate abstraction in `src/Geometry/`, new geometry types (e.g.
plaquette or row/column brickwork layers), and backend consideration: the
state-vector and Clifford backends are dimension-agnostic once sites are
mapped to a linear index, but the MPS backend would need a snake/space-filling
site ordering and would suffer the usual entanglement-area-law cost of
representing 2D states with a 1D tensor train. This is a major, cross-cutting
addition; until then, 1D-only is a documented limitation (see README
"Known Limitations").

### Noise channels (Kraus operators / density-matrix state)

All three backends currently simulate pure states only. Physical noise
(depolarizing, amplitude damping, dephasing, etc.) needs either a
density-matrix representation or Kraus-operator sampling layered on top of
the existing pure-state trajectories. This is a substantial addition (new
state representation or a stochastic-unravelling layer) rather than a small
patch.

### Computational-basis sampling / shots

Right now, observables are computed analytically from the state (exact
expectation values, Born probabilities). A `sample(state, n_shots)`-style API
that draws computational-basis bitstrings the way a real quantum device
would (or a classical shadow protocol) would let this package double as a
"virtual QPU" for benchmarking measurement-based post-processing pipelines.

### Trajectory / ensemble runner

MIPT/CIPT studies need averages over many random trajectories (different
`:gates_spacetime`/`:gates_realization`/`:born_measurement` seeds). Today
that's a user-written loop around `simulate!`. A built-in ensemble runner
(parallel seeds, automatic observable aggregation/error bars) would remove
a substantial amount of research-notebook boilerplate that every current
example notebook re-implements slightly differently.

### DomainWall on the Clifford backend

`DomainWall` is currently rejected on the Clifford backend with a clean
`ArgumentError` (see [CHANGELOG.md](CHANGELOG.md#040---2026-07-07)) rather
than silently crashing. It's feasible in principle: domain-wall counting can
be expressed via stabilizer-group Born probabilities of Pauli-diagonal
projector products, which is poly-time for a stabilizer state. `StringOrder`
on Clifford is a separate, harder question — it would additionally need a
spin-1-on-stabilizer formalism decision, since the Clifford backend is
qubit-only by design, so it isn't planned the same way.

### Entanglement negativity

Not implemented in v0.4.0. Would require the partial transpose of the
two-block reduced density matrix plus its trace norm. The subset-RDM machinery added for `MutualInformation` is the natural starting point; Clifford-state
negativity is also known to be poly-time computable via the bipartite
stabilizer group structure, so all three backends are plausible.

### Spin-S string order / operator strings

`StringOrder` is currently scoped to `S=1` chains (the AKLT string order
parameter). With arbitrary spin-`S` sites now supported (v0.4.0), a
generalized non-local string-order observable — the natural `PauliString`
analog for `S>1/2`, built from the same `Sz`/level-projector machinery
already in `src/Core/spin_sites.jl` — would let AKLT-family studies extend
past the spin-1 chain.

### Participation entropy

A standard complementary diagnostic to entanglement entropy in the MIPT
literature (Shannon/Rényi entropy of the computational-basis probability
distribution, rather than of a reduced density matrix's spectrum). Cheap to
compute on the state-vector and Clifford backends; on MPS it would need
either a sampling estimator or an exact but expensive full-amplitude
reconstruction.

### Named RNG streams for stochastic operations

The unified stochastic engine (`apply_with_prob!`) always draws its
per-element coin from the single `:gates_spacetime` stream — confirmed to match its documented contract, but the stream name itself is hardcoded. Allowing independently named streams per stochastic operation
would let correlated and uncorrelated randomness be composed more flexibly
(e.g. two independent measurement processes in the same circuit that
shouldn't share a coin sequence) — deferred until a concrete research use
case needs it, per the existing README "Known Limitations" note.

### TestItemRunner migration

The test suite currently uses plain `@testset`/`include` composition in
`test/runtests.jl`. Migrating to
[TestItemRunner.jl](https://github.com/julia-vscode/TestItemRunner.jl) would
enable parallel test execution and per-test-item IDE integration (VS Code
Julia extension test explorer), at the cost of restructuring every test file
into `@testitem` blocks. Given the suite's current size, this
is a mechanical but nontrivial migration best done as its own
dedicated pass, not incrementally.
