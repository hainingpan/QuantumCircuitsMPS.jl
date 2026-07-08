# === T23 regression: elements() caching in simulate! (static geometries only) ===
#
# simulate! caches `elements(geo, L, bc)` per op index, LOCAL to one
# simulate! call, ONLY for geometries with `_is_static_geometry(geo) == true`
# (Bricklayer, AllSites, EachSite, Sites, SingleSite, AdjacentPair).
# Mutable geometries (StaircaseLeft/Right, Pointer) and any unknown geometry
# type bypass the cache and are recomputed every step.
#
# Safety proof (plan T23):
#   (a) CIPT staircase (mutable geometry) trajectory bitwise-identical to the
#       cache-free eager reference under the same seeds
#   (b) Pointer+move! workflow unaffected (Pointer is eager-only today —
#       simulate! cannot even reach it — and the trait marks it non-static)
#   (c) Bricklayer/AllSites MIPT trajectory bitwise-identical to the
#       cache-free eager reference; repeat simulate! runs bitwise-identical
#   (d) allocation reduction for the MIPT simulate! benchmark is measured
#       out-of-suite (Bash @allocated before/after) — evidence:
#       .sisyphus/evidence/v04/task-23-alloc.log
#
# The eager path (`apply_with_prob!(state; ...)` / `apply!(state, ...)`)
# shares the selection engine with simulate! but has NO elements cache, so
# bitwise lazy==eager equality under identical seeds proves the cache is
# observationally transparent.

using Test
using QuantumCircuitsMPS
using QuantumCircuitsMPS: _is_static_geometry, events, measurements, GateApplied
using QuantumCircuitsMPS: move!, current_position

# Unknown geometry type for the conservative-fallback trait check
# (struct definitions must live at top level, outside @testset scopes)
struct _T23UnknownGeo <: QuantumCircuitsMPS.AbstractGeometry end

function _cache_test_state(; L = 8, bc = :periodic, backend = :mps,
        gs = 42, born = 1, real = 2, log_events = false)
    st = SimulationState(; L = L, bc = bc, maxdim = 64, backend = backend,
        rng = RNGRegistry(
            gates_spacetime = gs, born_measurement = born, gates_realization = real),
        log_events = log_events)
    initialize!(st, ProductState(binary_int = 0))
    return st
end

@testset "T23 elements() caching in simulate!" begin
    @testset "_is_static_geometry trait (explicit + conservative)" begin
        # Static (cacheable): step-invariant immutable geometries
        @test _is_static_geometry(Bricklayer(:even))
        @test _is_static_geometry(Bricklayer(:odd))
        @test _is_static_geometry(AllSites())
        @test _is_static_geometry(EachSite(2:5))
        @test _is_static_geometry(Sites(1:3))
        @test _is_static_geometry(SingleSite(1))
        @test _is_static_geometry(AdjacentPair(2))
        # Mutable (NEVER cached): advancing/movable positions
        @test !_is_static_geometry(StaircaseLeft(1))
        @test !_is_static_geometry(StaircaseRight(1))
        @test !_is_static_geometry(Pointer(1))
        # Conservative fallback: unknown geometry types default to false
        @test !_is_static_geometry(_T23UnknownGeo())
    end

    @testset "(a) CIPT staircase trajectory bitwise-identical (cache bypassed)" begin
        L, p_ctrl, n_steps = 8, 0.5, 24

        # Lazy: Circuit + simulate! (contains the per-call cache machinery;
        # staircases must bypass it)
        circuit = Circuit(L = L, bc = :periodic) do c
            apply_with_prob!(c;
                outcomes = [
                    (probability = p_ctrl, gate = Reset(), geometry = StaircaseLeft(1)),
                    (probability = 1 - p_ctrl, gate = HaarRandom(),
                        geometry = StaircaseRight(1))])
        end
        st_lazy = _cache_test_state(L = L, log_events = true)
        track!(st_lazy, :Mz => Magnetization(:Z))
        simulate!(circuit, st_lazy; n_steps = n_steps, record_when = :every_step)

        # Eager reference: NO cache exists on this path — same seeds
        left = StaircaseLeft(1)
        right = StaircaseRight(1)
        st_eager = _cache_test_state(L = L, log_events = true)
        track!(st_eager, :Mz => Magnetization(:Z))
        for _ in 1:n_steps
            apply_with_prob!(st_eager;
                outcomes = [
                    (probability = p_ctrl, gate = Reset(), geometry = left),
                    (probability = 1 - p_ctrl, gate = HaarRandom(), geometry = right)])
            record!(st_eager)
        end

        # BITWISE identity (==, not ≈): staircase positions advance
        # identically, so sites/outcomes/observables coincide exactly
        @test st_lazy.observables[:Mz] == st_eager.observables[:Mz]
        # The applied-site sequences match one-for-one (positions advanced
        # per selected outcome, never frozen by a cache)
        sites_lazy = [e.sites for e in events(st_lazy) if e isa GateApplied]
        sites_eager = [e.sites for e in events(st_eager) if e isa GateApplied]
        @test sites_lazy == sites_eager
        @test length(sites_lazy) > 1
        # A trajectory where the staircase actually moved: not all site
        # pairs identical (guards against a cache freezing the position)
        @test length(unique(sites_lazy)) > 1
        # Streams fully in sync afterwards
        for stream in (:gates_spacetime, :gates_realization, :born_measurement)
            @test rand(copy(get_rng(st_lazy.rng_registry, stream))) ==
                  rand(copy(get_rng(st_eager.rng_registry, stream)))
        end

        # Repeat simulate! with a fresh identically-seeded state: bitwise
        # reproducible (cache is per-call; no cross-call leakage)
        st_rerun = _cache_test_state(L = L)
        track!(st_rerun, :Mz => Magnetization(:Z))
        simulate!(circuit, st_rerun; n_steps = n_steps, record_when = :every_step)
        @test st_rerun.observables[:Mz] == st_lazy.observables[:Mz]
    end

    @testset "(b) Pointer + move! workflow unaffected" begin
        # Pointer is non-static by trait (asserted above) AND is eager-only:
        # simulate! cannot execute a Pointer op today (no compute_sites
        # method), so the cache can never touch one. Pin both facts.
        ptr_circ = Pointer(1)
        bad = Circuit(L = 4, bc = :periodic) do c
            apply!(c, PauliX(), ptr_circ)
        end
        st_bad = _cache_test_state(L = 4)
        @test_throws MethodError simulate!(bad, st_bad; n_steps = 1)

        # Eager Pointer + move! workflow: sites must track the pointer's
        # explicit movement, bitwise-reproducible across identical runs.
        function pointer_walk(; L = 6)
            st = _cache_test_state(L = L, bc = :periodic)
            ptr = Pointer(1)
            visited = Vector{Int}[]
            for _ in 1:L
                push!(visited, [current_position(ptr)])
                apply!(st, PauliX(), ptr)      # 1-site gate: acts at [pos]
                move!(ptr, :right, L, :periodic)
            end
            return visited, current_position(ptr),
            [born_probability(st, i, 1) for i in 1:L]
        end
        visited1, pos1, probs1 = pointer_walk()
        visited2, pos2, probs2 = pointer_walk()
        # The pointer genuinely walked: one application per site in order
        @test visited1 == [[1], [2], [3], [4], [5], [6]]
        @test pos1 == 1   # wrapped around L=6
        # Every site flipped once by PauliX: |0...0⟩ → |1...1⟩
        @test probs1 == ones(6)
        # Bitwise identical across identically-seeded repeats
        @test visited1 == visited2
        @test pos1 == pos2
        @test probs1 == probs2
    end

    @testset "(c) Bricklayer/AllSites MIPT trajectory bitwise-identical (cache hit path)" begin
        L, p, n_steps = 8, 0.15, 12

        circuit = Circuit(L = L, bc = :periodic) do c
            apply!(c, HaarRandom(), Bricklayer(:even))       # deterministic broadcast → cached
            apply_with_prob!(c; outcomes = [
                (probability = p, gate = Measure(:Z), geometry = AllSites())])  # stochastic broadcast → cached
            apply!(c, HaarRandom(), Bricklayer(:odd))
            apply_with_prob!(c; outcomes = [
                (probability = p, gate = Measure(:Z), geometry = AllSites())])
        end

        for backend in (:mps, :statevector)
            st_lazy = _cache_test_state(L = L, backend = backend, log_events = true)
            track!(st_lazy, :entropy => EntanglementEntropy(cut = L ÷ 2))
            track!(st_lazy, :Mz => Magnetization(:Z))
            simulate!(circuit, st_lazy; n_steps = n_steps, record_when = :every_step)

            # Eager reference (no cache), same seeds
            st_eager = _cache_test_state(L = L, backend = backend, log_events = true)
            track!(st_eager, :entropy => EntanglementEntropy(cut = L ÷ 2))
            track!(st_eager, :Mz => Magnetization(:Z))
            for _ in 1:n_steps
                apply!(st_eager, HaarRandom(), Bricklayer(:even))
                apply_with_prob!(st_eager;
                    outcomes = [
                        (probability = p, gate = Measure(:Z), geometry = AllSites())])
                apply!(st_eager, HaarRandom(), Bricklayer(:odd))
                apply_with_prob!(st_eager;
                    outcomes = [
                        (probability = p, gate = Measure(:Z), geometry = AllSites())])
                record!(st_eager)
            end

            # BITWISE identity: same backend, same seeds, same op sequence —
            # the cache must be observationally invisible
            @test st_lazy.observables[:entropy] == st_eager.observables[:entropy]
            @test st_lazy.observables[:Mz] == st_eager.observables[:Mz]
            # Identical measurement records (sites AND outcomes)
            ms_lazy = [(m.sites, m.outcome) for m in measurements(st_lazy)]
            ms_eager = [(m.sites, m.outcome) for m in measurements(st_eager)]
            @test ms_lazy == ms_eager
            for stream in (:gates_spacetime, :gates_realization, :born_measurement)
                @test rand(copy(get_rng(st_lazy.rng_registry, stream))) ==
                      rand(copy(get_rng(st_eager.rng_registry, stream)))
            end

            # Cached element enumeration is CORRECT (not just self-consistent):
            # every applied site group is a genuine element of its geometry
            bl_even = Set(elements(Bricklayer(:even), L, :periodic))
            bl_odd = Set(elements(Bricklayer(:odd), L, :periodic))
            all_sites = Set(elements(AllSites(), L, :periodic))
            for e in events(st_lazy)
                e isa GateApplied || continue
                @test (e.sites in bl_even) || (e.sites in bl_odd) ||
                      (e.sites in all_sites)
            end
        end

        # Repeat simulate! on the SAME circuit object with a fresh
        # identically-seeded state: bitwise reproducible (per-call cache)
        st_a = _cache_test_state(L = L)
        track!(st_a, :entropy => EntanglementEntropy(cut = L ÷ 2))
        simulate!(circuit, st_a; n_steps = n_steps)
        st_b = _cache_test_state(L = L)
        track!(st_b, :entropy => EntanglementEntropy(cut = L ÷ 2))
        simulate!(circuit, st_b; n_steps = n_steps)
        @test st_a.observables[:entropy] == st_b.observables[:entropy]
    end

    @testset "(c+) mixed static/mutable stochastic op bypasses cache entirely" begin
        # One outcome static (Sites), one mutable (staircase): the WHOLE op
        # must bypass the cache (conservative all-static rule)
        L, n_steps = 6, 15
        circuit = Circuit(L = L, bc = :periodic) do c
            apply_with_prob!(c;
                outcomes = [
                    (probability = 0.5, gate = Reset(), geometry = StaircaseLeft(1)),
                    (probability = 0.5, gate = HaarRandom(), geometry = StaircaseRight(1))])
            apply!(c, HaarRandom(), Bricklayer(:even))   # cached det op alongside
        end
        st_lazy = _cache_test_state(L = L)
        track!(st_lazy, :Mz => Magnetization(:Z))
        simulate!(circuit, st_lazy; n_steps = n_steps, record_when = :every_step)

        left = StaircaseLeft(1)
        right = StaircaseRight(1)
        st_eager = _cache_test_state(L = L)
        track!(st_eager, :Mz => Magnetization(:Z))
        for _ in 1:n_steps
            apply_with_prob!(st_eager;
                outcomes = [
                    (probability = 0.5, gate = Reset(), geometry = left),
                    (probability = 0.5, gate = HaarRandom(), geometry = right)])
            apply!(st_eager, HaarRandom(), Bricklayer(:even))
            record!(st_eager)
        end
        @test st_lazy.observables[:Mz] == st_eager.observables[:Mz]
    end

    @testset "(d) allocation note" begin
        # Allocation reduction for the MIPT simulate! benchmark entry is
        # measured out-of-suite (@allocated before/after via git, evidence
        # in .sisyphus/evidence/v04/task-23-alloc.log and the v04 notepad).
        # In-suite we only sanity-check that a multi-step run completes and
        # records the expected number of observations (cache plumbing sound).
        L = 6
        circuit = Circuit(L = L, bc = :open) do c
            apply!(c, HaarRandom(), Bricklayer(:even))
            apply_with_prob!(c; outcomes = [
                (probability = 0.15, gate = Measure(:Z), geometry = AllSites())])
        end
        st = _cache_test_state(L = L, bc = :open)
        track!(st, :entropy => EntanglementEntropy(cut = L ÷ 2))
        simulate!(circuit, st; n_steps = 30, record_when = :every_step)
        @test length(st.observables[:entropy]) == 30
    end
end
