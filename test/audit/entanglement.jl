# test/audit/entanglement.jl
#
# AUDIT (T6): Entanglement entropy — analytic cross-checks on all 3 backends.
#
# What was reviewed (line-by-line, v0.4.0 audit):
#   - src/Observables/entanglement.jl (_von_neumann_entropy): Rényi formula
#     Sₙ = log_b(Σ pⁿ)/(1−n) with p = normalized squared singular values, and the
#     von Neumann limit S₁ = −Σ p log_b(p). VERIFIED correct. Threshold clamping
#     (max.(svals, 1e-16) then square + renormalize) contributes O(1e-32) per
#     clamped value — negligible; verified by product-state case (a) below.
#   - src/StateVector/entanglement.jl: reshape(ψ, (d^(L−cut), d^cut)) + svdvals.
#     Site 1 = most-significant digit (src/StateVector/initialization.jl), so the
#     column-major reshape groups sites {cut+1..L} into rows and {1..cut} into
#     columns; svdvals is transpose-invariant, so the Schmidt spectrum of the
#     {1..cut} bipartition is correct. VERIFIED — and PINNED by the asymmetric
#     Bell-pair placement checks in case (b), which would fail under a mirrored
#     (cut ↔ L−cut) reshape orientation.
#   - src/Clifford/entanglement.jl: QuantumClifford.entanglement_entropy(copy,
#     1:cut, Val(:rref)) returns bits; conversion k·log(2)/log(base) matches the
#     MPS/SV base convention. Flat-spectrum claim (all Rényi indices identical
#     for stabilizer states, Fattal et al.) VERIFIED by case (d).
#
# Known cross-backend semantics caveat, PINNED by case (f):
#   Under PBC the MPS backend's `cut` is the RAM bond index of the FOLDED MPS
#   (src/Observables/entanglement.jl:62-67; fold defined in src/Core/basis.jl,
#   pbc_fold_start = L÷4+1). For L=8 this gives ram_phy = [3,2,4,1,5,8,6,7], so
#   MPS cut=2 bipartitions the physical arc {2,3} vs the rest, whereas the
#   SV/Clifford backends bipartition {1,2} vs the rest for the same cut value.
#   Only cut = L÷2 is fold-aligned with the physical {1..L÷2} bipartition.
#   This is documented intended behavior of the MPS implementation, but it makes
#   `EntanglementEntropy(cut=k)` mean DIFFERENT physical bipartitions across
#   backends for PBC + k ≠ L÷2 — recorded as an audit finding (see
#   .sisyphus/notepads/v04-findings.md, "T6 Entanglement") and encoded as
#   @test_broken cross-backend equality below. Relevant for T38 (EntropyProfile).

using Test
using QuantumCircuitsMPS

# Exact backends (SV, Clifford): 1e-12. MPS (SVD/truncation at maxdim>=16): 1e-8.
_audit_ee_tol(backend::Symbol) = backend === :mps ? 1e-8 : 1e-12

function _audit_ee_state(backend::Symbol; L::Int, bc::Symbol = :open, maxdim::Int = 64)
    rng = RNGRegistry(gates_spacetime = 11, gates_realization = 12, born_measurement = 13)
    if backend === :mps
        SimulationState(L = L, bc = bc, maxdim = maxdim, rng = rng)
    else
        SimulationState(L = L, bc = bc, backend = backend, rng = rng)
    end
end

# Deterministic all-Clifford scrambling layer (works identically on all 3 backends)
function _audit_ee_scramble!(state, L::Int)
    apply!(state, Hadamard(), AllSites())
    for i in 1:2:(L - 1)
        apply!(state, CNOT(), Sites([i, i + 1]))
    end
    for i in 2:2:(L - 1)
        apply!(state, CZ(), Sites([i, i + 1]))
    end
    apply!(state, Hadamard(), SingleSite(1))
    for i in 1:2:(L - 1)
        apply!(state, CNOT(), Sites([i + 1, i]))
    end
    return state
end

@testset "AUDIT T6: entanglement entropy analytic cross-checks" begin
    backends = (:mps, :statevector, :clifford)

    # ------------------------------------------------------------------
    # (a) Product state → S = 0 exactly (every cut, several Rényi indices)
    # ------------------------------------------------------------------
    @testset "(a) product state S=0 [$b]" for b in backends
        tol = _audit_ee_tol(b)
        for binary_int in (0, 5)   # |0000⟩ and |0101⟩
            st = _audit_ee_state(b; L = 4)
            initialize!(st, ProductState(binary_int = binary_int))
            for cut in 1:3, n in (1, 2, 3)
                S = EntanglementEntropy(cut = cut, renyi_index = n)(st)
                @test abs(S) < tol
            end
        end
    end

    # ------------------------------------------------------------------
    # (b) Bell pair across the cut → S = log(2) in the chosen base.
    #     Placement asymmetry pins the SV reshape orientation (a mirrored
    #     cut ↔ L−cut bug would swap the 0/1 pattern below).
    # ------------------------------------------------------------------
    @testset "(b) Bell pair S=log(2) [$b]" for b in backends
        tol = _audit_ee_tol(b)

        # Bell on sites (1,2) of L=4: only cut=1 splits the pair
        st = _audit_ee_state(b; L = 4)
        initialize!(st, ProductState(binary_int = 0))
        apply!(st, Hadamard(), SingleSite(1))
        apply!(st, CNOT(), Sites([1, 2]))
        @test EntanglementEntropy(cut = 1, base = 2)(st) ≈ 1.0 atol=tol
        @test EntanglementEntropy(cut = 1, base = ℯ)(st) ≈ log(2) atol=tol
        @test abs(EntanglementEntropy(cut = 2, base = 2)(st)) < tol
        @test abs(EntanglementEntropy(cut = 3, base = 2)(st)) < tol

        # Bell on sites (3,4) of L=4: only cut=3 splits the pair
        st2 = _audit_ee_state(b; L = 4)
        initialize!(st2, ProductState(binary_int = 0))
        apply!(st2, Hadamard(), SingleSite(3))
        apply!(st2, CNOT(), Sites([3, 4]))
        @test abs(EntanglementEntropy(cut = 1, base = 2)(st2)) < tol
        @test abs(EntanglementEntropy(cut = 2, base = 2)(st2)) < tol
        @test EntanglementEntropy(cut = 3, base = 2)(st2) ≈ 1.0 atol=tol
    end

    # MPS truncation sanity: Bell pair needs bond dimension exactly 2, so
    # maxdim=2 and maxdim=16 must BOTH give log(2) — proves the 1e-8 MPS
    # tolerance validates physics, not truncation noise.
    @testset "(b) Bell pair MPS maxdim invariance" begin
        for maxdim in (2, 16)
            st = _audit_ee_state(:mps; L = 4, maxdim = maxdim)
            initialize!(st, ProductState(binary_int = 0))
            apply!(st, Hadamard(), SingleSite(1))
            apply!(st, CNOT(), Sites([1, 2]))
            @test EntanglementEntropy(cut = 1, base = 2)(st) ≈ 1.0 atol=1e-8
            @test EntanglementEntropy(cut = 1, base = ℯ)(st) ≈ log(2) atol=1e-8
        end
    end

    # ------------------------------------------------------------------
    # (c) GHZ(L=4): every cut gives exactly log(2)
    # ------------------------------------------------------------------
    @testset "(c) GHZ(4) S=log(2) at every cut [$b]" for b in backends
        tol = _audit_ee_tol(b)
        st = _audit_ee_state(b; L = 4)
        initialize!(st, ProductState(binary_int = 0))
        apply!(st, Hadamard(), SingleSite(1))
        apply!(st, CNOT(), Sites([1, 2]))
        apply!(st, CNOT(), Sites([2, 3]))
        apply!(st, CNOT(), Sites([3, 4]))
        for cut in 1:3
            @test EntanglementEntropy(cut = cut, base = 2)(st) ≈ 1.0 atol=tol
            @test EntanglementEntropy(cut = cut, base = ℯ)(st) ≈ log(2) atol=tol
        end
    end

    # ------------------------------------------------------------------
    # (d) Stabilizer flat spectrum: all Rényi indices identical.
    #     Verified on Clifford (exact) AND on MPS/SV for the same stabilizer
    #     state (their generic Rényi formulas must reproduce flatness).
    # ------------------------------------------------------------------
    @testset "(d) flat spectrum: Rényi 1,2,3,5 identical [$b]" for b in backends
        tol = _audit_ee_tol(b)
        st = _audit_ee_state(b; L = 6)
        initialize!(st, ProductState(binary_int = 0))
        _audit_ee_scramble!(st, 6)
        for cut in 1:5
            vals = [EntanglementEntropy(cut = cut, renyi_index = n, base = 2)(st)
                    for n in (1, 2, 3, 5)]
            for v in vals[2:end]
                @test v ≈ vals[1] atol=tol
            end
            # Stabilizer-state entropies are integers in base 2
            @test vals[1] ≈ round(vals[1]) atol=tol
        end
    end

    # ------------------------------------------------------------------
    # (e) Rényi-2 of a Bell pair, analytic: p = {1/2, 1/2} ⇒
    #     S₂ = log_b(Σp²)/(1−2) = −log_b(1/2) = log_b(2). Flat spectrum also
    #     fixes S₃ = (1/(1−3))·log_b(2·(1/2)³) = log_b(2).
    # ------------------------------------------------------------------
    @testset "(e) Bell Rényi-2/3 analytic [$b]" for b in backends
        tol = _audit_ee_tol(b)
        st = _audit_ee_state(b; L = 4)
        initialize!(st, ProductState(binary_int = 0))
        apply!(st, Hadamard(), SingleSite(1))
        apply!(st, CNOT(), Sites([1, 2]))
        @test EntanglementEntropy(cut = 1, renyi_index = 2, base = 2)(st) ≈ 1.0 atol=tol
        @test EntanglementEntropy(cut = 1, renyi_index = 3, base = 2)(st) ≈ 1.0 atol=tol
        @test EntanglementEntropy(cut = 1, renyi_index = 2, base = ℯ)(st) ≈ log(2) atol=tol
    end

    # ------------------------------------------------------------------
    # (f) PBC/OBC cut-alignment sanity, MPS vs SV vs Clifford.
    # ------------------------------------------------------------------
    @testset "(f) OBC: identical circuit → identical entropy at every cut" begin
        L = 8
        states = Dict(b => _audit_ee_state(b; L = L, bc = :open) for b in backends)
        for st in values(states)
            initialize!(st, ProductState(binary_int = 0))
            _audit_ee_scramble!(st, L)
        end
        for cut in 1:(L - 1)
            S_sv = EntanglementEntropy(cut = cut, base = 2)(states[:statevector])
            S_cl = EntanglementEntropy(cut = cut, base = 2)(states[:clifford])
            S_mps = EntanglementEntropy(cut = cut, base = 2)(states[:mps])
            @test S_cl ≈ S_sv atol=1e-12
            @test S_mps ≈ S_sv atol=1e-8
        end
    end

    @testset "(f) PBC: cut=L÷2 is fold-aligned across backends" begin
        L = 8
        states = Dict(b => _audit_ee_state(b; L = L, bc = :periodic) for b in backends)
        for st in values(states)
            initialize!(st, ProductState(binary_int = 0))
            _audit_ee_scramble!(st, L)
        end
        cut = L ÷ 2
        S_sv = EntanglementEntropy(cut = cut, base = 2)(states[:statevector])
        S_cl = EntanglementEntropy(cut = cut, base = 2)(states[:clifford])
        S_mps = EntanglementEntropy(cut = cut, base = 2)(states[:mps])
        @test S_cl ≈ S_sv atol=1e-12
        @test S_mps ≈ S_sv atol=1e-8
    end

    @testset "(f) PBC: cut≠L÷2 — MPS RAM-bond vs physical bipartition (FINDING)" begin
        # Bell pair on PHYSICAL sites (1,2) of an L=8 PBC ring, rest |0⟩.
        #   SV/Clifford cut=2 → region {1,2} contains the whole Bell pair → S = 0.
        #   MPS cut=2 → RAM bond 2 of the folded MPS (ram_phy = [3,2,4,1,5,8,6,7])
        #     → physical region {2,3}, which SPLITS the Bell pair → S = 1.
        L = 8
        states = Dict(b => _audit_ee_state(b; L = L, bc = :periodic) for b in backends)
        for st in values(states)
            initialize!(st, ProductState(binary_int = 0))
            apply!(st, Hadamard(), SingleSite(1))
            apply!(st, CNOT(), Sites([1, 2]))
        end
        S_sv = EntanglementEntropy(cut = 2, base = 2)(states[:statevector])
        S_cl = EntanglementEntropy(cut = 2, base = 2)(states[:clifford])
        S_mps = EntanglementEntropy(cut = 2, base = 2)(states[:mps])

        # Pin the ACTUAL (documented) behavior of each backend:
        @test abs(S_sv) < 1e-12                # physical {1,2} vs rest
        @test abs(S_cl) < 1e-12                # physical {1,2} vs rest
        @test S_mps ≈ 1.0 atol=1e-8            # folded RAM {1,2} = physical {2,3}

        # The naive cross-backend expectation "same cut ⇒ same physical
        # bipartition" does NOT hold under PBC for cut ≠ L÷2:
        @test_broken S_mps ≈ S_sv atol=1e-8

        # Fold-aligned half-cut agrees even for this state (region {1,2,3,4}
        # contains the full Bell pair on every backend → S = 0):
        for b in backends
            @test abs(EntanglementEntropy(cut = 4, base = 2)(states[b])) < _audit_ee_tol(b)
        end
    end
end
