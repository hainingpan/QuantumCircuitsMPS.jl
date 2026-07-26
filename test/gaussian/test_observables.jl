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
#   - Rényi-n for any real n > 0 (closed-form / per-pair-form pins, flat pins,
#     monotonicity, near-1 branch handoffs) — see the T4 block at the end
#   - rejections: :X/:Y axis, uninitialized state, out-of-range cut

using Test
using QuantumCircuitsMPS
using LinearAlgebra: I, eigvals, Hermitian

const QCM = QuantumCircuitsMPS

# T5's exponential-cost exact oracle (test-only; L ≤ 5)
include(joinpath(@__DIR__, "oracle.jl"))

function _rng(k)
    RNGRegistry(gates_spacetime = k, gates_realization = k + 10,
        born_measurement = k + 20, state_init = k + 30)
end

function _gaussian_state(L, k; bc = :open)
    SimulationState(L = L, bc = bc, backend = :gaussian, rng = _rng(k))
end

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

# === Region-based EntanglementEntropy (T5) ===================================
# Tests for (ee::EntanglementEntropy{Vector{Int}})(::SimulationState{GaussianBackend})
# (src/Gaussian/entanglement.jl). Conventions asserted here:
#   - region semantics: ee.cut is a set of PHYSICAL sites (not a bond index),
#     so non-contiguous and PBC-wrapped regions are well defined
#   - prefix equivalence: cut=k (bipartition) ≡ cut=1:k (region)
#   - complement symmetry S(A) = S(Ā) on a pure global state
#   - call-time validation: out-of-range / full-system regions → ArgumentError
# (Rényi-n on regions is covered by the T4 block at the end of this file.)

"""
Gaussian-preserving entangler (same construction as the "random circuit"
testset above): alternating `GaussianHaar` bricklayers on a `ProductState`.
The global state stays PURE, so complement symmetry S(A) = S(Ā) must hold.
"""
function _t5_entangled(L, k; bc = :open, layers = 10)
    st = _gaussian_state(L, k; bc = bc)
    initialize!(st, ProductState(binary_int = 0))
    for _ in 1:layers
        apply!(st, GaussianHaar(), Bricklayer(:odd))
        apply!(st, GaussianHaar(), Bricklayer(:even))
    end
    return st
end

@testset "Gaussian region EntanglementEntropy (T5)" begin
    @testset "product state: every region has zero entropy" begin
        L = 6
        state = _gaussian_state(L, 40)
        initialize!(state, ProductState(bitstring = "010101"))
        for region in ([2, 3], [1], [1, 4, 5], 2:4, [L, 1])
            @test EntanglementEntropy(cut = region)(state) ≈ 0.0 atol = 1e-10
            @test EntanglementEntropy(cut = region, base = ℯ)(state) ≈ 0.0 atol = 1e-10
        end
    end

    @testset "two maximally entangled pairs: analytic region entropies" begin
        # Givens(π/2) on Majoranas (2,3) pairs sites 1-2; on (6,7) pairs 3-4.
        state = _gaussian_state(4, 41)
        initialize!(state, ProductState(binary_int = 0))
        _givens!(state, 2, π / 2)
        _givens!(state, 6, π / 2)
        @test EntanglementEntropy(cut = [1])(state) ≈ 1.0 atol = 1e-10      # half a pair
        @test EntanglementEntropy(cut = [1, 2])(state) ≈ 0.0 atol = 1e-10   # a whole pair
        @test EntanglementEntropy(cut = [1, 3])(state) ≈ 2.0 atol = 1e-10   # non-contiguous
        @test EntanglementEntropy(cut = [2, 3])(state) ≈ 2.0 atol = 1e-10   # interior
        @test EntanglementEntropy(cut = [1, 3], base = ℯ)(state) ≈ 2 * log(2) atol = 1e-10
    end

    @testset "prefix equivalence: cut=k ≡ cut=1:k" begin
        L = 8
        state = _t5_entangled(L, 42)
        for k in 1:(L - 1)
            @test EntanglementEntropy(cut = 1:k)(state) ≈
                  EntanglementEntropy(cut = k)(state) atol = 1e-10
            @test EntanglementEntropy(cut = collect(1:k), base = ℯ)(state) ≈
                  EntanglementEntropy(cut = k, base = ℯ)(state) atol = 1e-10
        end
        # non-vacuous: the circuit genuinely entangles
        @test EntanglementEntropy(cut = 1:(L ÷ 2))(state) > 0.01
    end

    @testset "complement symmetry on a pure state (contiguous + non-contiguous)" begin
        L = 8
        state = _t5_entangled(L, 43)
        for A in ([1, 3], [2], 3:5, [1, 4, 7], [2, 3, 5, 8])
            Av = collect(A)
            SA = EntanglementEntropy(cut = Av)(state)
            SB = EntanglementEntropy(cut = setdiff(1:L, Av))(state)
            @test SA isa Float64
            @test SA ≈ SB atol = 1e-10
        end
        # non-vacuous: the non-contiguous region carries real entanglement
        @test EntanglementEntropy(cut = [1, 3])(state) > 0.01
    end

    @testset "PBC-wrapped region equals its complement" begin
        L = 8
        state = _t5_entangled(L, 44; bc = :periodic)
        S_wrap = EntanglementEntropy(cut = [L, 1])(state)
        @test S_wrap ≈ EntanglementEntropy(cut = collect(2:(L - 1)))(state) atol = 1e-10
        @test S_wrap > 0.01
        # a wider wrapped block
        @test EntanglementEntropy(cut = [L - 1, L, 1, 2])(state) ≈
              EntanglementEntropy(cut = 3:(L - 2))(state) atol = 1e-10
    end

    @testset "call-time region validation" begin
        L = 4
        state = _gaussian_state(L, 46)
        initialize!(state, ProductState(binary_int = 0))
        # out of range (ArgumentError, never BoundsError)
        @test_throws ArgumentError EntanglementEntropy(cut = [L + 1])(state)
        @test_throws ArgumentError EntanglementEntropy(cut = [1, 2, 9])(state)
        # full system = trivial bipartition
        @test_throws ArgumentError EntanglementEntropy(cut = collect(1:L))(state)
        @test_throws ArgumentError EntanglementEntropy(cut = 1:L)(state)
        # uninitialized state → same informative ArgumentError as the Int path
        raw = _gaussian_state(L, 47)
        @test_throws ArgumentError EntanglementEntropy(cut = [1, 2])(raw)
    end
end

# === Rényi-n EntanglementEntropy (T4) ========================================
# Tests for the general-n branches of `subsystem_entropy`
# (src/Gaussian/entanglement.jl), reached through BOTH public EE paths
# (bipartition `cut::Int` and region `cut::Vector{Int}`). Conventions asserted:
#   - closed form Sₙ = log(νⁿ + (1−ν)ⁿ)/(1−n) for a single-mode reduced state
#   - per-pair form Sₙ = 1/(1−n)·Σ_k log[((1+λ_k)/2)ⁿ + ((1−λ_k)/2)ⁿ] over the
#     POSITIVE half of spec(iΓ_A), for a non-contiguous region
#   - odd-dimensional Γ_A (Majorana-chain granularity): the unpaired ξ = 0 mode
#     contributes exactly log(2)/2 for EVERY n, including 2048 and floatmax
#   - the three δ = n − 1 branches: exact von Neumann shunt (bit-identical),
#     cancellation-safe near-1 form (incl. zero-weight skipping on a product
#     state), scale-safe log-domain general form
#   - invariances at n = 2: prefix equivalence, complement symmetry, log base

@testset "Gaussian Rényi-n EntanglementEntropy (T4)" begin
    @testset "closed-form single-mode pin Sₙ = log(νⁿ+(1−ν)ⁿ)/(1−n)" begin
        # L=2 fermionic modes, one GaussianHaar on the (1,2) bond. The reduced
        # state of mode 1 has the single occupation pair {ν, 1−ν} with
        # ν = (1 − Γ[1,2])/2 (docs/src/backends/gaussian.md:199 convention), so
        # its Rényi entropy has a closed form derived independently of the
        # kernel under test.
        state = _gaussian_state(2, 76)
        initialize!(state, ProductState(binary_int = 0))
        apply!(state, GaussianHaar(), AdjacentPair(1))
        ν = (1 - state.backend.corr[1, 2]) / 2
        # SEED HARDENING: the pin is vacuous on a flat (ν = 1/2) reduced state
        # — every Sₙ would collapse to log 2 — and insensitive on a nearly pure
        # one. Seed 76 is chosen so neither degeneracy occurs.
        @test 0.05 < abs(ν - 0.5)
        @test 0.05 < ν < 0.95
        for n in (0.5, 2, 3.7)
            @test EntanglementEntropy(cut = [1], renyi_index = n, base = ℯ)(state) ≈
                  log(ν^n + (1 - ν)^n) / (1 - n) atol=1e-10
        end
        # n = 2048: the REFERENCE must be evaluated in the log domain too —
        # ν^2048 underflows to 0.0, so the naive closed form is Inf/NaN.
        let n = 2048, wmax = max(ν, 1 - ν), wmin = min(ν, 1 - ν)
            ref = (n * log(wmax) + log1p((wmin / wmax)^n)) / (1 - n)
            @test EntanglementEntropy(cut = [1], renyi_index = n, base = ℯ)(state) ≈
                  ref atol=1e-10
        end
        @test EntanglementEntropy(cut = [1], renyi_index = 1, base = ℯ)(state) ≈
              -(ν * log(ν) + (1 - ν) * log(1 - ν)) atol=1e-10
    end

    @testset "per-pair-form equivalence on a non-contiguous region" begin
        L = 6
        region = [2, 3, 5]
        state = _t5_entangled(L, 61)
        idx = QCM._gaussian_region_majoranas(state, region)
        ξ = eigvals(Hermitian(im .* state.backend.corr[idx, idx]))
        pos = filter(>(0), ξ)
        # SEED HARDENING: fermionic granularity ⇒ even-dimensional Γ_A ⇒ exactly
        # |region| POSITIVE eigenvalues (clean ± pairing), and a spectrum well
        # separated from 0 (a ξ ≈ 0 pair makes the comparison branch-insensitive).
        @test length(pos) == length(region)
        @test minimum(abs.(ξ)) > 1e-6
        for n in (2, 2.5, 3)
            ref = sum(log(((1 + x) / 2)^n + ((1 - x) / 2)^n) for x in pos) / (1 - n)
            @test EntanglementEntropy(cut = region, renyi_index = n, base = ℯ)(state) ≈
                  ref atol=1e-10
        end
    end

    @testset "flat pins: Majorana odd cut = log(2)/2 ∀n; product region = 0" begin
        # Majorana-chain granularity: cut=1 selects ONE Majorana index, so Γ_A
        # is 1×1 (ODD-dimensional). Its single unpaired ξ = 0 mode must give
        # exactly log(2)/2 for EVERY n — a direct-power implementation returns
        # Inf at n = 2048 and an un-scaled term overflows at floatmax.
        mj = SimulationState(L = 8, bc = :open, backend = :gaussian,
            site_type = "Majorana", rng = _rng(70))
        initialize!(mj, ProductState(binary_int = 0))
        for n in (0.5, 1, 2, 5, 2048, floatmax(Float64))
            @test EntanglementEntropy(cut = 1, renyi_index = n, base = ℯ)(mj) ≈
                  log(2) / 2 atol=1e-12
        end
        # product state: every region is exactly unentangled at every n
        prod = _gaussian_state(4, 71)
        initialize!(prod, ProductState(bitstring = "0101"))
        for n in (0.5, 2)
            @test abs(EntanglementEntropy(cut = [2, 3], renyi_index = n,
                base = ℯ)(prod)) < 1e-10
        end
    end

    @testset "monotonicity, near-1 continuity, shunt exactness, zero-weight skip" begin
        state = _t5_entangled(6, 62)
        Sn(n) = EntanglementEntropy(cut = 3, renyi_index = n, base = ℯ)(state)
        S1 = Sn(1)
        @test Sn(0.5) > S1 + 1e-6
        @test S1 > Sn(2) + 1e-6
        @test Sn(2) > Sn(3) + 1e-6
        # cancellation-safe near-1 branch: continuous AND still positive
        for n in (1 - 1e-6, 1 + 1e-6)
            @test abs(Sn(n) - S1) < 1e-4
            @test Sn(n) > 0
        end
        # WIDENED von Neumann shunt: these three indices must reproduce the
        # n = 1 body BIT FOR BIT (identical expression, not merely ≈).
        @test Sn(prevfloat(1.0)) == S1
        @test Sn(1.0 - 1e-8) == S1
        @test Sn(1.0 + 1e-8) == S1
        # PRODUCT state: all λ ∈ {0, 1}. The near-1 branch must SKIP those
        # zero-weight terms explicitly — `0 * expm1(δ * log(0))` is NaN for
        # δ < 0, so a missing skip shows up here and nowhere else.
        prod = _gaussian_state(4, 72)
        initialize!(prod, ProductState(bitstring = "0101"))
        for n in (1 - 1e-6, 1 + 1e-6)
            @test EntanglementEntropy(cut = [2, 3], renyi_index = n, base = ℯ)(prod) == 0
        end
    end

    @testset "invariances at n = 2: prefix, complement, log base" begin
        L = 8
        state = _t5_entangled(L, 63)
        for k in 1:(L - 1)
            @test EntanglementEntropy(cut = 1:k, renyi_index = 2, base = ℯ)(state) ≈
                  EntanglementEntropy(cut = k, renyi_index = 2,
                base = ℯ)(state) atol=1e-10
        end
        # complement symmetry on a PURE global state
        s4 = _t5_entangled(4, 64)
        @test EntanglementEntropy(cut = [1, 3], renyi_index = 2, base = ℯ)(s4) ≈
              EntanglementEntropy(cut = [2, 4], renyi_index = 2, base = ℯ)(s4) atol=1e-10
        # base conversion: S₂(base=2) = S₂(base=ℯ)/log 2
        @test EntanglementEntropy(cut = 3, renyi_index = 2, base = 2)(state) ≈
              EntanglementEntropy(cut = 3, renyi_index = 2, base = ℯ)(state) /
              log(2) atol=1e-10
        # NON-VACUITY: the compared numbers are genuinely entangled, not zeros
        @test EntanglementEntropy(cut = L ÷ 2, renyi_index = 2, base = ℯ)(state) > 0.1
        @test EntanglementEntropy(cut = [1, 3], renyi_index = 2, base = ℯ)(s4) > 0.1
    end

    @testset "kernel-level near-1 handoff on an EXTREME-skew pair" begin
        # Hand-built 2×2 covariance block with ξ = 1 − 2⁻⁵², whose occupation
        # pair is EXACTLY {2⁻⁵³, 1 − 2⁻⁵³} — it sums to exactly 1.0, so the
        # near-1 branch's `Σ λ = 1` assumption carries no normalization
        # residual and the BigFloat reference is a clean oracle.
        ξ0 = 1 - 2.0^-52
        Γ_A = [0.0 ξ0; -ξ0 0.0]
        λs = clamp.((1 .- eigvals(Hermitian(im .* Γ_A))) ./ 2, 0.0, 1.0)
        λmin = minimum(λs)
        @test λmin == 2.0^-53                 # fixture integrity
        @test λmin + maximum(λs) == 1.0
        function _pair_ref(n)
            b = BigFloat(λmin)
            nb = BigFloat(n)
            return Float64(log(b^nb + (1 - b)^nb) / (1 - nb))
        end
        for n in (1 - 1e-6, 1 + 1e-6, 0.9999, prevfloat(0.9999),
            1.0001, nextfloat(1.0001))
            S = QCM.subsystem_entropy(Γ_A, [1, 2]; renyi_index = n)
            @test S > 0                                    # positivity
            @test isapprox(S, _pair_ref(n); rtol = 1e-6)   # BigFloat reference
        end
        # INSIDE/OUTSIDE adjacent-pair continuity across the ±1e-4 handoff:
        # 0.9999 / 1.0001 land in the near-1 branch, their neighbours just
        # outside it in the log-domain branch.
        for n_in in (0.9999, 1.0001)
            n_out = n_in < 1 ? prevfloat(n_in) : nextfloat(n_in)
            @test abs(n_in - 1) <= QCM._RENYI_NEAR1        # branch-placement pin
            @test abs(n_out - 1) > QCM._RENYI_NEAR1
            S_in = QCM.subsystem_entropy(Γ_A, [1, 2]; renyi_index = n_in)
            S_out = QCM.subsystem_entropy(Γ_A, [1, 2]; renyi_index = n_out)
            @test isapprox(S_in, S_out; rtol = 1e-9)
        end
    end
end
