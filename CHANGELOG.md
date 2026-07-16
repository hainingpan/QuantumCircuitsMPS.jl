# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html)
in spirit (pre-1.0, so breaking changes can land in minor versions).

## [Unreleased]

## [0.5.1] - 2026-07-15

### Changed

- Applied JuliaFormatter v2.10.1 with `SciMLStyle` to the package entrypoints,
  Gaussian backend implementation, and Gaussian test suite. This is a
  formatting-only maintenance release with no runtime behavior changes.
- Recorded the bulk formatting commits in `.git-blame-ignore-revs` so line
  history remains useful across the mechanical rewrite.

## [0.5.0] - 2026-07-13

This release adds a fourth simulation backend: a fermionic Gaussian
(free-fermion) backend for circuits built entirely out of Gaussian-preserving
gates and parity measurements, along with two new gates, a Majorana-chain
site granularity for class-DIII circuits, and a matching documentation and
test suite.

### Added

- **Gaussian backend** (`backend=:gaussian`): a pure fermionic Gaussian state
  is represented as a dense `2L×2L` real antisymmetric Majorana covariance
  matrix `Γ` (`Γ[a,b] = (i/2)⟨[γ_a,γ_b]⟩`, satisfying `Γ² = -I`) instead of
  an MPS, state vector, or stabilizer tableau; `GaussianBackend` holds
  `corr`, a `scratch` buffer, `purify_tol` (default `1e-10`), and
  `majoranas_per_site`. `apply!`, `track!`, `record!`, and `simulate!` work
  unchanged — only the `SimulationState(...; backend=:gaussian)` constructor
  call differs. Gate/measurement application is `O(L³)` per operation
  (Schur-complement contraction on `Γ`, no truncation error, exact for any
  circuit depth), and a re-purification step (`purify!`, eigen-clamping
  `iΓ`'s spectrum back to `±1`) fires automatically whenever floating-point
  drift exceeds `purify_tol`.
- Two new gates, dispatched only on the Gaussian backend (informative
  `ArgumentError` rejection on MPS/state-vector/Clifford):
  - `GaussianHaar()` — Haar-random `SO(4)` rotation (fermionic-mode
    granularity) or `SO(2)` rotation (Majorana-chain granularity,
    `exp(θγ_aγ_b)`, `θ ~ U[0,2π)`), drawn from `:gates_realization` and
    conjugated directly onto `Γ`.
  - `BondParity()` — projective bond-parity measurement `iγ_{2i}γ_{2i+1}`
    between adjacent sites (fermionic-mode) or `iγ_iγ_{i+1}` between
    adjacent Majorana sites (Majorana chain), with PBC wrap support;
    consumes one `:born_measurement` draw per bond under the same
    redundant-draw contract as `Measure`.
- `PauliX()`, `Measure(:Z)`, and `Reset()` now also work on the Gaussian
  backend: `PauliX` flips fermionic occupation parity (a single Majorana
  row/column sign flip), `Measure(:Z)` is a projective on-site
  occupation-parity measurement (`iγ_{2i-1}γ_{2i}`), and `Reset()` composes
  the two, matching the existing semantics on every other backend.
- **Majorana-chain site granularity** (`site_type="Majorana"`): each site is
  one Majorana mode rather than one fermionic mode (`Γ` is `L×L` instead of
  `2L×2L`; requires even `L`), directly modeling the staggered class-DIII
  monitored Majorana-chain circuit family — `GaussianHaar`/`BondParity` on
  `Bricklayer(:odd)`/`Bricklayer(:even)` reproduce the protocol with no new
  gate types.
- `RandomGaussianState` initial-state type: draws `O ∈ SO(2L)` (or `SO(L)`
  on the Majorana chain) from `:state_init` via an exact Haar sampler,
  `haar_orthogonal`, using QR decomposition of a Ginibre matrix.
- Gaussian-backend observable support: `EntanglementEntropy` (von Neumann
  only, covariance-matrix formula; `renyi_index != 1` rejected),
  `Magnetization(:Z)` (fermionic-mode granularity only), `BornProbability`,
  `MutualInformation` and `TripartiteMutualInformation` (von Neumann only;
  the only backend that accepts non-contiguous or PBC-wrapped region pairs,
  since a covariance-matrix reduced state is just an index selection), and
  `EntropyProfile`. `StringOrder`, `DomainWall`, `PauliString`, `Correlator`,
  and `MagnetizationFluctuations` are rejected with an informative
  `ArgumentError` (no fermionic-Gaussian formula exists for these).
- New Documenter.jl page `docs/src/backends/gaussian.md` documenting the
  backend, and a substantially expanded `docs/src/devdocs/backend_interface.md`
  developer-docs page covering the Gaussian method tables (`initialize!`,
  `_apply_single!`, `_measure_single_site!`, `born_probability`,
  observables).
- `examples/gaussian_example.ipynb` / `examples/gaussian_example.jl`:
  reproduces the class-DIII phase diagram via the staggered monitored
  Majorana-chain protocol.
- New `test/gaussian/` suite (14 files): construction and rejection checks,
  gate and measurement tests, an oracle-based cross-validation against an
  independent reference implementation, golden-value regression tests, and
  Majorana-chain-specific coverage.

## [0.4.0] - 2026-07-07

This release is a quality/hardening pass across the whole package: a systematic
audit of every backend and observable, arbitrary spin-S support, four new
composed observables, a custom-observable API, a benchmark suite, a full
Documenter.jl site, and CI/quality gates (Aqua, JET, ExplicitImports). It also
removes one redundant gate and tightens the public export surface.

### Added

- `PauliString(i => :P, j => :P', ...)` — multi-site Pauli-string expectation
  value observable, on the MPS, state-vector, and Clifford backends.
- `MutualInformation(regionA, regionB; renyi_index=1, base=ℯ)` —
  `I(A:B) = S(A) + S(B) - S(A∪B)` for two disjoint contiguous site regions, on
  all three backends (MPS via subset-RDM contraction with a size guard, exact
  state vector via partial trace, Clifford via poly-time GF(2)-rank stabilizer
  entropies). Regions are physical sites on every backend and under both
  boundary conditions.
- `Correlator(i => :P, j => :P')` — connected two-point correlator
  `⟨PᵢPⱼ⟩ - ⟨Pᵢ⟩⟨Pⱼ⟩`, composed from `PauliString`.
- `EntropyProfile(; renyi_index=1, base=ℯ)` — vector observable returning
  `[S(cut=x) for x in 1:L-1]` in one call; the first vector-valued built-in
  observable (see the custom-observable API below for how the vector storage
  is threaded through `track!`/`record!`).
- `TripartiteMutualInformation(A, B, C)` — `I₃ = I(A:B) + I(A:C) - I(A:BC)`
  (Gullans–Huse MIPT convention), composed from `MutualInformation`.
- `MagnetizationFluctuations(region; axis=:Z)` — `Var(M)` for
  `M = Σᵢ∈region Pᵢ`, composed from `PauliString`.
- **Custom-observable API**: `track!` now also accepts `Symbol => <any callable>`
  (not just a built-in `AbstractObservable`), `record_value` has an untyped
  fallback (`record_value(obs, state) = obs(state)`), and per-key storage
  auto-widens from `Vector{Float64}` to `Vector{Any}` the first time a
  non-scalar value is recorded — this is what makes vector-valued observables
  like `EntropyProfile` work without a new trait system. See
  `docs/src/custom_observables.md` for the contract and worked examples.
- **Arbitrary spin-S site types** (`"S=k/2"` for `S` up to 10, half-integer
  steps), on the MPS and state-vector backends: initialization at any level
  (`"Z<m>"` state names, e.g. `"Z3/2"`, `"Z-1/2"`), `Sz`/`S+`/`S-` operators,
  per-level projectors (`"Proj0"` .. `"Proj2S"`), categorical
  (2S+1)-outcome single-site `Measure(:Z)` (reduces bitwise to the old
  binary Born-sampling algorithm at `S=1/2`), `Projection(k)` for any level
  `k`, `MatrixGate(U; d=...)` for explicit local dimension, and
  `total_spin_projector(S; s=...)` / `verify_spin_projectors(; s=...)`
  generalized from the hardcoded `S=1` case to arbitrary spin-`s` pairs via
  the Lagrange/Casimir projection formula.
- `RandomStateVector` (state-vector-backend random initialization, drawing
  from the `:state_init` RNG stream) is now exported.
- **Benchmark suite** (`benchmark/benchmarks.jl`, AirspeedVelocity-compatible,
  10 scope-table entries / 14 leaves) with a committed baseline
  (`benchmark/results/baseline-5ab86ab.json`) and a CI workflow
  (`.github/workflows/benchmarks.yml`, `continue-on-error: true` on pull
  requests).
- **Documenter.jl site** (`docs/`): design philosophy, per-backend pages
  (MPS/state-vector/Clifford), tutorials (MIPT/CIPT/AKLT/feedback quick
  starts), a restructured API reference (`@docs` blocks per module area, plus
  an "Observables Catalog" and an "Arbitrary Spin-S Support" section), a
  private/internal API page, a developer-docs backend-interface contract page
  (`docs/src/devdocs/backend_interface.md`), and the custom-observables page.
  100% of `names(QuantumCircuitsMPS)` are documented on the built site.
- **CI workflows**: `CI.yml`, `format-check.yml` (JuliaFormatter v2,
  SciMLStyle), `CompatHelper.yml`, `TagBot.yml`, `docs.yml` (Documenter
  deploy), `benchmarks.yml`.
- **Quality gates**: `Aqua.test_all` and `ExplicitImports` run as standing
  tests in every `Pkg.test()`; `JET.report_package` runs opt-in under
  `JET_TEST=true` with a documented, only-decreasing report-count ratchet.
- **Audit test suites** (`test/audit/`) systematically cross-checking every
  backend/observable/gate against its documented contract; several findings
  from this audit are the `Fixed` entries below, and the remainder are
  recorded as open questions in [ROADMAP.md](ROADMAP.md).

### Fixed

- `RandomMPS` now respects `RNGRegistry`'s `:state_init` stream (previously
  ignored it and drew from the global RNG, so random initial states were not
  reproducible under a fixed seed).
- Calling `StringOrder` or `DomainWall` on a Clifford-backend state no longer
  crashes with a raw `FieldError` (`no field mps` / `no field sites`); both
  now raise an informative `ArgumentError` explaining that these observables
  are not supported on the stabilizer-tableau backend.
- `plot_circuit`'s Luxor SVG rendering of non-adjacent (NNN) gates: PBC-wrap
  labels no longer collide pixel-exactly with unrelated gates' labels at
  lattice center, and non-wrap NNN gate labels no longer get overdrawn by a
  later gate's box in the same packed layer; open-boundary long-range gates
  are no longer misclassified as periodic wraps.
- `CITATION.cff` was out of sync (`version: 0.1.0`, stale `date-released`);
  now tracks this release.
- `Bricklayer(:even)` at odd system size `L` under periodic boundary
  conditions no longer double-touches site `L` within a single brickwork
  layer (it now leaves site 1 unpaired, mirroring `:odd`'s existing
  behavior of leaving site `L` unpaired). In addition, using
  `Bricklayer(:odd)`/`Bricklayer(:even)` with odd `L` under `bc=:periodic`
  now emits a one-time warning (at circuit-build time and on immediate-mode
  `apply!`): an odd ring has no valid brickwork tiling — each layer leaves
  one site unpaired (`:odd` → site `L`, `:even` → site 1) and the wrap bond
  `(L,1)` is gated by neither layer, so an alternating `:odd`/`:even`
  circuit is effectively open across that bond. Enumeration is unchanged;
  `:nn` and the NNN sublayers do not warn. Verify intended patterns with
  `print_circuit`.
- `SpinSectorProjection` gained a `gate_matrix` method, so it now works on
  the state-vector backend (previously `MethodError: no method matching
  gate_matrix(::SpinSectorProjection)` — the AKLT Quick Start could not run
  with `backend=:statevector`).
- `Magnetization(:Z)` on `"S=1"` (and other arbitrary spin-S) MPS/state-vector
  states no longer throws; it now correctly reports `⟨Sz⟩ ∈ [-S, S]` (qubit
  and `"S=1/2"` sites keep the existing `±1` Pauli convention).
- `SimulationState(L=0, ...)` (or negative `L`) now throws an informative
  `ArgumentError` on all backends (previously constructed a silent, unusable
  empty state).
- `ProductState(binary_int=-1)` (or any negative value) now throws an
  informative `ArgumentError` (previously accepted silently, and
  `initialize!` produced a garbage state by parsing the `-` sign character
  as a state label).

### Changed / BREAKING

- **BREAKING — Clifford Born-draw contract (redundant draw)**: the Clifford
  backend's measurement primitive now consumes exactly ONE `:born_measurement`
  draw per measured site — always — matching MPS/state-vector. When the
  stabilizer tableau fixes the outcome (deterministic measurement), the draw
  is made anyway and its value is **discarded** (a deliberate *redundant
  draw*). This restores absolute cross-backend reproducibility: same
  `RNGRegistry` seeds now produce the same measurement record on all three
  backends. **Migration impact**: seeded Clifford trajectories generated
  with earlier versions (which consumed zero draws for deterministic
  outcomes) are NOT reproducible under the new contract — a one-time break.
  MPS/state-vector trajectories are completely unaffected. Deterministic
  outcomes themselves are unchanged (still read off the tableau); only the
  RNG stream position differs.
- **BREAKING — removed**: the `Measurement` gate. Use `Measure(:Z)` instead
  (drop-in replacement: same Born sampling, same one-draw-per-measurement
  contract, same `"Meas"` circuit label, bit-identical trajectories under the
  same seeds). For feedback, use
  `Measure(:Z; feedback=OnOutcome(1 => PauliX()))` etc. No deprecation alias
  is provided.
- **BREAKING — export surface**: 11 internal symbols are no longer exported:
  `advance!`, `get_sites`, `current_position`, `reset!`,
  `compute_site_staircase_right`, `compute_site_staircase_left`,
  `compute_pair_staircase`, `apply_op_internal!`, `compute_basis_mapping`,
  `physical_to_ram`, `ram_to_physical`. They remain defined for
  debugging/introspection — use qualified access, e.g.
  `QuantumCircuitsMPS.advance!(geo, L, bc)`.
- **BREAKING**: `CZ`/`CNOT`/`SWAP` now reject non-qubit sites
  (`local_dim != 2`) with an informative `ArgumentError`, matching the
  existing guard on `Rx`/`Ry`/`Rz`/`Hadamard`. Previously these gates
  silently built an undocumented, non-standard qudit generalization when
  applied to `S≥1` sites (e.g. a 3-level "CZ" that put `-1` only on
  `|22⟩` instead of the standard `ωʲᵏ` phases) — a silent-physics-trap that
  is now a clean error instead.
- `born_probability(state, site, outcome)` is now a documented public export
  (promoted out of the internal-exports block).
- The `SimulationState` field-forwarding `getproperty` shim
  (`state.mps`/`state.sites`/`state.cutoff`/`state.maxdim`, MPS backend
  only) is **kept** and is now explicitly documented as supported public
  API, not a deprecated compatibility layer — a usage census found 42 call
  sites in `test/` alone, above the removal threshold.
- **BREAKING**: Julia compatibility floor raised from 1.11 to 1.12 (required
  by QuantumClifford 0.11.5, which itself requires julia≥1.12 — the
  previously-declared 1.11 floor did not actually resolve).

### Performance

Baseline: commit `5ab86ab` (`benchmark/results/baseline-5ab86ab.json`),
Julia 1.12.6. All comparisons below are before/after on the same machine;
see the notepad-linked evidence logs for full detail.

- **State-vector observable loop optimization** (shared `_sv_digit` stride
  helper + single-pass algorithms, L=12 random state):
  | Observable | Before | After | Speedup |
  |---|---|---|---|
  | `Magnetization(:Z)` | 86.7 µs | 2.62 µs | **~33x** |
  | `DomainWall(order=1)` | 277.9 µs | 8.3 µs | **~33x** |
  | `DomainWall(order=2)` | 277.8 µs | 7.7 µs | **~36x** |
  | `StringOrder(order=1)` | 54.1 µs | 7.4 µs | **~7.3x** |
  | `StringOrder(order=2)` | 53.0 µs | 14.8 µs | **~3.6x** |
  | `born_probability` | 7.8 µs | 4.1 µs | ~1.9x |

  Corroborated by the benchmark suite: `magnetization/sv_L8` 3.417 µs → 208 ns
  (16.4x). All changes verified bitwise-identical or within 1e-15 of the old
  formulas on 20 random states; no formula or RNG behavior changed.
- **Vectorized `CZ`/`CNOT`/`SWAP` ITensor construction** (reshape + `ITensor`
  constructor instead of a 16-iteration scalar `setindex!` loop):
  gate-construction alone went from 1.584 µs / 65 allocs to 1.167 µs / 39
  allocs (1.36x faster, 40% fewer allocations); the full
  `apply!(state, CZ(), AdjacentPair(...))` on MPS L=12 improved from
  330.875 µs / 4802 allocs to 318.104 µs / 4749 allocs. Verified bitwise
  identical to the old operator construction on all 16 index combinations.
- **`elements()` caching in `simulate!`** (step-invariant static geometries
  cached per circuit run instead of recomputed every step):
  | Scenario | Before allocs | After allocs | Δ |
  |---|---|---|---|
  | MIPT, state vector, L=8, 50 steps | 18,703 | 16,315 | **-12.8%** |
  | MIPT, Clifford, L=100, 20 steps | 173,361 | 163,627 | **-5.6%** |
  | MIPT, MPS, L=20, 20 steps | 2,163,183 | 2,161,106 | -0.1% (MPS SVD-dominated) |

  Bitwise-identical trajectories verified before/after (a lazy-vs-cached
  equality regression suite is now permanent, `test/regression/elements_cache.jl`).

## [0.3.0] - 2026-07-05

Clifford (stabilizer-tableau) backend: `CNOT`, `PhaseGate`, `SWAP`,
`RandomClifford` gates, and a Clifford-backend MIPT demo.

## [0.2.1] - 2026-07-05

Removed a stale "Known Limitations" README entry.

## [0.2.0] - 2026-07-05

State-vector backend, and periodic-boundary-condition fold alignment for the
MPS backend.

## [0.1.1] - 2026-07-04

Removed an orphaned `imperative.jl`; synced `dev` with `main`.

## [0.1.0] - 2026-07-04

API refactor: MPS quantum circuit simulation core (the "v0.1" API — `Gates`,
`Geometry`, `Observables`, the unified stochastic rule, `SimulationState`).

## [0.0.7] - 2026-06-13

Hygiene fix.

## [0.0.6] - 2026-06-11

Maintenance release.

## [0.0.5] - 2026-06-10

Fixed AKLT plotting; updated the random seed for consistency across example
notebooks.

## [0.0.4] - 2026-06-08

Added citation metadata.

## [0.0.3] - 2026-06-08

Fixed circuit plotting.

## [0.0.2] - 2026-02-04

AKLT/qudit support, improved circuit visualization, comprehensive
documentation.

## [0.0.1] - 2026-01-31

Initial clean release, with CIPT and MIPT example notebooks.

[Unreleased]: https://github.com/hainingpan/QuantumCircuitsMPS.jl/compare/v0.5.0...HEAD
[0.5.1]: https://github.com/hainingpan/QuantumCircuitsMPS.jl/compare/v0.5.0...v0.5.1
[0.5.0]: https://github.com/hainingpan/QuantumCircuitsMPS.jl/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/hainingpan/QuantumCircuitsMPS.jl/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/hainingpan/QuantumCircuitsMPS.jl/compare/v0.2.1...v0.3.0
[0.2.1]: https://github.com/hainingpan/QuantumCircuitsMPS.jl/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/hainingpan/QuantumCircuitsMPS.jl/compare/v0.1.1...v0.2.0
[0.1.1]: https://github.com/hainingpan/QuantumCircuitsMPS.jl/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/hainingpan/QuantumCircuitsMPS.jl/compare/v0.0.7...v0.1.0
[0.0.7]: https://github.com/hainingpan/QuantumCircuitsMPS.jl/compare/v0.0.6...v0.0.7
[0.0.6]: https://github.com/hainingpan/QuantumCircuitsMPS.jl/compare/v0.0.5...v0.0.6
[0.0.5]: https://github.com/hainingpan/QuantumCircuitsMPS.jl/compare/v0.0.4...v0.0.5
[0.0.4]: https://github.com/hainingpan/QuantumCircuitsMPS.jl/compare/v0.0.3...v0.0.4
[0.0.3]: https://github.com/hainingpan/QuantumCircuitsMPS.jl/compare/v0.0.2...v0.0.3
[0.0.2]: https://github.com/hainingpan/QuantumCircuitsMPS.jl/compare/v0.0.1...v0.0.2
[0.0.1]: https://github.com/hainingpan/QuantumCircuitsMPS.jl/releases/tag/v0.0.1
