# === Gate Application Engine ===
# Core apply! function implementing CT.jl-style MPS contraction

using ITensors
using ITensorMPS

"""
    apply!(state::SimulationState, gate::AbstractGate, geo::AbstractGeometry)

Apply a gate to the state at sites specified by geometry.
Modifies state.backend.mps in-place.

Geometry dispatch resolves the target region(s); each region is executed
through the uniform `execute!(state, gate, region)` protocol.

Normalization dispatch (Contract 3.5) is trait-based:
- `needs_normalization(gate) == false` (unitaries): NO normalize after apply
- `needs_normalization(gate) == true` (projective gates): normalize + truncate
"""
function apply!(state::SimulationState, gate::AbstractGate, geo::AbstractGeometry)
    # Dispatch to appropriate handler based on geometry type
    _apply_dispatch!(state, gate, geo)
end

"""
    apply!(state::SimulationState, gate::AbstractGate, sites::Vector{Int})

Apply a gate to specific physical sites. Direct site specification.
Routes through the uniform `execute!` protocol (so measurement-like gates
such as `Measure`/`Reset` work with explicit site vectors too).
"""
function apply!(state::SimulationState, gate::AbstractGate, sites::Vector{Int})
    execute!(state, gate, sites)
end

# === Dispatch handlers for different geometry types ===
# Each handler resolves the geometry to concrete region(s) and calls execute!.

function _apply_dispatch!(state::SimulationState, gate::AbstractGate, geo::SingleSite)
    sites = get_sites(geo, state)
    execute!(state, gate, sites)
end

function _apply_dispatch!(state::SimulationState, gate::AbstractGate, geo::AdjacentPair)
    sites = get_sites(geo, state)
    execute!(state, gate, sites)
end

function _apply_dispatch!(state::SimulationState, gate::AbstractGate, geo::AbstractStaircase)
    # Gate-support-aware resolution: 1-site gates (e.g. Reset, Measure)
    # act at the current position; 2-site gates act on (pos, pos+range).
    sites = compute_sites(geo, 1, state.L, state.bc, gate)
    execute!(state, gate, sites)
    # Advance staircase AFTER application
    advance!(geo, state.L, state.bc)
end

function _apply_dispatch!(state::SimulationState, gate::AbstractGate, geo::Bricklayer)
    pairs = get_pairs(geo, state)
    for (p1, p2) in pairs
        execute!(state, gate, [p1, p2])
    end
end

function _apply_dispatch!(state::SimulationState, gate::AbstractGate, geo::AllSites)
    all_sites = get_all_sites(geo, state)
    for site in all_sites
        execute!(state, gate, [site])  # independent per-site execution
    end
end

# Pointer does NOT auto-advance - user controls movement via move!()
function _apply_dispatch!(state::SimulationState, gate::AbstractGate, geo::Pointer)
    # Gate-support-aware resolution (mirrors staircase): 1-site gates act at
    # the current position; 2-site gates act on the (pos, pos+1) pair.
    sites = support(gate) == 1 ? [geo._position] : get_sites(geo, state)
    execute!(state, gate, sites)
    # NO advance! - user explicitly calls move!()
end

# Sites: one explicit multi-site region (set geometry, v0.1)
function _apply_dispatch!(state::SimulationState, gate::AbstractGate, geo::Sites)
    validate_support(gate, geo, state.L, state.bc)  # names support vs region size on mismatch
    sites = get_sites(geo, state)
    execute!(state, gate, sites)
end

# === Internal helper for Born-sampled projection ===

"""
    _measure_single_site!(state::SimulationState, site::Int) -> Int

Perform Born-sampled projective measurement on a single site.
Returns the measurement outcome (a level index `0 .. local_dim-1`;
0 or 1 for qubits).

This is the FUNDAMENTAL measurement operation:
1. Compute Born probabilities P(k|ψ) for levels k = 0 .. local_dim-2
2. Sample ONE categorical outcome using a single scalar draw from the
   :born_measurement RNG stream (at local_dim=2 this reduces EXACTLY to the
   historical binary draw `rand < P(0) ? 0 : 1` — same draw count, same
   float comparison, bitwise-identical qubit trajectories)
3. Apply the per-level Projection operator
4. Return outcome (for conditional logic in Reset / feedback)
"""
function _measure_single_site!(state::SimulationState, site::Int)
    d = state.local_dim
    born_measurement_rng = get_rng(state.rng_registry, :born_measurement)
    # SCALAR-DRAW CONTRACT: one scalar Born draw per measured site
    r = rand(born_measurement_rng)
    outcome = d - 1  # falls through to the last level (Σₖ P(k) = 1 up to fp error)
    cumprob = 0.0
    for k in 0:(d - 2)
        cumprob += born_probability(state, site, k)
        if r < cumprob
            outcome = k
            break
        end
    end
    _apply_single!(state, Projection(outcome), [site])
    if state.event_log !== nothing
        # Real (step, op_idx) via the engine's event context (set by
        # simulate! before each execute! call; 0 outside an engine run,
        # e.g. for eager apply! calls which have no step context).
        log_event!(state, MeasurementOutcome(state.event_step, state.event_op_idx, [site], outcome))
    end
    return outcome
end

# === execute! protocol (v0.1) ===
# ONE uniform entry point for executing a gate on a concrete site region.
# Geometry dispatch (above) and the circuit engine (Circuit/execute.jl) both
# call execute! — there is no gate-type special-casing outside these methods.

"""
    execute!(state::SimulationState, gate::AbstractGate, region::Vector{Int})

Execute `gate` on the physical sites `region` (already resolved from a
geometry). This is the v0.1 gate-execution protocol:

- **Default implementation**: `build_operator` → `apply_op_internal!`, then
  normalize + truncate iff `needs_normalization(gate)` (see `_apply_single!`).
- **Gate-specific overrides**: gates with non-operator semantics (Born
  sampling + classical logic) override this method — see `Measure` and
  `Reset` below. User-defined gates may override it the same way:

```julia
function QuantumCircuitsMPS.execute!(state::SimulationState, g::MyGate, region::Vector{Int})
    # custom behavior; region is a vector of physical sites
end
```

Related traits: `needs_normalization(gate)` (post-apply renormalization) and
`is_measurement(gate)` (gate Born-samples via `:born_measurement`).
"""
function execute!(state::SimulationState, gate::AbstractGate, region::Vector{Int})
    _apply_single!(state, gate, region)
end

"""
    execute!(state::SimulationState, gate::Reset, region::Vector{Int})

Reset (DERIVED - measurement + conditional X): Born-sample the single site in
`region`; if the outcome is 1, flip it back to |0⟩ with PauliX.
"""
function execute!(state::SimulationState, gate::Reset, region::Vector{Int})
    if support(gate) != length(region)
        throw(ArgumentError("Gate support $(support(gate)) does not match sites $(length(region))"))
    end
    site = region[1]
    outcome = _measure_single_site!(state, site)
    if outcome == 1
        _apply_single!(state, PauliX(), [site])
    end
    return nothing
end

"""
    execute!(state::SimulationState, gate::Measure, region::Vector{Int})

Measure (v0.1, feedback-capable): Born-sample the single site in `region`
(via `_measure_single_site!`, which emits the `MeasurementOutcome` event with
the engine's real step/op indices), then dispatch the gate's feedback — if
any — with the observed outcome.

Feedback runs INSIDE `with_guarded_stream(registry, :gates_spacetime)`: it
can never consume spacetime coins (fixed-draw contract), while
`:gates_realization` and `:born_measurement` remain freely usable. Feedback
gates execute through this same `execute!` protocol but are NOT engine op
slots: they advance no counters and emit no `GateApplied` events. Recursion
(feedback applying another `Measure`) is allowed — user responsibility.
"""
function execute!(state::SimulationState, gate::Measure, region::Vector{Int})
    if support(gate) != length(region)
        throw(ArgumentError("Gate support $(support(gate)) does not match sites $(length(region))"))
    end
    site = region[1]
    outcome = _measure_single_site!(state, site)
    fb = gate.feedback
    if fb !== nothing
        with_guarded_stream(state.rng_registry, :gates_spacetime) do
            apply_feedback!(fb, state, [site], outcome)
        end
    end
    return nothing
end

# === Core application logic ===

"""
    _apply_single!(state::SimulationState, gate::AbstractGate, phy_sites::Vector{Int})

Apply gate to specific physical sites. Internal workhorse.

Steps:
1. Validate support matches site count
2. Convert physical sites to RAM indices
3. Build operator with physical site indices
4. Apply operator to MPS
5. Normalize + truncate iff `needs_normalization(gate)` (trait, Contract 3.5)
"""
function _apply_single!(state::SimulationState, gate::AbstractGate, phy_sites::Vector{Int})
    # Contract 2.1: Support validation
    if support(gate) != length(phy_sites)
        throw(ArgumentError("Gate support $(support(gate)) does not match sites $(length(phy_sites))"))
    end

    # Convert physical sites to RAM indices
    ram_sites = [state.phy_ram[ps] for ps in phy_sites]

    # Build operator with state.backend.sites indices (in physical pair order)
    op = _build_gate_operator(state, gate, phy_sites, ram_sites)

    # Apply operator using CT.jl algorithm
    apply_op_internal!(state.backend.mps, op, state.backend.sites,
        state.backend.cutoff, state.backend.maxdim)

    # Contract 3.5: Normalization via the needs_normalization trait
    # (true for Projection/SpinSectorProjection/SpinSectorMeasurement and any
    # user gate that opts in; unitaries default to false — NO normalize)
    if needs_normalization(gate)
        normalize!(state.backend.mps)
        truncate!(state.backend.mps; cutoff = state.backend.cutoff)
    end
end

"""
    _build_gate_operator(state, gate, phy_sites, ram_sites) -> ITensor

Build the operator tensor for the gate.
"""
function _build_gate_operator(state::SimulationState, gate::AbstractGate,
        phy_sites::Vector{Int}, ram_sites::Vector{Int})
    if length(ram_sites) == 1
        # Single-site gate. rng is passed for gates that need randomness
        # (e.g. HaarRandom(1)); all other single-site gates absorb it via kwargs.
        site_idx = state.backend.sites[ram_sites[1]]
        return build_operator(gate, site_idx, state.local_dim; rng = state.rng_registry)
    else
        # Multi-site gate: use indices in RAM order
        site_indices = [state.backend.sites[rs] for rs in ram_sites]
        return build_operator(gate, site_indices, state.local_dim;
            rng = state.rng_registry, mps = state.backend.mps, ram_sites = ram_sites)
    end
end

"""
    apply_op_internal!(mps::MPS, op::ITensor, sites::Vector{Index}, cutoff::Float64, maxdim::Int)

Apply operator to MPS following CT.jl algorithm (lines 147-172).

Contract 3.6: Index matching via Index comparison, NOT tag parsing.
"""
function apply_op_internal!(
        mps::MPS, op::ITensor, sites::Vector{Index}, cutoff::Float64, maxdim::Int)
    # Get RAM site indices from operator indices (Contract 3.6)
    i_list = get_op_ram_sites(op, sites)
    sort!(i_list)

    # Orthogonalize MPS to first site
    orthogonalize!(mps, i_list[1])

    # Contract MPS tensors in range
    mps_ij = mps[i_list[1]]
    for idx in (i_list[1] + 1):i_list[end]
        mps_ij *= mps[idx]
    end

    # Apply operator
    mps_ij *= op
    noprime!(mps_ij)

    if length(i_list) == 1
        # Single-site: direct assignment
        mps[i_list[1]] = mps_ij
    else
        # Multi-site: SVD chain reconstruction
        lefttags = (i_list[1] == 1) ? nothing : tags(linkind(mps, i_list[1] - 1))

        for idx in i_list[1]:(i_list[end] - 1)
            if idx == 1
                inds1 = [siteind(mps, 1)]
            else
                inds1 = [findindex(mps[idx - 1], lefttags), findindex(mps[idx], "Site")]
            end

            lefttags = tags(linkind(mps, idx))
            U, S, V = svd(
                mps_ij, inds1; cutoff = cutoff, lefttags = lefttags, maxdim = maxdim)
            mps[idx] = U
            mps_ij = S * V
        end

        mps[i_list[end]] = mps_ij
    end

    return nothing
end

"""
    get_op_ram_sites(op::ITensor, sites::Vector{Index}) -> Vector{Int}

Get RAM site indices from operator indices using Index comparison (Contract 3.6).
Does NOT parse tags.
"""
function get_op_ram_sites(op::ITensor, sites::Vector{Index})
    op_inds = inds(op)
    ram_sites = Int[]

    for op_idx in op_inds
        # Only process unprimed indices (inputs)
        if plev(op_idx) != 0
            continue
        end

        # Find matching site by Index comparison
        found = false
        for (ram_idx, site_idx) in enumerate(sites)
            if noprime(op_idx) == noprime(site_idx)
                push!(ram_sites, ram_idx)
                found = true
                break
            end
        end

        if !found
            error("Operator index $op_idx not found in state sites")
        end
    end

    return ram_sites
end
