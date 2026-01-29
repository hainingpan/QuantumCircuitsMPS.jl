# Draft: Multiple Probabilistic API Styles Comparison

## Requirements (confirmed)

- **Multiple styles for comparison**: User wants to see ALL styles as final products to make informed choice
- **User's THREE complaints about current `apply_with_prob!`**:
  1. Only supports 2 outcomes (not generalizable to 3+)
  2. Does not conceptually combine gate with geometry
  3. Bad readability - positional arguments require memorization
- **User requested this THREE TIMES** in prompt_history.md (lines 91, 122, 173) - never delivered

## Technical Decisions

- **Number of styles**: Implement all 4 (unless one is obviously absurd)
- **Comparison example**: Use CT Model (exact same physics logic in all styles)
- **Current API fate**: Replace `apply_with_prob!` completely (no alias, no deprecation)
- **Philosophy**: "Physicists code as they speak"

## Style Candidates

### Style A: Action-Based (Unified Gate+Geometry)
```julia
reset_left = Action(Reset(), left)
haar_right = Action(HaarRandom(), right)
apply_stochastic!(state, p_ctrl => reset_left, (1-p_ctrl) => haar_right)
```
- Pros: Combines gate+geometry; N-way natural; clear probability association
- Cons: Requires new `Action` wrapper type

### Style B: Categorical/Distribution Tuple-Based
```julia
apply_categorical!(state, [
    (p_ctrl, Reset(), left),
    (1-p_ctrl, HaarRandom(), right)
])
```
- Pros: Simple tuple syntax; N-way natural; no new types
- Cons: Still position-based within tuple

### Style C: Fully Named Parameters
```julia
apply_branch!(state;
    rng = :ctrl,
    outcomes = [
        (probability=p_ctrl, gate=Reset(), geometry=left),
        (probability=1-p_ctrl, gate=HaarRandom(), geometry=right)
    ]
)
```
- Pros: Completely self-documenting; no argument order to memorize
- Cons: Verbose for simple cases

### Style D: Macro/DSL (Turing.jl-Inspired)
```julia
@stochastic state :ctrl begin
    p_ctrl => apply!(Reset(), left)
    (1-p_ctrl) => apply!(HaarRandom(), right)
end
```
- Pros: Reads like natural language; clean syntax
- Cons: Macros can be harder to debug

## Research Findings

### Cirq (Google) - Fluent Approach
```python
gate = cirq.X.with_probability(0.3)
mixture = [(0.5, I), (0.3, X), (0.2, Y)]  # Multi-outcome
```

### Turing.jl / Gen.jl - Julia PPL Style
```julia
gate_choice ~ Categorical([0.25, 0.25, 0.25, 0.25])
```

## Scope Boundaries

### INCLUDE
- All 4 style implementations in `src/API/probabilistic_styles.jl`
- Comparison example: `examples/ct_model_styles.jl`
- Style comparison document / pros-cons table
- Delete current `apply_with_prob!` implementation

### EXCLUDE
- Changes to core `apply!` engine
- Changes to Gate or Geometry types
- Any backward compatibility with old API
- Performance optimization (functional correctness first)

## Open Questions

- None remaining - ready for plan generation

## Contract Requirements (from quantum-circuits-mps-v2.md)

### Contract 4.4: RNG Advancement
CRITICAL: ALL styles must draw random number BEFORE checking probability.
This ensures deterministic RNG advancement regardless of which branch is taken.

### Physics Correctness
All styles must:
1. Use the same RNG stream (`:ctrl` for CT model)
2. Draw ONCE per decision
3. Produce identical physics when seeded identically
