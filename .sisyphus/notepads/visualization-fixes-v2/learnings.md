## [2026-01-30T15:50:00] Task: visualization-fixes-v2

### Learnings

**Test Optimization**
- Reducing `n_circuits` from 5→2 requires updating assertions (e.g., `length == 6` → `length == 3`)
- Pattern: 1 initial + n_circuits = expected length
- Test time reduced from ~50min target to 1m47s (highly effective)

**SVG White Fill**
- Luxor pattern: `sethue("white")` → `box(..., :fill)` → `sethue("black")` → `box(..., :stroke)`
- Must apply to BOTH single-qubit and multi-qubit gate boxes
- Located at lines 113-116 (single) and 126-129 (multi) in QuantumCircuitsMPSLuxorExt.jl

**Tutorial Fixes**
- Reset() should use StaircaseLeft, not StaircaseRight (canonical pattern in ct_model.jl)
- Observable access via `state.observables[:name]` returns Vector{Float64}
- Both .jl and .ipynb files needed updates

**Time Estimates**
- User was RIGHT to call out bloated estimates (10-15 hours was absurd)
- Actual time: ~15 minutes for all 3 tasks
- Metis review was valuable for catching missing assertion updates

### Patterns

**When optimizing tests:**
1. Identify expensive operations (simulate! with high n_circuits/n_steps)
2. Reduce parameters but maintain test coverage
3. Update assertions that depend on parameter values
4. Verify tests still pass

**When adding visual fixes:**
1. Read existing code first to understand rendering pattern
2. Apply fix consistently (both single and multi-qubit cases)
3. Test generation to ensure no runtime errors
4. Visual inspection optional but recommended

### Success Factors

- All 3 tasks were truly independent - parallel execution would have worked
- Clear line numbers in plan made changes surgical
- Verification commands caught all issues
- Atomic commits per task maintained clean history
