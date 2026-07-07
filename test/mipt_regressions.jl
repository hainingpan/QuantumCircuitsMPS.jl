# test/mipt_regressions.jl
# Regression tests for bugs found during the MIPT debugging session:
#   1. Statevector lockstep  — MPS entropy must match a dense state-vector reference
#   2. Born statistics       — measurement outcomes must follow the Born rule
#   3. Parity artifact       — phase-averaged entropy must collapse (area law) at p=0.5
#   4. RAM bipartition       — folded PBC basis mapping must be correct
# Full analysis: docs/mipt_debug_report.md

using Test
using QuantumCircuitsMPS
using LinearAlgebra
using Statistics
using ITensors
using ITensorMPS

"""
Dense reference: contract the MPS to a full state vector and compute the
von Neumann entropy (bits) across the cut after the first `cut` sites.
Only valid for OBC (RAM order == physical order).
"""
function _dense_entropy_halfcut(state, cut::Int)
    T = contract(state.mps)                    # single ITensor with L site indices
    ψ = Array(T, state.sites...)               # dims ordered as sites 1..L (RAM = physical for OBC)
    d = state.local_dim
    M = reshape(ψ, d^cut, :)                   # rows = sites 1..cut, cols = rest
    sv = svdvals(M)
    p = sv .^ 2
    p = p[p .> 1e-16]
    p ./= sum(p)                               # guard against non-unit norm
    return -sum(p .* log2.(p))
end

@testset "Statevector lockstep: MPS entropy matches dense state vector" begin
    # Bug guarded: MPS entropy silently diverging from the exact state-vector
    # result (truncation / normalization errors). With maxdim=2^L and an
    # ultra-tight cutoff the MPS is exact, so the entropy must agree with a
    # dense SVD calculation to machine-ish precision at EVERY recorded step.
    L = 6
    cut = L ÷ 2
    for seed in 1:3
        state = SimulationState(L = L, bc = :open, maxdim = 2^L, cutoff = 1e-14,
            rng = RNGRegistry(gates_spacetime = 3*(seed-1)+1,
                born_measurement = 3*(seed-1)+2,
                gates_realization = 3*(seed-1)+3))
        initialize!(state, ProductState(binary_int = 0))
        track!(state, :entropy => EntanglementEntropy(cut = cut))

        circuit = Circuit(L = L, bc = :open) do c
            apply!(c, HaarRandom(), Bricklayer(:even))
            apply!(c, HaarRandom(), Bricklayer(:odd))
        end

        for step in 1:4
            simulate!(circuit, state; n_steps = 1, record_when = :every_step)
            S_mps = state.observables[:entropy][end]
            S_dense = _dense_entropy_halfcut(state, cut)
            @test abs(S_mps - S_dense) < 1e-8
        end

        # Sanity: entropies are physical (0 <= S <= cut qubits)
        S_vals = state.observables[:entropy]
        @test length(S_vals) == 4
        @test all(s -> -1e-12 <= s <= cut + 1e-10, S_vals)
    end
end

@testset "Born statistics: measurement outcomes match Born rule" begin
    # Bug guarded: measurement sampling not following Born probabilities
    # (e.g. missing norm division before sampling).
    #
    # Part A: exact Born probabilities on the initial product state.
    L = 4
    state0 = SimulationState(L = L, bc = :open)
    initialize!(state0, ProductState(binary_int = 0))
    for site in 1:L
        p0 = born_probability(state0, site, 0)
        p1 = born_probability(state0, site, 1)
        @test p0 ≈ 1.0 atol=1e-10
        @test p1 ≈ 0.0 atol=1e-10
        @test abs(p0 + p1 - 1.0) < 1e-10   # normalization
    end

    # Part B: sampled outcome frequencies match the pre-measurement Born
    # probability. The Haar gate is DETERMINISTIC across trials (fixed
    # gates_realization seed); only the Born-measurement stream varies.
    N = 400
    haar_circuit = Circuit(L = L, bc = :open) do c
        apply!(c, HaarRandom(), Bricklayer(:odd))   # pairs (1,2),(3,4)
    end
    meas_circuit = Circuit(L = L, bc = :open) do c
        apply!(c, Measure(:Z), SingleSite(1))
    end

    p0_expected = NaN
    n_zero = 0
    gate_deterministic = true
    all_collapsed = true
    all_normalized = true
    for trial in 1:N
        state = SimulationState(L = L, bc = :open, maxdim = 16, cutoff = 1e-14,
            rng = RNGRegistry(gates_spacetime = 1,
                born_measurement = 1000 + trial,
                gates_realization = 7))
        initialize!(state, ProductState(binary_int = 0))
        simulate!(haar_circuit, state; n_steps = 1, record_when = :final_only)

        p0 = born_probability(state, 1, 0)
        p1 = born_probability(state, 1, 1)
        all_normalized &= abs(p0 + p1 - 1.0) < 1e-8
        if trial == 1
            p0_expected = p0
        else
            gate_deterministic &= abs(p0 - p0_expected) < 1e-10
        end

        simulate!(meas_circuit, state; n_steps = 1, record_when = :final_only)
        p0_after = born_probability(state, 1, 0)
        all_collapsed &= (p0_after > 1 - 1e-8) || (p0_after < 1e-8)
        n_zero += (p0_after > 0.5)
    end

    @test gate_deterministic
    @test all_normalized
    @test all_collapsed
    @test 0.0 < p0_expected < 1.0

    freq0 = n_zero / N
    sem = sqrt(p0_expected * (1 - p0_expected) / N)
    tol = max(4 * sem, 0.02)
    @test abs(freq0 - p0_expected) < tol
end

@testset "Phase-averaged entropy: area-law collapse at high measurement rate" begin
    # Bug guarded: parity artifact — recording entropy only once per full
    # period made S(L) zigzag with L (e.g. S(8) < S(6)). Phase-averaged
    # recording (after EACH measurement round) must give L-independent
    # entropy deep in the area-law phase (p=0.5).
    # Mirrors the phase-averaged recording protocol (full analysis: validation-srn branch).
    function phase_avg_S(; L, p, seed, bc = :open, n_steps = 2*L, maxdim = 2^20,
            cutoff = 1e-10, burn_in = max(L, 8))
        circuit_half1 = Circuit(L = L, bc = bc, p = p) do c
            apply!(c, HaarRandom(), Bricklayer(:even))
            apply_with_prob!(c;
                outcomes = [
                    (probability = c.params[:p],
                    gate = Measure(:Z), geometry = AllSites())
                ])
        end
        circuit_half2 = Circuit(L = L, bc = bc, p = p) do c
            apply!(c, HaarRandom(), Bricklayer(:odd))
            apply_with_prob!(c;
                outcomes = [
                    (probability = c.params[:p],
                    gate = Measure(:Z), geometry = AllSites())
                ])
        end

        state = SimulationState(L = L, bc = bc, maxdim = maxdim, cutoff = cutoff,
            rng = RNGRegistry(gates_spacetime = 3*(seed-1)+1,
                born_measurement = 3*(seed-1)+2,
                gates_realization = 3*(seed-1)+3))
        initialize!(state, ProductState(binary_int = 0))
        track!(state, :entropy => EntanglementEntropy(cut = L÷2))

        for period in 1:n_steps
            simulate!(circuit_half1, state; n_steps = 1, record_when = :every_step)
            simulate!(circuit_half2, state; n_steps = 1, record_when = :every_step)
        end

        records = state.observables[:entropy]
        post_burn = records[(2 * burn_in + 1):end]
        n_avg_periods = min(4, length(post_burn) ÷ 2)
        post_burn_tail = post_burn[(end - 2 * n_avg_periods + 1):end]
        return mean(post_burn_tail)
    end

    p = 0.5
    S6 = [phase_avg_S(L = 6, p = p, seed = s) for s in 1:50]
    S8 = [phase_avg_S(L = 8, p = p, seed = s) for s in 51:100]

    mean6, mean8 = mean(S6), mean(S8)
    sem6 = std(S6) / sqrt(length(S6))
    sem8 = std(S8) / sqrt(length(S8))

    delta = abs(mean6 - mean8)
    tol = max(3 * (sem6 + sem8), 0.1)

    @test delta < tol   # area law: S is L-independent at p=0.5
    @info "Phase-averaged S regression" mean6=round(mean6, digits = 4) mean8=round(mean8, digits = 4) delta=round(
        delta, digits = 4) tol=round(tol, digits = 4)
end

@testset "RAM bipartition: compute_basis_mapping returns correct folded order" begin
    # Bug guarded: wrong RAM<->physical mapping for the folded PBC basis,
    # which silently corrupts the bipartition used for entanglement cuts.
    # For L=8 PBC the folded RAM order must interleave sites from both ends.

    # Backward-compat guard: pbc_fold_start=1 reproduces the original
    # hardcoded fold order exactly (pre-pbc_fold_start behavior).
    phy_ram, ram_phy = QuantumCircuitsMPS.compute_basis_mapping(8, :periodic; pbc_fold_start = 1)
    @test ram_phy == [1, 8, 2, 7, 3, 6, 4, 5]

    # Default pbc_fold_start (L÷4+1): fold origin shifted for half-cut alignment.
    phy_ram, ram_phy = QuantumCircuitsMPS.compute_basis_mapping(8, :periodic)
    @test ram_phy == [3, 2, 4, 1, 5, 8, 6, 7]

    # Valid permutations
    @test sort(ram_phy) == collect(1:8)
    @test sort(phy_ram) == collect(1:8)

    # Exact inverse relationship
    for i in 1:8
        @test ram_phy[phy_ram[i]] == i
        @test phy_ram[ram_phy[i]] == i
    end

    # OBC: identity mapping (no folding)
    phy_ram_obc, ram_phy_obc = QuantumCircuitsMPS.compute_basis_mapping(8, :open)
    @test ram_phy_obc == collect(1:8)
    @test phy_ram_obc == collect(1:8)

    # Half-cut alignment property: with the default fold origin, the first
    # half of the RAM order must be exactly the first half of physical sites
    # (as a set), for a range of even L.
    for L in [4, 6, 8, 10, 12]
        _, ram_phy_L = QuantumCircuitsMPS.compute_basis_mapping(L, :periodic)
        @test Set(ram_phy_L[1:(L ÷ 2)]) == Set(1:(L ÷ 2))
    end

    # Mutual-inverse property holds for the default fold across L.
    for L in [4, 6, 8, 10, 12]
        phy_ram_L, ram_phy_L = QuantumCircuitsMPS.compute_basis_mapping(L, :periodic)
        for i in 1:L
            @test ram_phy_L[phy_ram_L[i]] == i
            @test phy_ram_L[ram_phy_L[i]] == i
        end
    end

    # OBC ignores pbc_fold_start entirely (identity mapping regardless).
    _, ram_phy_obc2 = QuantumCircuitsMPS.compute_basis_mapping(8, :open; pbc_fold_start = 5)
    @test ram_phy_obc2 == collect(1:8)

    # Invalid pbc_fold_start values must be rejected for periodic BC.
    @test_throws ArgumentError QuantumCircuitsMPS.compute_basis_mapping(8, :periodic; pbc_fold_start = 0)
    @test_throws ArgumentError QuantumCircuitsMPS.compute_basis_mapping(8, :periodic; pbc_fold_start = 9)
end
