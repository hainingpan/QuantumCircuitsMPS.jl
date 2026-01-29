# Learnings: Probabilistic API Styles

## Action Type
- Created unified `Action` type in `src/API/probabilistic_styles/action.jl`.
- It combines `AbstractGate` and `AbstractGeometry`.
- This follows the "Physicists code as they speak" philosophy, making the "action" the atomic unit.
- The `apply!(state, action)` method provides a clean delegation to the core `apply!` engine.
- Verification confirmed that `Action` can be instantiated with existing gate and geometry types.

## Style A: Action-Based apply_stochastic!
- Implemented in `src/API/probabilistic_styles/style_a_action.jl`.
- Uses variadic `Pair{<:Real, Action}...` to support N-way branching.
- Strictly follows Contract 4.4: draws ONE random number before any logic.
- Includes validation that probabilities sum to 1.0 (tolerance 1e-10).
- `Action` and `apply_stochastic!` exported from main module.

## Task 3: CT Model Style Comparison Example

- Created `examples/ct_model_styles.jl` with all 4 API styles implementing IDENTICAL CT Model physics
- All 4 styles use same parameters: L=10, p_ctrl=0.5, seed_C=42, seed_m=123, steps=200
- Physics verification confirms all 4 styles produce identical DW1 and DW2 values
- Key insight: All styles correctly implement Contract 4.4 (draw ONE random BEFORE checking probabilities)
- The comparison table helps users choose their preferred syntax style

## Probabilistic API Style Documentation (2026-01-28)
- Added comprehensive pros/cons headers to all 4 probabilistic API style files.
- Headers follow a consistent template: Philosophy, Pros, Cons, When to Use.
- Verified that adding large block comments at the top of files included via `include()` does not break module loading.
- Documentation is neutral and factual, derived from the comparison table in `examples/ct_model_styles.jl`.

## Task 4: Comprehensive Documentation
- Added pros/cons headers to all 4 style files.
- Each header includes: Philosophy, Pros, Cons, When to Use, and reference to comparison example.
- Documentation is neutral and factual to avoid biasing user choice.
- Module verification: All styles load successfully with comprehensive documentation.

## Completion Status (as of current)
- ✅ Task 1: Action type created and committed
- ✅ Task 2a-2d: All 4 styles implemented and committed
- ✅ Task 3: Comparison example created and committed
- ✅ Task 4: Documentation enhanced and committed
- 🚫 Task 5: BLOCKED - Requires user to select preferred style

## Blocker Documentation
Task 5 cannot proceed without user input. The plan explicitly states:
"This task WAITS for user decision - do not execute until user confirms choice."

User must:
1. Run `julia --project=. examples/ct_model_styles.jl`
2. Review all 4 API styles
3. Confirm their choice (A, B, C, or D)

Only after explicit user confirmation can Task 5 proceed to:
- Remove old `apply_with_prob!` API
- Promote chosen style to official API
- Archive/delete other 3 styles

## Final Status: Work Complete Except User-Blocked Task

**Date**: 2026-01-28

All implementation work is complete. The only remaining task (Task 5) cannot proceed without user input.

**Summary**:
- Tasks 1-4: ✅ COMPLETE (100% of automatable work)
- Task 5: 🚫 BLOCKED (requires user decision)

**Evidence of Completion**:
1. All 4 API styles implemented, documented, and tested
2. Comparison example created and verified
3. All acceptance criteria met except those dependent on Task 5
4. All commits atomic and well-documented

**Blocker properly documented in**: `.sisyphus/notepads/probabilistic-api-styles/problems.md`

**Next action**: Await user style selection (A, B, C, or D)
