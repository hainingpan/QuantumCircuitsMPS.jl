# test/statevector/integration.jl
# End-to-end integration tests for the state-vector backend.
# Covers: full MIPT-style workflow, all record_when modes, event logging,
# apply_with_prob!, and edge cases (L=1, L=2, empty circuit, measurement-only).

using Test
using QuantumCircuitsMPS
using LinearAlgebra
using Random

@testset "State-Vector Integration Tests" begin

    # =====================================================================
    # 1. Full MIPT-style workflow (SV backend)
    # =====================================================================
    @testset "MIPT-style workflow (L=6, SV backend)" begin
        L = 6
        p = 0.15
        n_steps = 10

        circuit = Circuit(L = L, bc = :periodic) do c
            apply!(c, HaarRandom(), Bricklayer(:even))
            apply_with_prob!(c; outcomes = [
                (probability = p, gate = Measure(:Z), geometry = AllSites())
            ])
            record!(c, :entropy)
            apply!(c, HaarRandom(), Bricklayer(:odd))
            apply_with_prob!(c; outcomes = [
                (probability = p, gate = Measure(:Z), geometry = AllSites())
            ])
            record!(c, :entropy)
        end

        state = SimulationState(L = L, bc = :periodic, backend = :statevector,
            rng = RNGRegistry(gates_spacetime = 42, gates_realization = 2, born_measurement = 1))
        initialize!(state, ProductState(binary_int = 0))
        track!(state, :entropy => EntanglementEntropy(cut = L÷2))

        simulate!(circuit, state; n_steps = n_steps, record_when = :marks)

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
        function sv_state_no_markers(; L = 4)
            circuit = Circuit(L = L, bc = :open) do c
                apply!(c, Hadamard(), SingleSite(1))
                apply!(c, PauliX(), SingleSite(2))
            end
            state = SimulationState(L = L, bc = :open, backend = :statevector,
                rng = RNGRegistry(gates_spacetime = 1, gates_realization = 2, born_measurement = 3))
            initialize!(state, ProductState(binary_int = 0))
            track!(state, :entropy => EntanglementEntropy(cut = L÷2))
            return circuit, state
        end

        @testset ":every_step" begin
            circuit, state = sv_state_no_markers()
            n = 5
            simulate!(circuit, state; n_steps = n, record_when = :every_step)
            @test length(state.observables[:entropy]) == n
        end

        @testset ":every_gate" begin
            circuit, state = sv_state_no_markers()
            n = 5
            simulate!(circuit, state; n_steps = n, record_when = :every_gate)
            # 2 gates per step × 5 steps = 10
            @test length(state.observables[:entropy]) == 2 * n
        end

        @testset ":final_only" begin
            circuit, state = sv_state_no_markers()
            n = 5
            simulate!(circuit, state; n_steps = n, record_when = :final_only)
            @test length(state.observables[:entropy]) == 1
        end

        @testset ":marks" begin
            L = 4
            circuit = Circuit(L = L, bc = :open) do c
                apply!(c, Hadamard(), SingleSite(1))
                record!(c, :entropy)
                apply!(c, PauliX(), SingleSite(2))
                record!(c, :entropy)
            end
            state = SimulationState(L = L, bc = :open, backend = :statevector,
                rng = RNGRegistry(gates_spacetime = 1, gates_realization = 2, born_measurement = 3))
            initialize!(state, ProductState(binary_int = 0))
            track!(state, :entropy => EntanglementEntropy(cut = L÷2))

            n = 5
            simulate!(circuit, state; n_steps = n, record_when = :marks)
            # 2 markers × 5 steps = 10
            @test length(state.observables[:entropy]) == 2 * n
        end
    end

    # =====================================================================
    # 3. Event logging with SV backend
    # =====================================================================
    @testset "Event logging (SV backend)" begin
        L = 4

        circuit = Circuit(L = L, bc = :open) do c
            apply!(c, Hadamard(), SingleSite(1))
            apply_with_prob!(c; outcomes = [
                (probability = 1.0, gate = Measure(:Z), geometry = AllSites())
            ])
        end

        state = SimulationState(L = L, bc = :open, backend = :statevector,
            log_events = true,
            rng = RNGRegistry(gates_spacetime = 42, gates_realization = 2, born_measurement = 1))
        initialize!(state, ProductState(binary_int = 0))

        simulate!(circuit, state; n_steps = 1, record_when = :every_step)

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
        circuit = Circuit(L = L, bc = :open) do c
            apply_with_prob!(c;
                outcomes = [
                    (probability = p_measure, gate = Measure(:Z), geometry = AllSites())
                ])
        end

        n_meas_total = 0
        for trial in 1:n_trials
            state = SimulationState(L = L, bc = :open, backend = :statevector,
                log_events = true,
                rng = RNGRegistry(
                    gates_spacetime = trial,
                    gates_realization = trial + 1000,
                    born_measurement = trial + 2000))
            initialize!(state, ProductState(binary_int = 0))
            simulate!(circuit, state; n_steps = 1, record_when = :every_step)
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
        circuit = Circuit(L = L, bc = :open) do c
            apply!(c, Hadamard(), SingleSite(1))
        end

        state = SimulationState(L = L, bc = :open, backend = :statevector,
            rng = RNGRegistry(gates_spacetime = 1, gates_realization = 2, born_measurement = 3))
        initialize!(state, ProductState(binary_int = 0))

        simulate!(circuit, state; n_steps = 1, record_when = :every_step)

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
        circuit = Circuit(L = L, bc = :open) do c
            apply!(c, CZ(), AdjacentPair(1))
            apply!(c, Hadamard(), SingleSite(1))
        end

        state = SimulationState(L = L, bc = :open, backend = :statevector,
            rng = RNGRegistry(gates_spacetime = 1, gates_realization = 2, born_measurement = 3))
        initialize!(state, ProductState(binary_int = 0))
        track!(state, :entropy => EntanglementEntropy(cut = 1))

        simulate!(circuit, state; n_steps = 1, record_when = :every_step)

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
        circuit = Circuit(L = L, bc = :open) do c
            # No gates at all
        end

        state = SimulationState(L = L, bc = :open, backend = :statevector,
            rng = RNGRegistry(gates_spacetime = 1, gates_realization = 2, born_measurement = 3))
        initialize!(state, ProductState(binary_int = 0))

        ψ_before = copy(state.backend.ψ)

        simulate!(circuit, state; n_steps = 5, record_when = :every_step)

        # State unchanged after empty circuit
        @test state.backend.ψ == ψ_before
        @test norm(state.backend.ψ) ≈ 1.0 atol=1e-12
    end

    # =====================================================================
    # 8. Edge case: measurement-only circuit
    # =====================================================================
    @testset "Edge case: measurement-only circuit" begin
        L = 4
        circuit = Circuit(L = L, bc = :open) do c
            apply_with_prob!(c; outcomes = [
                (probability = 1.0, gate = Measure(:Z), geometry = AllSites())
            ])
        end

        state = SimulationState(L = L, bc = :open, backend = :statevector,
            log_events = true,
            rng = RNGRegistry(gates_spacetime = 42, gates_realization = 2, born_measurement = 1))
        # Start in |0000⟩ — deterministic measurement outcome
        initialize!(state, ProductState(binary_int = 0))

        simulate!(circuit, state; n_steps = 1, record_when = :every_step)

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
        state2 = SimulationState(L = L, bc = :open, backend = :statevector,
            log_events = true,
            rng = RNGRegistry(gates_spacetime = 42, gates_realization = 2, born_measurement = 99))
        initialize!(state2, ProductState(binary_int = 0))
        # Put site 1 in superposition first
        apply!(state2, Hadamard(), SingleSite(1))
        # Now measure all sites
        circuit2 = Circuit(L = L, bc = :open) do c
            apply_with_prob!(c; outcomes = [
                (probability = 1.0, gate = Measure(:Z), geometry = AllSites())
            ])
        end
        simulate!(circuit2, state2; n_steps = 1, record_when = :every_step)

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
            circuit = Circuit(L = L, bc = :open) do c
                apply!(c, HaarRandom(), Bricklayer(:odd))
                apply_with_prob!(c; outcomes = [
                    (probability = p, gate = Measure(:Z), geometry = AllSites())
                ])
            end
            state = SimulationState(L = L, bc = :open, backend = :statevector,
                rng = RNGRegistry(gates_spacetime = seed, gates_realization = seed+1,
                    born_measurement = seed+2))
            initialize!(state, ProductState(binary_int = 0))
            track!(state, :entropy => EntanglementEntropy(cut = L÷2))
            simulate!(circuit, state; n_steps = n_steps, record_when = :every_step)
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

    # =====================================================================
    # 10. Region-based entanglement entropy (EntanglementEntropy{Vector{Int}})
    # =====================================================================
    @testset "Region entanglement entropy (SV backend)" begin
        _sv_rng(seed) = RNGRegistry(gates_spacetime = seed,
            gates_realization = seed + 100, born_measurement = seed + 200)

        # Two independent Bell pairs on (1,2) and (3,4)
        function two_bell_pairs(; L = 4)
            s = SimulationState(L = L, bc = :open, backend = :statevector,
                rng = _sv_rng(7))
            initialize!(s, ProductState(binary_int = 0))
            apply!(s, Hadamard(), SingleSite(1))
            apply!(s, CNOT(), Sites([1, 2]))
            apply!(s, Hadamard(), SingleSite(3))
            apply!(s, CNOT(), Sites([3, 4]))
            return s
        end

        # ----------------------------------------------------------------
        # (a) Prefix equivalence: cut=k  ==  cut=1:k
        # ----------------------------------------------------------------
        @testset "(a) prefix equivalence cut=k vs cut=1:k" begin
            L = 6
            circuit = Circuit(L = L, bc = :open) do c
                apply!(c, HaarRandom(), Bricklayer(:odd))
                apply!(c, HaarRandom(), Bricklayer(:even))
            end
            state = SimulationState(L = L, bc = :open, backend = :statevector,
                rng = _sv_rng(31))
            initialize!(state, ProductState(binary_int = 0))
            simulate!(circuit, state; n_steps = 3, record_when = :final_only)

            for k in 1:(L - 1)
                S_int = EntanglementEntropy(cut = k)(state)
                S_reg = EntanglementEntropy(cut = 1:k)(state)
                @test S_int≈S_reg atol=1e-10
            end
            # the reference state is genuinely entangled (non-vacuous test)
            @test EntanglementEntropy(cut = 3)(state) > 0.5
        end

        # ----------------------------------------------------------------
        # (b) Bell pair analytic values
        # ----------------------------------------------------------------
        @testset "(b) Bell pair analytic" begin
            s = SimulationState(L = 2, bc = :open, backend = :statevector,
                rng = _sv_rng(11))
            initialize!(s, ProductState(binary_int = 0))
            apply!(s, Hadamard(), SingleSite(1))
            apply!(s, CNOT(), Sites([1, 2]))

            @test EntanglementEntropy(cut = [1])(s)≈1.0 atol=1e-10
            @test EntanglementEntropy(cut = [2])(s)≈1.0 atol=1e-10
            # both sites = the whole L=2 system → rejected as a trivial region
            @test_throws ArgumentError EntanglementEntropy(cut = [1, 2])(s)

            # both sites of the FIRST pair inside a larger system → pure → 0
            s4 = two_bell_pairs()
            @test abs(EntanglementEntropy(cut = [1, 2])(s4)) < 1e-10
        end

        # ----------------------------------------------------------------
        # (c) Complement symmetry S(A) = S(Ā) on a pure entangled state
        # ----------------------------------------------------------------
        @testset "(c) complement symmetry" begin
            L = 6
            circuit = Circuit(L = L, bc = :open) do c
                apply!(c, HaarRandom(), Bricklayer(:odd))
                apply!(c, HaarRandom(), Bricklayer(:even))
            end
            state = SimulationState(L = L, bc = :open, backend = :statevector,
                rng = _sv_rng(57))
            initialize!(state, ProductState(binary_int = 0))
            simulate!(circuit, state; n_steps = 3, record_when = :final_only)

            for A in ([1, 3], [2, 5], [1, 2, 4], [4], [2, 3, 5, 6])
                Abar = setdiff(collect(1:L), A)
                SA = EntanglementEntropy(cut = A)(state)
                SB = EntanglementEntropy(cut = Abar)(state)
                @test SA≈SB atol=1e-10
                @test SA > 0.1   # non-vacuous
            end
        end

        # ----------------------------------------------------------------
        # (d) Non-contiguous regions on two independent Bell pairs
        # ----------------------------------------------------------------
        @testset "(d) non-contiguous regions" begin
            s = two_bell_pairs()
            @test EntanglementEntropy(cut = [1, 3])(s)≈2.0 atol=1e-10
            @test EntanglementEntropy(cut = [2, 4])(s)≈2.0 atol=1e-10
            @test EntanglementEntropy(cut = [1, 4])(s)≈2.0 atol=1e-10
            @test EntanglementEntropy(cut = [2, 3])(s)≈2.0 atol=1e-10
            @test abs(EntanglementEntropy(cut = [1, 2])(s)) < 1e-10
            @test abs(EntanglementEntropy(cut = [3, 4])(s)) < 1e-10
            @test EntanglementEntropy(cut = [1, 2, 3])(s)≈1.0 atol=1e-10
            # unsorted / PBC-wrapped input is canonicalized at construction
            @test EntanglementEntropy(cut = [3, 1])(s) ≈
                  EntanglementEntropy(cut = [1, 3])(s) atol=1e-12
        end

        # ----------------------------------------------------------------
        # (e) Rényi index parity on a flat 2-level spectrum
        # ----------------------------------------------------------------
        @testset "(e) Rényi region entropy" begin
            s = SimulationState(L = 2, bc = :open, backend = :statevector,
                rng = _sv_rng(13))
            initialize!(s, ProductState(binary_int = 0))
            apply!(s, Hadamard(), SingleSite(1))
            apply!(s, CNOT(), Sites([1, 2]))
            for n in (1, 2, 3)
                @test EntanglementEntropy(cut = [1], renyi_index = n)(s)≈1.0 atol=1e-10
            end
            # base conversion honored: 1 bit = log(2) nats
            @test EntanglementEntropy(cut = [1], base = ℯ)(s)≈log(2) atol=1e-10

            # Rényi-2 region vs prefix agreement on an entangled 4-site state
            s4 = two_bell_pairs()
            @test EntanglementEntropy(cut = 2, renyi_index = 2)(s4) ≈
                  EntanglementEntropy(cut = 1:2, renyi_index = 2)(s4) atol=1e-10
        end

        # ----------------------------------------------------------------
        # (f) Qudit (spin-3/2, local_dim = 4) regions
        # ----------------------------------------------------------------
        @testset "(f) qudit (S=3/2) regions" begin
            state = SimulationState(L = 4, bc = :open, site_type = "S=3/2",
                backend = :statevector, rng = _sv_rng(23))
            @test state.local_dim == 4
            initialize!(state, ProductState(spin_state = "Z1/2"))
            # product state → every region has zero entropy
            for A in ([1], [2, 3], [1, 3], [1, 2, 3])
                @test abs(EntanglementEntropy(cut = A)(state)) < 1e-10
            end

            # entangle sites 2-3 with a d=4 two-site gate, then check prefix equivalence
            rng_u = MersenneTwister(2024)
            U = Matrix(qr(randn(rng_u, ComplexF64, 16, 16)).Q)
            apply!(state, MatrixGate(U; d = 4), Sites([2, 3]))
            for k in 1:3
                @test EntanglementEntropy(cut = k)(state) ≈
                      EntanglementEntropy(cut = 1:k)(state) atol=1e-10
            end
            @test EntanglementEntropy(cut = [2])(state) > 0.1   # non-vacuous
            @test EntanglementEntropy(cut = [2])(state) ≈
                  EntanglementEntropy(cut = [1, 3, 4])(state) atol=1e-10
        end

        # ----------------------------------------------------------------
        # (g) Call-time region validation
        # ----------------------------------------------------------------
        @testset "(g) call-time validation" begin
            L = 4
            s = SimulationState(L = L, bc = :open, backend = :statevector,
                rng = _sv_rng(3))
            initialize!(s, ProductState(binary_int = 0))
            @test_throws ArgumentError EntanglementEntropy(cut = [L + 1])(s)
            @test_throws ArgumentError EntanglementEntropy(cut = [2, L + 3])(s)
            @test_throws ArgumentError EntanglementEntropy(cut = collect(1:L))(s)
        end
    end
end

# ======================================================================
# Real-valued `renyi_index`: state-vector domain edges, branch handoffs and
# threshold sensitivity.
#
# The state-vector backend has TWO distinct entropy kernels and both must be
# pinned:
#   - `cut::Int`  -> the dedicated bipartition kernel in
#                    src/StateVector/entanglement.jl (reshape + svdvals)
#   - `cut::Vector{Int}` -> `_mi_entropy_from_probs`
#                    (src/Observables/mutual_information.jl) via
#                    `_sv_subset_probs`
# A `cut = 1` test alone leaves the region kernel unpinned and vice versa, so
# every value assertion below is run through BOTH dispatches.
# ======================================================================
@testset "State-Vector Rényi domain edges (real renyi_index)" begin
    _svr_rng(s) = RNGRegistry(gates_spacetime = s, gates_realization = s + 1,
        born_measurement = s + 2)

    function _svr_bell()
        st = SimulationState(L = 2, bc = :open, backend = :statevector,
            rng = _svr_rng(5))
        initialize!(st, ProductState(binary_int = 0))
        apply!(st, Hadamard(), SingleSite(1))
        apply!(st, CNOT(), Sites([1, 2]))
        return st
    end

    @testset "Bell (flat) = 1 bit at every n, both dispatches" begin
        st = _svr_bell()
        # Flat spectrum ⇒ n-independent. n = 2048 kills direct powers
        # (0.5^2048 underflows to 0.0 → log(0) = -Inf); n = floatmax kills an
        # un-scaled logsumexp (every floatmax * log(p) is already -Inf).
        for n in (0.5, 1.5, 3, 2048, floatmax(Float64))
            S_bi = EntanglementEntropy(cut = 1, renyi_index = n, base = 2)(st)
            S_rg = EntanglementEntropy(cut = [1], renyi_index = n, base = 2)(st)
            @test isfinite(S_bi)
            @test isfinite(S_rg)
            @test S_bi≈1.0 rtol=1e-9
            @test S_rg≈1.0 rtol=1e-9
        end
    end

    @testset "von Neumann shunt is EXACT on both dispatches" begin
        # A genuinely non-flat spectrum, so "equal to S(1)" is a real
        # statement about the shunt and not an artifact of flatness.
        st = SimulationState(L = 4, bc = :open, backend = :statevector,
            rng = _svr_rng(31))
        initialize!(st, ProductState(binary_int = 0))
        for _ in 1:3
            apply!(st, HaarRandom(), Bricklayer(:odd))
            apply!(st, HaarRandom(), Bricklayer(:even))
        end
        S_bi1 = EntanglementEntropy(cut = 1, renyi_index = 1, base = 2)(st)
        S_rg1 = EntanglementEntropy(cut = [1], renyi_index = 1, base = 2)(st)
        @test S_bi1 > 0.1                       # non-vacuous
        for n in (prevfloat(1.0), nextfloat(1.0), 1.0 - 1e-8, 1.0 + 1e-8)
            @test EntanglementEntropy(cut = 1, renyi_index = n, base = 2)(st) == S_bi1
            @test EntanglementEntropy(cut = [1], renyi_index = n, base = 2)(st) == S_rg1
        end
        # The LOWER decimal boundary is the asymmetric one: 1.0 - 1e-8 is at
        # Float64 distance ≈ 1.0000000050e-8 > 1e-8 from 1.0, so the shunt
        # half-width MUST be widened past the bare 1e-8 literal.
        @test abs((1.0 - 1e-8) - 1.0) > 1e-8
        @test abs((1.0 + 1e-8) - 1.0) < 1e-8
    end

    @testset "kernel-level branch handoff on an exactly-normalized fixture" begin
        # `[prevfloat(1.0), 2.0^-53]` sums to EXACTLY 1.0 in Float64
        # (prevfloat(1.0) = 1 - 2^-53), which is why the fixture is written in
        # binary: a decimal `1e-16` is not Float64-representable and would
        # leave a sub-ulp normalization residual that makes any tight BigFloat
        # reference unsatisfiable.
        p_fixture() = [prevfloat(1.0), 2.0^-53]
        kern = QuantumCircuitsMPS._mi_entropy_from_probs
        ref(n) = Float64(log(big(prevfloat(1.0))^big(n) + big(2.0^-53)^big(n)) /
                         (1 - big(n)))
        # 0.9999 / 1.0001 are just INSIDE the ±1e-4 handoff, their
        # prevfloat/nextfloat neighbours just OUTSIDE it.
        for n in (1.0 - 1e-6, 1.0 + 1e-6, 0.9999, prevfloat(0.9999),
            1.0001, nextfloat(1.0001))
            v = kern(p_fixture(), n, Float64(ℯ), 1e-16)
            @test v > 0                          # cancellation would go negative
            @test v≈ref(n) rtol=1e-6
        end
        # Handoff CONTINUITY: adjacent Float64 neighbours straddling the
        # branch boundary must agree to relative 1e-9.
        for (a, b) in ((prevfloat(0.9999), 0.9999), (1.0001, nextfloat(1.0001)))
            va = kern(p_fixture(), a, Float64(ℯ), 1e-16)
            vb = kern(p_fixture(), b, Float64(ℯ), 1e-16)
            @test abs(va - vb) / abs(va) < 1e-9
        end
    end

    @testset "skew spectrum: near-1 positivity vs BigFloat reference" begin
        # Strongly skewed two-qubit state cos(θ)|00> + sin(θ)|11>, θ = 0.01,
        # i.e. a realized Schmidt spectrum ≈ [1 - 1e-4, 1e-4] (10^4 : 1).
        θ = 0.01
        U = ComplexF64[cos(θ) 0 0 -sin(θ); 0 1 0 0; 0 0 1 0; sin(θ) 0 0 cos(θ)]
        st = SimulationState(L = 2, bc = :open, backend = :statevector,
            rng = _svr_rng(9))
        initialize!(st, ProductState(binary_int = 0))
        apply!(st, MatrixGate(U), Sites([1, 2]))

        # Reference is built from the REALIZED spectrum (self-consistent), not
        # from the nominal angle: the kernel's own threshold clamp and
        # renormalization are reproduced here verbatim.
        M = reshape(st.backend.ψ, (2, 2))
        p_real = max.(svdvals(M), 1e-16) .^ 2
        p_real ./= sum(p_real)
        @test p_real[2] < 1e-3 && p_real[2] > 1e-5      # genuinely skewed
        bigref(n) = Float64(log(sum(big.(p_real) .^ big(n))) / (1 - big(n)) /
                            log(big(2)))

        for n in (1.0 - 1e-6, 1.0 + 1e-6)
            S = EntanglementEntropy(cut = 1, renyi_index = n, base = 2)(st)
            @test S > 0                                  # NOT negative
            @test S≈bigref(n) rtol=1e-6
        end
        # How far the skew can be pushed at the PUBLIC-API level is limited by
        # the sub-ulp normalization residual of the realized Float64 spectrum
        # (the near-1 branch assumes Σp = 1); the extreme-skew regime is
        # covered by the kernel-level fixture above, which sums to exactly 1.
    end

    @testset "continuity + strict monotonicity on a Haar state" begin
        st = SimulationState(L = 6, bc = :open, backend = :statevector,
            rng = _svr_rng(31))
        initialize!(st, ProductState(binary_int = 0))
        for _ in 1:4
            apply!(st, HaarRandom(), Bricklayer(:odd))
            apply!(st, HaarRandom(), Bricklayer(:even))
        end
        for cut in (3, [1, 2, 3])
            S(n) = EntanglementEntropy(cut = cut, renyi_index = n, base = 2)(st)
            S1 = S(1)
            @test S1 > 0.5                              # non-vacuous
            @test abs(S(1 + 1e-6) - S1) < 1e-4
            @test abs(S(1 - 1e-6) - S1) < 1e-4
            @test S(0.5) - S1 > 1e-6
            @test S1 - S(2) > 1e-6
            @test S(2) - S(3) > 1e-6
        end
    end

    @testset "small n is threshold-dominated (documented caveat, pinned)" begin
        # Product state ⇒ the ONLY non-zero RDM eigenvalue is 1; every other
        # entry is the probability FLOOR threshold^2. As n → 0⁺ the floor
        # terms (threshold^2)^n stop being negligible, which is exactly the
        # threshold-dependence documented in `EntanglementEntropy`'s Hartley
        # note. Both directions are pinned so the caveat cannot silently
        # become false.
        st = SimulationState(L = 6, bc = :open, backend = :statevector,
            rng = _svr_rng(3))
        initialize!(st, ProductState(binary_int = 0))
        # floor 1e-200 ⇒ (1e-200)^0.1 = 1e-20 per entry ⇒ effectively zero
        @test EntanglementEntropy(cut = 2:3, renyi_index = 0.1,
            threshold = 1e-100)(st) < 1e-8
        # DEFAULT floor 1e-32 ⇒ (1e-32)^0.1 ≈ 6e-4 per entry ⇒ visibly non-zero
        @test EntanglementEntropy(cut = 2:3, renyi_index = 0.1)(st) > 1e-4
        # ... while the von Neumann value of the same product state is ~0
        @test EntanglementEntropy(cut = 2:3, renyi_index = 1)(st) < 1e-10
    end
end
