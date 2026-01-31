# Circuit Visualization & Lazy Mode API

## TL;DR

> **Quick Summary**: Add lazy/symbolic circuit representation to QuantumCircuitsMPS.jl enabling circuit visualization (ASCII + SVG) before execution. Circuits are built first, then optionally plotted, then simulated.
> 
> **Deliverables**:
> - `Circuit` type with internal NamedTuple-based operation storage
> - Pure `compute_sites()` functions for symbolic geometry expansion
> - ASCII circuit visualization (`print_circuit`)
> - SVG circuit visualization via Luxor.jl extension (`plot_circuit`)
> - Circuit executor (`simulate!`)
> - Updated examples demonstrating new API
> 
> **Estimated Effort**: Large (1-2 weeks)
> **Parallel Execution**: YES - 3 waves
> **Critical Path**: Task 1 → Task 3 → Task 5 → Task 8 → Task 11

---

## Context

### Original Request
Add plotting utilities for rendering quantum circuits. This requires transitioning from imperative execution (`apply_with_prob!(state, ...)`) to a lazy/symbolic circuit representation that can be visualized before execution.

### Interview Summary
**Key Discussions**:
- **Architecture**: Circuit-first (Build → Plot → Simulate). Circuit is UPSTREAM of execution.
- **API Style**: Do-Block style selected: `Circuit(L=10) do c; ...; end`
- **Old API**: Full replacement - current imperative API will be deprecated (not in Phase 1)
- **Granularity**: Support both single-step AND full L-step circuits
- **Branching Display**: Show ONE sampled path based on RNG seed (not all branches)
- **Measurements**: Display as "M" without predicting outcome
- **Output Formats**: ASCII (always available) + SVG (Luxor.jl optional extension)
- **Tests**: Write tests after implementation

**Research Findings**:
- Luxor.jl is standard for circuit diagrams in Julia (used by YaoPlots.jl)
- Package dependencies: ITensors, ITensorMPS, JSON, LinearAlgebra, Random
- Current geometries are **mutable** (`StaircaseLeft/Right` have `_position` pointer)
- Existing `NamedTuple{(:probability,:gate,:geometry)}` pattern in `src/API/probabilistic.jl:46`

### Metis Review
**Identified Gaps** (addressed in plan):
1. **Geometry Immutability**: Current geometries mutate. Solution: Add pure `compute_sites(start, step, L, bc)` functions that don't depend on geometry object mutation.
2. **RNG Alignment**: `plot(seed=42)` and `simulate!(seed=42)` must produce same branches. Solution: Same RNG consumption algorithm in both paths.
3. **Multi-site Geometries**: `Bricklayer`, `AllSites` have complex expansion. Solution: Defer to Phase 2, support only `StaircaseLeft/Right` and `SingleSite`/`AdjacentPair` initially.
4. **Existing AbstractCircuit**: `MonitoredCircuit` and `AbstractCircuit` exist in deprecated/example code (`src/_deprecated/Core/types.jl`, `examples/monitored_circuit.jl`) but are NOT part of the current exported API. Solution: New `Circuit` is independent type, no inheritance, no integration constraint.

---

## Circuit Semantics (CRITICAL - Read Before Implementation)

> **IMPORTANT**: This section is the AUTHORITATIVE source for semantics.
> All algorithms are inlined in this plan. No external draft files are referenced.

### Time Axis Definition
- `Circuit.operations`: Operations for ONE logical step (a "step template")
- `Circuit.n_steps`: Number of times to repeat the step template
- `Circuit.L`: System size (number of qubits)
- **Total expanded steps** = `n_steps` (NOT `L * n_steps`)

**Example**: `Circuit(L=4, bc=:periodic, n_steps=4)` with one stochastic operation produces:
- 4 expanded steps (step 1, 2, 3, 4)
- At each step, the staircase geometry advances based on `step` index

### Within-Step Semantics (CRITICAL - Multi-Op Handling)

**Circuit.operations ordering**: Operations are stored in insertion order and executed **SEQUENTIALLY** within each step.

**Rules for Phase 1**:
1. **Sequential Execution**: Operations within a step execute in the order they were added via `apply!`/`apply_with_prob!`
2. **No Site-Overlap Validation**: Phase 1 does NOT validate site overlap between operations. If two ops target the same site in the same step, they execute sequentially (second op sees result of first)
3. **Visualization**: Each operation in a step gets its own column. Multiple ops = multiple columns for that logical step

**Example**:
```julia
circuit = Circuit(L=4, bc=:periodic, n_steps=2) do c
    apply!(c, Reset(), StaircaseRight(1))      # Op 1: position advances per step
    apply!(c, HaarRandom(), StaircaseLeft(4))  # Op 2: different staircase
end
# At step 1: Op1 acts on site 1, then Op2 acts on sites [4,1] (sequential)
# At step 2: Op1 acts on site 2, then Op2 acts on sites [3,4]
```

**Expansion Output**: `Vector{Vector{ExpandedOp}}` preserves insertion order within each inner vector:
```julia
ops = expand_circuit(circuit; seed=0)
# ops[1] = [ExpandedOp(op1...), ExpandedOp(op2...)]  # Order preserved
```

### `expand_circuit` Output Contract
**Return type**: `Vector{Vector{ExpandedOp}}` where outer vector length = `n_steps`
- `ops[step]` = all operations that happen at that step
- Each step may have 0, 1, or more `ExpandedOp` entries depending on circuit definition
- **"Do nothing" branches** (probability sum < 1 and RNG hits empty slot): produce NO entry for that step/op

**Multi-Op Step with Do-Nothing Clarification**:
When a step has multiple operations defined but some hit "do nothing":
- `expand_circuit` outputs ONLY the operations that actually execute (no placeholders)
- Example: 2 ops defined, op1 executes, op2 is do-nothing → `ops[step] = [ExpandedOp(op1)]` (length 1)
- Visualization handles this by rendering columns ONLY for executed ops (see Task 6 rendering rules)
- This means column count can vary per step, which is acceptable in Phase 1

**Example**:
```julia
# Circuit with 1 stochastic operation, 4 steps
ops = expand_circuit(circuit; seed=42)
length(ops) == 4  # Always equals n_steps
# ops[1] might be empty Vector{ExpandedOp} if "do nothing" was selected
# ops[2] might have [ExpandedOp(step=2, gate=Reset(), sites=[2], label="Rst")]
```

### `n_circuits` in `simulate!`
- `n_circuits`: Number of circuit repetitions for statistics
- Each circuit = full `n_steps` execution
- `simulate!(circuit, state; n_circuits=100)` runs the circuit 100 times

**State Evolution Semantics** (CRITICAL):
Repetitions **continue evolving the SAME state** - there is NO reset between circuits.
- Circuit 1 executes on `state`, producing evolved state₁
- Circuit 2 executes on state₁, producing evolved state₂
- ... and so on

This matches the existing pattern in `src/API/simulation_styles/style_callback.jl` where repeated timesteps evolve the same MPS without reset.

**Why no reset**: Resetting would require an "initial state specification" (which ProductState to use, etc.). Phase 1 keeps it simple: the user initializes once with `initialize!(state, ProductState(...))`, then `simulate!` evolves forward.

**Consequence**: "Independent repetitions" means independent RNG draws, NOT independent initial states. Observable tracking captures the ongoing evolution trajectory.

### `simulate!` Recording Contract (CRITICAL)
The `simulate!` function records observables with this cadence:

```
Initial record (before any gates)  →  record!(state)
Execute circuit 1 (all n_steps)    →  record!(state)
Execute circuit 2 (all n_steps)    →  record!(state)
...
Execute circuit N (all n_steps)    →  record!(state) (final)
```

**API Note**: The repo's `record!` signature is `record!(state; i1=nothing)` (see `src/Observables/Observables.jl:38`).
Do NOT pass step indices to `record!` - it doesn't accept them. Recording simply appends current observable values.

**Concrete behavior**:
- `record_initial=true` (default): Call `record!(state)` before first circuit
- After EVERY circuit repetition: Call `record!(state)`
- `record_every::Int` (default=1): Record after every Nth circuit (1=every circuit, 10=every 10th)
- Final circuit ALWAYS records regardless of `record_every`

**Phase 1 `simulate!` Signature**:
```julia
function simulate!(
    circuit::Circuit, 
    state::SimulationState; 
    n_circuits::Int=1,
    record_initial::Bool=true,
    record_every::Int=1
)
```

**Expected Observable Length Formula**:
```
n_records = (record_initial ? 1 : 0) + 
            floor(Int, (n_circuits - 1) / record_every) + 
            1  # final always records
```

**Examples**:
- `n_circuits=5, record_initial=true, record_every=1` → 6 records (1 initial + 5 circuits)
- `n_circuits=10, record_initial=false, record_every=2` → 5 records (circuits 2,4,6,8,10 → but 10 always records → 5 records)
- `n_circuits=1, record_initial=true, record_every=1` → 2 records (initial + 1 circuit)

**DomainWall requirement**: The repo's `record!` supports TWO approaches for DomainWall i1:
1. **Register with `i1_fn`** (RECOMMENDED for circuit simulate!):
   ```julia
   track!(state, :dw => DomainWall(order=1, i1_fn=() -> 1))
   record!(state)  # Automatically calls i1_fn
   ```
2. **Pass `i1` at record time**:
   ```julia
   track!(state, :dw => DomainWall(order=1))
   record!(state; i1=current_position)  # Must pass i1 explicitly
   ```

**For circuit `simulate!`, approach 1 (i1_fn) is REQUIRED** because there's no dynamic position to track.
If using approach 2, `simulate!` would need an `i1` parameter to pass through - NOT supported in Phase 1.

### Geometry Mutation Rule (CRITICAL)
**`simulate!` and `expand_circuit` MUST NOT mutate geometry objects.**

- Current `apply!(state, gate, geo::AbstractStaircase)` calls `advance!(geo, ...)` - this MUTATES the geometry
- Circuit-based execution CANNOT use this dispatch
- Instead: `simulate!` must call `apply!(state, gate, sites::Vector{Int})` directly
- Sites are computed via `compute_site_staircase_*(start, step, L, bc)` at each step

**Why**: Circuits must be reusable. Running `simulate!` twice on the same circuit must produce identical behavior.

### Staircase + Gate Support Rules (Phase 1)
**For Circuit expansion, staircase geometry produces sites based on the GATE:**

| Gate | `support(gate)` | Staircase produces | Current `apply!` behavior |
|------|-----------------|-------------------|---------------------------|
| `Reset` | 1 | Single site: `[pos]` | Special-cased in `apply.jl:94-108` |
| `Projection` | 1 | Single site: `[pos]` | **NEW**: Must use `apply!(state, gate, [site])` |
| `PauliX/Y/Z` | 1 | Single site: `[pos]` | **NEW**: Must use `apply!(state, gate, [site])` |
| `HaarRandom` | 2 | Pair: `[pos, pos+1]` | Uses `get_sites()` returning pair |
| `CZ` | 2 | Pair: `[pos, pos+1]` | Uses `get_sites()` returning pair |

**Note**: This differs from current imperative API where `apply!(state, PauliX(), StaircaseRight(1))` would error (PauliX support=1 but staircase returns pair). In Circuit mode, we use the gate's support to determine expansion.

### Reset Execution Rule (CRITICAL)
**`Reset` is a special gate that CANNOT use `apply!(state, gate, sites::Vector{Int})` because its `build_operator` method intentionally throws an error (see `src/Gates/composite.jl:12-17`).**

This is by design: Reset involves measurement + conditional flip, which cannot be represented as a simple tensor operator.

The executor (`simulate!`) MUST special-case `Reset`:
```julia
# In execute_step! when processing an operation that selected Reset:
if gate isa Reset
    # Use SingleSite geometry wrapper to trigger correct dispatch
    apply!(state, gate, SingleSite(computed_site))
    # This calls _apply_dispatch!(state, ::Reset, ::SingleSite) in apply.jl:73-92
else
    # Normal gates: use sites vector
    apply!(state, gate, sites)
end
```

**Why this works**: `SingleSite` is an immutable static geometry (no `advance!` is called for it).
The dispatch to `_apply_dispatch!(state, ::Reset, ::SingleSite)` handles:
1. Born probability computation
2. RNG sampling for measurement outcome
3. Projection application
4. Conditional PauliX flip

**Reference**: See `src/Core/apply.jl:73-92` for the `Reset + SingleSite` handler.

### Unsupported Geometry Handling (Phase 1)

**Supported geometries for circuit expansion**:
- `StaircaseRight`, `StaircaseLeft` (via `compute_site_staircase_*` functions)
- `SingleSite`, `AdjacentPair` (static geometries)

**Unsupported geometries**: `Bricklayer`, `AllSites`, `Pointer`, any custom `AbstractGeometry` subtype.

**Failure Mode** (MANDATORY):
When `expand_circuit` or `simulate!` encounters an unsupported geometry, throw `ArgumentError` immediately:

```julia
function validate_geometry(geo::AbstractGeometry)
    # Pattern-match on geometry type - no custom circuit operation types needed
    if geo isa StaircaseRight
        # supported
    elseif geo isa StaircaseLeft
        # supported
    elseif geo isa SingleSite || geo isa AdjacentPair
        # supported (static)
    else
        throw(ArgumentError("Phase 1 does not support geometry type $(typeof(geo)). " *
                            "Supported: StaircaseRight, StaircaseLeft, SingleSite, AdjacentPair"))
    end
end
```

**Same validation in `simulate!`**: If a circuit somehow bypasses expansion (e.g., directly constructed), the executor must also validate geometry types before attempting to compute sites.

### Geometry Validation Strategy (EXPLICIT IMPLEMENTATION GUIDE)

**WHERE the validation function lives**: `src/Circuit/types.jl`
- Define `validate_geometry(geo::AbstractGeometry)` once, shared by both expand and execute
- Export: NO (internal implementation detail)

**WHO calls it and WHEN**:

1. **DO NOT validate at circuit construction** (`CircuitBuilder`)
   - Accept any geometry for forward compatibility (Phase 2 may support more)
   - User can build circuits with unsupported geometries; they fail at expand/execute

2. **`expand_circuit` calls `validate_geometry`** (`src/Circuit/expand.jl`):
   ```julia
   for op in circuit.operations
       if op.type == :deterministic
           validate_geometry(op.geometry)  # Throws if unsupported
           sites = compute_sites(...)
       elseif op.type == :stochastic
           for outcome in op.outcomes
               validate_geometry(outcome.geometry)  # Validate ALL branches
           end
           # Then proceed with RNG draw
       end
   end
   ```

3. **`simulate!` calls `validate_geometry`** (`src/Circuit/execute.jl`):
   ```julia
   # Same pattern as expand_circuit - validate before computing sites
   validate_geometry(op.geometry)  # or outcome.geometry for stochastic
   ```

**WHY both places**: 
- `expand_circuit` catches errors during visualization
- `simulate!` catches errors if user constructs Circuit directly (bypassing expand)
- DRY: Both call the same function from types.jl

### Validation Responsibility Matrix

**Who validates what**:

| Validation | Location | Error Type | When |
|------------|----------|------------|------|
| `rng == :ctrl` | `CircuitBuilder.apply_with_prob!` | `ArgumentError` | At circuit construction |
| Probability sum ≤ 1 | `CircuitBuilder.apply_with_prob!` | `ArgumentError` | At circuit construction |
| Non-empty outcomes | `CircuitBuilder.apply_with_prob!` | `ArgumentError` | At circuit construction |
| Supported geometry | `expand_circuit` / `simulate!` | `ArgumentError` | At expansion/execution |
| L and bc match | `simulate!` | `ArgumentError` | At execution |
| OBC pair validity (pos ≤ L-1) | `compute_pair_staircase` | `ArgumentError` | At site computation |

**Rationale**: Early validation (in builder) catches user errors immediately. Geometry validation at expansion allows the builder to accept any geometry (forward-compatible for Phase 2).

### Gate Label Mapping (for Plotting)
**Labels used in ASCII/SVG visualization:**

| Gate Type | Label | Width (chars) |
|-----------|-------|---------------|
| `Reset` | `"Rst"` | 3 |
| `HaarRandom` | `"Haar"` | 4 |
| `Projection` | `"Prj"` | 3 |
| `PauliX` | `"X"` | 1 |
| `PauliY` | `"Y"` | 1 |
| `PauliZ` | `"Z"` | 1 |
| `CZ` | `"CZ"` | 2 |

**Implementation**: Define `gate_label(gate::AbstractGate)::String` in `src/Circuit/expand.jl`:
```julia
gate_label(::Reset) = "Rst"
gate_label(::HaarRandom) = "Haar"
gate_label(::Projection) = "Prj"
gate_label(::PauliX) = "X"
gate_label(::PauliY) = "Y"
gate_label(::PauliZ) = "Z"
gate_label(::CZ) = "CZ"
gate_label(g::AbstractGate) = string(typeof(g))  # Fallback for unknown gates
```

**Usage**: `ExpandedOp` stores `label::String` field populated by `gate_label(selected_gate)`.

---

### RNG Alignment Contract
**To get identical branches in `expand_circuit` and `simulate!`:**

1. `expand_circuit(circuit; seed=N)` creates `MersenneTwister(N)` and draws once per stochastic operation per step
2. `simulate!(circuit, state)` uses `get_rng(state.rng_registry, op.rng)` per stochastic operation per step
3. **Phase 1 constraint**: Only `rng=:ctrl` is supported for plotted stochastic branching
4. **Alignment requirement**: `state.rng_registry` must have `:ctrl` stream seeded with same value as `expand_circuit`'s `seed`

**CRITICAL: Do NOT use `RNGRegistry(Val(:ct_compat); ...)` for alignment tests!**
The `:ct_compat` mode aliases `:ctrl`, `:proj`, and `:haar` to the SAME RNG object (`src/Core/rng.jl:50-60`).
This means HaarRandom gate generation consumes from the shared stream, shifting `:ctrl` branch decisions
relative to `expand_circuit`'s single `MersenneTwister(seed)` approach.

**For alignment to work**: Use standard `RNGRegistry(ctrl=seed, proj=X, haar=Y, born=Z)` with SEPARATE streams.

**Example for alignment:**
```julia
seed = 42
ops = expand_circuit(circuit; seed=seed)  # Uses MersenneTwister(42) for :ctrl decisions

# To get same branches in simulate! - use SEPARATE RNG streams, NOT :ct_compat:
rng = RNGRegistry(ctrl=seed, proj=0, haar=1, born=2)  # :ctrl matches seed, others SEPARATE
state = SimulationState(L=4, bc=:periodic, rng=rng)
simulate!(circuit, state)  # Will make same branch choices as expand_circuit

# WRONG - this breaks alignment:
# rng_bad = RNGRegistry(Val(:ct_compat); circuit=seed, measurement=0)  # ALIASED streams!
```

### RNG Alignment Verification (How to Test)
**Problem**: We need to verify `expand_circuit` and `simulate!` make identical branch choices.
**Solution**: Directly compare MPS states from two execution paths that should be identical.

**Direct Alignment Test** (MANDATORY for Task 10):
This test verifies that the same seed produces the exact same execution sequence:

```julia
using ITensors

circuit = Circuit(L=4, bc=:periodic, n_steps=4) do c
    apply_with_prob!(c; rng=:ctrl, outcomes=[
        (probability=0.5, gate=Reset(), geometry=StaircaseRight(1)),
        (probability=0.5, gate=HaarRandom(), geometry=StaircaseRight(1))
    ])
end

seed = 12345

# Approach 1: Manual execution of expanded schedule
ops = expand_circuit(circuit; seed=seed)
rng1 = RNGRegistry(ctrl=seed, proj=100, haar=101, born=102)  # :ctrl matches seed
state_manual = SimulationState(L=4, bc=:periodic, rng=rng1)
initialize!(state_manual, ProductState(x0=1//16))

# Apply each expanded op manually
for step_ops in ops
    for eop in step_ops
        if eop.gate isa Reset
            apply!(state_manual, eop.gate, SingleSite(eop.sites[1]))
        else
            apply!(state_manual, eop.gate, eop.sites)
        end
    end
end

# Approach 2: simulate! with same seed
rng2 = RNGRegistry(ctrl=seed, proj=100, haar=101, born=102)  # SAME :ctrl seed
state_simulate = SimulationState(L=4, bc=:periodic, rng=rng2)
initialize!(state_simulate, ProductState(x0=1//16))
simulate!(circuit, state_simulate; n_circuits=1)

# CRITICAL ASSERTION: Both approaches must produce IDENTICAL MPS
# Primary method: use inner product (always defined for MPS)
fidelity = abs(inner(state_manual.mps, state_simulate.mps))
@assert fidelity > 1 - 1e-10 "RNG alignment failed! Fidelity = $fidelity (expected ~1.0)"

# Alternative method if norm(mps1 - mps2) is supported in your ITensorMPS version:
# diff = norm(state_manual.mps - state_simulate.mps)
# @assert diff < 1e-10 "RNG alignment failed! norm(diff) = $diff"
```

**MPS Comparison Methods** (choose based on ITensorMPS version):
1. **`inner(mps1, mps2)`** (PREFERRED): Always defined. Returns overlap ⟨ψ₁|ψ₂⟩. For identical normalized states: `abs(inner) ≈ 1.0`
2. **`norm(mps1 - mps2)`**: May not be defined in all versions. If available, should be `≈ 0` for identical states.

Use method 1 (`inner`) as the primary test since it's guaranteed available.

**Why this test is sufficient**:
- If `expand_circuit` and `simulate!` consume RNG in different orders, the selected branches differ
- Different branches → different gates applied → different final MPS
- Matching MPS proves identical RNG consumption order

**Indirect test (weaker, also include)**:
```julia
# Different seeds → different states (shows seeds matter, but doesn't prove alignment)
rng3 = RNGRegistry(ctrl=99999, proj=100, haar=101, born=102)
state_different_seed = SimulationState(L=4, bc=:periodic, rng=rng3)
initialize!(state_different_seed, ProductState(x0=1//16))
simulate!(circuit, state_different_seed; n_circuits=1)

diff_seeds = norm(state_simulate.mps - state_different_seed.mps)
# This SHOULD be non-zero (different branches taken)
# But could be zero by chance - not a definitive test
```

---

## Work Objectives

### Core Objective
Enable circuit visualization by creating a symbolic Circuit representation that captures operations without immediate execution, allowing ASCII/SVG rendering before simulation.

### Concrete Deliverables
- `src/Circuit/` module with types and builder
- `src/Plotting/` module with ASCII and Luxor-based SVG output
- Pure `compute_sites()` functions for `StaircaseLeft`, `StaircaseRight`, `SingleSite`, `AdjacentPair`
- `simulate!(circuit, state)` executor
- Updated `examples/ct_model_circuit_style.jl` demonstrating new API

### Definition of Done
- [x] `Circuit(L=10) do c; apply_with_prob!(c; ...); end` builds valid circuit
- [x] `print_circuit(circuit; seed=42)` produces readable ASCII output
- [x] `plot_circuit(circuit; seed=42)` produces SVG file (when Luxor loaded)
- [x] `simulate!(circuit, state; n_circuits=100)` executes correctly
- [x] Same seed produces identical branch choices in plot and simulate
- [x] All tests pass: `julia --project -e 'using Pkg; Pkg.test()'`

### Must Have
- Do-Block API for circuit construction
- Pure `compute_sites` functions (no geometry mutation during expansion)
- ASCII visualization with qubit wires and gate labels
- SVG visualization as optional Luxor.jl extension
- Circuit executor that works with existing `SimulationState`

### Must NOT Have (Guardrails)
- NO `MeasurementOp` in Phase 1 (Born rule complexity)
- NO `Bricklayer` or `AllSites` geometry support (complex multi-site expansion)
- NO circuit composition/concatenation
- NO custom gate labels or rendering options
- NO SVG customization (colors, fonts, themes)
- NO deprecation warnings for old API in Phase 1 (add in Phase 2)
- NO observable tracking in Circuit (keep in `simulate!`)
- NO step-dependent probabilities
- NO nested circuits
- NO circuit serialization (JSON/YAML export)

---

## Verification Strategy

### Test Decision
- **Infrastructure exists**: PARTIAL - `test/verify_ct_match.jl` exists but NO `test/runtests.jl`
- **User wants tests**: Tests after implementation
- **Framework**: Julia's built-in `Test` module

### Test Structure
**Task 10 MUST create `test/runtests.jl`** as it does not currently exist. The file will:
- Include Julia's `Test` module
- Include all test files
- Run test suites via `@testset`

Test files to create:
- `test/runtests.jl` - Main test entry point (REQUIRED - currently missing)
- `test/circuit_test.jl` - Circuit construction, expansion, execution tests

### Manual Verification
For plotting output, visual verification:
- ASCII output readable in terminal
- SVG opens correctly in browser
- Gate positions match expected staircase pattern

---

## Execution Strategy

### Parallel Execution Waves

```
Wave 1 (Start Immediately):
├── Task 1: Pure compute_sites functions (no deps)
└── Task 2: Circuit module structure (no deps)

Wave 2 (After Wave 1):
├── Task 3: Circuit types (depends: 2)
├── Task 4: CircuitBuilder + apply_with_prob! (depends: 3)
└── Task 5: Circuit expansion (depends: 1, 3)

Wave 3 (After Wave 2):
├── Task 6: ASCII visualization (depends: 5)
├── Task 7: Luxor extension setup (depends: 2)
└── Task 8: Circuit executor (depends: 4, 5)

Wave 4 (After Wave 3):
├── Task 9: SVG visualization (depends: 5, 7)
├── Task 10: Tests (depends: 6, 8)
└── Task 11: Example update (depends: 8)

Wave 5 (Final):
└── Task 12: Documentation and cleanup (depends: all)
```

### Dependency Matrix

| Task | Depends On | Blocks | Can Parallelize With |
|------|------------|--------|---------------------|
| 1 | None | 5 | 2 |
| 2 | None | 3, 7 | 1 |
| 3 | 2 | 4, 5 | None |
| 4 | 3 | 8 | 5 |
| 5 | 1, 3 | 6, 8, 9 | 4 |
| 6 | 5 | 10 | 7, 8 |
| 7 | 2 | 9 | 4, 5, 6 |
| 8 | 4, 5 | 10, 11 | 6, 7 |
| 9 | 5, 7 | 10 | 8 |
| 10 | 6, 8, 9 | 12 | 11 |
| 11 | 8 | 12 | 10 |
| 12 | 10, 11 | None | None |

### Agent Dispatch Summary

| Wave | Tasks | Recommended Approach |
|------|-------|---------------------|
| 1 | 1, 2 | Parallel: both are foundational, no deps |
| 2 | 3, 4, 5 | 3 first (types), then 4 and 5 in parallel |
| 3 | 6, 7, 8 | All can run in parallel after deps |
| 4 | 9, 10, 11 | All can run in parallel after deps |
| 5 | 12 | Sequential: final cleanup |

---

## TODOs

- [x] 1. Add Pure `compute_sites` Functions for Symbolic Geometry Expansion

  **What to do**:
  - Create `src/Geometry/compute_sites.jl` with pure functions that compute site indices without mutating geometry objects
  - **CRITICAL**: These functions must account for GATE SUPPORT differences:
    - `Reset` gate with staircase uses SINGLE site (`geo._position` only) - see `src/Core/apply.jl:94-95`
    - `HaarRandom`/two-qubit gates with staircase uses PAIR (`[pos, pos+1]`) - see `src/Core/apply.jl:43-48`
  - Implement `compute_site_staircase_right(start::Int, step::Int, L::Int, bc::Symbol) -> Int` (single position)
  - Implement `compute_site_staircase_left(start::Int, step::Int, L::Int, bc::Symbol) -> Int` (single position)
  - Implement `compute_pair_staircase(pos::Int, L::Int, bc::Symbol) -> Vector{Int}` (convert position to pair)
  - Implement for `SingleSite`: `compute_sites(geo::SingleSite, step::Int, L::Int, bc::Symbol) -> Vector{Int}`
  - Implement for `AdjacentPair`: `compute_sites(geo::AdjacentPair, step::Int, L::Int, bc::Symbol) -> Vector{Int}`
  - Add exports to `src/QuantumCircuitsMPS.jl`: `compute_site_staircase_right`, `compute_site_staircase_left`, `compute_pair_staircase`
  - Include `compute_sites.jl` in `src/Geometry/Geometry.jl` **AFTER** `static.jl` and `staircase.jl`:
    ```julia
    # In src/Geometry/Geometry.jl:
    include("static.jl")      # Defines SingleSite, AdjacentPair types
    include("staircase.jl")   # Defines StaircaseRight, StaircaseLeft types
    include("compute_sites.jl")  # NEW: depends on types above
    ```
    **Rationale**: `compute_sites` defines methods on `SingleSite`/`AdjacentPair`, so their types must exist first.

  **Semantics Clarification**:
  - Staircase position at step N: `pos_N = advance(start, N-1, L, bc)` where advance applies N-1 times
  - For `StaircaseRight`: position increases mod L (PBC) or mod L-1 (OBC)
  - For `StaircaseLeft`: position decreases with wrap
  - The `expand_circuit` function will need to know the GATE to decide if it needs single-site or pair

  **Edge Cases and Validation** (CRITICAL):
  - `step < 1`: Throw `ArgumentError("step must be >= 1")`
  - `L < 2`: Throw `ArgumentError("L must be >= 2 for staircase geometry")`
  - `bc` not in `[:periodic, :open]`: Throw `ArgumentError("bc must be :periodic or :open")`
  - `start < 1` or `start > L`: Throw `ArgumentError("start must be in 1:L")`
  - **OBC specifics** (from `src/Geometry/staircase.jl:63-88`):
    - StaircaseRight: cycles over `1:(L-1)`, wraps `(L-1) → 1` (NOT L → 1)
    - StaircaseLeft: cycles over `1:(L-1)`, wraps `1 → (L-1)` (NOT 1 → L)
    - Both cycle over the same range `1:(L-1)` for OBC - this is because OBC pairs cannot include position L
  - **OBC start=L semantics** (CRITICAL for single-site gates):
    - For OBC, `start==L` IS ALLOWED for single-site gate expansion (e.g., `Reset` at site L is valid)
    - `compute_site_staircase_right(start=L, step=1, L, :open)` returns `L` (step=1 means initial position)
    - `compute_site_staircase_right(start=L, step=2, L, :open)` returns `1` (wrapped after first advance)
    - `compute_site_staircase_right(start=L, step=3, L, :open)` returns `2` (continues in 1:(L-1))
    - **Clarification**: "step" is 1-indexed where step=1 means initial position with zero advances.
      Step N applies (N-1) advances to the starting position.
    - For two-qubit gates, `pos==L` is INVALID (would need site L+1 which doesn't exist)
    - This matches current behavior: `StaircaseLeft(L)` is valid and applies single-site gates at L initially
  - **OBC pair validity**: For `bc=:open` and two-qubit gates, computed position MUST be in `1:(L-1)`.
    - `compute_pair_staircase(pos, L, :open)` should throw if `pos == L`
    - Validation in `expand_circuit`: if gate support=2 and bc=:open and pos==L, throw error

  **Must NOT do**:
  - Do NOT modify existing mutable geometry behavior
  - Do NOT add `Bricklayer` or `AllSites` support yet

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Mathematical functions, single file, clear specification
  - **Skills**: `[]`
    - No specialized skills needed - pure Julia math
  - **Skills Evaluated but Omitted**:
    - None needed for pure function implementation

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 1 (with Task 2)
  - **Blocks**: Task 5
  - **Blocked By**: None (can start immediately)

  **References**:
  
  **Pattern References**:
  - `src/Geometry/staircase.jl:50-55` - Current `get_sites()` logic for site calculation
  - `src/Geometry/staircase.jl:63-72` - `advance!` for StaircaseRight wrapping logic (PBC/OBC)
  - `src/Geometry/staircase.jl:80-88` - `advance!` for StaircaseLeft wrapping logic
  
  **Type References**:
  - `src/Geometry/staircase.jl:18-22` - `StaircaseRight` struct (note: stores `_position`)
  - `src/Geometry/staircase.jl:31-35` - `StaircaseLeft` struct
  - `src/Geometry/static.jl` - `SingleSite`, `AdjacentPair` types
  
  **Why Each Reference Matters**:
  - `get_sites()` shows the current algorithm - new functions must produce IDENTICAL results
  - `advance!` shows wrapping logic for PBC/OBC that must be replicated in pure form
  - The key insight: `step` parameter replaces mutable `_position` state

  **Acceptance Criteria**:

  **Manual Verification**:
  - [ ] REPL test (PBC):
    ```julia
    using QuantumCircuitsMPS
    # StaircaseRight: compute POSITION (single Int, not pair)
    # Starting at 1, after 0 advances = position 1
    compute_site_staircase_right(1, 1, 4, :periodic)  # Expected: 1
    # After 3 advances (step 4) = position 4
    compute_site_staircase_right(1, 4, 4, :periodic)  # Expected: 4
    # After 4 advances (step 5) = position 1 (wrapped)
    compute_site_staircase_right(1, 5, 4, :periodic)  # Expected: 1
    
    # Convert position to pair for two-qubit gates
    compute_pair_staircase(1, 4, :periodic)  # Expected: [1, 2]
    compute_pair_staircase(4, 4, :periodic)  # Expected: [4, 1] (PBC wrap)
    
    # StaircaseLeft starting at 4
    compute_site_staircase_left(4, 1, 4, :periodic)   # Expected: 4
    compute_site_staircase_left(4, 4, 4, :periodic)   # Expected: 1
    ```
  - [ ] REPL test (OBC - cycles over L-1 positions):
    ```julia
    # OBC: StaircaseRight cycles 1→2→3 (for L=4, avoids position 4)
    compute_site_staircase_right(1, 1, 4, :open)  # Expected: 1
    compute_site_staircase_right(1, 2, 4, :open)  # Expected: 2
    compute_site_staircase_right(1, 3, 4, :open)  # Expected: 3
    compute_site_staircase_right(1, 4, 4, :open)  # Expected: 1 (wrapped at L-1)
    
    # OBC StaircaseLeft: also cycles over 1:(L-1), wraps 1 → (L-1)
    compute_site_staircase_left(3, 1, 4, :open)   # Expected: 3
    compute_site_staircase_left(3, 3, 4, :open)   # Expected: 1
    compute_site_staircase_left(3, 4, 4, :open)   # Expected: 3 (wrapped 1 → 3)
    
    # OBC pair from position 3 (L=4): [3, 4] is valid
    compute_pair_staircase(3, 4, :open)  # Expected: [3, 4]
    
    # OBC pair from position 4 is INVALID (would need site 5)
    compute_pair_staircase(4, 4, :open)  # Should throw ArgumentError
    ```
  - [ ] Validation test:
    ```julia
    # Should throw ArgumentError
    compute_site_staircase_right(1, 0, 4, :periodic)  # Error: step < 1
    compute_site_staircase_right(1, 1, 1, :periodic)  # Error: L < 2
    compute_site_staircase_right(5, 1, 4, :periodic)  # Error: start > L
    compute_pair_staircase(4, 4, :open)               # Error: OBC pos=L invalid for pair
    ```
  - [ ] Results match current runtime behavior when `apply!` is called

  **Commit**: YES
  - Message: `feat(geometry): add pure compute_sites functions for symbolic expansion`
  - Files: `src/Geometry/compute_sites.jl`, `src/Geometry/Geometry.jl`
  - Pre-commit: `julia --project -e 'using QuantumCircuitsMPS'`

---

- [x] 2. Create Circuit Module Structure

  **What to do**:
  - Create `src/Circuit/` directory
  - Create `src/Circuit/Circuit.jl` as an **include file** (NOT a nested module - follows existing pattern)
  - Add `include("Circuit/Circuit.jl")` to main `src/QuantumCircuitsMPS.jl`
  - Add exports to `src/QuantumCircuitsMPS.jl` (NOT in `Circuit.jl`): `Circuit`, `expand_circuit`, `simulate!`
    - **Note**: `CircuitBuilder` is NOT exported (internal to do-block API)
    - **Note**: NO `GateOp`, `StochasticOp`, `AbstractCircuitOp` - internal representation uses NamedTuples
  - Define placeholder includes in `Circuit.jl` (types.jl, builder.jl, expand.jl, execute.jl)

  **Module Structure Clarification**:
  This package does NOT use nested Julia `module` blocks in subdirectories.
  - `src/Geometry/Geometry.jl` is just an include file with more includes, NOT `module Geometry ... end`
  - `src/Gates/Gates.jl` same pattern
  - All exports are centralized in `src/QuantumCircuitsMPS.jl`
  
  **Include Order Constraint** (CRITICAL):
  In `src/QuantumCircuitsMPS.jl`, the new includes MUST be placed AFTER existing dependencies:
  ```julia
  # Existing includes (order preserved)
  include("Geometry/Geometry.jl")  # Defines AbstractGeometry, SingleSite, etc.
  include("Gates/Gates.jl")        # Defines AbstractGate, Reset, HaarRandom, etc.
  include("Core/apply.jl")         # Defines apply! dispatches
  # ... other existing includes ...
  
  # NEW: Add Circuit after Gates and Geometry (Circuit types reference these)
  include("Circuit/Circuit.jl")
  
  # NEW: Add Plotting after Circuit (print_circuit references Circuit)
  include("Plotting/Plotting.jl")
  ```
  
  **Rationale**: Circuit struct fields reference `AbstractGate` and `AbstractGeometry` at type-definition time. Plotting functions reference `Circuit` and `expand_circuit`. Wrong order → compilation error.
  
  **Files to modify**:
  - CREATE: `src/Circuit/Circuit.jl` (include file, no `module` keyword)
  - EDIT: `src/QuantumCircuitsMPS.jl` to add `include("Circuit/Circuit.jl")` and export statements

  **Must NOT do**:
  - Do NOT create a nested `module Circuit ... end` block
  - Do NOT implement types yet (just include file structure)
  - Do NOT break existing functionality

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Boilerplate module setup, minimal logic
  - **Skills**: `[]`
    - No specialized skills needed
  - **Skills Evaluated but Omitted**:
    - None needed for module scaffolding

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 1 (with Task 1)
  - **Blocks**: Task 3, Task 7
  - **Blocked By**: None (can start immediately)

  **References**:
  
  **Pattern References**:
  - `src/Geometry/Geometry.jl` - Module structure pattern (includes, exports)
  - `src/Gates/Gates.jl` - Another module structure example
  - `src/QuantumCircuitsMPS.jl` - Main module showing include order
  
  **Why Each Reference Matters**:
  - Follow existing module patterns for consistency
  - Main module shows where to add new `include` statement

  **Acceptance Criteria**:

  **Manual Verification**:
  - [ ] `julia --project -e 'using QuantumCircuitsMPS; println("OK")'` → prints "OK"
  - [ ] Directory exists: `ls src/Circuit/` shows `Circuit.jl`

  **Commit**: YES
  - Message: `feat(circuit): add Circuit module structure`
  - Files: `src/Circuit/Circuit.jl`, `src/QuantumCircuitsMPS.jl`
  - Pre-commit: `julia --project -e 'using QuantumCircuitsMPS'`

---

- [x] 3. Implement Circuit Types (Internal NamedTuple Storage)

  **What to do**:
  - Create `src/Circuit/types.jl` with:
    - `struct Circuit` with `Base.@kwdef` for keyword construction
    - **NO exported `GateOp`, `StochasticOp`, or `AbstractCircuitOp` types**
    - Operations stored as `Vector{NamedTuple}` internally
    
  **Internal Representation** (NOT exported):
  ```julia
  # Deterministic operation (stored internally when apply!(c, gate, geo) is called)
  # Type: NamedTuple{(:type, :gate, :geometry), Tuple{Symbol, AbstractGate, AbstractGeometry}}
  (type = :deterministic, gate = Reset(), geometry = SingleSite(1))
  
  # Stochastic operation (stored internally when apply_with_prob!(c; ...) is called)
  # Type: NamedTuple{(:type, :rng, :outcomes), Tuple{Symbol, Symbol, Vector{...}}}
  (type = :stochastic, rng = :ctrl, outcomes = [...])
  ```
  
  **Circuit struct**:
  ```julia
  Base.@kwdef struct Circuit
      L::Int
      bc::Symbol
      operations::Vector{NamedTuple} = NamedTuple[]  # Internal storage
      n_steps::Int = 1
  end
  ```
  **Note**: `@kwdef` enables both keyword and positional construction:
  - `Circuit(L=4, bc=:periodic, n_steps=10)` (keyword)
  - `Circuit(4, :periodic, ops, 10)` (positional)
  
  **Why NamedTuples**:
  - No new user-visible types - keeps API clean
  - Consistent with existing `outcomes` pattern in `probabilistic.jl`
  - Pattern matching via `op.type` field distinguishes operation kinds
  - User only interacts with familiar Gates and Geometry concepts

  **Must NOT do**:
  - Do NOT export any internal operation types
  - Do NOT add `MeasurementOp` (Phase 2)
  - Do NOT add circuit composition methods

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Struct definitions, straightforward types
  - **Skills**: `[]`
    - No specialized skills needed
  - **Skills Evaluated but Omitted**:
    - None needed for type definitions

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Sequential (after Task 2)
  - **Blocks**: Task 4, Task 5
  - **Blocked By**: Task 2

  **References**:
  
  **Pattern References**:
  - `src/API/probabilistic.jl:46` - `NamedTuple{(:probability, :gate, :geometry)}` pattern for outcomes
  - `src/Geometry/staircase.jl:9` - Struct definition patterns
  
  **Type References**:
  - `src/Gates/Gates.jl` - `AbstractGate` type for gate field
  - `src/Geometry/Geometry.jl` - `AbstractGeometry` type for geometry field
  
  **Why Each Reference Matters**:
  - `probabilistic.jl` shows exact NamedTuple syntax - we're reusing this pattern
  - The internal representation leverages Julia's built-in NamedTuple rather than custom types

  **Acceptance Criteria**:

  **Manual Verification**:
  - [ ] REPL test:
    ```julia
    using QuantumCircuitsMPS
    # User should NOT be able to construct GateOp or StochasticOp (they don't exist!)
    @test !isdefined(QuantumCircuitsMPS, :GateOp)
    @test !isdefined(QuantumCircuitsMPS, :StochasticOp)
    @test !isdefined(QuantumCircuitsMPS, :AbstractCircuitOp)
    
    # Circuit can be constructed with keyword args
    c = Circuit(L=4, bc=:periodic, n_steps=1)
    c.L == 4  # Expected: true
    c.operations isa Vector  # Expected: true
    ```

  **Commit**: YES
  - Message: `feat(circuit): add Circuit type with internal NamedTuple storage`
  - Files: `src/Circuit/types.jl`, `src/Circuit/Circuit.jl`
  - Pre-commit: `julia --project -e 'using QuantumCircuitsMPS; Circuit(L=4, bc=:periodic)'`

---

- [x] 4. Implement CircuitBuilder and Do-Block API

  **What to do**:
  - Create `src/Circuit/builder.jl` with:
    - `mutable struct CircuitBuilder` (L, bc, operations vector) - **NOT exported**
    - `apply_with_prob!(builder::CircuitBuilder; rng, outcomes)` - records stochastic NamedTuple
    - `apply!(builder::CircuitBuilder, gate, geometry)` - records deterministic NamedTuple
  - Add do-block constructor: `Circuit(f::Function; L, bc, n_steps=1)`
  - Include in `Circuit.jl`
  - **Note**: `CircuitBuilder` is NOT exported - users only use it through the do-block syntax
  
  **Internal Operation Recording**:
  ```julia
  function apply!(builder::CircuitBuilder, gate::AbstractGate, geometry::AbstractGeometry)
      # Store as NamedTuple - NO GateOp type!
      op = (type = :deterministic, gate = gate, geometry = geometry)
      push!(builder.operations, op)
  end
  
  function apply_with_prob!(builder::CircuitBuilder; rng::Symbol, outcomes)
      # Validations...
      # Store as NamedTuple - NO StochasticOp type!
      op = (type = :stochastic, rng = rng, outcomes = outcomes)
      push!(builder.operations, op)
  end
  ```
  
  **Phase 1 RNG Key Validation** (CRITICAL):
  `apply_with_prob!(builder; rng, outcomes)` MUST validate `rng == :ctrl`.
  If `rng` is `:proj`, `:born`, or any other value, throw:
  ```julia
  if rng != :ctrl
      throw(ArgumentError("Phase 1 only supports rng=:ctrl for stochastic operations. Got: $rng"))
  end
  ```
  **Rationale**: `expand_circuit` uses a single MersenneTwister for branch selection, which only aligns with `:ctrl` stream in `RNGRegistry`. Supporting `:proj`/`:born` requires multi-stream expansion logic (Phase 2).
  
  **Additional Validations in `apply_with_prob!`**:
  ```julia
  function apply_with_prob!(builder::CircuitBuilder; rng::Symbol, outcomes)
      # Validation 1: RNG key (Phase 1)
      if rng != :ctrl
          throw(ArgumentError("Phase 1 only supports rng=:ctrl. Got: $rng"))
      end
      
      # Validation 2: Non-empty outcomes
      if isempty(outcomes)
          throw(ArgumentError("outcomes cannot be empty"))
      end
      
      # Validation 3: Probability sum
      prob_sum = sum(o.probability for o in outcomes)
      if prob_sum > 1.0
          throw(ArgumentError("Probability sum exceeds 1.0: $prob_sum"))
      end
      
      # Record the operation as NamedTuple (probability sum < 1 allows "do nothing" branch)
      push!(builder.operations, (type = :stochastic, rng = rng, outcomes = collect(outcomes)))
  end
  ```

  **Must NOT do**:
  - Do NOT export `CircuitBuilder` (internal to do-block)
  - Do NOT add deprecation warning to existing `apply_with_prob!(state, ...)`
  - Do NOT modify existing state-based API

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Builder pattern, straightforward implementation
  - **Skills**: `[]`
    - No specialized skills needed
  - **Skills Evaluated but Omitted**:
    - None needed for builder implementation

  **Parallelization**:
  - **Can Run In Parallel**: YES (with Task 5)
  - **Parallel Group**: Wave 2 (with Task 5)
  - **Blocks**: Task 8
  - **Blocked By**: Task 3

  **References**:
  
  **Pattern References**:
  - `src/API/probabilistic.jl:43-72` - Current `apply_with_prob!(state; ...)` signature and logic
  
  **API References**:
  - `src/Core/apply.jl` - `apply!(state, gate, geometry)` signature to mirror
  
  **Why Each Reference Matters**:
  - Mirror exact signature of state-based `apply_with_prob!` for consistency
  - Builder should record operations that match what `apply!` would execute

  **Acceptance Criteria**:

  **Manual Verification**:
  - [ ] REPL test:
    ```julia
    using QuantumCircuitsMPS
    circuit = Circuit(L=4, bc=:periodic) do c
        apply_with_prob!(c; rng=:ctrl, outcomes=[
            (probability=0.5, gate=Reset(), geometry=StaircaseRight(1)),
            (probability=0.5, gate=HaarRandom(), geometry=StaircaseLeft(4))
        ])
    end
    length(circuit.operations) == 1  # Expected: true (one operation stored)
    circuit.operations[1].type == :stochastic  # Expected: true
    circuit.operations[1].rng == :ctrl  # Expected: true
    ```
  - [ ] Deterministic operation test:
    ```julia
    circuit = Circuit(L=4, bc=:periodic) do c
        apply!(c, Reset(), StaircaseRight(1))
    end
    circuit.operations[1].type == :deterministic  # Expected: true
    circuit.operations[1].gate isa Reset  # Expected: true
    ```
  - [ ] CircuitBuilder NOT exported:
    ```julia
    @test !isdefined(Main, :CircuitBuilder)  # After `using QuantumCircuitsMPS`
    ```
  - [ ] Validation test (rng != :ctrl):
    ```julia
    try
        Circuit(L=4, bc=:periodic) do c
            apply_with_prob!(c; rng=:proj, outcomes=[  # Should fail!
                (probability=1.0, gate=Reset(), geometry=SingleSite(1))
            ])
        end
        error("Should have thrown!")
    catch e
        e isa ArgumentError  # Expected: true (Phase 1 only supports :ctrl)
    end
    ```
  - [ ] Validation test (probability sum > 1):
    ```julia
    try
        Circuit(L=4, bc=:periodic) do c
            apply_with_prob!(c; rng=:ctrl, outcomes=[
                (probability=0.8, gate=Reset(), geometry=SingleSite(1)),
                (probability=0.5, gate=HaarRandom(), geometry=SingleSite(1))  # Sum = 1.3!
            ])
        end
        error("Should have thrown!")
    catch e
        e isa ArgumentError  # Expected: true (probability sum exceeds 1.0)
    end
    ```

  **Commit**: YES
  - Message: `feat(circuit): add CircuitBuilder with do-block API`
  - Files: `src/Circuit/builder.jl`, `src/Circuit/Circuit.jl`
  - Pre-commit: `julia --project -e 'using QuantumCircuitsMPS; Circuit(L=4, bc=:periodic) do c; end'`

---

- [x] 5. Implement Circuit Expansion (Symbolic → Concrete)

  **What to do**:
  - Create `src/Circuit/expand.jl` with:
    - `struct ExpandedOp` (step, gate, sites, label) - this IS exported (needed for manual execution)
    - `expand_circuit(circuit::Circuit; seed::Int=0) -> Vector{Vector{ExpandedOp}}`
  - **Return type**: `Vector{Vector{ExpandedOp}}` - outer vector has length `n_steps`, inner vectors contain ops for that step
  - Use `compute_site_staircase_*` and `compute_pair_staircase` functions from Task 1
  - **CRITICAL**: Pattern-match on `op.type` field to distinguish operation kinds:
    ```julia
    for op in circuit.operations
        if op.type == :deterministic
            # op.gate and op.geometry are directly available
            expand_deterministic_op(op, step, L, bc)
        elseif op.type == :stochastic
            # op.rng and op.outcomes are available
            expand_stochastic_op(op, step, L, bc, rng)
        end
    end
    ```
  - **CRITICAL**: Determine sites based on gate support:
    - `support(gate) == 1` (Reset, Projection, PauliX) → use single site from `compute_site_staircase_*`
    - `support(gate) == 2` (HaarRandom, CZ) → use pair from `compute_pair_staircase`
  - Sample stochastic branches using seeded RNG
  - Handle "do nothing" branch (probability sum < 1) - produce empty inner vector for that step

  **RNG Alignment Specification** (CRITICAL):
  The `seed` parameter creates a **single MersenneTwister** that is consumed in this exact order:
  1. For each step (1 to `n_steps`):  # NOT n_steps × L - see Circuit Semantics
  2. For each operation in circuit.operations:
  3. If `op.type == :stochastic`: `rand(rng)` once to select branch
  
  This matches `simulate!` which uses `get_rng(state.rng_registry, op.rng)` per stochastic operation.
  
  **To guarantee alignment**: `simulate!` must be called with an `RNGRegistry` where the stream
  matching the stochastic operation's `rng` field (typically `:ctrl`) is seeded with the same value as
  `expand_circuit`'s `seed` parameter. Example:
  ```julia
  expand_circuit(circuit; seed=42)  # Uses MersenneTwister(42) for :ctrl decisions
  simulate!(circuit, state)         # state.rng_registry must have :ctrl seeded with 42
  ```

  **Must NOT do**:
  - Do NOT expand `Bricklayer` or `AllSites` (not supported yet)
  - Do NOT attempt gate fusion or optimization

  **Recommended Agent Profile**:
  - **Category**: `unspecified-low`
    - Reason: Core algorithm, needs careful RNG handling
  - **Skills**: `[]`
    - No specialized skills needed
  - **Skills Evaluated but Omitted**:
    - None needed for expansion logic

  **Parallelization**:
  - **Can Run In Parallel**: YES (with Task 4)
  - **Parallel Group**: Wave 2 (with Task 4)
  - **Blocks**: Task 6, Task 8, Task 9
  - **Blocked By**: Task 1, Task 3

  **References**:
  
  **Pattern References**:
  - `src/API/probabilistic.jl:56-68` - RNG consumption pattern (draw, cumulative check)
  - `src/Core/rng.jl` - `get_rng(registry, key)` for RNG access
  
  **RNG Consumption Algorithm** (MUST match `src/API/probabilistic.jl:56-68` exactly):
  
  ```julia
  # For each stochastic operation, consume RNG EXACTLY like apply_with_prob!
  function select_branch(rng::AbstractRNG, outcomes)
      r = rand(rng)  # Single draw per stochastic op - BEFORE checking
      cumulative = 0.0
      for outcome in outcomes
          cumulative += outcome.probability
          if r < cumulative  # STRICT <, not <=
              return outcome  # Return selected (gate, geometry) pair
          end
      end
      return nothing  # "do nothing" - no operation added to expansion
  end
  
  # Deterministic operations consume NO RNG draws
  ```
  
  **Full expand_circuit Algorithm**:
  ```julia
  function expand_circuit(circuit::Circuit; seed::Int=0)
      rng = MersenneTwister(seed)
      result = Vector{Vector{ExpandedOp}}()
      
      for step in 1:circuit.n_steps
          step_ops = ExpandedOp[]
          for op in circuit.operations
              if op.type == :deterministic
                  # No RNG consumption - just compute sites
                  sites = compute_sites(op.geometry, step, circuit.L, circuit.bc)
                  push!(step_ops, ExpandedOp(
                      step=step,
                      gate=op.gate,
                      sites=sites,
                      label=gate_label(op.gate)
                  ))
              elseif op.type == :stochastic
                  # Consume ONE RNG draw
                  selected = select_branch(rng, op.outcomes)
                  if selected !== nothing
                      sites = compute_sites(selected.geometry, step, circuit.L, circuit.bc)
                      push!(step_ops, ExpandedOp(
                          step=step,
                          gate=selected.gate,
                          sites=sites,
                          label=gate_label(selected.gate)
                      ))
                  end
                  # If nothing selected: "do nothing", no entry added
              end
          end
          push!(result, step_ops)
      end
      return result
  end
  ```
  
  **CRITICAL - NamedTuple Pattern Matching**:
  Because operations are NamedTuples (not custom types), you CANNOT use Julia dispatch:
  
  ❌ WRONG:
  ```julia
  expand_op(op::NamedTuple{(:type, :gate, :geometry)}, ...) = ...  # Won't work reliably
  ```
  
  ✅ CORRECT:
  ```julia
  if op.type == :deterministic
      # Access op.gate, op.geometry
  elseif op.type == :stochastic
      # Access op.rng, op.outcomes
  end
  ```
  
  The `.type` field is a Symbol, use equality checks.
  
  **Why Each Reference Matters**:
  - RNG pattern must match exactly so `seed=42` in expand gives same branches as simulate

  **Acceptance Criteria**:

  **Manual Verification**:
  - [ ] REPL test:
    ```julia
    using QuantumCircuitsMPS, Random
    circuit = Circuit(L=4, bc=:periodic, n_steps=4) do c
        apply_with_prob!(c; rng=:ctrl, outcomes=[
            (probability=0.5, gate=Reset(), geometry=StaircaseRight(1)),
            (probability=0.5, gate=HaarRandom(), geometry=StaircaseLeft(4))
        ])
    end
    ops = expand_circuit(circuit; seed=42)
    
    # Return type: Vector{Vector{ExpandedOp}}
    length(ops) == 4  # Expected: true (always n_steps)
    typeof(ops) <: Vector{Vector}  # Expected: true
    
    # Each inner vector may be empty (do-nothing) or have ops
    # Check determinism: same seed = same expansion
    ops2 = expand_circuit(circuit; seed=42)
    all(length(ops[i]) == length(ops2[i]) for i in 1:4)  # Expected: true
    
    # If step has ops, labels match
    for i in 1:4
        if length(ops[i]) > 0
            @assert ops[i][1].label == ops2[i][1].label
        end
    end
    ```

  **Commit**: YES
  - Message: `feat(circuit): add expand_circuit for symbolic to concrete conversion`
  - Files: `src/Circuit/expand.jl`, `src/Circuit/Circuit.jl`
  - Pre-commit: `julia --project -e 'using QuantumCircuitsMPS; expand_circuit(Circuit(L=4, bc=:periodic) do c; end)'`

---

- [x] 6. Implement ASCII Circuit Visualization

  **What to do**:
  - Create `src/Plotting/` directory
  - Create `src/Plotting/Plotting.jl` as an **include file** (NOT a nested module - follows existing pattern)
  - Create `src/Plotting/ascii.jl` with:
    - `print_circuit(circuit::Circuit; seed::Int=0, io::IO=stdout, unicode::Bool=true)`
  - Add `include("Plotting/Plotting.jl")` to main `src/QuantumCircuitsMPS.jl`
  - Add exports to `src/QuantumCircuitsMPS.jl`: `print_circuit`
  - **Unicode mode** (default): Use box-drawing characters `─`, `┤`, `├`
  - **ASCII fallback** (`unicode=false`): Use `-`, `|`, `[`, `]`
  - Draw qubit wires as horizontal lines
  - Draw gates inline with label
  - Show step numbers at top

  **Module Structure Clarification**:
  Same as Task 2 - this is an include file, NOT a nested `module Plotting ... end` block.
  Exports go in `src/QuantumCircuitsMPS.jl`.

  **Character Set Decision**:
  - Default: Unicode box-drawing (renders correctly in modern terminals)
  - Fallback: Pure ASCII for legacy terminals or piping to files
  - Unicode characters used: `─` (U+2500), `┤` (U+2524), `├` (U+251C)
  - ASCII equivalents: `-`, `|Lbl|`

  **Must NOT do**:
  - Do NOT create a nested `module Plotting ... end` block
  - Do NOT add multi-qubit gate visualization (vertical lines)
  - Do NOT add color support

  **Recommended Agent Profile**:
  - **Category**: `unspecified-low`
    - Reason: String manipulation, grid layout logic
  - **Skills**: `[]`
    - No specialized skills needed
  - **Skills Evaluated but Omitted**:
    - `frontend-ui-ux` - Not applicable to terminal output

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 3 (with Task 7, 8)
  - **Blocks**: Task 10
  - **Blocked By**: Task 5

  **References**:
  
  **ASCII Grid Construction Algorithm** (complete pseudocode):
  
  ```julia
  function print_circuit(circuit::Circuit; seed::Int=0, io::IO=stdout, unicode::Bool=true)
      # Character sets
      WIRE = unicode ? '─' : '-'
      LEFT_BOX = unicode ? '┤' : '|'
      RIGHT_BOX = unicode ? '├' : '|'
      
      # 1. Expand circuit to get concrete operations per step
      expanded = expand_circuit(circuit; seed=seed)  # Vector{Vector{ExpandedOp}}
      
      # 2. Build column list: (step_idx, substep_letter, op_or_nothing)
      columns = []
      for (step_idx, step_ops) in enumerate(expanded)
          if isempty(step_ops)
              # Empty step (all ops hit "do nothing") - still render one column
              push!(columns, (step_idx, "", nothing))
          elseif length(step_ops) == 1
              # Single op - no letter suffix
              push!(columns, (step_idx, "", step_ops[1]))
          else
              # Multiple ops - letter suffix (a, b, c...)
              for (substep_idx, op) in enumerate(step_ops)
                  letter = Char('a' + substep_idx - 1)
                  push!(columns, (step_idx, string(letter), op))
              end
          end
      end
      
      # 3. Calculate fixed column width (all columns same width for alignment)
      max_label_len = 1  # Minimum width
      for (_, _, op) in columns
          if op !== nothing
              max_label_len = max(max_label_len, length(op.label))
          end
      end
      COL_WIDTH = max_label_len + 2  # +2 for box characters
      
      # 4. Print header
      println(io, "Circuit (L=$(circuit.L), bc=$(circuit.bc), seed=$seed)")
      println(io)
      
      # Step header row
      print(io, "Step: ")
      for (step, letter, _) in columns
          header = letter == "" ? string(step) : "$(step)$(letter)"
          print(io, lpad(header, COL_WIDTH))
      end
      println(io)
      
      # 5. Print qubit rows
      for q in 1:circuit.L
          print(io, "q$q:   ")
          for (_, _, op) in columns
              if op !== nothing && q in op.sites
                  # Gate on this qubit - render box with label
                  label = op.label
                  padding = COL_WIDTH - length(label) - 2  # -2 for box chars
                  left_pad = padding ÷ 2
                  right_pad = padding - left_pad
                  print(io, LEFT_BOX, repeat(WIRE, left_pad), label, repeat(WIRE, right_pad), RIGHT_BOX)
              else
                  # Wire segment only
                  print(io, repeat(WIRE, COL_WIDTH))
              end
          end
          println(io)
      end
  end
  ```
  
  **Key Implementation Details**:
  - All columns have fixed width (based on max label length) for visual alignment
  - Empty steps still render one column with wire-only segments
  - For two-qubit gates, label appears on BOTH qubits that are in `op.sites`
  - `lpad` is Julia's built-in left-pad function
  
  **Example Output** (authoritative for Phase 1):
  ```
  Circuit (L=4, bc=periodic, seed=42)
  
  Step:      1     2     3     4
  q1:   ┤Rst ├────────────┤Haar├
  q2:   ──────┤Rst ├────────────
  q3:   ────────────┤Rst ├──────
  q4:   ┤Haar├────────────┤Rst ├
  ```
  
  **Multi-Op Step Rendering** (when a step has 2+ operations):
  Each operation within a step gets its own **sub-column**. The step header spans all sub-columns.
  
  ```
  Step:      1a    1b    2     3
  q1:   ┤Rst ├──────────┤Haar├────
  q2:   ──────┤Haar├┤X  ├─────────
  q3:   ┤Rst ├────────────────┤Z ├
  ```
  
  Here, step 1 has two ops (1a, 1b), step 2 has one op, step 3 has one op.
  
  **Rendering Rules**:
  1. Each `ExpandedOp` in a step's inner vector → one sub-column
  2. Sub-columns labeled with step number + letter suffix (1a, 1b, 1c...)
  3. If only one op in step, no letter suffix
  4. Gate boxes placed at the site(s) specified in `ExpandedOp.sites`
  5. For two-qubit gates (sites = [a, b]), place label on the site with **HIGHER index** (i.e., `max(sites)`). Do NOT reorder sites. Example: sites=[4,1] under PBC → place label on qubit 4 (the higher index).
  6. **Empty step rendering**: If `ops[step]` is empty (no operations due to ALL ops hitting "do nothing"), STILL render one column for that step with only wire segments (no gate boxes). This preserves the time axis alignment.
  7. **Partial do-nothing in multi-op steps**: If a step had N ops defined but only M<N executed (others hit do-nothing), render only M sub-columns. The visualization reflects actual execution, not potential execution. (Column count can vary per step based on RNG outcome.)
  
  **Empty Step Example**:
  ```
  Step:      1     2     3     4
  q1:   ┤Rst ├──────────────────   # Step 2 was "do nothing" - blank column
  q2:   ────────────┤Rst ├──────
  q3:   ──────────────────┤Rst ├
  q4:   ──────────────────────── 
  ```
  
  **Why Each Reference Matters**:
  - Algorithm above is the authoritative implementation guide
  - Example output above is the authoritative Phase 1 target

  **Acceptance Criteria**:

  **Manual Verification**:
  - [ ] REPL test:
    ```julia
    using QuantumCircuitsMPS
    circuit = Circuit(L=4, bc=:periodic, n_steps=4) do c
        apply!(c, Reset(), StaircaseRight(1))
    end
    print_circuit(circuit; seed=0)
    # Should show readable grid with Rst gates moving right
    ```
  - [ ] Output to file:
    ```julia
    open("circuit.txt", "w") do io
        print_circuit(circuit; seed=0, io=io)
    end
    ```
    → `circuit.txt` contains circuit diagram

  **Commit**: YES
  - Message: `feat(plotting): add ASCII circuit visualization`
  - Files: `src/Plotting/Plotting.jl`, `src/Plotting/ascii.jl`, `src/QuantumCircuitsMPS.jl`
  - Pre-commit: `julia --project -e 'using QuantumCircuitsMPS; print_circuit(Circuit(L=4, bc=:periodic) do c; end)'`

---

- [x] 7. Setup Luxor.jl Package Extension

  **What to do**:
  - Add Luxor.jl as extension dependency in `Project.toml`:
    ```toml
    [weakdeps]
    Luxor = "ae8d54c2-7ccd-5906-9d76-62fc9837b5bc"
    
    [extensions]
    QuantumCircuitsMPSLuxorExt = "Luxor"
    
    [compat]
    # ... existing compat entries ...
    Luxor = "4"
    julia = "1.9"
    ```
  
  **⚠️ BREAKING CHANGE: Julia 1.9 Minimum**:
  Adding `julia = "1.9"` to `[compat]` sets a NEW minimum Julia version. The current `Project.toml` has NO `julia` compat entry, so this is a potential breaking change for users on Julia 1.6-1.8.
  
  **Justification**: Package extensions require Julia 1.9+. This is the standard approach for optional dependencies in modern Julia.
  
  **Impact verification** (Task 7 acceptance):
  - [ ] Check if CI/tests currently run on Julia < 1.9 (if yes, update CI config)
  - [ ] Document the Julia 1.9+ requirement in the module docstring or README
  
  - Create `ext/QuantumCircuitsMPSLuxorExt.jl` with extension module structure:
    ```julia
    module QuantumCircuitsMPSLuxorExt
    
    using Luxor
    using QuantumCircuitsMPS
    using QuantumCircuitsMPS: Circuit, expand_circuit, ExpandedOp  # Import internals as needed
    
    # Extension provides plot_circuit when Luxor is loaded
    function QuantumCircuitsMPS.plot_circuit(circuit::Circuit; seed::Int=0, filename::String="circuit.svg")
        # Implementation in Task 9
        error("Not yet implemented - see Task 9")
    end
    
    end # module
    ```
  - **Function Declaration vs Method Definition** (IMPORTANT distinction):
    - In base `src/QuantumCircuitsMPS.jl`: Add a **function declaration** (generic function with 0 methods):
      ```julia
      # Provided by Luxor extension - see ext/QuantumCircuitsMPSLuxorExt.jl
      function plot_circuit end  # Declaration only - no method body
      export plot_circuit
      ```
    - Do NOT add any **method** (implementation) in base module
    - The extension adds the actual method via `QuantumCircuitsMPS.plot_circuit(...) = ...`

  **Extension Behavior Contract**:
  - WITHOUT Luxor: `plot_circuit` is defined but calling it throws `MethodError` (no methods defined)
  - WITH Luxor: `plot_circuit(circuit; seed, filename)` works and produces SVG
  - The function IS exported from `QuantumCircuitsMPS` (for discoverability) but has no methods until extension loads

  **Must NOT do**:
  - Do NOT make Luxor a required dependency
  - Do NOT implement full SVG rendering yet (Task 9)
  - Do NOT define any **method** (implementation) for `plot_circuit` in base module (only the declaration)

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Package configuration, boilerplate extension setup
  - **Skills**: `[]`
    - No specialized skills needed
  - **Skills Evaluated but Omitted**:
    - `librarian` - Extension pattern is standard Julia 1.9+

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 3 (with Task 6, 8)
  - **Blocks**: Task 9
  - **Blocked By**: Task 2

  **References**:
  
  **Documentation References**:
  - Julia Pkg docs: Package extensions (Julia 1.9+)
  - Luxor.jl UUID: `ae8d54c2-7ccd-5906-9d76-62fc9837b5bc` (from Luxor's Project.toml)
  
  **Type References**:
  - `Project.toml` - Current dependencies structure (no weakdeps yet)
  
  **Why Each Reference Matters**:
  - Extension pattern is specific to Julia 1.9+ - follow official docs
  - Luxor UUID is required for manual Project.toml editing
  - Need to add `julia = "1.9"` compat since extensions require it

  **Acceptance Criteria**:

  **Manual Verification**:
  - [ ] Without Luxor:
    ```julia
    using QuantumCircuitsMPS
    # plot_circuit should be exported but have no methods
    isdefined(QuantumCircuitsMPS, :plot_circuit)  # Expected: true
    methods(plot_circuit)  # Expected: empty (0 methods)
    ```
  - [ ] With Luxor:
    ```julia
    using Luxor, QuantumCircuitsMPS
    # Extension should load, plot_circuit should have method(s)
    length(methods(plot_circuit)) > 0  # Expected: true
    ```
  - [ ] Project.toml updated correctly:
    ```bash
    grep -A2 "\[weakdeps\]" Project.toml
    # Should show: Luxor = "ae8d54c2-7ccd-5906-9d76-62fc9837b5bc"
    ```

  **Commit**: YES
  - Message: `feat(plotting): setup Luxor.jl package extension`
  - Files: `Project.toml`, `ext/QuantumCircuitsMPSLuxorExt.jl`, `src/QuantumCircuitsMPS.jl`
  - Pre-commit: `julia --project -e 'using QuantumCircuitsMPS'`

---

- [x] 8. Implement Circuit Executor (`simulate!`)

  **What to do**:
  - Create `src/Circuit/execute.jl` with:
    - `simulate!(circuit::Circuit, state::SimulationState; n_circuits::Int=1, record_initial::Bool=true, record_every::Int=1)`
    - `execute_step!(circuit, state, step)` internal function
  - **CRITICAL**: Pattern-match on `op.type` field to distinguish operation kinds:
    ```julia
    for op in circuit.operations
        if op.type == :deterministic
            # op.gate and op.geometry are directly available
            execute_deterministic_op!(state, op, step, L, bc)
        elseif op.type == :stochastic
            # op.rng and op.outcomes are available
            execute_stochastic_op!(state, op, step, L, bc)
        end
    end
    ```
  - **CRITICAL**: For MOST gates, call `apply!(state, gate, sites::Vector{Int})` NOT `apply!(state, gate, geometry)`
    - This avoids mutating geometry objects (see Circuit Semantics section)
    - Sites are computed via `compute_site_staircase_*` functions
  - **SPECIAL CASE - Reset gate**: `Reset`'s `build_operator` method intentionally throws (see `src/Gates/composite.jl:12-17`), so it CANNOT use the sites vector dispatch.
    Instead, use `SingleSite` wrapper:
    ```julia
    if gate isa Reset
        # SingleSite is immutable - no advance! call happens
        apply!(state, gate, SingleSite(computed_site))
    else
        apply!(state, gate, sites)
    end
    ```
    This triggers `_apply_dispatch!(state, ::Reset, ::SingleSite)` in `apply.jl:73-92`.
  - Use `get_rng(state.rng_registry, op.rng)` for stochastic branch decisions (note: `op.rng`, not `op.rng_key`)
  - Validate L and bc match between circuit and state
  - Implement recording per "Recording Contract" in Circuit Semantics section

  **Must NOT do**:
  - Do NOT call `apply!(state, gate, geo::AbstractStaircase)` - this mutates geometry via `advance!`!
  - Do NOT modify existing `simulate()` function (different signature)
  - Do NOT add MeasurementOp handling yet

  **Recommended Agent Profile**:
  - **Category**: `unspecified-low`
    - Reason: Core execution logic, RNG handling
  - **Skills**: `[]`
    - No specialized skills needed
  - **Skills Evaluated but Omitted**:
    - None needed for execution logic

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 3 (with Task 6, 7)
  - **Blocks**: Task 10, Task 11
  - **Blocked By**: Task 4, Task 5

  **References**:
  
  **Pattern References**:
  - `src/API/functional.jl:21-68` - Existing `simulate()` function showing simulation loop pattern
  - `src/API/probabilistic.jl:56-68` - RNG consumption pattern (must match expand_circuit exactly)
  - `src/Core/apply.jl:23-29` - `apply!(state, gate, sites::Vector{Int})` for direct site application
  - `src/Core/apply.jl:73-92` - `_apply_dispatch!(state, ::Reset, ::SingleSite)` - Reset special handler (use this pattern!)
  - `src/Core/rng.jl:25-40` - `RNGRegistry` constructor showing required seed parameters
  
  **simulate! Algorithm** (complete pseudocode):
  
  ```julia
  function simulate!(circuit::Circuit, state::SimulationState;
                     n_circuits::Int=1,
                     record_initial::Bool=true,
                     record_every::Int=1)
      # Validation
      n_circuits >= 1 || throw(ArgumentError("n_circuits must be >= 1, got $n_circuits"))
      
      # Record initial state if requested
      if record_initial
          record!(state)
      end
      
      # Execute n_circuits repetitions (same state evolves, NO reset between)
      for circuit_idx in 1:n_circuits
          # Execute all n_steps of this circuit
          for step in 1:circuit.n_steps
              for op in circuit.operations
                  if op.type == :deterministic
                      # Compute sites, apply gate
                      sites = compute_sites(op.geometry, step, circuit.L, circuit.bc)
                      execute_gate!(state, op.gate, sites)
                  elseif op.type == :stochastic
                      # Consume ONE RNG draw from :ctrl stream
                      actual_rng = get_rng(state.rng_registry, op.rng)
                      r = rand(actual_rng)
                      cumulative = 0.0
                      for outcome in op.outcomes
                          cumulative += outcome.probability
                          if r < cumulative
                              sites = compute_sites(outcome.geometry, step, circuit.L, circuit.bc)
                              execute_gate!(state, outcome.gate, sites)
                              break
                          end
                      end
                      # If no break: "do nothing"
                  end
              end
          end
          
          # Record after this circuit (respecting record_every)
          should_record = (circuit_idx == n_circuits) ||  # Always record final
                          ((circuit_idx - 1) % record_every == 0)
          if should_record
              record!(state)
          end
      end
  end
  
  # Helper for applying gates (handles Reset special case)
  function execute_gate!(state, gate, sites::Vector{Int})
      if gate isa Reset
          # Reset requires SingleSite wrapper (see src/Core/apply.jl:73-92)
          site = sites[1]  # Reset is always single-site
          apply!(state, gate, SingleSite(site))
      else
          # Normal gates use sites vector directly
          apply!(state, gate, sites)
      end
  end
  ```
  
  **Why Each Reference Matters**:
  - `functional.jl` shows actual simulation loop (NOT `imperative.jl` which is just comments)
  - RNG consumption must be IDENTICAL to `expand_circuit` so same seed = same path
  - Use `apply!(state, gate, sites::Vector{Int})` for normal gates to avoid geometry mutation
  - **CRITICAL**: `apply.jl:73-92` shows how Reset is handled - use `SingleSite(site)` wrapper for Reset
  - `RNGRegistry` shows correct constructor: `RNGRegistry(ctrl=X, proj=Y, haar=Z, born=W)`

  **Acceptance Criteria**:

  **Manual Verification**:
  - [ ] REPL test (basic execution):
    ```julia
    using QuantumCircuitsMPS
    
    # Build circuit with n_steps=10 (10 steps total)
    circuit = Circuit(L=4, bc=:periodic, n_steps=10) do c
        apply_with_prob!(c; rng=:ctrl, outcomes=[
            (probability=0.5, gate=Reset(), geometry=StaircaseRight(1)),
            (probability=0.5, gate=HaarRandom(), geometry=StaircaseLeft(4))
        ])
    end
    
    # Create state with RNGRegistry (NOT raw MersenneTwister!)
    rng = RNGRegistry(ctrl=42, proj=43, haar=44, born=45)
    state = SimulationState(L=4, bc=:periodic, rng=rng)
    initialize!(state, ProductState(x0=1//16))
    
    # Register DomainWall observable (requires order parameter!)
    # Use i1_fn to provide sampling site dynamically
    track!(state, :dw => DomainWall(order=1, i1_fn=() -> 1))
    
    # Simulate 5 circuit repetitions
    simulate!(circuit, state; n_circuits=5)
    
    # Should complete without error
    # Check observables dict
    length(state.observables[:dw]) > 0  # Expected: true (recorded data exists)
    ```
  
  - [ ] Observable count verification (recording contract):
    ```julia
    # Create fresh state for count test
    rng = RNGRegistry(ctrl=42, proj=43, haar=44, born=45)
    state = SimulationState(L=4, bc=:periodic, rng=rng)
    initialize!(state, ProductState(x0=1//16))
    track!(state, :dw => DomainWall(order=1, i1_fn=() -> 1))
    
    # n_circuits=5, record_initial=true (default), record_every=1 (default)
    # Expected records = 1 (initial) + 5 (circuits) = 6
    simulate!(circuit, state; n_circuits=5)
    length(state.observables[:dw]) == 6  # Expected: true
    
    # Test with record_every=2
    rng2 = RNGRegistry(ctrl=42, proj=43, haar=44, born=45)
    state2 = SimulationState(L=4, bc=:periodic, rng=rng2)
    initialize!(state2, ProductState(x0=1//16))
    track!(state2, :dw => DomainWall(order=1, i1_fn=() -> 1))
    
    # n_circuits=10, record_initial=true, record_every=2
    # Expected: 1 (initial) + floor((10-1)/2) + 1 (final) = 1 + 4 + 1 = 6
    simulate!(circuit, state2; n_circuits=10, record_every=2)
    length(state2.observables[:dw]) == 6  # Expected: true
    ```
  
  - [ ] Verify geometry NOT mutated:
    ```julia
    geo = StaircaseRight(1)
    circuit = Circuit(L=4, bc=:periodic, n_steps=4) do c
        apply!(c, Reset(), geo)
    end
    # After building circuit, geo should still be at position 1
    current_position(geo) == 1  # Expected: true
    
    # After simulation, geo should STILL be at position 1
    state = SimulationState(L=4, bc=:periodic, rng=RNGRegistry(ctrl=1, proj=2, haar=3, born=4))
    initialize!(state, ProductState(x0=1//16))
    simulate!(circuit, state; n_circuits=1)
    current_position(geo) == 1  # Expected: true (NOT mutated!)
    ```

  **Commit**: YES
  - Message: `feat(circuit): add simulate! executor for Circuit`
  - Files: `src/Circuit/execute.jl`, `src/Circuit/Circuit.jl`
  - Pre-commit: Full REPL test above

---

- [x] 9. Implement SVG Circuit Visualization (Luxor Extension)

  **What to do**:
  - Implement `plot_circuit(circuit; seed, filename)` in Luxor extension
  - Draw horizontal qubit wires
  - Draw gate boxes with labels
  - Add qubit labels on left
  - Export to SVG file

  **Must NOT do**:
  - Do NOT add multi-qubit gate vertical lines (Phase 2)
  - Do NOT add colors, themes, fonts configuration
  - Do NOT add PDF export

  **Recommended Agent Profile**:
  - **Category**: `unspecified-low`
    - Reason: Graphics library usage, coordinate math
  - **Skills**: `[]`
    - No specialized skills needed - Luxor API is straightforward
  - **Skills Evaluated but Omitted**:
    - `frontend-ui-ux` - Not web frontend, different domain

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 4 (with Task 10, 11)
  - **Blocks**: Task 10
  - **Blocked By**: Task 5, Task 7

  **References**:
  
  **SVG Layout Algorithm** (complete pseudocode):
  
  ```julia
  function plot_circuit(circuit::Circuit; seed::Int=0, filename::String="circuit.svg")
      # Layout constants
      QUBIT_SPACING = 40.0      # Vertical space between qubits
      COLUMN_WIDTH = 60.0       # Horizontal space per column
      GATE_WIDTH = 40.0         # Gate box width
      GATE_HEIGHT = 30.0        # Gate box height
      MARGIN = 50.0             # Drawing margins
      
      # Expand circuit
      expanded = expand_circuit(circuit; seed=seed)
      
      # Count total columns (similar to ASCII)
      columns = []  # Same structure as ASCII algorithm
      for (step_idx, step_ops) in enumerate(expanded)
          if isempty(step_ops)
              push!(columns, (step_idx, "", nothing))
          elseif length(step_ops) == 1
              push!(columns, (step_idx, "", step_ops[1]))
          else
              for (substep_idx, op) in enumerate(step_ops)
                  push!(columns, (step_idx, Char('a' + substep_idx - 1), op))
              end
          end
      end
      
      # Calculate canvas size
      width = 2 * MARGIN + length(columns) * COLUMN_WIDTH + 100  # +100 for labels
      height = 2 * MARGIN + circuit.L * QUBIT_SPACING
      
      Drawing(width, height, filename)
      background("white")
      origin(Point(MARGIN, MARGIN))
      
      # Draw horizontal qubit wires
      for q in 1:circuit.L
          y = q * QUBIT_SPACING
          line(Point(0, y), Point(length(columns) * COLUMN_WIDTH, y))
          # Label
          text("q$q", Point(-30, y + 5))
      end
      
      # Draw step headers
      for (col_idx, (step, letter, _)) in enumerate(columns)
          x = (col_idx - 0.5) * COLUMN_WIDTH
          header = letter == "" ? string(step) : "$(step)$(letter)"
          text(header, Point(x, -10), halign=:center)
      end
      
      # Draw gate boxes
      for (col_idx, (_, _, op)) in enumerate(columns)
          if op !== nothing
              x = (col_idx - 0.5) * COLUMN_WIDTH - GATE_WIDTH/2
              for site in op.sites
                  y = site * QUBIT_SPACING - GATE_HEIGHT/2
                  box(Point(x + GATE_WIDTH/2, y + GATE_HEIGHT/2), GATE_WIDTH, GATE_HEIGHT, :stroke)
                  text(op.label, Point(x + GATE_WIDTH/2, y + GATE_HEIGHT/2 + 5), halign=:center)
              end
          end
      end
      
      finish()
  end
  ```
  
  **External References**:
  - Luxor.jl docs: https://juliagraphics.github.io/Luxor.jl/stable/
  - Key functions: `Drawing()`, `line()`, `box()`, `text()`, `finish()`
  
  **Why Each Reference Matters**:
  - Algorithm above provides complete implementation structure
  - Luxor docs for exact API syntax and options

  **Acceptance Criteria**:

  **Manual Verification**:
  - [ ] REPL test:
    ```julia
    using Luxor, QuantumCircuitsMPS
    
    circuit = Circuit(L=4, bc=:periodic, n_steps=4) do c
        apply!(c, Reset(), StaircaseRight(1))
    end
    
    plot_circuit(circuit; seed=42, filename="test_circuit.svg")
    # File should be created
    isfile("test_circuit.svg")  # Expected: true
    ```
  - [ ] Open `test_circuit.svg` in browser → Shows circuit diagram with wires and gates

  **Commit**: YES
  - Message: `feat(plotting): add SVG circuit visualization via Luxor extension`
  - Files: `ext/QuantumCircuitsMPSLuxorExt.jl`
  - Pre-commit: `julia --project -e 'using Luxor, QuantumCircuitsMPS'`

---

- [x] 10. Add Tests for Circuit Module

  **What to do**:
  - **CRITICAL**: Create `test/runtests.jl` (does NOT currently exist!)
    ```julia
    using Test
    using QuantumCircuitsMPS
    
    @testset "QuantumCircuitsMPS Tests" begin
        include("circuit_test.jl")
    end
    ```
  - Create `test/circuit_test.jl` with tests for:
    - Circuit construction (do-block, direct)
    - CircuitBuilder operations
    - `expand_circuit` determinism (same seed = same result)
    - `simulate!` basic execution
    - `print_circuit` output format (capture to IOBuffer)
    - RNG alignment: verify same seed produces same branches in expand and simulate

  **Test Infrastructure Note**:
  Currently only `test/verify_ct_match.jl` exists (a standalone verification script).
  This task MUST create the standard `test/runtests.jl` for `Pkg.test()` to work.

  **Must NOT do**:
  - Do NOT test Luxor extension (optional dependency)
  - Do NOT test performance benchmarks

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Test writing, follows established patterns
  - **Skills**: `[]`
    - No specialized skills needed
  - **Skills Evaluated but Omitted**:
    - None needed for Julia tests

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 4 (with Task 9, 11)
  - **Blocks**: Task 12
  - **Blocked By**: Task 6, Task 8 (NOT Task 9 - Luxor extension is explicitly not tested)

  **References**:
  
  **Pattern References**:
  - `test/verify_ct_match.jl` - Existing verification script (standalone, NOT via Pkg.test)
  - Julia `Test` standard library documentation
  
  **Why Each Reference Matters**:
  - `verify_ct_match.jl` shows project's testing style but is NOT a proper test suite
  - `test/runtests.jl` does NOT exist - this task MUST create it
  - Must follow Julia Pkg conventions: `test/runtests.jl` as entry point

  **Acceptance Criteria**:

  **Manual Verification**:
  - [ ] Run tests:
    ```bash
    julia --project -e 'using Pkg; Pkg.test()'
    ```
    → All tests pass
  - [ ] Specific circuit tests pass: Look for "circuit" in test output

  **Commit**: YES
  - Message: `test(circuit): add tests for Circuit module`
  - Files: `test/circuit_test.jl`, `test/runtests.jl`
  - Pre-commit: `julia --project -e 'using Pkg; Pkg.test()'`

---

- [x] 11. Update Example to Use Circuit API

  **What to do**:
  - Create `examples/ct_model_circuit_style.jl` demonstrating:
    - Circuit construction with do-block
    - ASCII visualization with `print_circuit`
    - Simulation with `simulate!`
    - Comparison showing same MPS state as imperative style (see verification below)
  - Keep existing `ct_model_simulation_styles.jl` unchanged (reference)
  
  **"Same Physics" Verification** (CRITICAL):
  The example must verify that circuit-style and imperative-style produce **identical final MPS states** when using the same RNG seeds. This is the acceptance criteria for "same physics":
  
  ```julia
  # Imperative style (existing approach)
  # NOTE: geometry must be INSIDE each outcome tuple, not as a separate kwarg
  state_imperative = SimulationState(L=4, bc=:periodic, rng=RNGRegistry(ctrl=42, proj=1, haar=2, born=3))
  initialize!(state_imperative, ProductState(x0=1//16))
  geo = StaircaseRight(1)
  for step in 1:n_steps
      apply_with_prob!(state_imperative; rng=:ctrl, outcomes=[
          (probability=p_ctrl, gate=Reset(), geometry=geo),
          (probability=1-p_ctrl, gate=HaarRandom(), geometry=geo)
      ])
  end
  
  # Circuit style
  circuit = Circuit(L=4, bc=:periodic, n_steps=n_steps) do c
      apply_with_prob!(c; rng=:ctrl, outcomes=[
          (probability=p_ctrl, gate=Reset(), geometry=StaircaseRight(1)),
          (probability=1-p_ctrl, gate=HaarRandom(), geometry=StaircaseRight(1))
      ])
  end
  state_circuit = SimulationState(L=4, bc=:periodic, rng=RNGRegistry(ctrl=42, proj=1, haar=2, born=3))
  initialize!(state_circuit, ProductState(x0=1//16))
  simulate!(circuit, state_circuit; n_circuits=1)
  
  # Verification: MPS states must be identical (use state.mps, NOT state.psi)
  # Compare using ITensors inner product (guaranteed available)
  using ITensors
  fidelity = abs(inner(state_imperative.mps, state_circuit.mps))
  @assert fidelity > 1 - 1e-10 "MPS states differ! Fidelity = $fidelity (expected ~1.0)"
  ```
  
  **Note on DomainWall and i1 Tracking** (WHY circuit mode differs):
  
  The existing example (`ct_model_simulation_styles.jl:36-37`) uses dynamic `i1` from `geo._position`:
  ```julia
  track!(state, :dw => DomainWall(order=1, i1_fn=() -> geo._position))
  ```
  
  Circuit mode uses fixed `i1_fn=() -> 1` because:
  1. **Geometries are NOT mutated** during circuit execution - `simulate!` uses `compute_sites()` pure functions
  2. There is no `geo._position` to track because no `geo` object exists during execution
  3. Observable tracking must use a fixed site or a separate tracking mechanism
  
  **Consequence**: Observable values will differ even though MPS states are identical.
  The verification compares MPS (physical state), not observables (measurement choice).

  **Must NOT do**:
  - Do NOT modify existing examples (keep for comparison)
  - Do NOT add deprecation comments to old examples

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Example file, follows existing patterns
  - **Skills**: `[]`
    - No specialized skills needed
  - **Skills Evaluated but Omitted**:
    - None needed for example writing

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 4 (with Task 9, 10)
  - **Blocks**: Task 12
  - **Blocked By**: Task 8

  **References**:
  
  **Pattern References**:
  - `examples/ct_model_simulation_styles.jl` - Current example structure to mirror
  
  **Physics References**:
  - Same CT model parameters (p_ctrl, L, etc.)
  
  **Why Each Reference Matters**:
  - New example should demonstrate same physics, different API

  **Acceptance Criteria**:

  **Manual Verification**:
  - [ ] Run example:
    ```bash
    julia --project examples/ct_model_circuit_style.jl
    ```
    → Completes without error, prints circuit, shows results

  **Commit**: YES
  - Message: `docs(examples): add circuit-style CT model example`
  - Files: `examples/ct_model_circuit_style.jl`
  - Pre-commit: `julia --project examples/ct_model_circuit_style.jl`

---

- [x] 12. Documentation and Cleanup

  **What to do**:
  - Add docstrings to all public functions and types
  - Update module-level documentation in `Circuit.jl` and `Plotting.jl`
  - Verify all exports are documented
  - Clean up any TODO comments left during implementation
  - **Add docstring to `plot_circuit` in `ext/QuantumCircuitsMPSLuxorExt.jl`** (MISSING)
  - **Add test warmup block to `test/circuit_test.jl`** to reduce test time from 90s to ~20s

  **Test Warmup Block** (add at top of test/circuit_test.jl, after imports):
  ```julia
  # WARMUP: Force compilation before tests run
  # This reduces test time from ~90s to ~20-30s by avoiding repeated JIT compilation
  let
      # Compile SimulationState
      _ = SimulationState(L=4, bc=:periodic)
      
      # Compile Circuit with various gate types  
      _ = Circuit(L=4, bc=:periodic) do c
          apply!(c, Reset(), SingleSite(1))
          apply!(c, HaarRandom(), StaircaseRight(1))
          apply_with_prob!(c; rng=:ctrl, outcomes=[
              (probability=0.5, gate=Reset(), geometry=SingleSite(1))
          ])
      end
      
      # Compile expand_circuit
      c = Circuit(L=4, bc=:periodic) do c
          apply!(c, Reset(), SingleSite(1))
      end
      _ = expand_circuit(c; seed=1)
  end
  ```

  **Must NOT do**:
  - Do NOT create separate README or documentation files
  - Do NOT add deprecation warnings yet (Phase 2)

  **Recommended Agent Profile**:
  - **Category**: `writing`
    - Reason: Documentation writing
  - **Skills**: `[]`
    - No specialized skills needed
  - **Skills Evaluated but Omitted**:
    - None needed for docstrings

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Sequential (final)
  - **Blocks**: None (final task)
  - **Blocked By**: Task 10, Task 11

  **References**:
  
  **Pattern References**:
  - `src/API/probabilistic.jl:13-42` - Docstring style example
  - `src/Geometry/staircase.jl:4-8` - Abstract type docstring pattern
  
  **Why Each Reference Matters**:
  - Follow existing docstring conventions

  **Acceptance Criteria**:

  **Manual Verification**:
  - [ ] REPL help:
    ```julia
    using QuantumCircuitsMPS
    ?Circuit
    ?print_circuit
    ?simulate!
    ```
    → All show documentation
  - [ ] No undocumented exports warning
  - [ ] **Test time reduced**: `Pkg.test()` completes in <45 seconds (was ~90s)

  **Commit**: YES (TWO COMMITS)
  - Commit 1:
    - Message: `docs(circuit): add docstrings for Circuit and Plotting modules`
    - Files: All `src/Circuit/*.jl`, `src/Plotting/*.jl`, `ext/QuantumCircuitsMPSLuxorExt.jl`
    - Pre-commit: `julia --project -e 'using QuantumCircuitsMPS'`
  - Commit 2:
    - Message: `perf(test): add warmup block to reduce JIT compilation overhead`
    - Files: `test/circuit_test.jl`
    - Pre-commit: `julia --project -e 'using Pkg; Pkg.test()'`

---

## Commit Strategy

| After Task | Message | Key Files | Verification |
|------------|---------|-----------|--------------|
| 1 | `feat(geometry): add pure compute_sites functions` | `src/Geometry/compute_sites.jl` | REPL test |
| 2 | `feat(circuit): add Circuit module structure` | `src/Circuit/Circuit.jl` | `using QuantumCircuitsMPS` |
| 3 | `feat(circuit): add Circuit and operation types` | `src/Circuit/types.jl` | REPL type check |
| 4 | `feat(circuit): add CircuitBuilder with do-block API` | `src/Circuit/builder.jl` | REPL circuit build |
| 5 | `feat(circuit): add expand_circuit` | `src/Circuit/expand.jl` | REPL expansion |
| 6 | `feat(plotting): add ASCII circuit visualization` | `src/Plotting/ascii.jl` | `print_circuit` output |
| 7 | `feat(plotting): setup Luxor.jl package extension` | `ext/`, `Project.toml` | Extension loads |
| 8 | `feat(circuit): add simulate! executor` | `src/Circuit/execute.jl` | Full simulation |
| 9 | `feat(plotting): add SVG visualization` | `ext/...LuxorExt.jl` | SVG file created |
| 10 | `test(circuit): add tests for Circuit module` | `test/circuit_test.jl` | `Pkg.test()` |
| 11 | `docs(examples): add circuit-style example` | `examples/ct_model_circuit_style.jl` | Example runs |
| 12 | `docs(circuit): add docstrings` | All Circuit/Plotting files | `?Circuit` works |

---

## Success Criteria

### Verification Commands
```bash
# All tests pass
julia --project -e 'using Pkg; Pkg.test()'

# Example runs successfully
julia --project examples/ct_model_circuit_style.jl

# ASCII plot works
julia --project -e '
using QuantumCircuitsMPS
circuit = Circuit(L=4, bc=:periodic, n_steps=4) do c
    apply!(c, Reset(), StaircaseRight(1))
end
print_circuit(circuit)
'

# SVG plot works (with Luxor)
julia --project -e '
using Luxor, QuantumCircuitsMPS
circuit = Circuit(L=4, bc=:periodic, n_steps=4) do c
    apply!(c, Reset(), StaircaseRight(1))
end
plot_circuit(circuit; filename="test.svg")
println(isfile("test.svg"))
'
```

### Final Checklist
- [x] All "Must Have" present (Circuit types, builder, ASCII, SVG extension, executor)
- [x] All "Must NOT Have" absent (no MeasurementOp, no Bricklayer, no deprecation warnings)
- [x] All tests pass
- [x] Example demonstrates full workflow (build → plot → simulate)
- [x] Same seed produces identical results in `expand_circuit` and `simulate!`
