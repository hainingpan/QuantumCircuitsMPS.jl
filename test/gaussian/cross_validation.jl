# test/gaussian/cross_validation.jl
# Cross-validation of the Gaussian (covariance-matrix) backend against the
# EXACT many-body ED/Pfaffian oracle (test/gaussian/oracle.jl, T5), plus a
# full simulate!/track!/record! circuit-integration test.
#
# Unlike test/clifford/cross_validation.jl (which compares backends against
# each other), the reference here is the exponential-cost exact density
# matrix ρ = oracle_density_matrix(Γ), so system sizes are small (L ≤ 4).
#
# Two parallel validation tracks along a scripted circuit:
#   • CONSISTENCY (every step): ρ reconstructed FROM Γ must be a valid pure
#     state (trace 1, Hermitian, ρ ⪰ 0, tr ρ² ≈ 1); its Born probabilities
#     and entanglement entropies must match the covariance-matrix values.
#   • INDEPENDENCE (PauliX / measurement steps): a shadow many-body state
#     ρ_ind is evolved WITHOUT the Gaussian formalism (exact product-state
#     projector; many-body parity projectors P_s = (I + s·i·γ̂_a γ̂_b)/2 using
#     the SAME outcome s the backend sampled; many-body γ̂ operator for
#     PauliX) and must equal oracle_density_matrix(Γ) after each such step.
#     After GaussianHaar steps ρ_ind is resynchronized from Γ (unitary steps
#     are independently validated by T2's Python golden contraction values +
#     purity invariants).
#
# Standalone: julia --project=. -e 'include("test/gaussian/cross_validation.jl")'

using Test
using LinearAlgebra
using QuantumCircuitsMPS

const QCM_CV = QuantumCircuitsMPS

# ED/Pfaffian oracle (helper file, not a testset) — guarded so this file can
# share a process with test_gaussian.jl.
isdefined(@__MODULE__, :oracle_density_matrix) ||
    include(joinpath(@__DIR__, "oracle.jl"))

# ── Helpers ─────────────────────────────────────────────────────────────────

"""Partial trace of ρ (msb ordering: site 1 = most significant bit) onto
sites 1..cut."""
function _cv_partial_trace(ρ::AbstractMatrix, cut::Int, L::Int)
    dA = 2^cut
    dB = 2^(L - cut)
    ρA = zeros(ComplexF64, dA, dA)
    for a1 in 0:(dA - 1), a2 in 0:(dA - 1)
        acc = zero(ComplexF64)
        for b in 0:(dB - 1)
            acc += ρ[a1 * dB + b + 1, a2 * dB + b + 1]
        end
        ρA[a1 + 1, a2 + 1] = acc
    end
    return ρA
end

"""Von Neumann entropy (nats) of a density matrix."""
function _cv_vn_entropy(ρA::AbstractMatrix)
    λ = eigvals(Hermitian(Matrix(ρA)))
    S = 0.0
    for x in λ
        x > 1e-14 && (S -= x * log(x))
    end
    return S
end

"""CONSISTENCY track: reconstruct ρ from Γ and verify it is a valid pure
state whose Born probabilities and entanglement entropies match the
covariance-matrix values. Returns ρ (for resynchronizing ρ_ind)."""
function _cv_consistency(state, L::Int, γ::Vector{Matrix{ComplexF64}})
    Γ = state.backend.corr
    ρ = oracle_density_matrix(Γ)
    # Valid pure state
    @test abs(tr(ρ) - 1) < 1e-10
    @test norm(ρ - ρ') < 1e-10
    @test eigmin(Hermitian(Matrix(ρ))) > -1e-10
    @test abs(tr(ρ * ρ) - 1) < 1e-10
    # Born probabilities: ⟨n̂ᵢ⟩ with n̂ᵢ = (I + i γ̂_{2i−1} γ̂_{2i})/2
    for i in 1:L
        n_op = (Matrix{ComplexF64}(I, 2^L, 2^L) + im .* (γ[2i - 1] * γ[2i])) ./ 2
        p1 = real(tr(ρ * n_op))
        @test abs(p1 - born_probability(state, i, 1)) < 1e-10
        @test abs((1 - p1) - born_probability(state, i, 0)) < 1e-10
    end
    # Entanglement entropy at every prefix cut (nats)
    for cut in 1:(L - 1)
        S_ed = _cv_vn_entropy(_cv_partial_trace(ρ, cut, L))
        S_cov = EntanglementEntropy(cut = cut, base = exp(1))(state)
        @test abs(S_ed - S_cov) < 1e-10
    end
    return ρ
end

"""Read the parity eigenvalue s ∈ {−1,+1} the backend just collapsed onto,
from the post-measurement Γ element at Majorana pair (a, b): post Γ[a,b]=−s
(T8/T9 convention). Asserts the element is ±1 to 1e-10."""
function _cv_sampled_s(state, a::Int, b::Int)
    g = state.backend.corr[a, b]
    @test abs(abs(g) - 1) < 1e-10
    return g < 0 ? 1.0 : -1.0
end

"""INDEPENDENCE track: apply the many-body parity projector
P_s = (I + s·i·γ̂_a γ̂_b)/2 to ρ_ind and renormalize."""
function _cv_project!(ρ_ind, γ, a::Int, b::Int, s::Float64, dim::Int)
    P = (Matrix{ComplexF64}(I, dim, dim) + s .* im .* (γ[a] * γ[b])) ./ 2
    ρ_new = P * ρ_ind * P'
    ρ_new ./= tr(ρ_new)
    return ρ_new
end

@testset "Gaussian Cross-Validation (ED oracle)" begin

    # ═══════════════════════════════════════════════════════════════════════
    # 1. ED-oracle circuit validation: scripted circuit, forced seeds,
    #    consistency + independence tracks at L = 2, 3, 4.
    # ═══════════════════════════════════════════════════════════════════════
    @testset "scripted circuit vs exact many-body evolution (L=$L)" for L in [2, 3, 4]
        pattern = Dict(2 => "01", 3 => "010", 4 => "0110")[L]
        bits = [c == '1' for c in pattern]
        dim = 2^L

        state = SimulationState(L = L, bc = :open, backend = :gaussian,
            rng = RNGRegistry(gates_spacetime = 5, gates_realization = 15,
                born_measurement = 25, state_init = 35))
        initialize!(state, ProductState(bitstring = pattern))

        γ = majorana_matrices(L)

        # Step 0 — init: ρ from Γ must equal the exact product-state projector
        ρ = _cv_consistency(state, L, γ)
        ρ_ind = oracle_basis_projector(bits)
        @test norm(ρ_ind - ρ) < 1e-10

        # Step 1 — GaussianHaar on bond (1,2)
        apply!(state, GaussianHaar(), AdjacentPair(1))
        ρ = _cv_consistency(state, L, γ)
        ρ_ind = ρ  # resync after unitary (validated by T2 goldens + purity)

        # Step 2 — GaussianHaar on bond (L−1, L)
        apply!(state, GaussianHaar(), AdjacentPair(max(L - 1, 1)))
        ρ = _cv_consistency(state, L, γ)
        ρ_ind = ρ

        # Step 3 — PauliX on site 1: many-body operator is γ̂₂ (flips row/col
        # 2 of Γ, exactly the backend's occupation flip)
        apply!(state, PauliX(), SingleSite(1))
        ρ = _cv_consistency(state, L, γ)
        ρ_ind = γ[2] * ρ_ind * γ[2]'
        @test norm(ρ_ind - ρ) < 1e-10

        # Step 4 — Measure(:Z) on site 2 (Born-sampled by the backend)
        site = 2
        apply!(state, Measure(:Z), SingleSite(site))
        s = _cv_sampled_s(state, 2site - 1, 2site)
        ρ = _cv_consistency(state, L, γ)
        ρ_ind = _cv_project!(ρ_ind, γ, 2site - 1, 2site, s, dim)
        @test norm(ρ_ind - ρ) < 1e-10

        # Step 5 — GaussianHaar on bond (1,2)
        apply!(state, GaussianHaar(), AdjacentPair(1))
        ρ = _cv_consistency(state, L, γ)
        ρ_ind = ρ

        # Step 6 — BondParity on bond (1,2): inner Majorana pair (2, 3)
        apply!(state, BondParity(), AdjacentPair(1))
        s = _cv_sampled_s(state, 2, 3)
        ρ = _cv_consistency(state, L, γ)
        ρ_ind = _cv_project!(ρ_ind, γ, 2, 3, s, dim)
        @test norm(ρ_ind - ρ) < 1e-10
    end

    # ═══════════════════════════════════════════════════════════════════════
    # 2. Circuit integration: full simulate!/track!/record! pipeline
    #    (mirrors the Clifford Circuit Integration testset).
    # ═══════════════════════════════════════════════════════════════════════
    @testset "Circuit Integration" begin
        @testset "GaussianHaar bricklayer + monitored measurements (L=8)" begin
            L = 8
            n_steps = 5

            circuit = Circuit(L = L, bc = :open) do c
                apply!(c, GaussianHaar(), Bricklayer(:odd))
                apply!(c, GaussianHaar(), Bricklayer(:even))
                apply_with_prob!(c; outcomes = [
                    (probability = 0.2, gate = Measure(:Z), geometry = AllSites())
                ])
                record!(c, :entropy, :mi)
            end

            state = SimulationState(L = L, bc = :open, backend = :gaussian,
                rng = RNGRegistry(gates_spacetime = 42, gates_realization = 7,
                    born_measurement = 99, state_init = 1))
            initialize!(state, ProductState(binary_int = 0))
            track!(state, :entropy => EntanglementEntropy(cut = L ÷ 2))
            track!(state, :mi => MutualInformation(1:2, 7:8))

            simulate!(circuit, state; n_steps = n_steps, record_when = :marks)

            @test length(state.observables[:entropy]) == n_steps
            @test length(state.observables[:mi]) == n_steps

            # EE (bits) within [0, min(cut, L−cut)]; MI (nats) ≥ 0; all finite
            max_entropy = min(L ÷ 2, L - L ÷ 2)
            for ee_val in state.observables[:entropy]
                @test isfinite(ee_val)
                @test -1e-10 <= ee_val <= max_entropy + 1e-10
            end
            for mi_val in state.observables[:mi]
                @test isfinite(mi_val)
                @test mi_val >= -1e-10
            end

            # State stays pure through the whole monitored trajectory
            Γ = state.backend.corr
            @test maximum(abs.(Γ * Γ + I)) < 1e-10
        end

        @testset "Reset circuit (L=4)" begin
            L = 4
            circuit = Circuit(L = L, bc = :open) do c
                apply!(c, GaussianHaar(), AdjacentPair(1))
                apply!(c, Reset(), SingleSite(1))
                apply!(c, Reset(), SingleSite(2))
                record!(c, :mz)
            end

            state = SimulationState(L = L, bc = :open, backend = :gaussian,
                rng = RNGRegistry(gates_spacetime = 1, gates_realization = 2,
                    born_measurement = 42, state_init = 3))
            initialize!(state, ProductState(binary_int = 0))
            track!(state, :mz => Magnetization(:Z))

            simulate!(circuit, state; n_steps = 1, record_when = :marks)

            # Sites 1,2 reset to unoccupied; sites 3,4 never touched → Mz = 1
            @test state.observables[:mz][end] ≈ 1.0 atol = 1e-12
        end
    end
end
