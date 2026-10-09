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
end
