# Roadmap

Directions being considered for future releases. Nothing here is scheduled;
items are ordered roughly by how well-scoped they are, not by priority. If
you're interested in tackling one, open an issue first so the design can be
discussed (see [CONTRIBUTING.md](CONTRIBUTING.md)).

## Open design question (needs resolution before further RNG work)

### Clifford backend's Born-draw-count contract

On the MPS/state-vector backends, every measurement consumes exactly one
`:born_measurement` RNG draw, even when the outcome is deterministic. The
Clifford backend only draws when the outcome is genuinely undetermined (zero
draws for deterministic measurements) — this is documented, intentional
behavior for the stabilizer formalism, not a bug. The consequence is that
`:born_measurement` stream positions drift between Clifford and MPS/SV after
the first deterministic measurement in a trajectory, so "same seed" no
longer implies "same trajectory" across backends past that point (entropy
trajectories still agree exactly, since they're Pauli-frame invariant, which
is why this went uncaught for a while).

Three options were identified and none was picked during the v0.4.0 audit,
because each has a real cost:

- **Force Clifford to always draw** one `:born_measurement` value per
  measurement (discarding it when deterministic) — restores cross-backend
  lockstep, but changes every existing seeded Clifford trajectory (a
  golden/regression-breaking change).
- **Keep the current divergence**, document it loudly — no behavior change,
  but "same seed ⇒ same trajectory" stays permanently false across backends
  once any deterministic measurement occurs.
- **Draw-per-measurement from a separate discard stream** — preserves
  Clifford's historical trajectories but doesn't fix cross-backend parity
  either; strictly worse than the other two for the stated goal.

This needs a deliberate decision (and, if Option A is chosen, a version bump
with a migration note), not a silent pick.

## Feature ideas

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
two-block reduced density matrix plus its trace norm. The MPS/state-vector
subset-RDM machinery added for `MutualInformation` (`_mps_subset_rdm_probs`
/ `_sv_subset_probs`) is the natural starting point; Clifford-state
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
per-element coin from the single `:gates_spacetime` stream — this was
explicitly audited in v0.4.0 (`src/Core/rng.jl`) and confirmed to have no
discrepancies against its documented contract, but the stream name itself is
hardcoded. Allowing independently named streams per stochastic operation
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
into `@testitem` blocks. Given the suite's current size (~7000 assertions),
this is a mechanical but nontrivial migration best done as its own
dedicated pass, not incrementally.

## Smaller, more contained follow-ups

These are lower-effort items noted during the v0.4.0 audit that didn't meet
the bar for that release's scope:

- **`Pointer` geometry inside `simulate!`**: `apply!(state, gate, pointer)`
  works in eager mode, but `Pointer` has no `compute_sites` method for the
  step-driven `Circuit`/`simulate!` path, so it throws `MethodError` if used
  inside a circuit builder. Either implement the missing method or document
  the restriction more prominently.
- **Non-contiguous individual regions for `MutualInformation`**: currently
  each of the two regions must be a single contiguous unit range (only the
  two regions' mutual disjointness is unconstrained). The underlying
  subset-entropy machinery on all three backends already handles arbitrary
  (non-contiguous) subsets — lifting the constructor restriction is a
  validation/documentation change, not new physics.
- **QuantumClifford deprecation warning**: `src/Clifford/Clifford.jl` still
  calls the deprecated `apply!(stab, op, indices)` argument order (should be
  `apply!(stab, indices, op)`); harmless today, trivial to fix, deferred to
  avoid touching Clifford source concurrently with the v0.4.0 audit work.
