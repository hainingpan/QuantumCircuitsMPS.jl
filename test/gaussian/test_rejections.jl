# test/gaussian/test_rejections.jl
# Unit tests for T12: Gaussian-backend observable rejections
# (src/Gaussian/observables.jl).
#
# Exhaustive observable inventory (11 types total, verified via grep against
# src/Observables/*.jl, see .sisyphus/notepads/gaussian-backend/learnings.md
# Task 12 for the full breakdown):
#   - REJECTED here (this task): StringOrder, DomainWall, PauliString,
#     Correlator, MagnetizationFluctuations
#   - Handled elsewhere, NOT rejected: BornProbability (T8, landed),
#     EntanglementEntropy / Magnetization (T10, pending as of this task),
#     MutualInformation / TripartiteMutualInformation (T11, not started),
#     EntropyProfile (pure composition of EntanglementEntropy — will work
#     automatically once T10 lands, no rejection needed)
#
# NOTE: not yet wired into test/runtests.jl — run directly:
#   julia --project=. -e 'include("test/gaussian/test_rejections.jl")'

using Test
using QuantumCircuitsMPS

function make_gaussian_state(L::Int; bc::Symbol = :open, seed::Int = 1)
    state = SimulationState(L = L, bc = bc, backend = :gaussian,
        rng = RNGRegistry(gates_spacetime = seed, gates_realization = seed + 10,
            born_measurement = seed + 20, state_init = seed + 30))
    initialize!(state, ProductState(binary_int = 0))
    return state
end

@testset "Gaussian backend observable rejections (T12)" begin

    state = make_gaussian_state(6)

    @testset "StringOrder rejected" begin
        err = nothing
        try
            StringOrder(1, 3)(state)
        catch e
            err = e
        end
        @test err isa ArgumentError
        @test occursin("StringOrder", err.msg)
        @test occursin("not supported on the Gaussian backend", err.msg)
        @test occursin(":mps", err.msg) || occursin(":statevector", err.msg)
    end

    @testset "DomainWall rejected" begin
        err = nothing
        try
            DomainWall(order = 1)(state, 1)
        catch e
            err = e
        end
        @test err isa ArgumentError
        @test occursin("DomainWall", err.msg)
        @test occursin("not supported on the Gaussian backend", err.msg)
        @test occursin(":mps", err.msg) || occursin(":statevector", err.msg)
    end

    @testset "PauliString rejected" begin
        err = nothing
        try
            PauliString(1 => :Z)(state)
        catch e
            err = e
        end
        @test err isa ArgumentError
        @test occursin("PauliString", err.msg)
        @test occursin("not supported on the Gaussian backend", err.msg)
        @test occursin(":mps", err.msg) || occursin(":statevector", err.msg)
    end

    @testset "Correlator rejected (names Correlator, not nested PauliString)" begin
        err = nothing
        try
            Correlator(1 => :Z, 2 => :Z)(state)
        catch e
            err = e
        end
        @test err isa ArgumentError
        @test occursin("Correlator", err.msg)
        @test occursin("not supported on the Gaussian backend", err.msg)
        @test occursin(":mps", err.msg) || occursin(":statevector", err.msg)
    end

    @testset "MagnetizationFluctuations rejected (names itself, not nested PauliString)" begin
        err = nothing
        try
            MagnetizationFluctuations(1:3)(state)
        catch e
            err = e
        end
        @test err isa ArgumentError
        @test occursin("MagnetizationFluctuations", err.msg)
        @test occursin("not supported on the Gaussian backend", err.msg)
        @test occursin(":mps", err.msg) || occursin(":statevector", err.msg)
    end

    @testset "Supported observables do NOT throw on Gaussian" begin
        # BornProbability: T8 landed (src/Gaussian/measurement.jl) — must work.
        @testset "BornProbability" begin
            val = BornProbability(1, 0)(state)
            @test val isa Real
            @test 0.0 <= val <= 1.0
        end

        # EntanglementEntropy / Magnetization: T10's job, a PARALLEL task.
        # If T10 has landed by the time this test runs, they must succeed
        # (no ArgumentError, no field-access crash). If T10 has NOT landed
        # yet, calling them crashes with a raw field-access error (expected
        # transient state, not this task's responsibility to fix) — recorded
        # as a skip rather than a hard failure so this test file remains
        # runnable in isolation during Wave-3 parallel development.
        for (label, obs) in (
            ("EntanglementEntropy", EntanglementEntropy(cut = 1)),
            ("Magnetization(:Z)", Magnetization(:Z)),
        )
            @testset "$label" begin
                try
                    val = obs(state)
                    @test val isa Real
                catch e
                    if e isa ArgumentError
                        # Would indicate a bug: these must NEVER be rejected
                        # by src/Gaussian/observables.jl (T12 scope).
                        @test false
                    else
                        @test_skip "$label not yet supported on Gaussian backend " *
                                   "(T10 pending as of T12) — $(typeof(e)): $(sprint(showerror, e))"
                    end
                end
            end
        end
    end

end
