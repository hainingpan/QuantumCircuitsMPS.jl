# === T38: Common observables — Correlator, EntropyProfile,
#          TripartiteMutualInformation, MagnetizationFluctuations ===
#
# All four are COMPOSITIONS of existing per-backend building blocks
# (PauliString, EntanglementEntropy, MutualInformation), so a single generic
# method serves all three backends.
#
# Analytic anchors (derived; see .sisyphus/notepads/v04-findings.md T38 entry):
#   - Correlator (connected): product Z-basis state → C(Z;i,j) = 0
#     (⟨ZᵢZⱼ⟩ = ⟨Zᵢ⟩⟨Zⱼ⟩ exactly); Bell on (1,2) → C(Z;1,2) = 1 − 0·0 = 1,
#     and C(X;1,2) = 1 as well (⟨XX⟩ = +1, ⟨X⟩ = 0).
#   - EntropyProfile: GHZ(L), bc=:open → S(cut=x) = log 2 for EVERY cut x
#     (tracing either side always leaves ½(|0…0⟩⟨0…0| + |1…1⟩⟨1…1|)); flat
#     stabilizer spectrum ⇒ every renyi_index gives the same profile.
#   - TMI, GHZ(8), A=1:2, B=3:4, C=5:6 (D=7:8 TRACED — four quarters, the
#     standard MIPT partition): every nonempty proper GHZ subset has S = log 2,
#     so I(A:B) = I(A:C) = I(A:BC) = log2 + log2 − log2 = log 2, hence
#     I₃ = log2 + log2 − log2 = +log 2. (NOT the equal-thirds-of-everything
#     case, which is ≡ 0 for ANY pure state — checked separately below as a
#     consistency identity, not as the discriminating anchor.)
#   - VarM, GHZ(6), R=1:6: ⟨ZᵢZⱼ⟩ = 1 for all i≠j (30 ordered pairs) and
#     ⟨Zᵢ⟩ = 0, so Var = |R| + Σ_{i≠j}⟨ZᵢZⱼ⟩ − (Σ⟨Zᵢ⟩)² = 6 + 30 − 0 = 36.
#     Subregion R=1:3 of the same GHZ: Var = 3 + 6 − 0 = 9.
#
# BC note: every cross-backend comparison uses bc=:open — under PBC the MPS
# EntanglementEntropy `cut` is a RAM-bond index of the folded MPS, not the
# physical bipartition SV/Clifford use (T6 audit finding).

using Test
using QuantumCircuitsMPS
using ITensors: ITensors

function _co_state(backend::Symbol, L::Int; maxdim = 64)
    state = SimulationState(L = L, bc = :open, backend = backend,
        maxdim = maxdim,
        rng = RNGRegistry(gates_spacetime = 21, gates_realization = 22,
            born_measurement = 23))
    initialize!(state, ProductState(binary_int = 0))
    return state
end

# GHZ(L) = (|0…0⟩ + |1…1⟩)/√2 via H + CNOT chain (Clifford-compatible).
function _co_ghz(backend::Symbol, L::Int)
    state = _co_state(backend, L)
    apply!(state, Hadamard(), SingleSite(1))
    for i in 1:(L - 1)
        apply!(state, CNOT(), Sites([i, i + 1]))
    end
    return state
end

# Deterministic entangling Clifford circuit (no RNG streams consumed) for
# cross-backend agreement on a non-trivial state.
function _co_scrambled(backend::Symbol, L::Int)
    state = _co_state(backend, L)
    for i in 1:L
        apply!(state, Hadamard(), SingleSite(i))
    end
    for pass in 1:2
        for i in 1:(L - 1)
            apply!(state, CNOT(), Sites([i, i + 1]))
        end
        apply!(state, PhaseGate(), SingleSite(1 + (pass % L)))
        apply!(state, CZ(), Sites([1, 2]))
    end
    return state
end

@testset "FEATURE common observables (T38)" begin

    # ---------------------------------------------------------------- Correlator
    @testset "Correlator: analytic anchors on all backends" begin
        for backend in (:mps, :statevector, :clifford)
            tol = backend === :mps ? 1e-8 : 1e-12

            # Product state |0100⟩: connected correlator vanishes exactly
            prod_state = _co_state(backend, 4)
            apply!(prod_state, PauliX(), SingleSite(2))
            @test abs(Correlator(1 => :Z, 2 => :Z)(prod_state)) < tol
            @test abs(Correlator(2 => :Z, 4 => :Z)(prod_state)) < tol

            # Bell on (1,2): C(Z;1,2) = ⟨ZZ⟩ − ⟨Z⟩⟨Z⟩ = 1 − 0 = 1; C(X) too
            bell = _co_state(backend, 4)
            apply!(bell, Hadamard(), SingleSite(1))
            apply!(bell, CNOT(), Sites([1, 2]))
            @test isapprox(Correlator(1 => :Z, 2 => :Z)(bell), 1.0; atol = tol)
            @test isapprox(Correlator(1 => :X, 2 => :X)(bell), 1.0; atol = tol)
            # Unentangled pair (3,4) stays uncorrelated
            @test abs(Correlator(3 => :Z, 4 => :Z)(bell)) < tol

            # Composition identity: Correlator == PauliString-composed value
            scr = _co_scrambled(backend, 6)
            direct = PauliString(2 => :Z, 5 => :Z)(scr) -
                     PauliString(2 => :Z)(scr) * PauliString(5 => :Z)(scr)
            @test isapprox(Correlator(2 => :Z, 5 => :Z)(scr), direct; atol = 1e-13)
        end
    end

    # ------------------------------------------------------------ EntropyProfile
    @testset "EntropyProfile: GHZ(6) = log2 at every cut (bc=:open)" begin
        for backend in (:mps, :statevector, :clifford)
            tol = backend === :mps ? 1e-8 : 1e-12
            ghz = _co_ghz(backend, 6)
            prof = EntropyProfile()(ghz)
            @test prof isa Vector{Float64}
            @test length(prof) == 5
            @test all(abs.(prof .- log(2)) .< tol)
            # base=2 → 1 bit at every cut; flat GHZ spectrum ⇒ Rényi-2 identical
            @test all(abs.(EntropyProfile(base = 2)(ghz) .- 1.0) .< tol)
            @test all(abs.(EntropyProfile(renyi_index = 2)(ghz) .- log(2)) .< tol)
        end
    end

    @testset "EntropyProfile: cross-backend agreement (scrambled, bc=:open)" begin
        prof_sv = EntropyProfile(base = 2)(_co_scrambled(:statevector, 6))
        prof_mps = EntropyProfile(base = 2)(_co_scrambled(:mps, 6))
        prof_cl = EntropyProfile(base = 2)(_co_scrambled(:clifford, 6))
        @test maximum(abs.(prof_mps .- prof_sv)) < 1e-8
        @test maximum(abs.(prof_cl .- prof_sv)) < 1e-12
    end

    # ------------------------------------------- TripartiteMutualInformation
    @testset "TMI: GHZ(8) four quarters, D traced → I₃ = +log2" begin
        # The MPS I(A:BC) term contracts a 6-site two-block RDM whose
        # intermediate ITensor has 14 indices — legitimate (within the size
        # guard) but at ITensors' default warn-order threshold; raise it
        # locally so the test log stays clean.
        ITensors.set_warn_order(16)
        tmi = TripartiteMutualInformation(1:2, 3:4, 5:6)  # D = 7:8 traced out
        for backend in (:mps, :statevector, :clifford)
            tol = backend === :mps ? 1e-8 : 1e-12
            ghz = _co_ghz(backend, 8)
            @test isapprox(tmi(ghz), log(2); atol = tol)
            # bits
            @test isapprox(TripartiteMutualInformation(1:2, 3:4, 5:6; base = 2)(ghz),
                1.0; atol = tol)
        end
        ITensors.reset_warn_order()
    end

    @testset "TMI: pure-state identity — equal thirds of the WHOLE system ≡ 0" begin
        # For ANY pure state, A∪B∪C = everything ⇒ I₃ ≡ 0 identically
        # (consistency check only — it discriminates nothing).
        tmi_thirds = TripartiteMutualInformation(1:2, 3:4, 5:6)
        state = _co_state(:statevector, 6)
        for i in 1:5
            apply!(state, HaarRandom(2), AdjacentPair(i))  # Haar-evolved pure state
        end
        @test abs(tmi_thirds(state)) < 1e-10
        # And on the GHZ pure state as well
        @test abs(tmi_thirds(_co_ghz(:statevector, 6))) < 1e-12
    end

    # ------------------------------------------- MagnetizationFluctuations
    @testset "VarM: analytic anchors on all backends" begin
        for backend in (:mps, :statevector, :clifford)
            tol = backend === :mps ? 1e-8 : 1e-12

            # Product Z-basis state: M is sharp ⇒ Var = 0 (any Z pattern)
            prod_state = _co_state(backend, 6)
            apply!(prod_state, PauliX(), SingleSite(3))
            @test abs(MagnetizationFluctuations(1:6)(prod_state)) < tol

            # |0…0⟩ with axis=:X: ⟨Xᵢ⟩ = ⟨XᵢXⱼ⟩ = 0 ⇒ Var = |R|
            zeros_state = _co_state(backend, 4)
            @test isapprox(MagnetizationFluctuations(1:4; axis = :X)(zeros_state),
                4.0; atol = tol)

            # GHZ(6), R=1:6 → Var = 6 + 30 − 0 = 36 exactly
            ghz = _co_ghz(backend, 6)
            @test isapprox(MagnetizationFluctuations(1:6)(ghz), 36.0; atol = tol)
            # Subregion R=1:3 of the same GHZ → Var = 3 + 6 − 0 = 9
            @test isapprox(MagnetizationFluctuations(1:3)(ghz), 9.0; atol = tol)
            # Single site: Var = 1 − ⟨Z⟩² = 1 on GHZ
            @test isapprox(MagnetizationFluctuations(1)(ghz), 1.0; atol = tol)
        end
    end

    # ------------------------------------------------- track!/simulate! wiring
    @testset "track!/record!/simulate! integration (scalar + vector-valued)" begin
        L = 4
        circuit = Circuit(L = L, bc = :open) do c
            apply!(c, HaarRandom(), Bricklayer(:odd))
            apply!(c, HaarRandom(), Bricklayer(:even))
        end
        state = _co_state(:mps, L)
        track!(state, :czz => Correlator(1 => :Z, 2 => :Z))
        track!(state, :prof => EntropyProfile(base = 2))
        track!(state, :varM => MagnetizationFluctuations(1:L))
        simulate!(circuit, state; n_steps = 3, record_when = :every_step)

        @test length(state.observables[:czz]) == 3
        @test all(v -> v isa Float64, state.observables[:czz])
        @test length(state.observables[:varM]) == 3
        # Vector-valued recording (T37 storage widening): one profile per record
        @test length(state.observables[:prof]) == 3
        @test all(p -> p isa Vector{Float64} && length(p) == L - 1,
            state.observables[:prof])

        # TMI records through track!/record! too (eager form, GHZ anchor)
        ghz = _co_ghz(:statevector, 8)
        track!(ghz, :I3 => TripartiteMutualInformation(1:2, 3:4, 5:6))
        record!(ghz)
        @test isapprox(ghz.observables[:I3][end], log(2); atol = 1e-12)
    end

    # ---------------------------------------------------------- negative paths
    @testset "invalid constructions / regions rejected (negative)" begin
        # Correlator: i == j rejected (documented — no self-correlation)
        @test_throws ArgumentError Correlator(2 => :Z, 2 => :Z)
        @test_throws ArgumentError Correlator(1 => :Q, 2 => :Z)  # bad pauli
        @test_throws ArgumentError Correlator(0 => :Z, 2 => :Z)  # bad site

        # EntropyProfile: constructor validation + L=1 evaluation
        @test_throws ArgumentError EntropyProfile(renyi_index = 0)
        @test_throws ArgumentError EntropyProfile(base = -1.0)
        state1 = _co_state(:statevector, 1)
        @test_throws ArgumentError EntropyProfile()(state1)

        # TMI: overlap, non-adjacent B∪C, non-contiguous region, out of range
        @test_throws ArgumentError TripartiteMutualInformation(1:2, 2:3, 5:6)
        @test_throws ArgumentError TripartiteMutualInformation(1:2, 3:4, 6:7)
        @test_throws ArgumentError TripartiteMutualInformation([1, 3], 4:5, 6:7)
        tmi_big = TripartiteMutualInformation(1:2, 3:4, 5:6)
        @test_throws ArgumentError tmi_big(_co_state(:statevector, 4))  # C > L

        # VarM: bad axis, repeated/empty/invalid region, out of range at eval
        @test_throws ArgumentError MagnetizationFluctuations(1:4; axis = :Q)
        @test_throws ArgumentError MagnetizationFluctuations([1, 1, 2])
        @test_throws ArgumentError MagnetizationFluctuations(Int[])
        @test_throws ArgumentError MagnetizationFluctuations(0:2)
        vm = MagnetizationFluctuations(1:8)
        @test_throws ArgumentError vm(_co_state(:statevector, 4))  # site 8 > L=4
    end
end
