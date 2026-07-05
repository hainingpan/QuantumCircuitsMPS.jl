# Migration Guide: QuantumCircuitsMPS.jl v0.1.0

> **Status**: created by Task 16 (migration triage + golden verification) with the
> "Test Triage" section below. Task 21 extends this file with the full user-facing
> migration guide (removed APIs, replacements, new stochastic-rule semantics).

## Test Triage

Every seeded-regression assertion in the pre-refactor test suite was classified
against the plan's migration case analysis before the refactor's golden gate was
declared passed. **No Case A/C/D value was re-goldened** — all reproduce bit-exactly
on the new engine (this is the plan's hard guardrail: any A/C/D mismatch is an
engine bug, never a value to update).

### Case definitions (plan §Oracle Review)

| Case | Pattern | Migration behavior |
|---|---|---|
| **A** | Single-outcome compound stochastic op (e.g. `apply_with_prob!` with one `(p, Measurement, AllSites())` outcome) | **Bit-for-bit identical** under the unified rule: same draw count (K Bernoulli coins), same strict-`<` decisions, same element order |
| **B** | Multi-outcome compound (≥2 outcomes, any geometry `Bricklayer`/`AllSites`/`EachSite`) | **Physics legitimately changes**: old engine drew ΣKᵢ independent Bernoulli coins per step (one loop per outcome, non-exclusive); new unified rule draws K categorical coins per step (exclusive per element slot). Accepted only after event-by-event audit vs `reference_select` |
| **C** | K=1 categorical (e.g. CIPT staircases: set geometries, one element slot) | **Bit-identical** (old "simple path" was already a cumulative categorical walk with one coin) |
| **D** | Deterministic (no `apply_with_prob!`, or no `:gates_spacetime` coins at all) | **Unchanged** |

### Grep heuristic for Case B

Per the plan: `apply_with_prob!` calls with **≥2 outcomes** where **any geometry is
broadcast** (`Bricklayer`/`AllSites`/`EachSite`). Scanning the pre-refactor test
files (`mipt_regressions.jl`, `circuit_test.jl`, `qudit_test.jl`, `recording_test.jl`,
`entanglement_test.jl`) and the golden generator yields exactly **two** Case B
instances:

1. `test/golden/generate_goldens.jl` → `case_aklt()` — AKLT `p_nn=1.0`,
   outcomes on `Bricklayer(:nn)` + `Bricklayer(:nnn)` (the checked-in AKLT golden).
2. `test/circuit_test.jl` → "Test 4: Multi-outcome Bricklayer(:odd)/(:even) both
   reachable" (in testset "Per-element independent sampling statistics").

All other multi-outcome `apply_with_prob!` calls in the pre-refactor files use only
set geometries (staircases/`SingleSite`) → K=1 → Case C. (Test files written *during*
the refactor — `geometry_v01.jl`, `gates_v01.jl`, `rng_v01.jl`, `execute_protocol.jl`,
`event_log.jl`, `unified_rule_engine.jl`, `feedback.jl`, `eager_probabilistic.jl`,
`recording_v01.jl`, `legacy_removal.jl`, `visualization_v01.jl` — target the NEW
semantics by construction and are outside triage scope.)

### Golden verification (`test/golden_compare.jl`)

Rerun of the pre-refactor golden circuits on the v0.1 engine, identical seeds:

| Golden | Case | Verdict |
|---|---|---|
| `case_a_mipt.json` (L=8, p=0.15, 20 steps) | A | **CASE-A: PASS** — entropy[20], ⟨Z⟩[8], all 4 RNG fingerprints bit-exact |
| `case_c_cipt.json` (L=8, p_ctrl=0.5, 128 steps) | C | **CASE-C: PASS** — Mz[128], all 4 RNG fingerprints bit-exact |
| `case_d_haar.json` (L=8, 10 steps) | D | **CASE-D: PASS** — entropy[10], P(0)[8], all 4 RNG fingerprints bit-exact |
| `case_aklt_pnn1.json` (L=12, p_nn=1.0, 12 steps) | B (degenerate) | **AKLT-DEGEN: PASS** — `final_entropy`/`string_order` + born/realization/state_init fingerprints bit-exact; `gates_spacetime` fingerprint re-goldened (below) |

### Triage table

#### `test/mipt_regressions.jl`

| Testset | Stochastic pattern | Case | Justification / verdict |
|---|---|---|---|
| Statevector lockstep (seeds 1–3) | none — deterministic Haar `Bricklayer(:even)`+`(:odd)`, OBC | **D** | No `:gates_spacetime` coins. Haar draws (`:gates_realization`) unchanged. Assertion is an invariant (MPS vs dense SVD at 1e-8), reproduces exactly. PASS |
| Born statistics (400 trials) | none — `apply!` Haar + `apply!(Measurement(:Z), SingleSite(1))` | **D** | Deterministic gate schedule; only `:born_measurement` varies by design. Statistical band vs exact Born probability. PASS |
| Phase-averaged entropy (p=0.5, 100 seeds) | `apply_with_prob!`, **1 outcome** `(p, Measurement(:Z), AllSites())` | **A** | Single-outcome compound: per-trajectory bit-identical under unified rule (K=L coins/step, strict `<`, same order). Assertion is a multi-seed statistical band (area-law L-independence). PASS |
| RAM bipartition | none | **D** | Pure function test (`compute_basis_mapping`); now uses a parameterized fold via `pbc_fold_start`. PASS |

#### `test/circuit_test.jl`

| Testset | Stochastic pattern | Case | Justification / verdict |
|---|---|---|---|
| Circuit Construction (4 subtests) | build-time only | **D** | Structural assertions on `circuit.operations`. Note: "Stochastic operations"/"Mixed operations" subtests were adjusted in Task 9 (staircase + Σp<1 is now a build-time error — CIPT walk guard); intent preserved with Σp=1. PASS |
| Circuit params field | none | **D** | PASS |
| CircuitBuilder Validation | build-time error paths | **D** | `rng=` kwarg rejection is the NEW migration error (hard-removed in Task 9); Σp>1 tolerance unchanged. PASS |
| expand_circuit Determinism | 2 outcomes, `StaircaseRight`+`StaircaseLeft`/`SingleSite` | **C** | K=1 set geometries → categorical walk bit-compatible with old simple path. Assertions are seed-determinism self-consistency. PASS |
| CIPT staircase (5 subtests) | 2 outcomes, staircases | **C** | K=1. Position-walk invariants (±1 steps, sync, start at L) + deterministic staircase traces. Bit-compatible; Case C golden (`case_c_cipt.json`) covers the same path end-to-end. PASS |
| simulate! Execution | staircase stochastic (Σp=1 after Task 9 adjustment) + deterministic | **C/D** | Record-count assertions; `:every_step` now fires structurally every step (Task 13 fixed the do-nothing skip bug — for Σp=1 staircase circuits the old count was already n_steps, so counts unchanged). PASS |
| print_circuit Output / Baseline Visualization Fixtures / Spanning Box / Transposed Layout / SVG | seeded renders (`gates_spacetime=0`), incl. K=1 stochastic | **D/C** | Structural rendering assertions; expansion delegates to the shared `select_outcome_index` (Task 15). PASS |
| RNG Alignment (2 subtests) | 2 outcomes, staircases | **C** | K=1; expand/simulate consume the stream identically (single source of truth). PASS |
| Compound Geometries: "Stochastic AllSites with Measurement", "RNG determinism", "expand + simulate! RNG alignment" | 1 outcome, `AllSites` | **A** | Single-outcome compound → bit-identical. Per-site frequency/independence statistics + same-seed MPS equality at 1e-14. PASS |
| Compound Geometries: deterministic Bricklayer/AllSites expansion, empty Bricklayer, entropy tracking | none | **D** | Canonical enumeration order preserved verbatim (Task 3 API contract). PASS |
| Circuit Visualization Fixes, Issue 4 | 1 outcome, p=1.0, `Bricklayer(:nn)` | **A** | Degenerate single-outcome (p=1 → every slot fires, both engines). PASS |
| Per-element sampling statistics, Tests 1–3 & 5 | 1 outcome, `AllSites` | **A** | Frequency ≈ p per site, anti-correlation ≈ p², p∈{0,1} edge cases, expand≡simulate alignment at 1e-14. Bit-identical semantics. PASS |
| Per-element sampling statistics, **Test 4** (odd/even both reachable) | **2 outcomes, `Bricklayer(:odd)` + `Bricklayer(:even)`** | **B** | See "Case B findings" below. **audit-verified** |

#### `test/qudit_test.jl`

| Testset | Stochastic pattern | Case | Justification / verdict |
|---|---|---|---|
| S=1 Site Type / Qudit Site Type / ProductState API | none | **D** | Constructor/initialization structure only. PASS |
| Spin Projector Properties | none | **D** | Exact projector algebra (trace/completeness/idempotence/orthogonality). PASS |
| AKLT Physics Sanity Check | none — eager `apply!` loop of `SpinSectorProjection` (forced projection, no Born sampling, no coins) | **D** | Deterministic protocol; physics invariant \|SO\| ≈ 4/9 ± 5%. PASS |

#### `test/recording_test.jl`, `test/entanglement_test.jl`

No `apply_with_prob!` anywhere; fixed seeds drive only deterministic circuits
(Haar staircase + Reset). All record-count and entropy assertions are **Case D**.
PASS (recording counts unchanged: `:every_step` per step, `:every_gate` per applied
gate — deterministic circuits apply a gate every slot).

### Case B findings (audit trail)

Both Case B instances were accepted only after verifying the NEW engine's
selections against the Task 7 oracle `reference_select` **event-by-event with the
same seed** (`test/golden_compare.jl`, run of 2026-07-03):

1. **AKLT golden `case_aklt_pnn1.json`** (p_nn=1.0, degenerate Case B) —
   **audit-verified**: engine run with `log_events=true`; all **144/144** element-slot
   selections (12 steps × K=12) match `reference_select(MersenneTwister(42), [1.0, 0.0], 12)`,
   including per-event `step`, `element_idx`, and canonical `Bricklayer(:nn)` element
   sites (`AKLT-AUDIT: PASS`). Physics values reproduce bit-exactly
   (`final_entropy = 1.9999836971234757`, `string_order = -0.4444494622199513`,
   atol 1e-14 — the degenerate p=1 decisions survive the rule change), as do the
   `born_measurement`/`gates_realization`/`state_init` fingerprints.
   **Re-goldened value**: the `:gates_spacetime` post-run fingerprint changes
   `0.6539347077753881` (old engine: ΣKᵢ = 12+12 = 24 coins/step, 288 total) →
   **`0.10031542999150234`** (unified rule: K = 12 coins/step, 144 total). The new
   value is derived from first principles in `golden_compare.jl` (twin-burn: 144
   scalar draws off `MersenneTwister(42)`, then draw) and pinned there as
   `AKLT_GATES_SPACETIME_FINGERPRINT_V01`. The pristine pre-refactor JSON is
   intentionally left untouched as the historical baseline; `golden_compare.jl`
   is the authoritative carrier of the accepted v0.1 fingerprint.
   Statistical backup: AKLT string order ≈ 4/9 invariant also holds in
   `qudit_test.jl` (5% band) — still green.

2. **`circuit_test.jl` "Test 4: Multi-outcome Bricklayer(:odd)/(:even)"** —
   **audit-verified**: the exact Test 4 circuit (2 × `Measurement(:Z)` at 0.5/0.5 on
   odd/even sublayers, L=8 PBC, K=4) expanded via `expand_circuit(seed=42)` for 20
   steps matches `reference_select(MersenneTwister(42), [0.5, 0.5], 4)` slot-by-slot,
   mapping selection 1 → k-th odd pair and 2 → k-th even pair
   (`CASEB-TEST4-AUDIT: PASS`; `expand_circuit` delegates to the engine's shared
   `select_outcome_index` since Task 15, so this audits the production selection
   path). Semantics change accepted: old engine could fire BOTH sublayers on
   overlapping sites in one step (8 independent coins); new rule picks exactly one
   outcome per element slot (4 coins, exclusive). The test asserts only
   reachability of both outcomes across seeds (no golden numeric value); its
   title/comments were updated for categorical semantics in Tasks 9/15 and it
   passes. Engine-level backup: `unified_rule_engine.jl` property test pins engine
   event log ≡ `reference_select` for 100 randomized multi-outcome configs.

**No other physics value in the repository changed.** In particular no Case A, C,
or D golden or in-test constant was modified by the refactor.

---

## Removed APIs (v0.1.0)

Twelve symbols were removed from the public API in v0.1.0 (see
`docs/api_surface_v0.1.md`'s REMOVE table for the one-line contract). Calling
any of them now raises an `error()` naming the replacement and pointing back
to this file — never a bare `UndefVarError`. This section gives worked
before/after snippets for each, reconstructed from the pre-refactor
implementations (`git show <pre-refactor commit>:src/API/...`).

A terminology note before the snippets: the old "circuits" style APIs counted
in **circuits**, where one circuit = `L` calls of a per-step function
(`circuit_step!(state)`). The new `Circuit(...) do c ... end` + `simulate!`
API counts in **raw steps** (`n_steps`) — a `Circuit` do-block plays the role
of the old `circuit_step!`. So `circuits=N` in the old API becomes
`n_steps = N * L` in the new one (shown explicitly below).

### `simulate`

**Before (v0.0.x, functional one-shot, `circuit!::Function` = `(state, t) -> Nothing`):**
```julia
results = simulate(
    L=8, bc=:periodic, init=ProductState(binary_int=0),
    circuit! = (state, t) -> apply!(state, HaarRandom(), Bricklayer(:even)),
    steps=20,
    observables=[:entropy => EntanglementEntropy(; cut=4)],
    rng=RNGRegistry(gates_spacetime=42, gates_realization=1, born_measurement=2),
    record_at=:every
)
entropies = results[:entropy]
```

**After (v0.1.0):**
```julia
circuit = Circuit(L=8, bc=:periodic) do c
    apply!(c, HaarRandom(), Bricklayer(:even))
end
state = SimulationState(L=8, bc=:periodic,
    rng=RNGRegistry(gates_spacetime=42, gates_realization=1, born_measurement=2))
initialize!(state, ProductState(binary_int=0))
track!(state, :entropy => EntanglementEntropy(; cut=4))
simulate!(circuit, state; n_steps=20, record_when=:every_step)
entropies = state.observables[:entropy]
```
(`record_at=:final`/`:custom` map to `record_when=:final_only`/a custom
predicate function respectively.)

### `simulate_circuits`

**Before (v0.0.x, `circuit_step!::Function` = `(state) -> Nothing`, counted in circuits):**
```julia
left, right = StaircaseLeft(8), StaircaseRight(1)
results = simulate_circuits(
    L=8, bc=:periodic, init=ProductState(binary_int=0),
    circuit_step! = state -> apply_with_prob!(state; outcomes=[
        (probability=0.5, gate=Reset(), geometry=left),
        (probability=0.5, gate=HaarRandom(), geometry=right)
    ]),
    circuits=16,   # total raw steps = 16 * 8 = 128
    observables=[:Mz => Magnetization(:Z)],
    rng=RNGRegistry(gates_spacetime=42, gates_realization=1, born_measurement=2),
    on_circuit! = record_every(2)
)
```

**After (v0.1.0 — one circuit repeated `n_steps` times replaces the circuits list):**
```julia
left, right = StaircaseLeft(8), StaircaseRight(1)
circuit = Circuit(L=8, bc=:periodic) do c
    apply_with_prob!(c; outcomes=[
        (probability=0.5, gate=Reset(), geometry=left),
        (probability=0.5, gate=HaarRandom(), geometry=right)
    ])
end
state = SimulationState(L=8, bc=:periodic,
    rng=RNGRegistry(gates_spacetime=42, gates_realization=1, born_measurement=2))
initialize!(state, ProductState(binary_int=0))
track!(state, :Mz => Magnetization(:Z))
simulate!(circuit, state; n_steps=16*8, record_when=every_n_steps(2*8))
```

### `run_circuit!`

**Before (v0.0.x — one call = `L` applications of `circuit_step!`):**
```julia
circuit_step!(s) = apply!(s, HaarRandom(), Bricklayer(:even))
run_circuit!(state, circuit_step!, L)
```

**After (v0.1.0):**
```julia
circuit = Circuit(L=L, bc=state.bc) do c
    apply!(c, HaarRandom(), Bricklayer(:even))
end
simulate!(circuit, state; n_steps=L, record_when=:every_step)
```

### `CircuitSimulation`

**Before (v0.0.x, lazy iterator, yields the SAME mutable state object each time):**
```julia
sim = CircuitSimulation(
    L=8, bc=:periodic, init=ProductState(binary_int=0),
    circuit_step! = state -> apply!(state, HaarRandom(), Bricklayer(:even)),
    observables=[:entropy => EntanglementEntropy(; cut=4)],
    rng=RNGRegistry(gates_spacetime=42, gates_realization=1, born_measurement=2)
)
record!(sim.state; i1=1)
for (n, s) in enumerate(Iterators.take(sim, 20))
    n % 2 == 0 && record!(s; i1=1)
end
results = get_observables(sim)
```

**After (v0.1.0 — own the loop yourself; `record_when` or `record!(c)` markers replace the callback):**
```julia
circuit = Circuit(L=8, bc=:periodic) do c
    apply!(c, HaarRandom(), Bricklayer(:even))
end
state = SimulationState(L=8, bc=:periodic,
    rng=RNGRegistry(gates_spacetime=42, gates_realization=1, born_measurement=2))
initialize!(state, ProductState(binary_int=0))
track!(state, :entropy => EntanglementEntropy(; cut=4))
simulate!(circuit, state; n_steps=20*8, record_when=every_n_steps(2*8))
results = state.observables
```

### `with_state`

**Before (v0.0.x — implicit state via task-local context, 2-arg `apply!(gate, geo)`):**
```julia
with_state(state) do
    apply!(HaarRandom(), Bricklayer(:odd))
end
```

**After (v0.1.0 — pass the state explicitly, always):**
```julia
apply!(state, HaarRandom(), Bricklayer(:odd))
```

### `current_state`

**Before (v0.0.x — retrieve the implicit state inside a nested helper):**
```julia
function my_helper()
    s = current_state()
    println("L = ", s.L)
end
with_state(state) do
    apply!(HaarRandom(), Bricklayer(:odd))
    my_helper()
end
```

**After (v0.1.0 — thread the state through as an ordinary argument):**
```julia
function my_helper(s)
    println("L = ", s.L)
end
apply!(state, HaarRandom(), Bricklayer(:odd))
my_helper(state)
```

### `record_every`

**Before (v0.0.x, `on_circuit!` callback for `simulate_circuits`, records every 2 circuits):**
```julia
simulate_circuits(; ..., circuits=16, on_circuit! = record_every(2))
```

**After (v0.1.0):**
```julia
simulate!(circuit, state; n_steps=16*L, record_when=every_n_steps(2*L))
```

### `record_at_circuits`

**Before (v0.0.x, records at specific circuit numbers):**
```julia
simulate_circuits(; ..., circuits=100, on_circuit! = record_at_circuits([10, 50, 100]))
```

**After (option A — regular cadence via `every_n_steps`):**
```julia
simulate!(circuit, state; n_steps=100*L, record_when=every_n_steps(40*L))  # only if the spacing is regular
```

**After (option B — explicit, arbitrary positions via `record!(c)` markers):**
```julia
circuit = Circuit(L=L, bc=:periodic) do c
    apply!(c, HaarRandom(), Bricklayer(:even))
    record!(c)                     # mark exactly where you want a snapshot
    apply!(c, HaarRandom(), Bricklayer(:odd))
end
simulate!(circuit, state; n_steps=100, record_when=:marks)
```

### `record_always`

**Before (v0.0.x — records after every circuit):**
```julia
simulate_circuits(; ..., on_circuit! = record_always())
```

**After (v0.1.0):**
```julia
simulate!(circuit, state; n_steps=16*L, record_when=:every_gate)
```

### `get_state`

**Before (v0.0.x — retrieve the iterator's internal state):**
```julia
sim = CircuitSimulation(; L=8, bc=:periodic, ...)
run!(sim, 10)
final_state = get_state(sim)
```

**After (v0.1.0 — you created `state`; it IS the final state after `simulate!` returns):**
```julia
simulate!(circuit, state; n_steps=10*8)
final_state = state
```

### `get_observables`

**Before (v0.0.x):**
```julia
entropies = get_observables(sim)[:entropy]
```

**After (v0.1.0):**
```julia
entropies = state.observables[:entropy]
```

### `circuits_run`

**Before (v0.0.x — number of circuits the iterator has advanced through):**
```julia
sim = CircuitSimulation(; L=8, bc=:periodic, ...)
for (n, s) in enumerate(Iterators.take(sim, 20))
    println("circuit ", circuits_run(sim))
end
```

**After (v0.1.0 — you pass `n_steps` yourself; track it directly, or read
`RecordingContext.step_idx` inside a custom `record_when` predicate):**
```julia
simulate!(circuit, state; n_steps=20,
    record_when = ctx -> (ctx.is_step_boundary && println("step ", ctx.step_idx); false))
```

---

## The Unified Stochastic Rule: What Changed

The pre-refactor engine (`Circuit/execute.jl:170-237`) silently switched
between two DIFFERENT selection algorithms depending on the shape of an
`apply_with_prob!` call:

- **Simple / single-outcome compound** (one outcome, or a set geometry): a
  cumulative-categorical walk with one coin — this is exactly today's rule
  (Case A/C in the triage table above).
- **Multi-outcome compound** (≥2 outcomes on a broadcast geometry, e.g.
  `Bricklayer`/`AllSites`): an INDEPENDENT Bernoulli trial per outcome, each
  in its OWN loop — `ΣKᵢ` coin draws per step, and because the trials were
  not exclusive, a given site could legitimately receive BOTH outcomes'
  gates, or NEITHER, in the same step.

v0.1.0 replaces both with ONE rule (see "The Unified Stochastic Rule" in the
README): per element `k = 1..K`, exactly one coin, one categorical selection
among the outcomes, remainder = identity. This is a **behavior change** only
for the multi-outcome-compound case (Case B in the triage table above) —
Case A/C/D users see bit-identical trajectories, verified in
`test/golden_compare.jl`.

### If you relied on the OLD independent-Bernoulli behavior

If your v0.0.x code depended on a site being able to receive multiple
outcomes' gates in the same step (or neither), express that explicitly as
SEPARATE `apply_with_prob!` calls — one per outcome, each with its own
single-outcome (Case-A-shaped) probability. Each call draws its own `K`
coins from `:gates_spacetime`, in sequence, and outcomes across the two calls
are independent of each other (reproducing the old "both or neither"
possibility):

**Before (v0.0.x, independent Bernoulli per outcome — `ΣKᵢ` coins/step):**
```julia
# Old engine: each site could get gate_a, gate_b, BOTH, or NEITHER
apply_with_prob!(c; outcomes=[
    (probability=0.3, gate=gate_a, geometry=Bricklayer(:odd)),
    (probability=0.3, gate=gate_b, geometry=Bricklayer(:even))
])
```

**After (v0.1.0, same independent-Bernoulli semantics via two separate ops):**
```julia
# New engine: two INDEPENDENT single-outcome ops reproduce "both or neither
# possible" — each op is its own Case-A-shaped categorical draw (K coins per
# op), and the two ops draw from :gates_spacetime independently in sequence.
apply_with_prob!(c; outcomes=[
    (probability=0.3, gate=gate_a, geometry=Bricklayer(:odd))
])
apply_with_prob!(c; outcomes=[
    (probability=0.3, gate=gate_b, geometry=Bricklayer(:even))
])
```

**For comparison, the NEW unified rule (one coin decides `gate_a` XOR
`gate_b` per element, never both — this is what the v0.1.0 call above
actually does now):**
```julia
apply_with_prob!(c; outcomes=[
    (probability=0.3, gate=gate_a, geometry=Bricklayer(:odd)),
    (probability=0.3, gate=gate_b, geometry=Bricklayer(:even))
])
```

This last form only compiles if `Bricklayer(:odd)` and `Bricklayer(:even)`
expand to the SAME element count `K` (the equal-K build-time rule) — for a
periodic-BC even-length chain they always do (`L/2` pairs each).

---

## API Contracts

This section documents the v0.1.0 API surface's binding contracts: things
user code MAY rely on staying fixed across releases. (Design choice: these
contracts are folded into this migration guide rather than a separate
`docs/api_contracts_v0.1.md` — everything a v0.0.x user needs when porting
code lives in one file, alongside the removed-API worked examples above.)

### Element enumeration order per geometry

`elements(geo, L, bc)::Vector{Vector{Int}}` (`src/Geometry/elements.jl`) is
the single source of truth for how a geometry expands into gate-application
regions. Its enumeration ORDER is an API contract — RNG coin consumption
follows this order — reproduced verbatim from the docstring:

- `AllSites()` → `[[1], [2], ..., [L]]`
- `EachSite(c)` → `[[i] for i in c]` (collection order, e.g. `EachSite(2:L-1)`)
- `Bricklayer(parity)` → pairs exactly as documented in the README's
  "Bricklayer Geometry Parities" table:
  - `:odd` → `[[1,2],[3,4],...]`
  - `:even` → `[[2,3],[4,5],...]`, with `[L,1]` appended LAST under PBC only
    (OBC has no wrap element)
  - `:nn` → all `:odd` elements THEN all `:even` elements, concatenated (not
    interleaved)
  - `:nnn_odd_1`/`:nnn_odd_2`/`:nnn_even_1`/`:nnn_even_2` → the four NNN
    sublayers individually (each with its own PBC wrap element, if any,
    appended last)
  - `:nnn` → sublayers 1, 2, 3, 4 concatenated in that order
- `SingleSite(i)` → `[[i]]`
- `AdjacentPair(i)` → `[[i, i+1]]` (PBC wraps `i=L` to `[[L, 1]]`)
- `Sites(c)` → `[collect(c)]` (ONE element spanning all of `c`)
- `StaircaseLeft`/`StaircaseRight` → `[[pos, pos+range]]` at the CURRENT
  position (PBC wraps via `mod1`; OBC throws `ArgumentError` on overflow)
- `Pointer` → `[[pos, pos+1]]` at the current position (PBC wraps at `L`)

`element_count(geo, L, bc) = length(elements(geo, L, bc))` is the `K` used by
the equal-K build-time validation. `is_broadcast(geo)::Bool` is `true` only
for `AllSites`, `Bricklayer`, `EachSite` (`K` can exceed 1); every other
geometry is a "set" geometry (`K == 1`, always).

### RNG contract

Four independent named streams live in `RNGRegistry` (`src/Core/rng.jl`):
`:gates_spacetime` (stochastic-op coin flips), `:gates_realization` (Haar
draws, custom-gate randomness, feedback randomness), `:born_measurement`
(measurement Born sampling), `:state_init` (random initial states).

- **Fixed-draw invariant**: `:gates_spacetime` consumption is
  data-independent — every stochastic op draws exactly `K` scalar coins per
  step (`K` = its outcomes' shared element count), REGARDLESS of which
  outcomes actually get selected. `expected_draws(circuit, n_steps)` computes
  the exact total and powers a draw-count invariant test.
- **Scalar-draws-only**: every coin is a single `rand(rng)` call — never
  `rand(rng, K)`. Vectorized/array fast paths are not used anywhere in the
  engine, because they can diverge from `K` independent scalar draws for some
  RNG implementations; this is enforced by convention (`# SCALAR-DRAW
  CONTRACT` comments at every draw site) rather than by the type system.
- **Feedback stream rules**: measurement feedback (`Measure(:Z;
  feedback=...)`) runs entirely inside `with_guarded_stream(registry,
  :gates_spacetime)` — any attempt to draw `:gates_spacetime` during feedback
  throws an `ErrorException` ("... forbidden ..."), because a feedback-time
  draw would desynchronize the fixed-draw invariant. Feedback randomness
  belongs on `:gates_realization` (e.g. `HaarRandom(1)` inside a feedback
  closure) or, for nested measurements, `:born_measurement`. Feedback gates
  never advance `gate_idx` and emit no `GateApplied` event (a nested
  `Measure` still emits its own `MeasurementOutcome`).
- **`ct_compat` exemption**: `RNGRegistry(Val(:ct_compat); circuit=...,
  measurement=...)` aliases `:gates_spacetime` and `:gates_realization` to
  the SAME `MersenneTwister` object (for CT.jl cross-validation parity).
  Under aliasing the fixed-draw invariant CANNOT hold (Haar draws interleave
  with coin draws by construction) — this is intentional, faithful to CT.jl's
  single-RNG design, not a bug. `is_aliased(registry)` detects this case;
  `expected_draws` draw-count checks and the `with_guarded_stream` sentinel
  guard are both automatically bypassed (documented no-op) for aliased
  registries.

### `deepcopy`/`copy(circuit)` per-trajectory threading pattern

A `Circuit` holding staircase or `Pointer` geometries is MUTABLE — their
positions advance during `simulate!`. For per-trajectory parallelism
(`Threads.@threads` over seeds, or any reuse of the same circuit across
independent runs), give each trajectory its OWN circuit via `copy(circuit)`
(a `Base.copy` override that performs a `deepcopy`, preserving any
intra-circuit staircase-position aliasing — e.g. `left`/`right` staircases
that must stay in sync within one trajectory but must NOT be shared across
trajectories):

```julia
Threads.@threads for seed in seeds
    c = copy(circuit)                                      # private geometry state
    st = SimulationState(L=8, bc=:periodic,
        rng=RNGRegistry(gates_spacetime=seed, gates_realization=seed+1000,
                         born_measurement=seed+2000))
    initialize!(st, ProductState(binary_int=0))
    simulate!(c, st; n_steps=64)
end
```

Reusing the SAME `Circuit` object across threads without `copy` is a bug: the
staircase positions from one trajectory would leak into another, breaking
reproducibility and thread safety.

### Σp ≤ 1 remainder-identity rule

Every `apply_with_prob!` outcome list must satisfy `Σp ≤ 1 + 1e-10`
(validated at BUILD time for the `Circuit` do-block form, and at CALL time
for the eager `apply_with_prob!(state; outcomes=...)` form — both delegate to
the same validation). The remainder `1 - Σp` is the probability of the
IDENTITY outcome: nothing is applied at that element, staircases/`Pointer`
positions do NOT advance, but the element-slot counter (`gate_idx`) still
advances (recording schedules stay trajectory-independent).

Because identity does not advance staircases, a stochastic op whose outcomes
include ANY staircase or `Pointer` geometry is REQUIRED to have `Σp = 1`
exactly (within tolerance) — enforced as a build-time `ArgumentError` (the
"CIPT walk guard"): a random walk that could silently stall for `Σp < 1`
steps would break control-induced-phase-transition physics, where every step
must move the walker. Non-walking (broadcast, or non-staircase set)
geometries may freely use `Σp < 1`.
