# test/features/custom_observable.jl
# ═══════════════════════════════════════════════════════════════════════════
# T37 FEATURE: custom-observable callable contract
# ═══════════════════════════════════════════════════════════════════════════
#
# The contract (see `track!` docstring / docs/src/custom_observables.md):
# `track!(state, :name => f)` accepts ANY callable `f(state)` returning a
# `Number` or an `AbstractVector` — subtyping `AbstractObservable` is
# optional. Pinned here:
#   1. a plain closure tracked through `simulate!` records the SAME values
#      as the equivalent built-in observable, on all 3 backends;
#   2. an erroring callable produces an ErrorException NAMING the observable
#      key (built-ins keep their own typed errors — recording_v01.jl pins
#      the DomainWall ArgumentError path);
#   3. vector-returning callables round-trip through storage (one entry per
#      record point, entry == the returned vector);
#   4. storage contract: AbstractObservable → Vector{Float64} (widened to
#      Vector{Any} only if it returns a non-scalar), generic callable →
#      Vector{Any};
#   5. the struct-based advanced path (subtype + record_value override)
#      matching the docs page's worked example (c).

using Test
using QuantumCircuitsMPS

# Prefixed helpers (runtests.jl includes all test files into one shared scope)
function _co_state(backend; L = 4, bc = :open)
    bk = backend == :mps ? (maxdim = 32,) : (backend = backend,)
    state = SimulationState(; L = L, bc = bc, bk...,
        rng = RNGRegistry(gates_spacetime = 42, gates_realization = 7,
            born_measurement = 99))
    initialize!(state, ProductState(binary_int = 0))
    return state
end

# Clifford-compatible circuit so the SAME circuit runs on all 3 backends
function _co_circuit(; L = 4)
    return Circuit(L = L, bc = :open) do c
        apply!(c, Hadamard(), SingleSite(1))
        apply!(c, CNOT(), Sites([1, 2]))
    end
end

_CO_BACKENDS = (:mps, :statevector, :clifford)
_co_tol(backend) = backend == :mps ? 1e-10 : 1e-12

# --- structs must be defined at top level (not inside @testset blocks) ---

# Docs example (c) shape: subtype + callable + record_value override.
struct T37ClampedProbability <: QuantumCircuitsMPS.AbstractObservable
    site::Int
end
(obs::T37ClampedProbability)(state) = born_probability(state, obs.site, 0)
function QuantumCircuitsMPS.record_value(obs::T37ClampedProbability, state;
        i1::Union{Int, Nothing} = nothing)
    return clamp(obs(state), 0.0, 1.0)
end

# Proves record_value (not obs(state)) is the recording path.
struct T37RecordValueMarker <: QuantumCircuitsMPS.AbstractObservable end
(obs::T37RecordValueMarker)(state) = 1.0
function QuantumCircuitsMPS.record_value(obs::T37RecordValueMarker, state;
        i1::Union{Int, Nothing} = nothing)
    return 2.0
end

# Vector-returning AbstractObservable (T38 EntropyProfile forward-compat).
struct T37ZProfile <: QuantumCircuitsMPS.AbstractObservable end
(obs::T37ZProfile)(state) = [PauliString(i => :Z)(state) for i in 1:state.L]

# Scalar-then-vector returns: pins that widening preserves prior records.
mutable struct T37ScalarThenVector <: QuantumCircuitsMPS.AbstractObservable
    calls::Int
    T37ScalarThenVector() = new(0)
end
function (obs::T37ScalarThenVector)(state)
    obs.calls += 1
    return obs.calls == 1 ? 1.5 : [1.0, 2.0]
end

@testset "custom-observable callable contract (T37)" begin
    @testset "plain closure through simulate! — all 3 backends" begin
        for backend in _CO_BACKENDS
            state = _co_state(backend)
            # closure and the equivalent built-in, tracked side by side
            track!(state, :custom => s -> born_probability(s, 1, 0))
            track!(state, :ref => BornProbability(1, 0))
            simulate!(_co_circuit(), state; n_steps = 3, record_when = :every_step)

            custom = state.observables[:custom]
            @test length(custom) == 3
            @test all(v -> 0.0 <= v <= 1.0, custom)
            # closure records EXACTLY what the built-in records (same record
            # points, same values — bitwise, both call born_probability)
            @test custom == state.observables[:ref]
            # storage contract
            @test custom isa Vector{Any}
            @test state.observables[:ref] isa Vector{Float64}
        end
    end

    @testset "closure composing PauliString: connected correlator" begin
        # C(i,j) = ⟨ZᵢZⱼ⟩ − ⟨Zᵢ⟩⟨Zⱼ⟩; on Bell(1,2): 1 − 0·0 = 1 (docs example b)
        connected_zz(i, j) = s -> PauliString(i => :Z, j => :Z)(s) -
                                  PauliString(i => :Z)(s) * PauliString(j => :Z)(s)
        for backend in _CO_BACKENDS
            state = _co_state(backend; L = 2)
            apply!(state, Hadamard(), SingleSite(1))
            apply!(state, CNOT(), Sites([1, 2]))
            track!(state, :czz => connected_zz(1, 2))
            record!(state)   # eager record path
            @test length(state.observables[:czz]) == 1
            @test state.observables[:czz][end] ≈ 1.0 atol = _co_tol(backend)
        end
    end

    @testset "erroring callable → ErrorException naming the key" begin
        state = _co_state(:statevector)
        track!(state, :bad => s -> error("boom"))
        err = try
            record!(state)
            nothing
        catch e
            e
        end
        @test err isa ErrorException
        @test occursin(":bad", err.msg)          # the observable key is named
        @test isempty(state.observables[:bad])   # nothing silently appended

        # selective record! of a healthy callable is unaffected by :bad
        track!(state, :good => s -> born_probability(s, 1, 0))
        record!(state; only = [:good])
        @test state.observables[:good] == Any[1.0]
        @test isempty(state.observables[:bad])
    end

    @testset "vector-returning callable round-trips — all 3 backends" begin
        for backend in _CO_BACKENDS
            state = _co_state(backend)
            track!(state, :zprof => s -> [PauliString(i => :Z)(s) for i in 1:s.L])
            simulate!(_co_circuit(), state; n_steps = 2, record_when = :every_step)

            prof = state.observables[:zprof]
            @test length(prof) == 2                     # ONE entry per record point
            @test all(v -> v isa Vector{Float64}, prof) # entries ARE the vectors
            @test all(v -> length(v) == 4, prof)
            # after step 1 (H₁ then CNOT₁₂ on |0000⟩ → Bell(1,2) ⊗ |00⟩):
            # ⟨Z₁⟩ = ⟨Z₂⟩ = 0, ⟨Z₃⟩ = ⟨Z₄⟩ = +1
            @test isapprox(prof[1], [0.0, 0.0, 1.0, 1.0]; atol = _co_tol(backend))
        end
    end

    @testset "struct-based observable + record_value override (advanced path)" begin
        for backend in _CO_BACKENDS
            state = _co_state(backend)
            track!(state, :clamped => T37ClampedProbability(1))
            # AbstractObservable subtypes keep the scalar Float64[] storage
            @test state.observables[:clamped] isa Vector{Float64}
            record!(state)
            @test state.observables[:clamped] == [1.0]  # |0000⟩ → P(site 1 = 0) = 1
        end
        # the record_value hook — not obs(state) — is what record! consumes
        state = _co_state(:statevector)
        track!(state, :marker => T37RecordValueMarker())
        record!(state)
        @test state.observables[:marker] == [2.0]
    end

    @testset "vector-returning AbstractObservable widens storage (T38 forward-compat)" begin
        state = _co_state(:statevector)
        track!(state, :prof => T37ZProfile())
        @test state.observables[:prof] isa Vector{Float64}  # scalar container pre-record
        record!(state)
        record!(state)
        prof = state.observables[:prof]
        @test prof isa Vector{Any}                          # widened on first push
        @test length(prof) == 2
        @test prof[1] == ones(4) && prof[2] == ones(4)      # |0000⟩ → all ⟨Zᵢ⟩ = +1

        # widening preserves records already stored as Float64
        state2 = _co_state(:statevector)
        track!(state2, :mixed => T37ScalarThenVector())
        record!(state2)                                     # scalar 1.5 → Float64[]
        @test state2.observables[:mixed] isa Vector{Float64}
        record!(state2)                                     # vector → widen, keep 1.5
        @test state2.observables[:mixed] isa Vector{Any}
        @test state2.observables[:mixed][1] == 1.5
        @test state2.observables[:mixed][2] == [1.0, 2.0]
    end
end
