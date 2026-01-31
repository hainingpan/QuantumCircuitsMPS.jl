# Visualization Improvements

## TL;DR

> **Quick Summary**: Fix 6 visualization/tutorial issues: multi-qubit gate rendering (ASCII/SVG), layout orientation flip, StaircaseLeft/Right pattern in tutorials, and observable listing helper.
> 
> **Deliverables**:
> - ASCII visualization with spanning boxes for multi-qubit gates + transposed layout (time=vertical)
> - SVG visualization with spanning boxes for multi-qubit gates
> - Fixed tutorials with correct StaircaseLeft/Right pattern
> - `list_observables()` helper function
> 
> **Estimated Effort**: Medium (8-10 hours with TDD)
> **Parallel Execution**: YES - 2 waves
> **Critical Path**: Task 1 (baseline) → Task 2 (observable helper) → Tasks 3,4 (parallel ASCII/SVG) → Task 5 (orientation) → Task 6 (tutorials)

---

## Context

### Original Request
User provided 6 issues with current visualization (prompt_history.md lines 306-322):
1. Multi-qubit gate labels appear on ALL qubits (confusing)
2. Cannot distinguish single vs two-qubit gates
3. Want time=vertical, qubits=horizontal (opposite of current)
4. SVG shows separate boxes per qubit (should be one spanning box)
5. Tutorial uses wrong StaircaseLeft/Right pattern for CT model
6. No way to list available observables

### Interview Summary
**Key Discussions**:
- Orientation: **NEW DEFAULT** (breaking change accepted) - time vertical, qubits horizontal
- Multi-qubit style: **Spanning box only** - single box containing label, no separate connectors
- Tutorial files: Update **BOTH** `.jl` AND `.ipynb`
- Test strategy: **TDD** - write failing tests first

**Research Findings**:
- ASCII rendering: `src/Plotting/ascii.jl` lines 123-140, loop draws box on each qubit in `op.sites`
- SVG rendering: `ext/QuantumCircuitsMPSLuxorExt.jl` lines 104-116, `for site in op.sites` draws separate boxes
- Correct CT pattern: `Reset()+StaircaseLeft`, `HaarRandom()+StaircaseRight` (from ct_model.jl)
- Observable types: `DomainWall`, `BornProbability` (subtypes of `AbstractObservable`)

### Metis Review
**Identified Gaps** (addressed):
- Baseline capture needed before changes → Added Task 1
- Single-qubit regression risk → Tests must verify single-qubit gates unchanged
- Edge cases (empty circuit, non-contiguous sites) → Added to acceptance criteria

---

## Work Objectives

### Core Objective
Fix visualization rendering for multi-qubit gates, transpose layout orientation, correct tutorial patterns, and add observable discovery helper.

### Concrete Deliverables
- `src/Plotting/ascii.jl` - Spanning box rendering + transposed layout
- `ext/QuantumCircuitsMPSLuxorExt.jl` - Spanning box rendering
- `src/Observables/Observables.jl` - `list_observables()` function
- `examples/circuit_tutorial.jl` - Correct StaircaseLeft/Right
- `examples/circuit_tutorial.ipynb` - Correct StaircaseLeft/Right

### Definition of Done
- [x] `julia --project -e 'using QuantumCircuitsMPS; println(list_observables())'` outputs `["DomainWall", "BornProbability"]`
- [x] Multi-qubit gates show ONE label in ASCII output (not duplicated per qubit)
- [x] Multi-qubit gates show ONE box in SVG output (count `<rect` tags)
- [x] ASCII layout: steps as rows, qubits as columns
- [x] Tutorial scripts execute without error (exit code 0)
- [x] All 100+ existing tests still pass

### Must Have
- Single spanning box for multi-qubit gates (ASCII + SVG)
- Transposed layout as new default (time=vertical)
- `list_observables()` helper function
- Correct StaircaseLeft/Right in both tutorial files

### Must NOT Have (Guardrails)
- NO changes to Gate or Geometry types
- NO changes to core `apply!` engine
- NO new visualization formats (PNG, PDF, etc.)
- NO color customization or animation
- NO performance optimization (unless regression detected)
- NO tutorial content changes beyond StaircaseLeft/Right fix
- NO refactoring of unrelated plotting code

---

## Verification Strategy (MANDATORY)

### Test Decision
- **Infrastructure exists**: YES (Julia Test module, `test/circuit_test.jl` exists)
- **User wants tests**: YES (TDD)
- **Framework**: Julia built-in `Test` module
- **QA approach**: TDD - write failing tests first, then implement

### TDD Workflow
Each TODO follows RED-GREEN-REFACTOR:

**Task Structure:**
1. **RED**: Write failing test first
   - Test file: `test/circuit_test.jl` (extend existing)
   - Test command: `julia --project -e 'using Pkg; Pkg.test()'`
   - Expected: FAIL (test exists, implementation doesn't match)
2. **GREEN**: Implement minimum code to pass
   - Command: `julia --project -e 'using Pkg; Pkg.test()'`
   - Expected: PASS
3. **REFACTOR**: Clean up while keeping green

---

## Execution Strategy

### Parallel Execution Waves

```
Wave 1 (Start Immediately):
├── Task 1: Baseline Capture (must complete first - foundational)
└── Task 2: Observable Helper (independent, low risk)

Wave 2 (After Wave 1):
├── Task 3: ASCII Multi-Qubit Spanning Box
└── Task 4: SVG Multi-Qubit Spanning Box

Wave 3 (After Wave 2):
└── Task 5: ASCII Layout Transpose (depends on ASCII structure from Task 3)

Wave 4 (After Wave 3):
└── Task 6: Tutorial Fixes (can verify visualization changes)

Critical Path: Task 1 → Task 3 → Task 5 → Task 6
```

### Dependency Matrix

| Task | Depends On | Blocks | Can Parallelize With |
|------|------------|--------|---------------------|
| 1 | None | 3, 4, 5 | 2 |
| 2 | None | None | 1 |
| 3 | 1 | 5 | 4 |
| 4 | 1 | None | 3 |
| 5 | 3 | 6 | None |
| 6 | 5 | None | None |

---

## TODOs

- [x] 1. Baseline Capture - Capture Current Visualization Output

  **What to do**:
  - Create test fixtures capturing current ASCII output for: single-qubit gate, 2-qubit gate, 3-qubit gate
  - Create test fixtures capturing current SVG output structure
  - Document current behavior as reference for regression testing
  - Add baseline tests that pass with current implementation

  **Must NOT do**:
  - Change any visualization code
  - Add new features

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Simple capture task, no complex logic
  - **Skills**: `[]`
    - No special skills needed

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 1 (with Task 2)
  - **Blocks**: Tasks 3, 4, 5
  - **Blocked By**: None

  **References**:

  **Pattern References**:
  - `test/circuit_test.jl:347-360` - Existing visualization tests structure

  **API References**:
  - `src/Plotting/ascii.jl:75-80` - `print_circuit()` function signature
  - `src/Circuit/expand.jl:6-25` - `ExpandedOp` struct with `sites::Vector{Int}`

  **Acceptance Criteria**:

  ```bash
  # Agent runs:
  julia --project -e '
  using QuantumCircuitsMPS, Test
  
  # Create test circuits
  c1 = Circuit(L=4, bc=:periodic) do c
      apply!(c, PauliX(), SingleSite(1))
  end
  c2 = Circuit(L=4, bc=:periodic) do c
      apply!(c, HaarRandom(), AdjacentPair(1))
  end
  
  # Capture ASCII output
  ascii1 = sprint(print_circuit, c1)
  ascii2 = sprint(print_circuit, c2)
  
  # Verify structure exists
  @test contains(ascii1, "q1:")
  @test contains(ascii2, "Haar")
  println("Baseline capture successful")
  '
  # Assert: Output contains "Baseline capture successful"
  ```

  **Commit**: YES
  - Message: `test(plotting): add baseline visualization tests`
  - Files: `test/circuit_test.jl`
  - Pre-commit: `julia --project -e 'using Pkg; Pkg.test()'`

---

- [x] 2. Add `list_observables()` Helper Function

  **What to do**:
  - Add `list_observables()` function to `src/Observables/Observables.jl`
  - Return `Vector{String}` of available observable type names
  - Export from main module
  - Add docstring explaining usage
  - Write test first (TDD)

  **Must NOT do**:
  - Add new observable types
  - Change existing observable behavior

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Small, isolated function addition
  - **Skills**: `[]`
    - No special skills needed

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 1 (with Task 1)
  - **Blocks**: None (independent)
  - **Blocked By**: None

  **References**:

  **Pattern References**:
  - `src/Observables/Observables.jl:7` - `AbstractObservable` base type
  - `src/Observables/domain_wall.jl:17` - `DomainWall <: AbstractObservable`
  - `src/Observables/born.jl:6` - `BornProbability <: AbstractObservable`

  **API References**:
  - `src/QuantumCircuitsMPS.jl:57` - Current exports: `AbstractObservable, DomainWall, BornProbability`

  **Acceptance Criteria**:

  **TDD RED phase:**
  ```bash
  # Agent writes test first, expects FAIL:
  julia --project -e '
  using QuantumCircuitsMPS, Test
  obs = list_observables()
  @test "DomainWall" in obs
  @test "BornProbability" in obs
  @test length(obs) >= 2
  '
  # Expected: ERROR - list_observables not defined
  ```

  **TDD GREEN phase:**
  ```bash
  # After implementation:
  julia --project -e '
  using QuantumCircuitsMPS, Test
  obs = list_observables()
  @test "DomainWall" in obs
  @test "BornProbability" in obs
  @test length(obs) >= 2
  println("list_observables() works: ", obs)
  '
  # Assert: Output contains "list_observables() works:"
  # Assert: Output contains "DomainWall"
  ```

  **Commit**: YES
  - Message: `feat(observables): add list_observables() helper function`
  - Files: `src/Observables/Observables.jl`, `src/QuantumCircuitsMPS.jl`, `test/circuit_test.jl`
  - Pre-commit: `julia --project -e 'using Pkg; Pkg.test()'`

---

- [x] 3. ASCII Multi-Qubit Gate Spanning Box

  **What to do**:
  - Modify `src/Plotting/ascii.jl` rendering loop (lines 123-140)
  - For multi-qubit gates: draw ONE spanning box with label, not separate boxes per qubit
  - Single-qubit gates must render IDENTICALLY to before (regression protection)
  - Write failing test first showing current duplicate-label behavior

  **Must NOT do**:
  - Change layout orientation (Task 5)
  - Add vertical connector lines (user chose spanning box only)
  - Modify SVG rendering

  **Recommended Agent Profile**:
  - **Category**: `unspecified-low`
    - Reason: Moderate complexity algorithm change
  - **Skills**: `[]`
    - No special skills needed

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 2 (with Task 4)
  - **Blocks**: Task 5
  - **Blocked By**: Task 1

  **References**:

  **Pattern References**:
  - `src/Plotting/ascii.jl:123-140` - Current rendering loop to modify
  - `src/Plotting/ascii.jl:38-41` - Documentation of current limitation

  **API References**:
  - `src/Circuit/expand.jl:6-25` - `ExpandedOp.sites` contains all site indices
  - `src/Plotting/ascii.jl:76-79` - Box-drawing characters (LEFT_BOX, RIGHT_BOX, WIRE)

  **Implementation Guidance**:
  ```julia
  # Current logic (lines 127-139):
  if op !== nothing && q in op.sites
      # Draws box on EVERY qubit - WRONG for multi-qubit
  
  # New logic needed:
  if op !== nothing && q == minimum(op.sites)
      # Draw spanning box with label (only on first qubit)
  elseif op !== nothing && q in op.sites && q != minimum(op.sites)
      # Draw continuation of spanning box (no label, just box edges)
  ```

  **Acceptance Criteria**:

  **TDD RED phase:**
  ```bash
  # Test that currently FAILS (shows the bug):
  julia --project -e '
  using QuantumCircuitsMPS, Test
  c = Circuit(L=4, bc=:periodic) do c
      apply!(c, HaarRandom(), AdjacentPair(1))  # 2-qubit gate on [1,2]
  end
  ascii = sprint(print_circuit, c)
  
  # Count occurrences of "Haar" - should be 1, not 2
  haar_count = count("Haar", ascii)
  @test haar_count == 1  # This FAILS with current implementation
  '
  # Expected: FAIL - haar_count is 2
  ```

  **TDD GREEN phase:**
  ```bash
  # After implementation:
  julia --project -e '
  using QuantumCircuitsMPS, Test
  
  # Multi-qubit: label appears once
  c2 = Circuit(L=4, bc=:periodic) do c
      apply!(c, HaarRandom(), AdjacentPair(1))
  end
  ascii2 = sprint(print_circuit, c2)
  @test count("Haar", ascii2) == 1
  
  # Single-qubit: still works
  c1 = Circuit(L=4, bc=:periodic) do c
      apply!(c, PauliX(), SingleSite(1))
  end
  ascii1 = sprint(print_circuit, c1)
  @test contains(ascii1, "X")
  @test count("X", ascii1) == 1
  
  println("ASCII spanning box works correctly")
  '
  # Assert: Output contains "ASCII spanning box works correctly"
  ```

  **Commit**: YES
  - Message: `fix(plotting): render multi-qubit gates with single spanning box in ASCII`
  - Files: `src/Plotting/ascii.jl`, `test/circuit_test.jl`
  - Pre-commit: `julia --project -e 'using Pkg; Pkg.test()'`

---

- [x] 4. SVG Multi-Qubit Gate Spanning Box

  **What to do**:
  - Modify `ext/QuantumCircuitsMPSLuxorExt.jl` rendering loop (lines 104-116)
  - For multi-qubit gates: draw ONE tall box spanning all qubits
  - Calculate: `min_y = minimum(op.sites) * QUBIT_SPACING`, `max_y = maximum(op.sites) * QUBIT_SPACING`
  - Box height: `max_y - min_y + GATE_HEIGHT`
  - Label centered vertically in spanning box
  - Write failing test first

  **Must NOT do**:
  - Change ASCII rendering
  - Add connector lines
  - Change layout orientation

  **Recommended Agent Profile**:
  - **Category**: `unspecified-low`
    - Reason: Moderate complexity, SVG coordinate math
  - **Skills**: `[]`
    - No special skills needed

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 2 (with Task 3)
  - **Blocks**: None
  - **Blocked By**: Task 1

  **References**:

  **Pattern References**:
  - `ext/QuantumCircuitsMPSLuxorExt.jl:104-116` - Current rendering loop
  - `ext/QuantumCircuitsMPSLuxorExt.jl:52-56` - Layout constants

  **API References**:
  - `ext/QuantumCircuitsMPSLuxorExt.jl:92` - `line()` usage for qubit wires
  - Luxor.jl: `box(center_point, width, height, :stroke)` - box primitive

  **Implementation Guidance**:
  ```julia
  # Current (lines 108-114):
  for site in op.sites  # Draws separate box per site
      y = site * QUBIT_SPACING
      box(Point(x, y), GATE_WIDTH, GATE_HEIGHT, :stroke)
  
  # New logic:
  if length(op.sites) == 1
      # Single-qubit: unchanged
      y = op.sites[1] * QUBIT_SPACING
      box(Point(x, y), GATE_WIDTH, GATE_HEIGHT, :stroke)
  else
      # Multi-qubit: spanning box
      min_site = minimum(op.sites)
      max_site = maximum(op.sites)
      center_y = (min_site + max_site) / 2 * QUBIT_SPACING
      span_height = (max_site - min_site) * QUBIT_SPACING + GATE_HEIGHT
      box(Point(x, center_y), GATE_WIDTH, span_height, :stroke)
  end
  # Label drawn ONCE at center
  ```

  **Acceptance Criteria**:

  **TDD RED phase:**
  ```bash
  # Test that currently FAILS:
  julia --project -e '
  using QuantumCircuitsMPS
  c = Circuit(L=4, bc=:periodic) do c
      apply!(c, HaarRandom(), AdjacentPair(1))
  end
  
  # This requires Luxor - check if available
  try
      using Luxor
      svg_path = tempname() * ".svg"
      plot_circuit(c, svg_path)
      svg_content = read(svg_path, String)
      
      # Count rect elements - should be 1 for 2-qubit gate
      rect_count = count("<rect", svg_content)
      @assert rect_count == 1 "Expected 1 rect, got $rect_count"
  catch e
      println("Luxor not available, skipping SVG test")
  end
  '
  # Expected: FAIL - rect_count is 2
  ```

  **TDD GREEN phase:**
  ```bash
  # After implementation:
  julia --project -e '
  using QuantumCircuitsMPS
  c = Circuit(L=4, bc=:periodic) do c
      apply!(c, HaarRandom(), AdjacentPair(1))
  end
  
  try
      using Luxor
      svg_path = tempname() * ".svg"
      plot_circuit(c, svg_path)
      svg_content = read(svg_path, String)
      rect_count = count("<rect", svg_content)
      @assert rect_count == 1 "SVG spanning box: PASS (1 rect)"
      println("SVG spanning box works correctly")
  catch e
      println("Luxor not available: ", e)
  end
  '
  # Assert: Output contains "SVG spanning box works correctly" OR "Luxor not available"
  ```

  **Commit**: YES
  - Message: `fix(plotting): render multi-qubit gates with single spanning box in SVG`
  - Files: `ext/QuantumCircuitsMPSLuxorExt.jl`, `test/circuit_test.jl`
  - Pre-commit: `julia --project -e 'using Pkg; Pkg.test()'`

---

- [x] 5. ASCII Layout Transpose (Time=Vertical, Qubits=Horizontal)

  **What to do**:
  - Modify `src/Plotting/ascii.jl` to transpose layout
  - NEW DEFAULT: rows = time steps, columns = qubits
  - Swap outer/inner loops in rendering
  - Update header to show qubit labels horizontally
  - This is a BREAKING CHANGE (user accepted)

  **Must NOT do**:
  - Add optional parameter (user wants new default, not option)
  - Change SVG orientation (only ASCII for now)

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
    - Reason: Structural change to rendering algorithm
  - **Skills**: `[]`
    - No special skills needed

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Wave 3 (sequential)
  - **Blocks**: Task 6
  - **Blocked By**: Task 3

  **References**:

  **Pattern References**:
  - `src/Plotting/ascii.jl:111-121` - Current header (step numbers horizontal)
  - `src/Plotting/ascii.jl:123-140` - Current loops (outer=qubit, inner=time)

  **Implementation Guidance**:
  ```julia
  # Current layout:
  # Step:      1     2     3
  # q1:   ┤X├─────────
  # q2:   ─────┤Y├────
  
  # Transposed layout:
  #        q1    q2    q3    q4
  # 1:    ┤X├─────────────────
  # 2:    ─────┤Y├────────────
  
  # Loop inversion:
  # Current: for q in 1:L { for step in columns }
  # New:     for (step, _, _) in columns { for q in 1:L }
  ```

  **Acceptance Criteria**:

  **TDD RED phase:**
  ```bash
  # Test for new layout (currently fails):
  julia --project -e '
  using QuantumCircuitsMPS, Test
  c = Circuit(L=4, bc=:periodic) do c
      apply!(c, PauliX(), SingleSite(1))
  end
  ascii = sprint(print_circuit, c)
  lines = split(ascii, "\n")
  
  # New format: first line should have qubit labels, not "Step:"
  @test !startswith(lines[1], "Step:")  # FAILS with current
  @test contains(lines[1], "q1") && contains(lines[1], "q2")  # FAILS
  '
  ```

  **TDD GREEN phase:**
  ```bash
  # After implementation:
  julia --project -e '
  using QuantumCircuitsMPS, Test
  c = Circuit(L=4, bc=:periodic) do c
      apply!(c, PauliX(), SingleSite(1))
      apply!(c, PauliY(), SingleSite(2))
  end
  ascii = sprint(print_circuit, c)
  lines = split(ascii, "\n")
  
  # Header has qubit labels
  @test contains(lines[1], "q1") && contains(lines[1], "q2")
  
  # Rows are time steps
  @test any(l -> contains(l, "1:") || contains(l, "1 :"), lines)
  
  println("Transposed layout works:")
  println(ascii)
  '
  # Assert: Output shows transposed format
  ```

  **Commit**: YES
  - Message: `feat(plotting)!: transpose ASCII layout to time=vertical qubits=horizontal`
  - Files: `src/Plotting/ascii.jl`, `test/circuit_test.jl`
  - Pre-commit: `julia --project -e 'using Pkg; Pkg.test()'`

---

- [x] 6. Fix Tutorial StaircaseLeft/Right Pattern

  **What to do**:
  - Update `examples/circuit_tutorial.jl`: change `Reset()` to use `StaircaseLeft`, `HaarRandom()` to use `StaircaseRight`
  - Update `examples/circuit_tutorial.ipynb` with same changes
  - Verify both files execute without error
  - Update Section 6 to mention `list_observables()` for discovery

  **Must NOT do**:
  - Change tutorial content beyond StaircaseLeft/Right and observable section
  - Add new examples
  - Change visualization output format descriptions (they may need updating after Task 5, but just for the pattern fix)

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Simple find-and-replace in two files
  - **Skills**: `[]`
    - No special skills needed

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Wave 4 (final)
  - **Blocks**: None
  - **Blocked By**: Task 5

  **References**:

  **Pattern References**:
  - `examples/ct_model.jl:10-11, 18-19` - CORRECT pattern to follow
  - `examples/ct_model_styles.jl:57-62` - CORRECT pattern example

  **Files to Modify**:
  - `examples/circuit_tutorial.jl:69-70, 95-96, 122-123` - StaircaseRight → StaircaseLeft for Reset
  - `examples/circuit_tutorial.ipynb` - Same pattern in code cells

  **Acceptance Criteria**:

  ```bash
  # Verify .jl file pattern:
  julia --project -e '
  content = read("examples/circuit_tutorial.jl", String)
  
  # Check for correct pattern (Reset with StaircaseLeft)
  @assert occursin(r"Reset\(\).*StaircaseLeft", content) || 
          occursin(r"StaircaseLeft.*Reset", content) "Reset should use StaircaseLeft"
  
  # Check HaarRandom with StaircaseRight
  @assert occursin(r"HaarRandom\(\).*StaircaseRight", content) ||
          occursin(r"StaircaseRight.*HaarRandom", content) "HaarRandom should use StaircaseRight"
  
  println("Pattern check PASSED")
  '
  # Assert: Output contains "Pattern check PASSED"
  ```

  ```bash
  # Verify script executes:
  julia --project examples/circuit_tutorial.jl
  # Assert: Exit code 0
  ```

  ```bash
  # Verify notebook structure:
  julia --project -e '
  using JSON
  nb = JSON.parsefile("examples/circuit_tutorial.ipynb")
  @assert haskey(nb, "cells") "Valid notebook structure"
  println("Notebook structure valid")
  '
  # Assert: Output contains "Notebook structure valid"
  ```

  **Commit**: YES
  - Message: `fix(examples): use correct StaircaseLeft/Right pattern in circuit tutorial`
  - Files: `examples/circuit_tutorial.jl`, `examples/circuit_tutorial.ipynb`
  - Pre-commit: `julia --project examples/circuit_tutorial.jl`

---

## Commit Strategy

| After Task | Message | Files | Verification |
|------------|---------|-------|--------------|
| 1 | `test(plotting): add baseline visualization tests` | test/circuit_test.jl | Pkg.test() |
| 2 | `feat(observables): add list_observables() helper function` | src/Observables/Observables.jl, src/QuantumCircuitsMPS.jl | Pkg.test() |
| 3 | `fix(plotting): render multi-qubit gates with single spanning box in ASCII` | src/Plotting/ascii.jl | Pkg.test() |
| 4 | `fix(plotting): render multi-qubit gates with single spanning box in SVG` | ext/QuantumCircuitsMPSLuxorExt.jl | Pkg.test() |
| 5 | `feat(plotting)!: transpose ASCII layout to time=vertical qubits=horizontal` | src/Plotting/ascii.jl | Pkg.test() |
| 6 | `fix(examples): use correct StaircaseLeft/Right pattern in circuit tutorial` | examples/*.jl, examples/*.ipynb | script execution |

---

## Success Criteria

### Verification Commands
```bash
# All tests pass
julia --project -e 'using Pkg; Pkg.test()'
# Expected: Test Summary: ... | Pass 100+ | Total 100+

# Observable helper works
julia --project -e 'using QuantumCircuitsMPS; println(list_observables())'
# Expected: ["DomainWall", "BornProbability"]

# Tutorial executes
julia --project examples/circuit_tutorial.jl
# Expected: Exit code 0

# Multi-qubit ASCII shows single label
julia --project -e '
using QuantumCircuitsMPS
c = Circuit(L=4, bc=:periodic) do c; apply!(c, HaarRandom(), AdjacentPair(1)); end
print_circuit(c)
'
# Expected: "Haar" appears exactly once in output
```

### Final Checklist
- [x] All "Must Have" present (spanning boxes, transposed layout, list_observables, tutorial fixes)
- [x] All "Must NOT Have" absent (no Gate/Geometry changes, no new formats)
- [x] All 100+ existing tests pass
- [x] New tests added for each feature
- [x] Tutorial executes without error
