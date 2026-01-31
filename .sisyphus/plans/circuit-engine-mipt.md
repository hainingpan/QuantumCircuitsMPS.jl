# Extend Circuit Engine for Bricklayer/AllSites + Fix MIPT Examples

## TL;DR

> **Quick Summary**: The Circuit execution engine (`simulate!` and `expand_circuit`) cannot handle Bricklayer or AllSites geometries — they have no `compute_sites` methods. This plan extends the engine to support compound geometries (including per-site independent stochastic decisions for MIPT physics), then rewrites both MIPT files to use the Circuit (declarative) API.
>
> **Deliverables**:
> - Extended Circuit engine supporting Bricklayer and AllSites in `simulate!`
> - Extended `expand_circuit` supporting Bricklayer and AllSites for visualization
> - Rewritten `mipt_example.jl` using Circuit API
> - Fixed `mipt_tutorial.ipynb` using Circuit API
> - Tests covering compound geometry execution + MIPT example correctness
> - Clarified EntanglementEntropy docstring re: Hartley entropy numerical issues
>
> **Estimated Effort**: Medium
> **Parallel Execution**: YES - 2 waves
> **Critical Path**: Task 1 → Task 2 → Task 3 → Task 5 → Task 6

---

## Context

### Original Request
User reported bugs in `mipt_tutorial.ipynb`:
1. `ProductState(fill(1//2, L))` — wrong argument type (Vector instead of scalar)
2. `SimulationState(circuit, x0)` — no such constructor (needs keyword args + RNGRegistry)
3. Even after fixing to `ProductState(0)`, `SimulationState(circuit, x0)` still fails

Investigation revealed the ROOT CAUSE is deeper: the Circuit execution engine doesn't support Bricklayer or AllSites geometries at all.

### Interview Summary
**Key Discussions**:
- User's design philosophy: Circuit (declarative) API is PRIMARY, NOT imperative. "Physicist-friendly, code as you declare."
- `mipt_example.jl` currently uses imperative loop — must be rewritten to Circuit style
- Per-site independent measurements: user writes `apply_with_prob!(..., geometry=AllSites())` and it should "just work" per-site under the hood
- Recording: each circuit completion = one "step". Use n_steps=1 + n_circuits=N for per-timestep recording.

**Research Findings**:
- `compute_sites` has methods ONLY for: SingleSite, AdjacentPair, StaircaseRight, StaircaseLeft
- Bricklayer/AllSites have NO `compute_sites` → Circuit engine throws MethodError
- Imperative API handles Bricklayer via `get_pairs()` and AllSites via `get_all_sites()` — both loop internally
- `execute_gate!` has special Reset handling (wraps in SingleSite); Measurement also needs compound handling
- Recording: `step_idx` = `circuit_idx`. `:every_step` fires once per circuit completion (after last gate of last timestep)

### Metis Review
**Identified Gaps** (addressed):
- **RNG Determinism**: Per-site stochastic draws consume L draws from `:ctrl` instead of 1 — `expand_circuit` must match this consumption pattern. → Addressed: expand_circuit will also expand per-element.
- **RNG Stream Separation**: `:ctrl` for "is site measured?" decisions, `:born` for Born outcomes. Two independent random processes. → Addressed: follows existing pattern in imperative API.
- **Empty Bricklayer edge case**: L=2 with :even parity → empty pairs. → Addressed: silently skip (match imperative behavior).
- **Scope creep risk**: Don't add geometry trait systems or touch Pointer. → Addressed: explicit guardrails.
- **expand_circuit alignment**: Must produce multiple ExpandedOps for compound geometries. → Addressed: Option A (expanded) chosen.

---

## Work Objectives

### Core Objective
Extend the Circuit execution engine to natively support Bricklayer and AllSites geometries — including per-site/per-pair independent stochastic decisions — then fix both MIPT files to use the Circuit API.

### Concrete Deliverables
- Modified `src/Circuit/execute.jl` — compound geometry handling in simulate!
- Modified `src/Circuit/expand.jl` — compound geometry expansion + Measurement label + validation
- Rewritten `examples/mipt_example.jl` — Circuit style
- Fixed `examples/mipt_tutorial.ipynb` — correct API usage
- New tests in `test/circuit_test.jl` — Bricklayer/AllSites execution

### Definition of Done
- [x] `julia --project examples/mipt_example.jl` exits with code 0 and prints entropy values
- [x] All existing tests pass: `julia --project -e 'using Pkg; Pkg.test()'` → 244 passing (up from 212)
- [x] New Bricklayer/AllSites circuit tests pass

### Must Have
- Bricklayer deterministic gates work in Circuit simulate!
- AllSites deterministic gates work in Circuit simulate!
- Stochastic AllSites does per-site independent RNG draws from `:ctrl`
- Stochastic Bricklayer does per-pair independent RNG draws from `:ctrl`
- expand_circuit produces correct ExpandedOps for compound geometries
- expand_circuit + simulate! RNG consumption aligned
- mipt_example.jl uses Circuit do-block, NOT imperative loop
- mipt_tutorial.ipynb runs all cells without error

### Must NOT Have (Guardrails)
- NO geometry trait system or abstract compound geometry framework
- NO changes to Pointer geometry
- NO refactoring of existing Reset special-case logic (unless blocking)
- NO changes to existing StaircaseRight/StaircaseLeft/SingleSite/AdjacentPair paths
- NO plotting/visualization code in examples
- NO new geometry types
- NO changes to the imperative API (`src/Core/apply.jl`)
- NO changes to RNGRegistry design or new RNG streams

---

## Verification Strategy (MANDATORY)

### Test Decision
- **Infrastructure exists**: YES (Julia test framework with `@testset`)
- **User wants tests**: YES (Tests-after, integrated with existing test suite)
- **Framework**: Julia `Test` stdlib, run via `Pkg.test()`

### Automated Verification

Each task includes specific verification commands. The full test suite is:
```bash
julia --project -e 'using Pkg; Pkg.test()'
```

For MIPT example:
```bash
julia --project examples/mipt_example.jl
```

---

## Execution Strategy

### Parallel Execution Waves

```
Wave 1 (Start Immediately):
├── Task 1: Extend simulate! for compound geometries (deterministic + stochastic)
└── Task 2: Extend expand_circuit for compound geometries (validation + expansion + labels)

Wave 2 (After Wave 1):
├── Task 3: Add tests for Bricklayer/AllSites in Circuit API
├── Task 4: Rewrite mipt_example.jl to Circuit style
└── Task 5: Fix mipt_tutorial.ipynb

Wave 3 (After Wave 2):
└── Task 6: Full test suite + end-to-end verification

Critical Path: Task 1 → Task 3 → Task 6
Parallel Speedup: ~30% faster than sequential
```

### Dependency Matrix

| Task | Depends On | Blocks | Can Parallelize With |
|------|------------|--------|---------------------|
| 1 | None | 3, 4, 5 | 2 |
| 2 | None | 3, 4, 5 | 1 |
| 3 | 1, 2 | 6 | 4, 5 |
| 4 | 1 | 6 | 3, 5 |
| 5 | 1 | 6 | 3, 4 |
| 6 | 3, 4, 5 | None | None (final) |

### Agent Dispatch Summary

| Wave | Tasks | Recommended Agents |
|------|-------|-------------------|
| 1 | 1, 2 | delegate_task(category="deep", load_skills=[], run_in_background=true) each |
| 2 | 3, 4, 5 | delegate_task(category="quick", ...) for 4, 5; category="unspecified-low" for 3 |
| 3 | 6 | delegate_task(category="quick", ...) |

---

## TODOs

- [x] 1. Extend `simulate!` in execute.jl for compound geometries

  **What to do**:
  - Add helper function `is_compound_geometry(geo)` that returns `true` for `Bricklayer` and `AllSites`
  - Add helper function `get_compound_elements(geo, state)`:
    - For `AllSites`: returns `[[1], [2], ..., [L]]` (each site as a single-element vector)
    - For `Bricklayer`: returns `[[p1,p2], [p3,p4], ...]` (each pair from `get_pairs`)
  - Modify the **deterministic** path in `simulate!` (around line 118-122):
    - If `is_compound_geometry(op.geometry)`:
      - Get elements via `get_compound_elements(op.geometry, state)`
      - For each element, call `execute_gate!(state, op.gate, element)`
      - Count each element execution as a separate gate for `gate_idx` and recording
    - Else: keep current `compute_sites_dispatch` → `execute_gate!` path unchanged
  - Modify the **stochastic** path in `simulate!` (around line 126-145):
    - If any outcome's geometry is compound (`any(is_compound_geometry(o.geometry) for o in op.outcomes)`):
      - Determine elements from the first compound geometry found
      - For EACH element independently:
        - Draw `r = rand(actual_rng)` from `:ctrl` stream
        - Select branch using cumulative probability (same `r < cumulative` logic)
        - If branch selected: call `execute_gate!(state, outcome.gate, element)`
        - If "do nothing": skip this element
      - Each executed gate counts as a separate gate for `gate_idx` and recording
    - Else: keep current single-draw stochastic path unchanged
  - Update `execute_gate!` to handle Measurement gates (like Reset):
    - Add: `elseif gate isa Measurement` → `apply!(state, gate, SingleSite(sites[1]))` (for single-site measurement from compound expansion)

  **Must NOT do**:
  - Do NOT modify the existing StaircaseRight/StaircaseLeft/SingleSite/AdjacentPair code paths
  - Do NOT refactor the existing Reset special-case logic
  - Do NOT create geometry trait types or abstract compound geometry hierarchies
  - Do NOT change the recording system or RecordingContext

  **Recommended Agent Profile**:
  - **Category**: `deep`
    - Reason: Core engine modification requiring careful understanding of RNG consumption patterns and recording interactions
  - **Skills**: []
    - No special skills needed — this is pure Julia logic
  - **Skills Evaluated but Omitted**:
    - `playwright`: No browser interaction
    - `git-master`: Will commit at end, not during

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 1 (with Task 2)
  - **Blocks**: Tasks 3, 4, 5
  - **Blocked By**: None (can start immediately)

  **References** (CRITICAL - Be Exhaustive):

  **Pattern References** (existing code to follow):
  - `src/Circuit/execute.jl:96-184` — The `simulate!` function: lines 118-122 (deterministic path), lines 126-145 (stochastic path). This is the PRIMARY file to modify. Study the exact flow: `compute_sites_dispatch` → `execute_gate!`.
  - `src/Circuit/execute.jl:205-215` — `execute_gate!` function: shows existing Reset special-case pattern. Add Measurement handling here.
  - `src/Core/apply.jl:50-62` — `_apply_dispatch!` for Bricklayer and AllSites: shows the ITERATION PATTERN (loop over pairs/sites). This is the pattern to replicate in simulate!.
  - `src/Core/apply.jl:95-107` — `_apply_dispatch!` for Measurement: shows per-site measurement pattern using `_measure_single_site!`.
  - `src/Circuit/expand.jl:119-133` — `select_branch` function: shows the `r < cumulative` branch selection logic that must be replicated per-element for compound stochastic.

  **API/Type References** (contracts to implement against):
  - `src/Geometry/static.jl:41-77` — Bricklayer struct and `get_pairs()`: returns `Vector{Tuple{Int,Int}}`. Use this to get elements.
  - `src/Geometry/static.jl:85-92` — AllSites struct and `get_all_sites()`: returns `collect(1:state.L)`. Use this to get elements.
  - `src/Circuit/recording.jl:20-25` — RecordingContext struct: `gate_idx` must increment for EACH element execution, not once per compound geometry op.

  **WHY Each Reference Matters**:
  - `execute.jl:96-184`: This IS the file being modified. Understand the exact flow before changing it.
  - `apply.jl:50-62`: Shows HOW Bricklayer/AllSites iterate — replicate this in the Circuit path.
  - `apply.jl:95-107`: Shows that Measurement uses `_measure_single_site!` which consumes `:born` RNG. The Circuit path must trigger this same mechanism.
  - `expand.jl:119-133`: The stochastic branch selection logic that must be per-element for compound geometries.

  **Acceptance Criteria**:

  **Automated Verification:**
  ```bash
  # Test: deterministic Bricklayer in Circuit
  julia --project -e '
  using QuantumCircuitsMPS
  circuit = Circuit(L=4, bc=:periodic, n_steps=1) do c
      apply!(c, HaarRandom(), Bricklayer(:odd))
      apply!(c, HaarRandom(), Bricklayer(:even))
  end
  state = SimulationState(L=4, bc=:periodic, rng=RNGRegistry(ctrl=42, born=1, haar=2, proj=3))
  initialize!(state, ProductState(x0=0//1))
  simulate!(circuit, state; n_circuits=1)
  println("Bricklayer deterministic: OK")
  '
  # Assert: prints "Bricklayer deterministic: OK" with exit code 0

  # Test: stochastic AllSites (per-site) in Circuit
  julia --project -e '
  using QuantumCircuitsMPS
  circuit = Circuit(L=4, bc=:periodic, n_steps=1) do c
      apply!(c, HaarRandom(), Bricklayer(:odd))
      apply_with_prob!(c; rng=:ctrl, outcomes=[
          (probability=0.5, gate=Measurement(:Z), geometry=AllSites())
      ])
  end
  state = SimulationState(L=4, bc=:periodic, rng=RNGRegistry(ctrl=42, born=1, haar=2, proj=3))
  initialize!(state, ProductState(x0=0//1))
  simulate!(circuit, state; n_circuits=5)
  println("Stochastic AllSites per-site: OK")
  '
  # Assert: prints "Stochastic AllSites per-site: OK" with exit code 0

  # Test: RNG determinism — same seed → same result
  julia --project -e '
  using QuantumCircuitsMPS, ITensors, ITensorMPS
  circuit = Circuit(L=4, bc=:periodic, n_steps=1) do c
      apply!(c, HaarRandom(), Bricklayer(:odd))
      apply_with_prob!(c; rng=:ctrl, outcomes=[
          (probability=0.3, gate=Measurement(:Z), geometry=AllSites())
      ])
  end
  s1 = SimulationState(L=4, bc=:periodic, rng=RNGRegistry(ctrl=42, born=1, haar=2, proj=3))
  initialize!(s1, ProductState(x0=0//1))
  simulate!(circuit, s1; n_circuits=10)
  s2 = SimulationState(L=4, bc=:periodic, rng=RNGRegistry(ctrl=42, born=1, haar=2, proj=3))
  initialize!(s2, ProductState(x0=0//1))
  simulate!(circuit, s2; n_circuits=10)
  maxdiff = maximum(abs.(array(s1.mps[i]) - array(s2.mps[i])) for i in 1:4)
  @assert maxdiff < 1e-14 "RNG determinism failed: maxdiff=$maxdiff"
  println("RNG determinism: OK (maxdiff=$maxdiff)")
  '
  # Assert: prints "RNG determinism: OK" with exit code 0
  ```

  **Commit**: YES (groups with Task 2)
  - Message: `feat(circuit): extend simulate! and expand_circuit for Bricklayer/AllSites geometries`
  - Files: `src/Circuit/execute.jl`, `src/Circuit/expand.jl`
  - Pre-commit: `julia --project -e 'using Pkg; Pkg.test()'`

---

- [x] 2. Extend `expand_circuit` for compound geometries

  **What to do**:
  - In `src/Circuit/expand.jl`, update `validate_geometry` (lines 72-85) to accept Bricklayer and AllSites:
    - Add `elseif geo isa Bricklayer` and `elseif geo isa AllSites` branches
  - Add `gate_label(::Measurement)` to return `"Meas"` (or `"M"`) for visualization
  - Modify `expand_circuit` (lines 204-260) to handle compound geometries:
    - **Deterministic compound**: produce multiple ExpandedOps, one per element
      - Bricklayer: one ExpandedOp per pair from `get_pairs`-style logic (compute pairs from L, bc, parity)
      - AllSites: one ExpandedOp per site (sites 1:L)
    - **Stochastic compound**: iterate per-element with independent RNG draws
      - For each element: call `select_branch(rng, outcomes)` (consumes ONE draw per element)
      - If branch selected: produce ExpandedOp for that element
      - If "do nothing": skip (no ExpandedOp for that element)
  - Helper functions needed (since expand_circuit doesn't have a SimulationState, compute pairs from L/bc directly):
    - `compute_bricklayer_pairs(parity::Symbol, L::Int, bc::Symbol)` → `Vector{Vector{Int}}`
    - `compute_allsites_elements(L::Int)` → `Vector{Vector{Int}}`

  **Must NOT do**:
  - Do NOT change the ExpandedOp struct (just produce more of them)
  - Do NOT modify behavior for existing geometry types (StaircaseRight, etc.)
  - Do NOT change select_branch logic

  **Recommended Agent Profile**:
  - **Category**: `deep`
    - Reason: Must precisely match RNG consumption pattern with simulate!
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 1 (with Task 1)
  - **Blocks**: Tasks 3, 4, 5
  - **Blocked By**: None (can start immediately)

  **References**:

  **Pattern References**:
  - `src/Circuit/expand.jl:72-85` — `validate_geometry`: add Bricklayer/AllSites branches here
  - `src/Circuit/expand.jl:49-56` — `gate_label` dispatch: add Measurement label here
  - `src/Circuit/expand.jl:204-260` — `expand_circuit`: the main function to extend
  - `src/Circuit/expand.jl:119-133` — `select_branch`: reused per-element for stochastic compound
  - `src/Geometry/static.jl:55-77` — `get_pairs` logic: replicate pair computation from L/bc/parity (no state available in expand_circuit)
  - `src/Geometry/static.jl:85-92` — AllSites pattern: just 1:L

  **WHY Each Reference Matters**:
  - `expand.jl:204-260`: This IS the function being extended. The existing pattern for deterministic and stochastic ops must be followed.
  - `static.jl:55-77`: `get_pairs` uses state (needs L and bc), but `expand_circuit` only has circuit.L and circuit.bc. Must compute pairs from those instead.
  - `expand.jl:119-133`: `select_branch` consumes ONE draw. For compound stochastic, call it per-element.

  **Acceptance Criteria**:

  ```bash
  # Test: expand_circuit with Bricklayer produces correct ExpandedOps
  julia --project -e '
  using QuantumCircuitsMPS
  circuit = Circuit(L=4, bc=:periodic, n_steps=1) do c
      apply!(c, HaarRandom(), Bricklayer(:odd))
  end
  ops = expand_circuit(circuit; seed=42)
  @assert length(ops) == 1  # 1 step
  @assert length(ops[1]) == 2  # 2 pairs for L=4 odd: (1,2), (3,4)
  @assert ops[1][1].sites == [1, 2]
  @assert ops[1][2].sites == [3, 4]
  println("expand_circuit Bricklayer: OK")
  '
  # Assert: prints OK with exit code 0

  # Test: expand_circuit with AllSites
  julia --project -e '
  using QuantumCircuitsMPS
  circuit = Circuit(L=4, bc=:periodic, n_steps=1) do c
      apply!(c, PauliX(), AllSites())
  end
  ops = expand_circuit(circuit; seed=42)
  @assert length(ops[1]) == 4  # 4 sites
  @assert ops[1][1].sites == [1]
  @assert ops[1][4].sites == [4]
  println("expand_circuit AllSites: OK")
  '
  # Assert: prints OK with exit code 0

  # Test: Measurement label
  julia --project -e '
  using QuantumCircuitsMPS
  circuit = Circuit(L=4, bc=:periodic, n_steps=1) do c
      apply!(c, Measurement(:Z), AllSites())
  end
  ops = expand_circuit(circuit; seed=42)
  @assert length(ops[1]) == 4
  label = ops[1][1].label
  @assert label in ["Meas", "M", "Msr"]  # Accept any reasonable label
  println("Measurement label: OK (label=$label)")
  '
  # Assert: prints OK with exit code 0
  ```

  **Commit**: YES (groups with Task 1)
  - Message: `feat(circuit): extend simulate! and expand_circuit for Bricklayer/AllSites geometries`
  - Files: `src/Circuit/expand.jl`
  - Pre-commit: `julia --project -e 'using Pkg; Pkg.test()'`

---

- [x] 3. Add tests for Bricklayer/AllSites in Circuit execution

  **What to do**:
  - Add new `@testset` blocks to `test/circuit_test.jl` (or create `test/circuit_compound_test.jl` if circuit_test.jl is too large):
    - Test: Deterministic Bricklayer(:odd) + Bricklayer(:even) in Circuit + simulate!
    - Test: Deterministic AllSites with PauliX in Circuit + simulate!
    - Test: Stochastic AllSites with Measurement(:Z) — per-site independent decisions
    - Test: RNG determinism — same seed produces identical MPS for compound stochastic
    - Test: expand_circuit produces correct ExpandedOps for Bricklayer (correct pairs, OBC vs PBC)
    - Test: expand_circuit produces correct ExpandedOps for AllSites (L entries)
    - Test: expand_circuit + simulate! RNG alignment (same seed → same branch selections)
    - Test: Empty Bricklayer (L=2, bc=:open, parity=:even) — should be no-op, no error
    - Test: EntanglementEntropy tracking works with compound geometry circuit (record + access)
  - Use existing test patterns from `test/circuit_test.jl` for structure

  **Must NOT do**:
  - Do NOT modify existing test cases
  - Do NOT add physics-specific tests (entropy values, phase transitions) — those go in Task 6
  - Do NOT add tests for Pointer or other geometries

  **Recommended Agent Profile**:
  - **Category**: `unspecified-low`
    - Reason: Straightforward test writing following existing patterns
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 2 (with Tasks 4, 5)
  - **Blocks**: Task 6
  - **Blocked By**: Tasks 1, 2

  **References**:
  - `test/circuit_test.jl` — Existing circuit test structure and patterns. Follow same `@testset` style.
  - `test/entanglement_test.jl` — Shows how to test EntanglementEntropy with SimulationState.
  - `src/Geometry/static.jl:55-77` — Bricklayer pair computation logic (for expected test values).
  - Task 1 acceptance criteria — Contains inline test code that should be formalized here.

  **Acceptance Criteria**:
  ```bash
  julia --project -e 'using Pkg; Pkg.test()'
  # Assert: All tests pass, new compound geometry tests included
  # Assert: Test count increased (was 212)
  ```

  **Commit**: YES
  - Message: `test(circuit): add tests for Bricklayer and AllSites compound geometries`
  - Files: `test/circuit_test.jl` (or new test file)
  - Pre-commit: `julia --project -e 'using Pkg; Pkg.test()'`

---

- [x] 4. Rewrite `mipt_example.jl` to Circuit API

  **What to do**:
  - Rewrite `examples/mipt_example.jl` to use Circuit do-block API instead of imperative loop
  - Keep the same physics: L=12, bc=:periodic, p=0.15, cut=L÷2, 50 timesteps
  - Structure:
    1. Parameters section (keep as-is)
    2. Build Circuit with `n_steps=1`:
       ```julia
       circuit = Circuit(L=L, bc=bc, n_steps=1) do c
           apply!(c, HaarRandom(), Bricklayer(:odd))
           apply!(c, HaarRandom(), Bricklayer(:even))
           apply_with_prob!(c; rng=:ctrl, outcomes=[
               (probability=p, gate=Measurement(:Z), geometry=AllSites())
           ])
       end
       ```
    3. Create SimulationState with RNGRegistry, initialize!, track!
    4. simulate!(circuit, state; n_circuits=50, record_when=:every_step)
    5. Access entropy via state.observables[:entropy]
    6. Print results section (adapted from current)
  - Keep all existing comments about MIPT physics
  - Remove imperative-specific code (manual loop, get_rng, per-site rand)

  **Must NOT do**:
  - Do NOT change physics parameters (L, p, n_steps=50 total)
  - Do NOT add plotting code
  - Do NOT add new observables beyond entropy
  - Do NOT add performance benchmarks
  - Do NOT increase line count by >20% unless justified by Circuit API verbosity

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Straightforward API translation, pattern clear from circuit_tutorial.jl
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 2 (with Tasks 3, 5)
  - **Blocks**: Task 6
  - **Blocked By**: Task 1

  **References**:
  - `examples/mipt_example.jl` — Current imperative implementation. Keep physics comments, replace code.
  - `examples/circuit_tutorial.jl:186-200` — Circuit API pattern: SimulationState → initialize! → simulate!. THIS is the pattern to follow.
  - `examples/circuit_tutorial.jl:67-72` — Circuit do-block construction pattern.
  - `examples/circuit_tutorial.jl:233-237` — track! + record! + simulate! pattern.
  - `src/Circuit/execute.jl:42-48` — simulate! API: `simulate!(circuit, state; n_circuits=N, record_when=:every_step)`

  **WHY Each Reference Matters**:
  - `mipt_example.jl`: Current file to rewrite. Preserve physics explanation comments, replace imperative code.
  - `circuit_tutorial.jl:186-200`: Shows the EXACT pattern for creating state and running circuit. This is the template.
  - `circuit_tutorial.jl:233-237`: Shows track!/record!/simulate! flow that must be replicated.

  **Acceptance Criteria**:
  ```bash
  julia --project examples/mipt_example.jl
  # Assert: Exit code 0
  # Assert: Output contains "Simulation complete!"
  # Assert: Output contains "Entanglement entropy"
  # Assert: Output contains entropy values at step 10, 20, 30, 40, 50
  ```

  **Commit**: YES (groups with Task 5)
  - Message: `refactor(examples): rewrite MIPT example and tutorial to use Circuit API`
  - Files: `examples/mipt_example.jl`, `examples/mipt_tutorial.ipynb`
  - Pre-commit: `julia --project examples/mipt_example.jl`

---

- [x] 5. Fix `mipt_tutorial.ipynb`

  **What to do**:
  - Fix Section 2 (Circuit building): use n_steps=1 (one timestep per circuit run), keep Bricklayer and AllSites
  - Fix Section 3 (Simulation):
    - Replace `x0 = ProductState(fill(1//2, L))` → proper state creation with RNGRegistry
    - Replace `state = SimulationState(circuit, x0)` → keyword constructor with L, bc, rng
    - Add `initialize!(state, ProductState(x0=0//1))` for |0⟩⊗L
    - Add `track!(state, :entropy => EntanglementEntropy(; cut=cut))`
    - Replace `simulate!(state; ctrl_rng=:seed, ...)` → `simulate!(circuit, state; n_circuits=n_steps, record_when=:every_step)`
    - Replace `result.observables[:entropy]` → `state.observables[:entropy]`
  - Fix Section 4 (Results): update entropy access to use correct variable
  - Keep all markdown explanations unless they reference wrong API
  - Clear all cell outputs (fresh notebook)
  - Update parameter section to include n_steps separately from Circuit construction (since Circuit uses n_steps=1 internally)

  **Must NOT do**:
  - Do NOT rewrite cells not affected by bugs
  - Do NOT add new cells
  - Do NOT change markdown physics explanations
  - Do NOT add plotting code

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Direct bug fixes following pattern from mipt_example.jl rewrite
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 2 (with Tasks 3, 4)
  - **Blocks**: Task 6
  - **Blocked By**: Task 1

  **References**:
  - `examples/mipt_tutorial.ipynb` — Current broken notebook. Fix cells 3 (Section 2) and 4 (Section 3) primarily.
  - `examples/mipt_example.jl` — After Task 4 rewrites this, use it as the template for notebook code.
  - `src/State/initialization.jl:22-29` — ProductState constructor: `ProductState(; x0::Union{Rational, Integer})`. Shows correct usage: `ProductState(x0=0//1)`.
  - `src/State/State.jl:47-79` — SimulationState constructor: keyword args `L, bc, local_dim, cutoff, maxdim, rng`.
  - `src/Observables/Observables.jl:23-28` — track! API: `track!(state, :name => observable)`.

  **WHY Each Reference Matters**:
  - `mipt_tutorial.ipynb`: This IS the file being fixed. Know which cells have bugs.
  - `initialization.jl:22-29`: Shows the EXACT ProductState constructor signature — the root cause of bug #1.
  - `State.jl:47-79`: Shows the EXACT SimulationState constructor — the root cause of bug #2.

  **Acceptance Criteria**:
  ```bash
  # Test: Run notebook cells as script to verify no errors
  julia --project -e '
  using QuantumCircuitsMPS
  using Printf

  L = 4; bc = :periodic; n_steps = 50; p = 0.15; cut = L ÷ 2

  circuit = Circuit(L=L, bc=bc, n_steps=1) do c
      apply!(c, HaarRandom(), Bricklayer(:odd))
      apply!(c, HaarRandom(), Bricklayer(:even))
      apply_with_prob!(c; rng=:ctrl, outcomes=[
          (probability=p, gate=Measurement(:Z), geometry=AllSites())
      ])
  end

  state = SimulationState(L=L, bc=bc, rng=RNGRegistry(ctrl=42, born=1, haar=2, proj=3))
  initialize!(state, ProductState(x0=0//1))
  track!(state, :entropy => EntanglementEntropy(; cut=cut))
  simulate!(circuit, state; n_circuits=n_steps, record_when=:every_step)
  entropy_vals = state.observables[:entropy]
  @assert length(entropy_vals) == n_steps "Expected $n_steps entropy values, got $(length(entropy_vals))"
  @assert all(e -> e >= 0, entropy_vals) "Negative entropy values found"
  println("Tutorial code works! Got $(length(entropy_vals)) entropy values")
  println("Final entropy: $(entropy_vals[end])")
  '
  # Assert: prints success message with exit code 0
  ```

  **Commit**: YES (groups with Task 4)
  - Message: `refactor(examples): rewrite MIPT example and tutorial to use Circuit API`
  - Files: `examples/mipt_tutorial.ipynb`
  - Pre-commit: run acceptance criteria script above

---

- [x] 6. Full test suite + end-to-end verification

  **What to do**:
  - Run full test suite: `julia --project -e 'using Pkg; Pkg.test()'`
  - Verify all existing tests pass (no regressions from compound geometry changes)
  - Run `julia --project examples/mipt_example.jl` — verify complete output
  - Verify entropy values are physically reasonable:
    - Initial entropy near 0 (product state)
    - Entropy grows over timesteps
    - Entropy non-negative throughout
  - If any test fails: diagnose and fix (this is the integration verification step)

  **Must NOT do**:
  - Do NOT add new features
  - Do NOT optimize performance
  - Do NOT refactor code for style

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Just running tests and verifying
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Wave 3 (sequential, after all others)
  - **Blocks**: None (final task)
  - **Blocked By**: Tasks 3, 4, 5

  **References**:
  - `test/runtests.jl` — Test entry point
  - All test files in `test/` directory
  - `examples/mipt_example.jl` — End-to-end example to verify

  **Acceptance Criteria**:
  ```bash
  # Full test suite
  julia --project -e 'using Pkg; Pkg.test()'
  # Assert: All tests pass (212+ tests, 0 failures)

  # MIPT example end-to-end
  julia --project examples/mipt_example.jl
  # Assert: Exit code 0
  # Assert: Output contains "Step 50: Entanglement entropy = "
  # Assert: Output contains "Simulation complete!"

  # Physics sanity check
  julia --project -e '
  using QuantumCircuitsMPS
  circuit = Circuit(L=4, bc=:periodic, n_steps=1) do c
      apply!(c, HaarRandom(), Bricklayer(:odd))
      apply!(c, HaarRandom(), Bricklayer(:even))
      apply_with_prob!(c; rng=:ctrl, outcomes=[
          (probability=0.15, gate=Measurement(:Z), geometry=AllSites())
      ])
  end
  state = SimulationState(L=4, bc=:periodic, rng=RNGRegistry(ctrl=42, born=1, haar=2, proj=3))
  initialize!(state, ProductState(x0=0//1))
  track!(state, :entropy => EntanglementEntropy(; cut=2))
  simulate!(circuit, state; n_circuits=50, record_when=:every_step)
  ev = state.observables[:entropy]
  @assert length(ev) == 50 "Expected 50 values"
  @assert ev[1] >= 0 "Entropy must be non-negative"
  @assert ev[end] >= 0 "Entropy must be non-negative"
  println("Physics sanity: OK (50 entropy values, all non-negative)")
  println("  Initial: $(ev[1])")
  println("  Final: $(ev[end])")
  '
  # Assert: Exit code 0, prints sanity check results
  ```

  **Commit**: NO (verification only)

---

- [x] 7. Clarify EntanglementEntropy docstring for Hartley entropy (order=0)

  **What to do**:
  - Update the docstring in `src/Observables/entanglement.jl` for `EntanglementEntropy`:
    - Change the `order` parameter documentation to clarify that `order=0` (Hartley entropy) is NOT supported via this interface
    - Explain WHY: numerically, "zero" singular values are never truly zero (~1e-10), so `log(rank)` gives `log(maxdim)` instead of `log(true_rank)` — making Hartley entropy unreliable and threshold-dependent
    - Suggest alternative: users who need Hartley entropy should access the MPS singular values directly via `orthogonalize` + `svd` and apply their own threshold to determine rank
    - Remove the misleading `order=0: Hartley entropy (log of Schmidt rank)` from the docstring bullet list
  - Keep the validation `order >= 1` as-is (this is intentional)
  - Keep the dead `elseif n == 0` branch in `_von_neumann_entropy` — it's harmless and may be useful if the interface is ever extended

  **Must NOT do**:
  - Do NOT change the validation logic
  - Do NOT remove the n==0 code branch
  - Do NOT change any computation logic

  **Recommended Agent Profile**:
  - **Category**: `quick`
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES (with any Wave 2 task)
  - **Parallel Group**: Wave 2
  - **Blocks**: None
  - **Blocked By**: None

  **References**:
  - `src/Observables/entanglement.jl:1-39` — The docstring and constructor to update
  - `src/Observables/entanglement.jl:76-105` — The `_von_neumann_entropy` function (keep as-is, just note dead branch)

  **Acceptance Criteria**:
  ```bash
  # Verify order=0 still throws (validation unchanged)
  julia --project -e '
  using QuantumCircuitsMPS
  try
      EntanglementEntropy(cut=2, order=0)
      println("ERROR: should have thrown")
      exit(1)
  catch e
      @assert e isa ArgumentError
      println("Correctly throws for order=0: OK")
  end
  '
  # Assert: prints "Correctly throws for order=0: OK"
  ```

  **Commit**: YES (groups with Tasks 4+5)
  - Message: `refactor(examples): rewrite MIPT example and tutorial to use Circuit API`
  - Files: `src/Observables/entanglement.jl`

---

## Commit Strategy

| After Task | Message | Files | Verification |
|------------|---------|-------|--------------|
| 1+2 | `feat(circuit): extend simulate! and expand_circuit for Bricklayer/AllSites geometries` | `src/Circuit/execute.jl`, `src/Circuit/expand.jl` | `Pkg.test()` |
| 3 | `test(circuit): add tests for Bricklayer and AllSites compound geometries` | `test/circuit_test.jl` (or new file) | `Pkg.test()` |
| 4+5+7 | `refactor(examples): rewrite MIPT example and tutorial to use Circuit API` | `examples/mipt_example.jl`, `examples/mipt_tutorial.ipynb`, `src/Observables/entanglement.jl` | `julia examples/mipt_example.jl` |

---

## Success Criteria

### Verification Commands
```bash
# Full test suite passes
julia --project -e 'using Pkg; Pkg.test()'

# MIPT example runs
julia --project examples/mipt_example.jl

# Quick smoke test for compound geometry Circuit
julia --project -e '
using QuantumCircuitsMPS
c = Circuit(L=4, bc=:periodic, n_steps=1) do c
    apply!(c, HaarRandom(), Bricklayer(:odd))
    apply_with_prob!(c; rng=:ctrl, outcomes=[
        (probability=0.5, gate=Measurement(:Z), geometry=AllSites())
    ])
end
s = SimulationState(L=4, bc=:periodic, rng=RNGRegistry(ctrl=1, born=2, haar=3, proj=4))
initialize!(s, ProductState(x0=0//1))
simulate!(c, s; n_circuits=1)
println("Compound geometry Circuit: OK")
'
```

### Final Checklist
- [x] All "Must Have" present
- [x] All "Must NOT Have" absent
- [x] All existing tests pass (no regressions) - 244/246 pass (2 pre-existing broken)
- [x] New compound geometry tests pass
- [x] mipt_example.jl runs end-to-end with Circuit API
- [x] mipt_tutorial.ipynb code is correct (verified via script extraction)
