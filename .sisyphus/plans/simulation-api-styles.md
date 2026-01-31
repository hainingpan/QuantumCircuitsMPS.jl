# Simulation API Styles

## TL;DR

> **Quick Summary**: Implement 3 simulation API styles (Imperative, Callback, Iterator) to give users circuit-level control over simulations. Users think in "circuits" (L steps), not raw steps. After implementation, user selects preferred style (same process as probabilistic API).
> 
> **Deliverables**:
> - `src/API/simulation_styles/style_imperative.jl` - `run_circuit!()` helper
> - `src/API/simulation_styles/style_callback.jl` - `simulate_circuits()` with `on_circuit!` callback
> - `src/API/simulation_styles/style_iterator.jl` - `CircuitSimulation` struct with iteration protocol
> - `examples/ct_model_simulation_styles.jl` - Comparison showing all 3 styles
> - Update `src/QuantumCircuitsMPS.jl` to include and export new APIs
> 
> **Estimated Effort**: Medium
> **Parallel Execution**: YES - 3 waves
> **Critical Path**: Task 1 (directory+includes) → Tasks 2,3,4 (parallel) → Task 5 (comparison) → Task 6 (verification)

---

## Context

### Original Request
User identified that current `simulate()` records at wrong granularity (steps vs circuits). They want:
1. One circuit = `circuit_step! × L` (one full sweep across system)
2. User-controlled recording timing (e.g., "every 2 circuits")
3. Compare 3 API styles before choosing (same process as probabilistic API)

### Interview Summary
**Key Discussions**:
- "Physicists code as they speak" - circuits match mental model
- Three styles: Imperative (run_circuit!), Callback (simulate_circuits), Iterator (CircuitSimulation)
- All must produce identical physics for same seeds

**Research Findings**:
- Current `simulate()` at `src/API/functional.jl:1-69` - step-based
- CT model at `examples/ct_model.jl` uses `steps = 2*L^2`
- Probabilistic styles pattern at `src/_deprecated/probabilistic_styles/`
- Comparison pattern at `examples/ct_model_styles.jl`

### Metis Review
**Identified Gaps** (addressed):
- Terminology: "circuit" = L gate applications (applied as default)
- Staircase reset: User-configurable via `reset_geometry!` parameter
- Iterator invalidation: Document as undefined behavior
- RNG semantics: Recording doesn't affect RNG (preserve current behavior)

---

## Work Objectives

### Core Objective
Implement 3 simulation API styles that operate at circuit granularity, allowing users to control when observables are recorded.

### Concrete Deliverables
- `src/API/simulation_styles/style_imperative.jl`
- `src/API/simulation_styles/style_callback.jl`
- `src/API/simulation_styles/style_iterator.jl`
- `examples/ct_model_simulation_styles.jl`

### Definition of Done
- [x] All 3 styles produce IDENTICAL DW1, DW2 values for same seed (exact match, not approximate)
- [x] Existing `examples/ct_model.jl` still works unchanged (backwards compatibility)
- [x] Each style has comprehensive docstring with Usage example and Pros/Cons
- [x] Comparison example runs without error: `julia examples/ct_model_simulation_styles.jl`

### Must Have
- Style 1: `run_circuit!(state, circuit_step!, L)` helper function
- Style 2: `simulate_circuits()` with `on_circuit!` callback, `circuits` parameter
- Style 3: `CircuitSimulation` struct implementing `Base.iterate()`
- Comparison example demonstrating "record every 2 circuits" in each style
- Physics verification that all 3 styles match

### Must NOT Have (Guardrails)
- DO NOT modify existing `simulate()` function - leave intact for backwards compatibility
- DO NOT add checkpointing, logging, or timing infrastructure
- DO NOT create abstract base types unifying the 3 styles (premature abstraction)
- DO NOT add recording features beyond what's needed (no "record window", no "record conditions")
- DO NOT modify `record!` function behavior
- DO NOT create new Staircase types or modify staircase interface

---

## Verification Strategy

### Test Decision
- **Infrastructure exists**: YES (Julia's `@assert` pattern used in existing comparison files)
- **User wants tests**: Manual verification (same pattern as `ct_model_styles.jl`)
- **Framework**: Simple assertions with `@assert`

### Manual Execution Verification

**For each style implementation:**
```julia
# Run in Julia REPL:
julia> using Pkg; Pkg.activate(".")
julia> include("src/API/simulation_styles/style_X.jl")
# Should load without errors
```

**For comparison example:**
```bash
cd /mnt/d/Rutgers/QuantumCircuitsMPS.jl
julia examples/ct_model_simulation_styles.jl
# Expected output: "All 3 styles produce identical results!" or similar
```

**Physics verification command:**
```julia
@assert results_imperative == results_callback == results_iterator
```

---

## Execution Strategy

### Parallel Execution Waves

```
Wave 1 (Start Immediately):
└── Task 1: Create directory structure

Wave 2 (After Wave 1):
├── Task 2: Style 1 - Imperative (no dependencies on other styles)
├── Task 3: Style 2 - Callback (no dependencies on other styles)
└── Task 4: Style 3 - Iterator (no dependencies on other styles)

Wave 3 (After Wave 2):
└── Task 5: Comparison example (needs all 3 styles)

Wave 4 (After Wave 3):
└── Task 6: Physics verification

Critical Path: Task 1 → Task 2 → Task 5 → Task 6
Parallel Speedup: ~40% faster than sequential (styles can run in parallel)
```

### Dependency Matrix

| Task | Depends On | Blocks | Can Parallelize With |
|------|------------|--------|---------------------|
| 1 | None | 2, 3, 4 | None |
| 2 | 1 | 5 | 3, 4 |
| 3 | 1 | 5 | 2, 4 |
| 4 | 1 | 5 | 2, 3 |
| 5 | 2, 3, 4 | 6 | None |
| 6 | 5 | None | None (final) |

### Agent Dispatch Summary

| Wave | Tasks | Recommended Agents |
|------|-------|-------------------|
| 1 | 1 | delegate_task(category="quick", ...) |
| 2 | 2, 3, 4 | dispatch 3 parallel agents |
| 3 | 5 | delegate_task(category="unspecified-low", ...) |
| 4 | 6 | manual verification |

---

## TODOs

- [x] 1. Create directory structure and module integration

  **What to do**:
  - Create `src/API/simulation_styles/` directory
  - Add includes to `src/QuantumCircuitsMPS.jl` (after line 32, before exports):
    ```julia
    # Simulation styles (circuit-level APIs)
    include("API/simulation_styles/style_imperative.jl")
    include("API/simulation_styles/style_callback.jl")
    include("API/simulation_styles/style_iterator.jl")
    ```
  - Add exports to `src/QuantumCircuitsMPS.jl` (in the API export section, line 49):
    ```julia
    export run_circuit!, simulate_circuits, CircuitSimulation
    export record_every, record_at_circuits, record_always
    export get_state, get_observables, circuits_run
    ```
  - Verify directory exists with `ls`

  **Must NOT do**:
  - Don't create any `.jl` files yet (just directory and module updates)
  - Don't modify any existing exports or includes

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Directory creation + simple module edits
  - **Skills**: []
    - No special skills needed

  **Parallelization**:
  - **Can Run In Parallel**: NO (blocks all subsequent tasks)
  - **Parallel Group**: Wave 1 (alone)
  - **Blocks**: Tasks 2, 3, 4
  - **Blocked By**: None

  **References**:
  - `src/QuantumCircuitsMPS.jl:1-58` - Module file to modify (add includes after line 32, exports after line 49)
  - `src/API/` - Parent directory structure

  **Acceptance Criteria**:
  - [x] `ls src/API/simulation_styles/` → directory exists (empty)
  - [x] `src/QuantumCircuitsMPS.jl` contains `include("API/simulation_styles/style_imperative.jl")`
  - [x] `src/QuantumCircuitsMPS.jl` contains `export run_circuit!, simulate_circuits, CircuitSimulation`

  **Commit**: NO (group with style implementations)

---

- [x] 2. Style 1: Imperative (run_circuit! helper)

  **What to do**:
  - Create `src/API/simulation_styles/style_imperative.jl`
  - Header comment block with PROS/CONS (follow pattern from `src/_deprecated/probabilistic_styles/style_a_action.jl`)
  - **NOTE**: File must be designed to be `include`d within the module context (NOT standalone)
  - Add comment at top: `# This file is meant to be included in the QuantumCircuitsMPS module context`
  - Implement `run_circuit!(state, circuit_step!, L)` function
  - Implement overload `run_circuit!(state, circuit_step!, L, reset_geometry!)` for optional geometry reset
  - Comprehensive docstring with usage example

  **Circuit Step Signature (CRITICAL)**:
  The new APIs use `circuit_step!(state)` (1-arg), NOT the existing `circuit!(state, t)` (2-arg).
  - **Why**: Circuit number is tracked externally; step function shouldn't need it
  - **User adaptation**: Wrap existing 2-arg functions: `circuit_step!(state) = circuit!(state, 0)`
  - **This is documented in docstrings**

  **reset_geometry! Semantics (CRITICAL)**:
  The `reset_geometry!` parameter is a user-provided function that resets any mutable geometry state.
  - **Purpose**: Staircases have internal `_position` field (`src/Geometry/staircase.jl:19,32`) that accumulates
  - **User provides**: `reset_geometry! = () -> (left._position = L; right._position = 1)` or similar
  - **When called**: At the START of each circuit (before L steps)
  - **Example in docstring**: Show how to reset StaircaseLeft/Right positions

  **Must NOT do**:
  - Don't create abstract types
  - Don't add any recording logic (user handles it)
  - Don't touch existing `simulate()` function
  - Don't make file standalone-loadable (it's part of module)

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Single file, small implementation (~80 lines), clear spec
  - **Skills**: []
    - No special skills needed

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 2 (with Tasks 3, 4)
  - **Blocks**: Task 5
  - **Blocked By**: Task 1

  **References**:
  - **Pattern Reference**: `src/_deprecated/probabilistic_styles/style_a_action.jl:1-25` - Header PROS/CONS format AND "include in module context" comment
  - **API Reference**: `src/State/State.jl` - SimulationState struct
  - **Docstring Pattern**: `src/API/functional.jl:1-20` - simulate() docstring format
  - **Geometry Reference**: `src/Geometry/staircase.jl:18-35` - Staircase `_position` field (what reset_geometry! should reset)

  **Implementation Spec**:
  ```julia
  #=
  Style 1: Imperative Loop
  ========================
  
  Philosophy: Maximum flexibility - user controls EVERYTHING
  
  Pros:
  - Maximum flexibility - user controls the entire loop
  - Explicit control flow - easy to understand and debug
  - No hidden magic - what you write is what happens
  - Easy to add conditional logic (early stopping, adaptive recording)
  
  Cons:
  - More boilerplate code
  - User must remember to call record!() themselves
  - No structure enforced
  
  When to Use:
  Choose this for complex simulations with irregular recording patterns
  or when you need maximum control over every aspect.
  
  See also: examples/ct_model_simulation_styles.jl for side-by-side comparison
  =#
  
  # This file is meant to be included in the QuantumCircuitsMPS module context
  # where SimulationState, record!, etc. are already defined.
  # It should NOT be loaded standalone.
  
  """
      run_circuit!(state, circuit_step!, L)
  
  Execute one complete circuit (L applications of circuit_step!).
  
  A "circuit" is one full sweep across the system: L steps.
  This matches physicist intuition: "run 20 circuits" rather than "run 200 steps".
  
  # Arguments
  - `state::SimulationState`: State to evolve
  - `circuit_step!::Function`: (state) -> Nothing, applies gates for one step
  - `L::Int`: System size (number of steps per circuit)
  
  # Note on circuit_step! signature
  This function expects `circuit_step!(state)` (1-arg), not `circuit!(state, t)` (2-arg).
  If you have a 2-arg function, wrap it: `circuit_step!(s) = my_circuit!(s, 0)`
  
  # Example
  ```julia
  state = SimulationState(L=10, bc=:periodic, rng=rng)
  initialize!(state, ProductState(x0 = 1//2^L))
  track!(state, :DW1 => DomainWall(order=1))
  
  left = StaircaseLeft(L)
  circuit_step!(s) = apply_branch!(s; rng=:ctrl, outcomes=[...])
  
  record!(state; i1=1)  # Initial recording
  for circuit in 1:n_circuits
      run_circuit!(state, circuit_step!, L)
      if circuit % 2 == 0
          record!(state; i1=(current_position(left) % L) + 1)
      end
  end
  ```
  """
  function run_circuit!(state, circuit_step!::Function, L::Int)
      for step in 1:L
          circuit_step!(state)
      end
      return nothing
  end
  
  """
      run_circuit!(state, circuit_step!, L, reset_geometry!)
  
  Execute one circuit with geometry reset at the START.
  
  # Arguments
  - `reset_geometry!::Function`: () -> Nothing, resets geometry state before circuit
  
  # What reset_geometry! should do
  Staircases have internal `_position` fields that accumulate across steps.
  Your reset function should set these to known starting positions:
  
  ```julia
  left = StaircaseLeft(L)   # _position starts at L
  right = StaircaseRight(1) # _position starts at 1
  
  reset_geometry!() = begin
      left._position = L
      right._position = 1
  end
  ```
  """
  function run_circuit!(state, circuit_step!::Function, L::Int, reset_geometry!::Function)
      reset_geometry!()
      for step in 1:L
          circuit_step!(state)
      end
      return nothing
  end
  ```

  **Acceptance Criteria**:
  - [x] File exists at `src/API/simulation_styles/style_imperative.jl`
  - [x] Header has PROS/CONS section (multi-line comment block)
  - [x] Contains "This file is meant to be included in the QuantumCircuitsMPS module context" comment
  - [x] `run_circuit!` function defined with 3-arg signature `(state, circuit_step!, L)`
  - [x] `run_circuit!` overload defined with 4-arg signature `(state, circuit_step!, L, reset_geometry!)`
  - [x] Docstring documents 1-arg `circuit_step!(state)` signature requirement
  - [x] Docstring shows `reset_geometry!` example with `left._position = L`
  - [x] `julia --project=. -e 'using QuantumCircuitsMPS'` → loads without error (after all 3 styles created)

  **Commit**: NO (group with Task 5)

---

- [x] 3. Style 2: Callback (simulate_circuits with on_circuit!)

  **What to do**:
  - Create `src/API/simulation_styles/style_callback.jl`
  - Header comment block with PROS/CONS (follow pattern from `src/_deprecated/probabilistic_styles/style_a_action.jl`)
  - **NOTE**: File must be designed to be `include`d within the module context (NOT standalone)
  - Add comment at top: `# This file is meant to be included in the QuantumCircuitsMPS module context`
  - Implement `simulate_circuits()` function with parameters listed below
  - Implement convenience callbacks: `record_every(n)`, `record_at_circuits(nums)`, `record_always()`

  **Function Parameters**:
  ```julia
  function simulate_circuits(;
      L::Int,
      bc::Symbol,
      init::AbstractInitialState,
      circuit_step!::Function,           # (state) -> Nothing (1-arg!)
      circuits::Int,                      # Number of circuits (NOT steps)
      observables::Vector{Pair{Symbol,<:AbstractObservable}},  # [:DW1 => DomainWall(order=1)]
      rng::RNGRegistry,
      on_circuit!::Union{Function,Nothing} = nothing,   # (state, circuit_num, get_i1) -> Nothing
      reset_geometry!::Union{Function,Nothing} = nothing,
      record_initial::Bool = true,
      i1_fn::Union{Function,Nothing} = nothing  # () -> Int
  )
  ```

  **Circuit Step Signature**: Same as Style 1 - expects `circuit_step!(state)` (1-arg)

  **reset_geometry! Semantics**: Same as Style 1 - called at START of each circuit

  **observables Parameter Type**:
  - Type: `Vector{Pair{Symbol,<:AbstractObservable}}` (same as `src/API/functional.jl:27`)
  - Usage: `[:DW1 => DomainWall(order=1), :DW2 => DomainWall(order=2)]`
  - Iteration: `for (name, obs) in observables` (destructure Pair)

  **record_at_circuits Semantics**:
  - Input: `Vector{Int}` of circuit numbers to record at
  - Does NOT include circuit 0 (use `record_initial=true` for that)
  - Duplicates are ignored (converted to Set internally)
  - Order doesn't matter
  - Example: `record_at_circuits([10, 50, 100])` records after circuits 10, 50, 100

  **Must NOT do**:
  - Don't modify existing `simulate()` function
  - Don't add logging or timing
  - Don't create abstract callback types
  - Don't make file standalone-loadable

  **Recommended Agent Profile**:
  - **Category**: `unspecified-low`
    - Reason: More complex than imperative but straightforward logic
  - **Skills**: []
    - No special skills needed

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 2 (with Tasks 2, 4)
  - **Blocks**: Task 5
  - **Blocked By**: Task 1

  **References**:
  - **Pattern Reference**: `src/API/functional.jl:21-68` - Current simulate() structure to mirror (state creation, observable registration, loop)
  - **Pattern Reference**: `src/_deprecated/probabilistic_styles/style_a_action.jl:1-25` - Header PROS/CONS format
  - **Pattern Reference**: `examples/ct_model_styles.jl:157-186` - Style C named parameters usage
  - **API Reference**: `src/State/State.jl` - SimulationState, initialize!
  - **API Reference**: `src/Observables/Observables.jl` - track!, record!
  - **Geometry Reference**: `src/Geometry/staircase.jl:18-35` - Staircase `_position` field

  **Implementation Spec**:
  ```julia
  #=
  Style 2: Callback-based simulate_circuits()
  ==========================================
  
  Philosophy: Structure provided, flexibility via callbacks
  
  Pros:
  - Less boilerplate than imperative
  - Structure provided - harder to forget steps
  - "circuits" parameter matches physicist thinking
  - on_circuit! callback gives flexibility without full loop control
  
  Cons:
  - Callback pattern can be less intuitive for some
  - Slightly hidden control flow
  - Harder to do early stopping
  
  When to Use:
  Choose this for standard simulations with regular recording patterns
  when you want structure but still need per-circuit flexibility.
  
  See also: examples/ct_model_simulation_styles.jl for side-by-side comparison
  =#
  
  # This file is meant to be included in the QuantumCircuitsMPS module context
  
  """
      simulate_circuits(; L, bc, init, circuit_step!, circuits, observables, rng, ...)
  
  Run a simulation measured in circuits (not raw steps).
  
  One circuit = L applications of circuit_step!. This matches physicist intuition:
  "run 20 circuits" rather than "run 200 steps" for L=10.
  
  # Arguments
  - `circuit_step!::Function`: (state) -> Nothing, applies gates for one step
  - `circuits::Int`: Number of circuits to run (total steps = circuits * L)
  - `observables::Vector{Pair{Symbol,<:AbstractObservable}}`: e.g., [:DW1 => DomainWall(order=1)]
  - `on_circuit!::Function`: Optional (state, circuit_num, get_i1) -> Nothing
  - `reset_geometry!::Function`: Optional () -> Nothing, called at START of each circuit
  - `record_initial::Bool`: Whether to record at t=0 (default: true)
  - `i1_fn::Function`: Optional () -> Int for DomainWall i1
  
  # Example
  ```julia
  left = StaircaseLeft(L)
  right = StaircaseRight(1)
  
  circuit_step!(state) = apply_branch!(state; ...)
  
  results = simulate_circuits(
      L = L,
      bc = :periodic,
      init = ProductState(x0 = 1//2^L),
      circuit_step! = circuit_step!,
      circuits = 2 * L,
      observables = [:DW1 => DomainWall(order=1)],
      rng = rng,
      on_circuit! = record_every(2),
      reset_geometry! = () -> (left._position = L; right._position = 1),
      i1_fn = () -> (current_position(left) % L) + 1
  )
  ```
  """
  function simulate_circuits(;
      L::Int,
      bc::Symbol,
      init::AbstractInitialState,
      circuit_step!::Function,
      circuits::Int,
      observables::Vector,
      rng::RNGRegistry,
      on_circuit!::Union{Function,Nothing} = nothing,
      reset_geometry!::Union{Function,Nothing} = nothing,
      record_initial::Bool = true,
      i1_fn::Union{Function,Nothing} = nothing
  )
      # 1. Create and initialize state
      state = SimulationState(L=L, bc=bc, rng=rng)
      initialize!(state, init)
      
      # 2. Register observables
      for (name, obs) in observables
          track!(state, name => obs)
      end
      
      # 3. Helper to get i1
      get_i1 = i1_fn !== nothing ? i1_fn : () -> 1
      
      # 4. Initial recording (t=0)
      if record_initial
          record!(state; i1=get_i1())
      end
      
      # 5. Main loop - by CIRCUITS
      for circuit_num in 1:circuits
          # Reset geometry at start of circuit if provided
          reset_geometry! !== nothing && reset_geometry!()
          
          # Run one circuit = L steps
          for step in 1:L
              circuit_step!(state)
          end
          
          # Call user's on_circuit! callback
          on_circuit! !== nothing && on_circuit!(state, circuit_num, get_i1)
      end
      
      return state.observables
  end
  
  # Convenience callbacks
  
  """
      record_every(n::Int)
  
  Create callback that records every n circuits.
  Example: `record_every(2)` records after circuits 2, 4, 6, ...
  """
  record_every(n::Int) = (state, circuit_num, get_i1) -> begin
      if circuit_num % n == 0
          record!(state; i1=get_i1())
      end
  end
  
  """
      record_at_circuits(circuit_nums::Vector{Int})
  
  Create callback that records at specific circuit numbers.
  Does NOT include circuit 0 (use record_initial=true).
  
  Example: `record_at_circuits([10, 50, 100])`
  """
  record_at_circuits(circuit_nums::Vector{Int}) = begin
      circuit_set = Set(circuit_nums)
      (state, circuit_num, get_i1) -> begin
          if circuit_num in circuit_set
              record!(state; i1=get_i1())
          end
      end
  end
  
  """
      record_always()
  
  Create callback that records after every circuit.
  """
  record_always() = (state, circuit_num, get_i1) -> record!(state; i1=get_i1())
  ```

  **Acceptance Criteria**:
  - [x] File exists at `src/API/simulation_styles/style_callback.jl`
  - [x] Header has PROS/CONS section (multi-line comment block)
  - [x] Contains "This file is meant to be included in the QuantumCircuitsMPS module context" comment
  - [x] `simulate_circuits` function with all specified parameters
  - [x] `on_circuit!` callback receives `(state, circuit_num, get_i1)` - 3 args
  - [x] `record_every(n)` returns callback that records when `circuit_num % n == 0`
  - [x] `record_at_circuits(nums)` converts to Set internally, records when `circuit_num in set`
  - [x] `record_always()` returns callback that always records
  - [x] Docstring shows `reset_geometry!` example with `left._position = L`
  - [x] `julia --project=. -e 'using QuantumCircuitsMPS'` → loads without error

  **Commit**: NO (group with Task 5)

---

- [x] 4. Style 3: Iterator (CircuitSimulation struct)

  **What to do**:
  - Create `src/API/simulation_styles/style_iterator.jl`
  - Header comment block with PROS/CONS (follow pattern from `src/_deprecated/probabilistic_styles/style_a_action.jl`)
  - **NOTE**: File must be designed to be `include`d within the module context (NOT standalone)
  - Add comment at top: `# This file is meant to be included in the QuantumCircuitsMPS module context`
  - Implement `CircuitSimulation` mutable struct
  - Implement Julia iteration protocol: `Base.iterate(sim)` and `Base.iterate(sim, prev_circuit)`
  - Implement convenience methods

  **CircuitSimulation Struct**:
  ```julia
  mutable struct CircuitSimulation
      # Config (set at construction, don't change)
      L::Int
      bc::Symbol
      circuit_step!::Function              # (state) -> Nothing
      reset_geometry!::Union{Function,Nothing}
      
      # State (mutable during iteration)
      state::SimulationState               # NOT Union - always present after construction
      circuit_count::Int
  end
  ```

  **Circuit Step Signature**: Same as Style 1/2 - expects `circuit_step!(state)` (1-arg)

  **reset_geometry! Semantics**: Same as Style 1/2 - called at START of each circuit

  **Iterator Behavior (CRITICAL)**:
  - **Infinite iterator**: `Base.IteratorSize(::Type{CircuitSimulation}) = Base.IsInfinite()`
  - **User limits with**: `Iterators.take(sim, n_circuits)`
  - **Yields SAME mutable object**: Each iteration returns the SAME `state` object (NOT a copy)
  - **User must understand**: `for state in sim` yields the same state mutated each time
  - **Document this clearly** in docstring to avoid confusion

  **circuits_run vs iteration state**:
  - `sim.circuit_count` is updated DURING iteration
  - `circuits_run(sim)` returns `sim.circuit_count` (same value)
  - After `for (n, state) in enumerate(take(sim, 10))`, `circuits_run(sim) == 10`

  **Must NOT do**:
  - Don't implement `take`/`drop` methods (use Julia's Iterators module)
  - Don't add termination condition to iterator (it's infinite)
  - Don't create inheritance hierarchy
  - Don't make file standalone-loadable

  **Recommended Agent Profile**:
  - **Category**: `unspecified-low`
    - Reason: Most complex of the 3 styles, but well-defined spec
  - **Skills**: []
    - No special skills needed

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 2 (with Tasks 2, 3)
  - **Blocks**: Task 5
  - **Blocked By**: Task 1

  **References**:
  - **Julia Docs**: Iteration protocol - `iterate(iter)` returns `(item, state)` or `nothing`
  - **Pattern Reference**: `src/API/functional.jl:21-68` - State initialization pattern
  - **Pattern Reference**: `src/_deprecated/probabilistic_styles/style_a_action.jl:1-25` - Header format
  - **API Reference**: `src/State/State.jl` - SimulationState struct
  - **Geometry Reference**: `src/Geometry/staircase.jl:18-35` - Staircase `_position` field

  **Implementation Spec**:
  ```julia
  #=
  Style 3: Iterator Pattern
  =========================
  
  Philosophy: Lazy evaluation, user controls loop with iterator utilities
  
  Pros:
  - Clean separation of setup vs. execution
  - Lazy evaluation - compute only what you need
  - User controls loop but with less boilerplate
  - Composable with Julia's Iterators (take, drop, enumerate)
  - Natural for "run until condition" patterns
  
  Cons:
  - Iterator semantics might be unfamiliar
  - Yields same mutable object (not copies!)
  - Debugging can be trickier
  
  When to Use:
  Choose this for exploratory simulation where you want to inspect
  state between circuits, or for "run until convergence" patterns.
  
  See also: examples/ct_model_simulation_styles.jl for side-by-side comparison
  =#
  
  # This file is meant to be included in the QuantumCircuitsMPS module context
  
  """
      CircuitSimulation
  
  A lazy simulation iterator. Each iteration runs one circuit (L steps).
  
  **WARNING**: Each iteration yields the SAME mutable state object.
  If you need snapshots, copy the state yourself.
  
  # Usage
  ```julia
  sim = CircuitSimulation(L=10, bc=:periodic, ...)
  
  # Run 20 circuits, record every 2
  record!(sim.state; i1=1)  # Initial
  for (n, state) in enumerate(Iterators.take(sim, 20))
      if n % 2 == 0
          record!(state; i1=get_i1())
      end
  end
  
  results = get_observables(sim)
  ```
  """
  mutable struct CircuitSimulation
      L::Int
      bc::Symbol
      circuit_step!::Function
      reset_geometry!::Union{Function,Nothing}
      state::SimulationState
      circuit_count::Int
  end
  
  """
      CircuitSimulation(; L, bc, init, circuit_step!, observables, rng, reset_geometry!=nothing)
  
  Create a lazy circuit simulation iterator.
  
  # Arguments
  - `circuit_step!::Function`: (state) -> Nothing
  - `observables::Vector{Pair{Symbol,<:AbstractObservable}}`
  - `reset_geometry!::Function`: Optional () -> Nothing, called at START of each circuit
  
  # Example
  ```julia
  left = StaircaseLeft(L)
  
  sim = CircuitSimulation(
      L = 10,
      bc = :periodic,
      init = ProductState(x0 = 1//2^10),
      circuit_step! = state -> apply_branch!(state; ...),
      observables = [:DW1 => DomainWall(order=1)],
      rng = rng,
      reset_geometry! = () -> (left._position = L)
  )
  ```
  """
  function CircuitSimulation(;
      L::Int,
      bc::Symbol,
      init::AbstractInitialState,
      circuit_step!::Function,
      observables::Vector,
      rng::RNGRegistry,
      reset_geometry!::Union{Function,Nothing} = nothing
  )
      state = SimulationState(L=L, bc=bc, rng=rng)
      initialize!(state, init)
      for (name, obs) in observables
          track!(state, name => obs)
      end
      return CircuitSimulation(L, bc, circuit_step!, reset_geometry!, state, 0)
  end
  
  # Julia iteration protocol
  
  function Base.iterate(sim::CircuitSimulation)
      sim.reset_geometry! !== nothing && sim.reset_geometry!()
      for step in 1:sim.L
          sim.circuit_step!(sim.state)
      end
      sim.circuit_count = 1
      return (sim.state, sim.circuit_count)
  end
  
  function Base.iterate(sim::CircuitSimulation, prev_circuit::Int)
      sim.reset_geometry! !== nothing && sim.reset_geometry!()
      for step in 1:sim.L
          sim.circuit_step!(sim.state)
      end
      sim.circuit_count = prev_circuit + 1
      return (sim.state, sim.circuit_count)
  end
  
  Base.IteratorSize(::Type{CircuitSimulation}) = Base.IsInfinite()
  Base.eltype(::Type{CircuitSimulation}) = SimulationState
  
  # Convenience methods
  
  """Get current simulation state."""
  get_state(sim::CircuitSimulation) = sim.state
  
  """Get recorded observables dictionary."""
  get_observables(sim::CircuitSimulation) = sim.state.observables
  
  """Get number of circuits run so far."""
  circuits_run(sim::CircuitSimulation) = sim.circuit_count
  
  """
      run!(sim::CircuitSimulation, n_circuits::Int)
  
  Run n circuits without yielding. Useful for burn-in.
  """
  function run!(sim::CircuitSimulation, n_circuits::Int)
      for _ in 1:n_circuits
          sim.reset_geometry! !== nothing && sim.reset_geometry!()
          for step in 1:sim.L
              sim.circuit_step!(sim.state)
          end
          sim.circuit_count += 1
      end
      return sim
  end
  ```

  **Acceptance Criteria**:
  - [x] File exists at `src/API/simulation_styles/style_iterator.jl`
  - [x] Header has PROS/CONS section (multi-line comment block)
  - [x] Contains "This file is meant to be included in the QuantumCircuitsMPS module context" comment
  - [x] `CircuitSimulation` struct defined with fields: `L, bc, circuit_step!, reset_geometry!, state, circuit_count`
  - [x] Constructor accepts same-named parameters and initializes state
  - [x] `Base.iterate(sim)` implemented (first iteration, returns `(state, 1)`)
  - [x] `Base.iterate(sim, prev)` implemented (subsequent, returns `(state, prev+1)`)
  - [x] `Base.IteratorSize(::Type{CircuitSimulation})` returns `Base.IsInfinite()`
  - [x] Docstring warns "yields SAME mutable state object"
  - [x] Convenience methods: `get_state`, `get_observables`, `circuits_run`, `run!`
  - [x] `julia --project=. -e 'using QuantumCircuitsMPS'` → loads without error

  **Commit**: NO (group with Task 5)

---

- [x] 5. Create comparison example (ct_model_simulation_styles.jl)

  **What to do**:
  - Create `examples/ct_model_simulation_styles.jl`
  - Follow structure of `examples/ct_model_styles.jl` (probabilistic comparison)
  - Same CT model physics (L=10, p_ctrl=0.5, seed_C=42, seed_m=123)
  - **Use `n_circuits = 2*L` to get equivalent physics to `steps = 2*L^2`**
  - Demonstrate "record every 2 circuits" pattern in each style
  - Run all 3 styles with SAME parameters
  - Physics verification: assert all 3 produce identical results
  - Print comparison table at end

  **Critical Physics Mapping**:
  - Old: `steps = 2 * L^2 = 200` individual step calls
  - New: `n_circuits = 2 * L = 20` circuits, each circuit = L=10 steps → 200 total steps
  - **SAME total gate applications, different recording granularity**

  **circuit_step! Adaptation**:
  The existing CT model uses `circuit!(state, t)` (2-arg). New APIs expect `circuit_step!(state)` (1-arg).
  Adaptation in each style function:
  ```julia
  # Define 1-arg wrapper
  circuit_step!(state) = apply_branch!(state; rng=:ctrl, outcomes=[
      (probability=p_ctrl, gate=Reset(), geometry=left),
      (probability=1-p_ctrl, gate=HaarRandom(), geometry=right)
  ])
  ```

  **reset_geometry! Usage**:
  For this example, we do NOT use reset_geometry! because:
  - Staircases should continue from where they left off (accumulating position)
  - This matches the original `steps = 2*L^2` behavior
  - Document this choice in comments

  **Must NOT do**:
  - Don't change CT model physics
  - Don't add extra features beyond comparison
  - Don't create elaborate test framework
  - Don't use reset_geometry! (would change physics)

  **Recommended Agent Profile**:
  - **Category**: `unspecified-low`
    - Reason: Moderate complexity, follows existing pattern
  - **Skills**: []
    - No special skills needed

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Wave 3 (alone)
  - **Blocks**: Task 6
  - **Blocked By**: Tasks 2, 3, 4

  **References**:
  - **Pattern Reference**: `examples/ct_model_styles.jl:1-325` - EXACT structure to follow (header, style sections, verification, comparison table)
  - **Physics Reference**: `examples/ct_model.jl:8-42` - CT model parameters and physics
  - **Style Reference**: `examples/ct_model_styles.jl:47-79` - Style A implementation pattern
  - **Style Reference**: `examples/ct_model_styles.jl:157-186` - Style C named parameters

  **Implementation Spec**:
  ```julia
  # CT Model - Simulation API Styles Comparison
  # ============================================
  # This file shows the EXACT SAME CT Model physics implemented in 3 simulation styles.
  # All 3 styles produce IDENTICAL results when given the same seed.
  # Run this file and choose your preferred syntax!
  #
  # The 3 styles are:
  #   1: Imperative (run_circuit!) - Maximum control, user manages loop
  #   2: Callback (simulate_circuits) - Structure provided, on_circuit! callback
  #   3: Iterator (CircuitSimulation) - Lazy evaluation, composable with Iterators
  #
  # Key concept: 1 circuit = L steps (one full sweep across system)
  # So n_circuits = 2*L gives same total steps as steps = 2*L^2
  
  using Pkg; Pkg.activate(dirname(@__DIR__))
  using QuantumCircuitsMPS
  
  # ============= COMMON PARAMETERS =============
  const L = 10
  const p_ctrl = 0.5
  const seed_C = 42
  const seed_m = 123
  const N_CIRCUITS = 2 * L  # 20 circuits × 10 steps = 200 total steps
  const RECORD_EVERY = 2    # Record every 2 circuits
  
  # ============= STYLE 1: IMPERATIVE =============
  function run_style1_imperative()
      left = StaircaseLeft(L)
      right = StaircaseRight(1)
      rng = RNGRegistry(Val(:ct_compat), circuit=seed_C, measurement=seed_m)
      
      state = SimulationState(L=L, bc=:periodic, rng=rng)
      initialize!(state, ProductState(x0 = 1//2^L))
      track!(state, :DW1 => DomainWall(order=1))
      
      # 1-arg circuit step (new API requirement)
      circuit_step!(s) = apply_branch!(s; rng=:ctrl, outcomes=[
          (probability=p_ctrl, gate=Reset(), geometry=left),
          (probability=1-p_ctrl, gate=HaarRandom(), geometry=right)
      ])
      
      get_i1() = (current_position(left) % L) + 1
      
      # Initial recording
      record!(state; i1=get_i1())
      
      # USER controls the loop
      for circuit in 1:N_CIRCUITS
          run_circuit!(state, circuit_step!, L)
          # Record every 2 circuits
          if circuit % RECORD_EVERY == 0
              record!(state; i1=get_i1())
          end
      end
      
      return state.observables[:DW1]
  end
  
  # ============= STYLE 2: CALLBACK =============
  function run_style2_callback()
      left = StaircaseLeft(L)
      right = StaircaseRight(1)
      rng = RNGRegistry(Val(:ct_compat), circuit=seed_C, measurement=seed_m)
      
      circuit_step!(s) = apply_branch!(s; rng=:ctrl, outcomes=[
          (probability=p_ctrl, gate=Reset(), geometry=left),
          (probability=1-p_ctrl, gate=HaarRandom(), geometry=right)
      ])
      
      results = simulate_circuits(
          L = L,
          bc = :periodic,
          init = ProductState(x0 = 1//2^L),
          circuit_step! = circuit_step!,
          circuits = N_CIRCUITS,
          observables = [:DW1 => DomainWall(order=1)],
          rng = rng,
          on_circuit! = record_every(RECORD_EVERY),
          i1_fn = () -> (current_position(left) % L) + 1
          # NOTE: No reset_geometry! - staircases continue accumulating
      )
      
      return results[:DW1]
  end
  
  # ============= STYLE 3: ITERATOR =============
  function run_style3_iterator()
      left = StaircaseLeft(L)
      right = StaircaseRight(1)
      rng = RNGRegistry(Val(:ct_compat), circuit=seed_C, measurement=seed_m)
      
      circuit_step!(s) = apply_branch!(s; rng=:ctrl, outcomes=[
          (probability=p_ctrl, gate=Reset(), geometry=left),
          (probability=1-p_ctrl, gate=HaarRandom(), geometry=right)
      ])
      
      sim = CircuitSimulation(
          L = L,
          bc = :periodic,
          init = ProductState(x0 = 1//2^L),
          circuit_step! = circuit_step!,
          observables = [:DW1 => DomainWall(order=1)],
          rng = rng
          # NOTE: No reset_geometry! - staircases continue accumulating
      )
      
      get_i1() = (current_position(left) % L) + 1
      
      # Initial recording
      record!(sim.state; i1=get_i1())
      
      # Iterate with take() to limit circuits
      for (n, state) in enumerate(Iterators.take(sim, N_CIRCUITS))
          if n % RECORD_EVERY == 0
              record!(state; i1=get_i1())
          end
      end
      
      return get_observables(sim)[:DW1]
  end
  
  # ============= RUN AND COMPARE =============
  # ... (verification code and comparison table)
  ```

  **Acceptance Criteria**:
  - [x] File exists at `examples/ct_model_simulation_styles.jl`
  - [x] Uses `N_CIRCUITS = 2 * L` (not `steps = 2*L^2`)
  - [x] All 3 styles implemented: `run_style1_imperative`, `run_style2_callback`, `run_style3_iterator`
  - [x] Each style uses 1-arg `circuit_step!(state)` (not 2-arg)
  - [x] Each style demonstrates "record every 2 circuits" pattern
  - [x] Style 2 uses `record_every(RECORD_EVERY)` convenience callback
  - [x] Style 3 uses `Iterators.take(sim, N_CIRCUITS)` pattern
  - [x] Physics verification: `dw1 == dw2 == dw3` check
  - [x] `julia --project=. examples/ct_model_simulation_styles.jl` → "✓ PASS"

  **Commit**: YES
  - Message: `feat(api): add 3 simulation API styles with circuit-level control`
  - Files: `src/QuantumCircuitsMPS.jl`, `src/API/simulation_styles/*.jl`, `examples/ct_model_simulation_styles.jl`
  - Pre-commit: `julia --project=. examples/ct_model_simulation_styles.jl`

---

- [x] 6. Physics verification

  **What to do**:
  - Run comparison example and verify output
  - Confirm all 3 styles produce identical DW1 values
  - Verify existing `examples/ct_model.jl` still works (backwards compatibility)

  **Must NOT do**:
  - Don't modify any files
  - Don't add extra tests

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Just running verification commands
  - **Skills**: []
    - No special skills needed

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Wave 4 (final)
  - **Blocks**: None
  - **Blocked By**: Task 5

  **References**:
  - `examples/ct_model_simulation_styles.jl` - File to run
  - `examples/ct_model.jl` - Backwards compatibility check

  **Acceptance Criteria**:
  - [x] `julia --project=. examples/ct_model_simulation_styles.jl` → prints "✓ PASS"
  - [x] `julia --project=. examples/ct_model.jl` → still works (prints "Done!")
  - [x] All 3 styles produce EXACT same DW1 array (not just similar)

  **Commit**: NO (already committed in Task 5)

---

## Commit Strategy

| After Task | Message | Files | Verification |
|------------|---------|-------|--------------|
| 5 | `feat(api): add 3 simulation API styles with circuit-level control` | `src/QuantumCircuitsMPS.jl`, `src/API/simulation_styles/*.jl`, `examples/ct_model_simulation_styles.jl` | `julia --project=. examples/ct_model_simulation_styles.jl` |

---

## Success Criteria

### Verification Commands
```bash
# Load module (verifies includes work)
julia --project=. -e 'using QuantumCircuitsMPS; println("Module loaded!")'

# Comparison example runs successfully
julia --project=. examples/ct_model_simulation_styles.jl
# Expected: "✓ PASS"

# Backwards compatibility
julia --project=. examples/ct_model.jl
# Expected: "Done! DW1[1:5]: ..."
```

### Final Checklist
- [x] All 3 style files created with PROS/CONS headers
- [x] All 3 style files have "include in module context" comment
- [x] `src/QuantumCircuitsMPS.jl` includes all 3 style files
- [x] `src/QuantumCircuitsMPS.jl` exports: `run_circuit!`, `simulate_circuits`, `CircuitSimulation`, etc.
- [x] Each style has comprehensive docstrings documenting 1-arg `circuit_step!(state)` requirement
- [x] Each style documents `reset_geometry!` semantics with concrete example
- [x] Comparison example demonstrates "record every 2 circuits"
- [x] Physics verification passes (exact match)
- [x] Backwards compatibility maintained
