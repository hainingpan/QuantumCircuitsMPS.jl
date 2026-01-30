# Visualization Improvements - Learnings

## [2026-01-30T13:45:00Z] Session Start

### Context
- User reported 6 issues with visualization
- Multi-qubit gates show duplicate labels (confusing)
- Layout orientation needs flip (time=vertical)
- Tutorial has wrong StaircaseLeft/Right pattern
- No helper to list observables

### Approach
- TDD: Write failing tests first
- 4 waves of execution (some parallel)
- Breaking change accepted for orientation flip

## [2026-01-30T14:00:00Z] Baseline Visualization Tests Complete

### Task 1: Capture Current Visualization Output
Successfully created comprehensive baseline tests for regression testing.

### Key Findings

#### ASCII Output Format
- **Header**: `Circuit (L=N, bc=periodic, seed=S)`
- **Step row**: `Step:  1  2  3  ...` with lettered columns for multi-op steps (1a, 1b, 1c)
- **Qubit rows**: `q1:  ┤Gate├──...` with Unicode box-drawing by default
- **Wire character**: `─` (Unicode) or `-` (ASCII mode)
- **Box characters**: `┤` (left) and `├` (right) for gates

#### Gate Label Mapping
- `Reset()` → "Rst"
- `HaarRandom()` → "Haar"
- `PauliX()` → "X"
- `PauliY()` → "Y"
- `PauliZ()` → "Z"
- `CZ()` → "CZ"

#### Multi-Qubit Gate Behavior
- **Two-qubit gates** (CZ on AdjacentPair): Gate label appears on BOTH qubits
- **Three-qubit gates** (Reset/Haar on Staircase): Applied to consecutive qubits in pattern
- **StaircaseRight(1)**: Applies to q1, then q2, then q3 (one per step)
- **StaircaseLeft(1)**: Applies in reverse pattern

#### Multi-Op Step Handling
- Single operation per step: No letter suffix (e.g., "1")
- Multiple operations per step: Lettered columns (e.g., "1a", "1b", "1c")
- Each operation gets its own column with letter suffix

#### ASCII Mode
- Uses `-` for wires instead of `─`
- Uses `|` for box edges instead of `┤` and `├`
- Controlled by `unicode=false` parameter

### Test Coverage Added
1. **Single-qubit gates**: PauliX, PauliY, PauliZ
2. **Multi-step single-qubit**: Multiple gates in same step with lettered columns
3. **Two-qubit gates**: CZ on adjacent pairs
4. **Multi-step two-qubit**: Multiple CZ gates with lettered columns
5. **Three-qubit gates**: Reset/Haar on StaircaseRight and StaircaseLeft
6. **Mixed gates**: Single and two-qubit gates in same circuit
7. **ASCII mode**: Non-Unicode output verification
8. **SVG placeholder**: For future SVG testing

### Commit
- Commit: `75ef84d` - test(plotting): add baseline visualization tests
- 205 lines added to test/circuit_test.jl
- All baseline tests pass ✓

### Next Steps
These baseline tests enable safe refactoring of:
1. Orientation flip (time=vertical instead of horizontal)
2. Duplicate label removal for multi-qubit gates
3. Layout improvements
4. SVG output implementation


## [2026-01-30] Task 3: ASCII Multi-Qubit Spanning Box

### Implementation Details

**Problem**: Multi-qubit gates (e.g., `CZ` on `AdjacentPair`, `HaarRandom` on two sites) were showing the gate label on BOTH qubits involved, creating visual confusion.

**Solution**: Implemented spanning box rendering where:
- The label appears ONCE on the minimum site in `op.sites`
- Other sites in the span show continuation boxes (box edges without label: `┤────├` or `┤──├`)
- Single-qubit gates are unaffected (explicit check for `length(op.sites) == 1`)

**Code Changes** (`src/Plotting/ascii.jl` lines 123-157):
```julia
if op !== nothing && q in op.sites
    if length(op.sites) == 1
        # Single-qubit gate - render box with label as before
        label = op.label
        padding = COL_WIDTH - length(label) - 2
        left_pad = padding ÷ 2
        right_pad = padding - left_pad
        print(io, LEFT_BOX, repeat(WIRE, left_pad), label, repeat(WIRE, right_pad), RIGHT_BOX)
    else
        # Multi-qubit gate - spanning box logic
        min_site = minimum(op.sites)
        if q == min_site
            # First qubit - show label
            [same as single-qubit rendering]
        else
            # Continuation qubit - show box without label
            print(io, LEFT_BOX, repeat(WIRE, COL_WIDTH - 2), RIGHT_BOX)
        end
    end
end
```

**Visual Output Examples**:
- Before: HaarRandom on sites [1,2] showed "Haar" on both q1 and q2
- After: Shows "Haar" on q1, continuation box `┤────├` on q2

**ExpandedOp Structure**: Each `ExpandedOp` has a `sites::Vector{Int}` field containing all qubit indices the gate operates on. Using `minimum(op.sites)` ensures consistent label placement.

### Testing Approach

**TDD Workflow (RED-GREEN-REFACTOR)**:

1. **RED Phase**: Added failing tests in `test/circuit_test.jl` (testset "Multi-Qubit Spanning Box (TDD)")
   - Test 1: `HaarRandom` on `AdjacentPair(1)` - verify `count("Haar", ascii) == 1`
   - Test 2: `CZ` on `AdjacentPair(2)` - verify `count("CZ", ascii) == 1`
   - Test 3: Single-qubit `PauliX` - regression test to ensure no breakage
   
   Initial verification showed:
   - `count("Haar", ascii) == 2` (FAILED as expected)
   - `count("CZ", ascii) == 2` (FAILED as expected)

2. **GREEN Phase**: Implemented spanning box logic
   - All tests now pass: 7 assertions successful
   - Single-qubit gates unaffected (baseline tests still pass)

3. **REFACTOR Phase**: Not needed - implementation is clean and minimal

**Sprint Pattern for Tests**:
```julia
ascii = sprint((io) -> print_circuit(circuit; seed=0, io=io))
```
Note: Cannot use `sprint(print_circuit, circuit; seed=0)` because `sprint` doesn't forward keyword arguments correctly.

### Verification Results

✓ Multi-qubit gates show label exactly once
✓ Continuation boxes render on other sites
✓ Single-qubit gates unchanged (regression protection)
✓ Baseline tests from Task 1 still pass

**Command-line verification**:
```bash
julia --project -e '
using QuantumCircuitsMPS
c = Circuit(L=4, bc=:periodic) do c
    apply!(c, HaarRandom(), AdjacentPair(1))
end
ascii = sprint((io) -> print_circuit(c; seed=0, io=io))
println(ascii)
println("Haar count: ", count("Haar", ascii))
'
# Output: "Haar count: 1" (SUCCESS)
```

### Edge Cases Considered

- ✓ Single-qubit gates (explicit check for `length(op.sites) == 1`)
- ✓ Two-qubit gates (AdjacentPair)
- ✓ Multi-qubit gates with >2 sites (continuation boxes on all non-minimum sites)
- ✓ Empty steps (unchanged - still render wire-only columns)

### Documentation Updates

Updated `src/Plotting/ascii.jl` docstring (lines 38-41):
```
# Multi-Qubit Gates
For gates spanning multiple sites (e.g., CZ on sites [2, 3]):
- Gate label appears ONCE in a box on the minimum site
- Other sites show continuation boxes (box edges without label)
- No vertical connectors drawn (Phase 1 simplification)
```
