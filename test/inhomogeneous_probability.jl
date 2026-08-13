# test/inhomogeneous_probability.jl
#
# Consolidated tests for per-element (inhomogeneous) probability schedules:
# (a) resolver validation, (b) builder & eager acceptance, (c) uniform-vector
# == scalar bit-exactness, (d) per-element selection, (e) engine/expansion
# parity, (f) ASCII labels, (g) failure atomicity.
#
# Standalone-runnable:
#   julia --project=. -e 'include("test/inhomogeneous_probability.jl")'

using Test
using QuantumCircuitsMPS
using QuantumCircuitsMPS: resolve_probability_schedule, events, GateApplied,
                          expand_circuit, is_record_mark, current_position,
                          build_template_groups_ascii
using SparseArrays

# ── Local helpers ───────────────────────────────────────────────────────────

# Minimal outcome for direct resolver calls (only `.probability` is read).
_oc(p) = (probability = p, gate = nothing, geometry = nothing)

const _STREAMS = (:born_measurement, :gates_realization, :gates_spacetime, :state_init)

function _inhp_state(L; bc = :periodic, gs = 42)
    state = SimulationState(L = L, bc = bc, maxdim = 32,
        rng = RNGRegistry(gates_spacetime = gs, born_measurement = 1,
            gates_realization = 2, state_init = 3),
        log_events = true)
    initialize!(state, ProductState(binary_int = 0))
    return state
end

function _gate_events(st)
    [(e.step, e.op_idx, e.element_idx, e.gate_label, e.sites)
     for e in events(st) if e isa GateApplied]
end

# Hand-built circuits bypass builder-time validation entirely.
_stoch(outs) = (type = :stochastic, rng = :gates_spacetime, outcomes = outs)
_hand(L, bc, ops...) = Circuit(L = L, bc = bc, operations = NamedTuple[ops...])

# Snapshot/assert pair for atomicity checks. RNG streams are probed via
# rand(copy(...)) so the real streams never advance while being compared.
function _snapshot(st, L)
    (p = [born_probability(st, i, 0) for i in 1:L],
        n_events = length(events(st)),
        streams = Dict(s => copy(get_rng(st.rng_registry, s)) for s in _STREAMS))
end

function _assert_unchanged(st, before)
    @test [born_probability(st, i, 0) for i in 1:length(before.p)] == before.p
    @test length(events(st)) == before.n_events
    for s in _STREAMS
        @test rand(copy(get_rng(st.rng_registry, s))) == rand(copy(before.streams[s]))
    end
end

@testset "(a) resolver validation" begin
    # Scalar broadcast across all K columns.
    M = resolve_probability_schedule([_oc(0.3), _oc(0.7)], 4)
    @test M isa Matrix{Float64} && size(M) == (2, 4)
    @test all(M[1, :] .== 0.3) && all(M[2, :] .== 0.7)
    # Vector materializes per-element values.
    @test resolve_probability_schedule([_oc([0.1, 0.2, 0.3])], 3)[1, :] == [0.1, 0.2, 0.3]
    # SparseVector densifies; structural zeros become literal dense 0.0.
    sv = sparsevec([2, 4], [0.3, 0.5], 5)
    Ms = resolve_probability_schedule([_oc(sv)], 5)
    @test Ms isa Matrix{Float64} && Ms[1, :] == [0.0, 0.3, 0.0, 0.5, 0.0]
    @test Ms[1, 1] === 0.0
    # Mixed scalar + vector rows in one call are legal.
    Mm = resolve_probability_schedule([_oc(0.2), _oc([0.1, 0.15, 0.05])], 3)
    @test Mm[1, :] == fill(0.2, 3) && Mm[2, :] == [0.1, 0.15, 0.05]
    # Length-1 vector is legal at K=1.
    @test resolve_probability_schedule([_oc([0.42])], 1) == reshape([0.42], 1, 1)

    @testset "reject: $name" for (name, outs, K) in [
        ("wrong length K", [_oc([0.1, 0.2])], 3),
        ("non-Real eltype", [_oc(["a", "b"])], 2),
        ("NaN", [_oc([0.1, NaN])], 2),
        ("negative", [_oc([-0.1, 0.2])], 2),
        ("element > 1", [_oc([0.5, 1.2])], 2),
        ("per-column sum > 1+1e-10", [_oc(0.6), _oc(0.6)], 1)
    ]
        @test_throws ArgumentError resolve_probability_schedule(outs, K)
    end
end

@testset "(b) builder & eager acceptance" begin
    L = 4
    vec_p = [0.1, 0.2, 0.3, 0.1]
    # Lazy builder: vector accepted; ORIGINAL objects recorded, no derived field.
    circuit = Circuit(L = L, bc = :periodic) do c
        apply_with_prob!(c;
            outcomes = [
                (probability = 0.2, gate = Reset(), geometry = AllSites()),
                (probability = vec_p, gate = Measure(:Z), geometry = AllSites())])
    end
    op = only(circuit.operations)
    @test op.type == :stochastic && propertynames(op) == (:type, :rng, :outcomes)
    @test op.outcomes[1].probability === 0.2
    @test op.outcomes[2].probability === vec_p

    # Eager: vector accepted and executes.
    st = _inhp_state(L)
    @test apply_with_prob!(st;
        outcomes = [
            (probability = fill(0.5, L), gate = PauliX(), geometry = EachSite(1:L))]) ===
          nothing

    # Staircase/Pointer walker guard: per-element Σp != 1 rejected in BOTH forms.
    bad = [(probability = [0.5], gate = Reset(), geometry = StaircaseLeft(1))]
    @test_throws ArgumentError Circuit(L = L, bc = :periodic) do c
        apply_with_prob!(c; outcomes = bad)
    end
    @test_throws ArgumentError apply_with_prob!(_inhp_state(L); outcomes = bad)
    @test_throws ArgumentError Circuit(L = L, bc = :periodic) do c
        apply_with_prob!(c;
            outcomes = [(probability = [0.9], gate = PauliX(), geometry = Pointer(1))])
    end
    # ...and per-element Σp = 1 (mixed scalar+vector) is accepted.
    accepted = Circuit(L = L, bc = :periodic) do c
        apply_with_prob!(c;
            outcomes = [
                (probability = [0.4], gate = Reset(), geometry = StaircaseLeft(1)),
                (probability = 0.6, gate = HaarRandom(), geometry = StaircaseRight(1))])
    end
    @test length(accepted.operations) == 1
end

@testset "(c) uniform-vector fill(p,K) == scalar p bit-exactness" begin
    L, bc, n_steps = 6, :periodic, 5
    Ko = element_count(Bricklayer(:odd), L, bc)
    Ka = element_count(AllSites(), L, bc)
    make_circuit(p_haar, p_meas) = Circuit(L = L, bc = bc) do c
        apply_with_prob!(c;
            outcomes = [
                (probability = p_haar, gate = HaarRandom(), geometry = Bricklayer(:odd))])
        apply_with_prob!(c;
            outcomes = [
                (probability = p_meas, gate = Measure(:Z), geometry = AllSites())])
    end
    c_scalar = make_circuit(0.5, 0.3)
    c_vector = make_circuit(fill(0.5, Ko), fill(0.3, Ka))

    s_scalar = _inhp_state(L; bc = bc, gs = 4242)
    s_vector = _inhp_state(L; bc = bc, gs = 4242)
    simulate!(c_scalar, s_scalar; n_steps = n_steps, record_when = :final_only)
    simulate!(c_vector, s_vector; n_steps = n_steps, record_when = :final_only)

    # Identical event logs (gate tuples + full event-type sequence)...
    @test _gate_events(s_scalar) == _gate_events(s_vector)
    @test !isempty(_gate_events(s_scalar))
    @test [typeof(e) for e in events(s_scalar)] == [typeof(e) for e in events(s_vector)]
    # ...and every named RNG stream ends in an identical state.
    for s in _STREAMS
        @test rand(copy(get_rng(s_scalar.rng_registry, s))) ==
              rand(copy(get_rng(s_vector.rng_registry, s)))
    end
end

@testset "(d) per-element selection: [1,0,0,1] on AllSites() at L=4" begin
    L, n_steps = 4, 4
    circuit = Circuit(L = L, bc = :periodic) do c
        apply_with_prob!(c;
            outcomes = [
                (probability = [1.0, 0.0, 0.0, 1.0], gate = Measure(:Z),
                geometry = AllSites())])
    end
    state = _inhp_state(L)
    simulate!(circuit, state; n_steps = n_steps, record_when = :final_only)
    evs = [e for e in events(state) if e isa GateApplied]
    @test length(evs) == 2 * n_steps   # exactly sites 1 and 4, every step
    for step in 1:n_steps
        step_evs = [e for e in evs if e.step == step]
        @test sort!([only(e.sites) for e in step_evs]) == [1, 4]
        @test sort!([e.element_idx for e in step_evs]) == [1, 4]
    end
end

@testset "(e) engine/expansion parity: nonuniform vector circuit" begin
    L, bc, n_steps, seed = 8, :periodic, 6, 55
    circuit = Circuit(L = L, bc = bc) do c
        apply_with_prob!(c;
            outcomes = [
                (probability = [0.1, 0.2, 0.3, 0.4], gate = HaarRandom(),
                    geometry = Bricklayer(:odd)),
                (probability = [0.5, 0.4, 0.3, 0.2], gate = CZ(),
                    geometry = Bricklayer(:odd))])
        apply_with_prob!(c;
            outcomes = [
                (probability = [0.05, 0.5, 0.9, 0.1], gate = CZ(),
                geometry = Bricklayer(:even))])
    end
    exp_seq = [(op.label, op.sites)
               for step_ops in expand_circuit(circuit; seed = seed, n_steps = n_steps)
               for op in step_ops if !is_record_mark(op)]
    state = _inhp_state(L; bc = bc, gs = seed)
    simulate!(circuit, state; n_steps = n_steps, record_when = :final_only)
    eng_seq = [(e.gate_label, e.sites) for e in events(state) if e isa GateApplied]
    @test exp_seq == eng_seq
    @test !isempty(exp_seq)
end

@testset "(f) ASCII per-element labels" begin
    L = 8
    # Nonuniform vector: distinct labels at distinct elements.
    circuit = Circuit(L = L, bc = :periodic) do c
        apply_with_prob!(c;
            outcomes = [
                (probability = [0.9, 0.1, 0.9, 0.1], gate = PauliX(),
                geometry = Bricklayer(:even))])
    end
    ops = build_template_groups_ascii(circuit)[1][1]
    @test [op.sites for op in ops] == [[2, 3], [4, 5], [6, 7], [8, 1]]
    @test [op.label for op in ops] == ["X(0.9)", "X(0.1)", "X(0.9)", "X(0.1)"]
    @test ops[1].label != ops[2].label

    # Scalar rendering unchanged: one broadcast label; p == 1.0 omits suffix.
    for (p, expected) in ((0.3, "Z(0.3)"), (1.0, "Z"))
        circ = Circuit(L = L, bc = :periodic) do c
            apply_with_prob!(c;
                outcomes = [
                    (probability = p, gate = PauliZ(), geometry = Bricklayer(:even))])
        end
        @test [op.label for op in build_template_groups_ascii(circ)[1][1]] ==
              fill(expected, 4)
    end
end

@testset "(g) failure atomicity: malformed schedules mutate nothing" begin
    L = 4   # AllSites() => K = 4
    cases = [
        ("wrong length",
            [(probability = fill(0.1, L + 1), gate = PauliX(), geometry = AllSites())]),
        ("out-of-range element",
            [(probability = [0.1, 1.5, 0.2, 0.0], gate = PauliX(), geometry = AllSites())]),
        ("per-column overflow",
            [(probability = fill(0.7, L), gate = PauliX(), geometry = AllSites()),
                (probability = fill(0.7, L), gate = PauliZ(), geometry = AllSites())])
    ]
    @testset "$name" for (name, outs) in cases
        # Eager: throws with state, event log, and all 4 streams untouched.
        st = _inhp_state(L)
        apply!(st, HaarRandom(), Bricklayer(:even))   # scramble: proxy nontrivial
        before = _snapshot(st, L)
        @test_throws ArgumentError apply_with_prob!(st; outcomes = outs)
        _assert_unchanged(st, before)

        # simulate!: hand-built [valid staircase op, malformed op] circuit is
        # rejected before geometry reset, RNG use, or any execution.
        walker = StaircaseLeft(3)
        QuantumCircuitsMPS.advance!(walker, L, :periodic)   # off start: 3 -> 2
        @test current_position(walker) == 2
        circuit = _hand(L, :periodic,
            _stoch([(probability = 1.0, gate = Reset(), geometry = walker)]),
            _stoch(outs))
        st2 = _inhp_state(L)
        before2 = _snapshot(st2, L)
        @test_throws ArgumentError simulate!(circuit, st2; n_steps = 2)
        @test current_position(walker) == 2   # a geometry reset would restore 3
        _assert_unchanged(st2, before2)

        # expand_circuit: throws, walker untouched, no partial result escapes.
        result = try
            expand_circuit(circuit; seed = 0, n_steps = 2)
        catch e
            e
        end
        @test result isa ArgumentError
        @test current_position(walker) == 2
    end
end

println("INHOMOGENEOUS-PROBABILITY: PASS")
