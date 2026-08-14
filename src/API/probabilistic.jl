# Probabilistic Branching API — EAGER mode (v0.1 unified stochastic rule)
#
# `apply_with_prob!(state::SimulationState; outcomes)` is the imperative twin
# of the lazy builder form; both share the same selection/resolver logic.

@doc raw"""
    apply_with_prob!(state::SimulationState; outcomes)

Eagerly execute ONE stochastic operation on `state` under the v0.1 unified
stochastic rule — identical semantics to recording the same `outcomes` in a
`Circuit` and running one step of `simulate!`, but applied immediately.

Each outcome is a NamedTuple with fields:
- `probability` (required): a scalar `Real`, which broadcasts identically
  across every element. `probability` may also be an `AbstractVector{<:Real}`
  with one entry per geometry element (in `elements(geo, L, bc)` order),
  so each gate location gets its own probability. Scalar and vector
  outcomes may be freely mixed within one call.
- `gate::AbstractGate` (required)
- `geometry::AbstractGeometry` (required)

# Semantics (v0.1 unified stochastic rule)
Each outcome's geometry expands to elements (`elements(geo, L, bc)` for
broadcast geometries; set geometries are a single element); all outcomes must
expand to the SAME element count K. At element k, ``\sum p`` is the sum of every
outcome's probability value AT THAT ELEMENT — a scalar outcome contributes
the same value to every element, a vector outcome contributes its `k`-th
entry. For each element ``k = 1, \ldots, K``, exactly ONE scalar coin is drawn from
the `:gates_spacetime` stream — unchanged whether probabilities are scalar or
per-element vectors — and a categorical selection is made among the
outcomes via `select_outcome_index` (the engine's single source of truth);
the remainder ``1 - \sum p`` selects identity (nothing applied, staircases not
advanced). The winning outcome's gate is executed at its k-th element via
the uniform `execute!` protocol.

A selected staircase advances after application and other staircase
geometries in `outcomes` are synced to its position
(`sync_staircase_positions!`) — exactly as in `simulate!`. Unlike
`simulate!`, the eager form never resets geometry positions: the caller owns
staircase/Pointer state across calls.

# Call-time validation (all `ArgumentError`, thrown BEFORE any coin is drawn
# or the state is touched — the lazy form runs the same checks at build time)
- `outcomes` must be non-empty
- ``\sum p`` must be ``\le 1`` (tolerance `1e-10`)
- Equal-K: every outcome's geometry must expand to the same element count
  (the error names each outcome's geometry and K)
- Staircase/`Pointer` physics guard: if any outcome uses a staircase or
  `Pointer` geometry, ``\sum p`` must equal ``1`` (an identity remainder would silently
  stall the random walk — see the builder docstring for the CIPT rationale)
- The removed `rng=` keyword (or any other keyword) throws with a migration
  message: all coins come from `:gates_spacetime` in v0.1

# Event log
When the state was constructed with `log_events=true`, each applied gate
emits a `GateApplied` event. Eager calls happen outside an engine run, so
`step` and `op_idx` are the documented `0` sentinels; `element_idx` is the
real element index k.

# Example
```julia
apply_with_prob!(state;
    outcomes = [
        (probability=p, gate=Measure(:Z), geometry=AllSites())
    ]
)
```

# Example (``\sum p < 1``: remaining 0.3 = identity)
```julia
apply_with_prob!(state;
    outcomes = [
        (probability=0.3, gate=PauliX(), geometry=site),
        (probability=0.4, gate=PauliY(), geometry=site)
    ]
)
```

# See Also
- `apply_with_prob!(c::CircuitBuilder; outcomes)`: lazy form (records into a
  `Circuit` for `simulate!`)
- `apply!(state, gate, geometry)`: deterministic, unconditional application
"""
function apply_with_prob!(
        state::SimulationState;
        outcomes::Vector{<:NamedTuple{(:probability, :gate, :geometry)}},
        kwargs...
)
    # rng= kwarg was hard-removed in v0.1 — fail loudly, never ignore
    # (same migration error as the lazy builder form).
    if haskey(kwargs, :rng)
        throw(ArgumentError(
            "apply_with_prob! no longer accepts the rng= keyword (removed in v0.1.0). " *
            "All stochastic coins are drawn from the :gates_spacetime stream — " *
            "remove `rng=$(repr(kwargs[:rng]))` from the call."))
    end
    if !isempty(kwargs)
        throw(ArgumentError(
            "apply_with_prob! got unsupported keyword argument(s): " *
            join(keys(kwargs), ", ")))
    end

    # === CALL-TIME VALIDATION ===
    # Same checks the lazy builder runs at build time (Circuit/builder.jl);
    # all throw BEFORE any coin is drawn or the state is mutated.
    if isempty(outcomes)
        throw(ArgumentError("outcomes cannot be empty"))
    end

    # Scalar-only fast path: reproduce the legacy Σp <= 1 error message
    # exactly; vector/mixed calls are validated by the resolver below.
    is_pure_scalar_call = all(o -> o.probability isa Real, outcomes)
    if is_pure_scalar_call
        probs = Float64[Float64(o.probability) for o in outcomes]
        total_prob = sum(probs)
        if total_prob > 1.0 + 1e-10
            throw(ArgumentError("Probabilities sum to $total_prob (must be ≤ 1)"))
        end
    end

    # Equal-K rule via the SHARED helper (Circuit/draws.jl) — throws an
    # ArgumentError naming each outcome's geometry and K on violation.
    op = (type = :stochastic, rng = :gates_spacetime, outcomes = collect(outcomes))
    K = _op_element_count(op, state.L, state.bc)

    # Shared per-element probability-schedule resolver: validates shape,
    # finiteness, range, and per-column Σp<=1+1e-10 before any coin draw.
    schedule = resolve_probability_schedule(outcomes, K)

    # Staircase/Pointer guard: the walk must advance at every element
    # (caller-level; the shared resolver stays permissive of Σp<1).
    has_walker = any(o -> (o.geometry isa AbstractStaircase) || (o.geometry isa Pointer),
        outcomes)
    if has_walker
        for k in 1:K
            total_probability_at_k = sum(view(schedule, :, k))
            if !(abs(total_probability_at_k - 1.0) <= 1e-10)
                if is_pure_scalar_call
                    throw(ArgumentError(
                        "Stochastic operation with staircase/Pointer geometry requires Σp = 1 " *
                        "(got Σp = $total_probability_at_k). The identity remainder (probability $(1 - total_probability_at_k)) " *
                        "does not advance staircases, which would silently stall the random walk " *
                        "(CIPT physics requires the walk to advance every step). Either make the " *
                        "probabilities sum to 1 (e.g. add an explicit identity-like outcome) or use " *
                        "a non-walking geometry."))
                else
                    throw(ArgumentError(
                        "Stochastic operation with staircase/Pointer geometry requires Σp = 1 " *
                        "at element $k (got Σp = $total_probability_at_k). The identity " *
                        "remainder (probability $(1 - total_probability_at_k)) does not advance " *
                        "staircases, which would silently stall the random walk (CIPT physics " *
                        "requires the walk to advance at every element). Either make element " *
                        "$k's probabilities sum to 1 (e.g. add an explicit identity-like " *
                        "outcome) or use a non-walking geometry."))
                end
            end
        end
    end

    # === EXECUTION (mirrors simulate!'s :stochastic branch exactly) ===
    # All coins from :gates_spacetime; selection via the engine's
    # single-source-of-truth select_outcome_index (Circuit/execute.jl).
    actual_rng = get_rng(state.rng_registry, :gates_spacetime)

    # Precompute broadcast element lists (fixed within the call); set
    # geometries resolve lazily at selection time because staircase/Pointer
    # positions are mutable and support-aware.
    elem_lists = Union{Nothing, Vector{Vector{Int}}}[is_broadcast(o.geometry) ?
                                                     elements(o.geometry, state.L, state.bc) :
                                                     nothing
                                                     for o in outcomes]

    for k in 1:K
        # Per-element categorical selection: pass THIS element's resolved
        # schedule column (row i = outcome i's probability at element k)
        # to the SAME single-source selector every other execution path
        # uses — materialized as a Vector{Float64} copy, matching
        # select_outcome_index's Vector{Float64} signature exactly.
        probs_k = schedule[:, k]
        sel = select_outcome_index(actual_rng, probs_k)
        if sel != 0
            outcome = outcomes[sel]
            sites = elem_lists[sel] === nothing ?
                    compute_sites_dispatch(
                outcome.geometry, outcome.gate, 0, state.L, state.bc) :
                    elem_lists[sel][k]
            # Eager mode runs outside an engine step: step/op_idx = 0
            # sentinels (documented), element_idx = real k.
            set_event_context!(state, 0, 0, k)
            execute!(state, outcome.gate, sites)
            if state.event_log !== nothing
                log_event!(state, GateApplied(0, 0, k, gate_label(outcome.gate), sites))
            end
            # Advance only the SELECTED staircase; identity does NOT advance
            # (guarded against at call time by the staircase Σp<1 rule).
            if outcome.geometry isa AbstractStaircase
                advance!(outcome.geometry, state.L, state.bc)
                sync_staircase_positions!(outcomes, outcome.geometry)
            end
        end
        # Identity remainder: nothing applied; the coin was still consumed,
        # so :gates_spacetime consumption is data-independent (K coins/call).
    end

    return nothing
end
