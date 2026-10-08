# test/regression/mps_observable_normalization.jl
#
# === MPS observables must be normalized by ⟨ψ|ψ⟩ ===
#
# The MPS backend does not renormalize after unitary gates, so a truncating
# unitary layer leaves ⟨ψ|ψ⟩ < 1. `born_probability`, `Magnetization`,
# `EntanglementEntropy` and `MutualInformation` always divided the norm out,
# but the `inner`-based observables (`PauliString`, `StringOrder`,
# `DomainWall` — and by composition `Correlator` and
# `MagnetizationFluctuations`) returned the RAW contraction ⟨ψ|O|ψ⟩, i.e. the
# expectation value scaled by the retained norm. On 0.6|00⟩ + 0.8|11⟩
# truncated at maxdim=1 (retained state 0.8|11⟩, ⟨ψ|ψ⟩ = 0.64) this gave
# ⟨Z₁⟩ = −0.64, ⟨Z₁Z₂⟩ = 0.64, a connected ZZ correlation of 0.2304 and
# Var(Z₁+Z₂) = 1.6416 for what is a product state.
#
# Test groups:
#   1. The analytic bug-report scenario above, pinned to the exact values of
#      the retained product state and to the `expect`-based observables.
#   2. Scale invariance + an independent dense reference on random MPS
#      (qubit and S=1; open and periodic) for every affected observable.
#   3. Consistency between the `inner`-based and `expect`-based families on
#      a genuinely truncating Haar circuit (⟨ψ|ψ⟩ drifts well below 1).
#   4. A zero-norm MPS is rejected with an informative ArgumentError.

using Test
using Random
using LinearAlgebra: norm, normalize!
using ITensors: array
using ITensorMPS
using QuantumCircuitsMPS

# --- helpers (file-local, `_mon_` prefixed: runtests.jl shares one scope) ---

const _MON_RNG = RNGRegistry(gates_spacetime = 11, gates_realization = 22,
    born_measurement = 33)

# SimulationState{MPSBackend} holding a random MPS (bond dimension `chi`) on
# the state's own RAM-ordered site indices, then rescaled by `scale` so that
# ⟨ψ|ψ⟩ = scale² ≠ 1 — mimicking the norm loss of a truncated unitary layer.
function _mon_random_state(; L::Int, chi::Int, site_type::String, bc::Symbol,
        seed::Int, scale::Float64 = 1.0)
    state = SimulationState(L = L, bc = bc, site_type = site_type, maxdim = 64,
        rng = _MON_RNG)
    psi = random_mps(MersenneTwister(seed), ComplexF64, state.backend.sites;
        linkdims = chi)
    normalize!(psi)
    psi[1] *= scale
    state.backend.mps = psi
    return state
end

# Dense amplitude tensor in RAM axis order (axis r ↔ RAM site r; index value
# k + 1 ↔ level k), plus the total weight Σ|A|².
function _mon_dense(state)
    A = array(prod(state.backend.mps), state.backend.sites...)
    return A, sum(abs2, A)
end

# ⟨∏ᵢ f_i(level at physical site i)⟩ for DIAGONAL single-site functions —
# an independent reference for Z strings, string order, and projector
# products. `fs` maps physical site => f(level::Int).
function _mon_diag_expect(state, fs::Dict{Int, <:Function})
    A, den = _mon_dense(state)
    acc = 0.0
    for I in CartesianIndices(A)
        w = abs2(A[I])
        w == 0 && continue
        for (p, f) in fs
            w *= f(I[state.phy_ram[p]] - 1)
        end
        acc += w
    end
    return acc / den
end

_mon_z(level) = level == 0 ? 1.0 : -1.0                 # qubit Z, ⟨Z⟩=+1 on |0⟩
_mon_sz(level) = (1.0, 0.0, -1.0)[level + 1]            # S=1 Sz on (Up, Z0, Dn)
_mon_expsz(level) = (-1.0, 1.0, -1.0)[level + 1]        # exp(iπ Sz)

# Dense DomainWall reference: Σⱼ (L−j+1)^order · P(first "1" at scan position j from i1)
function _mon_dense_domain_wall(state, i1::Int, order::Int)
    L = state.L
    phy_list = [mod(i1 + j - 2, L) + 1 for j in 1:L]
    dw = 0.0
    for j in 1:L
        fs = Dict{Int, Function}()
        for p in phy_list[1:(j - 1)]
            fs[p] = lv -> lv == 0 ? 1.0 : 0.0     # Proj0 on the sites scanned before j
        end
        fs[phy_list[j]] = lv -> lv == 1 ? 1.0 : 0.0  # Proj1 at scan position j
        dw += Float64((L - j + 1)^order) * _mon_diag_expect(state, fs)
    end
    return dw
end

# Dense StringOrder reference (order 1 and 2), physical-site formulas as in
# src/Observables/string_order.jl.
function _mon_dense_string_order(state, i::Int, j::Int, order::Int)
    fs = Dict{Int, Function}()
    if order == 1
        fs[i] = _mon_sz
        fs[j] = _mon_sz
        for k in (i + 1):(j - 1)
            fs[k] = _mon_expsz
        end
    else
        for p in (i, i + 1, j - 1, j)
            fs[p] = _mon_sz
        end
        for k in (i + 2):(j - 2)
            fs[k] = _mon_expsz
        end
    end
    return _mon_diag_expect(state, fs)
end

@testset "REGRESSION mps_observable_normalization" begin

    # =====================================================================
    # 1. Bug-report scenario: 0.6|00⟩ + 0.8|11⟩ truncated at maxdim=1
    # =====================================================================
    @testset "truncated 0.6|00⟩+0.8|11⟩ → retained 0.8|11⟩ measured as a product state" begin
        # U|00⟩ = 0.6|00⟩ + 0.8|11⟩ (basis order |00⟩,|01⟩,|10⟩,|11⟩), unitary.
        U = [0.6 0.0 0.0 -0.8;
             0.0 1.0 0.0 0.0;
             0.0 0.0 1.0 0.0;
             0.8 0.0 0.0 0.6]
        @test U' * U ≈ [1 0 0 0; 0 1 0 0; 0 0 1 0; 0 0 0 1]

        state = SimulationState(L = 2, bc = :open, maxdim = 1, cutoff = 1e-16,
            rng = _MON_RNG)
        initialize!(state, ProductState(binary_int = 0))
        apply!(state, MatrixGate(U), Sites(1:2))

        # Premise of the regression: truncation happened and the MPS was NOT
        # renormalized (⟨ψ|ψ⟩ = 0.8² = 0.64).
        @test norm(state.backend.mps)^2≈0.64 atol=1e-12

        # `expect`-based observables (already norm-independent)
        @test born_probability(state, 1, 1)≈1.0 atol=1e-12
        @test born_probability(state, 2, 1)≈1.0 atol=1e-12
        @test Magnetization(:Z)(state)≈-1.0 atol=1e-12

        # `inner`-based observables: the values the bug report lists as wrong
        # (−0.64, 0.64, 0.2304, 1.6416) must now be those of |11⟩.
        @test PauliString(1 => :Z)(state)≈-1.0 atol=1e-12
        @test PauliString(2 => :Z)(state)≈-1.0 atol=1e-12
        @test PauliString(1 => :Z, 2 => :Z)(state)≈1.0 atol=1e-12
        @test Correlator(1 => :Z, 2 => :Z)(state)≈0.0 atol=1e-12
        @test MagnetizationFluctuations(1:2)(state)≈0.0 atol=1e-12
        # Product state |11⟩: ⟨X₁⟩ = ⟨Y₁⟩ = 0 and ⟨X₁X₂⟩ = 0, norm or not.
        @test PauliString(1 => :X)(state)≈0.0 atol=1e-12
        @test PauliString(1 => :X, 2 => :X)(state)≈0.0 atol=1e-12

        # DomainWall from i1 = 1 on |11⟩: the first "1" is at scan position 1
        # with probability 1, weight (L − 1 + 1)^order = 2^order.
        @test DomainWall(order = 1)(state, 1)≈2.0 atol=1e-12
        @test DomainWall(order = 2)(state, 1)≈4.0 atol=1e-12
    end

    # =====================================================================
    # 2. Scale invariance + dense reference on random MPS
    # =====================================================================
    @testset "scale invariance vs dense reference (qubit, bc=$bc)" for bc in (:open, :periodic)
        L, chi = 6, 4
        kw = (; L, chi, site_type = "Qubit", bc, seed = 7)
        normalized = _mon_random_state(; kw...)
        scaled = _mon_random_state(; kw..., scale = 0.37)
        @test norm(scaled.backend.mps)^2≈0.37^2 atol=1e-12

        strings = (PauliString(1 => :Z),
            PauliString(3 => :Z),
            PauliString(1 => :Z, 4 => :Z),
            PauliString(2 => :Z, 3 => :Z, 6 => :Z),
            PauliString(1 => :X),
            PauliString(2 => :Y, 5 => :X),
            PauliString(1 => :X, 2 => :Y, 3 => :Z))
        for ps in strings
            @test ps(scaled)≈ps(normalized) atol=1e-12
        end
        # Independent dense reference for the diagonal (Z) strings
        for ps in strings[1:4]
            fs = Dict{Int, Function}(s => _mon_z for s in ps.sites)
            @test ps(scaled)≈_mon_diag_expect(scaled, fs) atol=1e-12
        end

        czz = Correlator(1 => :Z, 4 => :Z)
        @test czz(scaled)≈czz(normalized) atol=1e-12
        varm = MagnetizationFluctuations(1:L)
        @test varm(scaled)≈varm(normalized) atol=1e-11
        # Var(M) ≥ 0 is only guaranteed for a properly normalized expectation
        @test varm(scaled) >= -1e-12

        for i1 in (1, 4), order in (1, 2)

            dw = DomainWall(; order)
            @test dw(scaled, i1)≈dw(normalized, i1) atol=1e-11
            @test dw(scaled, i1)≈_mon_dense_domain_wall(scaled, i1, order) atol=1e-11
        end

        # Cross-family consistency: ⟨Zᵢ⟩ = P(0) − P(1), mean ⟨Zᵢ⟩ = Magnetization
        for i in 1:L
            pz = born_probability(scaled, i, 0) - born_probability(scaled, i, 1)
            @test PauliString(i => :Z)(scaled)≈pz atol=1e-12
        end
        mz = sum(PauliString(i => :Z)(scaled) for i in 1:L) / L
        @test mz≈Magnetization(:Z)(scaled) atol=1e-12
    end

    @testset "StringOrder scale invariance vs dense reference (S=1, bc=$bc)" for bc in (:open, :periodic)
        L, chi = 6, 3
        kw = (; L, chi, site_type = "S=1", bc, seed = 5)
        normalized = _mon_random_state(; kw...)
        scaled = _mon_random_state(; kw..., scale = 1.9)
        @test norm(scaled.backend.mps)^2≈1.9^2 atol=1e-12

        cases = ((1, 4, 1), (2, 5, 1), (1, 6, 1), (1, 5, 2), (1, 6, 2), (2, 6, 2))
        for (i, j, order) in cases
            so = StringOrder(i, j; order)
            @test so(scaled)≈so(normalized) atol=1e-12
            @test so(scaled)≈_mon_dense_string_order(scaled, i, j, order) atol=1e-12
        end
    end

    # =====================================================================
    # 3. Genuinely truncating circuit: inner-based == expect-based family
    # =====================================================================
    @testset "truncating Haar brickwork: PauliString agrees with born_probability/Magnetization" begin
        L = 8
        state = SimulationState(L = L, bc = :periodic, maxdim = 2, cutoff = 1e-12,
            rng = RNGRegistry(gates_spacetime = 1, gates_realization = 2,
                born_measurement = 3))
        initialize!(state, ProductState(binary_int = 0))
        for _ in 1:4
            apply!(state, HaarRandom(), Bricklayer(:even))
            apply!(state, HaarRandom(), Bricklayer(:odd))
        end
        n2 = norm(state.backend.mps)^2
        @test n2 < 1 - 1e-3          # premise: the unitaries truncated and were not renormalized
        @test n2 > 0

        for i in 1:L
            pz = born_probability(state, i, 0) - born_probability(state, i, 1)
            @test PauliString(i => :Z)(state)≈pz atol=1e-10
            @test abs(PauliString(i => :Z)(state)) <= 1 + 1e-10
            @test abs(PauliString(i => :Z, mod1(i + 1, L) => :Z)(state)) <= 1 + 1e-10
        end
        mz = sum(PauliString(i => :Z)(state) for i in 1:L) / L
        @test mz≈Magnetization(:Z)(state) atol=1e-10
        @test MagnetizationFluctuations(1:L)(state) >= -1e-10
        # DomainWall weights are probabilities of a complete set of events on
        # the retained state: the order-1 value is bounded by the largest weight L.
        @test 0 <= DomainWall(order = 1)(state, 1) <= L + 1e-10
    end

    # =====================================================================
    # 4. Zero-norm MPS is rejected
    # =====================================================================
    @testset "zero-norm MPS throws ArgumentError" begin
        state = _mon_random_state(;
            L = 4, chi = 2, site_type = "Qubit", bc = :open, seed = 3)
        state.backend.mps[1] *= 0.0
        @test norm(state.backend.mps) == 0
        @test_throws ArgumentError PauliString(1 => :Z)(state)
        @test_throws ArgumentError Correlator(1 => :Z, 2 => :Z)(state)
        @test_throws ArgumentError DomainWall(order = 1)(state, 1)

        s1 = _mon_random_state(; L = 4, chi = 2, site_type = "S=1", bc = :open, seed = 3)
        s1.backend.mps[1] *= 0.0
        @test_throws ArgumentError StringOrder(1, 4)(s1)
    end
end
