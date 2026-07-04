# === Fixed-draw contract helper (v0.1 RNG hygiene) ===
#
# `expected_draws` states the :gates_spacetime coin budget of a circuit under
# the v0.1 UNIFIED stochastic rule (equal-K, one scalar coin per element).
# It powers the draw-count invariant test: after `simulate!(circuit, state;
# n_steps=n)`, the :gates_spacetime stream must sit exactly
# `expected_draws(circuit, n)` scalar draws past its seed.

"""
    expected_draws(circuit::Circuit, n_steps::Int) -> Int

Fixed `:gates_spacetime` coin consumption of `circuit` over `n_steps` steps
under the v0.1 unified stochastic rule: each stochastic operation consumes
exactly ONE scalar coin per element per step (K coins, where K is the common
element count of its outcomes' geometries), independent of which outcomes are
selected. Deterministic operations consume none.

Set geometries (`SingleSite`, `AdjacentPair`, `Sites`, staircases, `Pointer`)
always count K = 1; broadcast geometries count `element_count(geo, L, bc)`.
Outcomes with unequal K violate the unified equal-K rule and make the coin
budget ill-defined — this throws an `ArgumentError` listing each outcome's K.

!!! note "Engine status"
    Since the v0.1 unified engine (Task 9), this count is EXACT for every
    operation: `simulate!` draws exactly one `:gates_spacetime` coin per
    element slot of every stochastic op, regardless of which outcomes are
    selected.

!!! note "ct_compat exemption"
    Under `RNGRegistry(Val(:ct_compat); ...)` the `:gates_spacetime` and
    `:gates_realization` streams are the SAME RNG object (CT.jl parity), so
    Haar draws interleave with coins and the fixed-draw invariant CANNOT
    hold. Detect such registries with `QuantumCircuitsMPS.is_aliased` and
    skip draw-count checks for them.
"""
function expected_draws(circuit::Circuit, n_steps::Int)
    n_steps >= 0 || throw(ArgumentError("n_steps must be >= 0, got $n_steps"))
    per_step = 0
    for op in circuit.operations
        op.type == :stochastic || continue
        per_step += _op_element_count(op, circuit.L, circuit.bc)
    end
    return n_steps * per_step
end

# Common element count K of a stochastic op's outcomes (equal-K rule).
function _op_element_count(op::NamedTuple, L::Int, bc::Symbol)
    Ks = [_outcome_element_count(o.geometry, L, bc) for o in op.outcomes]
    if !allequal(Ks)
        detail = join(
            ("$(typeof(o.geometry)) (K=$k)" for (o, k) in zip(op.outcomes, Ks)),
            ", ")
        throw(ArgumentError(
            "Unequal element counts across stochastic outcomes: $detail. " *
            "The v0.1 unified rule requires every outcome of a stochastic " *
            "operation to expand to the same number of elements K " *
            "(one :gates_spacetime coin per element)."))
    end
    return first(Ks)
end

# K for coin counting. Broadcast geometries expand via `elements`; set
# geometries are structurally ONE element — do NOT call `elements` on them,
# because staircase/Pointer site resolution is position-dependent (and can
# throw at OBC edges) while their K is 1 by definition.
function _outcome_element_count(geo::AbstractGeometry, L::Int, bc::Symbol)
    return is_broadcast(geo) ? element_count(geo, L, bc) : 1
end
