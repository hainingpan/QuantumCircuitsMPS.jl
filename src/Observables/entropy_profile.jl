# === Entanglement-Entropy Profile Observable ===
#
# S(x) for every cut x ∈ 1:L−1, as a Vector{Float64} — a composition of L−1
# EntanglementEntropy evaluations, so it inherits the per-cut entropy's
# per-backend dispatch (MPS, state vector, Clifford, Gaussian) with no
# backend-specific code of its own: any backend implementing the bipartition
# `EntanglementEntropy` — the fermionic Gaussian backend included — gets a
# profile for free. Vector-valued recording relies on the track!/record!
# storage-widening contract (see `track!`).

"""
    EntropyProfile(; renyi_index=1, threshold=1e-16, base=ℯ)

Entanglement-entropy profile: the vector `[S(cut=x) for x in 1:L-1]` of
bipartite entropies at every cut, computed by the existing per-cut
`EntanglementEntropy` on each backend.

# Arguments
- `renyi_index::Real=1`: Rényi index for all cuts (1 = von Neumann). Accepts
  any `Real`, normalized to `Float64` at construction; the normalized value
  must be finite and `> 0` (so a finite `BigFloat("1e400")`, which normalizes
  to `Inf`, is rejected, as is `Bool`). Mirrors `EntanglementEntropy`, which
  each per-cut evaluation reconstructs.
- `threshold::Float64=1e-16`: singular-value floor (see `EntanglementEntropy`)
- `base::Real=ℯ`: logarithm base (default natural log — NB:
  `EntanglementEntropy` itself defaults to `base=2`; pass `base=2` for bits)

# Backend cost
- MPS: O(L) orthogonalized MPS copies — O(L²·χ³) total
- StateVector: O(L) dense reshapes + SVDs
- Clifford: O(L) tableau copies + GF(2)-rank computations
- Gaussian: O(L) covariance-submatrix eigendecompositions — O(L⁴) total
  (real `renyi_index`, inherited from `EntanglementEntropy` on that backend)

# PBC caveat (cross-backend semantics)
On the MPS backend under `bc=:periodic`, each `cut` is the RAM bond index of
the FOLDED-PBC MPS (`src/Observables/entanglement.jl`), NOT the physical
prefix bipartition `{1..cut}` used by the state-vector, Clifford and Gaussian
backends (only `cut = L÷2` is fold-aligned). A periodic-BC MPS profile is
therefore in RAM-bond coordinates and is NOT directly comparable to the other
backends' physical-cut profiles. Cross-backend profile comparisons must use
`bc=:open`, where all four backends agree on the physical bipartition.

# Recording
Returns a `Vector{Float64}` (one entry per cut). When tracked, each record
point appends the whole vector as ONE entry; the observable storage is
transparently widened from `Vector{Float64}` to `Vector{Any}` at the first
record (see `track!`).

# Examples
```julia
ep = EntropyProfile(; base=2)
profile = ep(state)                 # Vector{Float64} of length L-1
track!(state, :Sx => EntropyProfile())
```
"""
struct EntropyProfile <: AbstractObservable
    renyi_index::Float64
    threshold::Float64
    base::Float64

    function EntropyProfile(; renyi_index::Real = 1, threshold::Float64 = 1e-16,
            base::Real = ℯ)
        # NORMALIZE THEN VALIDATE, matching `_ee_check_common` (each per-cut
        # evaluation reconstructs an `EntanglementEntropy`, so the two
        # contracts must not diverge): Bool first, then Float64 conversion,
        # then finite-and-positive ON THE CONVERTED value.
        renyi_index isa Bool &&
            throw(ArgumentError("EntropyProfile renyi_index must be a number, not Bool"))
        local n64::Float64
        try
            n64 = Float64(renyi_index)
        catch err
            throw(ArgumentError(
                "EntropyProfile renyi_index must be convertible to Float64; got " *
                "$(typeof(renyi_index)) value $renyi_index ($(sprint(showerror, err)))"))
        end
        isfinite(n64) && n64 > 0 ||
            throw(ArgumentError(
                "EntropyProfile renyi_index must normalize to a finite Float64 > 0; " *
                "got $renyi_index, which normalizes to $n64"))
        threshold > 0 || throw(ArgumentError("EntropyProfile threshold must be > 0"))
        base > 0 || throw(ArgumentError("EntropyProfile base must be > 0"))
        new(n64, threshold, Float64(base))
    end
end

"""
    (ep::EntropyProfile)(state::SimulationState) -> Vector{Float64}

Evaluate `EntanglementEntropy(cut=x, ...)` for every `x in 1:L-1`, on
whatever backend `state` uses. Requires L >= 2 (a single site has no cut).
"""
function (ep::EntropyProfile)(state)
    state.L >= 2 ||
        throw(ArgumentError("EntropyProfile requires L >= 2 (no cut exists at L=$(state.L))"))
    return [EntanglementEntropy(cut = x, renyi_index = ep.renyi_index,
                threshold = ep.threshold, base = ep.base)(state)
            for x in 1:(state.L - 1)]
end
