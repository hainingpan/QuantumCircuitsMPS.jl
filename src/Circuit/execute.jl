# === Circuit Execution Engine (v0.1 unified stochastic rule) ===
# Executes Circuit objects on SimulationState with the SINGLE-SOURCE
# per-element categorical selection rule (see `select_outcome_index`).

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
    select_outcome_index(rng::AbstractRNG, probs::Vector{Float64}) -> Int

SINGLE SOURCE OF TRUTH for the v0.1 unified stochastic rule's categorical
selection. Draws exactly ONE scalar coin from `rng` and returns the 1-based
index of the selected outcome, or `0` for the identity remainder
(`r >= Σp`).

Semantics (bit-identical to `test/reference_rule.jl`'s `reference_select`
for a single element):
- one scalar `rand(rng)` per call — never vectorized draws
- cumulative walk over `probs` with strict `<`
- cumsum snapping: when `abs(sum(probs) - 1) <= 1e-10`, the LAST cumulative
  boundary is snapped to exactly `1.0`, so float dust in Σp cannot leak
  spurious identity selections

`expand.jl`'s visualization path (Task 15) also delegates to this function —
there is exactly one categorical-selection implementation in the package.
"""
function select_outcome_index(rng::AbstractRNG, probs::Vector{Float64})
    # SCALAR-DRAW CONTRACT: exactly one scalar coin per element
    r = rand(rng)
    n = length(probs)
    snap = abs(sum(probs) - 1.0) <= 1e-10
    cumulative = 0.0
    for i in 1:n
        cumulative += probs[i]
        boundary = (snap && i == n) ? 1.0 : cumulative
        if r < boundary   # strict <
            return i
        end
    end
    return 0   # identity remainder
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

# Unified stochastic rule (v0.1)
Every stochastic operation (`apply_with_prob!`) is executed as follows:
1. All outcomes expand to the SAME number of elements K (validated at build
   time; broadcast geometries expand via `elements(geo, L, bc)`, set
   geometries are a single element).
2. For each element k = 1..K: exactly ONE scalar coin is drawn from the
   `:gates_spacetime` stream and a categorical selection is made among the
   outcomes via `select_outcome_index` (remainder `1 - Σp` = identity).
3. The winning outcome's gate is executed at its k-th element; identity
   applies nothing (and does NOT advance staircases).

Coin consumption is therefore data-independent: K draws per stochastic op
per step, always — see `expected_draws`.

# Recording Options
The `record_when` parameter accepts:
- `:every_step` (default): Record once per step, after the last operation.
  This fires STRUCTURALLY every step — even when every stochastic op selects
  the identity ("do nothing") branch.
- `:every_gate`: Record after every actual gate execution
- `:final_only`: Record only after the final step completes
- `:marks`: Record exactly at the circuit's `record!(c[, names...])` marker
  positions, in the op stream (NOT at the structural step boundary). A
  circuit with M markers yields exactly `M * n_steps` records per (matching)
  observable, deterministically — independent of stochastic outcomes.
  Selective markers (`record!(c, :entropy)`) grow only the named
  observables' vectors. Requires the circuit to contain markers
  (`ArgumentError` otherwise).
- Custom function `(ctx::RecordingContext) -> Bool`: evaluated once per
  element slot (with `is_step_boundary=false`), once per marker (with
  `at_mark=true`, `mark_index` set), and once at the structural end of each
  step (with `is_step_boundary=true`, `gate_type=nothing`); if any
  evaluation returns true, ONE record is taken at the end of the step.

# Marker/policy conflict (ArgumentError)
If the circuit contains `record!(c)` markers, `record_when` MUST be `:marks`
or a custom predicate. Passing (or defaulting to) `:every_step`,
`:every_gate`, or `:final_only` throws an `ArgumentError` — those policies
would silently ignore the markers.

# RecordingContext Fields
Custom recording functions receive a `RecordingContext` with:
- `step_idx::Int`: Current step index (1 to n_steps)
- `gate_idx::Int`: Cumulative element-slot count across all steps (never
  resets). Advances once per element slot REGARDLESS of the stochastic
  outcome (identity included), so gate_idx-based recording schedules are
  trajectory-independent. Markers do NOT advance it.
- `op_idx::Int`: Position of the current op in `circuit.operations`
  (0 for the step-boundary evaluation)
- `element_idx::Int`: Element index within the current op (0 for
  step-boundary and marker evaluations)
- `gate_type::Any`: The gate applied at this slot (`nothing` for identity
  slots, marker evaluations, and the structural step-boundary evaluation)
- `is_step_boundary::Bool`: True only for the structural step-boundary
  evaluation after the op loop
- `at_mark::Bool` / `mark_index::Int`: Marker evaluations carry
  `at_mark=true` and the marker's 1-based ordinal among the circuit's
  markers (0/false everywhere else)

# Examples
```julia
# Basic execution with 5 steps
circuit = Circuit(L=4, bc=:periodic) do c
    apply_with_prob!(c; outcomes=[
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

# Custom: record every 10 element slots
simulate!(circuit, state; n_steps=5, record_when=every_n_gates(10))

# Custom: record every 2 steps
simulate!(circuit, state; n_steps=10, record_when=every_n_steps(2))
```

# RNG Contract
- All stochastic coins come from `:gates_spacetime` (the builder no longer
  accepts an `rng=` keyword).
- Scalar draws only; element order = documented enumeration order of the
  outcome geometries (`elements`).
- Consumption is data-independent: `expected_draws(circuit, n_steps)` coins.

# Thread safety
A `Circuit` holding staircase/Pointer geometries is MUTABLE (positions
advance during `simulate!`). For per-trajectory parallelism use
`copy(circuit)` (a `deepcopy` preserving intra-circuit geometry aliasing)
so each trajectory owns private geometry state:

```julia
Threads.@threads for seed in seeds
    c = copy(circuit)
    st = SimulationState(...; rng=RNGRegistry(gates_spacetime=seed, ...))
    initialize!(st, ProductState(binary_int=0))
    simulate!(c, st; n_steps=n)
end
```

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
    if record_when isa Symbol && record_when ∉ (:every_step, :every_gate, :final_only, :marks)
        throw(ArgumentError("Unknown record_when symbol: $record_when. Valid options: :every_step, :every_gate, :final_only, :marks"))
    end

    # record!(c) marker <-> policy consistency (v0.1, Task 13):
    # markers and the step/gate-cadence symbol policies are mutually
    # exclusive — a symbol policy would silently ignore the markers (this
    # includes the DEFAULT :every_step, a real trap otherwise).
    has_markers = any(op -> op.type == :record_mark, circuit.operations)
    if has_markers && record_when isa Symbol && record_when !== :marks
        throw(ArgumentError(
            "circuit contains record!(c) markers but record_when=:$record_when would ignore them. " *
            "Use record_when=:marks, a custom predicate, or remove the markers."))
    end
    if !has_markers && record_when === :marks
        throw(ArgumentError(
            "record_when=:marks requires record!(c) markers in the circuit, but no markers present. " *
            "Add record!(c[, names...]) inside the Circuit do-block, or use " *
            ":every_step, :every_gate, :final_only, or a custom predicate."))
    end

    # Marker ordinals: 1-based position among the circuit's :record_mark
    # pseudo-ops (stable across steps) — exposed to predicates as
    # ctx.mark_index.
    mark_ordinals = Dict{Int,Int}()
    let m = 0
        for (i, op) in enumerate(circuit.operations)
            if op.type == :record_mark
                m += 1
                mark_ordinals[i] = m
            end
        end
    end

    # Cumulative element-slot counter across ALL steps. Advances once per
    # element slot regardless of stochastic outcome (identity included), so
    # recording schedules based on it are trajectory-independent.
    gate_idx = 0

    # Reset staircase positions once at the start
    _reset_circuit_geometries!(circuit)

    for step in 1:n_steps
        should_record_this_step = false

        for (op_idx, op) in enumerate(circuit.operations)
            if op.type == :deterministic
                geo = op.geometry
                if is_broadcast(geo)
                    # Broadcast geometry: one application per element, in
                    # canonical enumeration order (API contract).
                    elems = elements(geo, circuit.L, circuit.bc)
                    for (element_idx, sites) in enumerate(elems)
                        set_event_context!(state, step, op_idx, element_idx)
                        execute!(state, op.gate, sites)
                        if state.event_log !== nothing
                            log_event!(state, GateApplied(step, op_idx, element_idx, gate_label(op.gate), sites))
                        end
                        gate_idx += 1
                        ctx = RecordingContext(step, gate_idx, op_idx, element_idx, op.gate, false, false, 0)
                        set_flag, record_now = _evaluate_recording(record_when, ctx, step, n_steps)
                        should_record_this_step |= set_flag
                        record_now && record!(state)
                    end
                else
                    # Set geometry: a single region (support-aware for
                    # staircases via compute_sites_dispatch).
                    sites = compute_sites_dispatch(geo, op.gate, step, circuit.L, circuit.bc)
                    set_event_context!(state, step, op_idx, 1)
                    execute!(state, op.gate, sites)
                    if state.event_log !== nothing
                        log_event!(state, GateApplied(step, op_idx, 1, gate_label(op.gate), sites))
                    end
                    # Advance staircase after deterministic application
                    if geo isa AbstractStaircase
                        advance!(geo, circuit.L, circuit.bc)
                    end
                    gate_idx += 1
                    ctx = RecordingContext(step, gate_idx, op_idx, 1, op.gate, false, false, 0)
                    set_flag, record_now = _evaluate_recording(record_when, ctx, step, n_steps)
                    should_record_this_step |= set_flag
                    record_now && record!(state)
                end

            elseif op.type == :stochastic
                # === v0.1 UNIFIED RULE: per-element categorical selection ===
                # All coins from :gates_spacetime (rng= kwarg removed in v0.1).
                actual_rng = get_rng(state.rng_registry, :gates_spacetime)
                outcomes = op.outcomes

                # Common element count K (equal-K validated at build time;
                # re-validated here so hand-built Circuits fail loudly too).
                K = _op_element_count(op, circuit.L, circuit.bc)
                probs = Float64[Float64(o.probability) for o in outcomes]

                # Precompute broadcast element lists (fixed within the op);
                # set geometries resolve lazily at selection time because
                # staircase/Pointer positions are mutable and support-aware.
                elem_lists = Union{Nothing, Vector{Vector{Int}}}[
                    is_broadcast(o.geometry) ? elements(o.geometry, circuit.L, circuit.bc) : nothing
                    for o in outcomes]

                for k in 1:K
                    sel = select_outcome_index(actual_rng, probs)
                    applied_gate = nothing
                    if sel != 0
                        outcome = outcomes[sel]
                        sites = elem_lists[sel] === nothing ?
                            compute_sites_dispatch(outcome.geometry, outcome.gate, step, circuit.L, circuit.bc) :
                            elem_lists[sel][k]
                        set_event_context!(state, step, op_idx, k)
                        execute!(state, outcome.gate, sites)
                        if state.event_log !== nothing
                            log_event!(state, GateApplied(step, op_idx, k, gate_label(outcome.gate), sites))
                        end
                        # Advance only the SELECTED staircase; identity does
                        # NOT advance (guarded against at build time by the
                        # staircase Σp<1 rule, but never crash here).
                        if outcome.geometry isa AbstractStaircase
                            advance!(outcome.geometry, circuit.L, circuit.bc)
                            sync_staircase_positions!(outcomes, outcome.geometry)
                        end
                        applied_gate = outcome.gate
                    end
                    # Element-slot counter advances REGARDLESS of outcome.
                    gate_idx += 1
                    ctx = RecordingContext(step, gate_idx, op_idx, k, applied_gate, false, false, 0)
                    set_flag, record_now = _evaluate_recording(record_when, ctx, step, n_steps)
                    should_record_this_step |= set_flag
                    # :every_gate records only on actual gate application
                    # (identity slots advance counters but apply nothing).
                    (record_now && applied_gate !== nothing) && record!(state)
                end

            elseif op.type == :record_mark
                # === record!(c[, names...]) marker pseudo-op (v0.1) ===
                # Markers are pure annotations: no RNG draws, no gate_idx
                # advance, no staircase movement, no event-log entries.
                mark_index = mark_ordinals[op_idx]
                if record_when === :marks
                    # Fire exactly here, in the op stream (NOT at the
                    # structural step boundary). Empty names = record all
                    # tracked observables; explicit names = selective.
                    record!(state; only = isempty(op.names) ? nothing : op.names)
                elseif record_when isa Function
                    # Predicates see marks as events (at_mark=true); a true
                    # return uses the usual flag semantics — ONE record at
                    # the end of the step.
                    ctx = RecordingContext(step, gate_idx, op_idx, 0, nothing, false, true, mark_index)
                    set_flag, _ = _evaluate_recording(record_when, ctx, step, n_steps)
                    should_record_this_step |= set_flag
                end
            end
        end

        # === STRUCTURAL step boundary (v0.1) ===
        # Computed after the op loop from loop structure alone — fires
        # regardless of which outcomes any stochastic op selected. This
        # fixes the pre-v0.1 "do-nothing skip" bug where a trailing
        # stochastic op selecting identity silently dropped the step record.
        if record_when === :every_step
            record!(state)
        elseif record_when === :final_only
            step == n_steps && record!(state)
        elseif record_when isa Function
            boundary_ctx = RecordingContext(step, gate_idx, 0, 0, nothing, true, false, 0)
            if record_when(boundary_ctx)
                should_record_this_step = true
            end
        end
        # (:marks never records at the structural boundary — markers fire
        # inside the op loop, so a trailing marker cannot double-record.)

        if should_record_this_step
            record!(state)
        end
    end

    return nothing
end

# Gate execution is uniform: the engine calls execute!(state, gate, sites)
# (Core/apply.jl) for every gate. Gate-specific behavior (Measurement, Reset,
# user gates) lives in execute! methods + traits, NOT in engine type-checks.
# The former execute_gate! special-casing was removed in v0.1 (Task 8).

# Note: compute_sites_dispatch is defined in expand.jl (shared helper)
