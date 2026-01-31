# SVG Inline Display + Notebook Fixes (Round 3)

## TL;DR

> **Quick Summary**: Fix 3 remaining issues: (1) Make `plot_circuit()` auto-display SVG in Jupyter notebooks, (2) Rewrite Demo A/B to use Circuit API with `simulate!`, (3) Clean up notebook by deleting 6 redundant cells and renumbering sections.
> 
> **Deliverables**:
> - Modified `plot_circuit()` with auto-display in Jupyter via `SVGImage` wrapper type
> - Demo A/B cells rewritten to use `Circuit do-block + simulate!` pattern
> - Clean notebook with sequential section numbering (1-7)
> 
> **Estimated Effort**: Medium
> **Parallel Execution**: NO - sequential (Issue 2 depends on understanding Issue 1 changes, Issue 3 must come last)
> **Critical Path**: Issue 1 → Issue 2 → Issue 3

---

## Context

### Original Request
Fix 3 remaining issues identified in previous session:
1. SVG should auto-display inline in Jupyter (not just write to file)
2. Tracking demos use wrong API formalism (imperative instead of Circuit API)
3. Notebook is messy with redundant cells and broken section numbering

### Interview Summary
**Key Discussions**:
- SVG behavior: User wants **auto-display in Jupyter** (not just return string)
- Demo values: Different numbers acceptable (focus on API pattern, not exact values)
- Section numbering: Renumber to fill gap (5→4, 6→5, etc.)

**Research Findings**:
- Luxor uses `Drawing(w, h, :svg)` for in-memory + `svgstring()` after `finish()` to extract
- IJulia auto-displays via `Base.show(io, MIME"image/svg+xml", x)` method
- `simulate!` API: `simulate!(circuit, state; n_circuits=N, record_initial=bool, record_every=M)`
- Recording contract: initial (if requested) + every Mth circuit + always final

### Metis Review
**Identified Gaps** (addressed):
- Luxor `finish()` must be called BEFORE `svgstring()` - verified from docs
- Demo rewrite needs Circuit definition FIRST, then simulate! - plan includes this
- JSON notebook editing risk - will use proper JSON operations, not raw line editing
- RNG alignment between imperative/Circuit APIs may differ - accepted (different values OK)

---

## Work Objectives

### Core Objective
Complete the visualization and notebook improvements by implementing Jupyter auto-display for SVG, converting demos to Circuit API, and cleaning up the notebook structure.

### Concrete Deliverables
- `ext/QuantumCircuitsMPSLuxorExt.jl`: Add `SVGImage` type + `Base.show` method + modify `plot_circuit()` return
- `examples/circuit_tutorial.ipynb`: Rewritten Demo A/B cells, 6 cells deleted, sections renumbered 1-7

### Definition of Done
- [x] `plot_circuit(circuit)` auto-displays SVG in Jupyter (no filename needed)
- [x] `plot_circuit(circuit; filename="x.svg")` still writes file (backward compat)
- [x] Demo A uses `simulate!(circuit, state; n_circuits=3, record_initial=false, record_every=1)` → 3 recordings
- [x] Demo B uses `simulate!(circuit, state; n_circuits=3, record_initial=false, record_every=3)` → 2 recordings (sparse)
- [x] Notebook sections are sequential: 1, 2, 3, 4, 5, 6, 7
- [x] No error cells or undefined variable references remain

### Must Have
- SVG auto-display works in Jupyter via MIME type
- Backward compatibility: file-writing mode unchanged
- Demo cells demonstrate Circuit API pattern correctly
- Clean notebook with no broken cells

### Must NOT Have (Guardrails)
- DO NOT break existing `plot_circuit(circuit; filename="x.svg")` usage
- DO NOT change observable tracking setup (DomainWall with order=1)
- DO NOT change RNG seeds in demos (keep ctrl=1, proj=2, haar=3, born=4)
- DO NOT delete cells with unique educational content
- DO NOT leave malformed JSON in notebook

---

## Verification Strategy (MANDATORY)

### Test Decision
- **Infrastructure exists**: YES (test/circuit_test.jl exists)
- **User wants tests**: Manual verification + automated checks
- **Framework**: Julia Test module

### Automated Verification

**Issue 1 - SVG Auto-Display**:
```bash
# Test script execution
julia --project=. -e '
using QuantumCircuitsMPS, Luxor, Test

circuit = Circuit(L=4, bc=:periodic, n_steps=2) do c
    apply!(c, Reset(), StaircaseRight(1))
end

# Test 1: File mode still works
plot_circuit(circuit; filename="/tmp/test_circuit.svg")
@test isfile("/tmp/test_circuit.svg")
@test contains(read("/tmp/test_circuit.svg", String), "<svg")

# Test 2: In-memory mode returns SVGImage
result = plot_circuit(circuit)
@test result isa QuantumCircuitsMPS.SVGImage
@test contains(result.data, "<svg")
@test contains(result.data, "</svg>")
@test contains(result.data, "q1")

println("✓ All SVG tests passed")
'
```

**Issue 2 - Demo API Migration**:
```bash
# Run notebook cells and verify recording counts
julia --project=. -e '
using QuantumCircuitsMPS, Test

# Demo A pattern - record every circuit
circuit = Circuit(L=4, bc=:periodic, n_steps=1) do c
    apply!(c, HaarRandom(), StaircaseRight(1))
end

state_a = SimulationState(L=4, bc=:periodic, rng=RNGRegistry(ctrl=1, proj=2, haar=3, born=4))
initialize!(state_a, ProductState(x0=1//16))
track!(state_a, :dw => DomainWall(; order=1, i1_fn=() -> 1))
simulate!(circuit, state_a; n_circuits=3, record_initial=false, record_every=1)

@test length(state_a.observables[:dw]) == 3
println("Demo A: ", state_a.observables[:dw])

# Demo B pattern - sparse recording (every 3rd circuit, but also first due to modulo)
# Recording formula: (circuit_idx - 1) % record_every == 0 OR circuit_idx == n_circuits
# With n_circuits=3, record_every=3: records at circuit 1 (0%3==0) and circuit 3 (final)
state_b = SimulationState(L=4, bc=:periodic, rng=RNGRegistry(ctrl=1, proj=2, haar=3, born=4))
initialize!(state_b, ProductState(x0=1//16))
track!(state_b, :dw => DomainWall(; order=1, i1_fn=() -> 1))
simulate!(circuit, state_b; n_circuits=3, record_initial=false, record_every=3)

@test length(state_b.observables[:dw]) == 2  # Circuits 1 and 3
println("Demo B: ", state_b.observables[:dw])

println("✓ All Demo tests passed")
'
```

**Issue 3 - Notebook Cleanup**:
```bash
# Validate notebook JSON structure
python3 -c "import json; json.load(open('examples/circuit_tutorial.ipynb')); print('✓ Valid JSON')"

# Check section numbering
grep -o '"## Section [0-9]' examples/circuit_tutorial.ipynb | sort -u

# Check no error cells remain
! grep -q '"ename":' examples/circuit_tutorial.ipynb && echo "✓ No error cells"
```

---

## Execution Strategy

### Sequential Execution (NOT Parallel)

**Rationale**: Issues have soft dependencies:
- Issue 2 (demos) should reflect Issue 1's new pattern if applicable
- Issue 3 (cleanup) must come after Issue 2 to delete correct cells

```
Task 1 (Issue 1): SVG Auto-Display
    ↓
Task 2 (Issue 2): Demo API Migration  
    ↓
Task 3 (Issue 3): Notebook Cleanup
    ↓
Task 4: Final Verification + Commit
```

### Dependency Matrix

| Task | Depends On | Blocks |
|------|------------|--------|
| 1 (SVG) | None | 4 (verification) |
| 2 (Demos) | None | 3, 4 |
| 3 (Cleanup) | 2 | 4 |
| 4 (Verify) | 1, 2, 3 | None |

---

## TODOs

- [x] 1. Implement SVG Auto-Display in Jupyter

  **What to do**:
  1. Add `SVGImage` struct to hold SVG string data
  2. Add `Base.show(io, MIME"image/svg+xml", img::SVGImage)` method for auto-display
  3. Modify `plot_circuit()` signature: `filename::Union{String, Nothing}=nothing`
  4. When `filename === nothing`: use `Drawing(w, h, :svg)`, extract with `svgstring()`, return `SVGImage`
  5. When `filename` provided: use existing file-writing logic, return `nothing`
  6. Export `SVGImage` from module

  **Must NOT do**:
  - Change behavior when `filename` IS provided (backward compat)
  - Call `svgstring()` before `finish()` (order matters!)

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Single file modification, clear pattern to follow
  - **Skills**: `[]`
    - No special skills needed (pure Julia code)

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Sequential (Task 1)
  - **Blocks**: Task 4
  - **Blocked By**: None

  **References**:
  
  **Pattern References**:
  - `ext/QuantumCircuitsMPSLuxorExt.jl:51-140` - Current `plot_circuit()` implementation to modify
  
  **Luxor API References** (VERIFIED via testing):
  - `Drawing(width, height, :svg)` - Creates in-memory SVG drawing surface (verified: works with positional args)
  - `svgstring()` - Extracts SVG string AFTER `finish()` is called (no arguments, uses current drawing)
  - **Verified call sequence**: `Drawing(w, h, :svg)` → drawing operations → `finish()` → `svgstring()` → returns SVG string
  - **Verification command run**:
    ```julia
    Drawing(200, 200, :svg); background("white"); origin(); circle(Point(0, 0), 50, :stroke); finish(); svg_str = svgstring()
    # Result: 599-char SVG string containing "<svg" and "</svg>" tags
    ```
  
  **CRITICAL: Luxor uses implicit global drawing context**:
  - `Drawing()` sets global state (do NOT store its return value, it's not needed)
  - All drawing operations (`circle()`, `text()`, etc.) affect the "current drawing"
  - `finish()` finalizes the current drawing
  - `svgstring()` extracts SVG from the most recently finished drawing (no args needed)
  
  **IJulia MIME Display Protocol** (VERIFIED via testing):
  - Define `Base.show(io::IO, ::MIME"image/svg+xml", img::SVGImage)` method
  - Implementation: `write(io, img.data)` to write SVG string to output
  - **Verification command run**:
    ```julia
    struct TestSVG; data::String; end
    Base.show(io::IO, ::MIME"image/svg+xml", img::TestSVG) = write(io, img.data)
    hasmethod(Base.show, Tuple{IO, MIME"image/svg+xml", TestSVG})  # Returns true
    ```
  
  **SVGImage Type Definition**:
  ```julia
  """Wrapper type for SVG data that auto-displays in Jupyter notebooks."""
  struct SVGImage
      data::String
  end
  
  # MIME display method for IJulia auto-rendering
  function Base.show(io::IO, ::MIME"image/svg+xml", img::SVGImage)
      write(io, img.data)
  end
  ```
  
  **Export Strategy** (CHOSEN: Extension-local type):
  - Define `SVGImage` inside the extension module (loaded only when Luxor is available)
  - Extension modules cannot export to parent module scope
  - User accesses via return value: `img = plot_circuit(circuit)` → `img.data` to get raw string
  - The MIME show method enables auto-display in Jupyter without explicit access
  - **Type check**: Use `typeof(result).name.name == :SVGImage` (duck typing) or `hasproperty(result, :data)`
  
  **Why this strategy**: Simpler implementation, no stub needed in main module, adequate for Jupyter auto-display use case. Users don't need to `isa` check the type—they just call `plot_circuit()` and it renders.

  **Acceptance Criteria**:

  ```bash
  # Agent executes:
  julia --project=. -e '
  using QuantumCircuitsMPS, Luxor, Test
  
  circuit = Circuit(L=4, bc=:periodic, n_steps=2) do c
      apply!(c, Reset(), StaircaseRight(1))
  end
  
  # Test 1: File mode backward compatibility
  plot_circuit(circuit; filename="/tmp/test_circuit.svg")
  @test isfile("/tmp/test_circuit.svg")
  svg_file = read("/tmp/test_circuit.svg", String)
  @test contains(svg_file, "<svg")
  @test contains(svg_file, "q1")
  
  # Test 2: In-memory mode returns SVGImage wrapper
  result = plot_circuit(circuit)
  @test typeof(result).name.name == :SVGImage  # Type defined in extension module
  @test hasproperty(result, :data)
  @test contains(result.data, "<svg")
  @test contains(result.data, "</svg>")
  @test contains(result.data, "q1")
  
  # Test 3: SVGImage has MIME show method (enables Jupyter auto-display)
  io = IOBuffer()
  show(io, MIME("image/svg+xml"), result)
  @test contains(String(take!(io)), "<svg")
  
  rm("/tmp/test_circuit.svg")
  println("✓ All SVG auto-display tests passed")
  '
  ```
  
  **Evidence**:
  - [x] Test output shows "All SVG auto-display tests passed"
  - [x] No test failures

  **Commit**: YES
  - Message: `feat(svg): add auto-display in Jupyter via SVGImage wrapper`
  - Files: `ext/QuantumCircuitsMPSLuxorExt.jl`
  - Pre-commit: SVG tests pass

---

- [x] 2. Rewrite Demo A/B to Use Circuit API

  **What to do**:
  1. Locate Demo A cell (around lines 545-552)
  2. Replace imperative loop with Circuit API:
     ```julia
     # Demo A: Track at every circuit execution
     demo_circuit = Circuit(L=4, bc=:periodic, n_steps=1) do c
         apply!(c, HaarRandom(), StaircaseRight(1))
     end
     
     state_a = SimulationState(L=4, bc=:periodic, rng=RNGRegistry(ctrl=1, proj=2, haar=3, born=4))
     initialize!(state_a, ProductState(x0=1//16))
     track!(state_a, :dw => DomainWall(; order=1, i1_fn=() -> 1))
     
     simulate!(demo_circuit, state_a; n_circuits=3, record_initial=false, record_every=1)
     println("Every-circuit recordings (", length(state_a.observables[:dw]), " values): ", state_a.observables[:dw])
     ```
  3. Locate Demo B cell (around lines 587-593)
  4. Replace imperative loop with Circuit API:
     ```julia
     # Demo B: Sparse recording (record_every=3 records at circuits 1 and 3)
     # Recording formula: (circuit_idx - 1) % record_every == 0 OR circuit_idx == n_circuits
     state_b = SimulationState(L=4, bc=:periodic, rng=RNGRegistry(ctrl=1, proj=2, haar=3, born=4))
     initialize!(state_b, ProductState(x0=1//16))
     track!(state_b, :dw => DomainWall(; order=1, i1_fn=() -> 1))
     
     simulate!(demo_circuit, state_b; n_circuits=3, record_initial=false, record_every=3)
     println("Sparse recording (", length(state_b.observables[:dw]), " values): ", state_b.observables[:dw])
     ```
  5. Update Demo A markdown explanation to reference `record_every=1` (every circuit)
  6. Update Demo B markdown explanation to reference `record_every=3` (sparse recording - circuits 1 and 3 only)

  **Must NOT do**:
  - Change the observable being tracked (keep DomainWall order=1)
  - Change RNG seeds (keep ctrl=1, proj=2, haar=3, born=4)
  - Delete the comparative narrative between Demo A and Demo B

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Notebook cell edits with clear pattern from research
  - **Skills**: `[]`
    - No special skills needed

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Sequential (Task 2, after Task 1)
  - **Blocks**: Task 3, Task 4
  - **Blocked By**: None (soft dependency on Task 1 for consistency)

  **References**:
  
  **Pattern References**:
  - `src/Circuit/execute.jl:5-60` - `simulate!` function signature and recording contract
  - `test/circuit_test.jl:219-310` - Test examples showing `simulate!` with various `record_every` values
  
  **API References**:
  - `simulate!(circuit, state; n_circuits=N, record_initial=Bool, record_every=M)` - Main execution API
  - `track!(state, :name => Observable(...))` - Observable registration
  - `Circuit(L=N, bc=:sym, n_steps=M) do c; ...; end` - Circuit do-block syntax
  
  **Current Code References**:
  - `examples/circuit_tutorial.ipynb:545-552` - Demo A cell to replace
  - `examples/circuit_tutorial.ipynb:587-593` - Demo B cell to replace

  **Acceptance Criteria**:

  ```bash
  # Agent executes:
  julia --project=. -e '
  using QuantumCircuitsMPS, Test
  
  # Replicate Demo A pattern
  demo_circuit = Circuit(L=4, bc=:periodic, n_steps=1) do c
      apply!(c, HaarRandom(), StaircaseRight(1))
  end
  
  state_a = SimulationState(L=4, bc=:periodic, rng=RNGRegistry(ctrl=1, proj=2, haar=3, born=4))
  initialize!(state_a, ProductState(x0=1//16))
  track!(state_a, :dw => DomainWall(; order=1, i1_fn=() -> 1))
  simulate!(demo_circuit, state_a; n_circuits=3, record_initial=false, record_every=1)
  
  @test length(state_a.observables[:dw]) == 3
  println("Demo A verified: 3 recordings")
  
  # Replicate Demo B pattern
  state_b = SimulationState(L=4, bc=:periodic, rng=RNGRegistry(ctrl=1, proj=2, haar=3, born=4))
  initialize!(state_b, ProductState(x0=1//16))
  track!(state_b, :dw => DomainWall(; order=1, i1_fn=() -> 1))
  simulate!(demo_circuit, state_b; n_circuits=3, record_initial=false, record_every=3)
  
  @test length(state_b.observables[:dw]) == 2
  println("Demo B verified: 2 recordings (sparse: circuits 1 and 3)")
  
  println("✓ Demo API patterns verified")
  '
  ```
  
  **Evidence**:
  - [x] Demo A shows exactly 3 recordings
  - [x] Demo B shows exactly 2 recordings (sparse: circuits 1 and 3)
  - [x] Notebook cell executes without error

  **Commit**: YES
  - Message: `fix(notebook): rewrite demos to use Circuit API with simulate!`
  - Files: `examples/circuit_tutorial.ipynb`
  - Pre-commit: Demo verification passes

---

- [x] 3. Clean Up Notebook: Delete Redundant Cells + Renumber Sections

  **What to do**:
  1. Load notebook as JSON: `json.load(open('examples/circuit_tutorial.ipynb'))`
  2. Delete these 6 redundant cells (identify by source content):
     - Cell with source `"p_reset"` only (debugging artifact)
     - Cell with source `"short_circuit"` (undefined variable error)
     - Cell with isolated `plot_circuit(mixed_circuit; ...)` call (redundant)
     - Cell with source `"BornProbability"` only (type inspection)
     - Cell with source `"state.observables"` only (empty dict display)
     - Cell with source `"state_a"` only (verbose object dump)
  3. Renumber sections in markdown cells:
     - "## Section 5" → "## Section 4"
     - "## Section 6" → "## Section 5"
     - "## Section 7" → "## Section 6"
     - "## Section 8" → "## Section 7"
  4. Save notebook with proper JSON formatting
  5. Validate: `python3 -c "import json; json.load(open('examples/circuit_tutorial.ipynb'))"`

  **Must NOT do**:
  - Delete cells with unique educational content
  - Break JSON structure (watch for trailing commas)
  - Change cell execution order numbers (Jupyter handles this)
  - Delete markdown cells explaining concepts

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: JSON manipulation, straightforward deletions
  - **Skills**: `[]`
    - No special skills needed

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Sequential (Task 3, after Task 2)
  - **Blocks**: Task 4
  - **Blocked By**: Task 2

  **References**:
  
  **File References**:
  - `examples/circuit_tutorial.ipynb` - Target notebook
  
  **Cells to Delete** (identify by source content, not line numbers):
  - Source contains only `"p_reset"` 
  - Source contains only `"short_circuit"`
  - Source contains `plot_circuit(mixed_circuit;` (the duplicate, not the main one)
  - Source contains only `"BornProbability"`
  - Source contains only `"state.observables"`
  - Source contains only `"state_a"`
  
  **Robust Cell Deletion Strategy** (Python JSON approach - RECOMMENDED):
  ```python
  import json
  
  with open('examples/circuit_tutorial.ipynb') as f:
      nb = json.load(f)
  
  # Delete cells where source (joined as string) matches exactly
  cells_to_delete = []
  for i, cell in enumerate(nb['cells']):
      if cell['cell_type'] == 'code':
          source_str = ''.join(cell['source']).strip()
          # Exact match for single-expression cells
          if source_str in ['p_reset', 'short_circuit', 'BornProbability', 
                            'state.observables', 'state_a']:
              cells_to_delete.append(i)
          # Partial match for duplicate plot_circuit call
          elif 'plot_circuit(mixed_circuit' in source_str and 'examples/output' in source_str:
              cells_to_delete.append(i)
  
  # Delete in reverse order to avoid index shifting
  for i in reversed(cells_to_delete):
      del nb['cells'][i]
  
  # Save with proper formatting
  with open('examples/circuit_tutorial.ipynb', 'w') as f:
      json.dump(nb, f, indent=1)
  ```
  This approach avoids fragile grep-based JSON matching and ensures robust cell identification.

  **Acceptance Criteria**:

  ```bash
  # Agent executes:
  
  # Test 1: Valid JSON
  python3 -c "import json; json.load(open('examples/circuit_tutorial.ipynb')); print('✓ Valid JSON')"
  
  # Test 2: Section numbering is sequential
  grep -o '"## Section [0-9]' examples/circuit_tutorial.ipynb | tr -d '"' | sort -u
  # Expected output should show Section 1 through Section 7 with no gaps
  
  # Test 3: No error cells remain
  ! grep -q '"ename":' examples/circuit_tutorial.ipynb && echo "✓ No error output cells"
  
  # Test 4: Redundant cells removed (check for absence)
  ! grep -q '"source": \["p_reset"\]' examples/circuit_tutorial.ipynb && echo "✓ p_reset cell removed"
  ! grep -q '"source": \["short_circuit"\]' examples/circuit_tutorial.ipynb && echo "✓ short_circuit cell removed"
  ! grep -q '"source": \["BornProbability"\]' examples/circuit_tutorial.ipynb && echo "✓ BornProbability cell removed"
  ```
  
  **Evidence**:
  - [x] `python3 -c "import json; ..."` exits with code 0
  - [x] Section headers are sequential 1-7
  - [x] No `"ename"` fields in notebook (no error outputs)

  **Commit**: YES
  - Message: `chore(notebook): delete redundant cells and renumber sections`
  - Files: `examples/circuit_tutorial.ipynb`
  - Pre-commit: JSON validation passes

---

- [x] 4. Final Verification and Combined Commit

  **What to do**:
  1. Run full SVG test suite
  2. Run Demo API verification
  3. Validate notebook structure
  4. If all pass, create combined commit (or verify individual commits are clean)

  **Must NOT do**:
  - Skip any verification step
  - Commit with failing tests

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Verification only, no code changes
  - **Skills**: `[]`

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Sequential (final task)
  - **Blocks**: None
  - **Blocked By**: Tasks 1, 2, 3

  **References**:
  - All previous task acceptance criteria

  **Acceptance Criteria**:

  ```bash
  # Run all verification commands from Tasks 1-3
  # All must pass
  
  # Final git status check
  git status
  git log --oneline -5
  ```
  
  **Evidence**:
  - [x] All tests pass
  - [x] Git shows clean state or proper commits

  **Commit**: Verification only (individual tasks already committed)

---

## Commit Strategy

| After Task | Message | Files | Verification |
|------------|---------|-------|--------------|
| 1 | `feat(svg): add auto-display in Jupyter via SVGImage wrapper` | ext/QuantumCircuitsMPSLuxorExt.jl | SVG tests |
| 2 | `fix(notebook): rewrite demos to use Circuit API with simulate!` | examples/circuit_tutorial.ipynb | Demo verification |
| 3 | `chore(notebook): delete redundant cells and renumber sections` | examples/circuit_tutorial.ipynb | JSON validation |

---

## Success Criteria

### Verification Commands
```bash
# SVG auto-display
julia --project=. -e 'using QuantumCircuitsMPS, Luxor; c = Circuit(L=4, bc=:periodic, n_steps=1) do c; apply!(c, Reset(), StaircaseRight(1)); end; r = plot_circuit(c); println(typeof(r), " with ", length(r.data), " chars")'
# Expected: SVGImage with ~NNNN chars

# Demo recording counts
julia --project=. -e 'using QuantumCircuitsMPS; c = Circuit(L=4, bc=:periodic, n_steps=1) do c; apply!(c, HaarRandom(), StaircaseRight(1)); end; s = SimulationState(L=4, bc=:periodic, rng=RNGRegistry(ctrl=1, proj=2, haar=3, born=4)); initialize!(s, ProductState(x0=1//16)); track!(s, :dw => DomainWall(; order=1, i1_fn=() -> 1)); simulate!(c, s; n_circuits=3, record_initial=false, record_every=1); println("Demo A: ", length(s.observables[:dw]), " recordings")'
# Expected: Demo A: 3 recordings

# Notebook validity
python3 -c "import json; json.load(open('examples/circuit_tutorial.ipynb')); print('Valid')"
# Expected: Valid
```

### Final Checklist
- [x] `plot_circuit(circuit)` returns `SVGImage` (auto-displays in Jupyter)
- [x] `plot_circuit(circuit; filename="x.svg")` writes file (backward compat)
- [x] Demo A has exactly 3 recordings
- [x] Demo B has exactly 2 recordings (sparse: circuits 1 and 3)
- [x] Notebook JSON is valid
- [x] Sections are numbered 1-7 sequentially
- [x] No error cells remain in notebook
