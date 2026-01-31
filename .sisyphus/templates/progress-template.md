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

---

## Heartbeat Protocol

**CRITICAL**: This file MUST be updated at least every 5 minutes during active work.

Update triggers:
- Task start/completion
- Subtask start/completion
- File modification
- Every 5 minutes (heartbeat)

If no update for 10+ minutes → potential stuck state.
