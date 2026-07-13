# === Gaussian backend: EntanglementEntropy + Magnetization observables ===
# Tests for (ee::EntanglementEntropy)(::SimulationState{GaussianBackend})
# (src/Gaussian/entanglement.jl) and
# (m::Magnetization)(::SimulationState{GaussianBackend})
# (src/Gaussian/magnetization.jl).
#
# Conventions asserted here:
#   - cut semantics: subsystem = physical sites 1..cut (prefix bipartition)
#   - log base: honors ee.base exactly like MPS/SV/Clifford
#     (default base=2 → bits; base=ℯ → nats)
#   - Magnetization(:Z) = (1/L) Σᵢ ⟨Zᵢ⟩ with ⟨Zᵢ⟩ = 2·P(0)−1 = Γ[2i−1,2i]
#     — must agree with Clifford AND MPS for the same ProductState
#   - rejections: renyi_index != 1, :X/:Y axis, uninitialized state

using Test
using QuantumCircuitsMPS
using LinearAlgebra: I, eigvals, Hermitian

const QCM = QuantumCircuitsMPS

# T5's exponential-cost exact oracle (test-only; L ≤ 5)
include(joinpath(@__DIR__, "oracle.jl"))

_rng(k) = RNGRegistry(gates_spacetime = k, gates_realization = k + 10,
    born_measurement = k + 20, state_init = k + 30)

_gaussian_state(L, k; bc = :open) =
    SimulationState(L = L, bc = bc, backend = :gaussian, rng = _rng(k))

"""
Apply a Givens rotation of angle θ on Majorana indices (p, p+1) to the
covariance matrix of `state` by DIRECT orthogonal conjugation Γ ← R Γ Rᵀ.
GaussianHaar-free deterministic entangler for tests: on the L=2 vacuum with
p=2 (Majoranas 2,3 — straddling the two modes), Γ'[1,2] = cos(θ), so the
cut=1 occupation eigenvalues are λ = (1 ∓ cos θ)/2.
"""
function _givens!(state, p::Int, θ::Real)
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
Exact von Neumann entropy (nats) of mode 1 of an L=2 Gaussian state, via
T5's density-matrix oracle: ρ = oracle_density_matrix(Γ) (msb order: site 1
= most significant bit, basis index (0-based) = n₁·2 + n₂), partial trace
over mode 2, then −Σ eig(ρ_A) log eig(ρ_A).
"""
function _oracle_mode1_entropy(Γ)
    ρ = oracle_density_matrix(Γ)                       # 4×4, msb order
    ρ_A = zeros(ComplexF64, 2, 2)
    for a in 0:1, b in 0:1, c in 0:1                   # trace out mode 2 (LSB)
        ρ_A[a + 1, b + 1] += ρ[2a + c + 1, 2b + c + 1]
    end
    p = real.(eigvals(Hermitian(ρ_A)))
    return -sum(x <= 0 ? 0.0 : x * log(x) for x in p)
end

@testset "Gaussian observables (T10)" begin

    @testset "vacuum: EE ≈ 0 at every cut" begin
        L = 8
        state = _gaussian_state(L, 1)
        initialize!(state, ProductState(binary_int = 0))
        for cut in 1:(L - 1)
            @test EntanglementEntropy(cut = cut)(state) ≈ 0.0 atol = 1e-13          # base 2
            @test EntanglementEntropy(cut = cut, base = ℯ)(state) ≈ 0.0 atol = 1e-13 # nats
        end
    end

    @testset "occupied product state: EE ≈ 0 at every cut" begin
        L = 4
        state = _gaussian_state(L, 2)
        initialize!(state, ProductState(bitstring = "0101"))
        for cut in 1:(L - 1)
            @test EntanglementEntropy(cut = cut, base = ℯ)(state) ≈ 0.0 atol = 1e-13
        end
    end

    @testset "entangled pair: EE = log(2) at cut=1" begin
        # θ=π/2 Givens on Majoranas (2,3) of the L=2 vacuum → Γ'[1,2] = cos(π/2) = 0
        # → λ = {1/2, 1/2} → maximally entangled pair, S = log(2) exactly.
        state = _gaussian_state(2, 3)
        initialize!(state, ProductState(binary_int = 0))
        _givens!(state, 2, π / 2)
        @test EntanglementEntropy(cut = 1, base = ℯ)(state) ≈ log(2) atol = 1e-10
        @test EntanglementEntropy(cut = 1)(state) ≈ 1.0 atol = 1e-10   # default base=2: 1 bit
        # cross-check against T5's exact density-matrix oracle
        @test EntanglementEntropy(cut = 1, base = ℯ)(state) ≈
              _oracle_mode1_entropy(state.backend.corr) atol = 1e-10
    end

    @testset "generic angle: EE matches exact-ρ oracle + analytic value" begin
        # θ=π/3 → cos θ = 1/2 → λ = {1/4, 3/4} → S = 2log(2) − (3/4)log(3) nats
        state = _gaussian_state(2, 4)
        initialize!(state, ProductState(binary_int = 0))
        _givens!(state, 2, π / 3)
        S_pkg = EntanglementEntropy(cut = 1, base = ℯ)(state)
        S_analytic = 2 * log(2) - 0.75 * log(3)
        @test S_pkg ≈ S_analytic atol = 1e-10
        @test S_pkg ≈ _oracle_mode1_entropy(state.backend.corr) atol = 1e-10
    end

    @testset "random circuit: 0 ≤ EE ≤ min(cut, L−cut)·log(2)" begin
        L = 8
        state = _gaussian_state(L, 5)
        initialize!(state, ProductState(binary_int = 0))
        for _ in 1:20
            apply!(state, GaussianHaar(), Bricklayer(:odd))
            apply!(state, GaussianHaar(), Bricklayer(:even))
        end
        for cut in 1:(L - 1)
            S = EntanglementEntropy(cut = cut, base = ℯ)(state)
            @test S >= -1e-12
            @test S <= min(cut, L - cut) * log(2) + 1e-10
        end
        # 20 entangling layers must generate strictly positive half-cut entropy
        @test EntanglementEntropy(cut = L ÷ 2, base = ℯ)(state) > 0.01
    end

    @testset "EntropyProfile composes per-cut EE automatically (no Gaussian code)" begin
        L = 6
        state = _gaussian_state(L, 6)
        initialize!(state, ProductState(binary_int = 0))
        for _ in 1:5
            apply!(state, GaussianHaar(), Bricklayer(:odd))
            apply!(state, GaussianHaar(), Bricklayer(:even))
        end
        profile = EntropyProfile(base = ℯ)(state)   # EntropyProfile defaults to base=ℯ
        @test length(profile) == L - 1
        @test profile ≈ [EntanglementEntropy(cut = x, base = ℯ)(state) for x in 1:(L - 1)]
    end

    @testset "subsystem_entropy helper (for T11/MutualInformation)" begin
        # non-contiguous Majorana index set: modes {1, 3} of an L=4 product state
        state = _gaussian_state(4, 7)
        initialize!(state, ProductState(bitstring = "0101"))
        @test QCM.subsystem_entropy(state.backend.corr, [1, 2, 5, 6]) ≈ 0.0 atol = 1e-13
        # entangled pair, full system: pure state → S(A∪B) = 0
        s2 = _gaussian_state(2, 8)
        initialize!(s2, ProductState(binary_int = 0))
        _givens!(s2, 2, π / 2)
        @test QCM.subsystem_entropy(s2.backend.corr, [1, 2, 3, 4]) ≈ 0.0 atol = 1e-12
        @test QCM.subsystem_entropy(s2.backend.corr, [3, 4]) ≈ log(2) atol = 1e-10  # mode 2 alone
    end

    @testset "Magnetization(:Z): vacuum + cross-backend consistency" begin
        L = 4
        # Gaussian
        g = _gaussian_state(L, 9)
        initialize!(g, ProductState(binary_int = 0))
        @test Magnetization(:Z)(g) ≈ 1.0 atol = 1e-13
        # same ProductState on Clifford and MPS — hard consistency requirement
        c = SimulationState(L = L, bc = :open, backend = :clifford, rng = _rng(9))
        initialize!(c, ProductState(binary_int = 0))
        m = SimulationState(L = L, bc = :open, maxdim = 16, rng = _rng(9))
        initialize!(m, ProductState(binary_int = 0))
        @test Magnetization(:Z)(g) ≈ Magnetization(:Z)(c) atol = 1e-12
        @test Magnetization(:Z)(g) ≈ Magnetization(:Z)(m) atol = 1e-12

        # "0101" pattern (sites 2 and 4 occupied): M = (+1 −1 +1 −1)/4 = 0
        g2 = _gaussian_state(L, 10)
        initialize!(g2, ProductState(bitstring = "0101"))
        c2 = SimulationState(L = L, bc = :open, backend = :clifford, rng = _rng(10))
        initialize!(c2, ProductState(bitstring = "0101"))
        m2 = SimulationState(L = L, bc = :open, maxdim = 16, rng = _rng(10))
        initialize!(m2, ProductState(bitstring = "0101"))
        @test Magnetization(:Z)(g2) ≈ 0.0 atol = 1e-13
        @test Magnetization(:Z)(g2) ≈ Magnetization(:Z)(c2) atol = 1e-12
        @test Magnetization(:Z)(g2) ≈ Magnetization(:Z)(m2) atol = 1e-12

        # single occupied site: M = (L−2)/L, checked against Clifford
        g3 = _gaussian_state(L, 11)
        initialize!(g3, ProductState(bitstring = "1000"))
        c3 = SimulationState(L = L, bc = :open, backend = :clifford, rng = _rng(11))
        initialize!(c3, ProductState(bitstring = "1000"))
        @test Magnetization(:Z)(g3) ≈ (L - 2) / L atol = 1e-13
        @test Magnetization(:Z)(g3) ≈ Magnetization(:Z)(c3) atol = 1e-12
    end

    @testset "rejections (error paths)" begin
        L = 8
        state = _gaussian_state(L, 12)
        initialize!(state, ProductState(binary_int = 0))

        # renyi_index != 1 → ArgumentError (NEVER silently von Neumann)
        err = try
            EntanglementEntropy(cut = 4, renyi_index = 2)(state)
            nothing
        catch e
            e
        end
        @test err isa ArgumentError
        @test occursin("renyi_index", err.msg) && occursin("Gaussian", err.msg)

        # cut out of range
        @test_throws ArgumentError EntanglementEntropy(cut = L)(state)

        # Magnetization :X / :Y → ArgumentError naming the Gaussian backend
        for axis in (:X, :Y)
            err = try
                Magnetization(axis)(state)
                nothing
            catch e
                e
            end
            @test err isa ArgumentError
            @test occursin("Gaussian", err.msg)
        end

        # uninitialized state → informative ArgumentError for both observables
        raw = _gaussian_state(4, 13)
        @test_throws ArgumentError EntanglementEntropy(cut = 2)(raw)
        @test_throws ArgumentError Magnetization(:Z)(raw)
    end
end
