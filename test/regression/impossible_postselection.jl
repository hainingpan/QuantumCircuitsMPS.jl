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
# now throws an ArgumentError naming the gate, the physical sites and
# ‖Pψ‖², and — on both backends and both state-vector engines — leaves the
# state exactly as it was. The threshold is the shared
# POSTSELECTION_PROB_TOL = 1e-14 (also used by SpinSectorMeasurement).
#
# Test groups:
#   1. The bug-report scenario on MPS, SV :builtin and SV :optimized.
#   2. The threshold: a 1e-12 branch is accepted and normalized, a 1e-16
#      branch is rejected, on every backend/engine.
#   3. Two-site projective gates (SpinSectorProjection / SpinSectorMeasurement)
#      onto an empty sector: rejected with the MPS block never written back.
#   4. Periodic MPS (non-identity phy_ram), spin-site Projection, and the
#      circuit engine all surface the same error.

using Test
using LinearAlgebra: norm
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
        @test occursin("‖Pψ‖² = ", err.msg)
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
end
