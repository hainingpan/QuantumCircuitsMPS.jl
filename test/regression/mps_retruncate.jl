# test/regression/mps_retruncate.jl
#
# === MPS projective gates: gauge-center normalization and `retruncate` ===
#
# A projective gate on the MPS backend used to end with `normalize!(mps)` and
# a full-chain `truncate!(mps; cutoff)`. Two things made that expensive:
#
#   1. `_write_op_block!` left the MPS ortho limits spanning the whole gate
#      range after a multi-site SVD chain, although the gauge center is at the
#      range's last site. `normalize!` therefore fell back to a full-chain
#      inner product, and the next `orthogonalize!` re-factorized tensors that
#      were already left-orthonormal. The limits are now set to the true
#      center.
#   2. The full-chain `truncate!` costs two O(L) sweeps per projective gate —
#      O(pL²) per layer of measurements at rate p, against O(L) for the
#      unitaries. It is now opt-in via `SimulationState(; retruncate = :gate)`;
#      the default `:never` only truncates the bonds inside the gate's range,
#      like a unitary.
#
# Test groups:
#   1. The `retruncate` keyword: default, validation, accepted on other backends.
#   2. Ortho-limit bookkeeping after single-site, adjacent, non-adjacent (SVD
#      chain over three tensors) and PBC-folded gates: `isortho`, the center at
#      the gate's last RAM site, every tensor left/right of it orthonormal.
#   3. Projective gates under `:never`: unit norm, center at the gate's last
#      RAM site, bonds within `maxdim`; a fully measured chain is a product
#      state for every observable even though no bond was recompressed.
#   4. `:never`, `:gate` and the exact state vector agree on a seeded MIPT
#      trajectory (same measurement record, entropies to truncation accuracy).

using Test
using Random
using LinearAlgebra: norm
using ITensors: ITensor, Index, dag, delta, prime, inds, dim, array
using ITensorMPS: isortho, orthocenter, ortho_lims, linkind, linkdims, maxlinkdim
using QuantumCircuitsMPS
using QuantumCircuitsMPS: measurements

# --- helpers (file-local, `_rt_` prefixed: runtests.jl shares one scope) ---

function _rt_rng(seed)
    RNGRegistry(gates_spacetime = seed, gates_realization = seed + 1,
        born_measurement = seed + 2)
end

# Entangled qubit state (two Haar bricklayers) so every bond is non-trivial.
function _rt_entangled(; L, bc, seed, kwargs...)
    state = SimulationState(L = L, bc = bc, maxdim = 64, rng = _rt_rng(seed); kwargs...)
    initialize!(state, ProductState(binary_int = 0))
    apply!(state, HaarRandom(2), Bricklayer(:even))
    apply!(state, HaarRandom(2), Bricklayer(:odd))
    return state
end

# ‖A†A − I‖ over the link `l` of tensor `A` (all other indices contracted):
# 0 iff `A` is an isometry onto `l`.
function _rt_isometry_defect(A::ITensor, l::Index)
    G = prime(dag(A), l) * A
    return norm(array(G) - [i == j ? 1.0 : 0.0 for i in 1:dim(l), j in 1:dim(l)])
end

# The ortho limits are only bookkeeping; this checks they are TRUE: every
# tensor left of the center is left-orthonormal, every tensor right of it is
# right-orthonormal.
function _rt_gauge_is_true(mps; atol = 1e-12)
    isortho(mps) || return false
    c = orthocenter(mps)
    N = length(mps)
    for j in 1:(c - 1)
        _rt_isometry_defect(mps[j], linkind(mps, j)) < atol || return false
    end
    for j in (c + 1):N
        _rt_isometry_defect(mps[j], linkind(mps, j - 1)) < atol || return false
    end
    return true
end

# Last RAM site touched by a gate on `phy_sites`.
_rt_last_ram(state, phy_sites) = maximum(state.phy_ram[s] for s in phy_sites)

function _rt_mipt_circuit(L, p)
    return Circuit(L = L, bc = :open) do c
        apply!(c, HaarRandom(2), Bricklayer(:even))
        apply_with_prob!(c; outcomes = [
            (probability = p, gate = Measure(:Z), geometry = AllSites())])
        apply!(c, HaarRandom(2), Bricklayer(:odd))
        apply_with_prob!(c; outcomes = [
            (probability = p, gate = Measure(:Z), geometry = AllSites())])
    end
end

function _rt_run_mipt(; L, p, n_steps, seed, backend, kwargs...)
    state = SimulationState(L = L, bc = :open, backend = backend, rng = _rt_rng(seed),
        log_events = true; kwargs...)
    initialize!(state, ProductState(binary_int = 0))
    track!(state, :S => EntanglementEntropy(cut = L ÷ 2))
    track!(state, :mz => Magnetization(:Z))
    simulate!(_rt_mipt_circuit(L, p), state; n_steps = n_steps, record_when = :every_step)
    return state
end

@testset "REGRESSION mps_retruncate" begin

    # ------------------------------------------------------------------
    # 1. The keyword
    # ------------------------------------------------------------------
    @testset "retruncate keyword" begin
        s = SimulationState(L = 4, bc = :open)
        @test s.backend.retruncate == :never
        @test SimulationState(L = 4, bc = :open, retruncate = :gate).backend.retruncate ==
              :gate
        err = try
            SimulationState(L = 4, bc = :open, retruncate = :step)
            nothing
        catch e
            e
        end
        @test err isa ArgumentError
        @test occursin("retruncate", sprint(showerror, err))
        # Accepted and ignored on the other backends (cross-backend API consistency).
        @test SimulationState(L = 4, bc = :open, backend = :statevector, retruncate = :gate) isa
              SimulationState
        @test SimulationState(L = 4, bc = :open, backend = :clifford, retruncate = :gate) isa
              SimulationState
        @test SimulationState(L = 4, bc = :open, backend = :gaussian, retruncate = :gate) isa
              SimulationState
    end

    # ------------------------------------------------------------------
    # 2. Ortho limits tell the truth after every write path
    # ------------------------------------------------------------------
    @testset "gauge center at the gate's last RAM site (bc=$bc)" for bc in (:open, :periodic)
        L = 8
        # Single-site unitary (direct assignment path)
        s = _rt_entangled(L = L, bc = bc, seed = 5)
        apply!(s, PauliX(), SingleSite(3))
        @test _rt_gauge_is_true(s.backend.mps)
        @test orthocenter(s.backend.mps) == _rt_last_ram(s, [3])

        # Adjacent pair (two-tensor SVD chain)
        for site in (1, 4, L - 1)
            s = _rt_entangled(L = L, bc = bc, seed = 6)
            apply!(s, HaarRandom(2), AdjacentPair(site))
            pair = [site, mod1(site + 1, L)]
            @test _rt_gauge_is_true(s.backend.mps)
            @test orthocenter(s.backend.mps) == _rt_last_ram(s, pair)
        end

        # Non-adjacent pair: the chain runs over three tensors
        s = _rt_entangled(L = L, bc = bc, seed = 7)
        apply!(s, CZ(), Sites([2, 4]))
        @test _rt_gauge_is_true(s.backend.mps)
        @test orthocenter(s.backend.mps) == _rt_last_ram(s, [2, 4])

        # Projective single-site and two-site gates
        s = _rt_entangled(L = L, bc = bc, seed = 8)
        apply!(s, Measure(:Z), [5])
        @test _rt_gauge_is_true(s.backend.mps)
        @test orthocenter(s.backend.mps) == _rt_last_ram(s, [5])
        apply!(s, Projection(0), [2])
        @test _rt_gauge_is_true(s.backend.mps)
        @test orthocenter(s.backend.mps) == _rt_last_ram(s, [2])
    end

    @testset "PBC wrap pair spans the fold" begin
        # Under PBC the pair (L, 1) is folded onto RAM sites that are not
        # adjacent; the SVD chain then covers several tensors.
        L = 8
        s = _rt_entangled(L = L, bc = :periodic, seed = 9)
        ram = [s.phy_ram[L], s.phy_ram[1]]
        @test abs(ram[1] - ram[2]) >= 1
        apply!(s, HaarRandom(2), AdjacentPair(L))
        @test _rt_gauge_is_true(s.backend.mps)
        @test orthocenter(s.backend.mps) == maximum(ram)
    end

    @testset "S=1 two-site projector: center at the last RAM site, unit norm" begin
        L = 6
        s = SimulationState(
            L = L, bc = :open, site_type = "S=1", maxdim = 64, rng = _rt_rng(10))
        initialize!(s, ProductState(spin_state = "Z0"))
        apply!(s, HaarRandom(2), Bricklayer(:even))
        apply!(s, HaarRandom(2), Bricklayer(:odd))
        P01 = total_spin_projector(0) + total_spin_projector(1)
        apply!(s, SpinSectorProjection(P01), [3, 4])
        @test _rt_gauge_is_true(s.backend.mps)
        @test orthocenter(s.backend.mps) == 4
        @test norm(s.backend.mps) ≈ 1.0 atol = 1e-12
    end

    # ------------------------------------------------------------------
    # 3. Projective gates under the default :never
    # ------------------------------------------------------------------
    @testset "projective gate: unit norm, bonds within maxdim, nothing else touched" begin
        L = 10
        s = _rt_entangled(L = L, bc = :open, seed = 11)
        # A truncating step first (both sublayers, so every bond has been
        # SVD-truncated at the new maxdim), so the input norm is < 1
        # (unitaries are not renormalized) and the gate has something to
        # normalize.
        s.backend.maxdim = 3
        apply!(s, HaarRandom(2), Bricklayer(:even))
        apply!(s, HaarRandom(2), Bricklayer(:odd))
        @test norm(s.backend.mps) < 1 - 1e-6
        dims_before = linkdims(s.backend.mps)
        apply!(s, Measure(:Z), [5])
        @test norm(s.backend.mps) ≈ 1.0 atol = 1e-12
        @test maxlinkdim(s.backend.mps) <= 3
        @test _rt_gauge_is_true(s.backend.mps)
        # A single-site projection writes one tensor: no bond dimension changes.
        @test linkdims(s.backend.mps) == dims_before
    end

    @testset "fully measured chain is a product state without any recompression" begin
        L = 8
        s = _rt_entangled(L = L, bc = :open, seed = 12)
        outcomes = Int[]
        for site in 1:L
            apply!(s, Measure(:Z), [site])
            push!(outcomes, born_probability(s, site, 1) > 0.5 ? 1 : 0)
        end
        # Bonds were never recompressed (no truncate!, no SVD on a 1-site write)...
        @test maxlinkdim(s.backend.mps) > 1
        # ...yet the state is the measured product state for every observable.
        @test norm(s.backend.mps) ≈ 1.0 atol = 1e-12
        for site in 1:L
            @test born_probability(s, site, outcomes[site]) ≈ 1.0 atol = 1e-12
        end
        for cut in 1:(L - 1)
            @test EntanglementEntropy(cut = cut)(s) ≈ 0.0 atol = 1e-10
        end
        # The next unitary layer compresses the bonds it touches: each
        # in-pair bond (1|2), (3|4), ... of the (1,2),(3,4),... sublayer is
        # SVD'd, and a two-site gate on a product state has Schmidt rank <= 2
        # there.
        apply!(s, HaarRandom(2), Bricklayer(:odd))
        @test all(linkdims(s.backend.mps)[1:2:(L - 1)] .<= 2)
    end

    # ------------------------------------------------------------------
    # 4. :never vs :gate vs the exact state vector on one seeded trajectory
    # ------------------------------------------------------------------
    @testset "seeded MIPT trajectory: :never, :gate and statevector agree" begin
        L, p, n_steps, seed = 8, 0.3, 6, 13
        # cutoff=1e-14 so that the MPS trajectories are exact to ~1e-10 and
        # the two retruncate settings can only differ at that level.
        s_never = _rt_run_mipt(L = L, p = p, n_steps = n_steps, seed = seed,
            backend = :mps, maxdim = 64, cutoff = 1e-14, retruncate = :never)
        s_gate = _rt_run_mipt(L = L, p = p, n_steps = n_steps, seed = seed,
            backend = :mps, maxdim = 64, cutoff = 1e-14, retruncate = :gate)
        s_sv = _rt_run_mipt(L = L, p = p, n_steps = n_steps, seed = seed,
            backend = :statevector)

        rec(state) = [(m.step, m.sites, m.outcome) for m in measurements(state)]
        @test length(rec(s_never)) > 0
        @test rec(s_never) == rec(s_gate) == rec(s_sv)

        for key in (:S, :mz)
            a, b, c = s_never.observables[key], s_gate.observables[key],
            s_sv.observables[key]
            @test length(a) == n_steps
            @test maximum(abs.(a .- b)) < 1e-9
            @test maximum(abs.(a .- c)) < 1e-9
        end
        @test maximum(s_never.observables[:S]) > 0.1
        @test norm(s_never.backend.mps) ≈ 1.0 atol = 1e-10
        @test norm(s_gate.backend.mps) ≈ 1.0 atol = 1e-10
    end
end
