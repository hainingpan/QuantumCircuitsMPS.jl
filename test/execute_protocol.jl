# === execute! Protocol + Trait System Tests (Task 8, v0.1) ===
#
# Tests the uniform gate-execution protocol:
#   execute!(state, gate, region::Vector{Int})
# and the method-based traits:
#   needs_normalization(gate)::Bool  (default false)
#   is_measurement(gate)::Bool       (default false)
#
# Pure mechanism refactor: Measurement/Reset/SpinSectorMeasurement behavior
# must be preserved EXACTLY (goldens guard physics; these tests guard the API).

using Test
using QuantumCircuitsMPS
using ITensors
using ITensorMPS
using LinearAlgebra: norm

# --- User-defined gates for trait extensibility tests (no src/ edits!) ---

# Projective gate onto |0><0| that opts into normalization via the trait.
struct MyProjExecuteTest <: QuantumCircuitsMPS.AbstractGate end
QuantumCircuitsMPS.support(::MyProjExecuteTest) = 1
function QuantumCircuitsMPS.build_operator(::MyProjExecuteTest, site::Index, local_dim::Int; kwargs...)
    return op("Proj0", site)
end
QuantumCircuitsMPS.needs_normalization(::MyProjExecuteTest) = true

# Gate with a custom execute! override (protocol extensibility).
struct MyFlipExecuteTest <: QuantumCircuitsMPS.AbstractGate end
QuantumCircuitsMPS.support(::MyFlipExecuteTest) = 1
function QuantumCircuitsMPS.execute!(state::SimulationState, ::MyFlipExecuteTest, region::Vector{Int})
    # Delegate to the default path with a stock PauliX (proves overrides compose)
    QuantumCircuitsMPS.execute!(state, PauliX(), region)
    return nothing
end

function _fresh_state(; L=4, bc=:periodic, site_type="Qubit", maxdim=64,
                        seeds=(gates_spacetime=42, gates_realization=2, born_measurement=3))
    state = SimulationState(L=L, bc=bc, site_type=site_type, maxdim=maxdim,
        rng=RNGRegistry(gates_spacetime=seeds.gates_spacetime,
                        gates_realization=seeds.gates_realization,
                        born_measurement=seeds.born_measurement))
    if site_type == "S=1"
        initialize!(state, ProductState(spin_state="Z0"))
    else
        initialize!(state, ProductState(binary_int=0))
    end
    return state
end

@testset "execute! protocol + traits" begin

    @testset "trait defaults and opt-ins" begin
        # needs_normalization: default false for unitaries & measurement-like gates
        @test QuantumCircuitsMPS.needs_normalization(PauliX()) == false
        @test QuantumCircuitsMPS.needs_normalization(PauliY()) == false
        @test QuantumCircuitsMPS.needs_normalization(PauliZ()) == false
        @test QuantumCircuitsMPS.needs_normalization(HaarRandom()) == false
        @test QuantumCircuitsMPS.needs_normalization(CZ()) == false
        @test QuantumCircuitsMPS.needs_normalization(Hadamard()) == false
        @test QuantumCircuitsMPS.needs_normalization(Rx(0.3)) == false
        @test QuantumCircuitsMPS.needs_normalization(Measurement(:Z)) == false
        @test QuantumCircuitsMPS.needs_normalization(Reset()) == false
        # true for projective gates
        @test QuantumCircuitsMPS.needs_normalization(Projection(0)) == true
        @test QuantumCircuitsMPS.needs_normalization(Projection(1)) == true
        P01 = total_spin_projector(0) + total_spin_projector(1)
        @test QuantumCircuitsMPS.needs_normalization(SpinSectorProjection(P01)) == true
        @test QuantumCircuitsMPS.needs_normalization(SpinSectorMeasurement([0, 1])) == true

        # is_measurement: default false; true for Born-sampling measurement gates
        @test QuantumCircuitsMPS.is_measurement(PauliX()) == false
        @test QuantumCircuitsMPS.is_measurement(HaarRandom()) == false
        @test QuantumCircuitsMPS.is_measurement(Projection(0)) == false
        @test QuantumCircuitsMPS.is_measurement(Reset()) == false
        @test QuantumCircuitsMPS.is_measurement(SpinSectorProjection(P01)) == false
        @test QuantumCircuitsMPS.is_measurement(Measurement(:Z)) == true
        @test QuantumCircuitsMPS.is_measurement(SpinSectorMeasurement([0, 1])) == true
    end

    @testset "default execute! = build_operator -> apply_op_internal! path" begin
        state = _fresh_state()
        QuantumCircuitsMPS.execute!(state, PauliX(), [2])
        @test born_probability(state, 2, 1) ≈ 1.0 atol = 1e-12
        @test born_probability(state, 1, 0) ≈ 1.0 atol = 1e-12

        # two-site gate through the default path
        state2 = _fresh_state()
        QuantumCircuitsMPS.execute!(state2, CZ(), [1, 2])
        @test born_probability(state2, 1, 0) ≈ 1.0 atol = 1e-12
    end

    @testset "execute! validates support vs region size" begin
        state = _fresh_state()
        @test_throws ArgumentError QuantumCircuitsMPS.execute!(state, PauliX(), [1, 2])
        @test_throws ArgumentError QuantumCircuitsMPS.execute!(state, Measurement(:Z), [1, 2])
        @test_throws ArgumentError QuantumCircuitsMPS.execute!(state, Reset(), [1, 2])
    end

    @testset "Measurement via execute! (Born collapse, normalized)" begin
        state = _fresh_state()
        QuantumCircuitsMPS.execute!(state, PauliX(), [3])  # |0010>
        @test QuantumCircuitsMPS.execute!(state, Measurement(:Z), [3]) === nothing
        @test born_probability(state, 3, 1) ≈ 1.0 atol = 1e-12  # deterministic outcome
        @test norm(state.mps) ≈ 1.0 atol = 1e-10
    end

    @testset "Reset via execute! (measure + conditional X)" begin
        state = _fresh_state()
        QuantumCircuitsMPS.execute!(state, PauliX(), [2])  # prepare |1> at site 2
        @test born_probability(state, 2, 1) ≈ 1.0 atol = 1e-12
        @test QuantumCircuitsMPS.execute!(state, Reset(), [2]) === nothing
        @test born_probability(state, 2, 0) ≈ 1.0 atol = 1e-12
        @test norm(state.mps) ≈ 1.0 atol = 1e-10
    end

    @testset "apply! geometry dispatch routes through execute!" begin
        # SingleSite
        state = _fresh_state()
        apply!(state, PauliX(), SingleSite(2))
        apply!(state, Reset(), SingleSite(2))
        @test born_probability(state, 2, 0) ≈ 1.0 atol = 1e-12

        # AllSites: Measurement measures every site independently
        state2 = _fresh_state()
        apply!(state2, PauliX(), SingleSite(1))
        apply!(state2, Measurement(:Z), AllSites())
        @test born_probability(state2, 1, 1) ≈ 1.0 atol = 1e-12
        @test born_probability(state2, 2, 0) ≈ 1.0 atol = 1e-12

        # AllSites: Reset resets every site
        state3 = _fresh_state()
        apply!(state3, PauliX(), SingleSite(1))
        apply!(state3, PauliX(), SingleSite(4))
        apply!(state3, Reset(), AllSites())
        for i in 1:4
            @test born_probability(state3, i, 0) ≈ 1.0 atol = 1e-12
        end

        # Direct sites vector (uniform engine path)
        state4 = _fresh_state()
        apply!(state4, PauliX(), [2])
        apply!(state4, Reset(), [2])
        @test born_probability(state4, 2, 0) ≈ 1.0 atol = 1e-12
    end

    @testset "staircase/Pointer with 1-site gates: position semantics + advance" begin
        # Reset on a staircase applies at the CURRENT position, then advances
        state = _fresh_state(L=4)
        for i in 1:4
            apply!(state, PauliX(), SingleSite(i))  # |1111>
        end
        sc = StaircaseRight(2)
        apply!(state, Reset(), sc)
        @test born_probability(state, 2, 0) ≈ 1.0 atol = 1e-12  # reset at pos 2
        @test born_probability(state, 1, 1) ≈ 1.0 atol = 1e-12  # untouched
        @test current_position(sc) == 3                          # advanced

        # Measurement on a staircase: same position semantics
        state2 = _fresh_state(L=4)
        apply!(state2, PauliX(), SingleSite(3))
        sc2 = StaircaseLeft(3)
        apply!(state2, Measurement(:Z), sc2)
        @test born_probability(state2, 3, 1) ≈ 1.0 atol = 1e-12
        @test current_position(sc2) == 2

        # Pointer: 1-site gate at position, NO auto-advance
        state3 = _fresh_state(L=4)
        apply!(state3, PauliX(), SingleSite(2))
        ptr = Pointer(2)
        apply!(state3, Reset(), ptr)
        @test born_probability(state3, 2, 0) ≈ 1.0 atol = 1e-12
        @test current_position(ptr) == 2  # unchanged

        # Staircase with a 2-site gate still applies at the pair (existing behavior)
        state4 = _fresh_state(L=4)
        sc4 = StaircaseRight(1)
        apply!(state4, HaarRandom(), sc4)
        @test current_position(sc4) == 2
        @test norm(state4.mps) ≈ 1.0 atol = 1e-10
    end

    @testset "user-defined gate: needs_normalization trait (no src/ edits)" begin
        state = _fresh_state()
        apply!(state, Hadamard(), SingleSite(1))  # |+> at site 1
        @test born_probability(state, 1, 0) ≈ 0.5 atol = 1e-12
        apply!(state, MyProjExecuteTest(), SingleSite(1))
        # Projection |0><0| shrinks the norm to 1/sqrt(2); the trait must renormalize
        @test norm(state.mps) ≈ 1.0 atol = 1e-10
        @test born_probability(state, 1, 0) ≈ 1.0 atol = 1e-12
    end

    @testset "user-defined gate: execute! override (no src/ edits)" begin
        state = _fresh_state()
        apply!(state, MyFlipExecuteTest(), SingleSite(3))
        @test born_probability(state, 3, 1) ≈ 1.0 atol = 1e-12
    end

    @testset "SpinSectorMeasurement Born path preserved through execute!" begin
        # Z0 x Z0 two-spin-1 state: overlaps S=0,1,2 sectors; forced to {0,1}
        # (OBC so physical sites 1,2 are RAM-adjacent, as SpinSector* requires)
        state = _fresh_state(L=4, bc=:open, site_type="S=1", maxdim=128)
        gate = SpinSectorMeasurement([0, 1])
        apply!(state, gate, AdjacentPair(1))
        @test norm(state.mps) ≈ 1.0 atol = 1e-10  # trait-normalized after collapse

        # Determinism: same seeds -> same collapsed state (RAM-order ⟨Sz⟩)
        state_a = _fresh_state(L=4, bc=:open, site_type="S=1", maxdim=128)
        apply!(state_a, SpinSectorMeasurement([0, 1]), AdjacentPair(1))
        za = ITensorMPS.expect(state_a.mps, "Sz")
        state_b = _fresh_state(L=4, bc=:open, site_type="S=1", maxdim=128)
        apply!(state_b, SpinSectorMeasurement([0, 1]), AdjacentPair(1))
        zb = ITensorMPS.expect(state_b.mps, "Sz")
        @test za ≈ zb atol = 1e-14
    end

    @testset "Circuit engine uses uniform execute! (Reset in stochastic branch)" begin
        # CIPT-style circuit exercising the engine's Reset path (formerly
        # special-cased in execute_gate!)
        circuit = Circuit(L=4, bc=:periodic) do c
            apply_with_prob!(c; outcomes=[
                (probability=1.0, gate=Reset(), geometry=StaircaseRight(1))
            ])
        end
        state = _fresh_state(L=4)
        for i in 1:4
            apply!(state, PauliX(), SingleSite(i))  # |1111>
        end
        simulate!(circuit, state; n_steps=4, record_when=:final_only)
        for i in 1:4
            @test born_probability(state, i, 0) ≈ 1.0 atol = 1e-12
        end

        # Measurement through the engine's deterministic compound path
        circuit2 = Circuit(L=4, bc=:periodic) do c
            apply!(c, Measurement(:Z), AllSites())
        end
        state2 = _fresh_state(L=4)
        apply!(state2, Hadamard(), SingleSite(1))
        simulate!(circuit2, state2; n_steps=1, record_when=:final_only)
        p0 = born_probability(state2, 1, 0)
        @test isapprox(p0, 1.0; atol=1e-12) || isapprox(p0, 0.0; atol=1e-12)  # collapsed
        @test norm(state2.mps) ≈ 1.0 atol = 1e-10
    end
end
