# test/gaussian/test_gates.jl
# Unit tests for GaussianHaar/BondParity gate TYPES (T3): support(), the
# is_measurement trait, and the generic MPS/state-vector rejection
# `_apply_single!` fallback. Actual Gaussian-backend behavior for these
# gates is implemented in a later task and is NOT tested here.
#
# NOTE: not yet wired into test/runtests.jl — run directly:
#   julia --project=. -e 'include("test/gaussian/test_gates.jl")'

using Test
using QuantumCircuitsMPS

@testset "Gaussian Gate Types (GaussianHaar, BondParity)" begin
    @testset "support()" begin
        @test QuantumCircuitsMPS.support(GaussianHaar()) == 2
        @test QuantumCircuitsMPS.support(BondParity()) == 2
    end

    @testset "is_measurement trait" begin
        @test QuantumCircuitsMPS.is_measurement(BondParity()) == true
        @test QuantumCircuitsMPS.is_measurement(GaussianHaar()) == false
    end

    # Rejection must hold on ALL three non-Gaussian backends. `:statevector`
    # and `:clifford` each have their own backend-specific `AbstractGate`
    # catch-all `_apply_single!` (StateVectorBackend/CliffordBackend), which
    # is ambiguous against an un-parameterized `SimulationState`/gate-typed
    # method — hence the explicit `SimulationState{StateVectorBackend}` /
    # `SimulationState{CliffordBackend}` disambiguating overrides added in
    # `gaussian_haar.jl`/`bond_parity.jl`. `:mps` has no such catch-all (the
    # generic `Core/apply.jl` fallback IS its implementation), so no
    # ambiguity there, but it's still tested for completeness.
    @testset "$(gate_name) rejected on backend=:$(backend)" for (gate_name, gate) in [
            ("GaussianHaar", GaussianHaar()), ("BondParity", BondParity())],
        backend in [:mps, :statevector, :clifford]

        state = SimulationState(L = 4, bc = :open, backend = backend,
            rng = RNGRegistry(gates_spacetime = 1, gates_realization = 11,
                born_measurement = 21, state_init = 31))
        initialize!(state, ProductState(binary_int = 0))

        err = nothing
        try
            apply!(state, gate, [1, 2])
        catch e
            err = e
        end
        @test err isa ArgumentError
        @test occursin("gaussian", err.msg)
    end
end
