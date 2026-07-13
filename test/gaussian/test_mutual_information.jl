# === Gaussian backend: MutualInformation + TripartiteMutualInformation ===
# Tests for (mi::MutualInformation)(::SimulationState{GaussianBackend})
# (src/Gaussian/mutual_information.jl) and the composition-only
# TripartiteMutualInformation (NO Gaussian-specific TMI method exists —
# verified to work for free via MutualInformation dispatch).
#
# Conventions asserted here:
#   - log base: honors mi.base exactly like the other backends
#     (MutualInformation default base=ℯ → nats; base=2 → bits)
#   - arbitrary regions: non-contiguous / PBC-wrapped site subsets are
#     supported on the Gaussian backend ONLY; the MPS/SV/Clifford paths
#     still reject them at evaluation time (backward compat)
#   - straddling entangled pair: I = 2·log(2), cross-checked against T5's
#     exact density-matrix oracle at L=4
#   - TMI == S_A+S_B+S_C−S_AB−S_AC−S_BC+S_ABC from subsystem entropies

using Test
using QuantumCircuitsMPS
using LinearAlgebra: I, eigvals, Hermitian

const QCM = QuantumCircuitsMPS

# T5's exponential-cost exact oracle (test-only; L ≤ 5). Guarded so this file
# can be included in the same process as test_observables.jl (which also
# includes oracle.jl) without method-redefinition churn.
isdefined(@__MODULE__, :oracle_density_matrix) ||
    include(joinpath(@__DIR__, "oracle.jl"))

_mi_rng(k) = RNGRegistry(gates_spacetime = k, gates_realization = k + 10,
    born_measurement = k + 20, state_init = k + 30)

_mi_gauss(L, k; bc = :open) =
    SimulationState(L = L, bc = bc, backend = :gaussian, rng = _mi_rng(k))

"""
Givens rotation of angle θ on Majorana indices (p, p+1) by direct orthogonal
conjugation Γ ← R Γ Rᵀ (deterministic GaussianHaar-free entangler, same
helper as test_observables.jl). With p = 2i (straddling modes i and i+1) and
θ = π/2, modes i and i+1 form a maximally entangled pair.
"""
function _mi_givens!(state, p::Int, θ::Real)
    Γ = state.backend.corr
    n = size(Γ, 1)
    R = Matrix{Float64}(I, n, n)
    R[p, p] = cos(θ)
    R[p, p + 1] = -sin(θ)
    R[p + 1, p] = sin(θ)
    R[p + 1, p + 1] = cos(θ)
    Γ .= R * Γ * transpose(R)
    Γ .= (Γ .- transpose(Γ)) ./ 2
    return state
end

"""
Exact von Neumann entropy (nats) of the reduced density matrix of the
physical sites `keep` of an L-mode Gaussian state, via T5's density-matrix
oracle (msb order: site 1 = most significant bit, basis index (0-based) =
Σₛ nₛ·2^(L−s)). Exponential cost — L ≤ 5 only.
"""
function _oracle_subset_entropy(Γ, keep::Vector{Int}, L::Int)
    ρ = oracle_density_matrix(Γ)                      # 2^L × 2^L, msb order
    rest = [s for s in 1:L if !(s in keep)]
    m, nr = length(keep), length(rest)
    asm(a, c) = begin                                 # assemble full basis index
        idx = 0
        for (k, s) in enumerate(keep)
            idx |= ((a >> (m - k)) & 1) << (L - s)
        end
        for (k, s) in enumerate(rest)
            idx |= ((c >> (nr - k)) & 1) << (L - s)
        end
        idx
    end
    ρA = zeros(ComplexF64, 2^m, 2^m)
    for a in 0:(2^m - 1), b in 0:(2^m - 1), c in 0:(2^nr - 1)
        ρA[a + 1, b + 1] += ρ[asm(a, c) + 1, asm(b, c) + 1]
    end
    p = real.(eigvals(Hermitian(ρA)))
    return -sum(x <= 0 ? 0.0 : x * log(x) for x in p)
end

_oracle_mi(Γ, A, B, L) = _oracle_subset_entropy(Γ, A, L) +
                         _oracle_subset_entropy(Γ, B, L) -
                         _oracle_subset_entropy(Γ, sort(vcat(A, B)), L)

# Sorted Majorana indices of a physical-site collection (phy_ram-mapped).
_mi_maj(state, sites) = sort!(vcat([[2r - 1, 2r] for r in
    (state.phy_ram[s] for s in sites)]...))

@testset "Gaussian MutualInformation + TMI (T11)" begin

    @testset "product state: I(A:B) ≈ 0 for any disjoint A, B" begin
        L = 8
        for (k, bits) in enumerate(("00000000", "01011010", "11111111"))
            state = _mi_gauss(L, k)
            initialize!(state, ProductState(bitstring = bits))
            for (A, B) in ((1:2, 5:6), (1, 8), ([2, 3], [6, 7]),
                ([1, 4], [5, 8]), (3:5, 6:8))
                @test abs(MutualInformation(A, B)(state)) < 1e-12          # nats
                @test abs(MutualInformation(A, B; base = 2)(state)) < 1e-12 # bits
            end
        end
    end

    @testset "straddling entangled pair: I = 2·log(2), oracle cross-check" begin
        # L=4 vacuum, θ=π/2 Givens on Majoranas (4,5) — straddling modes 2|3,
        # i.e. exactly across the A=1:2 | B=3:4 boundary.
        L = 4
        state = _mi_gauss(L, 10)
        initialize!(state, ProductState(binary_int = 0))
        _mi_givens!(state, 4, π / 2)

        @test MutualInformation(1:2, 3:4)(state) ≈ 2 * log(2) atol = 1e-10  # nats
        @test MutualInformation(1:2, 3:4; base = 2)(state) ≈ 2.0 atol = 1e-10
        # single-site regions around the pair: S({2})=S({3})=log 2, S({2,3})=0
        @test MutualInformation(2, 3)(state) ≈ 2 * log(2) atol = 1e-10
        # spectator regions stay uncorrelated
        @test abs(MutualInformation(1, 4)(state)) < 1e-12

        # exact-ρ oracle cross-check (T5), same L=4 state
        Γ = state.backend.corr
        @test MutualInformation(1:2, 3:4)(state) ≈
              _oracle_mi(Γ, [1, 2], [3, 4], L) atol = 1e-10
        @test MutualInformation(2, 3)(state) ≈
              _oracle_mi(Γ, [2], [3], L) atol = 1e-10

        # generic angle θ=π/3 → partially entangled: oracle cross-check incl.
        # a NON-CONTIGUOUS region pair (only possible on the Gaussian backend)
        s2 = _mi_gauss(L, 11)
        initialize!(s2, ProductState(binary_int = 0))
        _mi_givens!(s2, 4, π / 3)
        _mi_givens!(s2, 2, 0.7)
        Γ2 = s2.backend.corr
        @test MutualInformation(1:2, 3:4)(s2) ≈
              _oracle_mi(Γ2, [1, 2], [3, 4], L) atol = 1e-10
        @test MutualInformation([1, 3], [2, 4])(s2) ≈
              _oracle_mi(Γ2, [1, 3], [2, 4], L) atol = 1e-10
    end

    @testset "random circuit: I ≥ 0, symmetric under A↔B, I = 2S(A) for complement" begin
        L = 8
        state = _mi_gauss(L, 20; bc = :periodic)
        initialize!(state, ProductState(binary_int = 0))
        for _ in 1:10
            apply!(state, GaussianHaar(), Bricklayer(:odd))
            apply!(state, GaussianHaar(), Bricklayer(:even))
        end
        for (A, B) in ((1:2, 5:6), (1:4, 5:8), (1, 5), ([1, 3], [6, 8]),
            (2:3, 6:7))
            IAB = MutualInformation(A, B)(state)
            @test IAB >= -1e-10                                   # non-negative
            @test IAB ≈ MutualInformation(B, A)(state) atol = 1e-12  # symmetric
        end
        # pure global state, B = complement(A) ⇒ I = 2·S(A)
        @test MutualInformation(1:4, 5:8)(state) ≈
              2 * EntanglementEntropy(cut = 4, base = ℯ)(state) atol = 1e-10
    end

    @testset "wrapped region (PBC): A={7,8,1,2} == cyclic relabeling of 1:4" begin
        L = 8
        state = _mi_gauss(L, 30; bc = :periodic)
        initialize!(state, ProductState(binary_int = 0))
        for _ in 1:8
            apply!(state, GaussianHaar(), Bricklayer(:odd))
            apply!(state, GaussianHaar(), Bricklayer(:even))
        end
        A_wrap, B_mid = [7, 8, 1, 2], [3, 4, 5, 6]

        # (a) evaluates without error on the Gaussian backend
        I_wrap = MutualInformation(A_wrap, B_mid)(state)
        @test I_wrap isa Float64
        @test I_wrap >= -1e-10

        # (b) equals the unwrapped labeling after a manual cyclic relabeling:
        # relabel sites old → new = mod(old − 7, 8) + 1 (so old {7,8,1,2} →
        # new {1,2,3,4} and old {3,4,5,6} → new {5,6,7,8}), permute Γ's
        # Majorana rows/cols accordingly, and compare against plain 1:4 | 5:8.
        σ(old) = mod(old - 7, L) + 1
        P = zeros(Float64, 2L, 2L)
        for old in 1:L
            new = σ(old)
            P[2new - 1, 2old - 1] = 1.0
            P[2new, 2old] = 1.0
        end
        relabeled = _mi_gauss(L, 31; bc = :periodic)
        initialize!(relabeled, ProductState(binary_int = 0))   # allocate Γ
        relabeled.backend.corr .= P * state.backend.corr * transpose(P)
        I_unwrap = MutualInformation(1:4, 5:8)(relabeled)
        @test I_wrap ≈ I_unwrap atol = 1e-10

        # (c) backward compat: the SAME wrapped observable is rejected at
        # evaluation time on the generic (MPS) path — and on SV/Clifford too
        mi_wrap = MutualInformation(A_wrap, B_mid)   # constructs fine now
        for backend in (:mps, :statevector, :clifford)
            other = SimulationState(L = L, bc = :open, backend = backend,
                maxdim = 16, rng = _mi_rng(32))
            initialize!(other, ProductState(binary_int = 0))
            err = try
                mi_wrap(other)
                nothing
            catch e
                e
            end
            @test err isa ArgumentError
            @test occursin("CONTIGUOUS", err.msg)
            @test occursin("gaussian", err.msg)   # points at the one backend that supports it
        end
        # ... while contiguous regions still work on the MPS path (regression)
        mps = SimulationState(L = L, bc = :open, maxdim = 16, rng = _mi_rng(33))
        initialize!(mps, ProductState(binary_int = 0))
        @test abs(MutualInformation(1:2, 5:6)(mps)) < 1e-12
    end

    @testset "TripartiteMutualInformation: free composition + manual entropies" begin
        L = 8
        state = _mi_gauss(L, 40)
        initialize!(state, ProductState(binary_int = 0))
        for _ in 1:10
            apply!(state, GaussianHaar(), Bricklayer(:odd))
            apply!(state, GaussianHaar(), Bricklayer(:even))
        end

        # evaluates without error — NO Gaussian-specific TMI method exists;
        # dispatch flows through the generic composition into the Gaussian
        # MutualInformation override
        @test !any(m -> occursin("GaussianBackend", string(m.sig)),
            methods(TripartiteMutualInformation(1:2, 3:4, 5:6)))
        I3 = TripartiteMutualInformation(1:2, 3:4, 5:6)(state)   # D = 7:8 traced
        @test I3 isa Float64

        # I₃ = S_A+S_B+S_C −S_AB−S_AC−S_BC +S_ABC from subsystem entropies
        Γ = state.backend.corr
        S(sites) = QCM.subsystem_entropy(Γ, _mi_maj(state, sites))
        A, B, C = [1, 2], [3, 4], [5, 6]
        I3_manual = S(A) + S(B) + S(C) -
                    S(vcat(A, B)) - S(vcat(A, C)) - S(vcat(B, C)) +
                    S(vcat(A, B, C))
        @test I3 ≈ I3_manual atol = 1e-10   # TMI default base=ℯ ⇒ nats

        # base conversion forwards through the composition
        @test TripartiteMutualInformation(1:2, 3:4, 5:6; base = 2)(state) ≈
              I3_manual / log(2) atol = 1e-10

        # product state: I₃ = 0
        prod = _mi_gauss(L, 41)
        initialize!(prod, ProductState(bitstring = "01011010"))
        @test abs(TripartiteMutualInformation(1:2, 3:4, 5:6)(prod)) < 1e-12
    end

    @testset "rejections (error paths)" begin
        state = _mi_gauss(4, 50)
        initialize!(state, ProductState(binary_int = 0))

        # renyi_index != 1 → ArgumentError naming the Gaussian backend
        err = try
            MutualInformation(1, 3; renyi_index = 2)(state)
            nothing
        catch e
            e
        end
        @test err isa ArgumentError
        @test occursin("renyi_index", err.msg) && occursin("Gaussian", err.msg)

        # out-of-range region at evaluation time
        @test_throws ArgumentError MutualInformation(1, 6)(state)

        # uninitialized state → informative ArgumentError
        raw = _mi_gauss(4, 51)
        @test_throws ArgumentError MutualInformation(1, 3)(raw)

        # constructor invariants unchanged: overlap / dup / empty / non-positive
        @test_throws ArgumentError MutualInformation(1:3, 3:5)
        @test_throws ArgumentError MutualInformation([1, 1], [3])
        @test_throws ArgumentError MutualInformation(Int[], [2])
        @test_throws ArgumentError MutualInformation(0:1, 3:4)
    end
end
