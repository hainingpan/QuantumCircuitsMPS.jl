# API Refinement - Final User Choices

## TL;DR

> **Quick Summary**: Implement user's final API choices: rename `apply_branch!` → `apply_with_prob!`, simplify DomainWall with `i1_fn` parameter, remove verbose `run_circuit!` wrapper, and clean up `record!` to not require manual `i1` passing.
> 
> **Deliverables**:
> - Modified `src/API/probabilistic.jl` - rename + new semantics
> - Modified `src/Observables/domain_wall.jl` - add `i1_fn` support
> - Modified `src/Observables/Observables.jl` - simplify `record!`
> - Modified `src/QuantumCircuitsMPS.jl` - update exports
> - Updated examples to use new clean API
> 
> **Estimated Effort**: Small-Medium
> **Parallel Execution**: NO - sequential changes
> **Critical Path**: Task 1 → Task 2 → Task 3 → Task 4 → Task 5 → Task 6

---

## Context

### User's Final Choices

1. **Probabilistic API**: Choose Style C (Named Parameters) but:
   - Rename `apply_branch!` → `apply_with_prob!` (more physical)
   - Allow `sum(probabilities) ≤ 1` (implicit "do nothing" branch)
   - Error if `sum(probabilities) > 1 + tolerance`

2. **Simulation API**: Choose Style 1 (Imperative) but:
   - Remove `run_circuit!` - it's just a loop, keep it explicit
   - Simplify `track!/record!` - DomainWall should capture `i1_fn`
   - `record!(state)` should work without manual `i1` parameter

### Target API (What User's Code Will Look Like)

```julia
# Setup
left = StaircaseLeft(L)
right = StaircaseRight(1)
rng = RNGRegistry(Val(:ct_compat), circuit=seed_C, measurement=seed_m)

state = SimulationState(L=L, bc=:periodic, rng=rng)
initialize!(state, ProductState(x0 = 1//2^L))

# DomainWall captures i1_fn at registration - called automatically during record!
get_i1() = (current_position(left) % L) + 1
track!(state, :DW1 => DomainWall(order=1, i1_fn=get_i1))

# Simple circuit step with new name
circuit_step!(s) = apply_with_prob!(s; rng=:ctrl, outcomes=[
    (probability=p_ctrl, gate=Reset(), geometry=left),
    (probability=1-p_ctrl, gate=HaarRandom(), geometry=right)
])

# Simulation loop - plain Julia, no wrapper
record!(state)  # Initial - no i1 needed!
for circuit in 1:N_CIRCUITS
    for _ in 1:L
        circuit_step!(state)
    end
    if circuit % RECORD_EVERY == 0
        record!(state)  # Clean!
    end
end

results = state.observables[:DW1]
```

---

## Work Objectives

### Core Objective
Implement user's final API choices to create a clean, physicist-friendly interface.

### Concrete Deliverables
- `apply_with_prob!` function with sum≤1 semantics
- `DomainWall(order, i1_fn)` constructor
- Simplified `record!(state)` without `i1` parameter
- Updated exports (add `apply_with_prob!`, keep `apply_branch!` as deprecated alias)
- Updated examples demonstrating clean API

### Definition of Done
- [x] `apply_with_prob!` works with sum≤1, errors on sum>1
- [x] `DomainWall(order=1, i1_fn=get_i1)` captures the function
- [x] `record!(state)` calls `i1_fn()` automatically for DomainWall
- [x] `apply_branch!` still works but prints deprecation warning
- [x] Examples run without error
- [x] Module loads successfully

### Must Have
- Backwards compatibility for `apply_branch!` (deprecated alias)
- `i1_fn` is optional in DomainWall (for backwards compat with explicit `i1`)
- Clear error messages

### Must NOT Have (Guardrails)
- DO NOT break existing `record!(state; i1=...)` syntax (still supported)
- DO NOT remove `run_circuit!` entirely (just don't use in examples, keep for users who want it)
- DO NOT add unnecessary abstractions

---

## TODOs

- [x] 1. Update `apply_branch!` → `apply_with_prob!` with new semantics

  **What to do**:
  - In `src/API/probabilistic.jl`:
    - Rename function to `apply_with_prob!`
    - Change probability validation: error if `sum > 1 + 1e-10`
    - If `r >= sum(probs)`, return without applying (do nothing branch)
    - Add `apply_branch!` as deprecated alias that calls `apply_with_prob!`
  
  **Implementation**:
  ```julia
  function apply_with_prob!(
      state::SimulationState;
      rng::Symbol = :ctrl,
      outcomes::Vector{<:NamedTuple{(:probability, :gate, :geometry)}}
  )
      probs = [o.probability for o in outcomes]
      total_prob = sum(probs)
      
      # Error if probabilities sum to more than 1
      if total_prob > 1.0 + 1e-10
          error("Probabilities sum to $total_prob (must be ≤ 1)")
      end
      
      # CRITICAL: Draw BEFORE checking (Contract 4.4)
      actual_rng = get_rng(state.rng_registry, rng)
      r = rand(actual_rng)
      
      # Check each outcome
      cumulative = 0.0
      for outcome in outcomes
          cumulative += outcome.probability
          if r < cumulative
              apply!(state, outcome.gate, outcome.geometry)
              return nothing
          end
      end
      
      # If we get here: "do nothing" branch selected (r >= sum(probs))
      return nothing
  end
  
  # Backwards compatibility
  function apply_branch!(state::SimulationState; rng::Symbol = :ctrl, outcomes::Vector)
      @warn "apply_branch! is deprecated, use apply_with_prob! instead" maxlog=1
      apply_with_prob!(state; rng=rng, outcomes=outcomes)
  end
  ```

  **References**:
  - `src/API/probabilistic.jl:1-66` - Current implementation

  **Acceptance Criteria**:
  - [ ] `apply_with_prob!` function exists
  - [ ] Sum ≤ 1 works (do nothing when r >= sum)
  - [ ] Sum > 1 + 1e-10 throws error
  - [ ] `apply_branch!` still works with deprecation warning

  **Commit**: NO (group with other changes)

---

- [x] 2. Update DomainWall to accept `i1_fn` parameter

  **What to do**:
  - In `src/Observables/domain_wall.jl`:
    - Add `i1_fn::Union{Function, Nothing}` field to struct
    - Update constructor to accept optional `i1_fn` keyword
    - Keep backwards compatibility (i1_fn defaults to nothing)
  
  **Implementation**:
  ```julia
  struct DomainWall <: AbstractObservable
      order::Int
      i1_fn::Union{Function, Nothing}
      
      function DomainWall(; order::Int, i1_fn::Union{Function, Nothing}=nothing)
          order >= 1 || throw(ArgumentError("DomainWall order must be >= 1"))
          new(order, i1_fn)
      end
  end
  
  # Callable struct - now checks for i1_fn
  function (dw::DomainWall)(state, i1::Union{Int, Nothing}=nothing)
      actual_i1 = if dw.i1_fn !== nothing
          dw.i1_fn()  # Call the captured function
      elseif i1 !== nothing
          i1  # Use explicit parameter
      else
          throw(ArgumentError("DomainWall requires either i1_fn at construction or i1 at call time"))
      end
      return domain_wall(state, actual_i1, dw.order)
  end
  ```

  **References**:
  - `src/Observables/domain_wall.jl:1-25` - Current DomainWall struct

  **Acceptance Criteria**:
  - [ ] `DomainWall(order=1, i1_fn=get_i1)` works
  - [ ] `DomainWall(order=1)` still works (backwards compat)
  - [ ] Callable with no args when i1_fn is set
  - [ ] Callable with explicit i1 when i1_fn is not set

  **Commit**: NO (group with other changes)

---

- [x] 3. Simplify `record!` to not require `i1` parameter

  **What to do**:
  - In `src/Observables/Observables.jl`:
    - Modify `record!` to call observable with no `i1` when DomainWall has `i1_fn`
    - Keep backwards compat: if `i1` is passed, use it
  
  **Implementation**:
  ```julia
  function record!(state; i1::Union{Int,Nothing}=nothing)
      for (name, obs) in state.observable_specs
          if obs isa DomainWall
              if obs.i1_fn !== nothing
                  # i1_fn is set - call with no args, DomainWall will use i1_fn
                  value = obs(state)
              elseif i1 !== nothing
                  # Explicit i1 passed - use it
                  value = obs(state, i1)
              else
                  throw(ArgumentError(
                      "DomainWall '$name' requires either i1_fn at registration or i1 at record! call"
                  ))
              end
          else
              value = obs(state)
          end
          push!(state.observables[name], value)
      end
      return nothing
  end
  ```

  **References**:
  - `src/Observables/Observables.jl:29-49` - Current record! implementation

  **Acceptance Criteria**:
  - [ ] `record!(state)` works when DomainWall has i1_fn
  - [ ] `record!(state; i1=5)` still works (backwards compat)
  - [ ] Clear error when neither i1_fn nor i1 provided

  **Commit**: NO (group with other changes)

---

- [x] 4. Update module exports

  **What to do**:
  - In `src/QuantumCircuitsMPS.jl`:
    - Add `apply_with_prob!` to exports
    - Keep `apply_branch!` in exports (for backwards compat)
    - Keep `run_circuit!` in exports (users may want it)
  
  **Implementation**:
  Change line 54 from:
  ```julia
  export apply!, simulate, with_state, current_state, apply_branch!
  ```
  To:
  ```julia
  export apply!, simulate, with_state, current_state, apply_with_prob!, apply_branch!
  ```

  **References**:
  - `src/QuantumCircuitsMPS.jl:54` - API exports line

  **Acceptance Criteria**:
  - [ ] `apply_with_prob!` is exported
  - [ ] `apply_branch!` is still exported
  - [ ] Module loads without error

  **Commit**: NO (group with other changes)

---

- [x] 5. Update `ct_model_simulation_styles.jl` example

  **What to do**:
  - Replace `apply_branch!` with `apply_with_prob!`
  - Replace `run_circuit!` with explicit loop
  - Use `DomainWall(order=1, i1_fn=get_i1)` pattern
  - Remove `i1` parameter from `record!` calls
  - Keep only Style 1 (Imperative) as the main example, note others in comments
  
  **Target code for Style 1**:
  ```julia
  function run_style1_imperative()
      left = StaircaseLeft(L)
      right = StaircaseRight(1)
      rng = RNGRegistry(Val(:ct_compat), circuit=seed_C, measurement=seed_m)
      
      state = SimulationState(L=L, bc=:periodic, rng=rng)
      initialize!(state, ProductState(x0 = 1//2^L))
      
      # i1_fn captured at registration
      get_i1() = (current_position(left) % L) + 1
      track!(state, :DW1 => DomainWall(order=1, i1_fn=get_i1))
      
      # Circuit step with renamed API
      circuit_step!(s) = apply_with_prob!(s; rng=:ctrl, outcomes=[
          (probability=p_ctrl, gate=Reset(), geometry=left),
          (probability=1-p_ctrl, gate=HaarRandom(), geometry=right)
      ])
      
      # Initial recording - no i1 needed!
      record!(state)
      
      # Plain loop - no run_circuit! wrapper
      for circuit in 1:N_CIRCUITS
          for _ in 1:L
              circuit_step!(state)
          end
          if circuit % RECORD_EVERY == 0
              record!(state)
          end
      end
      
      return state.observables[:DW1]
  end
  ```

  **References**:
  - `examples/ct_model_simulation_styles.jl:26-57` - Current Style 1

  **Acceptance Criteria**:
  - [ ] Uses `apply_with_prob!` instead of `apply_branch!`
  - [ ] Uses explicit `for _ in 1:L` loop instead of `run_circuit!`
  - [ ] Uses `DomainWall(order=1, i1_fn=get_i1)`
  - [ ] Uses `record!(state)` without `i1` parameter
  - [ ] Example runs without error

  **Commit**: NO (group with other changes)

---

- [x] 6. Update `ct_model_styles.jl` example

  **What to do**:
  - Replace `apply_branch!` with `apply_with_prob!` in Style C
  - Update other styles similarly if they use apply_branch!
  - Update comments to reflect renamed function
  
  **References**:
  - `examples/ct_model_styles.jl:157-186` - Style C implementation

  **Acceptance Criteria**:
  - [ ] Style C uses `apply_with_prob!`
  - [ ] Example runs without error
  - [ ] Physics verification still passes

  **Commit**: NO (group with final commit)

---

- [x] 7. Verify and commit

  **What to do**:
  - Run module load test
  - Run both examples
  - Commit all changes with descriptive message
  
  **Verification commands**:
  ```bash
  julia --project=. -e 'using QuantumCircuitsMPS; println("✓ Module loads")'
  julia --project=. examples/ct_model_simulation_styles.jl
  julia --project=. examples/ct_model_styles.jl
  ```

  **Acceptance Criteria**:
  - [ ] Module loads without error
  - [ ] Both examples run successfully
  - [ ] Physics verification passes in ct_model_styles.jl

  **Commit**: YES
  - Message: `refactor(api): finalize user API choices - apply_with_prob!, DomainWall i1_fn, simplified record!`
  - Files: All modified files

---

## Success Criteria

### Verification Commands
```bash
# Module loads
julia --project=. -e 'using QuantumCircuitsMPS; println("✓ Module loads")'

# New API works
julia --project=. -e '
using QuantumCircuitsMPS
# Test apply_with_prob! with sum < 1 (do nothing branch)
state = SimulationState(L=4, bc=:open, rng=RNGRegistry(Val(:ct_compat), circuit=1, measurement=1))
initialize!(state, ProductState(x0=0))
site = SingleSite(1)
apply_with_prob!(state; outcomes=[(probability=0.3, gate=PauliX(), geometry=site)])
println("✓ apply_with_prob! works")
'

# Examples run
julia --project=. examples/ct_model_simulation_styles.jl
julia --project=. examples/ct_model_styles.jl
```

### Final Checklist
- [x] `apply_with_prob!` exported and working
- [x] `apply_branch!` still works (deprecated)
- [x] `DomainWall(order=1, i1_fn=...)` works
- [x] `record!(state)` works without `i1` when `i1_fn` is set
- [x] Examples use new clean API
- [x] Backwards compatibility maintained
