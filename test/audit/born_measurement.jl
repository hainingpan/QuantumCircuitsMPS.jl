# === AUDIT T7: Born rule / measurement / feedback cross-checks (v0.4.0) ===
#
# Executable audit of the measurement core, reviewed against:
#   src/Core/apply.jl        (_measure_single_site!, execute! for Measure/Reset)
#   src/Observables/born.jl  (MPS born_probability via expect + norm division)
#   src/StateVector/measurement.jl (digit-sum born_probability)
#   src/Clifford/measurement.jl    (projectZ!-based override)
#   src/Gates/feedback.jl    (Measure, OnOutcome, CallbackFeedback, sentinel guard)
#   src/Gates/spin_measurement.jl  (SpinSectorMeasurement Born sampling)
#
# What is verified here (audit conclusions encoded as permanent tests):
#  (a) Born normalization: Σ_o P(site,o) = 1 on all 3 backends (1e-14 exact
#      backends; MPS with active truncation still ~1e-15 because
#      born_probability divides by ⟨ψ|ψ⟩).
#  (b) |+⟩ measured in Z: P(0)=P(1)=1/2 exactly; the sampled outcome is drawn
#      from the :born_measurement stream via `rand(rng) < p0 ? 0 : 1` — pinned
#      by predicting the outcome from a twin MersenneTwister on every backend.
#  (c) Post-measurement state: normalized, and P(obtained outcome) = 1
#      (certainty after collapse) on all 3 backends.
#  (d) Reset() ≡ Measure(:Z; feedback=OnOutcome(1 => PauliX())): bit-identical
#      trajectories under identical seeds (same outcome sequence, same final
#      Born probabilities, same :born_measurement stream position) on
#      MPS + SV + Clifford. Extends test/feedback.jl (MPS-only) cross-backend.
#      Also: feedback fires on the correct outcome on every backend.
#  (e) Draw-count invariant: a DETERMINISTIC measurement (eigenstate) still
#      consumes exactly ONE :born_measurement draw on MPS/SV (scalar-draw
#      contract, src/Core/apply.jl:105-106). AUDIT NOTE: the Clifford override
#      consumes ZERO draws in the deterministic branch (documented in
#      src/Clifford/measurement.jl docstring) — a cross-backend draw-count
#      divergence, pinned here and recorded in the findings notepad.
#  (f) S=1 measurement sanity: single-site Measure(:Z)/born_probability are
#      qubit-only today (Projection is 0/1-only; "Proj0" op undefined for
#      "S=1" sites) — KNOWN limitation, T39 scope, pinned with @test_throws.
#      The supported S=1 measurement path, SpinSectorMeasurement, is audited
#      quantitatively: |Z0,Z0⟩ = √(2/3)|S=2,m=0⟩ − √(1/3)|S=0⟩, so
#      P(0)=1/3, P(1)=0, P(2)=2/3; sector sampled from :born_measurement
#      (one draw); post-state lies in the sampled sector with certainty.

using Test
using Random
using LinearAlgebra: norm
using QuantumCircuitsMPS
using QuantumCircuitsMPS: measurements  # ITensorMPS also exports `measurements`

# --- helpers (audit-local, prefixed to avoid clashes with sibling test files) ---

function _bm_state(backend::Symbol; L::Int = 4, bc::Symbol = :open,
        seeds::NTuple{3, Int} = (1, 2, 3), maxdim::Int = 32,
        log_events::Bool = false)
    st = SimulationState(L = L, bc = bc, backend = backend, maxdim = maxdim,
        rng = RNGRegistry(gates_spacetime = seeds[1], gates_realization = seeds[2],
            born_measurement = seeds[3]),
        log_events = log_events)
    initialize!(st, ProductState(binary_int = 0))
    return st
end

# Entangling preparation appropriate for each backend
function _bm_entangle!(st, backend::Symbol; layers::Int = 2)
    gate = backend === :clifford ? RandomClifford(2) : HaarRandom()
    for _ in 1:layers
        apply!(st, gate, Bricklayer(:odd))
        apply!(st, gate, Bricklayer(:even))
    end
    return st
end

_bm_norm(st, backend::Symbol) = backend === :statevector ?
                                norm(st.backend.ψ) : norm(st.backend.mps)

# true iff the :born_measurement stream of `st` (seeded with `seed`) has
# advanced by exactly `ndraws` scalar draws
function _bm_stream_advanced_by(st, seed::Int, ndraws::Int)
    twin = MersenneTwister(seed)
    for _ in 1:ndraws
        rand(twin)
    end
    return rand(copy(get_rng(st.rng_registry, :born_measurement))) == rand(copy(twin))
end

const _BM_BACKENDS = (:mps, :statevector, :clifford)

@testset "AUDIT T7: Born rule / measurement / feedback" begin

    # --- (a) Born normalization: Σ_outcomes P(site, o) = 1 -------------------
    @testset "(a) Born normalization Σ P(outcome) = 1 [$backend]" for backend in _BM_BACKENDS
        L = 6
        st = _bm_state(backend; L = L, bc = :periodic, maxdim = 8)  # maxdim=8: MPS actively truncates
        _bm_entangle!(st, backend; layers = 4)
        tol = backend === :mps ? 1e-13 : 1e-14
        for site in 1:L
            p0 = born_probability(st, site, 0)
            p1 = born_probability(st, site, 1)
            @test 0.0 <= p0 <= 1.0 + tol
            @test 0.0 <= p1 <= 1.0 + tol
            @test abs(p0 + p1 - 1.0) < tol
        end
        # Clifford probabilities are exactly ∈ {0, 1/2, 1} (stabilizer formalism)
        if backend === :clifford
            for site in 1:L
                @test born_probability(st, site, 0) in (0.0, 0.5, 1.0)
            end
        end
    end

    # --- (b) |+⟩ in Z: P(0)=P(1)=1/2; outcome drawn from :born_measurement ---
    @testset "(b) |+⟩ measurement statistics [$backend]" for backend in _BM_BACKENDS
        tol = backend === :mps ? 1e-10 : 1e-14
        # exact probability check
        st = _bm_state(backend; L = 2)
        apply!(st, Hadamard(), SingleSite(1))
        @test abs(born_probability(st, 1, 0) - 0.5) < tol
        @test abs(born_probability(st, 1, 1) - 0.5) < tol

        # outcome is `rand(:born_measurement) < p0 ? 0 : 1` — predict it with a
        # twin RNG for every seed (pins BOTH the stream identity and the
        # threshold convention)
        outcomes = Int[]
        for seed in 1:100
            s = _bm_state(backend; L = 2, seeds = (1, 2, seed), log_events = true)
            apply!(s, Hadamard(), SingleSite(1))
            apply!(s, Measure(:Z), SingleSite(1))
            o = measurements(s)[1].outcome
            @test o == (rand(MersenneTwister(seed)) < 0.5 ? 0 : 1)
            push!(outcomes, o)
        end
        # frequency sanity: 100 fair coins, mean well inside (0.35, 0.65)
        @test 0.35 < sum(outcomes) / length(outcomes) < 0.65
    end

    # --- (c) Post-measurement certainty + normalization -----------------------
    @testset "(c) post-measurement state [$backend]" for backend in _BM_BACKENDS
        tol = backend === :mps ? 1e-10 : 1e-12
        for seed in (3, 17, 99)
            st = _bm_state(backend; L = 4, seeds = (seed, seed + 1, seed + 2),
                log_events = true)
            _bm_entangle!(st, backend)
            apply!(st, Measure(:Z), SingleSite(2))
            o = measurements(st)[end].outcome
            # collapse ⇒ the measured site is CERTAIN in the obtained outcome
            @test abs(born_probability(st, 2, o) - 1.0) < tol
            @test abs(born_probability(st, 2, 1 - o) - 0.0) < tol
            # post-measurement state is normalized (tableau always is)
            if backend !== :clifford
                @test abs(_bm_norm(st, backend) - 1.0) < tol
            end
        end
    end

    # --- (d) Reset() ≡ Measure(:Z; feedback=OnOutcome(1 => PauliX())) --------
    @testset "(d) Reset ≡ Measure+feedback trajectories [$backend]" for backend in _BM_BACKENDS
        for seed in 1:10
            seeds = (seed, seed + 100, seed + 200)
            st1 = _bm_state(backend; L = 4, seeds = seeds, log_events = true)
            st2 = _bm_state(backend; L = 4, seeds = seeds, log_events = true)
            _bm_entangle!(st1, backend)
            _bm_entangle!(st2, backend)
            apply!(st1, Reset(), AllSites())
            apply!(st2, Measure(:Z; feedback = OnOutcome(1 => PauliX())), AllSites())
            # identical measurement-outcome sequence
            @test [m.outcome for m in measurements(st1)] ==
                  [m.outcome for m in measurements(st2)]
            # identical final Born probabilities on every site (all reset to |0⟩)
            for i in 1:4
                @test isapprox(born_probability(st1, i, 0),
                    born_probability(st2, i, 0); atol = 1e-14)
                @test abs(born_probability(st1, i, 0) - 1.0) < 1e-10
            end
            # identical :born_measurement stream position afterwards
            @test rand(copy(get_rng(st1.rng_registry, :born_measurement))) ==
                  rand(copy(get_rng(st2.rng_registry, :born_measurement)))
        end
    end

    # feedback fires on the CORRECT outcome on every backend (extends the
    # MPS-only checks in test/feedback.jl cross-backend)
    @testset "(d) feedback outcome dispatch [$backend]" for backend in _BM_BACKENDS
        # |1⟩ → outcome 1 → OnOutcome(1 => PauliX()) flips back to |0⟩
        st = _bm_state(backend; L = 2)
        apply!(st, PauliX(), SingleSite(1))
        apply!(st, Measure(:Z; feedback = OnOutcome(1 => PauliX())), SingleSite(1))
        @test born_probability(st, 1, 0) ≈ 1.0 atol=1e-12
        # |0⟩ → outcome 0 → no action registered for 0 → stays |0⟩
        st = _bm_state(backend; L = 2)
        apply!(st, Measure(:Z; feedback = OnOutcome(1 => PauliX())), SingleSite(1))
        @test born_probability(st, 1, 0) ≈ 1.0 atol=1e-12
        # |0⟩ → outcome 0 → OnOutcome(0 => PauliX()) fires → |1⟩
        st = _bm_state(backend; L = 2)
        apply!(st, Measure(:Z; feedback = OnOutcome(0 => PauliX())), SingleSite(1))
        @test born_probability(st, 1, 1) ≈ 1.0 atol=1e-12
        # closure feedback receives ([site], outcome)
        captured = Ref{Any}(nothing)
        st = _bm_state(backend; L = 2)
        apply!(st, PauliX(), SingleSite(2))
        apply!(st, Measure(:Z; feedback = (s, sites, o) -> (captured[] = (sites, o))),
            SingleSite(2))
        @test captured[] == ([2], 1)
    end

    # --- (e) deterministic measurement: draw-count invariant ------------------
    @testset "(e) deterministic measurement draw count [$backend]" for backend in
                                                                        (:mps, :statevector)
        # eigenstate |0⟩: outcome certain, yet exactly ONE Born draw consumed
        # (SCALAR-DRAW CONTRACT, src/Core/apply.jl `_measure_single_site!`)
        st = _bm_state(backend; L = 3, seeds = (1, 2, 33), log_events = true)
        apply!(st, Measure(:Z), SingleSite(1))
        @test measurements(st)[1].outcome == 0          # certain outcome
        @test _bm_stream_advanced_by(st, 33, 1)          # exactly one draw
        apply!(st, Measure(:Z), SingleSite(2))
        @test _bm_stream_advanced_by(st, 33, 2)          # one more
    end

    @testset "(e) Clifford draw count (documented divergence)" begin
        # AUDIT FINDING (documented behavior, src/Clifford/measurement.jl):
        # the Clifford override consumes NO Born draw when the measurement is
        # deterministic, and exactly one when undetermined. This DIVERGES from
        # the MPS/SV scalar-draw contract (one draw per measured site,
        # deterministic or not) — same seeds do NOT imply the same
        # :born_measurement stream position across backends once deterministic
        # measurements occur. Pinned here; recorded in the findings notepad.
        st = _bm_state(:clifford; L = 3, seeds = (1, 2, 33), log_events = true)
        apply!(st, Measure(:Z), SingleSite(1))           # deterministic (|0⟩)
        @test measurements(st)[1].outcome == 0
        @test _bm_stream_advanced_by(st, 33, 0)          # ZERO draws consumed
        apply!(st, Hadamard(), SingleSite(1))
        apply!(st, Measure(:Z), SingleSite(1))           # undetermined (50/50)
        @test _bm_stream_advanced_by(st, 33, 1)          # exactly one draw
    end

    # --- (f) S=1 spin measurement sanity --------------------------------------
    @testset "(f) S=1: single-site Measure works (categorical, T39)" begin
        # T39 resolved the former qubit-only limitation: per-level "Proj<k>"
        # ops now exist for spin site types, Projection accepts any level
        # index, and _measure_single_site! draws one categorical outcome.
        st = SimulationState(L = 4, bc = :open, site_type = "S=1", maxdim = 32,
            rng = RNGRegistry(gates_spacetime = 1, gates_realization = 2,
                born_measurement = 3))
        initialize!(st, ProductState(spin_state = "Z0"))
        @test born_probability(st, 1, 0) ≈ 0.0 atol=1e-12   # |Z0⟩ is level 1
        @test born_probability(st, 1, 1) ≈ 1.0 atol=1e-12
        apply!(st, Measure(:Z), SingleSite(1))               # deterministic: level 1
        @test born_probability(st, 1, 1) ≈ 1.0 atol=1e-12
        @test Projection(2) isa Projection    # level-2 projector valid for d ≥ 3
        @test_throws ArgumentError Projection(-1)            # negative still rejected
    end

    @testset "(f) S=1 SpinSectorMeasurement Born sampling" begin
        # |Z0,Z0⟩ = |1,0⟩⊗|1,0⟩ = √(2/3)|S=2,m=0⟩ − √(1/3)|S=0,m=0⟩
        # (Clebsch-Gordan) ⇒ P(S=0)=1/3, P(S=1)=0, P(S=2)=2/3.
        mkspin(seed) = begin
            s = SimulationState(L = 2, bc = :open, site_type = "S=1", maxdim = 32,
                rng = RNGRegistry(gates_spacetime = 1, gates_realization = 2,
                    born_measurement = seed))
            initialize!(s, ProductState(spin_state = "Z0"))
            s
        end
        sector_probs(s) = begin
            ram = [s.phy_ram[1], s.phy_ram[2]]
            [QuantumCircuitsMPS.compute_two_site_born_probability(
                 s.backend.mps, total_spin_projector(S), ram, 3) for S in 0:2]
        end

        # Born probabilities of the sectors: analytic values + normalization
        st0 = mkspin(1)
        ps = sector_probs(st0)
        @test abs(ps[1] - 1 / 3) < 1e-12   # S=0
        @test abs(ps[2] - 0.0) < 1e-12     # S=1
        @test abs(ps[3] - 2 / 3) < 1e-12   # S=2
        @test abs(sum(ps) - 1.0) < 1e-12   # Σ_S P(S) = 1

        # Sampled sector follows the :born_measurement stream (cumulative
        # sampling over sectors [0,1,2]: r < 1/3 → S=0, else S=2), the
        # post-measurement state lies in that sector with certainty, exactly
        # one Born draw is consumed, and the state is renormalized.
        for seed in 1:20
            s = mkspin(seed)
            r = rand(MersenneTwister(seed))
            expected_S = r < 1 / 3 ? 0 : 2
            apply!(s, SpinSectorMeasurement(), Sites([1, 2]))
            post = sector_probs(s)
            @test abs(post[expected_S + 1] - 1.0) < 1e-10
            @test abs(sum(post) - 1.0) < 1e-10
            @test abs(norm(s.backend.mps) - 1.0) < 1e-10
            @test _bm_stream_advanced_by(s, seed, 1)
        end

        # Restricted sectors renormalize over the allowed set:
        # SpinSectorMeasurement([0,1]) on |Z0,Z0⟩ → P(0)=1 after
        # renormalization over {0,1} (P(1)=0) → forced S=0, one draw consumed.
        for seed in (5, 6)
            s = mkspin(seed)
            apply!(s, SpinSectorMeasurement([0, 1]), Sites([1, 2]))
            post = sector_probs(s)
            @test abs(post[1] - 1.0) < 1e-10
            @test _bm_stream_advanced_by(s, seed, 1)
        end
    end
end
