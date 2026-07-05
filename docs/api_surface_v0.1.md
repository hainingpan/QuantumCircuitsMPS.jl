# API Surface Manifest — v0.1.0 (breaking)

Ground truth: export blocks in `src/QuantumCircuitsMPS.jl` (lines 45–85, including
the INTERNAL EXPORTS block). Every symbol exported by v0.0.x appears in exactly one
of KEEP or REMOVE. ADD lists symbols new in v0.1.

Decision context: `ct_compat` is KEPT (CT.jl cross-validation still required), so all
CT.jl-parity internal exports remain. `born_probability` is KEPT (public utility used
by regression tests).

## KEEP

| Symbol | v0.1 semantic change (— = none) |
|---|---|
| `SimulationState` | Gains opt-in event log: `SimulationState(...; log_events=false)`; default behavior unchanged |
| `initialize!` | — |
| `ProductState` | — |
| `RandomMPS` | — |
| `RNGRegistry` | Fixed-draw contract documented (K scalar draws per stochastic op per step, data-independent); `RNGRegistry(Val(:ct_compat); ...)` kept with documented invariant exemption (aliased streams) |
| `get_rng` | Sentinel guard: `:gates_spacetime` is blocked (errors) during feedback execution |
| `AbstractGate` | Gate contract now via `execute!(gate, state, region)` protocol + traits (`needs_normalization`, `is_measurement`); no hardcoded type checks in engine |
| `PauliX` | — |
| `PauliY` | — |
| `PauliZ` | — |
| `Projection` | Normalization now via trait (behavior identical) |
| `HaarRandom` | Gains n-site constructor `HaarRandom(n)`; draws remain on `:gates_realization` |
| `Measurement` | KEPT as alias for `Measure(:Z)` (outcome discarded, no feedback); candidate for deprecation in v0.2 — plan default, flagged for review |
| `Reset` | Reimplemented as sugar for `Measure(:Z; feedback=OnOutcome(1 => PauliX()))`; struct kept for dispatch/label; semantics identical |
| `CZ` | — |
| `total_spin_projector` | — |
| `verify_spin_projectors` | — |
| `SpinSectorProjection` | Normalization via trait (behavior identical) |
| `SpinSectorMeasurement` | Migrated onto `execute!` protocol; Born path preserved exactly; `feedback=` NOT supported in v0.1 (informative error) |
| `AbstractGeometry` | Gains canonical `elements(geo, L, bc)`, `element_count`, `is_broadcast` trait; enumeration order is now documented API contract |
| `SingleSite` | Set geometry (single element) |
| `AdjacentPair` | Set geometry (single element) |
| `Bricklayer` | Broadcast geometry; parity enumeration order preserved bit-for-bit and promoted to API contract |
| `AllSites` | Broadcast geometry; canonical order `[[1],[2],...,[L]]` promoted to API contract |
| `StaircaseLeft` | Identity remainder no longer advances the staircase; build-time error if combined with Σp < 1 stochastic op (physics guard) |
| `StaircaseRight` | Same as `StaircaseLeft` |
| `Pointer` | Kept; classified as Set geometry |
| `move!` | — |
| `AbstractObservable` | Contract unchanged: `obs(state) -> Float64` (event log is a separate structure) |
| `DomainWall` | `i1_fn` special case replaced by uniform record hook; recorded values unchanged |
| `BornProbability` | — |
| `EntanglementEntropy` | — |
| `StringOrder` | — |
| `Magnetization` | — |
| `track!` | — |
| `record!` | Existing `record!(state)` unchanged; gains new method `record!(::CircuitBuilder[, names...])` — recording marker inside `Circuit` do-block (see ADD) |
| `list_observables` | — |
| `apply!` | Public semantics unchanged; internally routed through `execute!` protocol |
| `apply_with_prob!` | BREAKING: single unified per-element categorical rule (one `:gates_spacetime` draw per element); duplicate lazy implementation removed; strict equal-K error; Σp ≤ 1 build-time validation; multi-outcome compound geometries (Case B) legitimately change physics — re-goldened |
| `Circuit` | Do-block builder unchanged; now accepts `record!` markers and `Measure`/feedback ops |
| `expand_circuit` | Rewired to the single shared selection function — expansions now match engine selections for the same seed |
| `expand_circuit_grouped` | Same as `expand_circuit` |
| `simulate!` | `record_when` must be explicit; conflicting recording specs raise `ArgumentError`; `:every_step` always fires; per-trajectory `deepcopy(circuit)` for thread safety |
| `ExpandedOp` | Handles per-element categorical results and `:record_mark` pseudo-ops |
| `RecordingContext` | Gains `op_idx`, `element_idx`, `at_mark::Bool`, `mark_index::Int` fields |
| `every_n_gates` | `gate_idx` now advances once per element slot regardless of sampled outcome (trajectory-independent schedules) |
| `every_n_steps` | — |
| `print_circuit` | Renders recording markers (`▽`/`[R]` glyph) and per-element categorical ops |
| `plot_circuit` | Luxor extension updated for markers + unified stochastic semantics |
| `advance!` | Internal (CT.jl parity) — unchanged |
| `get_sites` | Internal (CT.jl parity) — unchanged |
| `current_position` | Internal (CT.jl parity) — unchanged |
| `reset!` | Internal (CT.jl parity) — unchanged |
| `compute_site_staircase_right` | Internal (CT.jl parity) — unchanged |
| `compute_site_staircase_left` | Internal (CT.jl parity) — unchanged |
| `compute_pair_staircase` | Internal (CT.jl parity) — unchanged |
| `apply_op_internal!` | Internal (CT.jl parity) — unchanged |
| `born_probability` | Public utility (used by regression tests) — KEEP regardless of ct_compat decision |
| `compute_basis_mapping` | Internal (CT.jl parity) — gained a new `pbc_fold_start` keyword arg (default `L÷4+1`) controlling the PBC ring-fold origin; backward-compatible addition, not a breaking change |
| `physical_to_ram` | Internal (CT.jl parity) — unchanged |
| `ram_to_physical` | Internal (CT.jl parity) — unchanged |

## REMOVE

| Symbol | Migration |
|---|---|
| `simulate` | Build a `Circuit(...) do c ... end` and call `simulate!(circuit, state; n_steps=..., record_when=...)` |
| `simulate_circuits` | `simulate!(circuit, state; n_steps=N, record_when=...)` — one circuit repeated N steps replaces the circuits list |
| `run_circuit!` | `simulate!(circuit, state; n_steps=1, record_when=...)` |
| `CircuitSimulation` | Iterator style removed; own the loop yourself: call `simulate!` per chunk, or use `record_when`/markers for mid-run recording |
| `with_state` | Context API removed; pass `state` explicitly: `apply!(state, gate, geometry)` |
| `current_state` | Context API removed; you already hold the `SimulationState` — use it directly |
| `record_every` | `simulate!(...; record_when=every_n_steps(n))` |
| `record_at_circuits` | `simulate!(...; record_when=every_n_steps(n))` or place `record!(c)` markers at the desired points inside the `Circuit` do-block |
| `record_always` | `simulate!(...; record_when=:every_gate)` |
| `get_state` | Access your `SimulationState` variable directly |
| `get_observables` | `state.observables[:name]` |
| `circuits_run` | Track step count yourself (you pass `n_steps`), or use `RecordingContext.step_idx` inside `record_when` predicates |

## ADD (new in v0.1)

| Symbol | Description |
|---|---|
| `EachSite` | Broadcast geometry over a site collection: `EachSite(2:L-1)` → elements `[[i] for i in collection]` (SRN bulk eligibility) |
| `Sites` | Set geometry: one element `[sites...]`; gate support must equal `length(collection)` |
| `Measure` | `Measure(basis=:Z; feedback=nothing)` — measurement gate with typed (`OnOutcome`) or closure `(state, sites, outcome) -> ...` feedback |
| `OnOutcome` | Typed feedback map, e.g. `OnOutcome(1 => PauliX())` |
| `MatrixGate` | User-supplied unitary matrix as a gate |
| `Rx` | Single-qubit X rotation |
| `Ry` | Single-qubit Y rotation |
| `Rz` | Single-qubit Z rotation |
| `Hadamard` | Single-qubit Hadamard gate |
| `ProductGate` | Composite gate: inner gate applied element-wise over a geometry under ONE stochastic branch (K=1); MPS-friendly correlated layers |
| `record!(::CircuitBuilder)` | New method on existing export: `record!(c[, names...])` places explicit recording markers in the circuit (rendered as pseudo-ops) |
| `events` | Event-log accessor: `events(state)` (requires `log_events=true`) |
| `measurements` | Filtered event-log accessor for measurement outcomes — post-selection workflows |
| `expected_draws` | `expected_draws(circuit, n_steps)::Int` — fixed `:gates_spacetime` consumption; powers the draw-count invariant test (documented exemption under ct_compat aliased streams) |
