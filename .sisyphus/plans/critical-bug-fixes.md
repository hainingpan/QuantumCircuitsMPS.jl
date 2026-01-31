# Critical Bug Fixes - COMPLETE Audit (10+ Hours Iteration)

## TL;DR

> **Quick Summary**: Fix 6+ CRITICAL bugs that were missed in 10+ hours of failed iterations
> 
> **CONFIRMED BUGS** (user-reported, exhaustively verified):
> 1. ❌ ASCII plotting in notebook - user wants it REMOVED
> 2. ❌ SVG gate boxes don't hide qubit lines (`fill="none"` issue)
> 3. ❌ SVG time axis is horizontal (should be vertical)
> 4. ❌ Observable KeyError - `DomainWall(1)` is WRONG API (should be `DomainWall(; order=1)`)
> 5. ❌ Notebook line 166: `HaarRandom()` with `StaircaseLeft(1)` (should be `StaircaseRight(1)`)
> 6. ❌ Same DomainWall bug in `.jl` file
> 
> **Estimated Effort**: Medium (~30 minutes)
> **Parallel Execution**: NO - sequential fixes required

---

## User's Exact Words (DO NOT IGNORE)

> "I raised 9 issues, you didn't fix them all. I am very unhappy!"
> "Why do I still see 'plotting ascii' in the circuit_tutorial.ipynb?"
> "Why in SVG the gate is still not 'hiding' the qubit line, and the time axis not vertical??"
> "Your '## Section 8: Accessing Recorded Observable Data' does not even run!!"
> "You are completely mindless: everytime i can find incorrect Staircase pattern!!!"

---

## Bug Evidence (Exhaustive Search Results)

### Bug 1: ASCII Plotting Still in Notebook

**User Request**: Remove ASCII plotting from notebook
**Current State**: ASCII plotting is PROMINENTLY featured

```
Line 14:    "2. **Visualize**: ASCII/SVG diagrams without execution\n"
Line 278:   "## Section 4: ASCII Visualization\n"
Line 280:   "The `print_circuit` function generates ASCII diagrams..."
Line 319:   "println(\"ASCII Visualization (first 10 steps, seed=42):\")\n"
Line 330:   "# Print ASCII diagram\n"
Line 332:   "print_circuit(short_circuit; seed=42)\n"
Line 368:   "print_circuit(short_circuit; )\n"
Line 739:   "2. Visualize circuits with `print_circuit` (ASCII) and `plot_circuit` (SVG)\n"
```

### Bug 2: SVG Gate Boxes Don't Hide Qubit Lines

**Current SVG** (`examples/output/circuit_tutorial.svg`):
```xml
<path fill="none" stroke-width="2" ... d="M 60 145 L 60 75 L 100 75 L 100 145 Z"/>
```

The gate boxes have `fill="none"`, so qubit lines show through!

**Root Cause**: Luxor's `box()` function with `:fill` creates a path, but the SVG output still shows `fill="none"`. Need to investigate Luxor rendering.

### Bug 3: SVG Time Axis is Horizontal (Should be Vertical)

**Current Layout**:
- SVG dimensions: `width="800" height="260"` (wide, short)
- Qubit wires: HORIZONTAL (q1, q2, q3, q4 stacked vertically)
- Time steps: Along X-axis (1, 2, 3, 4, 5...)

**Expected Layout** (per user):
- Time axis: VERTICAL (steps go down)
- Qubits: HORIZONTAL (q1, q2, q3, q4 spread horizontally)

### Bug 4: Observable API Wrong - Causes KeyError

**Wrong Usage** (in both `.jl` and `.ipynb`):
```julia
track!(state_verify, :dw1, DomainWall(1))  # WRONG!
```

**Correct API**:
```julia
track!(state_verify, :dw1, DomainWall(; order=1))  # Keyword argument!
```

**Evidence**: Running the code gives:
```
ERROR: MethodError: no method matching DomainWall(::Int64)
Closest candidates are:
  DomainWall(; order, i1_fn)
```

### Bug 5: Notebook Line 166 - Wrong Staircase Pattern

**Current** (WRONG):
```julia
(probability=1-p_reset, gate=HaarRandom(), geometry=StaircaseLeft(1))
```

**Should Be**:
```julia
(probability=1-p_reset, gate=HaarRandom(), geometry=StaircaseRight(1))
```

**CT Model Convention** (from `ct_model.jl`):
- `Reset()` → `StaircaseLeft`
- `HaarRandom()` → `StaircaseRight`

---

## TODOs

- [ ] 1. Remove ASCII Plotting from Notebook (HIGH PRIORITY)

  **What to do**:
  - File: `examples/circuit_tutorial.ipynb`
  - Remove or comment out Section 4 (ASCII Visualization) entirely
  - Update introduction to only mention SVG visualization
  - Remove `print_circuit` calls
  - Update summary section
  
  **Lines to modify/remove**:
  - Line 14: Remove "ASCII/SVG" → just "SVG"
  - Lines 278-368: Remove entire Section 4
  - Line 739: Update summary to only mention SVG
  
  **Recommended Agent Profile**:
  - **Category**: `quick`
  - **Skills**: none
  
  **Acceptance Criteria**:
  ```bash
  # Should return NOTHING or only comments
  grep -i "ascii" examples/circuit_tutorial.ipynb | grep -v "comment\|#"
  # Should return 0 or very few
  grep -c "print_circuit" examples/circuit_tutorial.ipynb
  ```

---

- [ ] 2. Fix SVG Gate Box Fill (CRITICAL)

  **What to do**:
  - File: `ext/QuantumCircuitsMPSLuxorExt.jl`
  - The current code uses `box(..., :fill)` but SVG output has `fill="none"`
  - Need to investigate why Luxor's box fill isn't rendering
  - Might need to use `rect()` or `setcolor()` differently
  
  **Current Code** (lines 113-116):
  ```julia
  sethue("white")
  box(Point(x, y), GATE_WIDTH, GATE_HEIGHT, :fill)
  sethue("black")
  box(Point(x, y), GATE_WIDTH, GATE_HEIGHT, :stroke)
  ```
  
  **Potential Fix**: Use Luxor's `rect()` function or ensure fill is applied:
  ```julia
  setcolor("white")
  rect(x - GATE_WIDTH/2, y - GATE_HEIGHT/2, GATE_WIDTH, GATE_HEIGHT, :fill)
  setcolor("black")
  rect(x - GATE_WIDTH/2, y - GATE_HEIGHT/2, GATE_WIDTH, GATE_HEIGHT, :stroke)
  ```
  
  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
  - **Skills**: none (but needs Luxor investigation)
  
  **Acceptance Criteria**:
  ```bash
  # After regenerating SVG, gate boxes should have fill
  # The SVG should contain white-filled rectangles
  grep "fill.*white\|fill.*rgb(100" examples/output/circuit_tutorial.svg
  ```

---

- [ ] 3. Transpose SVG Layout (Time Vertical, Qubits Horizontal)

  **What to do**:
  - File: `ext/QuantumCircuitsMPSLuxorExt.jl`
  - Transpose the entire rendering logic:
    - Swap canvas width/height calculations
    - Draw VERTICAL qubit wires (columns) instead of horizontal
    - Draw time steps along Y-axis instead of X-axis
    - Gate boxes positioned accordingly
  
  **Current Layout**:
  ```
       t1  t2  t3  t4  t5
  q1 ─[H]─[X]───────────
  q2 ───[H]─[X]─────────
  q3 ─────[H]─[X]───────
  q4 ───────[H]─[X]─────
  ```
  
  **Target Layout**:
  ```
       q1  q2  q3  q4
  t1   |   |   |   |
       [H]
  t2   |  [H]  |   |
           |
  t3   |   |  [H]  |
               |
  t4   |   |   |  [H]
                   |
  t5   |   |   |   |
  ```
  
  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
  - **Skills**: none
  
  **Acceptance Criteria**:
  ```bash
  # SVG should be taller than wide (or square for few steps)
  # Check dimensions
  head -5 examples/output/circuit_tutorial.svg
  # Should show height > width for most circuits
  ```

---

- [ ] 4. Fix DomainWall API Usage (CRITICAL - Causes KeyError)

  **What to do**:
  - File: `examples/circuit_tutorial.jl` (line 234)
  - File: `examples/circuit_tutorial.ipynb` (line 667)
  - Change: `DomainWall(1)` → `DomainWall(; order=1)`
  
  **Also need `i1_fn`**: Looking at working examples, we need:
  ```julia
  track!(state_verify, :dw1, DomainWall(; order=1, i1_fn=() -> 1))
  ```
  
  **Current (WRONG)**:
  ```julia
  track!(state_verify, :dw1, DomainWall(1))
  ```
  
  **Correct**:
  ```julia
  track!(state_verify, :dw1, DomainWall(; order=1, i1_fn=() -> 1))
  ```
  
  **Recommended Agent Profile**:
  - **Category**: `quick`
  - **Skills**: none
  
  **Acceptance Criteria**:
  ```bash
  # Should find correct API usage
  grep "DomainWall(; order" examples/circuit_tutorial.jl
  grep "DomainWall(; order" examples/circuit_tutorial.ipynb
  
  # Run tutorial - should NOT have KeyError or MethodError
  julia --project examples/circuit_tutorial.jl 2>&1 | grep -i "error"
  # Should return nothing
  ```

---

- [ ] 5. Fix Notebook Line 166 Staircase Pattern

  **What to do**:
  - File: `examples/circuit_tutorial.ipynb`
  - Line 166: `StaircaseLeft(1)` → `StaircaseRight(1)` for HaarRandom
  
  **Current (WRONG)**:
  ```
  "        (probability=1-p_reset, gate=HaarRandom(), geometry=StaircaseLeft(1))\n",
  ```
  
  **Change to**:
  ```
  "        (probability=1-p_reset, gate=HaarRandom(), geometry=StaircaseRight(1))\n",
  ```
  
  **Recommended Agent Profile**:
  - **Category**: `quick`
  - **Skills**: none
  
  **Acceptance Criteria**:
  ```bash
  # Should return NOTHING
  grep "HaarRandom.*StaircaseLeft" examples/circuit_tutorial.ipynb
  
  # Should return 3 matches
  grep -c "HaarRandom.*StaircaseRight" examples/circuit_tutorial.ipynb
  ```

---

- [ ] 6. Regenerate SVG After All Fixes

  **What to do**:
  - After fixing Luxor code and layout
  - Run the tutorial to regenerate SVG
  - Verify the new SVG has correct layout and fill
  
  **Command**:
  ```bash
  julia --project examples/circuit_tutorial.jl
  ```
  
  **Recommended Agent Profile**:
  - **Category**: `quick`
  - **Skills**: none
  
  **Acceptance Criteria**:
  - [ ] Tutorial runs without errors
  - [ ] SVG file regenerated
  - [ ] Gate boxes have white fill (qubit lines hidden)
  - [ ] Time axis is vertical

---

- [ ] 7. Final Verification - Run Tutorial End-to-End

  **What to do**:
  - Run complete tutorial
  - Verify no errors
  - Check output
  
  **Command**:
  ```bash
  julia --project examples/circuit_tutorial.jl
  ```
  
  **Acceptance Criteria**:
  - [ ] Exit code 0
  - [ ] No MethodError, KeyError, or exceptions
  - [ ] "Tutorial Summary" printed at end
  - [ ] Observable data accessed successfully

---

## Execution Order (CRITICAL)

Must be done IN THIS ORDER:

1. **Task 4**: Fix DomainWall API (enables tutorial to run)
2. **Task 5**: Fix Staircase pattern
3. **Task 1**: Remove ASCII from notebook
4. **Task 2**: Fix SVG fill issue
5. **Task 3**: Transpose SVG layout
6. **Task 6**: Regenerate SVG
7. **Task 7**: Final verification

---

## Why Previous Iterations Failed

1. **Incomplete search**: Only looked at specific lines, not entire codebase
2. **Wrong conclusions**: Claimed `:dw1` was correct without running the code
3. **Missed API change**: `DomainWall(1)` vs `DomainWall(; order=1)` - BREAKING
4. **No actual execution**: Never ran `julia --project examples/circuit_tutorial.jl`
5. **Ignored user feedback**: User said ASCII should be removed, plan said "not a bug"
6. **SVG investigation skipped**: Assumed code was correct without checking output

---

## Mandatory Verification Script

**EXECUTOR MUST RUN THIS BEFORE CLAIMING COMPLETION:**

```bash
#!/bin/bash
set -e

echo "=== VERIFICATION SCRIPT ==="

echo "1. Checking ASCII removal..."
ascii_count=$(grep -ci "ascii" examples/circuit_tutorial.ipynb || echo "0")
if [ "$ascii_count" -gt 2 ]; then
  echo "FAIL: ASCII still in notebook ($ascii_count occurrences)"
  exit 1
fi

echo "2. Checking Staircase patterns..."
wrong=$(grep -c "HaarRandom.*StaircaseLeft" examples/circuit_tutorial.ipynb || echo "0")
if [ "$wrong" != "0" ]; then
  echo "FAIL: HaarRandom+StaircaseLeft found"
  exit 1
fi

echo "3. Checking DomainWall API..."
wrong_api=$(grep -c "DomainWall(1)" examples/circuit_tutorial.jl || echo "0")
if [ "$wrong_api" != "0" ]; then
  echo "FAIL: Wrong DomainWall API"
  exit 1
fi

echo "4. Running tutorial..."
julia --project examples/circuit_tutorial.jl
if [ $? -ne 0 ]; then
  echo "FAIL: Tutorial has errors"
  exit 1
fi

echo "5. Checking SVG..."
if grep -q 'fill="none".*d="M.*L.*L.*L.*Z"' examples/output/circuit_tutorial.svg; then
  echo "WARNING: Gate boxes may still have fill=none"
fi

echo "=== ALL CHECKS PASSED ==="
```

---

## Files Modified

| File | Changes |
|------|---------|
| `examples/circuit_tutorial.ipynb` | Remove ASCII, fix Staircase, fix DomainWall |
| `examples/circuit_tutorial.jl` | Fix DomainWall API |
| `ext/QuantumCircuitsMPSLuxorExt.jl` | Fix fill, transpose layout |
| `examples/output/circuit_tutorial.svg` | Regenerate |
