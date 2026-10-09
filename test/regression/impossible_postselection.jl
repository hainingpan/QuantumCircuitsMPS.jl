# test/regression/impossible_postselection.jl
#
# === Impossible postselection must be rejected, not "succeed" ===
#
# Gates with needs_normalization(gate) == true (Projection,
# SpinSectorProjection, SpinSectorMeasurement, user projectors) are applied
# and then renormalized. When the requested branch has zero Born probability
# there is nothing to renormalize: the MPS backend used to return normally
# with a zero MPS (entropy then reported 0), and the state-vector backend
# with a NaN vector (every later calculation failed). Starting from |00⟩,
#
#     apply!(state, Projection(1), SingleSite(1))
#
# now throws an ArgumentError naming the gate, the physical sites and the
# Born probability ‖Pψ‖²/‖ψ‖², and — on both backends and both state-vector
# engines — leaves the state exactly as it was. The threshold is the shared
# POSTSELECTION_PROB_TOL = 1e-14 (also used by SpinSectorMeasurement).
#
# The guard compares a *probability*, i.e. the projected norm relative to
# the input norm: the MPS backend does not renormalize after truncated
# unitary layers, so ‖ψ‖² alone can be arbitrarily small (0.64^80 ≈ 3e-16
# after 80 maxdim=1 truncations) while the retained state is exactly |00⟩
# and every outcome-0 projection has probability one. Comparing raw ‖Pψ‖²
# against the threshold rejected those certain projections (and, through
# the same path, Measure / Reset / SpinSectorMeasurement) as "impossible".
#
# Test groups:
#   1. The bug-report scenario on MPS, SV :builtin and SV :optimized.
#   2. The threshold: a 1e-12 branch is accepted and normalized, a 1e-16
#      branch is rejected, on every backend/engine.
#   3. Two-site projective gates (SpinSectorProjection / SpinSectorMeasurement)
#      onto an empty sector: rejected with the MPS block never written back.
#   4. Periodic MPS (non-identity phy_ram), spin-site Projection, and the
#      circuit engine all surface the same error.
#   5. Truncated (un-renormalized) MPS with ‖ψ‖² < POSTSELECTION_PROB_TOL:
#      a certain projection, Measure, Reset, SpinSectorProjection and
#      SpinSectorMeasurement all apply; an impossible branch is still
#      rejected; the guard itself is scale-invariant and names a zero-norm
#      input.

using Test
using LinearAlgebra: I, norm
using QuantumCircuitsMPS

# --- helpers (file-local, `_ip_` prefixed: runtests.jl shares one scope) ---

_ip_rng() = RNGRegistry(gates_spacetime = 5, gates_realization = 6, born_measurement = 7)

# (label, constructor kwargs) for the three gate-application paths under test.
const _IP_PATHS = (
    ("mps", (; backend = :mps, maxdim = 16)),
    ("sv builtin", (; backend = :statevector, engine = :builtin)),
    ("sv optimized", (; backend = :statevector, engine = :optimized))
)

function _ip_state(
        kw; L = 2, bc = :open, site_type = "Qubit", init = ProductState(binary_int = 0))
    st = SimulationState(; L = L, bc = bc, site_type = site_type, rng = _ip_rng(), kw...)
    initialize!(st, init)
    return st
end

# Dense amplitudes in a backend-independent (physical-site) order, so the
# MPS and SV snapshots can be compared before/after a rejected gate.
function _ip_dense(st)
    if st.backend isa QuantumCircuitsMPS.StateVectorBackend
        return copy(st.backend.ψ)
    end
    L = st.L
    full = reduce(*, [st.backend.mps[i] for i in 1:L])
    arr = Array(full, st.backend.sites...)
    perm = Tuple(st.phy_ram[L - p + 1] for p in 1:L)
    return vec(permutedims(arr, perm))
end

# "Unchanged" up to the gauge move of a rejected MPS gate (orthogonalize!
# re-factors tensors, which can shift amplitudes by an ulp); exact for SV.
function _ip_unchanged(st, before)
    all(isfinite, _ip_dense(st)) &&
        isapprox(_ip_dense(st), before; atol = 1e-14)
end

# c|0⟩ + s|1⟩ on one site, s real: Born probability s² for outcome 1.
_ip_tilt(s::Float64) = MatrixGate(ComplexF64[sqrt(1 - s^2) -s; s sqrt(1 - s^2)])

function _ip_error(f)
    try
        f()
        return nothing
    catch e
        return e
    end
end

# Rotation in the {|00⟩, |11⟩} plane (|01⟩, |10⟩ untouched): U|00⟩ = 0.8|00⟩ + 0.6|11⟩.
const _IP_U_ROT = [0.8 0 0 -0.6; 0 1 0 0; 0 0 1 0; 0.6 0 0 0.8]

# Spin-1 analogue acting on the two product levels |0,0⟩ (index 1) and
# |2,2⟩ (index 9) of a two-site d=3 space: V|0,0⟩ = 0.8|0,0⟩ + 0.6|2,2⟩.
const _IP_V_ROT = let V = Matrix{Float64}(I, 9, 9)
    V[1, 1] = 0.8
    V[1, 9] = -0.6
    V[9, 1] = 0.6
    V[9, 9] = 0.8
    V
end

# A maxdim=1, cutoff=0 MPS after `n` applications of the rotation: the SVD
# keeps only the 0.8|00⟩ (resp. 0.8|0,0⟩) component each time, so the
# retained state stays exactly the initial product state while ‖ψ‖² decays
# to 0.64^n — the MPS backend does not renormalize after unitary gates.
# n = 80 gives ‖ψ‖² ≈ 3.1e-16 < POSTSELECTION_PROB_TOL.
function _ip_truncated(; site_type = "Qubit", n = 80)
    d = site_type == "Qubit" ? 2 : 3
    U = d == 2 ? _IP_U_ROT : _IP_V_ROT
    st = SimulationState(L = 2, bc = :open, backend = :mps, maxdim = 1, cutoff = 0.0,
        site_type = site_type, rng = _ip_rng(), log_events = true)
    initialize!(st, ProductState(binary_int = 0))
    for _ in 1:n
        apply!(st, MatrixGate(U; d = d), Sites([1, 2]))
    end
    return st
end

@testset "REGRESSION impossible_postselection" begin

    # =====================================================================
    # 1. Bug-report scenario: |00⟩, postselect site 1 onto |1⟩
    # =====================================================================
    @testset "Projection(1) on |00⟩ throws and leaves the state unchanged ($label)" for (label, kw) in _IP_PATHS
        st = _ip_state(kw)
        before = _ip_dense(st)

        err = _ip_error(() -> apply!(st, Projection(1), SingleSite(1)))
        @test err isa ArgumentError
        @test occursin("Projection(1)", err.msg)
        @test occursin("[1]", err.msg)
        @test occursin("zero Born probability", err.msg)
        @test occursin("1.0e-14", err.msg)

        # State untouched: same amplitudes, normalized, no NaN, still usable.
        @test _ip_unchanged(st, before)
        @test norm(_ip_dense(st)) ≈ 1.0
        @test born_probability(st, 1, 0) ≈ 1.0
        @test born_probability(st, 1, 1) ≈ 0.0 atol = 1e-15
        @test EntanglementEntropy(cut = 1)(st) ≈ 0.0 atol = 1e-12
        apply!(st, Hadamard(), SingleSite(1))           # subsequent gates still work
        @test born_probability(st, 1, 1) ≈ 0.5
        apply!(st, Projection(1), SingleSite(1))          # the same gate, now possible
        @test born_probability(st, 1, 1) ≈ 1.0
        @test norm(_ip_dense(st)) ≈ 1.0
    end

    # The same event through the Born-sampling path is NOT affected: on |0⟩
    # the sampled outcome is 0 with certainty, so Measure/Reset still apply.
    @testset "Measure/Reset on a deterministic site still apply ($label)" for (label, kw) in _IP_PATHS
        st = _ip_state(kw)
        apply!(st, Measure(:Z), SingleSite(1))
        apply!(st, Reset(), SingleSite(2))
        @test born_probability(st, 1, 0) ≈ 1.0
        @test born_probability(st, 2, 0) ≈ 1.0
    end

    # =====================================================================
    # 2. Threshold semantics: ‖Pψ‖² ≥ 1e-14 accepted, < 1e-14 rejected
    # =====================================================================
    @testset "1e-12 branch accepted, 1e-16 branch rejected ($label)" for (label, kw) in _IP_PATHS
        @test QuantumCircuitsMPS.POSTSELECTION_PROB_TOL == 1e-14

        # amplitude 1e-6 ⇒ probability 1e-12 > tol: accepted and renormalized
        st = _ip_state(kw)
        apply!(st, _ip_tilt(1e-6), SingleSite(1))
        @test born_probability(st, 1, 1) ≈ 1e-12 rtol = 1e-6
        apply!(st, Projection(1), SingleSite(1))
        @test born_probability(st, 1, 1) ≈ 1.0
        @test norm(_ip_dense(st)) ≈ 1.0

        # amplitude 1e-8 ⇒ probability 1e-16 < tol: rejected, state unchanged
        st = _ip_state(kw)
        apply!(st, _ip_tilt(1e-8), SingleSite(1))
        before = _ip_dense(st)
        err = _ip_error(() -> apply!(st, Projection(1), SingleSite(1)))
        @test err isa ArgumentError
        @test occursin("‖Pψ‖²/‖ψ‖² = ", err.msg)
        @test occursin("‖Pψ‖² = ", err.msg)
        @test occursin("‖ψ‖² = ", err.msg)
        @test _ip_unchanged(st, before)
    end

    # =====================================================================
    # 3. Two-site projective gates onto an empty sector
    # =====================================================================
    # |+1,+1⟩ (binary_int = 0 on S=1 sites: both at level 0 = m=+1) lies
    # entirely in the S=2, M=2 sector: the singlet projector annihilates it.
    @testset "SpinSectorProjection onto an empty sector ($label)" for (label, kw) in _IP_PATHS
        st = _ip_state(kw; site_type = "S=1")
        before = _ip_dense(st)
        @test born_probability(st, 1, 0) ≈ 1.0

        singlet = SpinSectorProjection(total_spin_projector(0))
        err = _ip_error(() -> apply!(st, singlet, Sites([1, 2])))
        @test err isa ArgumentError
        @test occursin("SpinSectorProjection", err.msg)
        @test occursin("[1, 2]", err.msg)
        @test _ip_unchanged(st, before)
        # The multi-site MPS path wrote nothing back: still a bond-dimension-1
        # product state with the same Born probabilities.
        @test born_probability(st, 1, 0) ≈ 1.0
        @test born_probability(st, 2, 0) ≈ 1.0

        # Projecting onto the sector the state lives in is a no-op (accepted).
        apply!(st, SpinSectorProjection(total_spin_projector(2)), Sites([1, 2]))
        @test _ip_dense(st) ≈ before
    end

    @testset "SpinSectorMeasurement onto empty sectors throws ArgumentError (MPS)" begin
        st = _ip_state((; backend = :mps, maxdim = 16); site_type = "S=1")
        before = _ip_dense(st)
        err = _ip_error(() -> apply!(st, SpinSectorMeasurement([0, 1]), Sites([1, 2])))
        @test err isa ArgumentError                     # was a bare ErrorException
        @test occursin("zero overlap", err.msg)
        @test occursin("[0, 1]", err.msg)
        @test _ip_unchanged(st, before)

        # A sector with weight is still sampled and postselected normally:
        # |Z0,Z0⟩ = √(2/3)|S=2⟩ − √(1/3)|S=0⟩ ⇒ P(S=0) = 1/3 > 0.
        st0 = _ip_state((; backend = :mps, maxdim = 16); site_type = "S=1",
            init = ProductState(spin_state = "Z0"))
        apply!(st0, SpinSectorMeasurement([0]), Sites([1, 2]))
        @test norm(_ip_dense(st0)) ≈ 1.0
        ram = [st0.phy_ram[1], st0.phy_ram[2]]
        @test QuantumCircuitsMPS.compute_two_site_born_probability(
            st0.backend.mps, total_spin_projector(0), ram, 3) ≈ 1.0
    end

    # =====================================================================
    # 4. Same contract through PBC MPS, spin-site Projection, and simulate!
    # =====================================================================
    @testset "periodic MPS names the physical site and stays unchanged" begin
        st = _ip_state((; backend = :mps, maxdim = 16); L = 4, bc = :periodic)
        @test st.phy_ram != collect(1:4)                 # folded basis: RAM ≠ physical
        before = _ip_dense(st)
        err = _ip_error(() -> apply!(st, Projection(1), SingleSite(3)))
        @test err isa ArgumentError
        @test occursin("site(s) [3]", err.msg)
        @test _ip_unchanged(st, before)
        @test norm(st.backend.mps) ≈ 1.0
        apply!(st, Projection(0), SingleSite(3))          # the possible branch is fine
        @test _ip_dense(st) ≈ before
    end

    @testset "spin-site Projection onto an unoccupied level ($label)" for (label, kw) in _IP_PATHS
        st = _ip_state(kw; site_type = "S=1", init = ProductState(spin_state = "Z0"))   # level 1
        before = _ip_dense(st)
        err = _ip_error(() -> apply!(st, Projection(2), SingleSite(1)))
        @test err isa ArgumentError
        @test occursin("Projection(2)", err.msg)
        @test _ip_unchanged(st, before)
        apply!(st, Projection(1), SingleSite(1))          # occupied level: accepted
        @test born_probability(st, 1, 1) ≈ 1.0
    end

    @testset "simulate! propagates the rejection ($label)" for (label, kw) in _IP_PATHS
        circuit = Circuit(L = 2, bc = :open) do c
            apply!(c, Projection(1), SingleSite(1))
        end
        st = _ip_state(kw)
        before = _ip_dense(st)
        @test_throws ArgumentError simulate!(circuit, st; n_steps = 1)
        @test _ip_unchanged(st, before)
    end

    # =====================================================================
    # 5. Truncated MPS: the guard compares a probability, not a norm
    # =====================================================================
    @testset "guard is scale-invariant and names a zero-norm input" begin
        check = QuantumCircuitsMPS._check_postselection
        tol = QuantumCircuitsMPS.POSTSELECTION_PROB_TOL
        # Same physics, input norms spanning 16 orders of magnitude.
        for n2 in (1.0, 1e-8, 1e-16)
            @test check(0.5 * n2, n2, Projection(0), [1]) === nothing      # p = 1/2
            @test check(n2, n2, Projection(0), [1]) === nothing            # p = 1
            @test check(1e-12 * n2, n2, Projection(1), [1]) === nothing    # p = 1e-12 ≥ tol
            err = _ip_error(() -> check(1e-16 * n2, n2, Projection(1), [1]))   # p = 1e-16 < tol
            @test err isa ArgumentError
            @test occursin("‖Pψ‖²/‖ψ‖² = ", err.msg)
            @test occursin(", ‖ψ‖² = $(n2))", err.msg)        # the input norm is reported
            @test occursin("zero Born probability", err.msg)
        end
        # The threshold applies to the ratio (inclusive), not to ‖Pψ‖².
        @test check(tol, 1.0, Projection(1), [1]) === nothing
        @test check(1e-20, 1e-20, Projection(1), [1]) === nothing
        @test _ip_error(() -> check(0.0, 1e-16, Projection(1), [1])) isa ArgumentError
        # Zero-norm input: no probability is defined, distinct message, no NaN leak.
        err = _ip_error(() -> check(0.0, 0.0, Projection(0), [1]))
        @test err isa ArgumentError
        @test occursin("zero norm", err.msg)
        @test !occursin("NaN", err.msg)
    end

    # ‖ψ‖² ≈ 3.1e-16 while the retained state is exactly |00⟩: the raw
    # projected norm is below the threshold for the certain outcome, the
    # Born probability is one.
    @testset "truncated MPS: a certain projection is accepted" begin
        st = _ip_truncated()
        n2 = norm(st.backend.mps)^2
        @test n2 ≈ 0.64^80 rtol = 1e-6
        @test n2 < QuantumCircuitsMPS.POSTSELECTION_PROB_TOL
        @test born_probability(st, 1, 0) ≈ 1.0
        @test born_probability(st, 2, 0) ≈ 1.0

        apply!(st, Projection(0), SingleSite(1))      # used to throw "zero Born probability"
        @test norm(st.backend.mps) ≈ 1.0              # renormalized, as after any projective gate
        @test abs2(_ip_dense(st)[1]) ≈ 1.0            # still |00⟩
        @test born_probability(st, 1, 0) ≈ 1.0
        @test born_probability(st, 2, 0) ≈ 1.0
        apply!(st, Projection(0), SingleSite(2))      # and again on a normalized state
        @test abs2(_ip_dense(st)[1]) ≈ 1.0

        # The impossible branch is still impossible: ‖Pψ‖²/‖ψ‖² = 0, whatever ‖ψ‖².
        st = _ip_truncated()
        before = _ip_dense(st)
        @test born_probability(st, 1, 1) ≈ 0.0 atol = 1e-15
        err = _ip_error(() -> apply!(st, Projection(1), SingleSite(1)))
        @test err isa ArgumentError
        @test occursin("Projection(1)", err.msg)
        @test occursin("‖Pψ‖²/‖ψ‖² = ", err.msg)
        @test occursin("zero Born probability", err.msg)
        # The message names the input norm: "(‖Pψ‖² = 0.0, ‖ψ‖² = 3.12e-16)".
        reported = match(r", ‖ψ‖² = ([0-9.e+-]+)\)", err.msg)
        @test reported !== nothing && parse(Float64, reported.captures[1]) ≈ n2
        @test _ip_unchanged(st, before)
        @test norm(st.backend.mps)^2 ≈ n2            # not renormalized by a rejected gate
    end

    # Measure / Reset Born-sample with the (norm-independent) born_probability
    # and then project through the same guard: the sampled outcome 0 is
    # certain and must apply, including inside simulate!.
    @testset "truncated MPS: Measure and Reset apply" begin
        st = _ip_truncated()
        apply!(st, Measure(:Z), SingleSite(1))
        @test norm(st.backend.mps) ≈ 1.0
        @test born_probability(st, 1, 0) ≈ 1.0
        outcomes = measurements(st)
        @test length(outcomes) == 1
        @test outcomes[1].sites == [1]
        @test outcomes[1].outcome == 0

        st = _ip_truncated()
        apply!(st, Reset(), SingleSite(2))
        @test norm(st.backend.mps) ≈ 1.0
        @test born_probability(st, 2, 0) ≈ 1.0

        circuit = Circuit(L = 2, bc = :open) do c
            for _ in 1:80
                apply!(c, MatrixGate(_IP_U_ROT), Sites([1, 2]))
            end
            apply!(c, Measure(:Z), AllSites())
        end
        st = SimulationState(L = 2, bc = :open, maxdim = 1, cutoff = 0.0,
            rng = _ip_rng(), log_events = true)
        initialize!(st, ProductState(binary_int = 0))
        simulate!(circuit, st; n_steps = 1)
        @test norm(st.backend.mps) ≈ 1.0
        @test length(measurements(st)) == 2
        @test all(m.outcome == 0 for m in measurements(st))
    end

    # Two-site projective gates on a truncated spin-1 MPS: |+1,+1⟩ lies
    # entirely in the S=2 sector, so projecting/measuring onto a sector set
    # containing S=2 is certain; a set without it is still impossible.
    @testset "truncated MPS: SpinSectorProjection / SpinSectorMeasurement apply" begin
        st = _ip_truncated(site_type = "S=1")
        n2 = norm(st.backend.mps)^2
        @test n2 ≈ 0.64^80 rtol = 1e-6
        @test n2 < QuantumCircuitsMPS.POSTSELECTION_PROB_TOL
        ram = [st.phy_ram[1], st.phy_ram[2]]
        # The sector probabilities are Born probabilities (relative to ‖ψ‖²).
        ps = [QuantumCircuitsMPS.compute_two_site_born_probability(
                  st.backend.mps, total_spin_projector(S), ram, 3) for S in 0:2]
        @test ps ≈ [0.0, 0.0, 1.0] atol = 1e-12

        apply!(st, SpinSectorMeasurement([0, 1, 2]), Sites([1, 2]))   # used to throw "zero overlap"
        @test norm(st.backend.mps) ≈ 1.0
        @test born_probability(st, 1, 0) ≈ 1.0
        @test born_probability(st, 2, 0) ≈ 1.0

        st = _ip_truncated(site_type = "S=1")
        apply!(st, SpinSectorProjection(total_spin_projector(2)), Sites([1, 2]))
        @test norm(st.backend.mps) ≈ 1.0
        @test born_probability(st, 1, 0) ≈ 1.0

        st = _ip_truncated(site_type = "S=1")
        before = _ip_dense(st)
        err = _ip_error(() -> apply!(st, SpinSectorMeasurement([0, 1]), Sites([1, 2])))
        @test err isa ArgumentError
        @test occursin("zero overlap", err.msg)
        @test _ip_unchanged(st, before)
        singlet = SpinSectorProjection(total_spin_projector(0))
        err = _ip_error(() -> apply!(st, singlet, Sites([1, 2])))
        @test err isa ArgumentError
        @test occursin("‖Pψ‖²/‖ψ‖² = ", err.msg)
        @test _ip_unchanged(st, before)
    end
end
