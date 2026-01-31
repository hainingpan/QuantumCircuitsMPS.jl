"""
    RecordingContext

Context information passed to recording predicate functions during circuit execution.

# Fields
- `step_idx::Int`: Current circuit execution index (1 to n_circuits)
- `gate_idx::Int`: Cumulative gate count across all steps (never resets)
- `gate_type::Any`: The gate being applied
- `is_step_boundary::Bool`: True when at the last gate of the current step

# Example
```julia
# Custom recording function
function my_recorder(ctx::RecordingContext)
    return ctx.gate_idx > 10 && ctx.is_step_boundary
end
```
"""
struct RecordingContext
    step_idx::Int
    gate_idx::Int
    gate_type::Any
    is_step_boundary::Bool
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
