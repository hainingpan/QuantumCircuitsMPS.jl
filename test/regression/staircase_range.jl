# === regression: staircase `range` is honored on every execution path ===
#
# `StaircaseRight(p; range=r)` / `StaircaseLeft(p; range=r)` document the
# two-site target as (pos, pos+range). The canonical `elements()` enumeration
# always said so, but the execution-side resolver `compute_sites(geo, step,
# L, bc, gate)` used a nearest-neighbor shortcut that ignored `range`, so
# every path that applies gates (eager `apply!`, `apply_with_prob!`,
# `simulate!`, `expand_circuit`) acted on (pos, pos+1) instead. Open-boundary
# advancement also assumed range=1 (cycling over 1:L-1), which for range>1
# walked the pair off the end of the chain.
#
# These tests pin the corrected behavior:
#   (a) compute_sites == elements for two-site gates, for both directions and
#       both boundary conditions; single-site gates still act at `pos`
#   (b) end-to-end: CNOT on StaircaseRight(1; range=2) from |1000> gives
#       |1010> on MPS, state-vector, and Clifford backends; GaussianHaar on a
#       range=2 staircase matches the explicit Sites([1,3]) region
#   (c) the circuit, expansion, and eager-probabilistic paths all target
#       (pos, pos+range)
#   (d) OBC advancement cycles over 1:(L-range) so (pos, pos+range) always
#       fits; range=1 keeps the historical 1:(L-1) cycle; range >= L rejects
#       cleanly

using Test
using QuantumCircuitsMPS
using QuantumCircuitsMPS: compute_sites, elements, advance!, current_position,
                          events, GateApplied

@isdefined(make_backend_state) || include(joinpath(@__DIR__, "..", "testutils.jl"))

# Occupation pattern (outcome-1 Born probability per site), backend-agnostic.
_occupation(state, L) = [round(Int, BornProbability(i, 1)(state)) for i in 1:L]

@testset "REGRESSION staircase_range" begin

    # =====================================================================
    # (a) compute_sites honors range and agrees with elements()
    # =====================================================================
    @testset "compute_sites: two-site gates target (pos, pos+range)" begin
        L = 6
        for Geo in (StaircaseRight, StaircaseLeft), bc in (:open, :periodic),
            range in (1, 2, 3), pos in 1:(L - range)
            geo = Geo(pos; range = range)
            @test compute_sites(geo, 1, L, bc, CNOT()) == [pos, pos + range]
            @test compute_sites(geo, 1, L, bc, CNOT()) == elements(geo, L, bc)[1]
            # `step` is ignored: the staircase resolves at its current position
            @test compute_sites(geo, 7, L, bc, HaarRandom()) == [pos, pos + range]
        end
        # The headline case from the audit
        @test compute_sites(StaircaseRight(1; range = 2), 1, 4, :periodic, CNOT()) ==
              [1, 3]
        @test compute_sites(StaircaseLeft(1; range = 2), 1, 4, :open, CNOT()) == [1, 3]
    end

    @testset "compute_sites: PBC wrap and OBC bounds follow range" begin
        # PBC wraps via mod1
        @test compute_sites(StaircaseRight(4; range = 2), 1, 4, :periodic, CNOT()) ==
              [4, 2]
        @test compute_sites(StaircaseLeft(5; range = 3), 1, 6, :periodic, CNOT()) ==
              [5, 2]
        # OBC: pos+range beyond L is rejected (same error elements() raises)
        @test_throws ArgumentError compute_sites(
            StaircaseRight(3; range = 2), 1, 4, :open, CNOT())
        @test_throws ArgumentError compute_sites(
            StaircaseLeft(4; range = 1), 1, 4, :open, CNOT())
    end

    @testset "compute_sites: single-site gates act at pos (range irrelevant)" begin
        for Geo in (StaircaseRight, StaircaseLeft), bc in (:open, :periodic)

            @test compute_sites(Geo(3; range = 2), 1, 4, bc, Reset()) == [3]
            @test compute_sites(Geo(2; range = 2), 1, 4, bc, Measure(:Z)) == [2]
        end
    end

    # =====================================================================
    # (b) end-to-end eager apply! on every backend
    # =====================================================================
    @testset "apply!: CNOT on range=2 staircase flips the NNN site ($backend, $bc)" for backend in (:mps, :statevector, :clifford),
        bc in (:open, :periodic)

        L = 4
        # |1000>: site 1 occupied. CNOT(control=1, target=3) must give |1010>.
        for Geo in (StaircaseRight, StaircaseLeft)
            state = make_backend_state(backend, L; bc = bc, binary_int = 8)
            geo = Geo(1; range = 2)
            apply!(state, CNOT(), geo)
            @test _occupation(state, L) == [1, 0, 1, 0]
        end
        # range=1 (default) is unchanged: CNOT(1→2) gives |1100>
        state = make_backend_state(backend, L; bc = bc, binary_int = 8)
        apply!(state, CNOT(), StaircaseRight(1))
        @test _occupation(state, L) == [1, 1, 0, 0]
    end

    @testset "apply!: Bell pair across (1,3) is entangled across cut=2 ($backend)" for backend in (:mps, :statevector, :clifford)
        L = 4
        # H on 1, CNOT on (1,3): a Bell pair between sites 1 and 3 carries one
        # bit across the cut [1,2]|[3,4]. A nearest-neighbor pair (1,2) would
        # carry zero across that cut — this discriminates range=2 from range=1.
        state = make_backend_state(backend, L; bc = :open)
        apply!(state, Hadamard(), SingleSite(1))
        apply!(state, CNOT(), StaircaseRight(1; range = 2))
        @test EntanglementEntropy(cut = 2)(state)≈1.0 atol=1e-10
        @test EntanglementEntropy(cut = 3)(state)≈0.0 atol=1e-10

        nn = make_backend_state(backend, L; bc = :open)
        apply!(nn, Hadamard(), SingleSite(1))
        apply!(nn, CNOT(), StaircaseRight(1))
        @test EntanglementEntropy(cut = 2)(nn)≈0.0 atol=1e-10
    end

    @testset "apply!: GaussianHaar on range=2 staircase == explicit Sites([1,3])" begin
        L = 4
        via_staircase = make_backend_state(:gaussian, L; bc = :open)
        via_sites = make_backend_state(:gaussian, L; bc = :open)
        apply!(via_staircase, GaussianHaar(), StaircaseRight(1; range = 2))
        apply!(via_sites, GaussianHaar(), Sites([1, 3]))   # same :gates_realization draw
        @test via_staircase.backend.corr ≈ via_sites.backend.corr
        # ...and differs from the nearest-neighbor (1,2) application
        via_nn = make_backend_state(:gaussian, L; bc = :open)
        apply!(via_nn, GaussianHaar(), Sites([1, 2]))
        @test !(via_staircase.backend.corr ≈ via_nn.backend.corr)
    end

    # =====================================================================
    # (c) circuit, expansion, and eager-probabilistic paths
    # =====================================================================
    @testset "simulate!: deterministic range=2 staircase targets (pos, pos+2) under OBC" begin
        L = 4
        circuit = Circuit(L = L, bc = :open) do c
            apply!(c, CNOT(), StaircaseRight(1; range = 2))
        end
        state = make_backend_state(:statevector, L; bc = :open, binary_int = 8,
            log_events = true)
        simulate!(circuit, state; n_steps = 3)
        applied = [ev.sites for ev in events(state) if ev isa GateApplied]
        # OBC cycle for range=2 is 1 → 2 → 1 (never position 3, whose pair
        # (3,5) would leave the chain)
        @test applied == [[1, 3], [2, 4], [1, 3]]
        # |1000> → CNOT(1,3) → |1010> → CNOT(2,4) (control 2 is 0) → |1010>
        #        → CNOT(1,3) → |1000>
        @test _occupation(state, L) == [1, 0, 0, 0]
    end

    @testset "simulate!: stochastic (CIPT-style) range=2 staircases under OBC" begin
        L = 5
        left = StaircaseLeft(1; range = 2)
        right = StaircaseRight(1; range = 2)
        circuit = Circuit(L = L, bc = :open) do c
            apply_with_prob!(c;
                outcomes = [
                    (probability = 0.5, gate = Reset(), geometry = left),
                    (probability = 0.5, gate = HaarRandom(), geometry = right)])
        end
        state = make_backend_state(:mps, L; bc = :open, log_events = true)
        simulate!(circuit, state; n_steps = 40)   # would throw pre-fix at pos 4
        for ev in events(state)
            ev isa GateApplied || continue
            if length(ev.sites) == 2
                @test ev.sites[2] == ev.sites[1] + 2
                @test ev.sites[2] <= L
            else
                @test 1 <= ev.sites[1] <= L - 2
            end
        end
    end

    @testset "expand_circuit: range=2 staircase ops list (pos, pos+2)" begin
        L = 4
        circuit = Circuit(L = L, bc = :open) do c
            apply!(c, CNOT(), StaircaseRight(1; range = 2))
        end
        # expand_circuit returns one Vector{ExpandedOp} per step (one op each here)
        steps = expand_circuit(circuit; n_steps = 3)
        @test [only(ops).sites for ops in steps] == [[1, 3], [2, 4], [1, 3]]

        circuit_pbc = Circuit(L = L, bc = :periodic) do c
            apply!(c, CNOT(), StaircaseLeft(1; range = 2))
        end
        steps_pbc = expand_circuit(circuit_pbc; n_steps = 3)
        @test [only(ops).sites for ops in steps_pbc] == [[1, 3], [4, 2], [3, 1]]
    end

    @testset "apply_with_prob! (eager): range=2 staircase targets (pos, pos+2)" begin
        L = 4
        for bc in (:open, :periodic)
            state = make_backend_state(:statevector, L; bc = bc, binary_int = 8)
            geo = StaircaseRight(1; range = 2)
            apply_with_prob!(state;
                outcomes = [(probability = 1.0, gate = CNOT(), geometry = geo)])
            @test _occupation(state, L) == [1, 0, 1, 0]
            @test current_position(geo) == 2
        end
    end

    # =====================================================================
    # (d) open-boundary advancement follows range
    # =====================================================================
    @testset "advance!: OBC cycle is 1:(L-range)" begin
        L = 5
        # Positions visited over `n` applications (current position, then advance)
        function walk(geo, n, bc)
            visited = Int[]
            for _ in 1:n
                push!(visited, current_position(geo))
                advance!(geo, L, bc)
            end
            return visited
        end
        @test walk(StaircaseRight(1; range = 1), 6, :open) == [1, 2, 3, 4, 1, 2]   # unchanged
        @test walk(StaircaseRight(1; range = 2), 6, :open) == [1, 2, 3, 1, 2, 3]
        @test walk(StaircaseRight(1; range = 3), 6, :open) == [1, 2, 1, 2, 1, 2]
        @test walk(StaircaseLeft(1; range = 1), 6, :open) == [1, 4, 3, 2, 1, 4]     # unchanged
        @test walk(StaircaseLeft(1; range = 2), 6, :open) == [1, 3, 2, 1, 3, 2]
        @test walk(StaircaseLeft(2; range = 3), 4, :open) == [2, 1, 2, 1]
        # PBC is untouched by range: full 1:L cycle
        @test walk(StaircaseRight(4; range = 2), 6, :periodic) == [4, 5, 1, 2, 3, 4]
        @test walk(StaircaseLeft(2; range = 2), 6, :periodic) == [2, 1, 5, 4, 3, 2]
    end

    @testset "advance!: range >= L under OBC is rejected, not a DivideError" begin
        @test_throws ArgumentError advance!(StaircaseRight(1; range = 4), 4, :open)
        @test_throws ArgumentError advance!(StaircaseLeft(1; range = 5), 4, :open)
    end
end
