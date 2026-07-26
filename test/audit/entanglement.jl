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
#   .sisyphus/notepads/v04-findings.md, "T6 Entanglement"); each backend's
#   value is pinned EXACTLY in testset (f) below (cross-backend equality is
#   intentionally not asserted there). Relevant for T38 (EntropyProfile).

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
        # bipartition" does NOT hold under PBC for cut ≠ L÷2. The exact
        # per-backend pins above (S_sv = S_cl = 0, S_mps = 1) ARE the
        # documented contract; asserting S_mps ≈ S_sv here would be wrong
        # by design, so no cross-backend equality is tested at this cut.

        # Fold-aligned half-cut agrees even for this state (region {1,2,3,4}
        # contains the full Bell pair on every backend → S = 0):
        for b in backends
            @test abs(EntanglementEntropy(cut = 4, base = 2)(states[b])) < _audit_ee_tol(b)
        end
    end
end

# ======================================================================
# AUDIT (T6, region extension): EntanglementEntropy with a SITE REGION
# (`cut::Vector{Int}` / `cut::UnitRange`) on the three non-MPS backends.
#
# What is asserted here, and why it is the right analytic check:
#   - Region sites are PHYSICAL sites on every non-MPS backend (identity
#     phy_ram; see testset (f) above, which pins non-MPS `cut::Int` as a
#     PHYSICAL-site prefix under both OBC and PBC). A region is therefore
#     unambiguous under PBC, including wrapped regions like [L, 1] — in
#     contrast with the MPS RAM-bond `cut` caveat documented above.
#   - Cross-backend agreement is checked on an ALL-CLIFFORD circuit
#     (`_audit_ee_scramble!`), the only circuit both the dense state vector
#     and the stabilizer tableau can represent exactly. Any region-mapping
#     or spectrum bug in either backend breaks the equality.
#   - Gaussian: the audit suite has NO state-vector↔Gaussian cross-check
#     precedent (Gaussian-preserving circuits are not directly comparable to
#     the qubit backends' gate set here), so no new cross-backend machinery
#     is invented. Gaussian is validated INTERNALLY instead, via the two
#     properties that would break under a wrong region→Majorana mapping:
#     prefix equivalence (cut=k ≡ cut=1:k) and complement symmetry on a
#     pure state.
#   - MPS + region is pinned to throw `ArgumentError` — a permanent
#     regression pin so the MPS backend never silently starts accepting
#     regions (its bond-SVD `cut` has no region generalization).
# ======================================================================
@testset "AUDIT T6: region entanglement entropy (non-MPS backends)" begin
    region_backends = (:statevector, :clifford)

    # Same all-Clifford circuit on SV and Clifford, OBC and PBC.
    function _audit_region_pair(L::Int, bc::Symbol)
        states = Dict(b => _audit_ee_state(b; L = L, bc = bc) for b in region_backends)
        for st in values(states)
            initialize!(st, ProductState(binary_int = 0))
            _audit_ee_scramble!(st, L)
        end
        return states
    end

    # ------------------------------------------------------------------
    # (g) Cross-backend agreement SV ↔ Clifford on region entropies
    # ------------------------------------------------------------------
    @testset "(g) SV ≈ Clifford region entropy [bc=$bc]" for bc in (:open, :periodic)
        L = 6
        states = _audit_region_pair(L, bc)
        regions = Any[1:2,          # prefix (contiguous)
            2:3,                    # interior (contiguous)
            [1, 3],                 # non-contiguous
            [1, 3, 5],              # sparse non-contiguous
            [L, 1],                 # PBC-wrapped (well defined on both backends)
            [L - 1, L, 1, 2]]       # wider wrapped block
        for region in regions
            r = collect(region)
            S_sv = EntanglementEntropy(cut = r, base = 2)(states[:statevector])
            S_cl = EntanglementEntropy(cut = r, base = 2)(states[:clifford])
            @test S_cl ≈ S_sv atol=1e-10
            # base conversion agrees too (guards a log-base slip in one backend)
            @test EntanglementEntropy(cut = r, base = ℯ)(states[:clifford]) ≈
                  EntanglementEntropy(cut = r, base = ℯ)(states[:statevector]) atol=1e-10
            # stabilizer state ⇒ integer number of bits
            @test S_sv ≈ round(S_sv) atol=1e-10
        end
        # NON-VACUITY: the compared numbers are genuinely entangled, not two zeros.
        # A broken implementation returning 0 everywhere would pass the equalities
        # above but fails here.
        @test EntanglementEntropy(cut = [1, 3], base = 2)(states[:statevector]) > 0.5
        @test EntanglementEntropy(cut = [1, 3], base = 2)(states[:clifford]) > 0.5
        @test EntanglementEntropy(cut = [L, 1], base = 2)(states[:statevector]) > 0.5
    end

    # ------------------------------------------------------------------
    # (g) Prefix equivalence: cut=k (bipartition) ≡ cut=1:k (region)
    #     on ALL three non-MPS backends, OBC and PBC.
    # ------------------------------------------------------------------
    @testset "(g) prefix equivalence cut=k ≡ cut=1:k [$b, bc=$bc]" for b in region_backends,
        bc in (:open, :periodic)

        L = 6
        st = _audit_ee_state(b; L = L, bc = bc)
        initialize!(st, ProductState(binary_int = 0))
        _audit_ee_scramble!(st, L)
        for k in 1:(L - 1)
            @test EntanglementEntropy(cut = 1:k, base = 2)(st) ≈
                  EntanglementEntropy(cut = k, base = 2)(st) atol=1e-10
            @test EntanglementEntropy(cut = collect(1:k), base = ℯ)(st) ≈
                  EntanglementEntropy(cut = k, base = ℯ)(st) atol=1e-10
        end
        @test EntanglementEntropy(cut = 1:(L ÷ 2), base = 2)(st) > 0.5   # non-vacuous
    end

    @testset "(g) Gaussian prefix equivalence + complement symmetry [bc=$bc]" for bc in (:open, :periodic)
        L = 8
        st = _audit_ee_state(:gaussian; L = L, bc = bc)
        initialize!(st, ProductState(binary_int = 0))
        for _ in 1:10   # Gaussian-preserving entangler; global state stays PURE
            apply!(st, GaussianHaar(), Bricklayer(:odd))
            apply!(st, GaussianHaar(), Bricklayer(:even))
        end
        for k in 1:(L - 1)
            @test EntanglementEntropy(cut = 1:k, base = 2)(st) ≈
                  EntanglementEntropy(cut = k, base = 2)(st) atol=1e-10
        end
        # Complement symmetry S(A) = S(Ā) — the strongest available internal
        # check of the region → Majorana-index mapping.
        for A in ([1, 3], [2], 3:5, [1, 4, 7], [L, 1])
            Av = collect(A)
            @test EntanglementEntropy(cut = Av, base = 2)(st) ≈
                  EntanglementEntropy(cut = setdiff(1:L, Av), base = 2)(st) atol=1e-10
        end
        @test EntanglementEntropy(cut = [1, 3], base = 2)(st) > 0.5       # non-vacuous
        @test EntanglementEntropy(cut = 1:(L ÷ 2), base = 2)(st) > 0.5
    end

    # ------------------------------------------------------------------
    # (g) Complement symmetry on Haar-evolved (non-stabilizer) SV states.
    #     Fixed RNG seeds via _audit_ee_state ⇒ fully reproducible.
    # ------------------------------------------------------------------
    @testset "(g) SV Haar complement symmetry S(A) = S(Ā) [bc=$bc]" for bc in (:open, :periodic)
        L = 6
        st = _audit_ee_state(:statevector; L = L, bc = bc)
        initialize!(st, ProductState(binary_int = 0))
        for _ in 1:4
            apply!(st, HaarRandom(), Bricklayer(:odd))
            apply!(st, HaarRandom(), Bricklayer(:even))
        end
        for A in ([1, 3], [2], 3:4, [1, 4, 5], [L, 1], [2, 3, 5])
            Av = collect(A)
            SA = EntanglementEntropy(cut = Av, base = 2)(st)
            SB = EntanglementEntropy(cut = setdiff(1:L, Av), base = 2)(st)
            @test SA ≈ SB atol=1e-10
            # Rényi-2 obeys the same purity-based symmetry
            @test EntanglementEntropy(cut = Av, renyi_index = 2, base = 2)(st) ≈
                  EntanglementEntropy(cut = setdiff(1:L, Av), renyi_index = 2,
                base = 2)(st) atol=1e-10
        end
        # NON-VACUITY: a Haar-evolved state is generically volume-law entangled,
        # so these are not trivially-equal zeros.
        @test EntanglementEntropy(cut = [1, 3], base = 2)(st) > 0.5
    end

    # ------------------------------------------------------------------
    # (g) Rényi on a region: Bell pair, single-site region.
    #     Flat 2-level spectrum p = {1/2, 1/2} ⇒ Sₙ = log_b(2) for EVERY n.
    # ------------------------------------------------------------------
    @testset "(g) Bell single-site region: Rényi-n = 1 bit ∀n [$b]" for b in region_backends
        st = _audit_ee_state(b; L = 4)
        initialize!(st, ProductState(binary_int = 0))
        apply!(st, Hadamard(), SingleSite(1))
        apply!(st, CNOT(), Sites([1, 2]))
        apply!(st, Hadamard(), SingleSite(3))
        apply!(st, CNOT(), Sites([3, 4]))
        for n in (1, 2, 3)
            @test EntanglementEntropy(cut = [1], renyi_index = n, base = 2)(st) ≈
                  1.0 atol=1e-10
            @test EntanglementEntropy(cut = [2], renyi_index = n, base = 2)(st) ≈
                  1.0 atol=1e-10
            @test EntanglementEntropy(cut = [1], renyi_index = n, base = ℯ)(st) ≈
                  log(2) atol=1e-10
            # non-contiguous region splitting BOTH pairs ⇒ 2 bits
            @test EntanglementEntropy(cut = [1, 3], renyi_index = n, base = 2)(st) ≈
                  2.0 atol=1e-10
            # a whole pure sub-block ⇒ 0
            @test abs(EntanglementEntropy(cut = [1, 2], renyi_index = n,
                base = 2)(st)) < 1e-10
        end
    end

    # ------------------------------------------------------------------
    # (g) MPS rejection pin: the MPS backend must NEVER accept a region.
    # ------------------------------------------------------------------
    @testset "(g) MPS + region → ArgumentError (permanent pin)" begin
        for bc in (:open, :periodic)
            st = _audit_ee_state(:mps; L = 6, bc = bc)
            initialize!(st, ProductState(binary_int = 0))
            _audit_ee_scramble!(st, 6)
            @test_throws ArgumentError EntanglementEntropy(cut = [1, 2])(st)
            @test_throws ArgumentError EntanglementEntropy(cut = 2:3)(st)
            @test_throws ArgumentError EntanglementEntropy(cut = [6, 1])(st)
            @test_throws ArgumentError EntanglementEntropy(cut = [1, 3],
                renyi_index = 2)(st)
            # the Int path on the SAME state is unaffected
            @test EntanglementEntropy(cut = 3, base = 2)(st) isa Float64
        end
    end
end

# ======================================================================
# AUDIT (T4 follow-up): Gaussian Rényi-n entanglement entropy.
#
# What was reviewed:
#   - src/Gaussian/entanglement.jl (subsystem_entropy): the general-n branches
#     evaluate Sₙ = Σ ln(λⁿ + (1−λ)ⁿ)/(1−n)/2 over the occupation eigenvalues
#     λ = (1 − ξ)/2 of spec(iΓ_A), in a scale-before-overflow log domain with
#     the (1−n) division applied PER TERM. VERIFIED against the invariants
#     below; the pins here are the audit-level (cross-checked, backend-generic)
#     subset of the dedicated suite in test/gaussian/test_observables.jl.
#
# Two properties are pinned, chosen because each fails under a DIFFERENT
# plausible implementation error:
#   - prefix equivalence at n = 2 (cut=k ≡ cut=1:k) — fails if the region →
#     Majorana index mapping is not shared by both EE paths, or if only one of
#     the two paths forwards `renyi_index`.
#   - Majorana-chain odd-cut flat pin = ln(2)/2 for every n INCLUDING n = 2048
#     — fails (Inf/NaN) under a direct-power implementation, and fails
#     (DimensionMismatch or a wrong value) if odd-dimensional Γ_A is special-
#     cased instead of being handled by the per-eigenvalue sum.
# ======================================================================
@testset "AUDIT T6: (h) gaussian renyi" begin
    @testset "(h) Gaussian prefix equivalence at n=2 [bc=$bc]" for bc in (:open, :periodic)
        L = 8
        st = _audit_ee_state(:gaussian; L = L, bc = bc)
        initialize!(st, ProductState(binary_int = 0))
        for _ in 1:10   # Gaussian-preserving entangler; global state stays PURE
            apply!(st, GaussianHaar(), Bricklayer(:odd))
            apply!(st, GaussianHaar(), Bricklayer(:even))
        end
        for k in 1:(L - 1)
            @test EntanglementEntropy(cut = 1:k, renyi_index = 2, base = 2)(st) ≈
                  EntanglementEntropy(cut = k, renyi_index = 2, base = 2)(st) atol=1e-10
        end
        # Rényi-2 obeys complement symmetry on a pure state, exactly like S₁
        for A in ([1, 3], [2], 3:5, [L, 1])
            Av = collect(A)
            @test EntanglementEntropy(cut = Av, renyi_index = 2, base = 2)(st) ≈
                  EntanglementEntropy(cut = setdiff(1:L, Av), renyi_index = 2,
                base = 2)(st) atol=1e-10
        end
        # NON-VACUITY + strict Rényi ordering S₁ > S₂ (non-flat spectrum), which
        # a silent von-Neumann fallback would violate.
        @test EntanglementEntropy(cut = L ÷ 2, renyi_index = 2, base = 2)(st) > 0.5
        @test EntanglementEntropy(cut = L ÷ 2, renyi_index = 1, base = 2)(st) >
              EntanglementEntropy(cut = L ÷ 2, renyi_index = 2, base = 2)(st) + 1e-6
    end

    @testset "(h) Majorana-chain odd cut: Sₙ = ln(2)/2 ∀n incl. n=2048" begin
        L = 8
        st = SimulationState(L = L, bc = :open, backend = :gaussian,
            site_type = "Majorana",
            rng = RNGRegistry(gates_spacetime = 11, gates_realization = 12,
                born_measurement = 13))
        initialize!(st, ProductState(binary_int = 0))
        for n in (0.5, 1, 2, 5, 2048, floatmax(Float64))
            S = EntanglementEntropy(cut = 1, renyi_index = n, base = ℯ)(st)
            @test isfinite(S)
            @test S ≈ log(2) / 2 atol=1e-12
            @test EntanglementEntropy(cut = 1, renyi_index = n, base = 2)(st) ≈
                  0.5 atol=1e-12
        end
        # a WHOLE dimer (sites 1,2) is pure ⇒ zero at every n
        for n in (0.5, 2, 2048)
            @test abs(EntanglementEntropy(cut = [1, 2], renyi_index = n,
                base = ℯ)(st)) < 1e-12
        end
    end
end
