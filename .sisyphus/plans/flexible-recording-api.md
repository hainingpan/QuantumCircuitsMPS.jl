# Flexible Recording API for QuantumCircuitsMPS.jl

## TL;DR

> **Quick Summary**: Implement a flexible `record_when` parameter in `simulate!()` that allows recording observables at any granularity - every gate, every step, every N gates/steps, final only, or arbitrary lambda conditions. Also fix notebook demos and SVG auto-display.
> 
> **Deliverables**:
> - Modified `src/Circuit/execute.jl` with new `record_when` parameter
> - Helper functions for presets (`every_n_gates`, `every_n_steps`)
> - Recording context struct for lambda functions
> - Updated notebook with Demo A (every_gate) and Demo B (final_only)
> - Fixed SVG auto-display in notebook
> - Unit tests for recording API
> 
> **Estimated Effort**: Medium
> **Parallel Execution**: YES - 2 waves
> **Critical Path**: Task 1 → Task 2 → Task 3 → Task 5 → Task 6

---

## Context

### Original Request
User wanted two demos in the notebook:
- Demo A: Track DomainWall at **each gate** (not each circuit)
- Demo B: Track DomainWall at **final state only**

The existing `simulate!()` only records at circuit boundaries, not per-gate. User requested a flexible recording API with lambda support instead of manual loops.

### Interview Summary
**Key Discussions**:
- **Terminology clarified**:
  - "Step" = one circuit execution (the `circuit_idx` loop, 1 to `n_circuits`)
  - "Gate" = each individual gate application (each `execute_gate!()` call)
  - "Timestep" = one iteration of `circuit.n_steps` (inner loop, 1 to `n_steps`)
- **API Design**: Single `record_when` kwarg replaces `record_every` and `record_initial`
- **Lambda Context**: Should include `step_idx`, `gate_idx`, `gate_type`, `is_step_boundary` for versatile filtering
- **No Auto-Timestamps**: Users track their own time; observable storage unchanged
- **Presets**: Functions `every_n_gates(n)` and `every_n_steps(n)` return lambdas

**Research Findings**:
- Functional API has `record_at` with `:every`, `:final`, `:custom` but at step-level only
- No existing API supports per-gate recording - this is genuinely new
- SVG auto-display works; notebook incorrectly uses `filename=` argument

### Metis Review
**Identified Gaps** (addressed):
- API fragmentation risk → Added refactor note for future unification
- Backward compatibility → **CLEAN BREAK**: Old params removed, `record_when` defaults to `:every_step`
- Lambda context design → Confirmed versatile context struct with step/gate/type info

---

## Work Objectives

### Core Objective
Add flexible per-gate recording capability to `simulate!()` with lambda support and intuitive presets.

### Concrete Deliverables
- `src/Circuit/execute.jl`: Modified with `record_when` parameter
- `src/Circuit/recording.jl` (new): Recording presets and context struct
- `examples/circuit_tutorial.ipynb`: Updated demos and SVG fix
- `test/recording_test.jl` (new): Unit tests

### Definition of Done
- [x] `simulate!(circuit, state; record_when=:every_gate)` records after each gate
- [x] `simulate!(circuit, state; record_when=:final_only)` records only at the end
- [x] `simulate!(circuit, state; record_when=every_n_gates(5))` records every 5 gates
- [x] Custom lambda `record_when=ctx -> ctx.gate_idx % 10 == 0` works
- [x] Notebook Demo A shows per-gate DomainWall tracking
- [x] Notebook Demo B shows final-only DomainWall tracking
- [x] `plot_circuit(circuit)` displays inline in Jupyter (no filename)
- [x] All unit tests pass

### Must Have
- `:every_step`, `:every_gate`, `:final_only` presets
- `every_n_steps(n)` and `every_n_gates(n)` helper functions
- Lambda support with context containing `step_idx`, `gate_idx`, `gate_type`, `is_step_boundary`
- Clean API: ONLY `record_when` parameter (old `record_every` and `record_initial` REMOVED)

### Must NOT Have (Guardrails)
- Automatic timestamp storage (users track externally)
- Old API parameters `record_every` and `record_initial` (REMOVED, not deprecated)
- Changes to other simulation APIs (Functional, Callback, Iterator) - deferred to refactor
- Complex callback system - keep it simple with single `record_when` parameter

---

## Verification Strategy (MANDATORY)

### Test Decision
- **Infrastructure exists**: YES (bun test equivalent in Julia is `julia --project -e 'using Pkg; Pkg.test()'`)
- **User wants tests**: YES (unit tests)
- **Framework**: Julia's built-in Test module

### Test Structure
Each TODO includes specific test cases. Tests will be in `test/recording_test.jl`.

---

## Execution Strategy

### Parallel Execution Waves

```
Wave 1 (Start Immediately):
├── Task 1: Create RecordingContext struct and presets
└── Task 4: Fix SVG auto-display in notebook

Wave 2 (After Task 1):
├── Task 2: Modify simulate!() to use record_when
└── Task 3: Add unit tests for recording API

Wave 3 (After Tasks 2, 3, 4):
├── Task 5: Update notebook Demo A (every_gate)
└── Task 6: Update notebook Demo B (final_only)

Wave 4 (After Wave 3):
└── Task 7: Final integration test and docstring update

Critical Path: Task 1 → Task 2 → Task 3 → Task 5 → Task 6 → Task 7
```

### Dependency Matrix

| Task | Depends On | Blocks | Can Parallelize With |
|------|------------|--------|---------------------|
| 1 | None | 2, 3 | 4 |
| 2 | 1 | 3, 5, 6 | - |
| 3 | 1, 2 | 7 | - |
| 4 | None | 5, 6 | 1 |
| 5 | 2, 4 | 7 | 6 |
| 6 | 2, 4 | 7 | 5 |
| 7 | 3, 5, 6 | None | - |

### Agent Dispatch Summary

| Wave | Tasks | Recommended Agents |
|------|-------|-------------------|
| 1 | 1, 4 | quick (parallel) |
| 2 | 2, 3 | unspecified-high (sequential) |
| 3 | 5, 6 | quick (parallel) |
| 4 | 7 | quick |

---

## TODOs

- [x] 1. Create RecordingContext struct and preset functions

  **What to do**:
  - Create new file `src/Circuit/recording.jl`
  - Define `RecordingContext` struct with these exact fields:
    ```julia
    struct RecordingContext
        step_idx::Int           # Current circuit execution (1 to n_circuits)
        gate_idx::Int           # Cumulative gate count since simulation start (never resets)
        gate_type::Any          # The gate being applied (Reset(), HaarRandom(), etc.)
        is_step_boundary::Bool  # True when this is the last gate of the current circuit/step
    end
    ```
  - Implement preset functions:
    - `every_n_gates(n::Int)` → returns `ctx -> ctx.gate_idx % n == 0`
    - `every_n_steps(n::Int)` → returns `ctx -> ctx.step_idx % n == 0 && ctx.is_step_boundary`
      - This records ONCE per N steps at step boundaries (when all gates of circuit are done)
      - Matches functional API pattern where recording happens AFTER step completes
  - Export symbols and functions from module

  **Must NOT do**:
  - Add timestamp tracking to context
  - Create complex inheritance hierarchy

  **Recommended Agent Profile**:
  - **Category**: `quick`
  - **Skills**: `[]`
    - No specialized skills needed - pure Julia struct and function definitions

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 1 (with Task 4)
  - **Blocks**: Tasks 2, 3
  - **Blocked By**: None

  **References**:

  **Pattern References**:
  - `src/Observables/Observables.jl:7` - AbstractObservable pattern for defining types
  - `src/Circuit/Circuit.jl` - How Circuit module exports types

  **API/Type References**:
  - `src/Circuit/execute.jl:134-144` - `execute_gate!` shows what gate info is available

  **Test References**:
  - `test/` - Check existing test patterns in the codebase

  **Acceptance Criteria**:

  ```julia
  # Agent runs in Julia REPL:
  using QuantumCircuitsMPS
  
  # Test RecordingContext creation (with all 4 fields)
  ctx = RecordingContext(step_idx=1, gate_idx=5, gate_type=Reset(), is_step_boundary=false)
  @assert ctx.step_idx == 1
  @assert ctx.gate_idx == 5
  @assert ctx.is_step_boundary == false
  
  # Test every_n_gates preset
  fn = every_n_gates(5)
  @assert fn(RecordingContext(1, 5, nothing, false)) == true   # 5 % 5 == 0
  @assert fn(RecordingContext(1, 3, nothing, false)) == false  # 3 % 5 != 0
  @assert fn(RecordingContext(1, 10, nothing, true)) == true   # 10 % 5 == 0
  
  # Test every_n_steps preset
  fn2 = every_n_steps(2)
  @assert fn2(RecordingContext(2, 10, nothing, true)) == true   # step 2, is boundary
  @assert fn2(RecordingContext(2, 10, nothing, false)) == false # step 2, NOT boundary
  @assert fn2(RecordingContext(3, 15, nothing, true)) == false  # step 3 (odd), is boundary
  
  println("Task 1 PASS")
  ```

  **Commit**: YES
  - Message: `feat(recording): add RecordingContext struct and preset functions`
  - Files: `src/Circuit/recording.jl`, `src/Circuit/Circuit.jl` (include statement)

---

- [x] 2. Modify simulate!() to support record_when parameter

  **What to do**:
  - Add `record_when` parameter to `simulate!()` signature
  - **REMOVE** old `record_every` and `record_initial` parameters (CLEAN BREAK)
  - New signature: `record_when::Union{Symbol, Function} = :every_step`

  **CRITICAL: Gate Counting Rules** (fixes Momus issue #1):
  - Initialize `gate_idx = 0` BEFORE the `circuit_idx` loop
  - `gate_idx` counts EXECUTED gates only (never resets during simulation)
  - For deterministic operations: increment `gate_idx` after `execute_gate!()`, then evaluate `record_when`
  - For stochastic operations with "do nothing" branch (r >= sum(probabilities)):
    - **DO NOT increment `gate_idx`** - no gate was executed
    - **DO NOT create RecordingContext** - nothing to record about
    - **DO NOT evaluate `record_when`** - skip recording check entirely
  - RecordingContext is ONLY created when a gate actually executes

  **CRITICAL: Recording Structure** (fixes Momus issue #2):
  The recording MUST stay OUTSIDE the loops to maintain observable timing. Use flag-based approach:
  
  ```julia
  gate_idx = 0  # Initialize BEFORE loops
  
  for circuit_idx in 1:n_circuits
      should_record_this_step = false  # Flag for this circuit
      
      for step in 1:circuit.n_steps
          for (op_idx, op) in enumerate(circuit.operations)
              # ... execute gate logic ...
              if gate_executed  # Only if a gate was actually applied
                  gate_idx += 1
                  is_step_boundary = (step == circuit.n_steps) && (op_idx == length(circuit.operations))
                  ctx = RecordingContext(circuit_idx, gate_idx, gate_type, is_step_boundary)
                  
                  # Evaluate record_when and SET FLAG (don't record yet!)
                  if should_record(record_when, ctx)
                      should_record_this_step = true
                  end
              end
          end
      end
      
      # Recording happens HERE - AFTER circuit completes (same position as current code!)
      if should_record_this_step
          record!(state)
      end
  end
  ```
  
  **WHY this structure**: Current code records at line 108, OUTSIDE the inner loops. This timing is correct for observable semantics - you measure the state AFTER the circuit executes, not mid-execution. The flag approach lets us evaluate `record_when` per-gate but still record at the right time.

  **CRITICAL: API Design - CLEAN BREAK** (fixes Momus issue #3):
  
  **Philosophy**: "There should be only one obvious way to do things."
  
  The old parameters `record_every` and `record_initial` are **REMOVED**, not deprecated:
  
  ```julia
  # NEW SIGNATURE (clean, no legacy baggage):
  function simulate!(circuit::Circuit, state::SimulationState;
                     n_circuits::Int=1,
                     record_when::Union{Symbol, Function}=:every_step)
      # NO record_every or record_initial parameters!
  end
  ```
  
  **Migration Notes** (for docstring/changelog):
  ```
  # OLD (no longer works - BREAKING CHANGE):
  simulate!(circuit, state; n_circuits=100, record_every=10, record_initial=true)
  
  # NEW (use instead):
  simulate!(circuit, state; n_circuits=100, record_when=every_n_steps(10))
  
  # For initial state recording: call record!() before simulate!()
  record!(state)  # optional: record initial state
  simulate!(circuit, state; n_circuits=100, record_when=:every_step)
  ```

  Handle symbol presets (concrete implementations):
  - `:every_step` → record when `is_step_boundary == true`
    - Records once per circuit (at end of last timestep)
    - This is the DEFAULT behavior
  - `:every_gate` → always record (returns true unconditionally)
  - `:final_only` → record when `is_step_boundary && circuit_idx == n_circuits`
    - Only records at: last gate of last timestep of last circuit

  **Must NOT do**:
  - Keep old `record_every`/`record_initial` parameters (REMOVE them)
  - Change observable storage format
  - Move `record!(state)` call inside the inner loops (breaks timing!)

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
  - **Skills**: `[]`
    - Core algorithm change, no specialized tools needed

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Sequential (after Task 1)
  - **Blocks**: Tasks 3, 5, 6
  - **Blocked By**: Task 1

  **References**:

  **Pattern References**:
  - `src/Circuit/execute.jl:61-113` - Current `simulate!()` implementation (ENTIRE FUNCTION)
  - `src/Circuit/execute.jl:74-101` - Nested loop structure where recording must be injected
  - `src/Circuit/execute.jl:104-109` - Current recording logic to be replaced

  **API/Type References**:
  - `src/Observables/Observables.jl:38-58` - `record!()` function signature

  **Acceptance Criteria**:

  **Code Structure Verification** (agent runs grep to verify):
  ```bash
  # Verify gate_idx initialization is BEFORE circuit_idx loop:
  grep -n "gate_idx = 0" src/Circuit/execute.jl
  # Assert: Line number is BEFORE "for circuit_idx"
  
  # Verify record!(state) stays OUTSIDE inner loops (not inside for step/for op):
  grep -n "record!(state)" src/Circuit/execute.jl
  # Assert: Line number is AFTER "end  # step loop" and AFTER "end  # op loop"
  
  # Verify OLD parameters are REMOVED (not in signature):
  grep "record_every" src/Circuit/execute.jl
  # Assert: NO matches (old param removed)
  
  grep "record_initial" src/Circuit/execute.jl  
  # Assert: NO matches (old param removed)
  
  # Verify stochastic "do nothing" branch does NOT increment gate_idx:
  grep -A5 "do nothing" src/Circuit/execute.jl
  # Assert: No "gate_idx +=" in the following lines
  ```

  **Functional Verification** (Julia REPL):
  ```julia
  # Agent runs in Julia REPL:
  using QuantumCircuitsMPS
  
  # Setup - deterministic circuit for predictable gate counting
  circuit = Circuit(L=4, bc=:open, n_steps=2) do c
      apply!(c, HaarRandom(), Bricklayer(:even))  # 2 gates per step (sites 1-2, 3-4)
      apply!(c, HaarRandom(), Bricklayer(:odd))   # 1 gate per step (sites 2-3)
  end
  # Total gates per circuit = 2 steps × (2 + 1) ops = 6 gates
  # With n_circuits=2: 12 total gates
  
  rng = RNGRegistry(ctrl=42, proj=43, haar=44, born=45)
  state = SimulationState(L=4, bc=:open, rng=rng)
  initialize!(state, ProductState(x0=1//16))
  track!(state, :dw => DomainWall(order=1, i1_fn=() -> 1))
  
  # Test :every_gate - should record 12 times (once per gate)
  simulate!(circuit, state; n_circuits=2, record_when=:every_gate)
  gate_count = length(state.observables[:dw])
  @assert gate_count == 12 "Expected 12 records for :every_gate, got $gate_count"
  
  # Test :every_step (DEFAULT) - should record 2 times (once per circuit)
  state2 = SimulationState(L=4, bc=:open, rng=rng)
  initialize!(state2, ProductState(x0=1//16))
  track!(state2, :dw => DomainWall(order=1, i1_fn=() -> 1))
  simulate!(circuit, state2; n_circuits=2, record_when=:every_step)
  @assert length(state2.observables[:dw]) == 2 "Expected 2 records for :every_step"
  
  # Test :final_only - should record 1 time
  state3 = SimulationState(L=4, bc=:open, rng=rng)
  initialize!(state3, ProductState(x0=1//16))
  track!(state3, :dw => DomainWall(order=1, i1_fn=() -> 1))
  simulate!(circuit, state3; n_circuits=2, record_when=:final_only)
  @assert length(state3.observables[:dw]) == 1 "Expected 1 record for :final_only"
  
  # Test every_n_steps(2) helper - should record 1 time (step 2 only)
  state4 = SimulationState(L=4, bc=:open, rng=rng)
  initialize!(state4, ProductState(x0=1//16))
  track!(state4, :dw => DomainWall(order=1, i1_fn=() -> 1))
  simulate!(circuit, state4; n_circuits=2, record_when=every_n_steps(2))
  @assert length(state4.observables[:dw]) == 1 "Expected 1 record for every_n_steps(2)"
  
  # Test custom lambda
  state5 = SimulationState(L=4, bc=:open, rng=rng)
  initialize!(state5, ProductState(x0=1//16))
  track!(state5, :dw => DomainWall(order=1, i1_fn=() -> 1))
  simulate!(circuit, state5; n_circuits=2, record_when=ctx -> ctx.gate_idx == 6)
  @assert length(state5.observables[:dw]) == 1 "Expected 1 record for lambda at gate 6"
  
  println("Task 2 PASS")
  ```

  **Commit**: YES
  - Message: `feat(simulate): add record_when parameter for flexible recording`
  - Files: `src/Circuit/execute.jl`

---

- [x] 3. Add unit tests for recording API

  **What to do**:
  - Create `test/recording_test.jl`
  - Test cases with CONCRETE expected values:
  
  **Test Circuit Definition** (use consistent circuit for all tests):
  ```julia
  # Standard test circuit:
  circuit = Circuit(L=4, bc=:open, n_steps=2) do c
      apply!(c, HaarRandom(), Bricklayer(:even))  # 2 gates per step (sites 1-2, 3-4)
      apply!(c, HaarRandom(), Bricklayer(:odd))   # 1 gate per step (sites 2-3)
  end
  ```
  
  **Gate Count Calculation**:
  - L=4 with Bricklayer(:even): sites (1,2), (3,4) → 2 gates
  - L=4 with Bricklayer(:odd): sites (2,3) → 1 gate
  - Total per timestep: 2 + 1 = 3 gates
  - Total per circuit (n_steps=2): 2 × 3 = 6 gates
  - Total for n_circuits=2: 2 × 6 = 12 gates
  - Total for n_circuits=3: 3 × 6 = 18 gates

  **Concrete Test Cases**:
  | Test | n_circuits | record_when | Expected Records | Calculation |
  |------|------------|-------------|------------------|-------------|
  | 1 | 2 | `:every_step` | 2 | One per circuit |
  | 2 | 2 | `:every_gate` | 12 | 2 circuits × 6 gates |
  | 3 | 2 | `:final_only` | 1 | Only the very end |
  | 4 | 3 | `every_n_gates(3)` | 6 | Gates 3,6,9,12,15,18 |
  | 5 | 4 | `every_n_steps(2)` | 2 | Steps 2, 4 |
  | 6 | 2 | `ctx -> ctx.gate_idx == 1` | 1 | Only first gate |
  | 7 | 2 | DEFAULT (no kwarg) | 2 | Defaults to :every_step |

  **Must NOT do**:
  - Test timestamp storage (not implemented)
  - Modify source code

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
  - **Skills**: `[]`
    - Test writing requires understanding the API

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Sequential (after Task 2)
  - **Blocks**: Task 7
  - **Blocked By**: Tasks 1, 2

  **References**:

  **Pattern References**:
  - `test/` - Existing test file patterns
  - `src/Circuit/execute.jl` - Updated simulate!() to test against

  **Acceptance Criteria**:

  ```bash
  # Agent runs:
  cd /mnt/d/Rutgers/QuantumCircuitsMPS.jl
  julia --project -e 'using Pkg; Pkg.test()' 2>&1 | tail -20
  # Assert: "Test Summary" shows all tests pass
  # Assert: No test failures
  # Assert: recording_test.jl is included in output
  ```

  **Commit**: YES
  - Message: `test(recording): add unit tests for record_when API`
  - Files: `test/recording_test.jl`, `test/runtests.jl` (include statement)

---

- [x] 4. Fix SVG auto-display in notebook

  **What to do**:
  - Open `examples/circuit_tutorial.ipynb`
  - Find the cell with `plot_circuit(circuit; seed=42, filename="...")`
  - Remove the `filename=` argument
  - Result: `plot_circuit(circuit; seed=42)` returns SVGImage which auto-displays

  **Must NOT do**:
  - Change the Luxor extension code (already correct)
  - Remove the output file if it exists

  **Recommended Agent Profile**:
  - **Category**: `quick`
  - **Skills**: `[]`
    - Simple notebook edit

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 1 (with Task 1)
  - **Blocks**: Tasks 5, 6
  - **Blocked By**: None

  **References**:

  **Pattern References**:
  - `ext/QuantumCircuitsMPSLuxorExt.jl:8-15` - SVGImage wrapper that enables auto-display
  - `ext/QuantumCircuitsMPSLuxorExt.jl:118-144` - plot_circuit return value logic

  **Acceptance Criteria**:

  ```bash
  # Agent searches notebook for the change:
  grep -n "plot_circuit" examples/circuit_tutorial.ipynb | grep -v "filename"
  # Assert: At least one plot_circuit call without filename argument
  
  # Verify no filename= in the modified cell:
  grep "plot_circuit.*seed=42" examples/circuit_tutorial.ipynb | grep -v "filename"
  # Assert: Returns the cell with just seed=42
  ```

  **Commit**: YES
  - Message: `fix(notebook): remove filename arg for SVG auto-display`
  - Files: `examples/circuit_tutorial.ipynb`

---

- [x] 5. Update notebook Demo A - every_gate tracking

  **What to do**:
  - Find or create Demo A section in `examples/circuit_tutorial.ipynb`
  - Implement demo showing per-gate DomainWall tracking:
    ```julia
    # Demo A: Track DomainWall at each gate
    circuit = Circuit(L=4, bc=:open, n_steps=10) do c
        apply!(c, HaarRandom(), Bricklayer(:even))
        apply!(c, HaarRandom(), Bricklayer(:odd))
    end
    
    state = SimulationState(L=4, bc=:open, rng=RNGRegistry(...))
    initialize!(state, ProductState(x0=1//16))
    track!(state, :dw => DomainWall(order=1, i1_fn=() -> 1))
    
    simulate!(circuit, state; n_circuits=5, record_when=:every_gate)
    
    # Plot results - many data points showing evolution at each gate
    plot(state.observables[:dw], title="DomainWall at every gate")
    ```
  - Add markdown explanation of what `:every_gate` does

  **Must NOT do**:
  - Use manual loops
  - Track timestamps automatically
  - Change unrelated notebook sections

  **Recommended Agent Profile**:
  - **Category**: `quick`
  - **Skills**: `[]`
    - Notebook editing

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 3 (with Task 6)
  - **Blocks**: Task 7
  - **Blocked By**: Tasks 2, 4

  **References**:

  **Pattern References**:
  - `examples/circuit_tutorial.ipynb` - Existing notebook structure
  - `src/Circuit/execute.jl` - simulate!() API with record_when

  **Acceptance Criteria**:

  ```bash
  # Agent searches notebook:
  grep -o "record_when.*every_gate" examples/circuit_tutorial.ipynb
  # Assert: Returns match showing :every_gate usage
  
  grep -o "Demo A" examples/circuit_tutorial.ipynb
  # Assert: Returns match for Demo A section
  ```

  **Commit**: YES (group with Task 6)
  - Message: `docs(notebook): add Demo A/B for recording modes`
  - Files: `examples/circuit_tutorial.ipynb`

---

- [x] 6. Update notebook Demo B - final_only tracking

  **What to do**:
  - Find or create Demo B section in `examples/circuit_tutorial.ipynb`
  - Implement demo showing final-only DomainWall tracking:
    ```julia
    # Demo B: Track DomainWall only at final state
    circuit = Circuit(L=4, bc=:open, n_steps=10) do c
        apply!(c, HaarRandom(), Bricklayer(:even))
        apply!(c, HaarRandom(), Bricklayer(:odd))
    end
    
    state = SimulationState(L=4, bc=:open, rng=RNGRegistry(...))
    initialize!(state, ProductState(x0=1//16))
    track!(state, :dw => DomainWall(order=1, i1_fn=() -> 1))
    
    simulate!(circuit, state; n_circuits=5, record_when=:final_only)
    
    # Only 1 data point - the final state
    println("Final DomainWall: ", state.observables[:dw][1])
    ```
  - Add markdown explanation contrasting with Demo A

  **Must NOT do**:
  - Use manual loops
  - Change Demo A

  **Recommended Agent Profile**:
  - **Category**: `quick`
  - **Skills**: `[]`
    - Notebook editing

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 3 (with Task 5)
  - **Blocks**: Task 7
  - **Blocked By**: Tasks 2, 4

  **References**:

  **Pattern References**:
  - `examples/circuit_tutorial.ipynb` - Existing notebook structure
  - Task 5 reference - For consistent styling

  **Acceptance Criteria**:

  ```bash
  # Agent searches notebook:
  grep -o "record_when.*final_only" examples/circuit_tutorial.ipynb
  # Assert: Returns match showing :final_only usage
  
  grep -o "Demo B" examples/circuit_tutorial.ipynb
  # Assert: Returns match for Demo B section
  ```

  **Commit**: YES (grouped with Task 5)
  - Message: (same commit as Task 5)
  - Files: `examples/circuit_tutorial.ipynb`

---

- [x] 7. Final integration test and docstring update

  **What to do**:
  - Update `simulate!()` docstring with:
    - New `record_when` parameter documentation
    - Examples for each preset (`:every_step`, `:every_gate`, `:final_only`)
    - Examples for helper functions (`every_n_gates(n)`, `every_n_steps(n)`)
    - Migration note: old parameters removed, use `record_when` instead
  - Run full test suite
  - Verify notebook renders correctly (optional manual check)

  **Must NOT do**:
  - Add new functionality
  - Change API behavior

  **Recommended Agent Profile**:
  - **Category**: `quick`
  - **Skills**: `[]`
    - Documentation and verification

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Wave 4 (final)
  - **Blocks**: None
  - **Blocked By**: Tasks 3, 5, 6

  **References**:

  **Pattern References**:
  - `src/Circuit/execute.jl:4-60` - Current docstring to update

  **Acceptance Criteria**:

  ```bash
  # Agent runs full test suite:
  cd /mnt/d/Rutgers/QuantumCircuitsMPS.jl
  julia --project -e 'using Pkg; Pkg.test()'
  # Assert: All tests pass
  
  # Verify docstring updated:
  grep -A5 "record_when" src/Circuit/execute.jl | head -10
  # Assert: Shows record_when documentation
  ```

  **Commit**: YES
  - Message: `docs(simulate): update docstring with record_when examples`
  - Files: `src/Circuit/execute.jl`

---

## Commit Strategy

| After Task | Message | Files | Verification |
|------------|---------|-------|--------------|
| 1 | `feat(recording): add RecordingContext struct and preset functions` | recording.jl, Circuit.jl | Julia REPL test |
| 2 | `feat(simulate): add record_when parameter for flexible recording` | execute.jl | Julia REPL test |
| 3 | `test(recording): add unit tests for record_when API` | recording_test.jl, runtests.jl | Pkg.test() |
| 4 | `fix(notebook): remove filename arg for SVG auto-display` | circuit_tutorial.ipynb | grep check |
| 5+6 | `docs(notebook): add Demo A/B for recording modes` | circuit_tutorial.ipynb | grep check |
| 7 | `docs(simulate): update docstring with record_when examples` | execute.jl | Pkg.test() |

---

## Success Criteria

### Verification Commands
```bash
# Full test suite
julia --project -e 'using Pkg; Pkg.test()'
# Expected: All tests pass

# Quick API verification
julia --project -e '
using QuantumCircuitsMPS
circuit = Circuit(L=4, bc=:open, n_steps=2) do c
    apply!(c, HaarRandom(), Bricklayer(:even))
end
state = SimulationState(L=4, bc=:open, rng=RNGRegistry(ctrl=42, proj=43, haar=44, born=45))
initialize!(state, ProductState(x0=1//16))
track!(state, :dw => DomainWall(order=1, i1_fn=() -> 1))
simulate!(circuit, state; n_circuits=2, record_when=:every_gate)
println("Records: ", length(state.observables[:dw]))
'
# Expected: Records: > 2 (per-gate recording works)
```

### Final Checklist
- [x] `:every_gate` records after each gate application
- [x] `:every_step` records after each circuit (DEFAULT behavior)
- [x] `:final_only` records exactly once at the end
- [x] `every_n_gates(n)` and `every_n_steps(n)` work
- [x] Lambda functions receive correct context
- [x] Old params `record_every`/`record_initial` are REMOVED from signature
- [x] Notebook Demo A shows per-gate tracking
- [x] Notebook Demo B shows final-only tracking
- [x] SVG auto-displays in notebook (no filename arg)
- [x] All unit tests pass
- [x] Docstrings updated with migration note

---

## Future Refactor Note

**TODO (for later refactor session):**
- Unify recording APIs across Circuit/Functional/Callback/Iterator APIs
- Consider consistent parameter naming (`record_when` vs `record_at`)
- This is intentionally deferred to keep this change focused
