# test/regression/audit_safeguards.jl
#
# === Accepted operations compute the advertised quantity or reject the
# request before the state changes ===
#
# Each group below pins a case that, in v0.5.6, returned a plausible-looking
# but wrong result instead of erroring:
#
#   1. DomainWall weights (L-j+1)^order were Int64 powers: order=32 at L=4
#      overflowed to 0 instead of 4^32 (MPS and state vector). Fixed — the
#      weights are now exact BigInt powers rounded to Float64.
#   2. Reset on a spin-1 site measured in level 2 left the site there (only
#      outcome 1 triggered the X flip). Now qubit-only: rejected before the
#      Born draw on any site with local_dim ≠ 2.
#   3. StringOrder on the state-vector backend used a qubit eigenvalue table
#      for every local_dim ≠ 3 (nonsense for spin-3/2); MPS died in an
#      ITensor internal error. Now both backends require site_type="S=1".
#   4. ProductState(binary_int=16) at L=4 built a 32-component state vector
#      and a 10×10 Gaussian covariance while MPS/Clifford kept |1000⟩. Now an
#      integer that needs more than L binary digits is rejected everywhere.
#   5. BornProbability(site, 2) on a qubit returned 0.0 (MPS/SV) or 0.5
#      (Clifford, undetermined branch) for a level that does not exist. Now
#      rejected on every backend.
#   6. A region with a repeated site (Sites([2,2]), apply!(s, g, [2,2]))
#      reached the backends; on Clifford it turned a maximally mixed reduced
#      state into a pure one. Now rejected by Sites and by execute!.
#   7. SpinSectorMeasurement([0,0,2]) was accepted and the sampler summed one
#      Born weight per listed entry, so the repeated sector was double-
#      weighted: on a spin-1 pair in |0,0⟩ it picked S=0 with probability
#      1/2 instead of 1/3. Now rejected by the constructor.

using Test
using QuantumCircuitsMPS

# --- helpers (file-local, `_as_` prefixed: runtests.jl shares one scope) ---

_as_seeds() = (gates_spacetime = 3, gates_realization = 5, born_measurement = 7)
_as_rng() = RNGRegistry(; _as_seeds()...)

# Run `f()` and return the thrown exception (or `nothing` if it returned).
function _as_caught(f)
    try
        f()
        return nothing
    catch e
        return e
    end
end

@testset "Audit safeguards: no silent wrong results" begin

    # ------------------------------------------------------------------
    # 1. DomainWall: exact weights, no Int64 overflow
    # ------------------------------------------------------------------
    @testset "DomainWall(order=32) on |1000⟩ is 4^32, not 0" begin
        L = 4
        exact = Float64(big(4)^32)   # 1.8446744073709552e19
        for backend in (:mps, :statevector)
            s = make_backend_state(backend, L; binary_int = 8, seeds = _as_seeds())  # |1000⟩
            # Scanning from i1=1 the first "1" is at position 1: weight L^order
            @test DomainWall(order = 32)(s, 1) ≈ exact
            @test DomainWall(order = 1)(s, 1) ≈ 4.0
            # Scanning from i1=2 (sites 2,3,4,1) it is at position 4: weight 1^order
            @test DomainWall(order = 32)(s, 2) ≈ 1.0
        end
    end

    # ------------------------------------------------------------------
    # 2. Reset is qubit-only
    # ------------------------------------------------------------------
    @testset "Reset rejected on non-qubit sites; state and RNG untouched" begin
        for backend in (:mps, :statevector)
            s = SimulationState(L = 2, bc = :open, site_type = "S=1", backend = backend,
                rng = _as_rng())
            initialize!(s, ProductState(spin_state = "Dn"))   # level 2 on every site
            rng_before = copy(get_rng(s.rng_registry, :born_measurement))

            err = _as_caught(() -> apply!(s, Reset(), SingleSite(1)))
            @test err isa ArgumentError
            @test occursin("Reset", err.msg)
            @test occursin("local_dim=3", err.msg)
            @test occursin("S=1", err.msg)

            # Nothing happened: still |Dn⟩, and no :born_measurement draw was consumed
            @test BornProbability(1, 2)(s) ≈ 1.0
            @test rand(copy(get_rng(s.rng_registry, :born_measurement))) ==
                  rand(copy(rng_before))

            # Same via the explicit site-vector path
            @test_throws ArgumentError apply!(s, Reset(), [1])
            @test BornProbability(1, 2)(s) ≈ 1.0
        end

        # Higher spin and a d=3 qudit are rejected the same way
        for (st, d) in (("S=3/2", 4), ("Qudit", 3))
            s = SimulationState(
                L = 2, bc = :open, site_type = st, local_dim = d, rng = _as_rng())
            initialize!(s, ProductState(binary_int = 0))
            err = _as_caught(() -> apply!(s, Reset(), SingleSite(1)))
            @test err isa ArgumentError
            @test occursin("local_dim=$d", err.msg)
        end

        # Qubits are unaffected: |11⟩ → Reset site 1 → |01⟩
        for backend in (:mps, :statevector, :clifford)
            s = make_backend_state(backend, 2; binary_int = 3, seeds = _as_seeds())
            apply!(s, Reset(), SingleSite(1))
            @test BornProbability(1, 0)(s) ≈ 1.0
            @test BornProbability(2, 1)(s) ≈ 1.0
        end
    end

    # ------------------------------------------------------------------
    # 3. StringOrder is spin-1 only
    # ------------------------------------------------------------------
    @testset "StringOrder rejected outside site_type=\"S=1\" on MPS and SV" begin
        for backend in (:mps, :statevector)
            # Qubits (the state-vector method used to evaluate a qubit table)
            sq = make_backend_state(backend, 4; seeds = _as_seeds())
            err = _as_caught(() -> StringOrder(1, 4)(sq))
            @test err isa ArgumentError
            @test occursin("S=1", err.msg)
            @test occursin("Qubit", err.msg)

            # Spin-3/2, all |Up⟩: the state-vector method returned +1 here
            s32 = SimulationState(
                L = 6, bc = :open, site_type = "S=3/2", backend = backend,
                rng = _as_rng())
            initialize!(s32, ProductState(spin_state = "Up"))
            @test_throws ArgumentError StringOrder(1, 4)(s32)
            @test_throws ArgumentError StringOrder(1, 5, order = 2)(s32)

            # A d=3 qudit has the right dimension but no spin operators
            sq3 = SimulationState(L = 4, bc = :open, site_type = "Qudit", local_dim = 3,
                backend = backend, rng = _as_rng())
            initialize!(sq3, ProductState(binary_int = 0))
            @test_throws ArgumentError StringOrder(1, 4)(sq3)

            # Spin-1 still evaluates: |Up Up Up Up⟩ → (+1)·(−1)·(−1)·(+1) = +1,
            # |Z0 …⟩ → Sz = 0 at the endpoints
            s1 = SimulationState(L = 4, bc = :open, site_type = "S=1", backend = backend,
                rng = _as_rng())
            initialize!(s1, ProductState(spin_state = "Up"))
            @test StringOrder(1, 4)(s1) ≈ 1.0
            initialize!(s1, ProductState(spin_state = "Z0"))
            @test StringOrder(1, 4)(s1) ≈ 0.0 atol = 1e-12
        end
    end

    # ------------------------------------------------------------------
    # 4. ProductState(binary_int) must fit in L binary digits
    # ------------------------------------------------------------------
    @testset "Oversized binary_int rejected identically on all four backends" begin
        L = 4
        for backend in (:mps, :statevector, :clifford, :gaussian)
            s = SimulationState(L = L, bc = :open, backend = backend, rng = _as_rng())
            for bad in (16, 17, 2^10)
                err = _as_caught(() -> initialize!(s, ProductState(binary_int = bad)))
                @test err isa ArgumentError
                @test occursin("binary_int=$bad", err.msg)
                @test occursin("2^$L - 1 = 15", err.msg)
            end
            # The largest value that fits is accepted and prepares |1111⟩
            initialize!(s, ProductState(binary_int = 15))
            @test all(BornProbability(i, 1)(s) ≈ 1.0 for i in 1:L)
            initialize!(s, ProductState(binary_int = 0))
            @test all(BornProbability(i, 0)(s) ≈ 1.0 for i in 1:L)
        end
        # The dense representations have the advertised size for L sites
        sv = make_backend_state(:statevector, L; binary_int = 15, seeds = _as_seeds())
        @test length(sv.backend.ψ) == 2^L
        g = make_backend_state(:gaussian, L; binary_int = 15, seeds = _as_seeds())
        @test size(g.backend.corr) == (2L, 2L)
    end

    # ------------------------------------------------------------------
    # 5. Born probability of a nonexistent level
    # ------------------------------------------------------------------
    @testset "BornProbability rejects levels ≥ local_dim on every backend" begin
        # Qubits on all four backends: level 2 does not exist
        for backend in (:mps, :statevector, :clifford, :gaussian)
            s = make_backend_state(backend, 2; seeds = _as_seeds())
            err = _as_caught(() -> BornProbability(1, 2)(s))
            @test err isa ArgumentError
            @test occursin("outcome 2", err.msg)
            @test occursin("local_dim=2", err.msg)
            @test BornProbability(1, 0)(s) ≈ 1.0
            @test BornProbability(1, 1)(s) ≈ 0.0 atol = 1e-12
        end

        # The reported Clifford case: |+⟩ gave [0.5, 0.5, 0.5] for levels 0, 1, 2
        cs = make_backend_state(:clifford, 2; seeds = _as_seeds())
        apply!(cs, Hadamard(), SingleSite(1))
        @test BornProbability(1, 0)(cs) == 0.5
        @test BornProbability(1, 1)(cs) == 0.5
        @test_throws ArgumentError BornProbability(1, 2)(cs)
        @test_throws ArgumentError born_probability(cs, 1, 2)   # direct call too

        # Spin-1: levels 0..2 exist, level 3 does not
        for backend in (:mps, :statevector)
            s = SimulationState(L = 2, bc = :open, site_type = "S=1", backend = backend,
                rng = _as_rng())
            initialize!(s, ProductState(spin_state = "Dn"))
            @test BornProbability(1, 2)(s) ≈ 1.0
            @test_throws ArgumentError BornProbability(1, 3)(s)
        end
    end

    # ------------------------------------------------------------------
    # 6. Repeated sites in one region
    # ------------------------------------------------------------------
    @testset "Repeated sites rejected by Sites and by execute!" begin
        @test_throws ArgumentError Sites([2, 2])
        @test_throws ArgumentError Sites([1, 2, 1])
        @test Sites([2, 1]).sites == [2, 1]   # distinct sites keep their order

        # Bell pair; a "unitary" on Sites([2,2]) used to purify site 2's reduced state
        for backend in (:mps, :statevector, :clifford)
            s = make_backend_state(backend, 2; seeds = _as_seeds())
            apply!(s, Hadamard(), SingleSite(1))
            apply!(s, CNOT(), [1, 2])
            ee_before = EntanglementEntropy(cut = 1)(s)
            @test ee_before ≈ 1.0 atol = 1e-8

            err = _as_caught(() -> apply!(s, RandomClifford(), [2, 2]))
            @test err isa ArgumentError
            @test occursin("repeated site", err.msg)
            @test occursin("[2, 2]", err.msg)
            @test EntanglementEntropy(cut = 1)(s) ≈ ee_before atol = 1e-8

            # Other two-site gates take the same path
            @test_throws ArgumentError apply!(s, CNOT(), [1, 1])
            @test EntanglementEntropy(cut = 1)(s) ≈ ee_before atol = 1e-8
        end
    end

    # ------------------------------------------------------------------
    # 7. Repeated sectors in SpinSectorMeasurement
    # ------------------------------------------------------------------
    @testset "SpinSectorMeasurement rejects repeated sectors" begin
        for bad in ([0, 0, 2], [1, 1], [2, 0, 2])
            err = _as_caught(() -> SpinSectorMeasurement(bad))
            @test err isa ArgumentError
            @test occursin("distinct", err.msg)
            @test occursin(string(bad), err.msg)
        end
        @test SpinSectorMeasurement([2, 0]).sectors == [2, 0]   # distinct sectors keep their order
        @test SpinSectorMeasurement().sectors == [0, 1, 2]

        # The distribution the duplicate used to distort: |Z0,Z0⟩ = √(2/3)|S=2⟩ − √(1/3)|S=0⟩,
        # so over the sector set {0,2} the Born weights are [1/3, 2/3] (summing to 1);
        # [0,0,2] normalized [1/3, 1/3, 2/3] by 4/3 and gave S=0 half the time.
        s = SimulationState(L = 2, bc = :open, site_type = "S=1", rng = _as_rng())
        initialize!(s, ProductState(spin_state = "Z0"))
        ram = [s.phy_ram[1], s.phy_ram[2]]
        ps = [QuantumCircuitsMPS.compute_two_site_born_probability(
                  s.backend.mps, total_spin_projector(S), ram, 3) for S in (0, 2)]
        @test ps ≈ [1 / 3, 2 / 3] atol = 1e-12
        @test sum(ps) ≈ 1.0 atol = 1e-12
    end
end
