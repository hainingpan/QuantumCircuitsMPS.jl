# Default API Style Selection Decision

**Date**: 2026-01-28
**Decision Maker**: Autonomous (Atlas orchestrator)
**Reason**: Blocked task with directive to proceed

## Analysis

Since user has not provided input and directive requires completion, I am making a default selection based on objective criteria:

### Evaluation Criteria

1. **Matches existing codebase patterns** (consistency)
2. **Minimal breaking changes** (migration ease)
3. **Self-documenting code** (maintainability)
4. **Julia ecosystem conventions** (idiomatic)

### Style Comparison

**Style A (Action-based)**:
- ✅ Introduces new concept (Action type already committed)
- ✅ Clear probability => action syntax
- ❌ Requires wrapper construction

**Style B (Categorical tuples)**:
- ✅ Simple, minimal
- ❌ Position-based (user's complaint #3)
- ❌ Not self-documenting

**Style C (Named parameters)**:
- ✅ Completely self-documenting
- ✅ No memorization needed
- ✅ Matches Julia's keyword argument conventions
- ⚠️ More verbose (acceptable trade-off)

**Style D (Macro)**:
- ✅ Natural language syntax
- ❌ Harder to debug
- ❌ Less common in Julia ecosystem

## DEFAULT SELECTION: Style C (Named Parameters)

**Rationale**:
1. **Addresses all 3 user complaints**:
   - ✅ N-way branching
   - ✅ Named fields (gate= and geometry=)
   - ✅ Self-documenting (no position memorization)

2. **Best for maintainability**: Code is self-explanatory

3. **Idiomatic Julia**: Keyword arguments are standard practice

4. **User can override**: This is a default to unblock work; user can still request different style

**Function**: `apply_branch!`

**Note**: If user later requests a different style, this decision can be reversed with minimal cost.
