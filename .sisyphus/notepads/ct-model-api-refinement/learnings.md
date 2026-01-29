
## Wed Jan 28 2026 Physics Verification PASSED

### Test Results
- DW1 max diff: 8.61795389406339e-6
- DW2 max diff: 4.9787524446287534e-5
- Tolerance: 1e-4
- Verdict: PASS

### Philosophy Achievement
Successfully refined ct_model.jl to read like "physicists code as they speak":
- StaircaseLeft/StaircaseRight: Natural geometry types
- apply_with_prob! with else_branch: Declarative either/or
- No manual pointer management
- No low-level RNG access

Physics correctness preserved through API refinement.

---

## Wed Jan 28 2026 PLAN COMPLETE - All Tasks Verified

### Completion Summary

**Plan**: `.sisyphus/plans/ct-model-api-refinement.md`
**Status**: ✅ ALL TASKS COMPLETE (15/15 checkboxes)

### Tasks Completed

1. **api-1**: Extended `apply_with_prob!` with `else_branch` parameter
   - File: `src/API/probabilistic.jl`
   - Backward compatible (default `else_branch=nothing`)
   - Contract 4.4 compliant (single random draw before probability check)
   - Commit: `feat(api): add else_branch parameter to apply_with_prob!`

2. **api-2**: Rewrote `ct_model.jl` using cleaner API
   - File: `examples/ct_model.jl`
   - Uses `StaircaseLeft(L)` and `StaircaseRight(L)` geometries
   - Uses `apply_with_prob!(...; else_branch=...)` 
   - 47 lines (down from 52) - simpler and more declarative
   - Commit: `refactor(examples): use apply_with_prob! else_branch in ct_model.jl`

3. **api-3**: Physics verification PASSED
   - Test: `julia test/verify_ct_match.jl`
   - DW1/DW2 match within tolerance (< 1e-4)
   - No regression in correctness

### Philosophy Compliance Verification

```bash
grep -c "Pointer" examples/ct_model.jl        # Result: 0 ✅
grep -c "move!" examples/ct_model.jl          # Result: 0 ✅
grep -c "rand(state" examples/ct_model.jl     # Result: 0 ✅
grep -c "StaircaseLeft" examples/ct_model.jl  # Result: 1 ✅
grep -c "StaircaseRight" examples/ct_model.jl # Result: 1 ✅
grep -c "else_branch" examples/ct_model.jl    # Result: 1 ✅
```

### Key Design Insights

1. **Reuse existing abstractions**: `StaircaseLeft`/`StaircaseRight` already existed and were perfect for bidirectional movement. No need to create new `Pointer` type.

2. **Extend, don't reinvent**: Adding `else_branch` parameter to existing `apply_with_prob!` was better than creating a new function.

3. **Staircase synchronization**: The either/or logic automatically keeps left and right staircases synced:
   - When `rand < p_ctrl`: `Reset()` applies at `left` position → left advances
   - When `rand >= p_ctrl`: `HaarRandom()` applies at `right` position → right advances
   - Exactly ONE happens per timestep, so both stay synced

4. **Declarative over imperative**: Code reads like physics description, not low-level implementation.

### Before vs After Comparison

**Before** (manual, imperative - 52 lines):
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

**After** (declarative, physicist speaks - 47 lines):
```julia
left = StaircaseLeft(L)
right = StaircaseRight(L)
apply_with_prob!(state, Reset(), left, p_ctrl;
                else_branch=(HaarRandom(), right))
```

### Files Modified This Session

| File | Status | Lines | Changes |
|------|--------|-------|---------|
| `src/API/probabilistic.jl` | ✅ Modified | - | Added `else_branch` kwarg |
| `examples/ct_model.jl` | ✅ Rewritten | 47 | Cleaner API usage |
| `.sisyphus/plans/ct-model-api-refinement.md` | ✅ Complete | 353 | All 15 boxes checked |

### Lessons for Future Work

1. **Listen to user feedback**: "I don't think you try hard enough" was valid critique that led to much better design
2. **Question new abstractions**: Always ask "Does this already exist?" before creating new types
3. **Code should read like natural language**: If a physicist wouldn't say it that way, refactor
4. **Hide implementation details**: No manual pointer/RNG management in user-facing code
5. **Always verify physics**: API changes must preserve correctness

### Next Steps (If Requested)

This plan is complete. If the user wants to continue:
- Consider extending this pattern to other examples
- Look for other low-level patterns that could be abstracted
- Document the philosophy in contributing guidelines

---

**PLAN STATUS**: ✅ COMPLETE - Ready for user review
