# Task 1: Micro-Steps for Extending simulate!

## Overview
This breaks Task 1 into atomic steps that each take < 2 minutes to execute.
Each step is self-contained with exact line numbers, copy-pasteable code, and immediate verification.

---

## Pre-Requisite Check (30 seconds)

```bash
julia --project -e 'using QuantumCircuitsMPS; println("Package loads: OK")'
```
Expected: "Package loads: OK"

---

## STEP 1.1: Add `is_compound_geometry` helper (1 min)

**File**: `src/Circuit/execute.jl`
**Location**: Insert at line 1, before the comment block

**Insert this code**:
```julia
# === Compound Geometry Helpers ===

"""Check if geometry requires element-by-element iteration."""
is_compound_geometry(::Bricklayer) = true
is_compound_geometry(::AllSites) = true
is_compound_geometry(::AbstractGeometry) = false
```

**Verification**:
```bash
julia --project -e 'using QuantumCircuitsMPS; println(QuantumCircuitsMPS.is_compound_geometry(Bricklayer(:odd)))'
```
Expected: `true`

---

## STEP 1.2: Add `get_compound_elements` helper (2 min)

**File**: `src/Circuit/execute.jl`
**Location**: Immediately after `is_compound_geometry` (before the `# === Circuit Execution Engine ===` comment)

**Insert this code**:
```julia
"""
Get elements for compound geometry iteration.
Returns Vector{Vector{Int}} - each inner vector is sites for one gate application.
"""
function get_compound_elements(geo::Bricklayer, L::Int, bc::Symbol)
    pairs = Tuple{Int,Int}[]
    if geo.parity == :odd
        for i in 1:2:L-1
            push!(pairs, (i, i+1))
        end
    else
        for i in 2:2:L-1
            push!(pairs, (i, i+1))
        end
        if bc == :periodic
            push!(pairs, (L, 1))
        end
    end
    return [[p1, p2] for (p1, p2) in pairs]
end

function get_compound_elements(geo::AllSites, L::Int, bc::Symbol)
    return [[site] for site in 1:L]
end
```

**Verification**:
```bash
julia --project -e '
using QuantumCircuitsMPS
elems = QuantumCircuitsMPS.get_compound_elements(Bricklayer(:odd), 4, :periodic)
println("Odd pairs L=4: ", elems)
@assert elems == [[1,2], [3,4]] "Expected [[1,2], [3,4]]"
println("OK")
'
```
Expected: `Odd pairs L=4: [[1, 2], [3, 4]]` then `OK`

---

## STEP 1.3: Modify deterministic path for compound geometry (3 min)

**File**: `src/Circuit/execute.jl`
**Location**: Lines 118-124 (the `if op.type == :deterministic` block)

**Current code** (lines 118-124):
```julia
                if op.type == :deterministic
                    # Compute sites and apply gate
                    sites = compute_sites_dispatch(op.geometry, op.gate, step, circuit.L, circuit.bc)
                    execute_gate!(state, op.gate, sites)
                    gate_executed = true
                    current_gate = op.gate
```

**Replace with**:
```julia
                if op.type == :deterministic
                    if is_compound_geometry(op.geometry)
                        # Compound geometry: iterate over elements
                        elements = get_compound_elements(op.geometry, circuit.L, circuit.bc)
                        for sites in elements
                            execute_gate!(state, op.gate, sites)
                            gate_idx += 1
                            is_step_boundary = (step == circuit.n_steps) && (op_idx == length(circuit.operations)) && (sites == elements[end])
                            ctx = RecordingContext(circuit_idx, gate_idx, op.gate, is_step_boundary)
                            
                            # Evaluate recording
                            if record_when isa Symbol
                                if record_when == :every_step && is_step_boundary
                                    should_record_this_step = true
                                elseif record_when == :every_gate
                                    record!(state)
                                elseif record_when == :final_only && is_step_boundary && circuit_idx == n_circuits
                                    should_record_this_step = true
                                end
                            elseif record_when isa Function && record_when(ctx)
                                should_record_this_step = true
                            end
                        end
                        gate_executed = false  # Already handled above
                        current_gate = nothing
                    else
                        # Simple geometry: existing path
                        sites = compute_sites_dispatch(op.geometry, op.gate, step, circuit.L, circuit.bc)
                        execute_gate!(state, op.gate, sites)
                        gate_executed = true
                        current_gate = op.gate
                    end
```

**Verification**:
```bash
julia --project -e '
using QuantumCircuitsMPS
circuit = Circuit(L=4, bc=:periodic, n_steps=1) do c
    apply!(c, HaarRandom(), Bricklayer(:odd))
end
state = SimulationState(L=4, bc=:periodic, rng=RNGRegistry(ctrl=42, born=1, haar=2, proj=3))
initialize!(state, ProductState(x0=0//1))
simulate!(circuit, state; n_circuits=1)
println("Bricklayer deterministic: OK")
'
```
Expected: `Bricklayer deterministic: OK`

---

## STEP 1.4: Modify stochastic path for compound geometry (4 min)

**File**: `src/Circuit/execute.jl`
**Location**: Lines 125-145 (the `elseif op.type == :stochastic` block)

**Current code** (lines 125-145):
```julia
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
```

**Replace with**:
```julia
                elseif op.type == :stochastic
                    actual_rng = get_rng(state.rng_registry, op.rng)
                    
                    # Check if ANY outcome has compound geometry
                    has_compound = any(is_compound_geometry(o.geometry) for o in op.outcomes)
                    
                    if has_compound
                        # Compound stochastic: per-element independent RNG draws
                        # Use first compound geometry to determine elements
                        compound_geo = first(o.geometry for o in op.outcomes if is_compound_geometry(o.geometry))
                        elements = get_compound_elements(compound_geo, circuit.L, circuit.bc)
                        
                        for sites in elements
                            r = rand(actual_rng)  # Independent draw per element
                            cumulative = 0.0
                            for outcome in op.outcomes
                                cumulative += outcome.probability
                                if r < cumulative
                                    execute_gate!(state, outcome.gate, sites)
                                    gate_idx += 1
                                    is_step_boundary = (step == circuit.n_steps) && (op_idx == length(circuit.operations)) && (sites == elements[end])
                                    ctx = RecordingContext(circuit_idx, gate_idx, outcome.gate, is_step_boundary)
                                    
                                    if record_when isa Symbol
                                        if record_when == :every_step && is_step_boundary
                                            should_record_this_step = true
                                        elseif record_when == :every_gate
                                            record!(state)
                                        elseif record_when == :final_only && is_step_boundary && circuit_idx == n_circuits
                                            should_record_this_step = true
                                        end
                                    elseif record_when isa Function && record_when(ctx)
                                        should_record_this_step = true
                                    end
                                    break
                                end
                            end
                            # If no break: "do nothing" for this element
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
                                sites = compute_sites_dispatch(outcome.geometry, outcome.gate, step, circuit.L, circuit.bc)
                                execute_gate!(state, outcome.gate, sites)
                                gate_executed = true
                                current_gate = outcome.gate
                                break
                            end
                        end
                    end
                end
```

**Verification**:
```bash
julia --project -e '
using QuantumCircuitsMPS
circuit = Circuit(L=4, bc=:periodic, n_steps=1) do c
    apply!(c, HaarRandom(), Bricklayer(:odd))
    apply_with_prob!(c; rng=:ctrl, outcomes=[
        (probability=0.5, gate=Measurement(:Z), geometry=AllSites())
    ])
end
state = SimulationState(L=4, bc=:periodic, rng=RNGRegistry(ctrl=42, born=1, haar=2, proj=3))
initialize!(state, ProductState(x0=0//1))
simulate!(circuit, state; n_circuits=3)
println("Stochastic AllSites: OK")
'
```
Expected: `Stochastic AllSites: OK`

---

## STEP 1.5: Add Measurement handling to execute_gate! (1 min)

**File**: `src/Circuit/execute.jl`
**Location**: Inside `execute_gate!` function (around line 205-215)

**Current code**:
```julia
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
```

**Replace with**:
```julia
function execute_gate!(state::SimulationState, gate::AbstractGate, sites::Vector{Int})
    if gate isa Reset
        # Reset requires SingleSite wrapper to trigger correct dispatch
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
```

**Verification**:
```bash
julia --project -e '
using QuantumCircuitsMPS
circuit = Circuit(L=4, bc=:periodic, n_steps=1) do c
    apply!(c, Measurement(:Z), AllSites())
end
state = SimulationState(L=4, bc=:periodic, rng=RNGRegistry(ctrl=42, born=1, haar=2, proj=3))
initialize!(state, ProductState(x0=0//1))
simulate!(circuit, state; n_circuits=1)
println("Measurement in execute_gate!: OK")
'
```
Expected: `Measurement in execute_gate!: OK`

---

## STEP 1.6: Final Integration Test (1 min)

```bash
julia --project -e '
using QuantumCircuitsMPS

# Full MIPT-style circuit
circuit = Circuit(L=4, bc=:periodic, n_steps=1) do c
    apply!(c, HaarRandom(), Bricklayer(:odd))
    apply!(c, HaarRandom(), Bricklayer(:even))
    apply_with_prob!(c; rng=:ctrl, outcomes=[
        (probability=0.3, gate=Measurement(:Z), geometry=AllSites())
    ])
end

state = SimulationState(L=4, bc=:periodic, rng=RNGRegistry(ctrl=42, born=1, haar=2, proj=3))
initialize!(state, ProductState(x0=0//1))
track!(state, :entropy => EntanglementEntropy(; cut=2))
simulate!(circuit, state; n_circuits=10, record_when=:every_step)

ev = state.observables[:entropy]
println("Recorded $(length(ev)) entropy values")
@assert length(ev) == 10 "Expected 10, got $(length(ev))"
@assert all(e -> e >= 0, ev) "Negative entropy!"
println("TASK 1 COMPLETE: All tests pass!")
'
```
Expected: `TASK 1 COMPLETE: All tests pass!`

---

## STEP 1.7: Run Full Test Suite (2 min)

```bash
julia --project -e 'using Pkg; Pkg.test()'
```
Expected: All 212+ tests pass

---

## Summary

| Step | Description | Time |
|------|-------------|------|
| 1.1 | Add `is_compound_geometry` | 1 min |
| 1.2 | Add `get_compound_elements` | 2 min |
| 1.3 | Modify deterministic path | 3 min |
| 1.4 | Modify stochastic path | 4 min |
| 1.5 | Add Measurement to execute_gate! | 1 min |
| 1.6 | Integration test | 1 min |
| 1.7 | Full test suite | 2 min |
| **Total** | | **~14 min** |

Each step has:
- Exact file location
- Copy-pasteable code
- Immediate verification command
- Expected output

**If any step fails**: Stop, diagnose, fix before proceeding.
