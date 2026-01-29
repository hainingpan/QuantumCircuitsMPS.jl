# Multiple Probabilistic API Styles Comparison

## TL;DR

> **Quick Summary**: Implement 4 alternative API styles for probabilistic branching to replace the current `apply_with_prob!`, allowing the user to compare and choose their preferred syntax before final selection.
> 
> **Deliverables**:
> - 4 complete API style implementations in `src/API/probabilistic_styles/`
> - Comparison example `examples/ct_model_styles.jl` showing all styles side-by-side
> - Pros/cons documentation for each style
> - Removal of old `apply_with_prob!` after user selection
> 
> **Estimated Effort**: Medium (focused API design + implementation)
> **Parallel Execution**: YES - 2 waves
> **Critical Path**: Task 1 (Action type) → Task 2 (Style implementations) → Task 3 (Comparison example) → Task 4 (User selection & cleanup)

---

## Context

### User's THREE Complaints About Current API

From `prompt_history.md` line 253-259:
1. **"it only assume two outcomes, what if i have three outcomes?"** - Current API is binary-only
2. **"it does not conceptually 'combine' gate with geometry"** - Gate and geometry are separate arguments
3. **"the readability is very bad. everything is position based"** - Requires memorizing argument order

### User's Unfulfilled Request (THREE TIMES)

The user explicitly requested **"multiple styles"** to compare as final products:
- Line 91: "Make it multiple style for now, and i want to see how they look like as the final product, after that i can decide."
- Line 122: "your example code should also provide all the possible combinations"
- Line 173: "Long time ago, i mentioned 'Make it multiple style for now'..."

**THIS WAS NEVER DELIVERED.** This plan finally fulfills that request.

### Interview Summary

**Key Decisions**:
- Implement ALL 4 styles (unless one proves technically absurd)
- Use CT Model for comparison (exact same physics in all styles)
- Replace `apply_with_prob!` completely (no backward compatibility)
- Philosophy: "Physicists code as they speak"

### Research Findings

**Cirq (Google)**: Fluent gate decoration `gate.with_probability(0.3)`
**Turing.jl/Gen.jl**: Categorical distribution for N-way branching
**Best Practices**: Named parameters, tuple (prob, operation), unified "action" concept

---

## Work Objectives

### Core Objective
Create 4 complete, working API styles for probabilistic branching so the user can compare them side-by-side and make an informed final decision.

### Concrete Deliverables
1. `src/API/probabilistic_styles/action.jl` - Action type (gate + geometry unified)
2. `src/API/probabilistic_styles/style_a_action.jl` - Action-based style
3. `src/API/probabilistic_styles/style_b_categorical.jl` - Categorical/tuple style
4. `src/API/probabilistic_styles/style_c_named.jl` - Fully named parameters style
5. `src/API/probabilistic_styles/style_d_macro.jl` - DSL macro style
6. `examples/ct_model_styles.jl` - CT Model in all 4 styles side-by-side
7. Style comparison documentation (pros/cons table)

### Definition of Done
- [x] All 4 styles produce IDENTICAL physics output when given identical seeds
- [x] All 4 styles support N-way branching (3+ outcomes)
- [x] Comparison example compiles and runs for all styles
- [x] User can visually compare code readability across styles

### Auto-Resolved Gaps
- **Identity gate missing**: There's no `Identity()` gate in codebase. The examples showing 3-way branching will use existing gates (`PauliX`, `PauliY`, `PauliZ`). If needed, add `Identity = I` alias or use `NoOp` pattern.

### Must Have
- Generalization to 3+ outcomes (not just binary)
- Gate + geometry conceptually combined ("Action" concept)
- Named parameters (no positional argument memorization)
- Contract 4.4 compliance (draw RNG BEFORE checking probability)

### Must NOT Have (Guardrails)
- ❌ Breaking existing CT model physics
- ❌ Changes to core `apply!` engine
- ❌ New dependencies
- ❌ Pre-selecting a style for the user

---

## Verification Strategy

### Physics Verification
All styles must pass this test:
```julia
# Same seed, same physics → identical output
results_a = run_ct_with_style_a(seed=42)
results_b = run_ct_with_style_b(seed=42)
results_c = run_ct_with_style_c(seed=42)
results_d = run_ct_with_style_d(seed=42)

@assert results_a == results_b == results_c == results_d
```

### Manual QA Procedures
1. Run `examples/ct_model_styles.jl`
2. Verify terminal output shows all 4 styles producing same DW values
3. Visual inspection of code readability across styles

---

## Execution Strategy

### Parallel Execution Waves

```
Wave 1 (Start Immediately):
├── Task 1: Create Action type
└── Task 2: Implement all 4 styles (can work in parallel)

Wave 2 (After Wave 1):
├── Task 3: Create comparison example
└── Task 4: Document pros/cons

Wave 3 (After User Decision):
└── Task 5: Cleanup - remove old API, promote chosen style

Critical Path: Task 1 → Task 2 → Task 3 → (User Decision) → Task 5
```

### Dependency Matrix

| Task | Depends On | Blocks | Can Parallelize With |
|------|------------|--------|---------------------|
| 1 | None | 2 | - |
| 2 | 1 | 3, 4 | - |
| 3 | 2 | User Decision | 4 |
| 4 | 2 | - | 3 |
| 5 | User Decision | - | - |

---

## TODOs

### Task 1: Create Action Type (Foundation)

- [x] 1. Create unified Action type combining Gate + Geometry

  **What to do**:
  - Create `src/API/probabilistic_styles/action.jl`
  - Define `Action` struct:
    ```julia
    """
        Action(gate, geometry)
    
    Combines a gate with its target geometry into a single "action" concept.
    This is the atomic unit for probabilistic branching.
    
    Example:
        reset_left = Action(Reset(), left_staircase)
        haar_right = Action(HaarRandom(), right_staircase)
    """
    struct Action
        gate::AbstractGate
        geometry::AbstractGeometry
    end
    
    # Convenience method to execute an action
    function apply!(state::SimulationState, action::Action)
        apply!(state, action.gate, action.geometry)
    end
    ```

  **Must NOT do**:
  - Modify existing AbstractGate or AbstractGeometry types
  - Add complex validation logic (keep it simple)

  **Recommended Agent Profile**:
  - **Category**: `quick`
  - **Skills**: None needed - straightforward struct definition

  **Parallelization**:
  - **Can Run In Parallel**: NO (foundation for all other tasks)
  - **Blocks**: Task 2 (all style implementations)

  **References**:
  - `src/Gates/Gates.jl:7` - AbstractGate type definition
  - `src/Geometry/Geometry.jl:12` - AbstractGeometry type definition
  - `src/Core/apply.jl:17-20` - How apply! dispatches on gate+geometry

  **Acceptance Criteria**:
  - [ ] `Action(Reset(), StaircaseLeft(1))` creates valid Action
  - [ ] `apply!(state, action)` calls underlying `apply!(state, gate, geo)`
  - [ ] Action is exported from module
  - [ ] Staircase advancement works correctly when action contains staircase geometry

  **Commit**: YES
  - Message: `feat(api): add Action type unifying gate and geometry`
  - Files: `src/API/probabilistic_styles/action.jl`

---

### Task 2: Implement All 4 Styles

- [x] 2a. Style A: Action-Based (`apply_stochastic!`)

  **What to do**:
  - Create `src/API/probabilistic_styles/style_a_action.jl`
  - Implement:
    ```julia
    """
        apply_stochastic!(state, pairs...; rng=:ctrl)
    
    Probabilistically execute one of N actions based on their probabilities.
    
    CRITICAL: Always draws ONE random number BEFORE checking probabilities.
    
    Arguments:
    - state: SimulationState
    - pairs...: Pairs of probability => Action (e.g., 0.3 => action1, 0.7 => action2)
    - rng: Symbol for RNG stream (default :ctrl)
    
    Example (binary):
        apply_stochastic!(state, 
            p_ctrl => Action(Reset(), left),
            (1-p_ctrl) => Action(HaarRandom(), right)
        )
    
    Example (3-way):
        apply_stochastic!(state,
            0.25 => Action(PauliX(), site),
            0.25 => Action(PauliY(), site),
            0.50 => Action(Identity(), site)
        )
    """
    function apply_stochastic!(state::SimulationState, pairs::Pair{<:Real, Action}...; rng::Symbol = :ctrl)
        # Validate probabilities sum to ~1
        probs = [p.first for p in pairs]
        @assert abs(sum(probs) - 1.0) < 1e-10 "Probabilities must sum to 1, got $(sum(probs))"
        
        # CRITICAL: Draw random number BEFORE checking
        actual_rng = get_rng(state.rng_registry, rng)
        r = rand(actual_rng)
        
        # Find which action to execute
        cumulative = 0.0
        for (prob, action) in pairs
            cumulative += prob
            if r < cumulative
                apply!(state, action)
                return nothing
            end
        end
        
        # Edge case: r exactly equals 1.0 (extremely rare)
        apply!(state, last(pairs).second)
        return nothing
    end
    ```

  **Must NOT do**:
  - Skip RNG draw (Contract 4.4 violation)
  - Assume only 2 outcomes

  **Recommended Agent Profile**:
  - **Category**: `quick`
  - **Skills**: None needed

  **Parallelization**:
  - **Can Run In Parallel**: YES - with Tasks 2b, 2c, 2d
  - **Blocks**: Task 3

  **References**:
  - `src/API/probabilistic.jl:26-50` - Current implementation pattern
  - `src/Core/rng.jl` - RNG registry and get_rng pattern

  **Acceptance Criteria**:
  - [ ] 2-way branching works with identical physics to old API
  - [ ] 3-way branching works: `apply_stochastic!(state, 0.25 => a1, 0.25 => a2, 0.50 => a3)`
  - [ ] RNG is consumed exactly ONCE per call

  **Commit**: NO (groups with Task 2d)

---

- [x] 2b. Style B: Categorical/Tuple-Based (`apply_categorical!`)

  **What to do**:
  - Create `src/API/probabilistic_styles/style_b_categorical.jl`
  - Implement:
    ```julia
    """
        apply_categorical!(state, outcomes; rng=:ctrl)
    
    Execute one action from a categorical distribution over (prob, gate, geometry) tuples.
    
    Arguments:
    - state: SimulationState
    - outcomes: Vector of tuples (probability, gate, geometry)
    - rng: Symbol for RNG stream
    
    Example:
        apply_categorical!(state, [
            (p_ctrl, Reset(), left),
            (1-p_ctrl, HaarRandom(), right)
        ])
    
    Example (3-way):
        apply_categorical!(state, [
            (0.25, PauliX(), site),
            (0.25, PauliY(), site),
            (0.50, Identity(), site)
        ])
    """
    function apply_categorical!(
        state::SimulationState, 
        outcomes::Vector{<:Tuple{Real, AbstractGate, AbstractGeometry}};
        rng::Symbol = :ctrl
    )
        probs = [o[1] for o in outcomes]
        @assert abs(sum(probs) - 1.0) < 1e-10 "Probabilities must sum to 1"
        
        # CRITICAL: Draw BEFORE checking
        actual_rng = get_rng(state.rng_registry, rng)
        r = rand(actual_rng)
        
        cumulative = 0.0
        for (prob, gate, geo) in outcomes
            cumulative += prob
            if r < cumulative
                apply!(state, gate, geo)
                return nothing
            end
        end
        
        # Edge case
        _, gate, geo = last(outcomes)
        apply!(state, gate, geo)
        return nothing
    end
    ```

  **Must NOT do**:
  - Create named tuple overhead (keep tuples simple)

  **Recommended Agent Profile**:
  - **Category**: `quick`
  - **Skills**: None needed

  **Parallelization**:
  - **Can Run In Parallel**: YES - with Tasks 2a, 2c, 2d

  **References**:
  - Same as Task 2a

  **Acceptance Criteria**:
  - [ ] Tuple syntax works: `(0.5, Reset(), left)`
  - [ ] N-way branching supported
  - [ ] RNG consumed exactly ONCE

  **Commit**: NO (groups with Task 2d)

---

- [x] 2c. Style C: Fully Named Parameters (`apply_branch!`)

  **What to do**:
  - Create `src/API/probabilistic_styles/style_c_named.jl`
  - Implement:
    ```julia
    """
        apply_branch!(state; rng=:ctrl, outcomes)
    
    Execute one action from outcomes with fully named parameters.
    
    Each outcome is a NamedTuple with fields:
    - probability: Float64 (required)
    - gate: AbstractGate (required)
    - geometry: AbstractGeometry (required)
    
    Example:
        apply_branch!(state;
            rng = :ctrl,
            outcomes = [
                (probability=p_ctrl, gate=Reset(), geometry=left),
                (probability=1-p_ctrl, gate=HaarRandom(), geometry=right)
            ]
        )
    
    Example (3-way):
        apply_branch!(state;
            outcomes = [
                (probability=0.25, gate=PauliX(), geometry=site),
                (probability=0.25, gate=PauliY(), geometry=site),
                (probability=0.50, gate=Identity(), geometry=site)
            ]
        )
    """
    function apply_branch!(
        state::SimulationState;
        rng::Symbol = :ctrl,
        outcomes::Vector{<:NamedTuple{(:probability, :gate, :geometry)}}
    )
        probs = [o.probability for o in outcomes]
        @assert abs(sum(probs) - 1.0) < 1e-10 "Probabilities must sum to 1"
        
        # CRITICAL: Draw BEFORE checking
        actual_rng = get_rng(state.rng_registry, rng)
        r = rand(actual_rng)
        
        cumulative = 0.0
        for outcome in outcomes
            cumulative += outcome.probability
            if r < cumulative
                apply!(state, outcome.gate, outcome.geometry)
                return nothing
            end
        end
        
        last_outcome = last(outcomes)
        apply!(state, last_outcome.gate, last_outcome.geometry)
        return nothing
    end
    ```

  **Must NOT do**:
  - Make parameters positional
  - Skip any named field

  **Recommended Agent Profile**:
  - **Category**: `quick`
  - **Skills**: None needed

  **Parallelization**:
  - **Can Run In Parallel**: YES - with Tasks 2a, 2b, 2d

  **References**:
  - Same as Task 2a

  **Acceptance Criteria**:
  - [ ] Named tuple syntax works: `(probability=0.5, gate=Reset(), geometry=left)`
  - [ ] ALL parameters are named (no positional args)
  - [ ] RNG consumed exactly ONCE

  **Commit**: NO (groups with Task 2d)

---

- [x] 2d. Style D: Macro/DSL (`@stochastic`)

  **What to do**:
  - Create `src/API/probabilistic_styles/style_d_macro.jl`
  - Implement:
    ```julia
    """
        @stochastic state rng begin
            prob1 => apply!(gate1, geo1)
            prob2 => apply!(gate2, geo2)
            ...
        end
    
    DSL-style probabilistic branching that reads like natural language.
    
    Example:
        @stochastic state :ctrl begin
            p_ctrl => apply!(Reset(), left)
            (1-p_ctrl) => apply!(HaarRandom(), right)
        end
    
    Example (3-way):
        @stochastic state :ctrl begin
            0.25 => apply!(PauliX(), site)
            0.25 => apply!(PauliY(), site)
            0.50 => apply!(Identity(), site)
        end
    
    NOTE: The macro captures 'apply!' calls and transforms them into 
    conditional execution based on the drawn random number.
    """
    macro stochastic(state_expr, rng_expr, block)
        # Parse the block to extract probability => action pairs
        pairs = []
        for line in block.args
            if isa(line, Expr) && line.head == :call && line.args[1] == :(=>)
                prob = line.args[2]
                action_call = line.args[3]
                push!(pairs, (prob, action_call))
            end
        end
        
        # Generate the runtime code
        quote
            let _state = $(esc(state_expr)), _rng_sym = $(esc(rng_expr))
                _actual_rng = get_rng(_state.rng_registry, _rng_sym)
                _r = rand(_actual_rng)
                _cumulative = 0.0
                
                $(map(pairs) do (prob, action)
                    # Transform apply!(gate, geo) to apply!(state, gate, geo)
                    if isa(action, Expr) && action.head == :call && action.args[1] == :apply!
                        gate = action.args[2]
                        geo = action.args[3]
                        quote
                            _cumulative += $(esc(prob))
                            if _r < _cumulative
                                apply!(_state, $(esc(gate)), $(esc(geo)))
                                @goto done
                            end
                        end
                    else
                        error("Expected apply!(gate, geo), got $action")
                    end
                end...)
                
                @label done
            end
        end
    end
    ```

  **Must NOT do**:
  - Make the macro too complex to debug
  - Deviate from Contract 4.4 (must draw once before all checks)

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
    - Reason: Macros require careful hygiene and AST manipulation
  - **Skills**: None

  **Parallelization**:
  - **Can Run In Parallel**: YES - with Tasks 2a, 2b, 2c

  **References**:
  - Julia metaprogramming docs
  - `src/API/probabilistic.jl` - Pattern to match

  **Acceptance Criteria**:
  - [ ] Macro compiles without errors
  - [ ] N-way branching supported
  - [ ] `@stochastic state :ctrl begin ... end` syntax works
  - [ ] RNG consumed exactly ONCE
  - [ ] All style implementations are exported from probabilistic_styles module

  **Implementation Note**: The macro pseudo-code shown is conceptual. Actual implementation may need:
  - Proper hygiene for local variables (`gensym()`)
  - Better error handling for malformed blocks
  - If macro proves too complex, Style D can be marked "technically infeasible" and excluded from comparison

  **Commit**: YES (includes all of Task 2)
  - Message: `feat(api): add 4 probabilistic API style implementations`
  - Files: `src/API/probabilistic_styles/*.jl`

---

### Task 3: Create Side-by-Side Comparison Example

- [x] 3. Create `examples/ct_model_styles.jl` showing ALL styles

  **What to do**:
  - Create a comprehensive example file that shows the EXACT SAME CT Model physics implemented in all 4 styles
  - Structure:
    ```julia
    # CT Model - API Style Comparison
    # This file shows the SAME physics logic implemented in 4 different styles
    # User should run this and choose their preferred syntax
    
    using QuantumCircuitsMPS
    
    # Common setup
    L = 10
    p_ctrl = 0.5
    seed_C = 42
    seed_m = 123
    
    #= ============================================
       STYLE A: Action-Based (apply_stochastic!)
       ============================================ =#
    
    function run_style_a()
        state = SimulationState(L=L, bc=:periodic, ...)
        left = StaircaseLeft(L)
        right = StaircaseRight(L)
        
        # Define actions (gate + geometry combined)
        reset_left = Action(Reset(), left)
        haar_right = Action(HaarRandom(), right)
        
        for t in 1:T
            # "With probability p_ctrl, reset and move left; otherwise Haar and move right"
            apply_stochastic!(state,
                p_ctrl => reset_left,
                (1-p_ctrl) => haar_right
            )
        end
        return get_dw(state)
    end
    
    #= ============================================
       STYLE B: Categorical/Tuple-Based
       ============================================ =#
    
    function run_style_b()
        # ... same setup ...
        
        for t in 1:T
            apply_categorical!(state, [
                (p_ctrl, Reset(), left),
                (1-p_ctrl, HaarRandom(), right)
            ])
        end
        return get_dw(state)
    end
    
    #= ============================================
       STYLE C: Fully Named Parameters
       ============================================ =#
    
    function run_style_c()
        # ... same setup ...
        
        for t in 1:T
            apply_branch!(state;
                rng = :ctrl,
                outcomes = [
                    (probability=p_ctrl, gate=Reset(), geometry=left),
                    (probability=1-p_ctrl, gate=HaarRandom(), geometry=right)
                ]
            )
        end
        return get_dw(state)
    end
    
    #= ============================================
       STYLE D: Macro/DSL
       ============================================ =#
    
    function run_style_d()
        # ... same setup ...
        
        for t in 1:T
            @stochastic state :ctrl begin
                p_ctrl => apply!(Reset(), left)
                (1-p_ctrl) => apply!(HaarRandom(), right)
            end
        end
        return get_dw(state)
    end
    
    #= ============================================
       PHYSICS VERIFICATION
       ============================================ =#
    
    println("Running all styles with same seed...")
    dw_a = run_style_a()
    dw_b = run_style_b()
    dw_c = run_style_c()
    dw_d = run_style_d()
    
    println("\n=== PHYSICS VERIFICATION ===")
    println("Style A DW1[1:5]: ", dw_a[:DW1][1:5])
    println("Style B DW1[1:5]: ", dw_b[:DW1][1:5])
    println("Style C DW1[1:5]: ", dw_c[:DW1][1:5])
    println("Style D DW1[1:5]: ", dw_d[:DW1][1:5])
    
    all_match = dw_a == dw_b == dw_c == dw_d
    println("\nAll styles produce identical physics: ", all_match ? "✓ PASS" : "✗ FAIL")
    
    #= ============================================
       STYLE COMPARISON TABLE
       ============================================ =#
    
    println("""
    
    ╔═══════════════════════════════════════════════════════════════════════════════╗
    ║                           API STYLE COMPARISON                                ║
    ╠═══════════╦═══════════════════════╦════════════════════════════════════════════╣
    ║ Style     ║ Pros                  ║ Cons                                       ║
    ╠═══════════╬═══════════════════════╬════════════════════════════════════════════╣
    ║ A: Action ║ • Gate+geometry       ║ • Requires Action() wrapper                ║
    ║           ║   unified             ║                                            ║
    ║           ║ • Clear probability   ║                                            ║
    ║           ║   association         ║                                            ║
    ╠═══════════╬═══════════════════════╬════════════════════════════════════════════╣
    ║ B: Tuple  ║ • Simple syntax       ║ • Position-based within tuple              ║
    ║           ║ • No new types        ║ • (prob, gate, geo) order to memorize      ║
    ╠═══════════╬═══════════════════════╬════════════════════════════════════════════╣
    ║ C: Named  ║ • Completely self-    ║ • Verbose for simple cases                 ║
    ║           ║   documenting         ║ • More typing                              ║
    ║           ║ • No memorization     ║                                            ║
    ╠═══════════╬═══════════════════════╬════════════════════════════════════════════╣
    ║ D: Macro  ║ • Reads like natural  ║ • Macros harder to debug                   ║
    ║           ║   language            ║ • Less IDE support                         ║
    ║           ║ • Cleanest syntax     ║                                            ║
    ╚═══════════╩═══════════════════════╩════════════════════════════════════════════╝
    
    Please run this file and choose your preferred style!
    """)
    ```

  **Must NOT do**:
  - Favor one style over another in the example
  - Skip the physics verification step
  - Use different seeds for different styles

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
    - Reason: Integration of all 4 styles requires attention to detail
  - **Skills**: None

  **Parallelization**:
  - **Can Run In Parallel**: NO (depends on Task 2 completion)
  - **Blocks**: User decision

  **References**:
  - `examples/ct_model.jl` - Current CT model implementation
  - Task 2 outputs - All 4 style implementations

  **Acceptance Criteria**:
  - [ ] File compiles and runs without errors
  - [ ] All 4 styles produce IDENTICAL DW values
  - [ ] Comparison table is printed
  - [ ] User can visually compare syntax

  **Commit**: YES
  - Message: `feat(examples): add CT model style comparison for API selection`
  - Files: `examples/ct_model_styles.jl`

---

### Task 4: Document Pros/Cons (Optional Enhancement)

- [x] 4. Add comprehensive pros/cons documentation

  **What to do**:
  - Add detailed documentation to each style file
  - Include in example output (already in Task 3)

  **Note**: This can be deferred if time is short - the comparison table in Task 3 covers the basics.

  **Commit**: NO (can be combined with Task 3)

---

### Task 5: Cleanup After User Selection

- [x] 5. After user chooses a style, clean up the API

  **What to do**:
  - User runs `examples/ct_model_styles.jl` and selects preferred style
  - Remove `src/API/probabilistic.jl` (old `apply_with_prob!`)
  - Move chosen style to `src/API/probabilistic.jl`
  - Archive other styles to `src/_deprecated/` or delete
  - Update exports in `src/QuantumCircuitsMPS.jl`

  **This task WAITS for user decision - do not execute until user confirms choice.**

  **Recommended Agent Profile**:
  - **Category**: `quick`
  - **Skills**: None

  **Parallelization**:
  - **Can Run In Parallel**: NO (requires user input)

  **Acceptance Criteria**:
  - [ ] Old `apply_with_prob!` is removed
  - [ ] Chosen style is the ONLY probabilistic API
  - [ ] `examples/ct_model.jl` uses the chosen style

  **Commit**: YES
  - Message: `refactor(api): replace apply_with_prob! with [chosen style]`
  - Files: Multiple

---

## Commit Strategy

| After Task | Message | Files | Verification |
|------------|---------|-------|--------------|
| 1 | `feat(api): add Action type unifying gate and geometry` | `action.jl` | Type exists |
| 2 | `feat(api): add 4 probabilistic API style implementations` | `style_*.jl` | All compile |
| 3 | `feat(examples): add CT model style comparison` | `ct_model_styles.jl` | Runs, shows comparison |
| 5 | `refactor(api): finalize probabilistic API with [style]` | Various | Old API removed |

---

## Success Criteria

### Verification Commands
```bash
# Run comparison example
julia --project=. examples/ct_model_styles.jl

# Expected output:
# - All 4 styles produce identical DW1/DW2 values
# - Comparison table is printed
# - "All styles produce identical physics: ✓ PASS"
```

### Final Checklist
- [x] All 4 styles implemented and working
- [x] N-way branching (3+ outcomes) works in all styles
- [x] Gate + geometry conceptually unified (Action type available)
- [x] Physics identical across all styles (same seed → same output)
- [x] User can make informed decision from comparison example
- [x] Contract 4.4 (RNG advancement) preserved in all styles
