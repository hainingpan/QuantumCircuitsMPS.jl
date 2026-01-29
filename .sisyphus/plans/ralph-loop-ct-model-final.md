# Ralph Loop: ct_model.jl Philosophy Compliance (Final Tasks)

## TL;DR

> **Quick Summary**: Complete the Ralph Loop by rewriting ct_model.jl to use proper abstractions and verify physics match.
> 
> **Deliverables**:
> - Rewritten `examples/ct_model.jl` using `Pointer` and `rand(state, :stream)`
> - Passing physics verification against CT.jl reference
> 
> **Estimated Effort**: Quick (2 small tasks)
> **Parallel Execution**: NO - sequential (must verify after rewrite)
> **Critical Path**: ralph-4 → ralph-5

---

## Context

### What Was Already Done (ralph-1 through ralph-3)

1. **ralph-1 COMPLETE**: Added `rand(state, stream)` convenience in `src/Core/rng.jl`
   - Users can now write `rand(state, :ctrl)` instead of `rand(get_rng(state.rng_registry, :ctrl))`

2. **ralph-2 COMPLETE**: Created `Pointer` type in `src/Geometry/pointer.jl`
   - Bidirectional movement via `move!(pointer, :left/:right, L, bc)`
   - Does NOT auto-advance (unlike Staircase)
   - Added dispatch methods in `src/Core/apply.jl` for both regular gates and Reset

3. **ralph-3 COMPLETE**: Removed `set_position!` 
   - Deleted from `src/Geometry/staircase.jl`
   - Removed from exports
   - Contract 2.2 compliance achieved

### Current Problem

`examples/ct_model.jl` still uses the OLD patterns:
- Line 15: `rand(get_rng(state.rng_registry, :ctrl))` - exposes internal `rng_registry`
- Lines 10-11: Two staircases (`StaircaseLeft`, `StaircaseRight`) - unnecessary complexity
- Lines 18, 22: `set_position!` calls - function no longer exists (code will error!)

### Philosophy Goals (from quantum-circuits-mps-v2.md)

- Line 5: "physicist-friendly MPS simulator where users focus on physics (Gates + Geometry)"
- Line 1121: "PyTorch for Quantum Circuits philosophy: physicists code as they speak"
- Line 1134: "Pointer management → Hidden from user"
- Contract 2.2: "Users cannot SET the pointer directly (no set_position! function)"

---

## Work Objectives

### Core Objective
Fix ct_model.jl to have ZERO philosophy violations and maintain physics correctness.

### Concrete Deliverables
- `examples/ct_model.jl` rewritten with proper abstractions
- Passing test: `test/verify_ct_match.jl`

### Definition of Done
- [x] ct_model.jl uses `Pointer` instead of two Staircases
- [x] ct_model.jl uses `rand(state, :ctrl)` instead of `rand(get_rng(...))`
- [x] No `set_position!` calls (they would error anyway)
- [x] `julia test/verify_ct_match.jl` passes (DW1/DW2 match within 1e-5)

### Must Have
- Single `Pointer(L)` for bidirectional movement
- `rand(state, :ctrl)` for random decisions
- `move!(pointer, :left/:right, L, :periodic)` for explicit direction control

### Must NOT Have (Guardrails)
- ❌ `get_rng()` calls - expose internals
- ❌ `set_position!()` - violates Contract 2.2 (and no longer exists)
- ❌ Two synchronized Staircases - unnecessary complexity
- ❌ Direct access to `state.rng_registry` field

---

## Verification Strategy

### Test Decision
- **Infrastructure exists**: YES (verify_ct_match.jl)
- **Verification method**: Run existing verification test
- **Framework**: Julia test script

### Acceptance Criteria
Physics verification MUST pass: DW1 and DW2 values must match CT.jl reference within 1e-5.

---

## Execution Strategy

### Sequential Execution
```
ralph-4: Rewrite ct_model.jl
    ↓
ralph-5: Verify physics match
```

No parallelization - must verify after rewrite.

---

## TODOs

### ✅ COMPLETED (for reference)
- [x] ralph-1: Add rand(state, stream) convenience
- [x] ralph-2: Create Pointer type for bidirectional movement
- [x] ralph-3: Remove set_position! (Contract 2.2 violation)

---

- [x] ralph-4. Rewrite ct_model.jl with proper abstractions

  **What to do**:
  
  Replace the current ct_model.jl content with:
  
  ```julia
  # CT Model - QuantumCircuitsMPS v2
  # Physicists code as they speak: Gates + Geometry, no MPS details

  using Pkg; Pkg.activate(dirname(@__DIR__))
  using QuantumCircuitsMPS
  using JSON

  function run_dw_t(L::Int, p_ctrl::Float64, p_proj::Float64, seed_C::Int, seed_m::Int)
      # Single bidirectional pointer - no syncing needed
      pointer = Pointer(L)
      
      # Circuit step: control vs Bernoulli with direction change
      function circuit_step!(state, t)
          if rand(state, :ctrl) < p_ctrl
              # CONTROL: Reset at current site, move LEFT
              apply!(state, Reset(), pointer)
              move!(pointer, :left, L, :periodic)
          else
              # BERNOULLI: HaarRandom at current pair, move RIGHT
              apply!(state, HaarRandom(), pointer)
              move!(pointer, :right, L, :periodic)
          end
      end
      
      # i1 for DomainWall depends on current pointer position
      get_i1(state, t) = (current_position(pointer) % L) + 1
      
      # Run simulation using functional API
      results = simulate(
          L = L,
          bc = :periodic,
          init = ProductState(x0 = 1//2^L),
          rng = RNGRegistry(Val(:ct_compat), circuit=seed_C, measurement=seed_m),
          steps = 2 * L^2,
          circuit! = circuit_step!,
          observables = [:DW1 => DomainWall(order=1), :DW2 => DomainWall(order=2)],
          i1_fn = get_i1
      )
      
      Dict("L"=>L, "p_ctrl"=>p_ctrl, "p_proj"=>p_proj, "seed_C"=>seed_C,
           "seed_m"=>seed_m, "DW1"=>results[:DW1], "DW2"=>results[:DW2])
  end

  if abspath(PROGRAM_FILE) == @__FILE__
      result = run_dw_t(10, 0.5, 0.0, 42, 123)
      mkpath(joinpath(dirname(@__DIR__), "examples/output"))
      open(joinpath(dirname(@__DIR__), "examples/output/ct_model_L10_sC42_sm123.json"), "w") do f
          JSON.print(f, result, 4)
      end
      println("Done! DW1[1:5]: ", result["DW1"][1:5])
  end
  ```

  **Must NOT do**:
  - Do NOT use `get_rng()` anywhere
  - Do NOT use `set_position!()` anywhere
  - Do NOT use two Staircase objects
  - Do NOT access `state.rng_registry` directly

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Single file replacement, exact content provided
  - **Skills**: None needed - straightforward file write

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Sequential
  - **Blocks**: ralph-5
  - **Blocked By**: None

  **References**:
  - Current file: `examples/ct_model.jl` - REPLACE ENTIRELY
  - New abstractions: `src/Geometry/pointer.jl` - Pointer type implementation
  - RNG convenience: `src/Core/rng.jl:117-125` - rand(state, stream) implementation

  **Acceptance Criteria**:
  - [x] File written successfully
  - [x] No syntax errors: `julia -e 'include("examples/ct_model.jl")' ` loads without error
  - [x] File contains `Pointer(L)` (single pointer)
  - [x] File contains `rand(state, :ctrl)` (convenience function)
  - [x] File contains `move!(pointer, :left, L, :periodic)` (explicit movement)
  - [x] File does NOT contain `get_rng` (grep returns empty)
  - [x] File does NOT contain `set_position!` (grep returns empty)
  - [x] File does NOT contain `StaircaseLeft` or `StaircaseRight` (grep returns empty)

  **Commit**: YES
  - Message: `fix(examples): rewrite ct_model.jl with Pointer and rand(state, stream)`
  - Files: `examples/ct_model.jl`
  - Pre-commit: Syntax check passes

---

- [x] ralph-5. Verify physics still matches CT.jl

  **What to do**:
  Run the physics verification test to ensure the rewritten example produces identical results.

  **Must NOT do**:
  - Do NOT skip this step even if syntax check passes
  - Do NOT accept "close enough" - must be within 1e-5

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Single command execution, pass/fail verification
  - **Skills**: None needed

  **Parallelization**:
  - **Can Run In Parallel**: NO (depends on ralph-4)
  - **Parallel Group**: Sequential (final task)
  - **Blocks**: Nothing (end of chain)
  - **Blocked By**: ralph-4

  **References**:
  - Test file: `test/verify_ct_match.jl` - verification script
  - Reference data: `test/ct_reference/` - CT.jl outputs

  **Acceptance Criteria**:
  - [x] Run: `julia test/verify_ct_match.jl`
  - [x] Output contains "PASS" or "All tests passed"
  - [x] DW1 values match within 1e-5
  - [x] DW2 values match within 1e-5

  **Commit**: NO (verification only)

---

## Success Criteria

### Verification Commands
```bash
# Syntax check
julia -e 'include("examples/ct_model.jl")'  # Expected: no errors

# Philosophy compliance check
grep -c "get_rng" examples/ct_model.jl      # Expected: 0
grep -c "set_position!" examples/ct_model.jl # Expected: 0
grep -c "StaircaseLeft\|StaircaseRight" examples/ct_model.jl  # Expected: 0

# Physics verification
julia test/verify_ct_match.jl               # Expected: PASS
```

### Final Checklist
- [x] ct_model.jl uses Pointer (single bidirectional geometry)
- [x] ct_model.jl uses rand(state, :ctrl) (hides rng_registry)
- [x] ct_model.jl uses move!(pointer, direction, L, bc) (explicit movement)
- [x] No philosophy violations remain
- [x] Physics verification passes

---

## Post-Completion: Ralph Loop Exit

After ralph-5 passes, the Ralph Loop is complete. Output:

```
<promise>DONE</promise>
```

This signals that ct_model.jl now 100% matches the philosophy in `.sisyphus/plans/quantum-circuits-mps-v2.md`.
