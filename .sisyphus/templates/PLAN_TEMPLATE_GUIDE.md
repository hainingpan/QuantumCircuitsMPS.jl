# Plan Template Guide

## Progress Visibility Best Practices

When creating work plans, follow these guidelines to ensure agents can report progress effectively.

---

## Task Breakdown Rules

### Rule 1: Maximum 30-Minute Subtasks

Break large tasks into subtasks that take ≤30 minutes each.

**BAD** (no visibility for hours):
```markdown
- [ ] 12. Add documentation and cleanup
```

**GOOD** (reportable every 15-30 min):
```markdown
- [ ] 12. Add documentation and cleanup

  **Subtasks** (report progress after each):
  1. Add module docstring to `src/Circuit/Circuit.jl`
  2. Add docstrings to `src/Circuit/types.jl` (5 functions)
  3. Add docstrings to `src/Circuit/builder.jl` (3 functions)
  4. Add docstrings to `src/Plotting/ascii.jl` (2 functions)
  5. Add docstring to `ext/QuantumCircuitsMPSLuxorExt.jl`
  6. Verify all `?` help works in REPL
  
  **Progress Checkpoints**:
  - After each file: Update progress.md with completion
  - After all files: Run verification and report results
```

---

## Rule 2: Specify Progress Indicators

Tell agents WHAT to report and WHEN.

**BAD** (vague):
```markdown
- [ ] 3. Implement feature X
```

**GOOD** (explicit checkpoints):
```markdown
- [ ] 3. Implement feature X

  **Progress Indicators**:
  - Before implementation: "Reading existing code in src/module.jl"
  - During implementation: "Modified lines 50-75 in src/module.jl"
  - After implementation: "Running tests"
  - On completion: "Tests pass, committing changes"
```

---

## Rule 3: List Files/Functions Explicitly

Enumerate specific files or functions to modify.

**BAD** (agent must discover):
```markdown
- [ ] 5. Add tests for all functions
```

**GOOD** (clear scope):
```markdown
- [ ] 5. Add tests for all functions

  **Files to test**:
  - `src/Gates/pauli.jl`: PauliX, PauliY, PauliZ (3 tests)
  - `src/Gates/haar.jl`: HaarRandom (2 tests)
  - `src/Geometry/staircase.jl`: StaircaseLeft, StaircaseRight (4 tests)
  
  **Progress**: Report after each file's tests complete
```

---

## Rule 4: Estimate Time

Provide rough time estimates for calibration.

```markdown
- [ ] 8. Refactor rendering loop

  **Estimated Time**: 45-60 minutes
  
  **Subtasks** (15-20 min each):
  1. Extract column-building logic (lines 84-100)
  2. Refactor rendering loop (lines 123-140)
  3. Update tests to match new structure
```

---

## Rule 5: Define "Done"

Specify exact acceptance criteria.

**BAD** (ambiguous):
```markdown
- [ ] 10. Make sure everything works
```

**GOOD** (verifiable):
```markdown
- [ ] 10. Verify implementation

  **Acceptance Criteria**:
  - [ ] `julia --project -e 'using Pkg; Pkg.test()'` exits with code 0
  - [ ] All 100+ tests pass
  - [ ] `lsp_diagnostics` shows zero errors
  - [ ] Example script runs without error
  
  **Progress**: Report result of each verification step
```

---

## Template Structure

Use this structure for all tasks:

```markdown
- [ ] N. Task Name

  **What to do**:
  - Clear description of the task
  - Expected outcome
  
  **Subtasks** (report progress after each):
  1. Subtask 1 (15-30 min)
  2. Subtask 2 (15-30 min)
  3. Subtask 3 (15-30 min)
  
  **Progress Checkpoints**:
  - When to update progress.md
  - What to report
  
  **Files to modify**:
  - `path/to/file1.jl` - what changes
  - `path/to/file2.jl` - what changes
  
  **Acceptance Criteria**:
  - [ ] Criterion 1 (verifiable)
  - [ ] Criterion 2 (verifiable)
  
  **Estimated Time**: X-Y minutes
```

---

## Examples from Real Plans

### Example 1: Documentation Task (Good)

```markdown
- [ ] 12. Add Module Documentation

  **What to do**:
  Add docstrings to all exported functions and types in the Circuit module.
  
  **Subtasks** (report progress after each):
  1. Module docstring for `src/Circuit/Circuit.jl` (10 min)
  2. Type docstrings in `src/Circuit/types.jl`: Circuit, ExpandedOp (15 min)
  3. Function docstrings in `src/Circuit/builder.jl`: apply!, apply_with_prob! (20 min)
  4. Function docstrings in `src/Plotting/ascii.jl`: print_circuit (10 min)
  5. Extension docstring in `ext/QuantumCircuitsMPSLuxorExt.jl`: plot_circuit (10 min)
  6. REPL verification: Test `?Circuit`, `?apply!`, `?print_circuit` (5 min)
  
  **Progress Checkpoints**:
  - After each file: "✅ Docstrings added to {file}"
  - After verification: "✅ All help text working in REPL"
  
  **Files to modify**:
  - `src/Circuit/Circuit.jl` - module docstring
  - `src/Circuit/types.jl` - Circuit, ExpandedOp docstrings
  - `src/Circuit/builder.jl` - apply!, apply_with_prob! docstrings
  - `src/Plotting/ascii.jl` - print_circuit docstring
  - `ext/QuantumCircuitsMPSLuxorExt.jl` - plot_circuit docstring
  
  **Acceptance Criteria**:
  - [ ] All exported functions have docstrings
  - [ ] `?Circuit` shows documentation in REPL
  - [ ] `?apply!` shows documentation in REPL
  - [ ] `?print_circuit` shows documentation in REPL
  
  **Estimated Time**: 70 minutes total
```

### Example 2: Implementation Task (Good)

```markdown
- [ ] 3. ASCII Multi-Qubit Gate Spanning Box

  **What to do**:
  Modify ASCII rendering to show ONE spanning box for multi-qubit gates instead of separate boxes per qubit.
  
  **Subtasks** (report progress after each):
  1. Write failing test showing current duplicate-label behavior (10 min)
  2. Modify rendering loop in `src/Plotting/ascii.jl` lines 123-140 (20 min)
  3. Add logic to detect multi-qubit gates and render spanning box (15 min)
  4. Run tests and verify single-qubit gates unchanged (10 min)
  5. Commit changes (5 min)
  
  **Progress Checkpoints**:
  - After test written: "RED phase complete - test fails as expected"
  - After implementation: "GREEN phase - running tests"
  - After tests pass: "REFACTOR phase - cleaning up code"
  - After commit: "Task complete"
  
  **Files to modify**:
  - `src/Plotting/ascii.jl` lines 123-140 - rendering loop
  - `test/circuit_test.jl` - add multi-qubit spanning box test
  
  **Acceptance Criteria**:
  - [ ] Multi-qubit gates show label once (not per qubit)
  - [ ] Single-qubit gates render identically to before
  - [ ] All existing tests still pass
  - [ ] New test added for spanning box behavior
  
  **Estimated Time**: 60 minutes
```

---

## Heartbeat Reminder

Agents MUST update progress.md every 5 minutes, even if just:
```markdown
### [HH:MM] Heartbeat
- Still working on: {current subtask}
```

No update for 10+ minutes = potential stuck state.

---

## Summary Checklist

When writing a plan, ensure:
- [ ] Tasks broken into ≤30 minute subtasks
- [ ] Progress checkpoints specified
- [ ] Files to modify listed explicitly
- [ ] Acceptance criteria are verifiable
- [ ] Time estimates provided
- [ ] "What to report" is clear at each checkpoint
