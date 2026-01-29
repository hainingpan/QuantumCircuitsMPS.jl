# CT Model API Refinement - Philosophy Compliance v2

## TL;DR

> **Quick Summary**: Improve ct_model.jl to truly embody "physicists code as they speak" by extending `apply_with_prob!` with else_branch support and using existing Staircase types.
> 
> **Deliverables**:
> - Extended `apply_with_prob!` function with `else_branch` parameter
> - Rewritten `examples/ct_model.jl` using the cleaner API
> - Passing physics verification
> 
> **Estimated Effort**: Quick (3 tasks)
> **Parallel Execution**: NO - sequential
> **Critical Path**: api-1 → api-2 → api-3

---

## Context

### User Feedback (CRITICAL)

The user correctly identified that the previous ct_model.jl implementation still had philosophy violations:

1. **Manual Pointer management**: Why create a new `Pointer` type with manual `move!()` when `StaircaseLeft` and `StaircaseRight` already encapsulate directional movement?

2. **Low-level randomness**: Using `rand(state, :ctrl) < p_ctrl` is still exposing randomness internals. The physicist's intent is "with probability p_ctrl, do X; otherwise do Y" - this should be expressed with `apply_with_prob!`.

### The Insight

The CT algorithm is fundamentally an **either/or choice**:
- With probability `p_ctrl`: Reset at current site, move LEFT
- With probability `1-p_ctrl`: HaarRandom at current pair, move RIGHT

The existing `apply_with_prob!` only handles "maybe apply" - it needs to be extended to handle "apply this OR that".

### Philosophy Goal

**Physicist speaks**: "With probability p_ctrl, Reset and move left; otherwise HaarRandom and move right"

**Code should read**:
```julia
apply_with_prob!(state, Reset(), left, p_ctrl;
                else_branch=(HaarRandom(), right))
```

NOT:
```julia
if rand(state, :ctrl) < p_ctrl
    apply!(state, Reset(), pointer)
    move!(pointer, :left, L, :periodic)
else
    apply!(state, HaarRandom(), pointer)
    move!(pointer, :right, L, :periodic)
end
```

---

## Work Objectives

### Core Objective
Refine the API so ct_model.jl reads like natural physics descriptions.

### Concrete Deliverables
- `src/API/probabilistic.jl` - extended `apply_with_prob!` with `else_branch`
- `examples/ct_model.jl` - rewritten with cleaner API
- Passing physics verification

### Definition of Done
- [x] `apply_with_prob!` accepts optional `else_branch=(gate, geo)` parameter
- [x] ct_model.jl uses `apply_with_prob!` with `else_branch` instead of if/else
- [x] ct_model.jl uses `StaircaseLeft`/`StaircaseRight` instead of `Pointer`
- [x] No `rand(state, :ctrl)` calls in ct_model.jl
- [x] No manual `move!()` calls in ct_model.jl
- [x] Physics verification passes (DW1/DW2 match within 1e-4)

### Must Have
- Backward compatible extension (existing `apply_with_prob!` calls still work)
- Single random draw for either/or decisions (Contract 4.4 compliance)
- Staircase auto-advancement preserved

### Must NOT Have (Guardrails)
- ❌ Breaking changes to existing API
- ❌ Manual pointer/position management in example
- ❌ Low-level RNG access in example

---

## Verification Strategy

### Test Decision
- **Infrastructure exists**: YES (verify_ct_match.jl)
- **Verification method**: Run existing test
- **Tolerance**: 1e-4

---

## TODOs

- [x] api-1. Extend apply_with_prob! to support else_branch parameter

  **What to do**:
  
  Modify `src/API/probabilistic.jl` to add `else_branch` keyword argument:
  
  ```julia
  """
      apply_with_prob!(state, gate, geo, prob; rng=:ctrl, else_branch=nothing)
  
  Conditionally apply a gate with probability `prob`, with optional else branch.
  
  CRITICAL: Per Contract 4.4, this function ALWAYS draws a random number from the 
  specified RNG stream BEFORE checking the probability. This ensures deterministic 
  RNG advancement regardless of which branch is taken.
  
  Arguments:
  - state: SimulationState
  - gate: AbstractGate to apply if rand < prob
  - geo: AbstractGeometry where to apply the gate
  - prob: Probability of application (0.0 to 1.0)
  - rng: Symbol identifying the RNG stream in state.rng_registry (default :ctrl)
  - else_branch: Optional tuple (gate, geo) to apply if rand >= prob
  
  Examples:
      # Simple probabilistic application (original behavior)
      apply_with_prob!(state, Reset(), site, 0.3)
      
      # Either/or branching (new behavior)
      apply_with_prob!(state, Reset(), left, p_ctrl;
                      else_branch=(HaarRandom(), right))
  """
  function apply_with_prob!(
      state::SimulationState,
      gate::AbstractGate,
      geo::AbstractGeometry,
      prob::Float64;
      rng::Symbol = :ctrl,
      else_branch::Union{Nothing, Tuple{AbstractGate, AbstractGeometry}} = nothing
  )
      # Get the actual RNG from state's registry
      actual_rng = get_rng(state.rng_registry, rng)
      
      # CRITICAL: ALWAYS draw random number BEFORE checking prob
      # This ensures deterministic RNG advancement
      r = rand(actual_rng)
      
      # Conditionally apply based on drawn value
      if r < prob
          apply!(state, gate, geo)
      elseif else_branch !== nothing
          # Apply the else branch if provided
          else_gate, else_geo = else_branch
          apply!(state, else_gate, else_geo)
      end
      return nothing
  end
  ```

  **Must NOT do**:
  - Do NOT break backward compatibility
  - Do NOT change the single random draw behavior
  - Do NOT modify Contract 4.4 compliance

  **Recommended Agent Profile**:
  - **Category**: `quick`
  - **Skills**: None needed

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Blocks**: api-2
  - **Blocked By**: None

  **References**:
  - Current file: `src/API/probabilistic.jl` - MODIFY
  - Contract 4.4 in plan: Random draw must happen before probability check

  **Acceptance Criteria**:
  - [x] File modified with new else_branch parameter
  - [x] Existing calls without else_branch still work (backward compatible)
  - [x] Julia syntax check passes

  **Commit**: YES
  - Message: `feat(api): add else_branch parameter to apply_with_prob!`
  - Files: `src/API/probabilistic.jl`

---

- [x] api-2. Rewrite ct_model.jl using apply_with_prob! with else_branch and StaircaseLeft/Right

  **What to do**:
  
  Replace `examples/ct_model.jl` with cleaner version:
  
  ```julia
  # CT Model - QuantumCircuitsMPS v2
  # Physicists code as they speak: Gates + Geometry, no MPS details
  
  using Pkg; Pkg.activate(dirname(@__DIR__))
  using QuantumCircuitsMPS
  using JSON
  
  function run_dw_t(L::Int, p_ctrl::Float64, p_proj::Float64, seed_C::Int, seed_m::Int)
      # Staircases encapsulate directional movement
      left = StaircaseLeft(L)
      right = StaircaseRight(L)
      
      # Circuit step: physicist speaks "with prob p_ctrl, Reset+left; else HaarRandom+right"
      function circuit_step!(state, t)
          apply_with_prob!(state, Reset(), left, p_ctrl;
                          else_branch=(HaarRandom(), right))
      end
      
      # i1 for DomainWall depends on current pointer position
      # Note: left and right are synced by the either/or logic
      get_i1(state, t) = (current_position(left) % L) + 1
      
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
  - Do NOT use `Pointer` type
  - Do NOT use `move!()` function
  - Do NOT use `rand(state, :ctrl)` directly
  - Do NOT use if/else for the probabilistic choice

  **Recommended Agent Profile**:
  - **Category**: `quick`
  - **Skills**: None needed

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Blocks**: api-3
  - **Blocked By**: api-1

  **References**:
  - Current file: `examples/ct_model.jl` - REPLACE ENTIRELY
  - New API: `src/API/probabilistic.jl` - apply_with_prob! with else_branch

  **Acceptance Criteria**:
  - [x] File uses `StaircaseLeft(L)` and `StaircaseRight(L)`
  - [x] File uses `apply_with_prob!` with `else_branch=`
  - [x] File does NOT contain `Pointer`
  - [x] File does NOT contain `move!`
  - [x] File does NOT contain `rand(state,`
  - [x] Syntax check passes

  **Commit**: YES
  - Message: `refactor(examples): use apply_with_prob! else_branch in ct_model.jl`
  - Files: `examples/ct_model.jl`

---

- [x] api-3. Verify physics still matches CT.jl

  **What to do**:
  Run physics verification to ensure the cleaner API produces identical results.

  **Recommended Agent Profile**:
  - **Category**: `quick`
  - **Skills**: None needed

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Blocks**: None
  - **Blocked By**: api-2

  **References**:
  - Test file: `test/verify_ct_match.jl`

  **Acceptance Criteria**:
  - [x] Run: `julia test/verify_ct_match.jl`
  - [x] Output shows PASS
  - [x] DW1/DW2 match within tolerance

  **Commit**: NO (verification only)

---

## Success Criteria

### Verification Commands
```bash
# Syntax check
julia -e 'include("examples/ct_model.jl")'  # Expected: no errors

# Philosophy compliance check
grep -c "Pointer" examples/ct_model.jl           # Expected: 0
grep -c "move!" examples/ct_model.jl             # Expected: 0
grep -c "rand(state" examples/ct_model.jl        # Expected: 0
grep -c "apply_with_prob!" examples/ct_model.jl  # Expected: 1
grep -c "else_branch" examples/ct_model.jl       # Expected: 1

# Physics verification
julia test/verify_ct_match.jl  # Expected: PASS
```

### Final Checklist
- [x] apply_with_prob! extended with else_branch
- [x] ct_model.jl uses StaircaseLeft/StaircaseRight
- [x] ct_model.jl uses apply_with_prob! with else_branch
- [x] No low-level RNG access in example
- [x] No manual pointer management in example
- [x] Physics verification passes

---

## Philosophy Achievement

**Before** (current ct_model.jl - still low-level):
```julia
pointer = Pointer(L)
if rand(state, :ctrl) < p_ctrl
    apply!(state, Reset(), pointer)
    move!(pointer, :left, L, :periodic)
else
    apply!(state, HaarRandom(), pointer)
    move!(pointer, :right, L, :periodic)
end
```

**After** (physicist speaks):
```julia
left = StaircaseLeft(L)
right = StaircaseRight(L)
apply_with_prob!(state, Reset(), left, p_ctrl;
                else_branch=(HaarRandom(), right))
```

The code now reads like the physics: "With probability p_ctrl, Reset and advance left staircase; otherwise HaarRandom and advance right staircase."
