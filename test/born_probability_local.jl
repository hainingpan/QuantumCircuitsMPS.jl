# test/born_probability_local.jl
#
# === born_probability (MPS backend): site-local evaluation + normalization ===
#
# Guards the site-local rewrite of `born_probability(::SimulationState{MPSBackend},
# …)` (src/Observables/born.jl) against the double-normalization regression it
# fixed: `ITensorMPS.expect` already divides by ⟨ψ|ψ⟩ internally, so the legacy
# extra `/ inner(ψ, ψ)` inflated every probability by 1/‖ψ‖² whenever the state
# was not normalized — i.e. after any truncating unitary layer.
#
# Test groups:
#   1. Equivalence vs an exact dense reference AND vs the full-vector
#      `expect(psi, "ProjK")[ram_idx]` formula, over
#      L ∈ {2, 6, 9, 10} × χ ∈ {4, 16} × {Float64, ComplexF64} ×
#      {"Qubit", "S=1"} × bc ∈ {:open, :periodic}, every outcome, plus the
#      Born sum rule Σₖ P(k) = 1.
#   2. Norm-drift regression — THE bug-fix test: on a deliberately rescaled
#      MPS the returned value must equal the normalized probability, NOT the
#      legacy `P_correct / ‖ψ‖²`.
#   3. Non-destructiveness of the PUBLIC function (documented read-only
#      contract relied on by the `BornProbability` observable).
#   4. Draw-count invariance: the :born_measurement stream still advances by
#      exactly one scalar draw per measured site.
#   5. Canonicity: over ≥50 measurement events at L = 8, 12 (PBC, actively
#      truncating), probabilities stay in [−1e-12, 1+1e-12] and ‖ψ‖ = 1 after
#      every post-measurement `normalize!`.

using Test
using Random
using LinearAlgebra: norm, normalize!
using ITensors: array
using ITensorMPS
using QuantumCircuitsMPS

# --- helpers (file-local, `_bpl_` prefixed to avoid clashes across the suite) ---

"""
Build a `SimulationState{MPSBackend}` whose MPS is a random MPS of bond
dimension `chi` and element type `elt`, laid out on the state's OWN RAM-ordered
site indices — so the `phy_ram` fold is genuinely exercised for `bc = :periodic`.
"""
function _bpl_state(; L::Int, chi::Int, site_type::String, elt::Type, bc::Symbol,
        seed::Int, normalized::Bool = true)
    state = SimulationState(L = L, bc = bc, site_type = site_type,
        maxdim = max(chi, 64), cutoff = 1.0e-10)
    psi = random_mps(MersenneTwister(seed), elt, state.backend.sites; linkdims = chi)
    normalized && normalize!(psi)
    state.backend.mps = psi
    return state
end

function _bpl_relerr(a::Real, b::Real)
    s = max(abs(a), abs(b))
    return s < 1.0e-300 ? abs(a - b) : abs(a - b) / s
end

"""
Exact reference P(k) at RAM site `r`: contract the whole MPS to a dense array
and sum |amplitude|² over the level-`k` slice, divided by the total weight.
Independent of `expect`, `inner` and of any MPS gauge convention.
"""
function _bpl_exact_probs(psi, sites, r::Int, d::Int)
    A = array(prod(psi), sites...)
    den = sum(abs2, A)
    return [sum(abs2, selectdim(A, r, k + 1)) / den for k in 0:(d - 1)]
end

# true iff the :born_measurement stream of `state` (seeded with `seed`) has
# advanced by exactly `ndraws` scalar draws. Mirrors `_bm_stream_advanced_by`
# (test/audit/born_measurement.jl), which runtests.jl includes after this file.
function _bpl_stream_advanced_by(state, seed::Int, ndraws::Int)
    twin = MersenneTwister(seed)
    for _ in 1:ndraws
        rand(twin)
    end
    return rand(copy(get_rng(state.rng_registry, :born_measurement))) == rand(copy(twin))
end

_bpl_local_dim(site_type::String) = site_type == "S=1" ? 3 : 2

@testset "born_probability (MPS): site-local + correctly normalized" begin

    # --- 1. Equivalence with an exact dense reference -------------------------
    @testset "1. equivalence vs exact reference" begin
        # The PBC folded basis requires an EVEN L (src/Core/basis.jl), so odd L
        # runs open-only and L = 10 covers "long chain + phy_ram fold".
        configs = [(L = L, chi = chi, site_type = stype, elt = elt, bc = bc)
                   for L in (2, 6, 9, 10), chi in (4, 16),
                       stype in ("Qubit", "S=1"), elt in (Float64, ComplexF64),
                       bc in (:open, :periodic)
                   if !(bc === :periodic && isodd(L))]

        @testset "L=$(cfg.L) χ=$(cfg.chi) $(cfg.site_type) $(cfg.elt) bc=$(cfg.bc)" for (
            i, cfg) in enumerate(configs)
            state = _bpl_state(; L = cfg.L, chi = cfg.chi, site_type = cfg.site_type,
                elt = cfg.elt, bc = cfg.bc, seed = 20260726 + 17i)
            psi = state.backend.mps
            d = state.local_dim
            @test d == _bpl_local_dim(cfg.site_type)

            # second reference: the full-vector expect(), indexed by RAM position
            all_probs = [expect(psi, "Proj$(k)") for k in 0:(d - 1)]

            worst_exact = 0.0        # vs the dense contraction
            worst_expect = 0.0       # vs expect(psi, "ProjK")[ram_idx]
            worst_sum = 0.0          # |Σₖ P(k) − 1|
            for phy in 1:(cfg.L)
                r = state.phy_ram[phy]
                exact = _bpl_exact_probs(psi, state.backend.sites, r, d)
                total = 0.0
                for k in 0:(d - 1)
                    p = born_probability(state, phy, k)
                    total += p
                    worst_exact = max(worst_exact, _bpl_relerr(p, exact[k + 1]))
                    worst_expect = max(
                        worst_expect, _bpl_relerr(p, real(all_probs[k + 1][r])))
                end
                worst_sum = max(worst_sum, abs(total - 1.0))
            end

            @test worst_exact <= 1.0e-12
            @test worst_expect <= 1.0e-12
            @test worst_sum <= 1.0e-10      # Born sum rule, all d outcomes
        end
    end

    # --- 2. Norm drift: THE double-normalization regression test --------------
    # Rescaling one tensor multiplies the state by a global constant, so every
    # NORMALIZED probability is invariant; the pre-fix code returned
    # `P_correct / ‖ψ‖²` instead.
    @testset "2. norm-drift semantics (double-normalization bug fix)" begin
        drift_configs = [
            (L = 6, chi = 8, site_type = "Qubit", elt = ComplexF64,
                bc = :open, tensor = 3, scale = 0.6),
            (L = 8, chi = 8, site_type = "Qubit", elt = Float64,
                bc = :periodic, tensor = 5, scale = 1.4),
            (L = 6, chi = 6, site_type = "S=1", elt = ComplexF64,
                bc = :periodic, tensor = 2, scale = 0.5),
            (L = 6, chi = 6, site_type = "S=1", elt = Float64,
                bc = :open, tensor = 4, scale = 0.25)
        ]

        @testset "L=$(cfg.L) $(cfg.site_type) $(cfg.elt) bc=$(cfg.bc) ×$(cfg.scale)" for (
            i, cfg) in enumerate(drift_configs)
            state = _bpl_state(; L = cfg.L, chi = cfg.chi, site_type = cfg.site_type,
                elt = cfg.elt, bc = cfg.bc, seed = 771 + 31i)
            psi = state.backend.mps
            d = state.local_dim

            # probabilities on the NORMALIZED state = the physically correct values
            p_ref = [[born_probability(state, phy, k) for k in 0:(d - 1)]
                     for phy in 1:(cfg.L)]

            psi[cfg.tensor] *= cfg.scale                # deliberate norm drift
            norm_sq = norm(psi)^2
            @test abs(norm_sq - 1.0) > 1.0e-3           # the drift is real
            @test abs(norm_sq - cfg.scale^2) <= 1.0e-10 # and of the expected size

            worst_correct = 0.0
            worst_sum = 0.0
            legacy_separated = true     # new value distinguishable from the buggy one
            in_range = true
            for phy in 1:(cfg.L)
                total = 0.0
                for k in 0:(d - 1)
                    p = born_probability(state, phy, k)
                    total += p
                    correct = p_ref[phy][k + 1]
                    worst_correct = max(worst_correct, _bpl_relerr(p, correct))
                    in_range &= (-1.0e-12 <= p <= 1.0 + 1.0e-12)
                    # the pre-fix return value on this drifted state
                    legacy = correct / norm_sq
                    if correct > 1.0e-3        # skip vanishing P (legacy ≈ correct ≈ 0)
                        legacy_separated &= !isapprox(p, legacy; rtol = 1.0e-6)
                    end
                end
                worst_sum = max(worst_sum, abs(total - 1.0))
            end

            @test worst_correct <= 1.0e-12   # returns the NORMALIZED probability …
            @test legacy_separated           # … and NOT the legacy P_correct/‖ψ‖²
            @test worst_sum <= 1.0e-10       # Born sum rule holds despite the drift
            @test in_range
        end
    end

    # --- 3. Non-destructiveness of the PUBLIC function -----------------------
    @testset "3. public born_probability is non-destructive" begin
        # (PBC needs an even L, hence L = 8 there.)
        @testset "L=$(L) $(site_type) bc=$(bc)" for (L, site_type, bc, elt) in (
            (7, "Qubit", :open, ComplexF64), (8, "Qubit", :periodic, Float64),
            (8, "S=1", :periodic, ComplexF64))
            state = _bpl_state(; L = L, chi = 8, site_type = site_type,
                elt = elt, bc = bc, seed = 90210)
            psi = state.backend.mps
            d = state.local_dim

            before = [copy(psi[i]) for i in 1:length(psi)]
            lims_before = (ITensorMPS.leftlim(psi), ITensorMPS.rightlim(psi))

            probe = [(phy, k) for phy in 1:L for k in 0:(d - 1)]
            v1 = [born_probability(state, phy, k) for (phy, k) in probe]
            v2 = [born_probability(state, phy, k) for (phy, k) in probe]
            v3 = [born_probability(state, phy, k) for (phy, k) in probe]

            @test state.backend.mps === psi                                # no swap
            @test all(psi[i] ≈ before[i] for i in 1:length(psi))           # elementwise
            @test maximum(norm(psi[i] - before[i]) for i in 1:length(psi)) == 0.0
            @test (ITensorMPS.leftlim(psi), ITensorMPS.rightlim(psi)) == lims_before
            @test v1 == v2 == v3                                           # bitwise stable
        end
    end

    # --- 4. Draw-count invariance: one :born_measurement draw per site -------
    @testset "4. draw-count invariance (:born_measurement)" begin
        @testset "L=$(L) bc=$(bc)" for (L, bc, n_steps) in (
            (6, :periodic, 3), (4, :open, 2))
            seed = 4321
            circuit = Circuit(L = L, bc = bc) do c
                apply!(c, HaarRandom(), Bricklayer(:odd))
                apply!(c, Measure(:Z), AllSites())
            end
            state = SimulationState(L = L, bc = bc, maxdim = 16, cutoff = 1.0e-12,
                rng = RNGRegistry(gates_spacetime = 1, gates_realization = 2,
                    born_measurement = seed))
            initialize!(state, ProductState(binary_int = 0))
            simulate!(circuit, state; n_steps = n_steps, record_when = :final_only)

            expected = n_steps * L      # one scalar draw per measured site
            @test _bpl_stream_advanced_by(state, seed, expected)
            @test !_bpl_stream_advanced_by(state, seed, expected - 1)
            @test !_bpl_stream_advanced_by(state, seed, expected + 1)
        end
    end

    # --- 5. Canonicity over a long measurement run ---------------------------
    # maxdim = 8 makes truncation BIND — the regime where the old double
    # normalization produced probabilities greater than 1.
    @testset "5. canonicity over ≥50 measurement events" begin
        @testset "L=$(L)" for (L, rounds) in ((8, 7), (12, 5))
            state = SimulationState(L = L, bc = :periodic, maxdim = 8, cutoff = 1.0e-10,
                rng = RNGRegistry(gates_spacetime = 5, gates_realization = 6,
                    born_measurement = 7))
            initialize!(state, ProductState(binary_int = 0))

            n_events = 0
            worst_norm = 0.0
            worst_sum = 0.0
            lo, hi = 1.0, 0.0
            for r in 1:rounds
                apply!(state, HaarRandom(), Bricklayer(isodd(r) ? :odd : :even))
                for phy in 1:L
                    apply!(state, Measure(:Z), SingleSite(phy))
                    n_events += 1
                    # the post-measurement normalize! must restore ‖ψ‖ = 1
                    worst_norm = max(worst_norm, abs(norm(state.backend.mps) - 1.0))
                    for site in 1:L
                        total = 0.0
                        for k in 0:1
                            p = born_probability(state, site, k)
                            total += p
                            lo = min(lo, p)
                            hi = max(hi, p)
                        end
                        worst_sum = max(worst_sum, abs(total - 1.0))
                    end
                end
            end

            @test n_events >= 50
            @test worst_norm <= 1.0e-10
            @test lo >= -1.0e-12
            @test hi <= 1.0 + 1.0e-12
            @test worst_sum <= 1.0e-10
        end
    end
end
