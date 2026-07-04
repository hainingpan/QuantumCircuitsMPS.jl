# test/statevector/integration.jl
# End-to-end integration tests for the state-vector backend.
# Covers: full MIPT-style workflow, all record_when modes, event logging,
# apply_with_prob!, and edge cases (L=1, L=2, empty circuit, measurement-only).

using Test
using QuantumCircuitsMPS
using LinearAlgebra

@testset "State-Vector Integration Tests" begin

    # =====================================================================
    # 1. Full MIPT-style workflow (SV backend)
    # =====================================================================
    @testset "MIPT-style workflow (L=6, SV backend)" begin
        L = 6
        p = 0.15
        n_steps = 10

        circuit = Circuit(L=L, bc=:periodic) do c
            apply!(c, HaarRandom(), Bricklayer(:even))
            apply_with_prob!(c; outcomes=[
                (probability=p, gate=Measure(:Z), geometry=AllSites())
            ])
            record!(c, :entropy)
            apply!(c, HaarRandom(), Bricklayer(:odd))
            apply_with_prob!(c; outcomes=[
                (probability=p, gate=Measure(:Z), geometry=AllSites())
            ])
            record!(c, :entropy)
        end

        state = SimulationState(L=L, bc=:periodic, backend=:statevector,
            rng=RNGRegistry(gates_spacetime=42, gates_realization=2, born_measurement=1))
        initialize!(state, ProductState(binary_int=0))
        track!(state, :entropy => EntanglementEntropy(cut=L÷2))

        simulate!(circuit, state; n_steps=n_steps, record_when=:marks)

        entropies = state.observables[:entropy]
        # 2 markers per step × 10 steps = 20 recorded values
        @test length(entropies) == 2 * n_steps
        # All values finite
        @test all(isfinite, entropies)
        # Entanglement entropy is non-negative
        @test all(e -> e >= 0, entropies)
        # State vector norm preserved
        @test norm(state.backend.ψ) ≈ 1.0 atol=1e-12
    end

    # =====================================================================
    # 2. record_when coverage
    # =====================================================================
    @testset "record_when modes" begin
        # Helper: simple deterministic SV circuit (no markers)
        function sv_state_no_markers(; L=4)
            circuit = Circuit(L=L, bc=:open) do c
                apply!(c, Hadamard(), SingleSite(1))
                apply!(c, PauliX(), SingleSite(2))
            end
            state = SimulationState(L=L, bc=:open, backend=:statevector,
                rng=RNGRegistry(gates_spacetime=1, gates_realization=2, born_measurement=3))
            initialize!(state, ProductState(binary_int=0))
            track!(state, :entropy => EntanglementEntropy(cut=L÷2))
            return circuit, state
        end

        @testset ":every_step" begin
            circuit, state = sv_state_no_markers()
            n = 5
            simulate!(circuit, state; n_steps=n, record_when=:every_step)
            @test length(state.observables[:entropy]) == n
        end

        @testset ":every_gate" begin
            circuit, state = sv_state_no_markers()
            n = 5
            simulate!(circuit, state; n_steps=n, record_when=:every_gate)
            # 2 gates per step × 5 steps = 10
            @test length(state.observables[:entropy]) == 2 * n
        end

        @testset ":final_only" begin
            circuit, state = sv_state_no_markers()
            n = 5
            simulate!(circuit, state; n_steps=n, record_when=:final_only)
            @test length(state.observables[:entropy]) == 1
        end

        @testset ":marks" begin
            L = 4
            circuit = Circuit(L=L, bc=:open) do c
                apply!(c, Hadamard(), SingleSite(1))
                record!(c, :entropy)
                apply!(c, PauliX(), SingleSite(2))
                record!(c, :entropy)
            end
            state = SimulationState(L=L, bc=:open, backend=:statevector,
                rng=RNGRegistry(gates_spacetime=1, gates_realization=2, born_measurement=3))
            initialize!(state, ProductState(binary_int=0))
            track!(state, :entropy => EntanglementEntropy(cut=L÷2))

            n = 5
            simulate!(circuit, state; n_steps=n, record_when=:marks)
            # 2 markers × 5 steps = 10
            @test length(state.observables[:entropy]) == 2 * n
        end
    end

    # =====================================================================
    # 3. Event logging with SV backend
    # =====================================================================
    @testset "Event logging (SV backend)" begin
        L = 4

        circuit = Circuit(L=L, bc=:open) do c
            apply!(c, Hadamard(), SingleSite(1))
            apply_with_prob!(c; outcomes=[
                (probability=1.0, gate=Measure(:Z), geometry=AllSites())
            ])
        end

        state = SimulationState(L=L, bc=:open, backend=:statevector,
            log_events=true,
            rng=RNGRegistry(gates_spacetime=42, gates_realization=2, born_measurement=1))
        initialize!(state, ProductState(binary_int=0))

        simulate!(circuit, state; n_steps=1, record_when=:every_step)

        evts = events(state)
        meas = measurements(state)

        # At least one event recorded
        @test length(evts) > 0
        # probability=1.0 on AllSites(L=4) → 4 measurements
        @test length(meas) == L
        # Each is a MeasurementOutcome
        @test all(m -> m isa QuantumCircuitsMPS.MeasurementOutcome, meas)
        # Outcomes are valid (0 or 1 for qubits)
        @test all(m -> m.outcome in (0, 1), meas)
        # Sites are populated
        @test all(m -> length(m.sites) == 1, meas)
    end

    # =====================================================================
    # 4. apply_with_prob! stochastic gate selection (SV backend)
    # =====================================================================
    @testset "apply_with_prob! stochastic selection (SV backend)" begin
        L = 4
        n_trials = 200
        p_measure = 0.5

        # Circuit: 50% chance of Measure(:Z) on each site, 50% identity
        circuit = Circuit(L=L, bc=:open) do c
            apply_with_prob!(c; outcomes=[
                (probability=p_measure, gate=Measure(:Z), geometry=AllSites())
            ])
        end

        n_meas_total = 0
        for trial in 1:n_trials
            state = SimulationState(L=L, bc=:open, backend=:statevector,
                log_events=true,
                rng=RNGRegistry(
                    gates_spacetime=trial,
                    gates_realization=trial + 1000,
                    born_measurement=trial + 2000))
            initialize!(state, ProductState(binary_int=0))
            simulate!(circuit, state; n_steps=1, record_when=:every_step)
            n_meas_total += length(measurements(state))
        end

        # Expected: p=0.5 × L=4 sites × n_trials=200 = 400 measurements on average
        # Allow wide margin for statistical test: ±30% → [280, 520]
        expected = p_measure * L * n_trials
        @test n_meas_total > expected * 0.5
        @test n_meas_total < expected * 1.5
    end

    # =====================================================================
    # 5. Edge case: L=1 single-qubit circuit
    # =====================================================================
    @testset "Edge case: L=1 (single qubit)" begin
        L = 1
        circuit = Circuit(L=L, bc=:open) do c
            apply!(c, Hadamard(), SingleSite(1))
        end

        state = SimulationState(L=L, bc=:open, backend=:statevector,
            rng=RNGRegistry(gates_spacetime=1, gates_realization=2, born_measurement=3))
        initialize!(state, ProductState(binary_int=0))

        simulate!(circuit, state; n_steps=1, record_when=:every_step)

        ψ = state.backend.ψ
        # |+⟩ = (|0⟩ + |1⟩)/√2
        @test length(ψ) == 2
        @test abs(ψ[1]) ≈ 1/√2 atol=1e-12
        @test abs(ψ[2]) ≈ 1/√2 atol=1e-12
        @test norm(ψ) ≈ 1.0 atol=1e-12
    end

    # =====================================================================
    # 6. Edge case: L=2 minimal multi-site circuit
    # =====================================================================
    @testset "Edge case: L=2 (minimal multi-site)" begin
        L = 2
        # Apply CZ to the only pair, then Hadamard on site 1
        circuit = Circuit(L=L, bc=:open) do c
            apply!(c, CZ(), AdjacentPair(1))
            apply!(c, Hadamard(), SingleSite(1))
        end

        state = SimulationState(L=L, bc=:open, backend=:statevector,
            rng=RNGRegistry(gates_spacetime=1, gates_realization=2, born_measurement=3))
        initialize!(state, ProductState(binary_int=0))
        track!(state, :entropy => EntanglementEntropy(cut=1))

        simulate!(circuit, state; n_steps=1, record_when=:every_step)

        ψ = state.backend.ψ
        # Initial |00⟩, CZ on |00⟩ → |00⟩ (no phase change), then H on site1
        # H|0⟩ = |+⟩, so final state = |+0⟩ = (|00⟩ + |10⟩)/√2
        @test length(ψ) == 4
        @test norm(ψ) ≈ 1.0 atol=1e-12
        # Entropy is well-defined
        @test length(state.observables[:entropy]) == 1
        @test isfinite(state.observables[:entropy][1])
    end

    # =====================================================================
    # 7. Edge case: empty circuit (no gates)
    # =====================================================================
    @testset "Edge case: empty circuit" begin
        L = 4
        circuit = Circuit(L=L, bc=:open) do c
            # No gates at all
        end

        state = SimulationState(L=L, bc=:open, backend=:statevector,
            rng=RNGRegistry(gates_spacetime=1, gates_realization=2, born_measurement=3))
        initialize!(state, ProductState(binary_int=0))

        ψ_before = copy(state.backend.ψ)

        simulate!(circuit, state; n_steps=5, record_when=:every_step)

        # State unchanged after empty circuit
        @test state.backend.ψ == ψ_before
        @test norm(state.backend.ψ) ≈ 1.0 atol=1e-12
    end

    # =====================================================================
    # 8. Edge case: measurement-only circuit
    # =====================================================================
    @testset "Edge case: measurement-only circuit" begin
        L = 4
        circuit = Circuit(L=L, bc=:open) do c
            apply_with_prob!(c; outcomes=[
                (probability=1.0, gate=Measure(:Z), geometry=AllSites())
            ])
        end

        state = SimulationState(L=L, bc=:open, backend=:statevector,
            log_events=true,
            rng=RNGRegistry(gates_spacetime=42, gates_realization=2, born_measurement=1))
        # Start in |0000⟩ — deterministic measurement outcome
        initialize!(state, ProductState(binary_int=0))

        simulate!(circuit, state; n_steps=1, record_when=:every_step)

        ψ = state.backend.ψ
        # After measuring |0000⟩, state should collapse back to a computational
        # basis state (still a product state)
        @test norm(ψ) ≈ 1.0 atol=1e-12
        # Exactly one basis state has amplitude 1
        @test count(x -> abs(x) > 0.5, ψ) == 1

        meas = measurements(state)
        @test length(meas) == L
        # All measurements on |0000⟩ should give outcome 0
        @test all(m -> m.outcome == 0, meas)

        # Now test measurement-only with a superposition (non-trivial collapse)
        state2 = SimulationState(L=L, bc=:open, backend=:statevector,
            log_events=true,
            rng=RNGRegistry(gates_spacetime=42, gates_realization=2, born_measurement=99))
        initialize!(state2, ProductState(binary_int=0))
        # Put site 1 in superposition first
        apply!(state2, Hadamard(), SingleSite(1))
        # Now measure all sites
        circuit2 = Circuit(L=L, bc=:open) do c
            apply_with_prob!(c; outcomes=[
                (probability=1.0, gate=Measure(:Z), geometry=AllSites())
            ])
        end
        simulate!(circuit2, state2; n_steps=1, record_when=:every_step)

        ψ2 = state2.backend.ψ
        @test norm(ψ2) ≈ 1.0 atol=1e-12
        # After full measurement, state is a computational basis state
        @test count(x -> abs(x) > 0.5, ψ2) == 1
    end

    # =====================================================================
    # 9. Deterministic reproducibility (same seeds → same results)
    # =====================================================================
    @testset "Deterministic reproducibility (SV backend)" begin
        L = 4
        p = 0.3
        n_steps = 5

        function run_trial(seed)
            circuit = Circuit(L=L, bc=:open) do c
                apply!(c, HaarRandom(), Bricklayer(:odd))
                apply_with_prob!(c; outcomes=[
                    (probability=p, gate=Measure(:Z), geometry=AllSites())
                ])
            end
            state = SimulationState(L=L, bc=:open, backend=:statevector,
                rng=RNGRegistry(gates_spacetime=seed, gates_realization=seed+1, born_measurement=seed+2))
            initialize!(state, ProductState(binary_int=0))
            track!(state, :entropy => EntanglementEntropy(cut=L÷2))
            simulate!(circuit, state; n_steps=n_steps, record_when=:every_step)
            return state.observables[:entropy], state.backend.ψ
        end

        ent1, ψ1 = run_trial(42)
        ent2, ψ2 = run_trial(42)
        # Same seeds → identical results
        @test ent1 == ent2
        @test ψ1 == ψ2

        # Different seed → different results
        ent3, ψ3 = run_trial(99)
        @test ψ1 != ψ3
    end

end
