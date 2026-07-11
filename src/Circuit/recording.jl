"""
    RecordingContext

Context information passed to recording predicate functions during circuit execution.

# Fields
- `step_idx::Int`: Current step index (1 to n_steps passed to simulate!)
- `gate_idx::Int`: Cumulative element-slot count across all steps (never
  resets). Advances once per element slot regardless of stochastic outcome;
  `record!(c)` markers do NOT advance it.
- `op_idx::Int`: 1-based position of the current operation within
  `circuit.operations` (0 for the structural step-boundary evaluation)
- `element_idx::Int`: 1-based element index within the current operation
  (0 for step-boundary and marker evaluations)
- `gate_type::Any`: The gate applied at this slot (`nothing` for identity
  slots, marker evaluations, and the step-boundary evaluation)
- `is_step_boundary::Bool`: True only for the structural step-boundary
  evaluation after the op loop
- `at_mark::Bool`: True when this evaluation happens at a `record!(c)`
  marker pseudo-op
- `mark_index::Int`: 1-based ordinal of the marker among the circuit's
  markers (stable across steps; 0 when `at_mark == false`)

# Example
```julia
# Custom recording function
function my_recorder(ctx::RecordingContext)
    return ctx.gate_idx > 10 && ctx.is_step_boundary
end

# Record only at the second marker of each step
simulate!(circuit, state; record_when = ctx -> ctx.at_mark && ctx.mark_index == 2)
```
"""
struct RecordingContext
    step_idx::Int
    gate_idx::Int
    op_idx::Int
    element_idx::Int
    gate_type::Any
    is_step_boundary::Bool
    at_mark::Bool
    mark_index::Int
end

# Convenience 4-arg constructor (pre-v0.1 field set). op/element/mark fields
# default to their "not applicable" values (0 / false).
function RecordingContext(step_idx::Int, gate_idx::Int, gate_type, is_step_boundary::Bool)
    RecordingContext(step_idx, gate_idx, 0, 0, gate_type, is_step_boundary, false, 0)
end

"""
    every_n_gates(n::Int)

Create a recording predicate that triggers every `n` gates.

# Arguments
- `n::Int`: Record every n gates (based on cumulative gate_idx)

# Returns
Function that takes a `RecordingContext` and returns `Bool`

# Example
```julia
simulate!(state, circuit; record_when=every_n_gates(5))
```
"""
function every_n_gates(n::Int)
    return ctx -> ctx.gate_idx % n == 0
end

"""
    every_n_steps(n::Int)

Create a recording predicate that triggers every `n` steps at step boundaries.

Records once per n steps, only when `is_step_boundary` is true (after all gates 
in the step have been executed).

# Arguments
- `n::Int`: Record every n steps (based on step_idx)

# Returns
Function that takes a `RecordingContext` and returns `Bool`

# Example
```julia
simulate!(state, circuit; record_when=every_n_steps(2))
```
"""
function every_n_steps(n::Int)
    return ctx -> ctx.step_idx % n == 0 && ctx.is_step_boundary
end

# === Recording Evaluation Helpers (used by simulate!) ===

"""
    _evaluate_recording(record_when, ctx, step_idx, n_steps) -> (set_flag::Bool, record_now::Bool)

Evaluate recording criteria and return whether to set the recording flag and/or record immediately.

For compound geometries (called inside element loops), `:every_gate` triggers immediate recording.
For simple geometries, the caller handles the immediate recording after setting the flag.

Returns a tuple:
- `set_flag`: Whether to set `should_record_this_step = true`
- `record_now`: Whether to call `record!(state)` immediately
"""
function _evaluate_recording(record_when::Symbol, ctx::RecordingContext, step_idx::Int, n_steps::Int)
    is_step_boundary = ctx.is_step_boundary

    if record_when == :every_step && is_step_boundary
        return (true, false)
    elseif record_when == :every_gate
        return (false, true)  # Record immediately for compound geometry case
    elseif record_when == :final_only && is_step_boundary && step_idx == n_steps
        return (true, false)
    else
        return (false, false)
    end
end

function _evaluate_recording(record_when::Function, ctx::RecordingContext, step_idx::Int, n_steps::Int)
    if record_when(ctx)
        return (true, false)
    else
        return (false, false)
    end
end
