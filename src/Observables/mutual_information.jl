# === Mutual-Information Observable ===
#
# I(A:B) = S(A) + S(B) - S(A∪B) for two CONTIGUOUS, DISJOINT site regions.
#
# Backend implementations:
#   - MPS (this file): reduced density matrices of arbitrary site subsets via
#     ITensor network contraction (left/right environments collapse to
#     identity through orthogonalization), eigenvalues -> entropy. Cost for
#     the joint RDM scales as χ²·d^(|A|+|B|) — a size guard rejects oversized
#     regions with an informative error.
#   - StateVector (src/StateVector/mutual_information.jl): exact subset
#     partial trace via grouped reshape + svdvals (dense, L ≲ 20).
#   - Clifford (src/Clifford/mutual_information.jl): stabilizer subsystem
#     entropies for arbitrary site subsets via QuantumClifford's GF(2)
#     rank routine (poly-time).
#
# Region semantics are PHYSICAL sites on every backend (mapped through
# `phy_ram` internally where needed), so — unlike `EntanglementEntropy`'s
# PBC `cut` (a RAM bond index on the MPS backend) — MutualInformation is
# cross-backend unambiguous under both open and periodic boundary conditions.

using ITensors
using ITensorMPS
using LinearAlgebra: Hermitian, eigvals

"""
    MutualInformation(regionA, regionB; renyi_index=1, threshold=1e-16, base=ℯ)

Mutual information I(A:B) = S(A) + S(B) - S(A∪B) between two site regions.

Each region must be a CONTIGUOUS, non-empty range of physical sites (a
`UnitRange` like `2:4`, a single `Int`, or a vector of consecutive integers),
and the two regions must be DISJOINT. Regions refer to physical sites on all
backends and under all boundary conditions.

# Arguments
- `regionA`, `regionB`: the two site regions (contiguous, disjoint)
- `renyi_index::Int=1`: entropy index used for all three terms
  - `renyi_index=1`: von Neumann entropies (default)
  - `renyi_index=n≥2`: Rényi-n entropies. NOTE: the Rényi "mutual
    information" Iₙ = Sₙ(A)+Sₙ(B)−Sₙ(A∪B) is NOT guaranteed non-negative
    for n≠1 — it is a commonly used diagnostic, not a proper mutual
    information. Documented, not forbidden.
- `threshold::Float64=1e-16`: singular-value floor (probabilities are clamped
  at `threshold^2` before taking logs), mirroring `EntanglementEntropy`
- `base::Real=ℯ`: logarithm base (default natural log, so a Bell pair gives
  I = 2·log(2) ≈ 1.386; use `base=2` for bits)

# Backend cost
- MPS: S(A∪B) for disjoint A, B requires a two-block reduced density matrix,
  contracted with cost/memory ~ χ²·d^(|A|+|B|) (χ = bond dimension). A size
  guard throws an informative `ArgumentError` when d^(|A|+|B|) > 256
  (e.g. more than 8 qubits combined).
- StateVector: exact dense partial trace — practical for L ≲ 20 only
  (memory/time scale as d^L).
- Clifford: poly-time GF(2)-rank stabilizer entropies; every Rényi index
  gives the same value (flat entanglement spectrum).

# Properties (analytic anchors)
- Product state: I = 0
- Pure global state with B = complement(A): I = 2·S(A)
- Bell pair, A = {1}, B = {2}: I = 2·log(2)
- GHZ(4), A = {1}, B = {4}: I = log(2)

# Examples
```julia
mi = MutualInformation(1:2, 5:6)            # blocks {1,2} and {5,6}
mi = MutualInformation(1, 4; base=2)        # single sites, result in bits
value = mi(state)
track!(state, :I => MutualInformation(1, 4))
```
"""
struct MutualInformation <: AbstractObservable
    regionA::UnitRange{Int}
    regionB::UnitRange{Int}
    renyi_index::Int
    threshold::Float64
    base::Float64

    function MutualInformation(regionA, regionB; renyi_index::Int = 1,
            threshold::Float64 = 1e-16, base::Real = ℯ)
        A = _mi_contiguous_region(regionA, "regionA")
        B = _mi_contiguous_region(regionB, "regionB")
        isempty(intersect(A, B)) ||
            throw(ArgumentError(
                "MutualInformation regions must be disjoint; regionA=$A and regionB=$B " *
                "overlap at sites $(intersect(A, B))"))
        renyi_index >= 1 ||
            throw(ArgumentError("MutualInformation renyi_index must be >= 1"))
        threshold > 0 || throw(ArgumentError("MutualInformation threshold must be > 0"))
        base > 0 || throw(ArgumentError("MutualInformation base must be > 0"))
        new(A, B, renyi_index, threshold, Float64(base))
    end
end

"""
    _mi_contiguous_region(r, which::String) -> UnitRange{Int}

Normalize a region spec (Int, range, or vector of integers) into a
`UnitRange{Int}`, throwing an informative `ArgumentError` unless it is a
non-empty, positive, strictly contiguous ascending set of sites.
"""
function _mi_contiguous_region(r, which::String)
    v = r isa Integer ? [Int(r)] : Int.(vec(collect(r)))
    isempty(v) &&
        throw(ArgumentError("MutualInformation $which must be non-empty"))
    allunique(v) ||
        throw(ArgumentError("MutualInformation $which has repeated sites: $v"))
    sort!(v)
    first(v) >= 1 ||
        throw(ArgumentError("MutualInformation $which sites must be positive, got $(first(v))"))
    v == collect(first(v):last(v)) ||
        throw(ArgumentError(
            "MutualInformation $which must be a CONTIGUOUS site range " *
            "(e.g. 2:4); got $v. Non-contiguous individual regions are not supported."))
    return first(v):last(v)
end

"""
    _validate_mutual_information(mi::MutualInformation, state) -> nothing

Shared evaluation-time validation for all backends: region sites within `1:L`.
"""
function _validate_mutual_information(mi::MutualInformation, state)
    for (which, region) in (("regionA", mi.regionA), ("regionB", mi.regionB))
        last(region) <= state.L ||
            throw(ArgumentError(
                "MutualInformation $which=$region exceeds system size L=$(state.L)"))
    end
    return nothing
end

"""
    _mi_entropy_from_probs(p, n, base, threshold) -> Float64

Entropy from a Schmidt/RDM probability spectrum `p` (need not be normalized;
tiny negative eigenvalues from numerical RDMs are clamped at `threshold^2`).
Mirrors `_von_neumann_entropy`'s formula cases exactly: n=1 gives von
Neumann −Σ p·log_b(p); n≥2 gives Rényi log_b(Σ pⁿ)/(1−n).
"""
function _mi_entropy_from_probs(p::Vector{Float64}, n::Int, base::Float64,
        threshold::Float64)
    q = max.(p, threshold^2)
    q ./= sum(q)
    log_fn = x -> log(x) / log(base)
    if n == 1
        return -sum(q .* log_fn.(q))
    else
        return log_fn(sum(q .^ n)) / (1 - n)
    end
end

# Combined-region size beyond which the MPS two-block RDM is rejected:
# the contraction carries intermediates of size up to χ²·d^(2·(|A|+|B|)),
# and the final RDM is a d^(|A|+|B|) × d^(|A|+|B|) dense matrix.
const _MI_MPS_MAX_JOINT_DIM = 256

"""
    _mps_subset_rdm_probs(state, phys_sites) -> Vector{Float64}

Eigenvalues of the reduced density matrix of the given PHYSICAL sites of an
MPS state. Sites are mapped to RAM positions via `phy_ram` (handling the
folded-PBC layout transparently); the RDM is built by sweeping the RAM span
`lo:hi`, keeping open (primed) site indices on the requested sites and
tracing all others. Left/right environments collapse to identity because the
MPS is orthogonalized to `lo` (sites < lo left-orthonormal, sites > lo
right-orthonormal).
"""
function _mps_subset_rdm_probs(state, phys_sites::Vector{Int})
    ram_sites = sort!([state.phy_ram[s] for s in phys_sites])
    ψ = orthogonalize(state.backend.mps, first(ram_sites))
    lo, hi = first(ram_sites), last(ram_sites)
    keep = Set(ram_sites)

    ρ = ITensor(1.0)
    if lo > 1
        l = linkind(ψ, lo - 1)
        ρ = delta(l, prime(l))
    end
    for j in lo:hi
        ρ = ρ * ψ[j]
        Tb = prime(dag(ψ[j]), "Link")
        if j in keep
            Tb = prime(Tb, "Site")
        end
        ρ = ρ * Tb
    end
    if hi < length(ψ)
        r = linkind(ψ, hi)
        ρ = ρ * delta(r, prime(r))
    end

    sinds = [siteind(ψ, j) for j in ram_sites]
    m = prod(dim.(sinds))
    M = reshape(Array(ρ, prime.(sinds)..., sinds...), m, m)
    return eigvals(Hermitian(M))
end

"""
    (mi::MutualInformation)(state::SimulationState) -> Float64

MPS implementation: S(A), S(B), and S(A∪B) are each computed from the
eigenvalues of the corresponding reduced density matrix, contracted directly
from the MPS (see `_mps_subset_rdm_probs`). The joint (two-block) RDM costs
~ χ²·d^(|A|+|B|); combined regions with d^(|A|+|B|) > $( _MI_MPS_MAX_JOINT_DIM)
are rejected with an informative error — use `backend=:statevector` for
larger regions on small systems.
"""
function (mi::MutualInformation)(state)
    _validate_mutual_information(mi, state)

    d = state.local_dim
    nA, nB = length(mi.regionA), length(mi.regionB)
    joint_dim = Float64(d)^(nA + nB)
    joint_dim <= _MI_MPS_MAX_JOINT_DIM ||
        throw(ArgumentError(
            "MutualInformation on the MPS backend requires d^(|A|+|B|) <= " *
            "$_MI_MPS_MAX_JOINT_DIM (got d=$d, |A|+|B|=$(nA + nB), " *
            "d^(|A|+|B|)=$(round(Int, joint_dim))): the two-block reduced density " *
            "matrix costs ~ chi^2 * d^(|A|+|B|) in time and memory. Use smaller " *
            "regions, or backend=:statevector for exact small-L computation."))

    SA = _mi_entropy_from_probs(_mps_subset_rdm_probs(state, collect(mi.regionA)),
        mi.renyi_index, mi.base, mi.threshold)
    SB = _mi_entropy_from_probs(_mps_subset_rdm_probs(state, collect(mi.regionB)),
        mi.renyi_index, mi.base, mi.threshold)
    SAB = _mi_entropy_from_probs(
        _mps_subset_rdm_probs(state, vcat(collect(mi.regionA), collect(mi.regionB))),
        mi.renyi_index, mi.base, mi.threshold)
    return SA + SB - SAB
end
