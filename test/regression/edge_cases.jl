# test/regression/edge_cases.jl
#
# T27 coverage additions (v0.4.0) — permanent regression guards for:
#   1. L=1 minimal systems (MPS + Clifford backends)
#   2. odd-L periodic circuits (L=5): Bricklayer wrap behavior post-T17 fix
#      (commit 23a5dee — no double-touch), a full MIPT circuit on the SV
#      backend, and the MPS backend's documented clean rejection of odd-L PBC
#      (the folded basis requires even L, src/Core/basis.jl)
#   3. SimulationState / ProductState constructor validation, including two
#      validations ADDED by T27 (L >= 1; binary_int >= 0) that previously
#      allowed silent construction of unusable/garbage states
#
# Scope is EXACTLY the cases enumerated in the v0.4 plan (T27) — no fuzzing,
# no exhaustive negative testing.

using Test
using QuantumCircuitsMPS
using LinearAlgebra: norm

@testset "REGRESSION edge_cases (T27)" begin

    # =====================================================================
    # 1. L=1 minimal systems
    # =====================================================================
    @testset "L=1 MPS: PauliX flip -> BornProbability(1,1) ≈ 1" begin
        state = SimulationState(L = 1, bc = :open, backend = :mps,
            rng = RNGRegistry(gates_spacetime = 1, gates_realization = 2,
                born_measurement = 3))
        initialize!(state, ProductState(binary_int = 0))
        apply!(state, PauliX(), SingleSite(1))
        @test BornProbability(1, 1)(state)≈1.0 atol=1e-12
        @test BornProbability(1, 0)(state)≈0.0 atol=1e-12
    end

    @testset "L=1 Clifford: PauliX flip -> Magnetization(:Z) ≈ -1" begin
        state = SimulationState(L = 1, bc = :open, backend = :clifford,
            rng = RNGRegistry(gates_spacetime = 1, gates_realization = 2,
                born_measurement = 3))
        initialize!(state, ProductState(binary_int = 0))
        apply!(state, PauliX(), SingleSite(1))
        @test Magnetization(:Z)(state)≈-1.0 atol=1e-12
    end

    # =====================================================================
    # 2. Odd-L PBC (L=5)
    # =====================================================================
    @testset "odd-L PBC: Bricklayer wrap behavior (post-T17 fix 23a5dee)" begin
        # T17 fixed the :even odd-L PBC double-touch bug (enumeration was
        # [[2,3],[4,5],[5,1]] — site 5 in TWO pairs of one brickwork layer).
        # PIN the corrected behavior: NO wrap pair is added at odd L; :even
        # leaves site 1 unpaired (mirror of :odd leaving site L unpaired).
        # Partial per-layer coverage at odd L is the documented design (no
        # error raised) — see .sisyphus/notepads/v04-findings.md (T9 + T17).
        @test QuantumCircuitsMPS.elements(Bricklayer(:even), 5, :periodic) ==
              [[2, 3], [4, 5]]
        @test QuantumCircuitsMPS.elements(Bricklayer(:odd), 5, :periodic) ==
              [[1, 2], [3, 4]]
        # No single layer touches any site twice
        for parity in (:odd, :even)
            layer = QuantumCircuitsMPS.elements(Bricklayer(parity), 5, :periodic)
            @test allunique(reduce(vcat, layer))
        end
    end

    @testset "odd-L PBC: full MIPT circuit, 3 steps, SV backend" begin
        L, p, n_steps = 5, 0.3, 3
        circuit = Circuit(L = L, bc = :periodic) do c
            apply!(c, HaarRandom(), Bricklayer(:even))
            apply_with_prob!(c;
                outcomes = [
                    (probability = p, gate = Measure(:Z), geometry = AllSites())
                ])
            apply!(c, HaarRandom(), Bricklayer(:odd))
            apply_with_prob!(c;
                outcomes = [
                    (probability = p, gate = Measure(:Z), geometry = AllSites())
                ])
        end
        state = SimulationState(L = L, bc = :periodic, backend = :statevector,
            rng = RNGRegistry(gates_spacetime = 42, gates_realization = 2,
                born_measurement = 1))
        initialize!(state, ProductState(binary_int = 0))
        track!(state, :entropy => EntanglementEntropy(cut = L ÷ 2))

        simulate!(circuit, state; n_steps = n_steps, record_when = :every_step)

        entropies = state.observables[:entropy]
        @test length(entropies) == n_steps
        @test all(isfinite, entropies)
        @test all(e -> e >= -1e-12, entropies)
        @test norm(state.backend.ψ)≈1.0 atol=1e-12
    end

    @testset "odd-L PBC: MPS backend cleanly rejects (folded basis needs even L)" begin
        # The MPS folded-PBC basis requires even L by design
        # (src/Core/basis.jl) — an odd-L periodic run is only possible on the
        # SV/Clifford backends (identity mapping). PIN the clean ArgumentError
        # at construction so it never degrades into a raw crash.
        err = try
            SimulationState(L = 5, bc = :periodic, backend = :mps)
            nothing
        catch e
            e
        end
        @test err isa ArgumentError
        @test occursin("requires even L", err.msg)
    end

    # =====================================================================
    # 3. Constructor validation
    # =====================================================================
    @testset "SimulationState: L=0 rejected (all 3 backends)" begin
        # Validation ADDED by T27: previously L=0 (and negative L) was
        # silently accepted on all 3 backends, yielding an empty state.
        for backend in (:mps, :statevector, :clifford)
            @test_throws ArgumentError SimulationState(
                L = 0, bc = :open, backend = backend)
        end
        err = try
            SimulationState(L = 0, bc = :open)
            nothing
        catch e
            e
        end
        @test err isa ArgumentError
        @test occursin("L must be a positive integer", err.msg)
    end

    @testset "SimulationState: invalid bc / backend rejected" begin
        @test_throws ArgumentError SimulationState(L = 4, bc = :weird)
        @test_throws ArgumentError SimulationState(L = 4, bc = :open, backend = :foo)
        # Messages are informative (not raw crashes)
        err_bc = try
            SimulationState(L = 4, bc = :weird)
            nothing
        catch e
            e
        end
        @test occursin("bc must be :open or :periodic", err_bc.msg)
        err_backend = try
            SimulationState(L = 4, bc = :open, backend = :foo)
            nothing
        catch e
            e
        end
        @test occursin("backend must be :mps, :statevector, or :clifford",
            err_backend.msg)
    end

    @testset "ProductState: binary_int=-1 rejected" begin
        # Validation ADDED by T27: previously ProductState(binary_int=-1) was
        # silently accepted, and initialize! parsed the '-' sign character of
        # the base-2 string as a bogus state label — producing a garbage state
        # instead of erroring.
        @test_throws ArgumentError ProductState(binary_int = -1)
        err = try
            ProductState(binary_int = -1)
            nothing
        catch e
            e
        end
        @test err isa ArgumentError
        @test occursin("binary_int must be non-negative", err.msg)
        # Positive controls: valid values still construct
        @test ProductState(binary_int = 0) isa ProductState
        @test ProductState(binary_int = 5) isa ProductState
    end

    @testset "L=1 periodic MPS: PINNED current behavior (clean error)" begin
        # Enumerated case "L=1 periodic MPS -> verify current behavior and PIN
        # it (works or clean error)": current behavior is the same clean
        # even-L folded-basis ArgumentError at construction. PINNED.
        err = try
            SimulationState(L = 1, bc = :periodic, backend = :mps)
            nothing
        catch e
            e
        end
        @test err isa ArgumentError
        @test occursin("requires even L", err.msg)
        @test occursin("L=1", err.msg)
    end
end
