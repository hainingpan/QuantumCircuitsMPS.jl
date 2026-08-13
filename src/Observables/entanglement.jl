@doc raw"""
    EntanglementEntropy(; cut, renyi_index::Real=1, threshold::Float64=1e-16, base::Real=2)

Entanglement entropy observable.

`cut` selects between two forms via multiple dispatch on its TYPE, giving a
parametric observable `EntanglementEntropy{C}` with `C === Int` or
`C === Vector{Int}`:

- **Bipartition (`cut::Int`)** — entropy of the bipartition at `cut`
  (`1 <= cut < L`). Supported on ALL backends (MPS, state vector, Clifford,
  Gaussian). This is the historical form; its `cut` SEMANTICS are unchanged
  (the `renyi_index` contract is not — see below, it now accepts any real
  index that normalizes to a finite `Float64 > 0`).
- **Region (`cut::AbstractRange` or `cut::AbstractVector{<:Integer}`)** —
  entropy of the reduced density matrix of an arbitrary set of PHYSICAL
  sites. Supported on the state-vector, Clifford and Gaussian backends only;
  **the MPS backend throws an `ArgumentError`** (see below).

# Arguments
- `cut`: either
  - `cut::Int`: physical site where the bipartition cut is made (must satisfy
    `1 <= cut < L`; `cut < 1` throws at construction, `cut >= L` at call time), or
  - `cut::UnitRange`/`cut::Vector{Int}`: a region of physical sites. Range
    semantics are INCLUSIVE site sets: `cut=3:6` means sites `{3,4,5,6}`.
    The region is validated at construction (non-empty, no duplicates, all
    sites `>= 1`) and stored **sorted** as a `Vector{Int}` — entropy is
    permutation-invariant, so sorting also canonicalizes PBC-wrapped input
    such as `[L-1, L, 1, 2]`. Bounds against the system size (`max <= L`) and
    properness (`length < L`) are checked at CALL time, when `L` is known.
- `renyi_index::Real=1`: Rényi index for entropy. Accepts any `Real`,
  NORMALIZED TO `Float64` at construction; the normalized value must be finite
  and `> 0`. Stating the contract on the normalized value is deliberate: a
  finite `BigFloat("1e400")` normalizes to `Inf` and a finite
  `BigFloat("1e-400")` to `0.0`, so both are rejected even though each is a
  "finite real > 0" before conversion. `Bool` is rejected outright.
  - `renyi_index=1`: von Neumann entropy ``S_1 = -\sum_i \lambda_i \log(\lambda_i)`` (default)
  - `renyi_index=2`: Rényi-2 entropy ``S_2 = \log\!\big(\sum_i \lambda_i^2\big) / (1-2)``
  - `renyi_index=n`: Rényi-n entropy ``S_n = \log\!\big(\sum_i \lambda_i^n\big) / (1-n)`` for any real
    ``n \neq 1``. Indices within `1e-8` of 1 evaluate the von Neumann formula
    instead (its continuous limit; error O(1e-8)), and the general branch is
    evaluated in a scale-before-overflow log domain, so extreme indices such
    as `n = 2048` or `n = floatmax(Float64)` are finite and accurate rather
    than overflowing to `Inf`/`NaN`.
- `threshold::Float64=1e-16`: Minimum threshold for singular values (default: 1e-16)
- `base::Real=2`: Base of logarithm for entropy computation (default: 2 for bits)

!!! note "Hartley entropy (renyi_index=0) is NOT supported"
    Hartley entropy (`renyi_index=0`) measures ``\log_2(\text{Schmidt rank})``, but is not available via
    this interface because:
    - MPS compression retains singular values above a cutoff threshold (~1e-10)
    - Numerically, "zero" singular values are never truly zero in floating-point arithmetic
    - This makes `log(rank)` give `log(maxdim)` instead of `log(true_rank)`
    - Result is threshold-dependent and unreliable
    
    **Alternative**: Access MPS singular values directly via `orthogonalize!` + `svd`,
    then apply your own threshold to determine the Schmidt rank.

    The same mechanism degrades CONTINUOUSLY as ``n \to 0^+``, so small
    ``0 < n \ll 1`` is accepted but should be read with care: on the MPS and
    state-vector backends the probability FLOOR (`threshold^2` per clamped
    Schmidt value) dominates ``\sum p^n`` as ``n \to 0^+`` — a floor of `1e-32`
    contributes ``(1\text{e-32})^n``, i.e. ``\approx 6\text{e-4}`` at `n = 0.1` but ``\approx 0.5`` at
    `n = 0.01` — so the reported entropy becomes threshold-dependent long
    before `n` reaches 0. On the Gaussian backend there is no floor, but
    covariance-eigenvalue roundoff makes the ``n \to 0^+`` rank limit numerically
    sensitive in the same way. The Clifford backend is EXEMPT: its
    GF(2)-rank entropy is exact and independent of every accepted `n`
    (stabilizer entanglement spectra are flat).

# Implementation (MPS, `cut::Int`)
The entropy is computed by:
1. Converting the physical cut position to RAM ordering
2. Orthogonalizing the MPS at the cut site
3. Performing SVD to obtain Schmidt values
4. Computing the entropy from the Schmidt spectrum

!!! warning "The MPS backend does NOT support regions"
    MPS entanglement entropy comes from the SVD of a single bond adjacent to
    the orthogonality center, which is exactly a bipartition — an arbitrary
    site region has no such native representation. Evaluating a region
    observable on an `MPSBackend` state throws an `ArgumentError`; use
    `backend=:statevector`, `:clifford`, or `:gaussian` for region entropies.

# Example
```julia
ee = EntanglementEntropy(; cut=2, renyi_index=1)   # bipartition, all backends
entropy = ee(state)

ee_region = EntanglementEntropy(; cut=3:6)          # sites {3,4,5,6}, non-MPS
ee_region.cut                                       # [3, 4, 5, 6]
EntanglementEntropy(; cut=[8, 1, 2, 7]).cut         # [1, 2, 7, 8] (sorted)
```
"""
struct EntanglementEntropy{C <: Union{Int, Vector{Int}}} <: AbstractObservable
    cut::C
    renyi_index::Float64
    threshold::Float64
    base::Float64
end

"""
    EntanglementEntropy(; cut, renyi_index=1, threshold=1e-16, base=2)

Keyword constructor. Delegates to [`_ee_from_cut`](@ref), which dispatches on
the TYPE of `cut` to build either an `EntanglementEntropy{Int}` (bipartition)
or an `EntanglementEntropy{Vector{Int}}` (site region).
"""
function EntanglementEntropy(; cut, renyi_index::Real = 1,
        threshold::Float64 = 1e-16, base::Real = 2)
    return _ee_from_cut(cut, renyi_index, threshold, base)
end

"""
    _ee_check_common(renyi_index, threshold, base) -> Float64

Shared construction-time validation of the non-`cut` parameters, identical
for the bipartition and region forms. Returns the NORMALIZED `renyi_index`
(a `Float64`), which both callers store in the struct's `Float64` field.

`renyi_index` is NORMALIZED THEN VALIDATED, in that order:

1. `Bool` is rejected outright — `true`/`false` are `Real` in Julia but are
   not meaningful Rényi indices, and `Float64(true) == 1.0` would otherwise
   be silently accepted as von Neumann.
2. The value is converted to `Float64` (conversion failure is re-thrown as an
   `ArgumentError`, never a bare `InexactError`/`MethodError`).
3. The CONVERTED value must be finite and `> 0`.

Validating after normalization is what keeps the struct's `Float64` field
invariant honest for wide inputs: `BigFloat("1e400")` converts to `Inf` and
`BigFloat("1e-400")` to `0.0`, so both are rejected here instead of being
stored as a nonsense index. `n = 0` (Hartley) stays excluded.
"""
function _ee_check_common(renyi_index::Real, threshold::Float64, base::Real)
    renyi_index isa Bool &&
        throw(ArgumentError("EntanglementEntropy renyi_index must be a number, not Bool"))
    local n64::Float64
    try
        n64 = Float64(renyi_index)
    catch err
        throw(ArgumentError(
            "EntanglementEntropy renyi_index must be convertible to Float64; got " *
            "$(typeof(renyi_index)) value $renyi_index ($(sprint(showerror, err)))"))
    end
    isfinite(n64) && n64 > 0 ||
        throw(ArgumentError(
            "EntanglementEntropy renyi_index must normalize to a finite Float64 > 0 " *
            "(Hartley n=0 is not supported); got $renyi_index, which normalizes to $n64"))
    threshold > 0 || throw(ArgumentError("EntanglementEntropy threshold must be > 0"))
    base > 0 || throw(ArgumentError("EntanglementEntropy base must be > 0"))
    return n64
end

# Bipartition form: `cut::Integer` -> EntanglementEntropy{Int}.
# The CUT validation and defaults are EXACTLY the historical behavior (cut < 1
# throws at construction; cut >= L throws at call time in each backend method).
# `renyi_index` validation is deliberately NOT historical any more: it is
# normalized to `Float64` and required to be finite and > 0 (see
# `_ee_check_common`), widening the accepted set from integers >= 1 to any
# positive real while still excluding Hartley n = 0.
function _ee_from_cut(cut::Integer, renyi_index::Real, threshold::Float64, base::Real)
    cut >= 1 || throw(ArgumentError("EntanglementEntropy cut must be >= 1"))
    n64 = _ee_check_common(renyi_index, threshold, base)
    return EntanglementEntropy{Int}(Int(cut), n64, threshold, Float64(base))
end

# Region form: range or vector of integers -> EntanglementEntropy{Vector{Int}}.
# Stored sorted (entropy is permutation-invariant; sorting canonicalizes
# PBC-wrapped input like [L-1, L, 1, 2]).
function _ee_from_cut(cut::Union{AbstractRange{<:Integer}, AbstractVector{<:Integer}},
        renyi_index::Real, threshold::Float64, base::Real)
    region = collect(Int, cut)
    isempty(region) &&
        throw(ArgumentError(
            "EntanglementEntropy cut region must be non-empty; got $cut. Accepted: " *
            "an Int bipartition cut, or a non-empty duplicate-free collection of " *
            "positive physical sites (e.g. 3:6 or [1, 2, 7, 8])."))
    allunique(region) ||
        throw(ArgumentError("EntanglementEntropy cut region has repeated sites: $region"))
    minimum(region) >= 1 ||
        throw(ArgumentError(
            "EntanglementEntropy cut region sites must be positive, got " *
            "$(minimum(region)); sites are 1-based physical indices in 1:L"))
    sort!(region)
    n64 = _ee_check_common(renyi_index, threshold, base)
    return EntanglementEntropy{Vector{Int}}(region, n64, threshold, Float64(base))
end

# Anything else: informative error rather than a bare MethodError. The second
# argument is `::Real` (not `::Int`) so that a bad `cut` combined with a
# non-integer `renyi_index` still lands HERE and reports the cut problem,
# instead of falling off the method table as a MethodError.
function _ee_from_cut(cut, ::Real, ::Float64, ::Real)
    throw(ArgumentError(
        "EntanglementEntropy cut must be an Int (bipartition) or a collection of " *
        "integer physical sites (e.g. 3:6 or [1, 2, 7, 8]); got $(typeof(cut))"))
end

"""
    _ee_validate_region(region::Vector{Int}, L::Int) -> nothing

Call-time validation of a stored (sorted, duplicate-free, positive) region
against the system size `L`, shared by every region-capable backend method.

Throws an `ArgumentError` when

- any site exceeds `L` (`maximum(region) > L`), or
- the region covers the whole system (`length(region) >= L`) — a trivial
  bipartition with zero entropy, mirroring the bipartition path's
  `1 <= cut < L` call-time check.
"""
function _ee_validate_region(region::Vector{Int}, L::Int)
    maximum(region) <= L ||
        throw(ArgumentError(
            "EntanglementEntropy region $region exceeds system size L=$L; " *
            "region sites must satisfy 1 <= site <= L"))
    length(region) < L ||
        throw(ArgumentError(
            "EntanglementEntropy region must be a PROPER subset of the L=$L sites " *
            "(got $(length(region)) sites): the full system is a trivial bipartition, " *
            "mirroring the bipartition requirement 1 <= cut < L"))
    return nothing
end

"""
    (ee::EntanglementEntropy{Vector{Int}})(state::SimulationState{MPSBackend})

The MPS backend does NOT support site-region entanglement entropy — always
throws an `ArgumentError`. MPS entropy is read off the SVD of a single bond
adjacent to the orthogonality center, i.e. a bipartition specified by
`cut::Int`; an arbitrary region has no such native bond.
"""
function (ee::EntanglementEntropy{Vector{Int}})(state::SimulationState{MPSBackend})
    throw(ArgumentError(
        "EntanglementEntropy with a site region (cut=$(ee.cut)) is not supported on " *
        "the MPS backend: MPS entanglement entropy is obtained from the bond SVD at a " *
        "single orthogonality-center-adjacent cut, so only a bipartition cut::Int " *
        "(1 <= cut < L) is available. Use cut::Int here, or switch to " *
        "backend=:statevector, :clifford, or :gaussian for region-based entropy."))
end

# Callable struct interface
function (ee::EntanglementEntropy)(state)
    # Validate cut is in valid range
    1 <= ee.cut < state.L || throw(ArgumentError("cut must satisfy 1 <= cut < L"))

    # Determine RAM cut position based on boundary conditions
    # For periodic BC with folded MPS, the fold origin is configurable via
    # pbc_fold_start (default: L÷4+1, aligning the half-cut with the physical
    # midpoint). The cut parameter directly specifies the RAM bond index.
    # For open BC, ram_phy is identity so this also works correctly.
    ram_cut = ee.cut

    # Compute entropy using internal helper
    return _von_neumann_entropy(state.backend.mps, ram_cut; n = ee.renyi_index,
        threshold = ee.threshold, base = ee.base)
end

# === Rényi branch thresholds (shared by ALL THREE probability kernels) ===
#
# The three spectrum→entropy kernels — `_von_neumann_entropy` below, the
# state-vector bipartition kernel (src/StateVector/entanglement.jl) and
# `_mi_entropy_from_probs` (src/Observables/mutual_information.jl) — are
# deliberately SEPARATE implementations (each is fed a spectrum obtained a
# different way), but they must agree on WHERE the branches switch, or the
# same physical state would give different numbers through different code
# paths. Only these two thresholds are shared; the kernel bodies are not.
#
# `_RENYI_SHUNT` — half-width of the von Neumann shunt around n = 1. The
# `+ eps(1.0)` widening is REQUIRED, not cosmetic: the decimal literal
# `1.0 - 1e-8` sits at Float64 distance ≈ 1.0000000050e-8 from 1.0, which
# MISSES a bare `<= 1e-8` test; the general formula would then be entered at a
# δ so small that catastrophic cancellation returns NEGATIVE entropy (e.g.
# −1.1e−8 for p = [1e−16, 1 − 1e−16]).
const _RENYI_SHUNT = 1e-8 + eps(1.0)

# `_RENYI_NEAR1` — outer edge of the cancellation-safe `expm1`/`log1p` branch.
# The scale-safe log-domain form used beyond it is overflow-proof but NOT
# cancellation-proof just outside the shunt (on the normalized spectrum
# p = [prevfloat(1.0), 2^-53] at n = 1 − 1e-6 it returns ≈ −1.1e−10 where the
# truth is ≈ +3.8e−15).
const _RENYI_NEAR1 = 1e-4

@doc raw"""
    _renyi_scaled_tails(logs, n::Real) -> (t_n, s)

Rescaled tail sums of a log-probability vector, shared by the GENERAL-n branch
of all three entropy kernels (and by nothing else — no `n = 1` path calls it).

With `lmax = maximum(logs)` attained at index `imax`, returns

```math
t_n = \sum_{k \neq i_{\max}} \exp\big(n(\ell_k - \ell_{\max})\big) = \sum_{k \neq i_{\max}} (p_k/p_{\max})^n
```
```math
s = \sum_{k \neq i_{\max}} \exp(\ell_k - \ell_{\max}) = (\textstyle\sum p - p_{\max})/p_{\max}
```

Every exponent is `≤ 0`, so neither sum can overflow at ANY accepted `n`, and
both lie in `[0, length(logs) − 1]`.

The max index is located, and the sums accumulated, with PLAIN INTEGER
indexing on purpose. `logs` is not always a `Vector`: on the MPS path it is an
`NDTensors.DenseTensor` (from `diag(S)` of the bond SVD), for which
`eachindex` yields `CartesianIndex{1}` while `argmax` returns an `Int64` — so
the natural `for k in eachindex(logs) if k != argmax(logs)` filter silently
excludes NOTHING and leaves the maximum in the tail, inflating a flat rank-2
spectrum's Rényi entropy from `log 2` to `log 3`. Integer indexing is
consistent across both conventions.
"""
function _renyi_scaled_tails(logs, n::Real)
    m = length(logs)
    m == 0 && return (0.0, 0.0)
    imax = 1
    @inbounds for k in 2:m
        logs[k] > logs[imax] && (imax = k)
    end
    lmax = @inbounds logs[imax]
    t_n = 0.0
    s = 0.0
    @inbounds for k in 1:m
        k == imax && continue
        d = logs[k] - lmax          # ≤ 0, finite or -Inf
        t_n += exp(n * d)
        s += exp(d)
    end
    return (t_n, s)
end

@doc raw"""
    _von_neumann_entropy(mps::MPS, i::Int; n::Real=1, threshold::Float64=1e-16, base::Float64=2.0) -> Float64

Compute entanglement entropy at bond i of an MPS.

Arguments:
- mps: The MPS state
- i: The bond index (site index) where entropy is computed
- n: Rényi index (1=von Neumann, n=Rényi-n); any finite real > 0
- threshold: Minimum threshold for singular values to avoid log(0)
- base: Base of logarithm for entropy computation (default: 2.0 for bits)

Returns:
- Entanglement entropy value

The function:
1. Orthogonalizes the MPS to site i
2. Performs SVD on the tensor to extract Schmidt values
3. Computes probabilities from Schmidt values (squared)
4. Returns entropy based on Rényi index, in three branches of δ = n − 1:
   - `|δ| <= _RENYI_SHUNT`: von Neumann entropy ``S_1 = -\sum p \log_b(p)`` — the exact
     n = 1 expression, used as the continuous limit (error O(1e-8))
   - `_RENYI_SHUNT < |δ| <= _RENYI_NEAR1`: cancellation-safe near-1 form
   - `|δ| > _RENYI_NEAR1`: Rényi entropy ``S_n = \log_b\!\big(\sum p^n\big)/(1-n)``, evaluated in
     a scale-before-overflow log domain

Hartley entropy (n = 0) is NOT a case here: `EntanglementEntropy` rejects
`renyi_index <= 0` at construction (see `_ee_check_common`).
"""
function _von_neumann_entropy(
        mps::MPS,
        i::Int;
        n::Real = 1,
        threshold::Float64 = 1e-16,
        base::Float64 = 2.0
)
    # Orthogonalize MPS to site i
    mps_ = orthogonalize(mps, i)

    # Perform SVD on the link between site i and i+1
    # Extract singular values from the bond
    _, S = svd(mps_[i], (linkind(mps_, i),))

    # Get singular values and compute probabilities (squared for normalization)
    # Apply threshold to avoid numerical issues with log(0)
    singular_vals = diag(S)
    p = max.(singular_vals, threshold) .^ 2
    p ./= sum(p)   # renormalize after threshold replacement

    # Define log with specified base: log_b(x) = log(x) / log(b)
    log_fn = x -> log(x) / log(base)

    # Compute entropy based on Rényi index (three branches of δ = n − 1)
    δ = n - 1
    if abs(δ) <= _RENYI_SHUNT
        # von Neumann entropy: S₁ = -Σ p log_b(p)
        return -sum(p .* log_fn.(p))
    end
    isempty(p) && return 0.0
    if abs(δ) <= _RENYI_NEAR1
        # Cancellation-safe near-1 Rényi. Σ pⁿ = Σ p·p^δ = Σp + t where
        # t = Σ p·(p^δ − 1) and Σp = 1 for this normalized spectrum, so
        # Sₙ = log(1 + t)/(1 − n) = −log1p(t)/δ. expm1/log1p keep full
        # relative precision for the tiny δ·log(p) exponents here, which a
        # plain `sum(p .^ n)` would lose to cancellation against 1.
        t = sum(p .* expm1.(δ .* log.(p)))
        return -log1p(t) / δ / log(base)
    end
    # General real n: SCALE-BEFORE-OVERFLOW log domain. Rescaling by the
    # largest probability makes every exponent ≤ 0, so `exp` cannot overflow
    # at ANY accepted n (t_n ∈ [0, length(p)−1] even at n = floatmax). The
    # form is also NORMALIZATION-AWARE: the log(pmax) terms of the numerator
    # and of the spectrum's own normalization cancel algebraically, so a
    # sub-ulp normalization deficit is not amplified by 1/(1−n), and log1p
    # preserves sub-ulp tails that log(sum(1 + tiny)) would destroy.
    # Direct powers (underflow at n = 2048) and un-scaled logsumexp (every
    # element is already −Inf at n = floatmax) both fail here.
    t_n, s = _renyi_scaled_tails(log.(p), n)
    return (log1p(t_n) / (1 - n) - (n / (1 - n)) * log1p(s)) / log(base)
end
