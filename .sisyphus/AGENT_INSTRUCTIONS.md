# Agent Instructions: Progress Visibility Protocol

## For Atlas (Orchestrator) Agents

### Progress Tracking Requirements

When executing a boulder plan, you MUST:

1. **Initialize progress.md** at boulder start:
   ```bash
   cp .sisyphus/templates/progress-template.md .sisyphus/notepads/{boulder-name}/progress.md
   # Fill in initial values
   ```

2. **Update progress.md** at these triggers:
   - Task start: `[HH:MM] Task N - {name}: Started`
   - Before each delegation: `[HH:MM] Delegating to {agent}: {task}`
   - After delegation completes: `[HH:MM] Task N: Completed by {agent}`
   - Task completion: `[HH:MM] ✅ Task N complete`

3. **Heartbeat every 5 minutes**:
   - Even if just: `[HH:MM] Still coordinating Task N`
   - Include current action: "Waiting for subagent", "Verifying tests", etc.

4. **Update "Last Update" timestamp** with every write

### Example Progress Updates

```markdown
### [14:23] Task 3 - ASCII Multi-Qubit Spanning Box
- ⏳ Started: Delegating to Sisyphus-Junior-unspecified-low
- 🔄 In Progress: Agent working on rendering loop modification

### [14:28] Heartbeat
- Still monitoring Task 3 execution
- Agent has made 3 file modifications

### [14:35] Task 3 - Verification
- Running lsp_diagnostics
- Running test suite
- ✅ All tests pass

### [14:37] Task 3 Complete
- Files modified: src/Plotting/ascii.jl, test/circuit_test.jl
- Commit: fix(plotting): render multi-qubit gates with single spanning box
```

---

## For Sisyphus (Execution) Agents

### Progress Tracking Requirements

When executing a delegated task, you MUST:

1. **Append to progress.md** (do NOT overwrite):
   ```markdown
   ### [HH:MM] Subtask: {description}
   - Action: {what you're doing}
   - Files: {files being modified}
   ```

2. **Update at these triggers**:
   - Before reading files: `Reading: path/to/file.jl`
   - Before modifying files: `Modifying: path/to/file.jl`
   - After running tests: `Tests: {result}`
   - Before commits: `Committing: {message}`

3. **Heartbeat every 5 minutes**:
   - `[HH:MM] Still working on: {current action}`

4. **Use APPEND mode** for all progress.md writes:
   ```julia
   # Read existing content
   existing = read(".sisyphus/notepads/{boulder}/progress.md", String)
   # Append new entry
   write(".sisyphus/notepads/{boulder}/progress.md", existing * "\n### [HH:MM] ...\n")
   ```

### Example Progress Updates

```markdown
### [14:24] Subtask: Modify ASCII rendering loop
- Reading: src/Plotting/ascii.jl lines 123-140
- Analyzing: Current multi-qubit gate rendering logic

### [14:27] Subtask: Implementing spanning box logic
- Modifying: src/Plotting/ascii.jl
- Changes: Lines 127-139 - added single-box rendering for multi-qubit gates

### [14:29] Heartbeat
- Still working on: Test implementation

### [14:32] Subtask: Running tests
- Command: julia --project -e 'using Pkg; Pkg.test()'
- Tests: PASS (100/100)

### [14:35] Subtask: Committing changes
- Commit: fix(plotting): render multi-qubit gates with single spanning box
- Files: src/Plotting/ascii.jl, test/circuit_test.jl
```

---

## Stuck Detection

**For Users**: If `progress.md` has no update for 10+ minutes, the agent may be stuck.

**Recovery**:
1. Interrupt the session
2. Resume with `session_id` to preserve context
3. Provide specific guidance: "You were stuck on X, try Y instead"

**Watchdog command**:
```bash
# Alert if no progress update in 10 minutes
watch -n 60 'find .sisyphus/notepads/*/progress.md -mmin -10 || echo "⚠️ No progress update in 10 minutes!"'
```

---

## Plan Author Guidelines

When creating plans, break down large tasks:

**BAD** (no visibility):
```markdown
- [ ] 12. Add documentation
```

**GOOD** (reportable progress):
```markdown
- [ ] 12. Add documentation

  **Subtasks** (report progress after each):
  1. Add module docstring to `src/Circuit/Circuit.jl`
  2. Add docstrings to `src/Circuit/types.jl` exports
  3. Add docstrings to `src/Circuit/builder.jl` exports
  4. Add docstrings to `src/Plotting/ascii.jl` exports
  5. Verify all `?` help works in REPL
  
  **Progress Checkpoints**:
  - After each file: Update progress.md
  - After all files: Run verification
```

Expected work time per subtask: 15-30 minutes maximum.
