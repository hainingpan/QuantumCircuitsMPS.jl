# === Gaussian backend: BondParity measurement (T9) ===
# Standalone: julia --project=. -e 'include("test/gaussian/test_bond_parity.jl")'
# NOT wired into runtests.jl (T13's job).

using Test
using QuantumCircuitsMPS
using LinearAlgebra
const QC = QuantumCircuitsMPS

function _rng(k)
    RNGRegistry(gates_spacetime = k, gates_realization = k + 10,
        born_measurement = k + 20, state_init = k + 30)
end

function _gaussian_state(L; bc = :open, seed = 1, log_events = false)
    state = SimulationState(L = L, bc = bc, backend = :gaussian,
        rng = _rng(seed), log_events = log_events)
    initialize!(state, ProductState(binary_int = 0))
    return state
end

# deterministic entangler: a few GaussianHaar bricklayer layers
function _entangle!(state, L; layers = 4)
    for _ in 1:layers
        apply!(state, GaussianHaar(), Bricklayer(:odd))
        apply!(state, GaussianHaar(), Bricklayer(:even))
    end
    return state
end

@testset "BondParity: fresh vacuum, bond (1,2)" begin
    L = 4
    state = _gaussian_state(L; log_events = true)
    Γ = state.backend.corr
    # vacuum: inner-Majorana element Γ[2,3] = 0 → P(0) = P(1) = 1/2
    @test Γ[2, 3] == 0.0
    apply!(state, BondParity(), AdjacentPair(1))
    Γ = state.backend.corr
    # post-measurement: bond parity definite, Γ[2,3] = ∓1
    @test abs(abs(Γ[2, 3]) - 1.0) < 1e-12
    # purity: Γ² = −I
    @test maximum(abs.(Γ * Γ + I)) < 1e-10
    # event log carries a MeasurementOutcome consistent with post-state
    ev = [e for e in state.event_log if e isa QC.MeasurementOutcome]
    @test length(ev) == 1
    @test ev[end].sites == [1, 2]
    @test ev[end].outcome == (Γ[2, 3] > 0 ? 0 : 1)   # post Γ = −s = 1 − 2·outcome
end

@testset "BondParity: entangled state — seed repro + re-measurement idempotence" begin
    L = 6
    sA = _entangle!(_gaussian_state(L; seed = 42), L)
    sB = _entangle!(_gaussian_state(L; seed = 42), L)
    apply!(sA, BondParity(), AdjacentPair(3))
    apply!(sB, BondParity(), AdjacentPair(3))
    # identical seeds → bitwise-identical trajectory
    @test sA.backend.corr == sB.backend.corr
    outcome1 = sA.backend.corr[6, 7] > 0 ? 0 : 1
    # re-measuring the SAME bond immediately: deterministic, same outcome, state unchanged
    Γ_before = copy(sA.backend.corr)
    apply!(sA, BondParity(), AdjacentPair(3))
    outcome2 = sA.backend.corr[6, 7] > 0 ? 0 : 1
    @test outcome2 == outcome1
    @test maximum(abs.(sA.backend.corr .- Γ_before)) < 1e-12
    @test maximum(abs.(sA.backend.corr * sA.backend.corr + I)) < 1e-10
end

@testset "BondParity: exactly one :born_measurement draw (redundant-draw contract)" begin
    L = 4
    sA = _entangle!(_gaussian_state(L; seed = 5), L)
    sB = _entangle!(_gaussian_state(L; seed = 5), L)
    # A: measure bond (2,3), then bond (1,2). B: burn ONE manual draw instead
    # of the first measurement — the SECOND measurement must then consume
    # draw #2 on both, but states differ; instead check stream position by
    # drawing after: both streams must be at the same position.
    apply!(sA, BondParity(), AdjacentPair(2))
    rand(QC.get_rng(sB.rng_registry, :born_measurement))  # burn exactly one draw
    rA = rand(QC.get_rng(sA.rng_registry, :born_measurement))
    rB = rand(QC.get_rng(sB.rng_registry, :born_measurement))
    @test rA == rB
end

@testset "BondParity: PBC wrap bond (L,1), even and odd L" begin
    for L in (4, 5)
        state = _entangle!(_gaussian_state(L; bc = :periodic, seed = 100 + L), L)
        # wrap bond via geometry (AdjacentPair(L) wraps under PBC)...
        apply!(state, BondParity(), AdjacentPair(L))
        Γ = state.backend.corr
        # inner Majoranas of the wrap bond: ix = [2L, 1]
        @test abs(abs(Γ[2L, 1]) - 1.0) < 1e-12
        @test maximum(abs.(Γ * Γ + I)) < 1e-10
        # ...and directly with reversed site order [1, L] — also accepted
        state2 = _entangle!(_gaussian_state(L; bc = :periodic, seed = 100 + L), L)
        QC.execute!(state2, BondParity(), [1, L])
        @test state2.backend.corr == state.backend.corr
    end
end

@testset "BondParity: OBC wrap bond rejected" begin
    L = 4
    state = _gaussian_state(L; bc = :open)
    err = try
        QC.execute!(state, BondParity(), [L, 1])
        nothing
    catch e
        e
    end
    @test err isa ArgumentError
    @test occursin("ADJACENT", err.msg)
end

@testset "BondParity: non-adjacent pair rejected" begin
    L = 4
    state = _gaussian_state(L; bc = :periodic)
    for sites in ([1, 3], [2, 4], [1, 1])
        err = try
            QC.execute!(state, BondParity(), sites)
            nothing
        catch e
            e
        end
        @test err isa ArgumentError
    end
    # wrong site count
    err = try
        QC.execute!(state, BondParity(), [1])
        nothing
    catch e
        e
    end
    @test err isa ArgumentError
end

@testset "BondParity: Born rule cross-check vs ED oracle (L=3)" begin
    include(joinpath(@__DIR__, "oracle.jl"))
    L = 3
    state = _entangle!(_gaussian_state(L; bc = :periodic, seed = 9), L; layers = 3)
    Γ = copy(state.backend.corr)
    ρ = oracle_density_matrix(Γ)
    γ = majorana_matrices(L)
    # bond (1,2) inner pair (2,3) and PBC wrap pair (6,1)
    for (a, b) in ((2, 3), (4, 5), (2L, 1))
        g = Γ[a, b]
        P₊ = (I + im * γ[a] * γ[b]) / 2
        # VERIFIED convention: ⟨iγ̂ₐγ̂_b⟩ = −Γ[a,b] ⇒ P(parity +1) = (1−g)/2 = P(outcome 1)
        @test abs(real(tr(ρ * P₊)) - (1 - g) / 2) < 1e-10
    end
end

println("test_bond_parity.jl: all testsets finished")
