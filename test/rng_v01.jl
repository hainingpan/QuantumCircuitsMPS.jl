# === RNG hygiene tests (v0.1, Task 5) ===
#
# Covers:
# 1. `draw(state_or_registry, stream)` replacing the pirated Base.rand(state, stream)
# 2. `SentinelRNG` — throws ErrorException containing "forbidden" on any draw
# 3. `with_guarded_stream(f, registry, stream)` — swap-in sentinel, ALWAYS restore
# 4. `is_aliased(registry)` + ct_compat exemption (guard bypass on aliased streams)
# 5. `expected_draws(circuit, n_steps)` — fixed :gates_spacetime consumption under
#    the v0.1 unified rule, verified against the CURRENT engine for the cases
#    where the two coincide (single-outcome compound, all-simple K=1, deterministic)

using Test
using Random
using QuantumCircuitsMPS
using QuantumCircuitsMPS: draw, with_guarded_stream, is_aliased, SentinelRNG

function _fresh_registry(; spacetime = 42, realization = 2, born = 1)
    RNGRegistry(gates_spacetime = spacetime, gates_realization = realization, born_measurement = born)
end

@testset "RNG hygiene (v0.1)" begin
    @testset "draw() replaces pirated Base.rand" begin
        # Registry method: identical sequence to the raw stream RNG
        reg = _fresh_registry()
        twin = MersenneTwister(42)
        vals = [draw(reg, :gates_spacetime) for _ in 1:5]
        @test vals == [rand(twin) for _ in 1:5]
        @test draw(reg, :gates_realization) isa Float64
        @test_throws ArgumentError draw(reg, :no_such_stream)

        # SimulationState method
        state = SimulationState(L = 4, bc = :periodic, rng = _fresh_registry(spacetime = 7))
        twin7 = MersenneTwister(7)
        @test draw(state, :gates_spacetime) == rand(twin7)
        @test draw(state, :gates_spacetime) == rand(twin7)  # sequence continues

        # State without a registry errors informatively
        bare = SimulationState(L = 4, bc = :periodic)
        err = try
            draw(bare, :gates_spacetime)
            nothing
        catch e
            e
        end
        @test err isa ErrorException
        @test occursin("RNG registry", sprint(showerror, err))

        # Type piracy removed: Base.rand no longer accepts (state, stream)
        @test !hasmethod(rand, Tuple{SimulationState, Symbol})
        @test_throws MethodError rand(state, :gates_spacetime)

        # Owned-type Base extension kept (behavior identical, not piracy)
        reg2a = _fresh_registry()
        reg2b = _fresh_registry()
        @test rand(reg2a, :gates_spacetime) == draw(reg2b, :gates_spacetime)
    end

    @testset "SentinelRNG throws 'forbidden' on any draw" begin
        s = SentinelRNG(:gates_spacetime)
        @test s isa Random.AbstractRNG

        draw_calls = [
            () -> rand(s),
            () -> rand(s, Float64),
            () -> rand(s, Bool),
            () -> rand(s, 3),
            () -> rand(s, 1:5),
            () -> rand(s, Float64, 2),
            () -> randn(s),
            () -> randn(s, 2, 2)
        ]
        for f in draw_calls
            err = try
                f()
                nothing
            catch e
                e
            end
            @test err isa ErrorException
            @test occursin("forbidden", sprint(showerror, err))
        end

        # The sentinel remembers which stream it guards (message is prescriptive)
        err = try
            rand(SentinelRNG(:gates_spacetime))
            nothing
        catch e
            e
        end
        @test occursin("gates_spacetime", sprint(showerror, err))
        @test occursin("gates_realization", sprint(showerror, err))  # points to the allowed stream
    end

    @testset "with_guarded_stream blocks / allows / restores" begin
        # Returns f()'s value
        reg = _fresh_registry()
        @test with_guarded_stream(() -> 42, reg, :gates_spacetime) == 42

        # Inside the guard: guarded stream throws, others draw freely
        reg = _fresh_registry()
        with_guarded_stream(reg, :gates_spacetime) do
            @test rand(get_rng(reg, :gates_realization)) isa Float64
            @test draw(reg, :born_measurement) isa Float64
            @test_throws ErrorException rand(get_rng(reg, :gates_spacetime))
            @test_throws ErrorException draw(reg, :gates_spacetime)
        end

        # Restores the ORIGINAL stream object and its sequence (twin comparison)
        reg_a = _fresh_registry()
        reg_b = _fresh_registry()  # unguarded twin
        # advance both identically before the guard
        draw(reg_a, :gates_spacetime);
        draw(reg_b, :gates_spacetime)
        original = get_rng(reg_a, :gates_spacetime)
        with_guarded_stream(reg_a, :gates_spacetime) do
            draw(reg_a, :gates_realization)  # consume a non-guarded stream
        end
        draw(reg_b, :gates_realization)      # twin does the same, unguarded
        @test get_rng(reg_a, :gates_spacetime) === original
        @test draw(reg_a, :gates_spacetime) == draw(reg_b, :gates_spacetime)

        # Restores even when f throws (try/finally) — the guard rethrows
        reg_c = _fresh_registry()
        orig_c = get_rng(reg_c, :gates_spacetime)
        @test_throws ErrorException with_guarded_stream(reg_c, :gates_spacetime) do
            error("boom from user code")
        end
        @test get_rng(reg_c, :gates_spacetime) === orig_c
        @test rand(get_rng(reg_c, :gates_spacetime)) isa Float64  # usable again

        # Restores after a CAUGHT internal error (sentinel fired inside f)
        reg_d = _fresh_registry()
        reg_e = _fresh_registry()  # unguarded twin
        orig_d = get_rng(reg_d, :gates_spacetime)
        with_guarded_stream(reg_d, :gates_spacetime) do
            try
                rand(get_rng(reg_d, :gates_spacetime))  # sentinel fires
            catch
            end
        end
        @test get_rng(reg_d, :gates_spacetime) === orig_d
        @test draw(reg_d, :gates_spacetime) == draw(reg_e, :gates_spacetime)

        # Unknown stream errors up front
        @test_throws ArgumentError with_guarded_stream(() -> 1, _fresh_registry(), :nope)
    end

    @testset "is_aliased + ct_compat exemption" begin
        @test !is_aliased(_fresh_registry())

        ct = RNGRegistry(Val(:ct_compat); circuit = 5, measurement = 6)
        @test is_aliased(ct)
        @test get_rng(ct, :gates_spacetime) === get_rng(ct, :gates_realization)

        # Guard is a documented NO-OP on aliased registries: draws still work
        result = with_guarded_stream(ct, :gates_spacetime) do
            rand(get_rng(ct, :gates_spacetime))
        end
        @test result isa Float64

        # ...and the guard does not perturb the shared stream's sequence
        ct1 = RNGRegistry(Val(:ct_compat); circuit = 5, measurement = 6)
        ct2 = RNGRegistry(Val(:ct_compat); circuit = 5, measurement = 6)
        with_guarded_stream(() -> nothing, ct1, :gates_spacetime)
        @test draw(ct1, :gates_spacetime) == draw(ct2, :gates_spacetime)
    end

    @testset "expected_draws: unified-rule coin counts" begin
        L = 8

        # Case A pattern (MIPT): single-outcome compound ops, K = L each
        mipt = Circuit(L = L, bc = :periodic) do c
            apply!(c, HaarRandom(), Bricklayer(:even))
            apply_with_prob!(c;
                outcomes = [
                    (probability = 0.15, gate = Measurement(:Z), geometry = AllSites())
                ])
            apply!(c, HaarRandom(), Bricklayer(:odd))
            apply_with_prob!(c;
                outcomes = [
                    (probability = 0.15, gate = Measurement(:Z), geometry = AllSites())
                ])
        end
        @test expected_draws(mipt, 1) == 2L
        @test expected_draws(mipt, 20) == 40L
        @test expected_draws(mipt, 0) == 0
        @test expected_draws(mipt, 1) isa Int

        # Deterministic-only circuit: zero coins
        det = Circuit(L = L, bc = :periodic) do c
            apply!(c, HaarRandom(), Bricklayer(:even))
            apply!(c, HaarRandom(), Bricklayer(:odd))
        end
        @test expected_draws(det, 10) == 0

        # Case C pattern (CIPT): staircase set geometries, K = 1 per op
        cipt = Circuit(L = L, bc = :periodic) do c
            apply_with_prob!(c;
                outcomes = [
                    (probability = 0.5, gate = Reset(), geometry = StaircaseLeft(1)),
                    (probability = 0.5, gate = HaarRandom(), geometry = StaircaseRight(1))
                ])
        end
        @test expected_draws(cipt, 128) == 128

        # EachSite broadcast geometry counts its collection size
        srn = Circuit(L = L, bc = :periodic) do c
            apply_with_prob!(c;
                outcomes = [
                    (probability = 0.3, gate = Measurement(:Z),
                    geometry = EachSite(2:(L - 1)))
                ])
        end
        @test expected_draws(srn, 3) == 3 * (L - 2)

        # Multi-outcome EQUAL-K compound op: the NEW rule says K coins
        # (one per element), NOT the current engine's sum over outcomes (2K).
        # Task 9 aligns the engine to this count.
        two = Circuit(L = L, bc = :periodic) do c
            apply_with_prob!(c;
                outcomes = [
                    (probability = 0.5, gate = HaarRandom(), geometry = Bricklayer(:even)),
                    (probability = 0.5, gate = CZ(), geometry = Bricklayer(:even))
                ])
        end
        K_even = element_count(Bricklayer(:even), L, :periodic)
        @test expected_draws(two, 1) == K_even   # NOT 2 * K_even

        # Unequal K across outcomes → ArgumentError printing each K.
        # Since Task 9 the builder already rejects this at build time, so
        # exercise expected_draws directly on a hand-built circuit.
        bad = Circuit(L = 4,
            bc = :periodic,
            operations = NamedTuple[
                (type = :stochastic,
                rng = :gates_spacetime,
                outcomes = [
                    (probability = 0.3, gate = Measurement(:Z), geometry = AllSites()),      # K=4
                    (probability = 0.3, gate = HaarRandom(), geometry = Bricklayer(:odd))    # K=2
                ])
            ])
        err = try
            expected_draws(bad, 1)
            nothing
        catch e
            e
        end
        @test err isa ArgumentError
        msg = sprint(showerror, err)
        @test occursin("K=4", msg)
        @test occursin("K=2", msg)

        # Negative n_steps rejected
        @test_throws ArgumentError expected_draws(det, -1)
    end

    @testset "expected_draws matches CURRENT engine (Cases A/C/D coincide)" begin
        # Run a circuit, then advance a twin MersenneTwister by
        # expected_draws() scalar draws; the :gates_spacetime streams must
        # then produce the same next value (fixed-draw invariant).
        function consumption_matches(make_circuit, n_steps; L, bc)
            reg = _fresh_registry()
            state = SimulationState(L = L, bc = bc, maxdim = 32, rng = reg)
            initialize!(state, ProductState(binary_int = 0))
            circuit = make_circuit()
            simulate!(circuit, state; n_steps = n_steps, record_when = :final_only)
            twin = MersenneTwister(42)   # same seed as :gates_spacetime above
            for _ in 1:expected_draws(circuit, n_steps)
                rand(twin)               # SCALAR-DRAW CONTRACT: scalar burn
            end
            return rand(get_rng(reg, :gates_spacetime)) == rand(twin)
        end

        L = 6

        # Case A pattern: single-outcome compound (AllSites) stochastic ops
        @test consumption_matches(4; L = L, bc = :periodic) do
            Circuit(L = L, bc = :periodic) do c
                apply!(c, HaarRandom(), Bricklayer(:even))
                apply_with_prob!(c;
                    outcomes = [
                        (
                        probability = 0.15, gate = Measurement(:Z), geometry = AllSites())
                    ])
                apply!(c, HaarRandom(), Bricklayer(:odd))
                apply_with_prob!(c;
                    outcomes = [
                        (
                        probability = 0.15, gate = Measurement(:Z), geometry = AllSites())
                    ])
            end
        end

        # Case C pattern: all-simple categorical op (staircases), K=1
        @test consumption_matches(20; L = L, bc = :periodic) do
            Circuit(L = L, bc = :periodic) do c
                apply_with_prob!(c;
                    outcomes = [
                        (probability = 0.5, gate = Reset(), geometry = StaircaseLeft(1)),
                        (probability = 0.5, gate = HaarRandom(),
                            geometry = StaircaseRight(1))
                    ])
            end
        end

        # Case D pattern: deterministic-only circuit, zero coins
        @test consumption_matches(4; L = L, bc = :periodic) do
            Circuit(L = L, bc = :periodic) do c
                apply!(c, HaarRandom(), Bricklayer(:even))
                apply!(c, HaarRandom(), Bricklayer(:odd))
            end
        end

        # Single-outcome EachSite (SRN bulk-eligibility pattern) also coincides
        @test consumption_matches(5; L = L, bc = :periodic) do
            Circuit(L = L, bc = :periodic) do c
                apply_with_prob!(c;
                    outcomes = [
                        (probability = 0.3, gate = Measurement(:Z),
                        geometry = EachSite(2:(L - 1)))
                    ])
            end
        end
    end
end
