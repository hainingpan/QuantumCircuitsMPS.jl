
## [2026-01-30] SVG Observable Fixes - Completion

### Work Completed
All 5 tasks completed successfully:
1. SVG Y-axis inverted for upward time flow
2. SVG rendering verified with multi-qubit gates
3. Fixed record! API error in notebook Section 7
4. Added two tracking demo cells (every-gate vs final-only)
5. Verified Section 8 data access works

### Key Technical Details

#### SVG Coordinate Transformation
- Formula used: `y_new = wire_length - y_old`
- Qubit labels moved from y=-10 to y=wire_length+20 (y=670)
- Time step 1 now at bottom (y=625), higher steps above
- All gate positions inverted using same formula

#### Observable API Pattern
**WRONG**: `record!(state, :symbol)` - causes MethodError
**CORRECT**: `record!(state)` - records ALL tracked observables

The `record!` function signature is:
```julia
function record!(state; i1::Union{Int,Nothing}=nothing)
```
- One positional param: `state`
- One optional keyword param: `i1` (for DomainWall without i1_fn)
- NO symbol parameter

#### Tracking Modes Demonstrated
**Every-gate tracking** (Demo A):
- Calls `record!(state)` INSIDE loop after each gate
- Result: N recordings for N gates (fine-grained monitoring)

**Final-only tracking** (Demo B):
- Calls `record!(state)` AFTER loop completes
- Result: 1 recording (efficient for large simulations)

### Commits Created
1. `ac42f9f fix(svg): invert time axis and move qubit labels to bottom`
2. `ae523fc fix(notebook): correct record! API usage in Section 7`
3. `bd4b55f feat(notebook): add tracking mode demos (every-gate vs final-only)`

### Verification Evidence
- ✅ SVG qubit labels at y=670 (bottom)
- ✅ Time step 1 at y=625 (bottom), step 2 at y=565 (moving up)
- ✅ Observable data: [1.0, 1.0, 3.551985583120051] (non-empty)
- ✅ Demo A: 3 recordings, Demo B: 1 recording
- ✅ No MethodError in Section 7
- ✅ Package loads successfully
- ✅ All git commits follow semantic style

### Success Metrics
- 5/5 tasks completed
- 7/7 Definition of Done items complete
- 3/3 Final Checklist items complete
- 0 regressions introduced
- All user-reported issues fixed

### Files Modified
- `ext/QuantumCircuitsMPSLuxorExt.jl` - SVG coordinate inversion
- `examples/circuit_tutorial.ipynb` - API fix + tracking demos
- `examples/output/circuit_tutorial.svg` - Regenerated with new layout

### Session Duration
Approximately 13 minutes from start to completion.
