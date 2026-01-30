# === Circuit Execution Engine ===
# Executes Circuit objects on SimulationState with stochastic branch resolution

"""
    simulate!(circuit::Circuit, state::SimulationState; n_circuits::Int=1, record_initial::Bool=true, record_every::Int=1)

Execute a circuit on a simulation state, applying gates and recording observables.

This function runs the circuit `n_circuits` times, with each run executing all `circuit.n_steps` timesteps.
For each timestep, all operations in `circuit.operations` are processed in order.

# Arguments
- `circuit::Circuit`: The circuit to execute (symbolic operations)
- `state::SimulationState`: The state to modify in-place
- `n_circuits::Int`: Number of times to execute the full circuit (default: 1)
- `record_initial::Bool`: Whether to record observables before any execution (default: true)
- `record_every::Int`: Record every Nth circuit (default: 1 = record after every circuit)

# Recording Contract
Observables are recorded at these points:
1. **Initial**: If `record_initial == true`, record before any gate execution
2. **Periodic**: After each circuit where `(circuit_idx - 1) % record_every == 0`
3. **Final**: Always record after the final circuit (circuit_idx == n_circuits)

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

simulate!(circuit, state; n_circuits=5)
# Result: 6 records (1 initial + 5 circuits)

# Sparse recording
simulate!(circuit, state; n_circuits=10, record_every=2)
# Result: 6 records (1 initial + circuits 1,3,5,7,9 + final 10)
```

# RNG Alignment
RNG consumption MUST match `expand_circuit` exactly:
- For each stochastic operation: consume exactly ONE `rand()` call
- Selection logic: cumulative probability with STRICT `<` comparison
- Same seed in state.rng_registry[op.rng] → same branch selection

# Validation
- Throws `ArgumentError` if `n_circuits < 1`

# See Also
- `expand_circuit`: Visualize which gates will be applied
- `record!`: Manual observable recording
"""
function simulate!(circuit::Circuit, state::SimulationState;
                   n_circuits::Int=1,
                   record_initial::Bool=true,
                   record_every::Int=1)
    # Validation
    n_circuits >= 1 || throw(ArgumentError("n_circuits must be >= 1, got $n_circuits"))
    
    # Record initial state if requested
    if record_initial
        record!(state)
    end
    
    # Execute n_circuits repetitions
    for circuit_idx in 1:n_circuits
        # Execute all n_steps of this circuit
        for step in 1:circuit.n_steps
            for op in circuit.operations
                if op.type == :deterministic
                    # Compute sites and apply gate
                    sites = compute_sites_dispatch(op.geometry, op.gate, step, circuit.L, circuit.bc)
                    execute_gate!(state, op.gate, sites)
                    
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
                            break
                        end
                    end
                    # If no break: "do nothing" branch (r >= sum(probabilities))
                end
            end
        end
        
        # Record after this circuit (respecting record_every)
        should_record = (circuit_idx == n_circuits) ||  # Always record final
                        ((circuit_idx - 1) % record_every == 0)
        if should_record
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
