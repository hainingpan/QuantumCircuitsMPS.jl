# SVG Layout + Observable Tracking Fixes

## TL;DR

> **Quick Summary**: Fix SVG visualization to show time flowing upward with qubit labels at bottom, fix the `record!` API error in notebook Section 7, and create two demo cells showing different observable tracking modes.
> 
> **Deliverables**:
> - SVG visualization with inverted time axis (upward) and bottom qubit labels
> - Fixed notebook Section 7 with correct `record!` API usage
> - Two new demo cells: track-every-gate vs track-final-only
> - Verified working observable data access
> 
> **Estimated Effort**: Medium
> **Parallel Execution**: NO - sequential (SVG fix affects notebook examples)
> **Critical Path**: Task 1 → Task 2 → Task 3 → Task 4 → Task 5

---

## Context

### Original Request
User found 3 issues after previous bug fixes:
1. SVG: qubit labels should be at BOTTOM, time should flow UPWARD
2. Section 7: `record!(state, :dw1)` throws MethodError
3. Empty observable data - want to see two tracking modes demonstrated

### Interview Summary
**Key Discussions**:
- Recording granularity: Every gate application (finest level), customizable by user
- Time labels: Stay on LEFT side, but MOVE to new positions (1 at bottom, N at top)
- Demo style: Two SEPARATE notebook cells, minimal complexity (2 gates, 1 observable)
- Verification: Test in `circuit_tutorial.jl` FIRST, then copy clean verified code to notebook
- Multi-qubit gates: Circuit HAS CNOT/controlled gates - must verify they still render

**Research Findings**:
- Observable API: `track!(state, :name => Obs(...))` then `record!(state)` - NO symbol argument
- SVG qubit labels: Line 95 has `Point(x, -10)` - needs `Point(x, wire_length + 20)`
- SVG time: All y-coordinates need `wire_length - y` transformation
- Notebook bug: Cell #16, `record!(state_verify, :dw1)` → `record!(state_verify)`

### Metis Review
**Identified Gaps** (addressed):
- Time label behavior clarified: Labels MOVE to new y-positions
- Multi-qubit gate regression: Must explicitly test CNOT rendering after changes
- Demo scope locked: Minimal (2 gates, 1 observable), ≤5 lines per demo
- Text orientation: Luxor text doesn't auto-rotate with coordinates, should be safe

---

## Work Objectives

### Core Objective
Fix SVG visualization orientation, correct the observable API usage, and demonstrate both tracking modes with working data access.

### Concrete Deliverables
- Modified `ext/QuantumCircuitsMPSLuxorExt.jl` with inverted y-axis
- Fixed `examples/circuit_tutorial.ipynb` Section 7 (no MethodError)
- Two new demo cells in notebook showing tracking modes
- Section 8 showing non-empty observable data

### Definition of Done
- [x] SVG renders with qubit labels at bottom of canvas
- [x] SVG renders with time step 1 at bottom, higher steps above
- [x] Multi-qubit gate connectors still render correctly (CNOT vertical lines)
- [x] Notebook Section 7 executes without MethodError
- [x] Demo A shows multiple recordings (one per gate)
- [x] Demo B shows single recording (final state only)
- [x] Section 8 shows non-empty `Float64[]` data

### Must Have
- Qubit labels at bottom of SVG
- Time flowing upward (step 1 at bottom)
- Time labels on left side at new y-positions
- Correct `record!(state)` API usage (no symbol argument)
- Two separate demo cells for tracking modes
- Working data access with actual values

### Must NOT Have (Guardrails)
- NO changes to gate colors, spacing, or visual styles
- NO modification to wire thickness or appearance
- NO changes to gate symbol rendering
- NO complex demo code (≤5 lines per demo, no plotting)
- NO changes to existing observables API (just fix usage)
- NO text rotation changes (verify Luxor handles this)

---

## Verification Strategy (MANDATORY)

### Test Decision
- **Infrastructure exists**: YES (Julia project with test directory)
- **User wants tests**: Manual verification via Julia execution
- **Framework**: Julia `--project` execution + visual SVG inspection

### Automated Verification Approach

Each task includes executable verification that agents can run:

**By Deliverable Type:**
| Type | Tool | Procedure |
|------|------|-----------|
| SVG Output | Bash + grep | Check SVG attributes for correct coordinates |
| Notebook Cells | Julia execution | Run cells, verify no errors |
| Observable Data | Julia execution | Run code, print observable values |

---

## Execution Strategy

### Sequential Execution (Required)

```
Task 1: Fix SVG rendering (Luxor extension)
    ↓
Task 2: Test SVG with circuit_tutorial.jl
    ↓
Task 3: Fix notebook Section 7 record! API
    ↓
Task 4: Add two demo cells for tracking modes
    ↓
Task 5: Verify Section 8 data access works
```

**Why Sequential**: SVG changes must be verified before updating notebook. Observable tracking demos depend on correct API usage.

### Dependency Matrix

| Task | Depends On | Blocks | Can Parallelize With |
|------|------------|--------|---------------------|
| 1 | None | 2 | None |
| 2 | 1 | 3, 4 | None |
| 3 | 2 | 4, 5 | None |
| 4 | 3 | 5 | None |
| 5 | 4 | None | None |

---

## TODOs

- [x] 1. Invert SVG Y-Axis and Move Qubit Labels to Bottom

  **What to do**:
  - Open `ext/QuantumCircuitsMPSLuxorExt.jl`
  - Calculate `wire_length = length(rows) * ROW_HEIGHT` (should exist around line 90)
  - Change qubit label position (line 95): `Point(x, -10)` → `Point(x, wire_length + 20)`
  - Invert time label y-positions (line 100): `y = (row_idx - 0.5) * ROW_HEIGHT` → `y = wire_length - (row_idx - 0.5) * ROW_HEIGHT`
  - Invert gate y-positions (lines 108, 117, 119, 130, 132): Apply same `wire_length - y` transformation
  - Update documentation comment (line 16): "Time axis goes downward" → "Time axis goes upward"

  **Must NOT do**:
  - Change gate colors, sizes, or symbols
  - Modify wire thickness or spacing
  - Change text font or alignment (except y-position)
  - Touch any code outside coordinate calculations

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Localized coordinate changes in single file, clear formulas
  - **Skills**: [`git-master`]
    - `git-master`: Atomic commit for SVG changes
  - **Skills Evaluated but Omitted**:
    - `frontend-ui-ux`: Not web frontend, Julia SVG extension
    - `playwright`: No browser testing needed

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Sequential (Wave 1)
  - **Blocks**: Task 2, 3, 4, 5
  - **Blocked By**: None (can start immediately)

  **References**:

  **Pattern References**:
  - `ext/QuantumCircuitsMPSLuxorExt.jl:89-96` - Current qubit wire and label rendering
  - `ext/QuantumCircuitsMPSLuxorExt.jl:98-103` - Current time header rendering
  - `ext/QuantumCircuitsMPSLuxorExt.jl:108-140` - Gate position calculations

  **API/Type References**:
  - `ext/QuantumCircuitsMPSLuxorExt.jl:53-57` - Layout constants (QUBIT_SPACING, ROW_HEIGHT, etc.)

  **WHY Each Reference Matters**:
  - Lines 89-96: Shows current `wire_length` calculation and qubit label `Point(x, -10)` that needs changing
  - Lines 98-103: Shows time label positioning that needs y-inversion
  - Lines 108-140: Shows ALL gate drawing code that uses y-coordinates

  **Acceptance Criteria**:

  **Automated Verification:**
  ```bash
  # Generate SVG with test circuit
  cd /mnt/d/Rutgers/QuantumCircuitsMPS.jl
  julia --project -e 'include("examples/circuit_tutorial.jl")'
  
  # Verify qubit labels are at bottom (high y-value)
  grep -o 'text[^>]*q[0-9]' examples/output/circuit_tutorial.svg | head -1
  # Assert: Contains y-coordinate > 500 (near bottom of 700-height canvas)
  
  # Verify time step 1 is at bottom
  grep -E '<text[^>]*>1<' examples/output/circuit_tutorial.svg
  # Assert: y-coordinate is near wire_length (high value)
  
  # Verify SVG dimensions unchanged
  head -5 examples/output/circuit_tutorial.svg | grep -o 'height="[0-9]*"'
  # Assert: height="700" (unchanged)
  ```

  **Evidence to Capture:**
  - [ ] SVG file content showing qubit labels with high y-coordinates
  - [ ] SVG file showing time label "1" at bottom position

  **Commit**: YES
  - Message: `fix(svg): invert time axis and move qubit labels to bottom`
  - Files: `ext/QuantumCircuitsMPSLuxorExt.jl`
  - Pre-commit: `julia --project examples/circuit_tutorial.jl` exits 0

---

- [x] 2. Verify SVG Rendering with Multi-Qubit Gates

  **What to do**:
  - Run `circuit_tutorial.jl` to regenerate SVG
  - Visually inspect `examples/output/circuit_tutorial.svg` for:
    - Qubit labels at bottom
    - Time step labels numbered correctly (1 at bottom)
    - CNOT/multi-qubit gate connectors still connect correct qubits
    - Gate boxes properly aligned with wires
  - If issues found, go back to Task 1 and fix

  **Must NOT do**:
  - Make code changes in this task (verification only)
  - Skip multi-qubit gate verification

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Verification task, no coding
  - **Skills**: []
    - No special skills needed, just run and verify
  - **Skills Evaluated but Omitted**:
    - All skills: This is pure verification

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Sequential (Wave 2)
  - **Blocks**: Task 3, 4, 5
  - **Blocked By**: Task 1

  **References**:

  **Pattern References**:
  - `examples/output/circuit_tutorial.svg` - Generated SVG to inspect

  **WHY Each Reference Matters**:
  - The SVG file is the deliverable being verified

  **Acceptance Criteria**:

  **Automated Verification:**
  ```bash
  cd /mnt/d/Rutgers/QuantumCircuitsMPS.jl
  
  # Run tutorial to regenerate SVG
  julia --project examples/circuit_tutorial.jl
  # Assert: Exit code 0
  
  # Verify SVG was regenerated (recent timestamp)
  ls -la examples/output/circuit_tutorial.svg
  # Assert: File exists, modified within last minute
  
  # Verify vertical wire lines still exist (qubit wires)
  grep -c 'line.*stroke' examples/output/circuit_tutorial.svg
  # Assert: Count > 0 (wires rendered)
  
  # Verify gate rectangles exist
  grep -c 'rect.*fill' examples/output/circuit_tutorial.svg
  # Assert: Count > 0 (gates rendered)
  
  # Verify qubit labels exist
  grep -c '>q[0-9]<' examples/output/circuit_tutorial.svg
  # Assert: Count matches number of qubits (4)
  ```

  **Evidence to Capture:**
  - [ ] Terminal output from julia execution (exit code 0)
  - [ ] SVG file stats showing recent modification

  **Commit**: NO (no code changes, groups with Task 1)

---

- [x] 3. Fix Section 7 `record!` API Error

  **What to do**:
  - Open `examples/circuit_tutorial.ipynb`
  - Find the cell with `record!(state_verify, :dw1)` (currently cell #16, around line 500)
  - Change `record!(state_verify, :dw1)` to `record!(state_verify)`
  - Ensure no other instances of `record!(state, :symbol)` pattern exist

  **Must NOT do**:
  - Change any other code in the cell
  - Modify the track! call (it's correct)
  - Add extra recording calls

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Single line fix, clear change
  - **Skills**: [`git-master`]
    - `git-master`: Atomic commit for API fix
  - **Skills Evaluated but Omitted**:
    - All others: Too simple a change

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Sequential (Wave 3)
  - **Blocks**: Task 4, 5
  - **Blocked By**: Task 2

  **References**:

  **Pattern References**:
  - `examples/circuit_tutorial.jl:235` - Correct API usage: `record!(state)`
  - `src/Observables/Observables.jl:38` - Function signature: `record!(state; i1=nothing)`

  **API/Type References**:
  - `src/Observables/Observables.jl:38-58` - Full record! implementation showing valid parameters

  **WHY Each Reference Matters**:
  - `circuit_tutorial.jl:235`: Shows the CORRECT pattern already working
  - `Observables.jl:38`: Proves the function only accepts `state` + optional `i1` keyword

  **Acceptance Criteria**:

  **Automated Verification:**
  ```bash
  cd /mnt/d/Rutgers/QuantumCircuitsMPS.jl
  
  # Verify old API pattern is removed
  grep -c 'record!(state_verify, :dw1)' examples/circuit_tutorial.ipynb
  # Assert: 0 (pattern removed)
  
  # Verify new API pattern is present
  grep -c 'record!(state_verify)' examples/circuit_tutorial.ipynb
  # Assert: >= 1 (correct pattern exists)
  
  # Run the notebook section to verify no error
  julia --project -e '
    include("examples/circuit_tutorial.jl")
    # If we reach here without error, section 7 logic works
    println("✓ No MethodError")
  '
  # Assert: Output contains "✓ No MethodError"
  ```

  **Evidence to Capture:**
  - [ ] grep output showing 0 matches for old pattern
  - [ ] grep output showing >=1 match for new pattern

  **Commit**: YES
  - Message: `fix(notebook): correct record! API usage in Section 7`
  - Files: `examples/circuit_tutorial.ipynb`
  - Pre-commit: grep confirms API pattern change

---

- [x] 4. Add Two Observable Tracking Demo Cells

  **What to do**:
  - First, test the demo code in `examples/circuit_tutorial.jl` to verify it works
  - Create Demo A (track every gate): Shows `track!` + loop with `apply_gate!` + `record!` after each gate
  - Create Demo B (track final only): Shows `track!` + multiple `apply_gate!` + single `record!` at end
  - Each demo should be ≤5 lines of code (excluding comments)
  - Use minimal circuit: 2 gates, 1 DomainWall observable
  - Add demos to notebook Section 7 after the existing fix

  **Must NOT do**:
  - Create complex circuits (keep to 2 gates max)
  - Add plotting or visualization code
  - Add excessive explanatory comments in code
  - Track multiple observables (keep to 1)

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Small code additions, clear patterns
  - **Skills**: [`git-master`]
    - `git-master`: Atomic commit
  - **Skills Evaluated but Omitted**:
    - `frontend-ui-ux`: No UI work

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Sequential (Wave 4)
  - **Blocks**: Task 5
  - **Blocked By**: Task 3

  **References**:

  **Pattern References**:
  - `examples/ct_model_simulation_styles.jl:45-80` - Imperative loop style with manual recording
  - `src/Observables/Observables.jl:38` - record! function usage

  **API/Type References**:
  - `src/Observables/domain_wall.jl` - DomainWall constructor: `DomainWall(; order=1, i1_fn=() -> 1)`

  **WHY Each Reference Matters**:
  - `ct_model_simulation_styles.jl`: Shows the loop pattern with apply_with_prob! + record!
  - `domain_wall.jl`: Shows correct DomainWall construction with i1_fn

  **Demo Code Templates**:
  
  **Demo A: Track Every Gate (≤5 lines)**
  ```julia
  # Demo A: Track at every gate application
  state_a = SimulationState(L=4, bc=:periodic, rng=RNGRegistry(ctrl=1, proj=2, haar=3, born=4))
  initialize!(state_a, ProductState(x0=1//16))
  track!(state_a, :dw => DomainWall(; order=1, i1_fn=() -> 1))
  for _ in 1:3; apply!(state_a, HaarRandom(), StaircaseRight(1)); record!(state_a); end
  println("Every-gate recordings ($(length(state_a.observables[:dw])) values): ", state_a.observables[:dw])
  ```
  
  **Demo B: Track Final Only (≤5 lines)**
  ```julia
  # Demo B: Track only final state
  state_b = SimulationState(L=4, bc=:periodic, rng=RNGRegistry(ctrl=1, proj=2, haar=3, born=4))
  initialize!(state_b, ProductState(x0=1//16))
  track!(state_b, :dw => DomainWall(; order=1, i1_fn=() -> 1))
  for _ in 1:3; apply!(state_b, HaarRandom(), StaircaseRight(1)); end; record!(state_b)
  println("Final-only recording ($(length(state_b.observables[:dw])) value): ", state_b.observables[:dw])
  ```

  **Acceptance Criteria**:

  **Automated Verification:**
  ```bash
  cd /mnt/d/Rutgers/QuantumCircuitsMPS.jl
  
  # Test demo code in Julia first
  julia --project -e '
    using QuantumCircuitsMPS
    
    # Demo A
    state_a = SimulationState(L=4, bc=:periodic, rng=RNGRegistry(ctrl=1, proj=2, haar=3, born=4))
    initialize!(state_a, ProductState(x0=1//16))
    track!(state_a, :dw => DomainWall(; order=1, i1_fn=() -> 1))
    for _ in 1:3; apply!(state_a, HaarRandom(), StaircaseRight(1)); record!(state_a); end
    @assert length(state_a.observables[:dw]) == 3 "Expected 3 recordings"
    
    # Demo B  
    state_b = SimulationState(L=4, bc=:periodic, rng=RNGRegistry(ctrl=1, proj=2, haar=3, born=4))
    initialize!(state_b, ProductState(x0=1//16))
    track!(state_b, :dw => DomainWall(; order=1, i1_fn=() -> 1))
    for _ in 1:3; apply!(state_b, HaarRandom(), StaircaseRight(1)); end
    record!(state_b)
    @assert length(state_b.observables[:dw]) == 1 "Expected 1 recording"
    
    println("✓ Both demos work correctly")
  '
  # Assert: Output contains "✓ Both demos work correctly"
  
  # Verify demos are in notebook
  grep -c "Demo A" examples/circuit_tutorial.ipynb
  # Assert: >= 1
  
  grep -c "Demo B" examples/circuit_tutorial.ipynb
  # Assert: >= 1
  ```

  **Evidence to Capture:**
  - [ ] Julia output showing "✓ Both demos work correctly"
  - [ ] grep output confirming demos in notebook

  **Commit**: YES
  - Message: `feat(notebook): add tracking mode demos (every-gate vs final-only)`
  - Files: `examples/circuit_tutorial.ipynb`
  - Pre-commit: Julia demo code runs without error

---

- [x] 5. Verify Section 8 Data Access Works

  **What to do**:
  - Ensure Section 8 code (`state_verify.observables[:dw1]`) shows non-empty data
  - The fix from Task 3 should make this work automatically
  - May need to add additional `record!` calls if data is still empty
  - Update output text to show actual values instead of empty array

  **Must NOT do**:
  - Change the data access pattern (it's correct)
  - Add complex data processing

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Verification and minor adjustments
  - **Skills**: [`git-master`]
    - `git-master`: Final commit
  - **Skills Evaluated but Omitted**:
    - All others: Simple verification task

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Sequential (Wave 5, Final)
  - **Blocks**: None (final task)
  - **Blocked By**: Task 4

  **References**:

  **Pattern References**:
  - `examples/circuit_tutorial.jl:240-245` - Existing data access pattern
  - `examples/circuit_tutorial.ipynb` Section 8 - Current data access code

  **WHY Each Reference Matters**:
  - Shows correct `state.observables[:name]` access pattern

  **Acceptance Criteria**:

  **Automated Verification:**
  ```bash
  cd /mnt/d/Rutgers/QuantumCircuitsMPS.jl
  
  # Run full tutorial and check observable data is non-empty
  julia --project -e '
    include("examples/circuit_tutorial.jl")
    # The tutorial prints observable data
  ' 2>&1 | grep -E "Domain wall|dw|observ"
  # Assert: Output shows actual Float64 values, not Float64[]
  
  # Verify Section 8 prints actual values
  julia --project -e '
    using QuantumCircuitsMPS
    state = SimulationState(L=4, bc=:periodic, rng=RNGRegistry(ctrl=42, proj=1, haar=2, born=3))
    initialize!(state, ProductState(x0=1//16))
    track!(state, :dw1 => DomainWall(; order=1, i1_fn=() -> 1))
    record!(state)  # Record initial
    # Simulate a bit
    apply!(state, HaarRandom(), StaircaseRight(1))
    record!(state)  # Record after
    dw_values = state.observables[:dw1]
    @assert length(dw_values) >= 1 "Expected non-empty observables"
    @assert !isempty(dw_values) "Observable data should not be empty"
    println("✓ Observable data: ", dw_values)
  '
  # Assert: Output shows "✓ Observable data: [...]" with actual values
  ```

  **Evidence to Capture:**
  - [ ] Julia output showing non-empty observable data
  - [ ] Confirmation that Section 8 no longer shows `Float64[]`

  **Commit**: YES (if changes needed) or NO (groups with Task 4)
  - Message: `fix(notebook): ensure Section 8 shows non-empty observable data`
  - Files: `examples/circuit_tutorial.ipynb`
  - Pre-commit: Observable data prints with actual values

---

## Commit Strategy

| After Task | Message | Files | Verification |
|------------|---------|-------|--------------|
| 1 | `fix(svg): invert time axis and move qubit labels to bottom` | `ext/QuantumCircuitsMPSLuxorExt.jl` | SVG regenerates |
| 3 | `fix(notebook): correct record! API usage in Section 7` | `examples/circuit_tutorial.ipynb` | No MethodError |
| 4+5 | `feat(notebook): add tracking demos and verify data access` | `examples/circuit_tutorial.ipynb`, `examples/output/circuit_tutorial.svg` | Demos work, data non-empty |

---

## Success Criteria

### Verification Commands
```bash
# Full verification sequence
cd /mnt/d/Rutgers/QuantumCircuitsMPS.jl

# 1. Run tutorial (tests everything)
julia --project examples/circuit_tutorial.jl
# Expected: Exit 0, no errors

# 2. Check SVG layout
head -10 examples/output/circuit_tutorial.svg
# Expected: width < height (vertical layout)

# 3. Check qubit labels position
grep -E 'text[^>]*>q[0-9]<' examples/output/circuit_tutorial.svg
# Expected: y-coordinates near bottom (high values)

# 4. Check no record! API errors
grep 'record!(state_verify, :' examples/circuit_tutorial.ipynb
# Expected: 0 matches

# 5. Check observable data output
julia --project -e 'include("examples/circuit_tutorial.jl")' 2>&1 | tail -20
# Expected: Shows actual Float64 values, not empty array
```

### Final Checklist
- [x] All "Must Have" present:
  - Qubit labels at bottom ✓
  - Time flowing upward ✓  
  - Time labels on left at correct positions ✓
  - Correct `record!(state)` API ✓
  - Two demo cells ✓
  - Non-empty observable data ✓
- [x] All "Must NOT Have" absent:
  - No gate style changes ✓
  - No complex demo code ✓
  - No multiple observables in demos ✓
- [x] All tests pass (Julia execution completes)
