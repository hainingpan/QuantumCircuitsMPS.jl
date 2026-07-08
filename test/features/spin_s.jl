# === T39: Arbitrary spin-S support (init + ops + projectors, MPS & SV) ===
#
# Covers:
#   (a) S=3/2 and S=2 init at every Z-level; Magnetization eigenvalues −S..S
#   (b) projector algebra for s = 1/2, 1, 3/2, 2 (±1e-13)
#   (c) singlet-projector sanity (rank 1, trace 1)
#   (d) spin-3/2 two-site MatrixGate(U; d=4) + entropy MPS-vs-SV (±1e-10)
#   (e) categorical Measure(:Z) on S=3/2 and S=1 (Born stats, collapse)
#   (f) qubit REGRESSION: categorical draw reduces bitwise to the old binary
#       draw at d=2 (identical outcomes AND identical post-measurement states)

using Test
using QuantumCircuitsMPS
using LinearAlgebra
using Random

const QCMS = QuantumCircuitsMPS

function _spin_rng(; born = 3)
    RNGRegistry(
        gates_spacetime = 1, gates_realization = 2, born_measurement = born)
end

# Deterministic Haar-like unitary of size N (seeded; only MPS-vs-SV agreement
# within a run matters, not cross-version stream stability)
function _rand_unitary(N::Int, seed::Int)
    rng = MersenneTwister(seed)
    A = randn(rng, ComplexF64, N, N)
    Q = Matrix(qr(A).Q)
    return Q
end

@testset "T39 arbitrary spin-S" begin

    # ------------------------------------------------------------------
    # (a) init at every Z-level + Magnetization eigenvalues, MPS + SV
    # ------------------------------------------------------------------
    @testset "(a) Z-level init + Magnetization: $st_str on $backend" for st_str in (
            "S=3/2", "S=2"),
        backend in (:mps, :statevector)

        s = QCMS._parse_spin_site_type(st_str)
        d = Int(2s + 1)
        for k in 0:(d - 1)
            m = s - k
            label = "Z" * QCMS._spin_m_label(m)
            state = SimulationState(L = 3, bc = :open, site_type = st_str,
                backend = backend, maxdim = 16, rng = _spin_rng())
            @test state.local_dim == d
            initialize!(state, ProductState(spin_state = label))
            @test Magnetization(:Z)(state)≈Float64(m) atol=1e-12
            # per-site Born probability concentrated on level k
            @test born_probability(state, 2, k)≈1.0 atol=1e-12
        end

        # binary bit-pattern init addresses the extremal levels: 0→m=+S, 1→m=−S
        state0 = SimulationState(L = 2, bc = :open, site_type = st_str,
            backend = backend, maxdim = 16, rng = _spin_rng())
        initialize!(state0, ProductState(binary_int = 0))
        @test Magnetization(:Z)(state0)≈Float64(s) atol=1e-12
        state1 = SimulationState(L = 2, bc = :open, site_type = st_str,
            backend = backend, maxdim = 16, rng = _spin_rng())
        initialize!(state1, ProductState(bitstring = "11"))
        @test Magnetization(:Z)(state1)≈-Float64(s) atol=1e-12
    end

    @testset "(a) S=1 Magnetization fixed on MPS (T9 bug)" begin
        s1 = SimulationState(L = 4, bc = :open, site_type = "S=1", maxdim = 32,
            rng = _spin_rng())
        initialize!(s1, ProductState(spin_state = "Z0"))
        @test Magnetization(:Z)(s1)≈0.0 atol=1e-12
        # new uniform "Z<m>" labels also work on the native S=1 type
        s1b = SimulationState(L = 4, bc = :open, site_type = "S=1", maxdim = 32,
            rng = _spin_rng())
        initialize!(s1b, ProductState(spin_state = "Z-1"))
        @test Magnetization(:Z)(s1b)≈-1.0 atol=1e-12
    end

    # ------------------------------------------------------------------
    # (b) projector algebra for s = 1/2, 1, 3/2, 2
    # ------------------------------------------------------------------
    @testset "(b) total_spin_projector algebra s=$s" for s in (
        1 // 2, 1 // 1, 3 // 2, 2 // 1)
        d = Int(2s + 1)
        Smax = Int(2s)
        Ps = [total_spin_projector(S; s = s) for S in 0:Smax]
        Id = Matrix{Float64}(I, d^2, d^2)
        # completeness
        @test norm(sum(Ps) - Id) < 1e-13
        for (i, P) in enumerate(Ps)
            S = i - 1
            @test norm(P * P - P) < 1e-13            # idempotence
            @test abs(tr(P) - (2S + 1)) < 1e-13      # sector dimension
            @test norm(P - P') < 1e-13               # hermiticity
            for j in (i + 1):length(Ps)
                @test norm(P * Ps[j]) < 1e-13        # orthogonality
            end
        end
        @test verify_spin_projectors(; s = s, tol = 1e-12)
    end

    @testset "(b) S=1 regression: hardcoded path byte-identical + matches Lagrange" begin
        # default call (s=1) must remain the historical hardcoded polynomials
        for S in 0:2
            P_default = total_spin_projector(S)
            P_kw = total_spin_projector(S; s = 1, d = 3)
            @test P_default == P_kw   # exact equality (same code path)
        end
        # and the general Lagrange route agrees with them analytically:
        # rebuild via the same formula used for s≠1
        SS = QCMS._s_dot_s(1 // 1)
        λ(j) = (j * (j + 1) - 4.0) / 2
        for S in 0:2
            P_lag = Matrix{Float64}(I, 9, 9)
            for k in 0:2
                k == S && continue
                P_lag = P_lag * (SS - λ(k) * I) / (λ(S) - λ(k))
            end
            @test norm(P_lag - total_spin_projector(S)) < 1e-13
        end
    end

    @testset "(b) invalid arguments" begin
        @test_throws ArgumentError total_spin_projector(4; s = 3 // 2)  # S > 2s
        @test_throws ArgumentError total_spin_projector(0; s = 3 // 2, d = 3)  # d ≠ 2s+1
        @test_throws ArgumentError total_spin_projector(-1; s = 2)
        @test_throws ArgumentError QCMS.spin_operators(0)
        @test_throws ArgumentError QCMS.spin_operators(3 // 4)
    end

    # ------------------------------------------------------------------
    # (c) singlet projector: rank 1, trace 1 on s ⊗ s
    # ------------------------------------------------------------------
    @testset "(c) singlet projector rank/trace s=$s" for s in (
        1 // 2, 1 // 1, 3 // 2, 2 // 1)
        P0 = total_spin_projector(0; s = s)
        @test abs(tr(P0) - 1) < 1e-13
        @test rank(P0; atol = 1e-10) == 1
        # singlet eigenvalue of S₁·S₂ is λ₀ = −s(s+1)
        SS = QCMS._s_dot_s(Rational{Int}(s))
        λ0 = -Float64(s) * (Float64(s) + 1)
        @test norm(SS * P0 - λ0 * P0) < 1e-12
    end

    # ------------------------------------------------------------------
    # (d) spin-3/2 two-site MatrixGate(U; d=4): MPS vs SV agreement
    # ------------------------------------------------------------------
    @testset "(d) S=3/2 MatrixGate(U; d=4) + entropy MPS vs SV" begin
        U = _rand_unitary(16, 42)
        g = MatrixGate(U; d = 4)
        @test QCMS.support(g) == 2 && g.d == 4

        results = Dict{Symbol, Tuple{Float64, Float64, Vector{Float64}}}()
        for backend in (:mps, :statevector)
            state = SimulationState(L = 4, bc = :open, site_type = "S=3/2",
                backend = backend, maxdim = 64, rng = _spin_rng())
            initialize!(state, ProductState(spin_state = "Z1/2"))
            apply!(state, g, Sites([2, 3]))
            mz = Magnetization(:Z)(state)
            ee = EntanglementEntropy(cut = 2)(state)
            probs = [born_probability(state, 2, k) for k in 0:3]
            results[backend] = (mz, ee, probs)
        end
        mzA, eeA, pA = results[:mps]
        mzB, eeB, pB = results[:statevector]
        @test abs(mzA - mzB) <= 1e-10
        @test abs(eeA - eeB) <= 1e-10
        @test maximum(abs.(pA .- pB)) <= 1e-10
        @test eeA > 0.01   # the gate actually entangles across the cut
        @test sum(pA)≈1.0 atol=1e-10

        # MatrixGate dimension checks
        @test_throws ArgumentError MatrixGate(U; d = 5)         # 16 ≠ 5^n
        @test_throws ArgumentError MatrixGate(U; d = 1)         # d ≥ 2
        @test MatrixGate(U).d == 2                              # inference: 2^4
        @test MatrixGate(_rand_unitary(3, 1); d = 3).n == 1     # explicit d unlocks 3×3
        @test_throws ArgumentError MatrixGate(_rand_unitary(3, 1))  # inference: rejected
    end

    # ------------------------------------------------------------------
    # (e) categorical Measure(:Z) on spin sites
    # ------------------------------------------------------------------
    @testset "(e) Measure(:Z) on S=3/2: outcomes, Born stats, collapse" begin
        U = _rand_unitary(16, 7)
        g = MatrixGate(U; d = 4)

        # reference Born distribution at site 1 (no measurement)
        ref = SimulationState(L = 2, bc = :open, site_type = "S=3/2",
            backend = :statevector, rng = _spin_rng())
        initialize!(ref, ProductState(spin_state = "Z1/2"))
        apply!(ref, g, Sites([1, 2]))
        p_ref = [born_probability(ref, 1, k) for k in 0:3]
        @test sum(p_ref)≈1.0 atol=1e-12

        counts = zeros(Int, 4)
        n_traj = 400
        for t in 1:n_traj
            st = SimulationState(L = 2, bc = :open, site_type = "S=3/2",
                backend = :statevector, rng = _spin_rng(born = 1000 + t),
                log_events = true)
            initialize!(st, ProductState(spin_state = "Z1/2"))
            apply!(st, g, Sites([1, 2]))
            apply!(st, Measure(:Z), SingleSite(1))
            outcome = only(QCMS.measurements(st)).outcome
            @test outcome in 0:3
            counts[outcome + 1] += 1
            # post-measurement certainty
            @test born_probability(st, 1, outcome)≈1.0 atol=1e-10
        end
        emp = counts ./ n_traj
        @test maximum(abs.(emp .- p_ref)) < 0.1   # loose Born-statistics sanity

        # same born seed ⇒ same outcome on MPS and SV
        outs = Int[]
        for backend in (:mps, :statevector)
            st = SimulationState(L = 2, bc = :open, site_type = "S=3/2",
                backend = backend, maxdim = 32, rng = _spin_rng(born = 99),
                log_events = true)
            initialize!(st, ProductState(spin_state = "Z1/2"))
            apply!(st, g, Sites([1, 2]))
            apply!(st, Measure(:Z), SingleSite(1))
            push!(outs, only(QCMS.measurements(st)).outcome)
        end
        @test outs[1] == outs[2]
    end

    @testset "(e) Measure(:Z) on S=1 now works (was impossible pre-T39)" begin
        for backend in (:mps, :statevector)
            st = SimulationState(L = 3, bc = :open, site_type = "S=1",
                backend = backend, maxdim = 16, rng = _spin_rng(), log_events = true)
            initialize!(st, ProductState(spin_state = "Z0"))
            apply!(st, Measure(:Z), SingleSite(2))
            m = only(QCMS.measurements(st))
            @test m.outcome == 1                        # |Z0⟩ is level 1, deterministic
            @test born_probability(st, 2, 1)≈1.0 atol=1e-12
        end
    end

    @testset "(e) Measure(:Z) on S=2 (5 outcomes)" begin
        U = _rand_unitary(25, 11)
        g = MatrixGate(U; d = 5)
        st = SimulationState(L = 2, bc = :open, site_type = "S=2",
            backend = :statevector, rng = _spin_rng(born = 5), log_events = true)
        initialize!(st, ProductState(spin_state = "Z0"))
        apply!(st, g, Sites([1, 2]))
        apply!(st, Measure(:Z), SingleSite(1))
        outcome = only(QCMS.measurements(st)).outcome
        @test outcome in 0:4
        @test born_probability(st, 1, outcome)≈1.0 atol=1e-10
    end

    # ------------------------------------------------------------------
    # SpinSectorProjection generalization (d²×d²) + Clifford rejection
    # ------------------------------------------------------------------
    @testset "SpinSectorProjection d²×d² + spin-3/2 AKLT-style projection" begin
        # spin-3/2 pair: project out the top S=3 sector
        P012 = sum(total_spin_projector(S; s = 3 // 2) for S in 0:2)
        gate = SpinSectorProjection(P012)
        results = Float64[]
        for backend in (:mps, :statevector)
            st = SimulationState(L = 2, bc = :open, site_type = "S=3/2",
                backend = backend, maxdim = 32, rng = _spin_rng())
            initialize!(st, ProductState(bitstring = "01"))     # |+3/2, −3/2⟩
            apply!(st, gate, Sites([1, 2]))
            push!(results, Magnetization(:Z)(st))
        end
        @test abs(results[1] - results[2]) <= 1e-10
        # old 9×9-only guard is gone, but non-d² sizes still rejected
        @test_throws ArgumentError SpinSectorProjection(rand(5, 5))
        # size-vs-state mismatch rejected at apply time
        st = SimulationState(L = 2, bc = :open, site_type = "S=1", maxdim = 16,
            rng = _spin_rng())
        initialize!(st, ProductState(spin_state = "Z0"))
        @test_throws ArgumentError apply!(st, gate, Sites([1, 2]))  # 16×16 on d=3
    end

    @testset "Clifford backend rejects spin sites" begin
        err = try
            SimulationState(L = 4, bc = :open, site_type = "S=3/2",
                backend = :clifford, rng = _spin_rng())
            nothing
        catch e
            e
        end
        @test err isa ArgumentError
        @test occursin("qubit", err.msg)
        @test occursin("S=3/2", err.msg)
    end

    # ------------------------------------------------------------------
    # (f) qubit REGRESSION: categorical draw ≡ old binary draw at d=2
    # ------------------------------------------------------------------
    @testset "(f) qubit bitwise regression: $backend" for backend in (:mps, :statevector)
        L = 6
        function mk(; log = false)
            st = SimulationState(L = L, bc = :open, backend = backend, maxdim = 64,
                rng = RNGRegistry(gates_spacetime = 21, gates_realization = 22,
                    born_measurement = 23), log_events = log)
            initialize!(st, ProductState(binary_int = 0))
            apply!(st, HaarRandom(), Bricklayer(:odd))
            apply!(st, HaarRandom(), Bricklayer(:even))
            st
        end

        # NEW path: categorical _measure_single_site! via Measure(:Z)
        sA = mk(log = true)
        for site in 1:L
            apply!(sA, Measure(:Z), SingleSite(site))
        end
        outcomesA = [m.outcome for m in QCMS.measurements(sA)]

        # OLD path replayed verbatim: p₀ then one binary draw then Projection
        sB = mk()
        outcomesB = Int[]
        for site in 1:L
            p_0 = born_probability(sB, site, 0)
            rng_b = get_rng(sB.rng_registry, :born_measurement)
            outcome = rand(rng_b) < p_0 ? 0 : 1
            QCMS._apply_single!(sB, Projection(outcome), [site])
            push!(outcomesB, outcome)
        end

        @test outcomesA == outcomesB   # identical trajectory, bit for bit

        # identical post-measurement states (exact float equality, no atol)
        if backend == :statevector
            @test sA.backend.ψ == sB.backend.ψ
        else
            pA = [born_probability(sA, i, 1) for i in 1:L]
            pB = [born_probability(sB, i, 1) for i in 1:L]
            @test pA == pB
        end

        # Magnetization qubit semantics untouched: ⟨Z⟩ = ±1 eigenvalues
        mzA = Magnetization(:Z)(sA)
        @test mzA≈(L - 2 * sum(outcomesA)) / L atol=1e-10
    end
end
