# test/gaussian/cross_validation.jl
# Cross-validation of the Gaussian (covariance-matrix) backend against the
# EXACT many-body ED/Pfaffian oracle (test/gaussian/oracle.jl), plus a
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
#   • INDEPENDENCE (measurement steps): a shadow many-body state ρ_ind is
#     evolved WITHOUT the Gaussian formalism (exact product-state projector;
#     many-body parity projectors P_s = (I + s·i·γ̂_a γ̂_b)/2 using the SAME
#     outcome s the backend sampled) and must equal oracle_density_matrix(Γ)
#     after each such step. After GaussianHaar steps ρ_ind is resynchronized
#     from Γ (unitary steps are independently validated by the Python golden
#     contraction values + purity invariants).
#
# A third testset pins the FERMIONIC-vs-SPIN region-entropy contract: the
# covariance-matrix entropy of a site region equals the Jordan-Wigner spin
# partial-trace entropy exactly when the region or its complement is a
# contiguous block, and differs for doubly non-contiguous regions.
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

"""Reduced density matrix of the SPIN sites `keep` (any order) of ρ in msb
ordering, i.e. the partial trace over the complementary spins — the quantity
a qubit backend reports for a site region after Jordan-Wigner."""
function _cv_spin_rdm(ρ::AbstractMatrix, keep::AbstractVector{Int}, L::Int)
    keep = sort(keep)
    rest = setdiff(1:L, keep)
    # Column-major reshape: tensor axis k holds site L−k+1 (site 1 = msb).
    T = reshape(Matrix(ρ), ntuple(_ -> 2, 2L))
    ax(s) = L - s + 1
    perm = vcat(ax.(keep), ax.(rest), ax.(keep) .+ L, ax.(rest) .+ L)
    T = permutedims(T, perm)
    dk, dr = 2^length(keep), 2^length(rest)
    T = reshape(T, dk, dr, dk, dr)
    ρA = zeros(ComplexF64, dk, dk)
    for r in 1:dr
        ρA .+= T[:, r, :, r]
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
    # Born probabilities: ⟨n̂ᵢ⟩ with n̂ᵢ = (I − i γ̂_{2i−1} γ̂_{2i})/2
    for i in 1:L
        n_op = (Matrix{ComplexF64}(I, 2^L, 2^L) - im .* (γ[2i - 1] * γ[2i])) ./ 2
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

"""Read the parity eigenvalue s ∈ {−1,+1} of i γ̂_a γ̂_b the backend just
collapsed onto, from the post-measurement Γ element at Majorana pair (a, b):
Γ[a,b] = ⟨i γ̂_a γ̂_b⟩ = s. Asserts the element is ±1 to 1e-10."""
function _cv_sampled_s(state, a::Int, b::Int)
    g = state.backend.corr[a, b]
    @test abs(abs(g) - 1) < 1e-10
    return g < 0 ? -1.0 : 1.0
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
        ρ_ind = ρ  # resync after unitary (validated by goldens + purity)

        # Step 2 — GaussianHaar on bond (L−1, L)
        apply!(state, GaussianHaar(), AdjacentPair(max(L - 1, 1)))
        ρ = _cv_consistency(state, L, γ)
        ρ_ind = ρ

        # Step 3 — Measure(:Z) on site 1 (Born-sampled by the backend); the
        # independence track applies the exact parity projector for the
        # outcome the backend drew
        site = 1
        apply!(state, Measure(:Z), SingleSite(site))
        s = _cv_sampled_s(state, 2site - 1, 2site)
        ρ = _cv_consistency(state, L, γ)
        ρ_ind = _cv_project!(ρ_ind, γ, 2site - 1, 2site, s, dim)
        @test norm(ρ_ind - ρ) < 1e-10

        # Step 4 — Measure(:Z) on site 2
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
    # 1b. Fermionic-mode vs Jordan-Wigner spin region entropy. The covariance
    #     entropy of a site region is the entropy of those fermionic MODES;
    #     it equals the spin partial-trace entropy iff the region or its
    #     complement is one contiguous block (then the Jordan-Wigner strings
    #     stay inside one side of the cut). Pins the contract documented in
    #     docs/src/backends/gaussian.md ("Fermionic vs. spin subsystems").
    # ═══════════════════════════════════════════════════════════════════════
    @testset "region entropy: fermionic == spin iff region or complement contiguous (L=4)" begin
        L = 4
        state = SimulationState(L = L, bc = :periodic, backend = :gaussian,
            rng = RNGRegistry(gates_spacetime = 6, gates_realization = 16,
                born_measurement = 26, state_init = 36))
        initialize!(state, RandomGaussianState())
        ρ = oracle_density_matrix(state.backend.corr)
        @test abs(tr(ρ * ρ) - 1) < 1e-10

        S_f(region) = EntanglementEntropy(cut = region, base = exp(1))(state)
        S_s(region) = _cv_vn_entropy(_cv_spin_rdm(ρ, region, L))

        # Region or complement contiguous → identical, including PBC wraps
        # (whose complement is a block) and prefixes (the cut::Int path).
        contiguous_or_cocontiguous = ([1], [2], [1, 2], [2, 3], [3, 4], [2, 3, 4],
            [4, 1], [1, 4], [1, 3, 4])
        for region in contiguous_or_cocontiguous
            @test abs(S_f(region) - S_s(region)) < 1e-10
        end
        @test abs(S_f([1, 2]) - EntanglementEntropy(cut = 2, base = exp(1))(state)) < 1e-12

        # Doubly non-contiguous → genuinely different numbers (both finite,
        # both ≥ 0). A random Gaussian state separates them by O(1).
        for region in ([1, 3], [2, 4])
            sf, ss = S_f(region), S_s(region)
            @test isfinite(sf) && isfinite(ss) && sf >= -1e-12 && ss >= -1e-12
            @test abs(sf - ss) > 1e-3
        end
        # MutualInformation([1],[3]) inherits the difference through S({1,3});
        # adjacent blocks do not.
        mi_f(A, B) = MutualInformation(A, B; base = exp(1))(state)
        mi_s(A, B) = S_s(A) + S_s(B) - S_s(vcat(A, B))
        @test abs(mi_f([1], [2]) - mi_s([1], [2])) < 1e-10
        @test abs(mi_f([1], [3]) - mi_s([1], [3])) > 1e-3

        # The closed-form example from the guide: |ψ⟩ = ½(1 + c₁†c₃†)(1 + c₂†c₄†)|0⟩,
        # a product of a pure pair state on modes {1,3} and one on {2,4}, so
        # the fermionic S({1,3}) is exactly 0. Its Jordan-Wigner image is
        # ½(|0000⟩ + |0101⟩ + |1010⟩ − |1111⟩): the sign on the last term
        # (c₃† passing the particle at site 2) makes spins {1,3} share one
        # bit with {2,4}, so the spin partial-trace entropy is ln 2.
        γ4 = majorana_matrices(L)
        ψ = zeros(ComplexF64, 2^L)
        ψ[0b0000 + 1] = 0.5
        ψ[0b0101 + 1] = 0.5
        ψ[0b1010 + 1] = 0.5
        ψ[0b1111 + 1] = -0.5
        ρψ = ψ * ψ'
        Γψ = [a == b ? 0.0 : real(tr(ρψ * (im .* (γ4[a] * γ4[b]))))
              for a in 1:2L, b in 1:2L]
        @test norm(Γψ * Γψ + I) < 1e-12                      # pure Gaussian state
        @test norm(oracle_density_matrix(Γψ) - ρψ) < 1e-10    # Γ ↔ |ψ⟩ round-trips
        pair_state = SimulationState(L = L, bc = :open, backend = :gaussian,
            rng = RNGRegistry(gates_spacetime = 7, gates_realization = 17,
                born_measurement = 27, state_init = 37))
        initialize!(pair_state, ProductState(binary_int = 0))
        pair_state.backend.corr .= Γψ
        @test abs(EntanglementEntropy(cut = [1, 3], base = exp(1))(pair_state)) < 1e-12
        @test abs(_cv_vn_entropy(_cv_spin_rdm(ρψ, [1, 3], L)) - log(2)) < 1e-12
        # Contiguous region: both pictures agree (one bit across the cut).
        @test abs(EntanglementEntropy(cut = [1, 2], base = exp(1))(pair_state) -
                  _cv_vn_entropy(_cv_spin_rdm(ρψ, [1, 2], L))) < 1e-12
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

        @testset "Reset inside a Circuit is rejected before the Born draw (L=4)" begin
            L = 4
            circuit = Circuit(L = L, bc = :open) do c
                apply!(c, GaussianHaar(), AdjacentPair(1))
                apply!(c, Reset(), SingleSite(1))
                record!(c, :mz)
            end

            state = SimulationState(L = L, bc = :open, backend = :gaussian,
                rng = RNGRegistry(gates_spacetime = 1, gates_realization = 2,
                    born_measurement = 42, state_init = 3))
            initialize!(state, ProductState(binary_int = 0))
            track!(state, :mz => Magnetization(:Z))
            born_before = copy(QuantumCircuitsMPS.get_rng(state.rng_registry, :born_measurement))

            err = try
                simulate!(circuit, state; n_steps = 1, record_when = :marks)
                nothing
            catch e
                e
            end
            @test err isa ArgumentError
            @test occursin("Reset", err.msg)
            @test occursin("Gaussian", err.msg)
            # The GaussianHaar before it ran; the Reset consumed no Born draw.
            @test rand(copy(QuantumCircuitsMPS.get_rng(state.rng_registry, :born_measurement))) ==
                  rand(copy(born_before))
            @test isempty(state.observables[:mz])          # the record! was never reached
        end
    end
end
