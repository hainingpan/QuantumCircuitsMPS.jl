# === Circuit Expansion (Symbolic → Concrete) ===
# Converts Circuit's symbolic operations to concrete site lists with deterministic RNG sampling

using Random

"""
    ExpandedOp

Represents a concrete gate operation at specific sites for a specific timestep.

# Fields
- `step::Int`: Circuit timestep (1-indexed)
- `gate::AbstractGate`: The gate to apply
- `sites::Vector{Int}`: Physical sites for this operation
- `label::String`: Short label for visualization (e.g., "Rst", "Haar", "CZ")

# Usage
Produced by `expand_circuit` for visualization and manual execution.
"""
struct ExpandedOp
    step::Int
    gate::AbstractGate
    sites::Vector{Int}
    label::String
end

"""
    gate_label(gate::AbstractGate) -> String

Return a short visualization label for a gate type.

# Labels
- Reset → "Rst"
- HaarRandom → "Haar"
- Projection → "Prj"
- PauliX → "X"
- PauliY → "Y"
- PauliZ → "Z"
- CZ → "CZ"
- Other → Type name as string

# Examples
```julia
gate_label(Reset())       # Returns "Rst"
gate_label(HaarRandom())  # Returns "Haar"
gate_label(CZ())          # Returns "CZ"
```
"""
gate_label(::Reset) = "Rst"
gate_label(::HaarRandom) = "Haar"
gate_label(::Projection) = "Prj"
gate_label(::Measurement) = "Meas"
gate_label(::PauliX) = "X"
gate_label(::PauliY) = "Y"
gate_label(::PauliZ) = "Z"
gate_label(::CZ) = "CZ"
gate_label(::SpinSectorProjection) = "P(S≠2)"
gate_label(g::AbstractGate) = string(typeof(g))  # Fallback

"""
    validate_geometry(geo::AbstractGeometry)

Validate that a geometry type is supported for circuit expansion.

Phase 1 supports:
- `StaircaseRight`
- `StaircaseLeft`
- `SingleSite`
- `AdjacentPair`

# Throws
`ArgumentError` if geometry is not supported.
"""
function validate_geometry(geo::AbstractGeometry)
    if geo isa StaircaseRight
        # supported
    elseif geo isa StaircaseLeft
        # supported
    elseif geo isa SingleSite
        # supported
    elseif geo isa AdjacentPair
        # supported
    elseif geo isa Bricklayer
        # supported
    elseif geo isa AllSites
        # supported
    else
        throw(ArgumentError("Phase 1 does not support geometry type $(typeof(geo)). " *
                            "Supported: StaircaseRight, StaircaseLeft, SingleSite, AdjacentPair, Bricklayer, AllSites"))
    end
end

"""
    select_branch(rng::AbstractRNG, outcomes) -> Union{NamedTuple, Nothing}

Select a stochastic outcome using cumulative probability matching.

CRITICAL: This MUST match the RNG consumption pattern in `src/API/probabilistic.jl:56-68`.

# Algorithm
1. Draw `r = rand(rng)` ONCE (before checking)
2. Accumulate probabilities cumulatively
3. Return first outcome where `r < cumulative` (STRICT <, not <=)
4. If no outcome selected: return `nothing` (do-nothing branch)

# Arguments
- `rng`: Random number generator
- `outcomes`: Vector of NamedTuples with fields `(probability, gate, geometry)`

# Returns
- Selected outcome NamedTuple if `r` falls in any outcome's range
- `nothing` if "do nothing" branch is selected (r >= sum(probabilities))

# Examples
```julia
rng = MersenneTwister(42)
outcomes = [(probability=0.5, gate=Reset(), geometry=StaircaseRight(1)),
            (probability=0.3, gate=PauliX(), geometry=SingleSite(2))]

# If rand() = 0.4 → selects first outcome (0.4 < 0.5)
# If rand() = 0.7 → selects second outcome (0.7 < 0.8)
# If rand() = 0.9 → returns nothing (do-nothing branch)
```
"""
function select_branch(rng::AbstractRNG, outcomes)
    # CRITICAL: Draw BEFORE checking (matches apply_with_prob!)
    r = rand(rng)
    
    cumulative = 0.0
    for outcome in outcomes
        cumulative += outcome.probability
        if r < cumulative  # STRICT <, not <=
            return outcome
        end
    end
    
    # If we get here: "do nothing" branch selected
    return nothing
end

"""
    compute_sites_dispatch(geo::AbstractGeometry, gate::AbstractGate, step::Int, L::Int, bc::Symbol) -> Vector{Int}

Dispatch compute_sites with appropriate arguments based on geometry type.

For StaircaseRight/StaircaseLeft: requires gate parameter to determine support.
For SingleSite/AdjacentPair: gate parameter not needed.
"""
function compute_sites_dispatch(geo::AbstractGeometry, gate::AbstractGate, step::Int, L::Int, bc::Symbol)
    if geo isa StaircaseRight || geo isa StaircaseLeft
        return compute_sites(geo, step, L, bc, gate)
    else
        return compute_sites(geo, step, L, bc)
    end
end

"""
    expand_circuit_grouped(circuit::Circuit; n_steps::Int=1, seed::Int=0) -> Vector{Vector{Vector{ExpandedOp}}}

Expand a symbolic circuit to concrete gate operations, preserving operation groups.

Each `apply!` or `apply_with_prob!` call in the circuit definition becomes one group.
This grouping is essential for visualization: gates within the same group (e.g., all
pairs in a `Bricklayer`) can be rendered on the same row, while different groups
(e.g., a Bricklayer followed by AllSites measurements) get separate rows.

# Arguments
- `circuit::Circuit`: The circuit to expand (one time step)
- `n_steps::Int`: Number of times to repeat the circuit step (default: 1)
- `seed::Int`: RNG seed for stochastic branch selection (default: 0)

# Returns
- `Vector{Vector{Vector{ExpandedOp}}}`: steps → groups → ops.
  - Outer vector: one entry per timestep (length `n_steps`)
  - Middle vector: one entry per `apply!`/`apply_with_prob!` call that produced ops
  - Inner vector: concrete gate operations from that call

Groups with no operations (stochastic "do nothing" branches) are omitted.

# See Also
- [`expand_circuit`](@ref): Flat version (no grouping) for backward compatibility
"""
function expand_circuit_grouped(circuit::Circuit; n_steps::Int=1, seed::Int=0)
    # Validate all geometries upfront
    for op in circuit.operations
        if op.type == :deterministic
            validate_geometry(op.geometry)
        elseif op.type == :stochastic
            for outcome in op.outcomes
                validate_geometry(outcome.geometry)
            end
        end
    end
    
    # Reset staircase positions before expansion
    _reset_circuit_geometries!(circuit)
    rng = MersenneTwister(seed)
    result = Vector{Vector{Vector{ExpandedOp}}}()
    
    for step in 1:n_steps
        step_groups = Vector{Vector{ExpandedOp}}()
        
        for op in circuit.operations
            group_ops = ExpandedOp[]
            
            if op.type == :deterministic
                if is_compound_geometry(op.geometry)
                    elements = get_compound_elements(op.geometry, circuit.L, circuit.bc)
                    for sites in elements
                        push!(group_ops, ExpandedOp(step, op.gate, sites, gate_label(op.gate)))
                    end
                else
                    sites = compute_sites_dispatch(op.geometry, op.gate, step, circuit.L, circuit.bc)
                    push!(group_ops, ExpandedOp(step, op.gate, sites, gate_label(op.gate)))
                    if op.geometry isa AbstractStaircase
                        advance!(op.geometry, circuit.L, circuit.bc)
                    end
                end
                
             elseif op.type == :stochastic
                 has_compound = any(is_compound_geometry(o.geometry) for o in op.outcomes)
                 
                 if has_compound
                    for outcome in op.outcomes
                        outcome_ops = ExpandedOp[]

                        if is_compound_geometry(outcome.geometry)
                            elements = get_compound_elements(outcome.geometry, circuit.L, circuit.bc)
                            for sites in elements
                                r = rand(rng)
                                if r < outcome.probability
                                    push!(outcome_ops, ExpandedOp(step, outcome.gate, sites, gate_label(outcome.gate)))
                                end
                            end
                        else
                            r = rand(rng)
                            if r < outcome.probability
                                sites = compute_sites_dispatch(outcome.geometry, outcome.gate, step, circuit.L, circuit.bc)
                                push!(outcome_ops, ExpandedOp(step, outcome.gate, sites, gate_label(outcome.gate)))
                                if outcome.geometry isa AbstractStaircase
                                    advance!(outcome.geometry, circuit.L, circuit.bc)
                                end
                            end
                        end

                        if !isempty(outcome_ops)
                            push!(step_groups, outcome_ops)
                        end
                    end
                    continue
                else
                    selected = select_branch(rng, op.outcomes)
                    if selected !== nothing
                        sites = compute_sites_dispatch(selected.geometry, selected.gate, step, circuit.L, circuit.bc)
                        push!(group_ops, ExpandedOp(step, selected.gate, sites, gate_label(selected.gate)))
                        if selected.geometry isa AbstractStaircase
                            advance!(selected.geometry, circuit.L, circuit.bc)
                            sync_staircase_positions!(op.outcomes, selected.geometry)
                        end
                    end
                end
            end
            
            if !isempty(group_ops)
                push!(step_groups, group_ops)
            end
        end
        
        push!(result, step_groups)
    end
    
    return result
end

"""
    expand_circuit(circuit::Circuit; n_steps::Int=1, seed::Int=0) -> Vector{Vector{ExpandedOp}}

Expand a symbolic circuit to a flat list of concrete gate operations per timestep.

This is the backward-compatible flat version. For visualization, prefer
[`expand_circuit_grouped`](@ref) which preserves operation group boundaries.

# Arguments
- `circuit::Circuit`: The circuit to expand (one time step)
- `n_steps::Int`: Number of times to repeat the circuit step (default: 1)
- `seed::Int`: RNG seed for stochastic branch selection (default: 0)

# Returns
- `Vector{Vector{ExpandedOp}}`: Outer vector has length `n_steps`, inner vectors contain
  all operations for that timestep (flattened across groups). Inner vectors may be empty
  if "do nothing" is selected for all stochastic operations.

# See Also
- [`expand_circuit_grouped`](@ref): Grouped version for visualization
"""
function expand_circuit(circuit::Circuit; n_steps::Int=1, seed::Int=0)
    grouped = expand_circuit_grouped(circuit; n_steps=n_steps, seed=seed)
    return [reduce(vcat, groups; init=ExpandedOp[]) for groups in grouped]
end
