# === Circuit Execution Engine ===
# Executes Circuit objects on SimulationState with stochastic branch resolution

"""
    _reset_circuit_geometries!(circuit::Circuit)

Reset all staircase geometry positions to their initial values.
Called at the start of simulate! to ensure deterministic behavior.
"""
function _reset_circuit_geometries!(circuit::Circuit)
    for op in circuit.operations
        if op.type == :deterministic
            reset!(op.geometry)
        elseif op.type == :stochastic
            for outcome in op.outcomes
                reset!(outcome.geometry)
            end
        end
    end
end

"""
    simulate!(circuit::Circuit, state::SimulationState; n_steps::Int=1, record_when::Union{Symbol,Function}=:every_step)

Execute a circuit on a simulation state, applying gates and recording observables.

A `Circuit` represents ONE time step. This function runs that step `n_steps` times,
processing all operations in `circuit.operations` on each iteration.

# Arguments
- `circuit::Circuit`: The circuit to execute (symbolic operations)
- `state::SimulationState`: The state to modify in-place
- `n_steps::Int`: Number of times to execute the circuit step (default: 1)
- `record_when::Union{Symbol,Function}`: Controls when observables are recorded (default: `:every_step`)

# Recording Options
The `record_when` parameter accepts:
- `:every_step` (default): Record once per step, after the last gate
- `:every_gate`: Record after every gate execution
- `:final_only`: Record only after the final step completes
- Custom function `(ctx::RecordingContext) -> Bool`: Record when function returns true

# RecordingContext Fields
Custom recording functions receive a `RecordingContext` with:
- `step_idx::Int`: Current step index (1 to n_steps)
- `gate_idx::Int`: Cumulative gate count across all steps (never resets)
- `gate_type::Any`: The gate being applied
- `is_step_boundary::Bool`: True when at the last gate of the current step

# Examples
```julia
# Basic execution with 5 steps
circuit = Circuit(L=4, bc=:periodic) do c
    apply_with_prob!(c; rng=:gates_spacetime, outcomes=[
        (probability=0.5, gate=Reset(), geometry=StaircaseRight(1)),
        (probability=0.5, gate=HaarRandom(), geometry=StaircaseLeft(4))
    ])
end

rng = RNGRegistry(gates_spacetime=42, gates_realization=44, born_measurement=45)
state = SimulationState(L=4, bc=:periodic, rng=rng)
initialize!(state, ProductState(binary_int=1))
track!(state, :dw => DomainWall(order=1, i1_fn=() -> 1))

# Record after every step (default)
simulate!(circuit, state; n_steps=5)

# Record after every gate
simulate!(circuit, state; n_steps=5, record_when=:every_gate)

# Record only at the end
simulate!(circuit, state; n_steps=5, record_when=:final_only)

# Custom: record every 10 gates
simulate!(circuit, state; n_steps=5, record_when=every_n_gates(10))

# Custom: record every 2 steps
simulate!(circuit, state; n_steps=10, record_when=every_n_steps(2))

# Custom: record at specific gate
simulate!(circuit, state; n_steps=5, record_when=ctx -> ctx.gate_idx == 100)
```

# Migration from Old API
Breaking change: `n_circuits` keyword has been renamed to `n_steps`.

Old code (no longer works):
```julia
simulate!(circuit, state; n_circuits=100, record_initial=true, record_every=10)
```

New equivalent:
```julia
record!(state)  # Record initial state if desired
simulate!(circuit, state; n_steps=100, record_when=every_n_steps(10))
```

# RNG Alignment
RNG consumption MUST match `expand_circuit` exactly:
- For compound geometry stochastic ops: ONE `rand()` per element per outcome.
  Total draws = sum over outcomes of num_elements (or 1 for simple geometry outcomes)
- Selection logic: independent Bernoulli with STRICT `<` comparison per draw
- Same seed in state.rng_registry[op.rng] → same stochastic realization

# Validation
- Throws `ArgumentError` if `n_steps < 1`
- Throws `ArgumentError` for unknown symbol presets

# See Also
- `expand_circuit`: Visualize which gates will be applied
- `record!`: Manual observable recording
- `RecordingContext`: Context passed to custom recording functions
- `every_n_gates`, `every_n_steps`: Helper functions for common patterns
"""
function simulate!(circuit::Circuit, state::SimulationState;
                   n_steps::Int=1,
                   record_when::Union{Symbol,Function}=:every_step)
    # Validation
    n_steps >= 1 || throw(ArgumentError("n_steps must be >= 1, got $n_steps"))
    if record_when isa Symbol && record_when ∉ (:every_step, :every_gate, :final_only)
        throw(ArgumentError("Unknown record_when symbol: $record_when. Valid options: :every_step, :every_gate, :final_only"))
    end
    
    # Gate index tracks cumulative gates executed across ALL steps
    gate_idx = 0
    
    # Reset staircase positions once at the start
    _reset_circuit_geometries!(circuit)
    
    # Execute n_steps repetitions of the circuit
    for step in 1:n_steps
        should_record_this_step = false  # Flag for this step
        
        for (op_idx, op) in enumerate(circuit.operations)
            gate_executed = false
            current_gate = nothing
            
            if op.type == :deterministic
                if is_compound_geometry(op.geometry)
                    # Compound geometry: iterate over elements
                    elements = get_compound_elements(op.geometry, circuit.L, circuit.bc)
                    for sites in elements
                        execute_gate!(state, op.gate, sites)
                        gate_idx += 1
                        is_step_boundary = (op_idx == length(circuit.operations)) && (sites == elements[end])
                        ctx = RecordingContext(step, gate_idx, op.gate, is_step_boundary)
                        
                        # Evaluate recording
                        set_flag, record_now = _evaluate_recording(record_when, ctx, step, n_steps)
                        should_record_this_step |= set_flag
                        record_now && record!(state)
                    end
                    gate_executed = false  # Already handled above
                    current_gate = nothing
                else
                    # Simple geometry: existing path
                    sites = compute_sites_dispatch(op.geometry, op.gate, 1, circuit.L, circuit.bc)
                    execute_gate!(state, op.gate, sites)
                    # Advance staircase after deterministic application
                    if op.geometry isa AbstractStaircase
                        advance!(op.geometry, circuit.L, circuit.bc)
                    end
                    gate_executed = true
                    current_gate = op.gate
                end
                
            elseif op.type == :stochastic
                actual_rng = get_rng(state.rng_registry, op.rng)

                if any(is_compound_geometry(o.geometry) for o in op.outcomes)
                    # Compound stochastic: sample each outcome independently per element
                    for (outcome_idx, outcome) in enumerate(op.outcomes)
                        if is_compound_geometry(outcome.geometry)
                            elements = get_compound_elements(outcome.geometry, circuit.L, circuit.bc)

                            for sites in elements
                                r = rand(actual_rng)
                                if r < outcome.probability
                                    execute_gate!(state, outcome.gate, sites)
                                    gate_idx += 1
                                    is_step_boundary = (op_idx == length(circuit.operations)) &&
                                                       (outcome_idx == length(op.outcomes)) &&
                                                       (sites == elements[end])
                                    ctx = RecordingContext(step, gate_idx, outcome.gate, is_step_boundary)

                                    set_flag, record_now = _evaluate_recording(record_when, ctx, step, n_steps)
                                    should_record_this_step |= set_flag
                                    record_now && record!(state)
                                end
                            end
                        else
                            r = rand(actual_rng)
                            if r < outcome.probability
                                sites = compute_sites_dispatch(outcome.geometry, outcome.gate, 1, circuit.L, circuit.bc)
                                execute_gate!(state, outcome.gate, sites)
                                # Advance staircase if this non-compound outcome was selected
                                if outcome.geometry isa AbstractStaircase
                                    advance!(outcome.geometry, circuit.L, circuit.bc)
                                end
                                gate_idx += 1
                                is_step_boundary = (op_idx == length(circuit.operations)) &&
                                                   (outcome_idx == length(op.outcomes))
                                ctx = RecordingContext(step, gate_idx, outcome.gate, is_step_boundary)

                                set_flag, record_now = _evaluate_recording(record_when, ctx, step, n_steps)
                                should_record_this_step |= set_flag
                                record_now && record!(state)
                            end
                        end
                    end

                    is_step_boundary = (op_idx == length(circuit.operations))
                    if is_step_boundary && _should_record_at_step_boundary(record_when, step, n_steps)
                        should_record_this_step = true
                    end

                    gate_executed = false  # Already handled
                    current_gate = nothing
                else
                    # Simple stochastic: existing single-draw path
                    r = rand(actual_rng)
                    cumulative = 0.0
                    for outcome in op.outcomes
                        cumulative += outcome.probability
                        if r < cumulative
                            sites = compute_sites_dispatch(outcome.geometry, outcome.gate, 1, circuit.L, circuit.bc)
                            execute_gate!(state, outcome.gate, sites)
                            # Advance only the SELECTED staircase
                            if outcome.geometry isa AbstractStaircase
                                advance!(outcome.geometry, circuit.L, circuit.bc)
                                sync_staircase_positions!(op.outcomes, outcome.geometry)
                            end
                            gate_executed = true
                            current_gate = outcome.gate
                            break
                        end
                    end
                end
            end
            
            # Only process recording logic if a gate was actually executed
            if gate_executed
                gate_idx += 1
                is_step_boundary = (op_idx == length(circuit.operations))
                ctx = RecordingContext(step, gate_idx, current_gate, is_step_boundary)
                
                # Evaluate recording criteria
                set_flag, record_now = _evaluate_recording(record_when, ctx, step, n_steps)
                should_record_this_step |= set_flag
                record_now && record!(state)
            end
        end
        
        # Record after this step completes (flag set by :every_step, :final_only, or custom function)
        if should_record_this_step
            record!(state)
        end
    end
    
    return nothing
end

"""
    execute_gate!(state::SimulationState, gate::AbstractGate, sites::Vector{Int})

Apply a gate to specific sites, handling special cases like Reset.

# Special Cases
- **Reset**: Must use `SingleSite` wrapper because Reset's `build_operator` throws for Vector{Int}.
  This triggers the specialized `_apply_dispatch!(state, ::Reset, ::SingleSite)` method.
- **All other gates**: Use `apply!(state, gate, sites)` directly.

# Arguments
- `state`: The simulation state to modify
- `gate`: The gate to apply
- `sites`: Physical site indices for this operation

# Internal Implementation Detail
This function is part of the circuit execution engine and should not be called directly
by users. Use `simulate!` or the imperative `apply!` API instead.
"""
function execute_gate!(state::SimulationState, gate::AbstractGate, sites::Vector{Int})
    if gate isa Reset
        # Reset requires SingleSite wrapper to trigger correct dispatch
        # (Reset's build_operator(gate, ::Vector{Int}) throws error)
        site = sites[1]  # Reset is always single-site
        apply!(state, gate, SingleSite(site))
    elseif gate isa Measurement
        # Measurement requires SingleSite wrapper (like Reset)
        site = sites[1]  # Measurement is always single-site
        apply!(state, gate, SingleSite(site))
    else
        # Normal gates use sites vector directly
        apply!(state, gate, sites)
    end
end

# Note: compute_sites_dispatch is defined in expand.jl (shared helper)
