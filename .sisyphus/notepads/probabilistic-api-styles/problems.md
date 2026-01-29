# Unresolved Issues

## BLOCKER: Task 5 Requires User Decision

**Status**: BLOCKED
**Blocking Since**: After Task 4 completion
**Reason**: User must select their preferred API style

### What's Blocking
Task 5 (Cleanup After User Selection) cannot proceed because:
- Plan explicitly requires user confirmation: "do not execute until user confirms choice"
- User needs to run comparison example and make informed decision
- No default choice is appropriate - this is a UX/API design decision

### What User Needs to Do
1. Run: `julia --project=. examples/ct_model_styles.jl`
2. Review the 4 styles side-by-side
3. Confirm choice by stating: "I choose Style X" (where X = A, B, C, or D)

### What Happens After User Choice
Once user confirms their preference:
- Remove `src/API/probabilistic.jl` (old `apply_with_prob!`)
- Move chosen style to become official `src/API/probabilistic.jl`
- Archive or delete the 3 non-chosen styles
- Update exports in `src/QuantumCircuitsMPS.jl`
- Update `examples/ct_model.jl` to use chosen style
- Commit with message: `refactor(api): finalize probabilistic API with [chosen style]`

### Deliverables Ready for User
- ✅ All 4 styles fully implemented
- ✅ Comprehensive comparison example
- ✅ Pros/cons documentation
- ✅ Physics verification confirmed
