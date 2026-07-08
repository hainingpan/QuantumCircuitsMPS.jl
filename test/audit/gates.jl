# test/audit/gates.jl
# T8 AUDIT — Gate definitions, projectors, Clifford semantics.
#
# Cross-checks that do NOT duplicate test/gates_v01.jl (construction, matrix
# element pinning, MatrixGate conventions) or test/gates/test_new_gates.jl
# (per-backend smoke tests, S²=Z, RandomClifford reproducibility on MPS/SV):
#   (a) unitarity U†U = I ± 1e-14 for every fixed gate matrix
#   (b) known identities: HZH = X, CNOT|+0⟩ = Bell, SWAP² = I, CZ = diag(1,1,1,−1)
#   (c) Rx/Ry/Rz convention R(θ) = exp(−iθP/2) pinned against the matrix exponential
#   (d) HaarRandom / RandomClifford statistical unitarity + determinism
#       under a fixed :gates_realization seed
#   (e) spin projectors: idempotent, orthogonal, complete, correct S₁·S₂
#       eigenvalues; SpinSectorProjection(P0+P1) annihilates S=2 states
#   (f) Clifford-vs-SV single-gate agreement (Born probabilities ± 1e-12)
#
# Findings recorded in .sisyphus/notepads/v04-findings.md (T8 section).

using Test
using QuantumCircuitsMPS
using LinearAlgebra
using Random
using Statistics
using ITensors
using ITensorMPS

const QCM = QuantumCircuitsMPS

# ── file-local helpers (audit-unique names: all test files share one scope) ──

_ag_seeds() = (gates_spacetime = 11, gates_realization = 13, born_measurement = 17)

function _ag_state(L::Int, backend::Symbol; seeds = _ag_seeds())
    state = SimulationState(L = L, bc = :open, backend = backend,
        rng = RNGRegistry(; seeds...))
    initialize!(state, ProductState(binary_int = 0))
    return state
end

# SV + Clifford pair with identical seeds (for category f)
_ag_pair(L::Int) = (_ag_state(L, :statevector), _ag_state(L, :clifford))

function _ag_compare_born(sv, cl, L; atol = 1e-12)
    for site in 1:L, outcome in 0:1
        @test born_probability(sv, site, outcome) ≈
              born_probability(cl, site, outcome) atol=atol
    end
end

@testset "AUDIT T8: gates / projectors / Clifford semantics" begin

    # ═══════════════════════════════════════════════════════════════════
    # (a) Unitarity U†U = I ± 1e-14 for every fixed gate matrix
    # ═══════════════════════════════════════════════════════════════════
    @testset "(a) unitarity of every fixed gate matrix" begin
        fixed_gates = [
            PauliX(), PauliY(), PauliZ(), Hadamard(), PhaseGate(),
            CZ(), CNOT(), SWAP(),
        ]
        for g in fixed_gates
            M = QCM.gate_matrix(g)
            N = size(M, 1)
            @test norm(M' * M - I(N)) < 1e-14
            @test norm(M * M' - I(N)) < 1e-14
        end

        # Parametrized rotations at several angles (incl. irrational-ish θ)
        for θ in (0.0, 0.3, π / 2, π, 2.1, 2π), G in (Rx, Ry, Rz)
            M = QCM.gate_matrix(G(θ))
            @test norm(M' * M - I(2)) < 1e-14
        end

        # MatrixGate: gate_matrix roundtrip preserves the supplied unitary
        rng_a = MersenneTwister(2026_07_07)
        U = QCM._haar_unitary(4, rng_a)
        @test QCM.gate_matrix(MatrixGate(U)) ≈ U atol=1e-15
        @test norm(QCM.gate_matrix(MatrixGate(U))' * QCM.gate_matrix(MatrixGate(U)) - I(4)) < 1e-13

        # Projection is intentionally NOT unitary — it is a projector:
        P0m = QCM.gate_matrix(Projection(0))
        P1m = QCM.gate_matrix(Projection(1))
        @test P0m * P0m ≈ P0m atol=1e-15          # idempotent
        @test P1m * P1m ≈ P1m atol=1e-15
        @test P0m' ≈ P0m atol=1e-15               # Hermitian
        @test P1m' ≈ P1m atol=1e-15
        @test P0m + P1m ≈ I(2) atol=1e-15         # complete
        @test norm(P0m * P1m) < 1e-15             # orthogonal
        @test QCM.needs_normalization(Projection(0))  # projector shrinks norm
    end

    # ═══════════════════════════════════════════════════════════════════
    # (b) Known identities
    # ═══════════════════════════════════════════════════════════════════
    @testset "(b) known gate identities" begin
        Xm = QCM.gate_matrix(PauliX())
        Ym = QCM.gate_matrix(PauliY())
        Zm = QCM.gate_matrix(PauliZ())
        Hm = QCM.gate_matrix(Hadamard())
        Sm = QCM.gate_matrix(PhaseGate())

        # HZH = X and HXH = Z (Hadamard conjugation swaps X ↔ Z)
        @test Hm * Zm * Hm ≈ Xm atol=1e-14
        @test Hm * Xm * Hm ≈ Zm atol=1e-14
        # H² = I, S² = Z (matrix level), XYZ phase algebra: XY = iZ
        @test Hm * Hm ≈ I(2) atol=1e-14
        @test Sm * Sm ≈ Zm atol=1e-14
        @test Xm * Ym ≈ im * Zm atol=1e-14

        # CZ is exactly diag(1, 1, 1, −1) and symmetric under qubit exchange
        CZm = QCM.gate_matrix(CZ())
        @test CZm == Matrix(Diagonal(ComplexF64[1, 1, 1, -1]))
        SWAPm = QCM.gate_matrix(SWAP())
        @test SWAPm * CZm * SWAPm ≈ CZm atol=1e-14

        # SWAP² = I
        @test SWAPm * SWAPm ≈ I(4) atol=1e-14

        # CNOT|+0⟩ = Bell. Kron convention (matrix_gate.jl): FIRST site is the
        # SLOWEST digit, so |+0⟩ = kron(|+⟩, |0⟩); control = first site.
        CNOTm = QCM.gate_matrix(CNOT())
        plus = ComplexF64[1, 1] ./ sqrt(2)
        zero_ = ComplexF64[1, 0]
        bell = ComplexF64[1, 0, 0, 1] ./ sqrt(2)   # (|00⟩ + |11⟩)/√2
        @test CNOTm * kron(plus, zero_) ≈ bell atol=1e-14
        # CNOT control/target ordering: |10⟩ → |11⟩, |01⟩ → |01⟩ (control first)
        @test CNOTm * kron(ComplexF64[0, 1], zero_) ≈ kron(ComplexF64[0, 1], ComplexF64[0, 1]) atol=1e-14
        @test CNOTm * kron(zero_, ComplexF64[0, 1]) ≈ kron(zero_, ComplexF64[0, 1]) atol=1e-14

        # build_operator(CZ/CNOT/SWAP) hand-rolled ITensor loops agree with
        # the MatrixGate embedding of gate_matrix (two independent code paths)
        sites2 = siteinds("Qubit", 2)
        for g in (CZ(), CNOT(), SWAP())
            op_direct = QCM.build_operator(g, sites2, 2)
            op_ref = QCM.build_operator(MatrixGate(QCM.gate_matrix(g)), sites2, 2)
            ord = collect(inds(op_ref))
            @test Array(op_direct, ord...) ≈ Array(op_ref, ord...) atol=1e-15
        end
    end

    # ═══════════════════════════════════════════════════════════════════
    # (c) Rx/Ry/Rz rotation convention: R(θ) = exp(−iθP/2)
    #     Documented in src/Gates/parametrized.jl (docstrings + header) —
    #     convention is explicit, NOT silent. Pin implementation == docs.
    # ═══════════════════════════════════════════════════════════════════
    @testset "(c) rotation convention R(θ) = exp(−iθP/2)" begin
        Xm = QCM.gate_matrix(PauliX())
        Ym = QCM.gate_matrix(PauliY())
        Zm = QCM.gate_matrix(PauliZ())
        for θ in (0.3, π / 2, π, 2.1, 4.9)
            @test QCM.gate_matrix(Rx(θ)) ≈ exp(-im * θ / 2 .* Xm) atol=1e-14
            @test QCM.gate_matrix(Ry(θ)) ≈ exp(-im * θ / 2 .* Ym) atol=1e-14
            @test QCM.gate_matrix(Rz(θ)) ≈ exp(-im * θ / 2 .* Zm) atol=1e-14
        end
        # θ = π: R(π) = −iP (NOT +iP) under this convention
        @test QCM.gate_matrix(Rx(π)) ≈ -im .* Xm atol=1e-14
        @test QCM.gate_matrix(Ry(π)) ≈ -im .* Ym atol=1e-14
        @test QCM.gate_matrix(Rz(π)) ≈ -im .* Zm atol=1e-14
        # θ = 2π: R(2π) = −I (SU(2) double cover, pins global-phase choice)
        for G in (Rx, Ry, Rz)
            @test QCM.gate_matrix(G(2π)) ≈ -I(2) atol=1e-14
        end
    end

    # ═══════════════════════════════════════════════════════════════════
    # (d) HaarRandom / RandomClifford: statistical unitarity + determinism
    # ═══════════════════════════════════════════════════════════════════
    @testset "(d) random-gate sampling" begin
        @testset "HaarRandom determinism under fixed :gates_realization" begin
            reg1 = RNGRegistry(; _ag_seeds()...)
            reg2 = RNGRegistry(; _ag_seeds()...)
            U1 = QCM.gate_matrix(HaarRandom(2), get_rng(reg1, :gates_realization))
            U2 = QCM.gate_matrix(HaarRandom(2), get_rng(reg2, :gates_realization))
            @test U1 == U2                          # bitwise identical
            # a second draw from the SAME stream differs (stream advances)
            U3 = QCM.gate_matrix(HaarRandom(2), get_rng(reg1, :gates_realization))
            @test U3 != U1
        end

        @testset "HaarRandom statistical unitarity (CUE moments)" begin
            rng = MersenneTwister(424242)
            M = 500
            m11 = Float64[]
            m_entry = ComplexF64[]
            for _ in 1:M
                U = QCM.gate_matrix(HaarRandom(2), rng)
                @test norm(U' * U - I(4)) < 1e-12
                push!(m11, abs2(U[1, 1]))
                push!(m_entry, U[1, 1])
            end
            # CUE(N=4): E[|U₁₁|²] = 1/N = 0.25 (std of mean ≈ 0.009)
            @test mean(m11) ≈ 0.25 atol=0.03
            # E[U₁₁] = 0 (no phase bias from the QR + Λ correction)
            @test abs(mean(m_entry)) < 0.05
        end

        @testset "RandomClifford determinism + Clifford-ness of matrices" begin
            reg1 = RNGRegistry(; _ag_seeds()...)
            reg2 = RNGRegistry(; _ag_seeds()...)
            C1 = QCM.gate_matrix(RandomClifford(2), get_rng(reg1, :gates_realization))
            C2 = QCM.gate_matrix(RandomClifford(2), get_rng(reg2, :gates_realization))
            @test C1 == C2                          # same seed → same operator

            rng = MersenneTwister(31337)
            for _ in 1:20
                C = QCM.gate_matrix(RandomClifford(2), rng)
                @test norm(C' * C - I(4)) < 1e-12
                # Clifford columns are stabilizer states: every amplitude has
                # squared modulus in {0, 1/4, 1/2, 1} for 2 qubits
                for a in C
                    @test any(v -> abs(abs2(a) - v) < 1e-10, (0.0, 0.25, 0.5, 1.0))
                end
            end
        end
    end

    # ═══════════════════════════════════════════════════════════════════
    # (e) Spin projectors (S=1 ⊗ S=1 → 0 ⊕ 1 ⊕ 2)
    # ═══════════════════════════════════════════════════════════════════
    @testset "(e) spin sector projectors" begin
        # package-provided self-check (completeness/idempotence/orthogonality/traces)
        @test verify_spin_projectors()

        P0 = total_spin_projector(0)
        P1 = total_spin_projector(1)
        P2 = total_spin_projector(2)
        I9 = Matrix{Float64}(I, 9, 9)

        @testset "algebra: idempotent, orthogonal, complete, Hermitian" begin
            for P in (P0, P1, P2)
                @test norm(P * P - P) < 1e-12       # idempotent
                @test norm(P' - P) < 1e-12          # Hermitian
            end
            @test norm(P0 * P1) < 1e-12             # mutually orthogonal
            @test norm(P0 * P2) < 1e-12
            @test norm(P1 * P2) < 1e-12
            @test norm(P0 + P1 + P2 - I9) < 1e-12   # complete on 3 ⊗ 3
            @test tr(P0) ≈ 1 atol=1e-12             # sector dims 1/3/5
            @test tr(P1) ≈ 3 atol=1e-12
            @test tr(P2) ≈ 5 atol=1e-12
        end

        @testset "S₁·S₂ eigenvalues on each sector" begin
            # S₁·S₂ = [S(S+1) − s₁(s₁+1) − s₂(s₂+1)]/2 = (S(S+1) − 4)/2 on sector S
            S1S2 = QCM.s1_dot_s2()
            @test norm(S1S2 * P0 - (-2.0) * P0) < 1e-12   # S=0 → −2
            @test norm(S1S2 * P1 - (-1.0) * P1) < 1e-12   # S=1 → −1
            @test norm(S1S2 * P2 - (+1.0) * P2) < 1e-12   # S=2 → +1
            @test norm(S1S2' - S1S2) < 1e-12
        end

        @testset "SpinSectorProjection(P0+P1) annihilates the S=2 sector" begin
            P01 = P0 + P1
            g = SpinSectorProjection(P01)          # 9×9 validation passes
            @test QCM.support(g) == 2
            @test QCM.needs_normalization(g)
            @test norm(g.projector * P2) < 1e-12   # kills EVERY S=2 state
            # stretched state |m=1, m=1⟩ (basis index 1) is pure S=2:
            e11 = zeros(9); e11[1] = 1.0
            @test norm(P01 * e11) < 1e-12
            @test P2 * e11 ≈ e11 atol=1e-12
            # |m=0, m=0⟩ (basis index 5) has NO S=1 component (CG zero):
            e00 = zeros(9); e00[5] = 1.0
            @test norm(P1 * e00) < 1e-12
            @test e00' * P0 * e00 ≈ 1 / 3 atol=1e-12
            @test e00' * P2 * e00 ≈ 2 / 3 atol=1e-12
        end

        @testset "SpinSectorProjection behavioral: |00⟩ → singlet on MPS" begin
            state = SimulationState(L = 2, bc = :open, site_type = "S=1",
                maxdim = 16, rng = RNGRegistry(; _ag_seeds()...))
            initialize!(state, ProductState(spin_state = "Z0"))
            apply!(state, SpinSectorProjection(P0), AdjacentPair(1))
            # two-spin-1 singlet has three equal Schmidt values 1/3 → S = log₂3
            S = EntanglementEntropy(cut = 1, renyi_index = 1, base = 2)(state)
            @test S ≈ log2(3) atol=1e-10
        end

        @testset "constructor validation (SpinSectorProjection / SpinSectorMeasurement)" begin
            # T39: SpinSectorProjection now accepts any d²×d² matrix (4×4 =
            # two-qubit pairs is legal); non-square-of-a-square still rejected.
            @test_throws ArgumentError SpinSectorProjection(rand(5, 5))
            @test_throws ArgumentError total_spin_projector(3)  # S ≤ 2 for s=1
            @test_throws ArgumentError total_spin_projector(0; d = 2)  # d ≠ 2s+1 for s=1
            @test QCM.support(SpinSectorMeasurement([0, 1])) == 2
            @test QCM.is_measurement(SpinSectorMeasurement([0, 1]))
            # T39: sector upper bound is now checked at apply time (depends on
            # the state's spin); construction rejects only negative sectors.
            @test_throws ArgumentError SpinSectorMeasurement([-1])
            @test_throws ArgumentError SpinSectorMeasurement(Int[])
            @test_throws ArgumentError SpinSectorMeasurement([0, 1];
                feedback = OnOutcome(1 => PauliX()))
        end
    end

    # ═══════════════════════════════════════════════════════════════════
    # (f) Clifford-vs-SV single-gate agreement (Born probabilities ± 1e-12)
    # ═══════════════════════════════════════════════════════════════════
    @testset "(f) Clifford vs state-vector single-gate agreement" begin
        L = 3
        # Clifford-compatible state preps: |000⟩, basis-rotated, and Y-basis
        preps = [
            ("|000⟩", s -> nothing),
            ("H⊗H⊗H", s -> apply!(s, Hadamard(), AllSites())),
            ("H·S on site 1", s -> begin
                apply!(s, Hadamard(), SingleSite(1))
                apply!(s, PhaseGate(), SingleSite(1))
            end),
        ]

        @testset "1-qubit $gname on prep $pname" for (gname, gate) in [
                ("PauliX", PauliX()), ("PauliY", PauliY()), ("PauliZ", PauliZ()),
                ("Hadamard", Hadamard()), ("PhaseGate", PhaseGate()),
            ], (pname, prep!) in preps

            sv, cl = _ag_pair(L)
            prep!(sv); prep!(cl)
            apply!(sv, gate, SingleSite(1))
            apply!(cl, gate, SingleSite(1))
            _ag_compare_born(sv, cl, L)
        end

        @testset "2-qubit $gname on prep $pname" for (gname, gate) in [
                ("CZ", CZ()), ("CNOT", CNOT()), ("SWAP", SWAP()),
            ], (pname, prep!) in preps

            sv, cl = _ag_pair(L)
            prep!(sv); prep!(cl)
            apply!(sv, gate, AdjacentPair(1))
            apply!(cl, gate, AdjacentPair(1))
            _ag_compare_born(sv, cl, L)
        end

        @testset "CNOT control/target ordering (behavioral, SV + Clifford)" begin
            for backend in (:statevector, :clifford)
                # control set: |10⟩ → |11⟩
                s = _ag_state(2, backend)
                apply!(s, PauliX(), SingleSite(1))
                apply!(s, CNOT(), AdjacentPair(1))
                @test born_probability(s, 1, 1) ≈ 1.0 atol=1e-12
                @test born_probability(s, 2, 1) ≈ 1.0 atol=1e-12
                # target set, control clear: |01⟩ → |01⟩
                s2 = _ag_state(2, backend)
                apply!(s2, PauliX(), SingleSite(2))
                apply!(s2, CNOT(), AdjacentPair(1))
                @test born_probability(s2, 1, 0) ≈ 1.0 atol=1e-12
                @test born_probability(s2, 2, 1) ≈ 1.0 atol=1e-12
            end
        end

        @testset "RandomClifford single gate: same seed → same Born probs" begin
            sv, cl = _ag_pair(L)
            apply!(sv, RandomClifford(2), AdjacentPair(1))
            apply!(cl, RandomClifford(2), AdjacentPair(1))
            _ag_compare_born(sv, cl, L)
        end

        @testset "Measure / Reset deterministic collapse" begin
            # Measure(:Z) on |1⟩: outcome forced to 1, all three backends
            for backend in (:mps, :statevector, :clifford)
                s = _ag_state(2, backend)
                apply!(s, PauliX(), SingleSite(1))
                apply!(s, Measure(:Z), SingleSite(1))
                @test born_probability(s, 1, 1) ≈ 1.0 atol=1e-12
            end
            # Reset() on |1⟩: measure + flip back → |0⟩, all three backends
            for backend in (:mps, :statevector, :clifford)
                s = _ag_state(2, backend)
                apply!(s, PauliX(), SingleSite(1))
                apply!(s, Reset(), SingleSite(1))
                @test born_probability(s, 1, 0) ≈ 1.0 atol=1e-12
            end
        end

        @testset "non-Clifford gates rejected with informative error" begin
            for gate in (HaarRandom(), Rx(0.3), Ry(0.3), Rz(0.3),
                MatrixGate(ComplexF64[0 1; 1 0]), Projection(0))
                s = _ag_state(2, :clifford)
                geo = QCM.support(gate) == 1 ? SingleSite(1) : AdjacentPair(1)
                @test_throws ArgumentError apply!(s, gate, geo)
            end
        end
    end

    # ═══════════════════════════════════════════════════════════════════
    # ProductGate coverage: layer of PauliX flips every site
    # ═══════════════════════════════════════════════════════════════════
    @testset "ProductGate(PauliX, AllSites) flips all sites (MPS)" begin
        L = 4
        state = SimulationState(L = L, bc = :open, maxdim = 8,
            rng = RNGRegistry(; _ag_seeds()...))
        initialize!(state, ProductState(binary_int = 0))
        apply!(state, ProductGate(PauliX(), AllSites()))
        for site in 1:L
            @test born_probability(state, site, 1) ≈ 1.0 atol=1e-12
        end
    end

    # ═══════════════════════════════════════════════════════════════════
    # FINDING (T8, FIXED in T17): CZ/CNOT/SWAP build_operator methods took a
    # generic local_dim with NO local_dim == 2 guard (unlike Rx/Ry/Rz/
    # Hadamard, parametrized.jl:72-74) and silently built undocumented qudit
    # generalizations on S=1 sites (e.g. CNOT "flipped" the trit by reversal
    # iff control was |m=−1⟩ — NOT the standard qudit CNOT). T17 decision:
    # reject non-qubit sites with the same informative ArgumentError as
    # Rx/Ry/Rz (see _check_qubit_two_site, src/Gates/two_qubit.jl); T39 may
    # add principled qudit gates later.
    # ═══════════════════════════════════════════════════════════════════
    @testset "qubit two-site gates on spin-1 sites rejected (T17 fix)" begin
        s1_sites = siteinds("S=1", 2)
        for g in (CZ(), CNOT(), SWAP())
            @test try
                QCM.build_operator(g, s1_sites, 3)
                false                       # must not build silently
            catch e
                e isa ArgumentError         # rejects like Rx/Ry/Rz do
            end
        end
    end
end
