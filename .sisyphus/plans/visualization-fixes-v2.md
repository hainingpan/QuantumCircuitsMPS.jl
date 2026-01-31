# Visualization Fixes v2 (Final)

## TL;DR

> **Quick Summary**: Fix SVG white fill, tutorial bugs, optimize tests. ASCII OUT OF SCOPE.
> 
> **Deliverables**:
> - SVG gate boxes hide qubit lines (white fill)
> - Tutorial: StaircaseLeft fixes + observable access example
> - Tests run faster (reduce n_circuits/n_steps)
> 
> **Estimated Effort**: ~10 minutes
> **Parallel Execution**: YES - all independent
> **ASCII**: REMOVED FROM SCOPE

---

## TODOs

- [x] 1. Test Suite Optimization

  **What to do**:
  - Line 267: `n_circuits=5` → `n_circuits=2`
  - Line 268: `@test length(...) == 6` → `== 3` (assertion fix!)
  - Line 285: `n_circuits=5` → `n_circuits=2`
  - Line 286: Update assertion to match (if exists)
  - Line 290: `n_steps=20` → `n_steps=10`

  **References**:
  - `test/circuit_test.jl:267-268`
  - `test/circuit_test.jl:285-286`
  - `test/circuit_test.jl:290`

  **Acceptance Criteria**:
  ```bash
  # Tests must pass
  julia --project -e 'using Pkg; Pkg.test()'
  # Exit code 0
  ```

  **Commit**: `perf(test): reduce n_circuits and n_steps for faster tests`

---

- [x] 2. SVG White Fill

  **What to do**:
  Add white fill BEFORE stroke on box() calls (~lines 113, 123):
  ```julia
  sethue("white")
  box(Point(x, y), width, height, :fill)
  sethue("black")
  box(Point(x, y), width, height, :stroke)
  ```

  **References**:
  - `ext/QuantumCircuitsMPSLuxorExt.jl:113` - single-qubit gate box
  - `ext/QuantumCircuitsMPSLuxorExt.jl:123` - multi-qubit gate box

  **Acceptance Criteria**:
  ```bash
  # Verify code has white fill
  grep -B1 'box.*:stroke' ext/QuantumCircuitsMPSLuxorExt.jl | grep -q 'sethue.*white' && echo "PASS" || echo "FAIL"
  ```

  **Commit**: `fix(plotting): SVG gate boxes fill white to hide qubit lines`

---

- [x] 3. Tutorial Fixes

  **What to do**:
  - Fix ALL `Reset()` + `StaircaseRight` → `StaircaseLeft`:
    - `examples/circuit_tutorial.jl` lines 94-96
    - `examples/circuit_tutorial.ipynb` lines 158, 279
  - Add observable access example at END of tutorial:
    ```julia
    # Accessing recorded observable data
    dw_values = state.observables[:dw1]
    println("Domain wall measurements: ", dw_values)
    ```

  **References**:
  - `examples/circuit_tutorial.jl`
  - `examples/circuit_tutorial.ipynb`

  **Acceptance Criteria**:
  ```bash
  # No Reset+StaircaseRight
  ! grep -E "Reset.*StaircaseRight" examples/circuit_tutorial.jl
  ! grep -E "Reset.*StaircaseRight" examples/circuit_tutorial.ipynb
  
  # Observable access exists
  grep -q "state.observables" examples/circuit_tutorial.jl && echo "PASS" || echo "FAIL"
  ```

  **Commit**: `fix(tutorial): StaircaseLeft pattern + observable access example`

---

## Success Criteria

- [x] Tests pass
- [x] SVG code has white fill before stroke
- [x] No Reset+StaircaseRight in tutorials
- [x] Observable access example at end of tutorial
