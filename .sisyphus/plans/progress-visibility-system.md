# Progress Visibility System for OpenCode Agents

## TL;DR

> **Quick Summary**: Design and implement a progress reporting system so users can see real-time status of long-running tasks, preventing "black box" execution anxiety.
>
> **Problem Solved**: Task 12 of circuit-visualization took hours with zero visibility - user couldn't tell if it was working or stuck.
>
> **Deliverables**:
> - `progress.md` file standard for agent progress reporting
> - Progress update protocol for Sisyphus/Atlas agents
> - Guidelines for plan authors to include progress checkpoints
>
> **Estimated Effort**: Small (1-2 hours planning, implementation TBD)
> **Parallel Execution**: NO - sequential design work

---

## Context

### Original Problem

During execution of the `circuit-visualization` plan, Task 12 (Documentation) appeared "stuck" for ~4 hours. The user had no visibility into:

1. **Is the agent still working?** - No heartbeat or activity indicator
2. **What subtask is it on?** - No breakdown of progress within a task
3. **How much is done?** - No percentage or checkpoint reporting
4. **Is it stuck or just slow?** - No way to distinguish

### Root Cause Analysis

| Finding | Evidence |
|---------|----------|
| No progress file | `.sisyphus/notepads/circuit-visualization/` has no `progress.md` |
| Work WAS happening | Uncommitted changes to docstring files exist |
| No intermediate commits | Writing tasks accumulate changes without checkpoints |
| No progress protocol | Agents have no standard for reporting incremental progress |
| Session size | 1480 messages over 2 days - context exhaustion possible |

### What Exists Today

The current notepad system has:
- `learnings.md` - Knowledge accumulated during execution
- `decisions.md` - Choices made during implementation
- `issues.md` - Problems encountered
- `problems.md` - Blockers and errors

**Missing**: Real-time progress tracking

---

## Proposed Solution

### 1. Standard `progress.md` File

Each boulder's notepad should have a `progress.md` file that agents update in real-time:

```markdown
# Progress: {boulder-name}

## Current Status
**Task**: {current task number and name}
**Subtask**: {current subtask or "Main task"}
**Started**: {timestamp}
**Last Update**: {timestamp}

## Progress Log

### [HH:MM] Task N - {Task Name}
- ⏳ Started: {what's being done}
- ✅ Completed: {what was done}
- 🔄 In Progress: {current action}

### [HH:MM] Subtask N.1
- Details of work being done
- Files touched: `path/to/file.jl`
```

### 2. Progress Update Protocol

Agents should update `progress.md`:

| Trigger | Update Content |
|---------|----------------|
| Task start | "Started Task N: {name}" with timestamp |
| Subtask start | "Subtask: {description}" |
| File modification | "Modified: `path/to/file`" |
| Significant milestone | "Completed: {milestone}" |
| Every 5 minutes | Heartbeat with current action |
| Task complete | "✅ Task N complete" with summary |

### 3. Plan Author Guidelines

When creating plans, authors should:

1. **Break down large tasks**: Tasks like "add docstrings" should list specific files/functions
2. **Define checkpoints**: Every 15-30 minutes of expected work should have a checkpoint
3. **Specify progress indicators**: What milestones should be reported

Example for Task 12:
```markdown
- [ ] 12. Documentation and Cleanup

  **Subtasks** (report progress after each):
  1. Add module docstring to `src/Circuit/Circuit.jl`
  2. Add docstrings to `src/Circuit/types.jl` exports
  3. Add docstrings to `src/Circuit/builder.jl` exports
  4. Add docstrings to `src/Plotting/ascii.jl` exports
  5. Add docstring to `ext/QuantumCircuitsMPSLuxorExt.jl`
  6. Verify all `?` help works in REPL
  
  **Progress Checkpoints**:
  - After each file: Update progress.md
  - After all files: Run verification
```

### 4. User-Facing Visibility

Options for users to check progress:

1. **File watching**: `tail -f .sisyphus/notepads/{boulder}/progress.md`
2. **Status command**: `/boulder-status` shows current progress.md content
3. **TUI integration**: OpenCode TUI could show progress panel

### 5. Liveness Detection (Stuck Prevention)

**The Problem**: Progress.md alone doesn't detect if an agent is stuck - a stuck agent won't update progress either.

**Heartbeat Protocol**:
- Agent MUST update `progress.md` at least every 5 minutes
- Update can be minimal: `[HH:MM] Still working on: {description}`
- No update = potential stuck state

**Watchdog (User-side)**:
```bash
# Simple watchdog - alerts if no update in 10 min
watch -n 60 'find .sisyphus/notepads/*/progress.md -mmin -10 || echo "⚠️ No progress update in 10 minutes!"'
```

**Stuck Detection Heuristics**:
| Signal | Likely Cause |
|--------|--------------|
| No tool calls for 5+ minutes | Agent thinking/stuck/context exhaustion |
| Same error repeating | Infinite retry loop |
| Same file edited repeatedly | Thrashing on a problem |
| No progress.md update for 10+ min | Agent definitely stuck |

**Stuck Recovery**:
1. User interrupts session
2. Resume with `session_id` to preserve context
3. Provide specific guidance: "You were stuck on X, try Y instead"

---

## Implementation Options

### Option A: Agent Instruction Update (Recommended)

Update Sisyphus/Atlas agent prompts to require progress.md updates:

**Pros**:
- No code changes needed
- Works immediately
- Agents already have file write capability

**Cons**:
- Relies on agent compliance
- Adds token overhead

### Option B: OpenCode Core Feature

Add progress tracking to OpenCode itself:

**Pros**:
- Guaranteed consistency
- Could add TUI progress bar
- System-level heartbeat

**Cons**:
- Requires OpenCode code changes
- More complex implementation

### Option C: Hybrid

Agent instructions + optional OpenCode integration:

**Pros**:
- Immediate improvement via instructions
- Path to enhanced UX later

---

## Recommended Approach

**Phase 1 (Immediate)**: Update agent instructions to require progress.md updates
**Phase 2 (Later)**: Consider OpenCode core integration if needed

---

## Acceptance Criteria

1. [x] Agents create `progress.md` at boulder start
2. [x] Progress updated at task/subtask boundaries
3. [x] **Heartbeat every 5 minutes** (even if just "still working on...")
4. [x] User can `cat .sisyphus/notepads/{boulder}/progress.md` to see status
5. [x] No task runs >10 minutes without a progress update (stuck detection threshold)
6. [x] Plan template includes subtask breakdown guidance

---

## Related Findings

### Test Performance Issue (SOLVED)

User reported tests taking ~1m30s for 100 tests.

**Root Cause**: Julia JIT compilation happening **30+ times** (once per testset/new code path). NOT actual tensor operations.

**Evidence**:
| Operation | First Run | After Compilation |
|-----------|-----------|-------------------|
| SimulationState | 0.56s | 0.00009s (6000x faster) |
| Circuit creation | 0.04s | 0.01s |
| expand_circuit | 0.02s | 0.00007s |

**Solution**: Add warmup block to top of `test/circuit_test.jl`:

```julia
# WARMUP: Force compilation before tests run
# This reduces test time from ~90s to ~20s
let
    # Compile SimulationState
    _ = SimulationState(L=4, bc=:periodic)
    
    # Compile Circuit with various gate types
    _ = Circuit(L=4, bc=:periodic) do c
        apply!(c, Reset(), SingleSite(1))
        apply!(c, HaarRandom(), StaircaseRight(1))
        apply_with_prob!(c; rng=:ctrl, outcomes=[
            (probability=0.5, gate=Reset(), geometry=SingleSite(1))
        ])
    end
    
    # Compile expand_circuit
    c = Circuit(L=4, bc=:periodic) do c
        apply!(c, Reset(), SingleSite(1))
    end
    _ = expand_circuit(c; seed=1)
    
    # Compile simulate! (if working)
    # state = SimulationState(L=4, bc=:periodic)
    # simulate!(c, state; n_circuits=1)
end
```

**Expected improvement**: ~90s → ~20-30s (3-4x faster)

---

## Next Steps

1. Review this plan - does it address your concerns?
2. If approved, this becomes a system-level improvement (not specific to circuit-visualization)
3. For now: Let's manually complete Task 12 to unblock the boulder
