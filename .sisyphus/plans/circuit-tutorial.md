# Circuit Tutorial (Script + Notebook)

## TL;DR

> **Quick Summary**: Create a tutorial demonstrating the Circuit API workflow (build → visualize → simulate) in both executable `.jl` script and interactive `.ipynb` notebook formats.
> 
> **Deliverables**:
> - `examples/circuit_tutorial.jl` - Canonical executable script
> - `examples/circuit_tutorial.ipynb` - Interactive Jupyter notebook
> - SVG circuit diagram in `examples/output/`
> 
> **Estimated Effort**: Quick
> **Parallel Execution**: NO - sequential (notebook depends on script)
> **Critical Path**: Task 1 → Task 2 → Task 3

---

## Context

### Original Request
Create a Jupyter tutorial notebook demonstrating circuit plotting and simulation.

### Interview Summary
**Key Discussions**:
- Format decision: BOTH `.jl` script AND `.ipynb` notebook (user choice)
- Content scope: Circuit API only, no imperative comparison (user choice)
- Visualization: BOTH ASCII and SVG (user choice)

**Research Findings**:
- Project has zero `.ipynb` files - all tutorials are `.jl` scripts
- Reference implementation: `examples/ct_model_circuit_style.jl` (162 lines)
- Circuit API: `Circuit(L, bc, n_steps) do c ... end`
- Visualization: `print_circuit` (ASCII), `plot_circuit` (SVG with Luxor)

### Metis Review
**Identified Gaps** (addressed):
- File format mismatch: Resolved by creating BOTH formats
- Acceptance criteria: Defined agent-executable verification commands
- SVG dependency: Included as opt-in section with Luxor loading

---

## Work Objectives

### Core Objective
Create a comprehensive tutorial demonstrating the Circuit API workflow: build circuits → visualize (ASCII + SVG) → simulate deterministically.

### Concrete Deliverables
- `examples/circuit_tutorial.jl` - Executable script (canonical)
- `examples/circuit_tutorial.ipynb` - Interactive notebook
- `examples/output/circuit_diagram.svg` - Generated SVG visualization

### Definition of Done
- [x] `julia examples/circuit_tutorial.jl` exits with code 0
- [x] Output contains expected circuit visualization
- [x] Notebook executes all cells without error
- [x] SVG file generated when Luxor is available

### Must Have
- Setup section with `Pkg.activate`
- Circuit construction with do-block syntax
- ASCII visualization with `print_circuit`
- SVG visualization with `plot_circuit` (opt-in Luxor section)
- Simulation with `simulate!` and RNG determinism
- Clear section separators (following `ct_model_circuit_style.jl` pattern)

### Must NOT Have (Guardrails)
- Imperative style comparison (user excluded this)
- MPS tensor manipulation (library internals)
- Custom gate definitions (use built-in gates only)
- Performance benchmarking
- Dependencies not in Project.toml (Luxor is weak dep, already supported)

---

## Verification Strategy (MANDATORY)

### Test Decision
- **Infrastructure exists**: YES (project has test suite)
- **User wants tests**: Manual-only (tutorial, not library code)
- **Framework**: N/A (verification via script execution)

### Automated Verification Only (NO User Intervention)

**Script Verification** (using Bash):
```bash
# Agent runs:
julia examples/circuit_tutorial.jl
# Assert: Exit code 0
# Assert: Output contains "Circuit (L=" pattern

# Syntax check:
julia --check-bounds=no -e 'include("examples/circuit_tutorial.jl")'
# Assert: Exit code 0
```

**Notebook Verification** (using Bash):
```bash
# Agent runs:
cd examples && jupyter nbconvert --to notebook --execute circuit_tutorial.ipynb --output executed_tutorial.ipynb
# Assert: Exit code 0
# Assert: executed_tutorial.ipynb exists

# Cleanup:
rm -f examples/executed_tutorial.ipynb
```

**SVG Verification** (using Bash):
```bash
# Agent runs:
ls -la examples/output/circuit_diagram.svg
# Assert: File exists and size > 1KB (valid SVG)
```

---

## Execution Strategy

### Sequential Execution (No Parallelization)

```
Task 1: Create circuit_tutorial.jl (canonical script)
    ↓
Task 2: Create circuit_tutorial.ipynb (from script structure)
    ↓
Task 3: Verify both formats execute correctly
```

**Reason**: Notebook content mirrors script, so script must exist first.

### Dependency Matrix

| Task | Depends On | Blocks | Can Parallelize With |
|------|------------|--------|---------------------|
| 1 | None | 2, 3 | None |
| 2 | 1 | 3 | None |
| 3 | 1, 2 | None | None (final) |

### Agent Dispatch Summary

| Task | Recommended Approach |
|------|---------------------|
| 1 | delegate_task(category="quick", load_skills=[], ...) |
| 2 | Same agent session, continue after Task 1 |
| 3 | Verification in same session |

---

## TODOs

- [x] 1. Create `examples/circuit_tutorial.jl` (Canonical Script)

  **What to do**:
  - Create executable Julia script demonstrating Circuit API
  - Follow structure of `ct_model_circuit_style.jl` for section separators
  - Include: Setup → Build Circuit → ASCII Viz → SVG Viz (opt-in) → Simulate → Summary
  - Use shebang `#!/usr/bin/env julia` for direct execution
  - Add `Pkg.activate(dirname(@__DIR__))` for package loading

  **Content sections**:
  1. Header block: Title, description, key concepts
  2. Setup: `using Pkg; Pkg.activate()`, `using QuantumCircuitsMPS`
  3. Part 1: Building Circuits - do-block syntax, deterministic + stochastic ops
  4. Part 2: ASCII Visualization - `print_circuit` with seed parameter
  5. Part 3: SVG Visualization (opt-in) - Check Luxor, call `plot_circuit`
  6. Part 4: Circuit Simulation - `simulate!`, RNG determinism explanation
  7. Summary: Key takeaways, when to use circuit style

  **Must NOT do**:
  - Include imperative style comparison
  - Use gates not in reference (stick to Reset, HaarRandom, Hadamard, PauliX)
  - Add MPS manipulation code
  - Create output files outside `examples/output/`

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Single file creation, clear template to follow
  - **Skills**: `[]`
    - No special skills needed - straightforward file creation
  - **Skills Evaluated but Omitted**:
    - `frontend-ui-ux`: Not applicable (not UI work)
    - `playwright`: Not applicable (no browser testing)

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Sequential
  - **Blocks**: Task 2, Task 3
  - **Blocked By**: None (can start immediately)

  **References** (CRITICAL - Be Exhaustive):

  **Pattern References** (existing code to follow):
  - `examples/ct_model_circuit_style.jl:1-39` - Header block, section separators (`═`), key concepts format
  - `examples/ct_model_circuit_style.jl:79-88` - Circuit construction do-block pattern
  - `examples/ct_model_circuit_style.jl:93-104` - Visualization section with `print_circuit`
  - `examples/ct_model_circuit_style.jl:106-118` - Simulation section with `simulate!`

  **API/Type References** (contracts to implement against):
  - `src/Circuit/builder.jl:109-138` - `Circuit(f::Function; L, bc, n_steps)` signature and docstring
  - `src/Circuit/builder.jl:50-53` - `apply!(builder, gate, geometry)` for deterministic ops
  - `src/Circuit/builder.jl:81-106` - `apply_with_prob!(builder; rng, outcomes)` for stochastic ops
  - `src/Plotting/ascii.jl:4-74` - `print_circuit(circuit; seed, io, unicode)` full docstring
  - `ext/QuantumCircuitsMPSLuxorExt.jl` - `plot_circuit` extension function

  **Documentation References** (specs and requirements):
  - `.sisyphus/notepads/circuit-visualization/COMPLETION_SUMMARY.md:39-45` - Key features list

  **WHY Each Reference Matters**:
  - `ct_model_circuit_style.jl` provides exact formatting style to match (separator patterns, comment density)
  - `builder.jl` provides API signatures and docstring examples for correct usage
  - `ascii.jl` docstring shows output format and options
  - `COMPLETION_SUMMARY.md` confirms feature set to demonstrate

  **Acceptance Criteria**:

  **Automated Verification:**
  ```bash
  # Test 1: Script exists and has content
  wc -l examples/circuit_tutorial.jl
  # Assert: Line count > 100 (substantial tutorial)

  # Test 2: Script executes without error
  julia examples/circuit_tutorial.jl 2>&1
  # Assert: Exit code 0
  # Assert: Output contains "Circuit (L="
  # Assert: Output contains "q1:" (wire label from ASCII viz)

  # Test 3: Syntax is valid Julia
  julia -e 'include("examples/circuit_tutorial.jl"); println("OK")'
  # Assert: Output contains "OK"

  # Test 4: SVG generated (if Luxor section included)
  test -f examples/output/circuit_diagram.svg && echo "SVG exists"
  # Assert: If Luxor loaded, file exists
  ```

  **Evidence to Capture:**
  - [ ] Terminal output showing script execution success
  - [ ] ASCII circuit diagram in stdout
  - [ ] SVG file in examples/output/ (if Luxor available)

  **Commit**: YES
  - Message: `docs(examples): add circuit tutorial script`
  - Files: `examples/circuit_tutorial.jl`
  - Pre-commit: `julia examples/circuit_tutorial.jl`

---

- [x] 2. Create `examples/circuit_tutorial.ipynb` (Interactive Notebook)

  **What to do**:
  - Convert script structure to Jupyter notebook format
  - Add markdown cells for section explanations
  - Split code into executable cells (one concept per cell)
  - Include setup cell with instructions for running in Jupyter
  - Output cells should show ASCII visualization

  **Notebook structure**:
  1. Title markdown cell (matches script header)
  2. Setup code cell: `using Pkg; Pkg.activate(...)`, imports
  3. Part 1 cells: Circuit building (with markdown explanations)
  4. Part 2 cells: ASCII visualization
  5. Part 3 cells: SVG visualization (opt-in)
  6. Part 4 cells: Simulation
  7. Summary markdown cell

  **Must NOT do**:
  - Diverge from script content (notebook mirrors script)
  - Include output cells in committed file (run on user's machine)
  - Add dependencies not available in project
  - Create complex cell magics or Jupyter-specific features

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Converting existing script to notebook format
  - **Skills**: `[]`
    - No special skills needed - JSON structure manipulation
  - **Skills Evaluated but Omitted**:
    - `frontend-ui-ux`: Not applicable (notebook format, not styling)

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Sequential (after Task 1)
  - **Blocks**: Task 3
  - **Blocked By**: Task 1 (needs script content)

  **References** (CRITICAL - Be Exhaustive):

  **Pattern References** (existing code to follow):
  - `examples/circuit_tutorial.jl` (from Task 1) - Content to convert
  - Standard Jupyter notebook JSON format

  **API/Type References**:
  - Jupyter notebook format v4 schema

  **WHY Each Reference Matters**:
  - Script provides exact content; notebook is structural transformation
  - JSON format must be valid for Jupyter to open

  **Acceptance Criteria**:

  **Automated Verification:**
  ```bash
  # Test 1: Notebook is valid JSON
  python3 -c "import json; json.load(open('examples/circuit_tutorial.ipynb'))"
  # Assert: Exit code 0 (valid JSON)

  # Test 2: Notebook has expected structure
  python3 -c "
  import json
  nb = json.load(open('examples/circuit_tutorial.ipynb'))
  assert 'cells' in nb, 'Missing cells'
  assert len(nb['cells']) >= 10, 'Too few cells'
  print('Notebook structure OK')
  "
  # Assert: Output contains "Notebook structure OK"

  # Test 3: Notebook executes (if jupyter available)
  jupyter nbconvert --to notebook --execute examples/circuit_tutorial.ipynb --output /tmp/executed.ipynb 2>&1 || echo "Jupyter not available"
  # Assert: Exit code 0 OR "Jupyter not available"
  ```

  **Evidence to Capture:**
  - [ ] JSON validation success
  - [ ] Cell count verification
  - [ ] Jupyter execution log (if available)

  **Commit**: YES
  - Message: `docs(examples): add circuit tutorial notebook`
  - Files: `examples/circuit_tutorial.ipynb`
  - Pre-commit: `python3 -c "import json; json.load(open('examples/circuit_tutorial.ipynb'))"`

---

- [x] 3. Verify Both Formats Execute Correctly

  **What to do**:
  - Run script and capture output
  - Validate notebook structure
  - Check SVG generation (if Luxor available)
  - Ensure ASCII visualization appears correctly

  **Must NOT do**:
  - Modify files (verification only)
  - Skip any verification step
  - Accept partial success

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Verification commands only
  - **Skills**: `[]`
    - Standard bash verification

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Sequential (final task)
  - **Blocks**: None (final)
  - **Blocked By**: Task 1, Task 2

  **References**:
  - Task 1 and Task 2 outputs

  **Acceptance Criteria**:

  **Automated Verification:**
  ```bash
  # Final verification suite
  echo "=== Verifying circuit_tutorial.jl ==="
  julia examples/circuit_tutorial.jl 2>&1 | head -50
  echo "Exit code: $?"

  echo "=== Verifying circuit_tutorial.ipynb ==="
  python3 -c "import json; nb=json.load(open('examples/circuit_tutorial.ipynb')); print(f'Cells: {len(nb[\"cells\"])}')"

  echo "=== Checking SVG output ==="
  ls -la examples/output/*.svg 2>/dev/null || echo "No SVG files (Luxor may not be loaded)"

  echo "=== All verifications complete ==="
  ```

  **Evidence to Capture:**
  - [ ] Script execution output (first 50 lines)
  - [ ] Notebook cell count
  - [ ] SVG file listing

  **Commit**: NO (verification only)

---

## Commit Strategy

| After Task | Message | Files | Verification |
|------------|---------|-------|--------------|
| 1 | `docs(examples): add circuit tutorial script` | `examples/circuit_tutorial.jl` | `julia examples/circuit_tutorial.jl` |
| 2 | `docs(examples): add circuit tutorial notebook` | `examples/circuit_tutorial.ipynb` | JSON validation |
| 3 | (no commit - verification only) | - | - |

---

## Success Criteria

### Verification Commands
```bash
# Script runs successfully
julia examples/circuit_tutorial.jl  # Expected: exit 0, ASCII circuit output

# Notebook is valid
python3 -c "import json; json.load(open('examples/circuit_tutorial.ipynb'))"  # Expected: exit 0

# SVG generated (optional)
ls examples/output/circuit_diagram.svg  # Expected: file exists if Luxor loaded
```

### Final Checklist
- [x] Script executes without error
- [x] Notebook is valid JSON with 10+ cells
- [x] ASCII visualization appears in script output
- [x] SVG section included (opt-in with Luxor check)
- [x] No imperative comparison code (excluded by user)
- [x] Section separators match `ct_model_circuit_style.jl` pattern
