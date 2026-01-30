# === Circuit Execution Engine ===
# Executes Circuit objects on SimulationState with stochastic branch resolution

"""
    simulate!(circuit::Circuit, state::SimulationState; n_circuits::Int=1, record_when::Union{Symbol,Function}=:every_step)

Execute a circuit on a simulation state, applying gates and recording observables.

This function runs the circuit `n_circuits` times, with each run executing all `circuit.n_steps` timesteps.
For each timestep, all operations in `circuit.operations` are processed in order.

# Arguments
- `circuit::Circuit`: The circuit to execute (symbolic operations)
- `state::SimulationState`: The state to modify in-place
- `n_circuits::Int`: Number of times to execute the full circuit (default: 1)
- `record_when::Union{Symbol,Function}`: Controls when observables are recorded (default: `:every_step`)

# Recording Options
The `record_when` parameter accepts:
- `:every_step` (default): Record once per circuit, after the last gate of the last timestep
- `:every_gate`: Record after every gate execution
- `:final_only`: Record only after the final circuit completes
- Custom function `(ctx::RecordingContext) -> Bool`: Record when function returns true

# RecordingContext Fields
Custom recording functions receive a `RecordingContext` with:
- `step_idx::Int`: Current circuit execution index (1 to n_circuits)  
- `gate_idx::Int`: Cumulative gate count across all circuits (never resets)
- `gate_type::Any`: The gate being applied
- `is_step_boundary::Bool`: True when at the last gate of the current timestep

# Examples
```julia
# Basic execution with 5 runs
circuit = Circuit(L=4, bc=:periodic, n_steps=10) do c
    apply_with_prob!(c; rng=:ctrl, outcomes=[
        (probability=0.5, gate=Reset(), geometry=StaircaseRight(1)),
        (probability=0.5, gate=HaarRandom(), geometry=StaircaseLeft(4))
    ])
end

rng = RNGRegistry(ctrl=42, proj=43, haar=44, born=45)
state = SimulationState(L=4, bc=:periodic, rng=rng)
initialize!(state, ProductState(x0=1//16))
track!(state, :dw => DomainWall(order=1, i1_fn=() -> 1))

# Record after every circuit (default)
simulate!(circuit, state; n_circuits=5)

# Record after every gate
simulate!(circuit, state; n_circuits=5, record_when=:every_gate)

# Record only at the end
simulate!(circuit, state; n_circuits=5, record_when=:final_only)

# Custom: record every 10 gates
simulate!(circuit, state; n_circuits=5, record_when=every_n_gates(10))

# Custom: record at specific gate
simulate!(circuit, state; n_circuits=5, record_when=ctx -> ctx.gate_idx == 100)
```

# RNG Alignment
RNG consumption MUST match `expand_circuit` exactly:
- For each stochastic operation: consume exactly ONE `rand()` call
- Selection logic: cumulative probability with STRICT `<` comparison
- Same seed in state.rng_registry[op.rng] → same branch selection

# Validation
- Throws `ArgumentError` if `n_circuits < 1`
- Throws `ArgumentError` for unknown symbol presets

# See Also
- `expand_circuit`: Visualize which gates will be applied
- `record!`: Manual observable recording
- `RecordingContext`: Context passed to custom recording functions
- `every_n_gates`, `every_n_steps`: Helper functions for common patterns
"""
function simulate!(circuit::Circuit, state::SimulationState;
                   n_circuits::Int=1,
                   record_when::Union{Symbol,Function}=:every_step)
    # Validation
    n_circuits >= 1 || throw(ArgumentError("n_circuits must be >= 1, got $n_circuits"))
    if record_when isa Symbol && record_when ∉ (:every_step, :every_gate, :final_only)
        throw(ArgumentError("Unknown record_when symbol: $record_when. Valid options: :every_step, :every_gate, :final_only"))
    end
    
    # Gate index tracks cumulative gates executed across ALL circuits
    gate_idx = 0
    
    # Execute n_circuits repetitions
    for circuit_idx in 1:n_circuits
        should_record_this_step = false  # Flag for this circuit
        
        # Execute all n_steps of this circuit
        for step in 1:circuit.n_steps
            for (op_idx, op) in enumerate(circuit.operations)
                gate_executed = false
                current_gate = nothing
                
                if op.type == :deterministic
                    # Compute sites and apply gate
                    sites = compute_sites_dispatch(op.geometry, op.gate, step, circuit.L, circuit.bc)
                    execute_gate!(state, op.gate, sites)
                    gate_executed = true
                    current_gate = op.gate
                    
                elseif op.type == :stochastic
                    # Consume ONE RNG draw (matches expand_circuit and apply_with_prob!)
                    actual_rng = get_rng(state.rng_registry, op.rng)
                    r = rand(actual_rng)
                    
                    # Select branch using cumulative probability matching
                    cumulative = 0.0
                    for outcome in op.outcomes
                        cumulative += outcome.probability
                        if r < cumulative  # STRICT < (matches probabilistic.jl:64)
                            # Branch selected - compute sites and apply
                            sites = compute_sites_dispatch(outcome.geometry, outcome.gate, step, circuit.L, circuit.bc)
                            execute_gate!(state, outcome.gate, sites)
                            gate_executed = true
                            current_gate = outcome.gate
                            break
                        end
                    end
                    # If no break: "do nothing" branch (r >= sum(probabilities))
                    # DO NOT increment gate_idx or create RecordingContext for "do nothing"
                end
                
                # Only process recording logic if a gate was actually executed
                if gate_executed
                    gate_idx += 1
                    is_step_boundary = (step == circuit.n_steps) && (op_idx == length(circuit.operations))
                    ctx = RecordingContext(circuit_idx, gate_idx, current_gate, is_step_boundary)
                    
                    # Evaluate record_when and set flag
                    if record_when isa Symbol
                        if record_when == :every_step && is_step_boundary
                            should_record_this_step = true
                        elseif record_when == :every_gate
                            should_record_this_step = true
                        elseif record_when == :final_only && is_step_boundary && circuit_idx == n_circuits
                            should_record_this_step = true
                        end
                    elseif record_when isa Function
                        if record_when(ctx)
                            should_record_this_step = true
                        end
                    end
                    
                    # For :every_gate, record immediately after each gate
                    if record_when == :every_gate && should_record_this_step
                        record!(state)
                        should_record_this_step = false  # Reset flag after recording
                    end
                end
            end
        end
        
        # Record after this circuit completes (for non-every_gate modes)
        if should_record_this_step && record_when != :every_gate
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
    else
        # Normal gates use sites vector directly
        apply!(state, gate, sites)
    end
end

# Note: compute_sites_dispatch is defined in expand.jl (shared helper)
