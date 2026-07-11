# === Circuit Expansion (Symbolic → Concrete) ===
# Converts Circuit's symbolic operations to concrete site lists using the
# SAME single-source stochastic selection as the engine (`select_outcome_index`
# in Circuit/execute.jl). Visualization and execution share ONE rule (v0.1).

"""
    ExpandedOp

Represents a concrete gate operation at specific sites for a specific timestep.

# Fields
- `step::Int`: Circuit timestep (1-indexed)
- `gate::Union{AbstractGate, Nothing}`: The gate to apply. `nothing` marks a
  `record!` marker pseudo-op (no gate, no sites — see `is_record_mark`).
- `sites::Vector{Int}`: Physical sites for this operation (empty for markers)
- `label::String`: Short label for visualization (e.g., "Rst", "Haar", "CZ";
  `"[R]"` / `"[R:names]"` for record markers)

# Usage
Produced by `expand_circuit` for visualization and manual execution.
"""
struct ExpandedOp
    step::Int
    gate::Union{AbstractGate, Nothing}
    sites::Vector{Int}
    label::String
end

"""
    is_record_mark(op::ExpandedOp) -> Bool

True when `op` is a `record!` marker pseudo-op (gate-less annotation produced
from a `(type=:record_mark, ...)` circuit operation). Marker ops carry no gate
(`gate === nothing`) and no sites; visualization renders them as a marker row
(`▽` in Unicode mode, `[R]` in ASCII mode).
"""
is_record_mark(op::ExpandedOp) = op.gate === nothing

# Build the marker ExpandedOp for a `(type=:record_mark, ...)` pseudo-op.
# Canonical label is "[R]" (ASCII-safe); named markers get "[R:name1,name2]".
function _record_mark_op(step::Int, op::NamedTuple)
    names = haskey(op, :names) ? op.names : ()
    label = isempty(names) ? "[R]" : "[R:" * join(names, ",") * "]"
    return ExpandedOp(step, nothing, Int[], label)
end

"""
    gate_label(gate::AbstractGate) -> String

Return a short visualization label for a gate type.

# Labels
- Reset → "Rst"
- HaarRandom → "Haar"
- RandomClifford → "Cl"
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
gate_label(::Measure) = "Meas"  # v0.1 feedback-capable measurement
gate_label(::PauliX) = "X"
gate_label(::PauliY) = "Y"
gate_label(::PauliZ) = "Z"
gate_label(::CZ) = "CZ"
gate_label(::SpinSectorProjection) = "P(S≠2)"
gate_label(::MatrixGate) = "U"
gate_label(::Rx) = "Rx"
gate_label(::Ry) = "Ry"
gate_label(::Rz) = "Rz"
gate_label(::Hadamard) = "H"
gate_label(::RandomClifford) = "Cl"
gate_label(g::AbstractGate) = string(typeof(g))  # Fallback

"""
    validate_geometry(geo::AbstractGeometry)

Validate that a geometry type is supported for circuit expansion.

Supported:
- `StaircaseRight`, `StaircaseLeft`
- `SingleSite`, `AdjacentPair`, `Sites`
- `Bricklayer`, `AllSites`, `EachSite`

# Throws
`ArgumentError` if geometry is not supported (e.g. `Pointer`, whose position
depends on runtime measurement outcomes and cannot be expanded statically).
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
    elseif geo isa EachSite
        # supported (v0.1 broadcast geometry)
    elseif geo isa Sites
        # supported (v0.1 set geometry; also ProductGate's canonical region)
    else
        throw(ArgumentError("Circuit expansion does not support geometry type $(typeof(geo)). " *
                            "Supported: StaircaseRight, StaircaseLeft, SingleSite, AdjacentPair, " *
                            "Bricklayer, AllSites, EachSite, Sites"))
    end
end

"""
    compute_sites_dispatch(geo::AbstractGeometry, gate::AbstractGate, step::Int, L::Int, bc::Symbol) -> Vector{Int}

Dispatch compute_sites with appropriate arguments based on geometry type.

For StaircaseRight/StaircaseLeft: requires gate parameter to determine support.
For SingleSite/AdjacentPair/Sites: gate parameter not needed.
"""
function compute_sites_dispatch(
        geo::AbstractGeometry, gate::AbstractGate, step::Int, L::Int, bc::Symbol)
    if geo isa StaircaseRight || geo isa StaircaseLeft
        return compute_sites(geo, step, L, bc, gate)
    else
        return compute_sites(geo, step, L, bc)
    end
end

"""
    expand_circuit_grouped(circuit::Circuit; n_steps::Int=1, seed::Int=0) -> Vector{Vector{Vector{ExpandedOp}}}

Expand a symbolic circuit to concrete gate operations, preserving operation groups.

Each `apply!` / `apply_with_prob!` / `record!` call in the circuit definition
becomes (at most) one group. This grouping is essential for visualization:
gates within the same group (e.g., all pairs in a `Bricklayer`) can be
rendered on the same row, while different groups (e.g., a Bricklayer followed
by AllSites measurements) get separate rows.

# Stochastic selection (v0.1 unified rule)
Stochastic operations are expanded with the ENGINE's single-source selection
function `select_outcome_index` — one scalar coin per element k = 1..K,
categorical selection among the outcomes, remainder `1 - Σp` = identity
(element omitted). This is the exact rule `simulate!` executes: expanding
with `seed=X` shows the same selections the engine makes when its
`:gates_spacetime` stream is seeded with `X`.

# Record markers
`(type=:record_mark, ...)` pseudo-ops (from `record!(c[, names...])`) become
gate-less marker `ExpandedOp`s (see [`is_record_mark`](@ref)) in their own
group. Markers consume no RNG. Unknown operation types are skipped (never an
error), keeping expansion forward-compatible.

# Arguments
- `circuit::Circuit`: The circuit to expand (one time step)
- `n_steps::Int`: Number of times to repeat the circuit step (default: 1)
- `seed::Int`: RNG seed for stochastic branch selection (default: 0)

# Returns
- `Vector{Vector{Vector{ExpandedOp}}}`: steps → groups → ops.
  - Outer vector: one entry per timestep (length `n_steps`)
  - Middle vector: one entry per circuit call that produced ops
  - Inner vector: concrete gate operations from that call

Groups with no operations (stochastic all-identity selections) are omitted.

# See Also
- [`expand_circuit`](@ref): Flat version (no grouping) for backward compatibility
- `select_outcome_index`: The shared engine/visualization selection rule
"""
function expand_circuit_grouped(circuit::Circuit; n_steps::Int = 1, seed::Int = 0)
    # Validate all geometries upfront
    for op in circuit.operations
        if op.type == :deterministic
            validate_geometry(op.geometry)
        elseif op.type == :stochastic
            for outcome in op.outcomes
                validate_geometry(outcome.geometry)
            end
        end
        # :record_mark and unknown op types carry no geometry — nothing to validate
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
                geo = op.geometry
                if is_broadcast(geo)
                    for sites in elements(geo, circuit.L, circuit.bc)
                        push!(group_ops, ExpandedOp(step, op.gate, sites, gate_label(op.gate)))
                    end
                else
                    sites = compute_sites_dispatch(
                        geo, op.gate, step, circuit.L, circuit.bc)
                    push!(group_ops, ExpandedOp(step, op.gate, sites, gate_label(op.gate)))
                    if geo isa AbstractStaircase
                        advance!(geo, circuit.L, circuit.bc)
                    end
                end

            elseif op.type == :stochastic
                # === v0.1 UNIFIED RULE — mirrors simulate!'s :stochastic branch ===
                # Selection is DELEGATED to select_outcome_index (Circuit/
                # execute.jl): per element k, ONE scalar coin, categorical
                # choice among outcomes, identity remainder applies nothing.
                outcomes = op.outcomes
                K = _op_element_count(op, circuit.L, circuit.bc)
                probs = Float64[Float64(o.probability) for o in outcomes]

                # Precompute broadcast element lists (fixed within the op);
                # set geometries resolve lazily at selection time because
                # staircase positions are mutable and support-aware.
                elem_lists = Union{Nothing, Vector{Vector{Int}}}[is_broadcast(o.geometry) ?
                                                                 elements(o.geometry, circuit.L, circuit.bc) :
                                                                 nothing
                                                                 for o in outcomes]

                for k in 1:K
                    sel = select_outcome_index(rng, probs)
                    sel == 0 && continue   # identity remainder: nothing rendered
                    outcome = outcomes[sel]
                    sites = elem_lists[sel] === nothing ?
                            compute_sites_dispatch(
                        outcome.geometry, outcome.gate, step, circuit.L, circuit.bc) :
                            elem_lists[sel][k]
                    push!(group_ops, ExpandedOp(step, outcome.gate, sites, gate_label(outcome.gate)))
                    # Advance only the SELECTED staircase (identity does not
                    # advance) — same as the engine.
                    if outcome.geometry isa AbstractStaircase
                        advance!(outcome.geometry, circuit.L, circuit.bc)
                        sync_staircase_positions!(outcomes, outcome.geometry)
                    end
                end

            elseif op.type == :record_mark
                # record!(c[, names...]) marker pseudo-op (Task 13): gate-less
                # annotation, own group, no RNG consumption.
                push!(group_ops, _record_mark_op(step, op))
            end
            # Unknown op types: skipped (forward-compatible, never an error)

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

Stochastic operations are expanded with the engine's shared selection function
`select_outcome_index` (v0.1 unified rule) — see
[`expand_circuit_grouped`](@ref) for details. Record markers appear as
gate-less pseudo-ops (see [`is_record_mark`](@ref)).

# Arguments
- `circuit::Circuit`: The circuit to expand (one time step)
- `n_steps::Int`: Number of times to repeat the circuit step (default: 1)
- `seed::Int`: RNG seed for stochastic branch selection (default: 0)

# Returns
- `Vector{Vector{ExpandedOp}}`: Outer vector has length `n_steps`, inner vectors contain
  all operations for that timestep (flattened across groups). Inner vectors may be empty
  if the identity remainder is selected for all stochastic elements.

# See Also
- [`expand_circuit_grouped`](@ref): Grouped version for visualization
"""
function expand_circuit(circuit::Circuit; n_steps::Int = 1, seed::Int = 0)
    grouped = expand_circuit_grouped(circuit; n_steps = n_steps, seed = seed)
    return [reduce(vcat, groups; init = ExpandedOp[]) for groups in grouped]
end
