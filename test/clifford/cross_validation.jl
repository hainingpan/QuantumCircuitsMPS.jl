# test/clifford/cross_validation.jl
# Cross-validation: the Clifford (stabilizer-tableau) backend produces
# IDENTICAL physics to the MPS and state-vector backends for pure-Clifford
# circuits, given the SAME RNG seeds. This is the ultimate correctness proof
# that the native tableau code path (QuantumClifford.jl) and the dense
# gate_matrix/QuantumOpticsBase code path (MPS/SV) converge on the same
# physics for every gate/geometry/measurement combination.
#
# IMPORTANT: HaarRandom is NEVER used in this file — the Clifford backend
# rejects it by design (see src/Clifford/Clifford.jl's fallback
# _apply_single! method). Only Clifford-group gates are used:
# Hadamard, PhaseGate, PauliX/Y/Z, CNOT, CZ, SWAP, RandomClifford.

using Test
using QuantumCircuitsMPS

const QCM = QuantumCircuitsMPS

# ── Helper: build one SimulationState of a given backend with given seeds ──
function _make_state(L::Int, backend::Symbol;
        bc=:open, seeds=(gates_spacetime=42, gates_realization=7, born_measurement=99))
    state = SimulationState(L=L, bc=bc, backend=backend,
        rng=RNGRegistry(; seeds...))
    initialize!(state, ProductState(binary_int=0))
    return state
end

# ── Helper: build the SAME (mps, sv, clifford) triple, identical seeds ──────
function make_triple(; L, bc=:open,
        seeds=(gates_spacetime=42, gates_realization=7, born_measurement=99))
    mps_s = _make_state(L, :mps; bc=bc, seeds=seeds)
    sv_s  = _make_state(L, :statevector; bc=bc, seeds=seeds)
    cl_s  = _make_state(L, :clifford; bc=bc, seeds=seeds)
    return mps_s, sv_s, cl_s
end

@testset "Clifford Cross-Validation (MPS / SV / Clifford)" begin

    # ═══════════════════════════════════════════════════════════════════════
    # 1. Deterministic circuit (no measurement):
    #    H(site 1), CNOT(1,2), CZ(2,3)
    #    Compare born_probability at EVERY site, BOTH outcomes, across ALL
    #    THREE backend pairs. Exact match expected (tolerance atol=1e-12).
    # ═══════════════════════════════════════════════════════════════════════
    @testset "Circuit 1: H + CNOT + CZ (deterministic) — L=$L" for L in [4, 6]
        mps_s, sv_s, cl_s = make_triple(L=L)

        function apply_circuit1!(state)
            apply!(state, Hadamard(), SingleSite(1))
            apply!(state, CNOT(), AdjacentPair(1))   # CNOT(1,2)
            apply!(state, CZ(),   AdjacentPair(2))   # CZ(2,3)
            return state
        end

        apply_circuit1!(mps_s)
        apply_circuit1!(sv_s)
        apply_circuit1!(cl_s)

        for site in 1:L
            for outcome in 0:1
                p_mps = born_probability(mps_s, site, outcome)
                p_sv  = born_probability(sv_s,  site, outcome)
                p_cl  = born_probability(cl_s,  site, outcome)

                @test p_mps ≈ p_sv atol=1e-12   # control baseline
                @test p_mps ≈ p_cl atol=1e-12   # mps vs clifford
                @test p_sv  ≈ p_cl atol=1e-12   # sv vs clifford
            end
        end

        # Guard against a trivially-passing all-deterministic-but-wrong test:
        # site 1 after H should be in superposition BEFORE the CNOT/CZ, and
        # after CNOT/CZ the joint state is still non-classical for site 1,2 —
        # verify the state is not simply the all-|0⟩ product state.
        @test !isapprox(born_probability(mps_s, 1, 0), 1.0; atol=1e-9)
    end

    # ═══════════════════════════════════════════════════════════════════════
    # 2. RandomClifford bricklayer + explicit-site measurement
    #    Bricklayer(:odd) then Bricklayer(:even) of RandomClifford(2), then
    #    Measure(:Z) at sites 1 and 3 only (not all sites).
    #    Compare EntanglementEntropy (mid-chain cut) and Magnetization(:Z).
    # ═══════════════════════════════════════════════════════════════════════
    @testset "Circuit 2: RandomClifford bricklayer + partial measurement — L=$L" for L in [4, 6]
        seeds = (gates_spacetime=42, gates_realization=7, born_measurement=99)
        mps_s, sv_s, cl_s = make_triple(L=L, seeds=seeds)

        function apply_circuit2!(state, L)
            apply!(state, RandomClifford(2), Bricklayer(:odd))
            apply!(state, RandomClifford(2), Bricklayer(:even))
            apply!(state, Measure(:Z), SingleSite(1))
            apply!(state, Measure(:Z), SingleSite(3))
            return state
        end

        apply_circuit2!(mps_s, L)
        apply_circuit2!(sv_s, L)
        apply_circuit2!(cl_s, L)

        ee = EntanglementEntropy(cut=L ÷ 2)
        mz = Magnetization(:Z)

        e_mps, e_sv, e_cl = ee(mps_s), ee(sv_s), ee(cl_s)
        m_mps, m_sv, m_cl = mz(mps_s), mz(sv_s), mz(cl_s)

        @test e_mps ≈ e_sv atol=1e-12
        @test e_mps ≈ e_cl atol=1e-12
        @test e_sv  ≈ e_cl atol=1e-12

        # FORMERLY A KNOWN BUG (documented in
        # .sisyphus/notepads/clifford-backend/issues.md, "RandomClifford
        # site-order mismatch: Clifford backend vs MPS/SV"), now FIXED.
        # RandomClifford's MPS/SV dense-matrix path applies a REVERSED
        # qubit-index-to-physical-site convention (src/Gates/two_qubit.jl:94-95,
        # src/StateVector/StateVector.jl:43). The Clifford backend's native
        # tableau path (src/Clifford/Clifford.jl, RandomClifford's
        # `_apply_single!`) now matches this by reversing `ram_sites` before
        # calling `QuantumClifford.apply!(tableau, op, reverse(ram_sites))`.
        @test m_mps ≈ m_sv atol=1e-12
        @test m_mps ≈ m_cl atol=1e-12
        @test m_sv  ≈ m_cl atol=1e-12

        # Also cross-check born_probability at the measured sites (should be
        # a deterministic 0/1 collapse identical across all three backends).
        for site in (1, 3)
            for outcome in 0:1
                p_mps = born_probability(mps_s, site, outcome)
                p_sv  = born_probability(sv_s,  site, outcome)
                p_cl  = born_probability(cl_s,  site, outcome)
                @test p_mps ≈ p_sv atol=1e-12
                @test p_mps ≈ p_cl atol=1e-12
                @test p_sv  ≈ p_cl atol=1e-12
            end
        end
    end

    # ═══════════════════════════════════════════════════════════════════════
    # 3. Full MIPT-style circuit: RandomClifford bricklayer (alternating
    #    even/odd) + stochastic Measure(:Z) via apply_with_prob!, run for
    #    several steps. Compare the FULL entropy TRAJECTORY (every step),
    #    not just the final value, across all three backends.
    # ═══════════════════════════════════════════════════════════════════════
    @testset "Circuit 3: MIPT-style trajectory — L=$L" for L in [4, 6]
        seeds = (gates_spacetime=17, gates_realization=23, born_measurement=5)
        mps_s, sv_s, cl_s = make_triple(L=L, seeds=seeds)

        n_steps = 6
        p_meas = 0.3

        function run_circuit3!(state, L, n_steps, p_meas)
            ee = EntanglementEntropy(cut=L ÷ 2)
            entropies = Float64[]
            for step in 1:n_steps
                parity = isodd(step) ? :odd : :even
                apply!(state, RandomClifford(2), Bricklayer(parity))
                apply_with_prob!(state; outcomes=[
                    (probability=p_meas, gate=Measure(:Z), geometry=AllSites())])
                push!(entropies, ee(state))
            end
            return entropies
        end

        traj_mps = run_circuit3!(mps_s, L, n_steps, p_meas)
        traj_sv  = run_circuit3!(sv_s,  L, n_steps, p_meas)
        traj_cl  = run_circuit3!(cl_s,  L, n_steps, p_meas)

        @test length(traj_mps) == n_steps
        @test length(traj_sv)  == n_steps
        @test length(traj_cl)  == n_steps

        for i in 1:n_steps
            @test traj_mps[i] ≈ traj_sv[i] atol=1e-12
            @test traj_mps[i] ≈ traj_cl[i] atol=1e-12
            @test traj_sv[i]  ≈ traj_cl[i] atol=1e-12
        end

        # Guard against a trivially-passing all-zero trajectory: RandomClifford
        # bricklayers should generate SOME entanglement at some point.
        @test maximum(traj_mps) > 0.01
        @test maximum(traj_sv)  > 0.01
        @test maximum(traj_cl)  > 0.01
    end

end  # top-level @testset
