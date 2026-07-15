import QuantumClifford: MixedDestabilizer

"""
    AbstractBackend

Abstract base type for all simulation backends. A backend is the mutable
struct that owns the numerical representation of the quantum state; the
user-facing [`SimulationState`](@ref) is parametrically typed on it
(`SimulationState{B<:AbstractBackend}`), so backend selection is pure
multiple dispatch.

Concrete backends: `MPSBackend` (ITensor MPS), `StateVectorBackend`
(dense `Vector{ComplexF64}`), `CliffordBackend` (QuantumClifford.jl
stabilizer tableau).

A new backend must implement, for `SimulationState{MyBackend}`:

- `initialize!(state, init)` for each supported `AbstractInitialState`
- `_apply_single!(state, gate, phy_sites)` — the gate-application primitive
  (either one generic method that resolves gates to matrices/operators, or
  per-gate methods plus an informative-`ArgumentError` fallback)
- `born_probability(state, site, outcome)` — required by the default
  measurement path and the `BornProbability` observable
- `_measure_single_site!(state, site)` — only if the default
  (Born-sample + `Projection`) implementation in `src/Core/apply.jl` cannot
  work for the representation
- a method (or an explicit `ArgumentError` rejection) for every exported
  observable callable — unhandled observables fall through to MPS-assumed
  generics and crash with a `FieldError`

The full contract — required fields, method tables per backend, RNG-stream
expectations, and indexing conventions — is documented in
`docs/src/devdocs/backend_interface.md`.
"""
abstract type AbstractBackend end

"""
MPS-based backend: holds the underlying matrix product state, site indices,
and truncation parameters (SVD cutoff, maximum bond dimension).
"""
mutable struct MPSBackend <: AbstractBackend
    mps::Union{MPS, Nothing}
    sites::Vector{Index}
    cutoff::Float64
    maxdim::Int
end

"""
State-vector backend: holds the full statevector as a dense complex vector.

`engine` selects the gate-application algorithm used by `_apply_single!`:
- `:builtin` (default): Tier 1, reshape + permutedims + matmul (see
  `apply_gate_sv!` in `src/StateVector/StateVector.jl`). Ground truth.
- `:optimized`: Tier 2, hand-written stride-loop kernel (see
  `apply_gate_sv_optimized!` in `src/StateVector/optimized.jl`). Faster,
  numerically verified to match Tier 1 bitwise/to <1e-13.
"""
mutable struct StateVectorBackend <: AbstractBackend
    ψ::Union{Vector{ComplexF64}, Nothing}
    engine::Symbol
end

"""
Clifford (stabilizer) backend: holds a QuantumClifford.jl stabilizer tableau.

Uses `MixedDestabilizer` (tracks both stabilizer and destabilizer generators),
which enables efficient O(n²) measurement via `project!`.
"""
mutable struct CliffordBackend <: AbstractBackend
    tableau::Union{MixedDestabilizer, Nothing}
end

"""
Gaussian (free-fermion) backend: holds a Majorana covariance matrix Γ for
Gaussian-state simulation of fermionic circuits.

`corr` is the `2L×2L` real antisymmetric Majorana covariance matrix
`Γ[a,b] = (i/2)⟨[γ_a, γ_b]⟩`, satisfying the invariant `Γ² = -I` for a pure
Gaussian state. Mode `i` (1-indexed, `1 <= i <= L`) maps to Majorana indices
`(2i−1, 2i)`.

`scratch` is a preallocated `2L×2L` buffer of the same size as `corr`, used
by the Gaussian gate-application kernel to avoid per-gate allocation.

`purify_tol` is the threshold on `‖Γ² + I‖` (or an equivalent purity
diagnostic) above which the backend re-purifies `corr` to correct
floating-point drift from repeated updates (default `1e-10`).

`majoranas_per_site` selects the SITE GRANULARITY (set from `site_type` in
the `SimulationState` constructor, `src/State/State.jl`):
- `2` (default, `site_type="Qubit"`): each site is one fermionic mode
  carrying the Majorana pair `(2i−1, 2i)`; Γ is `2L×2L`.
- `1` (`site_type="Majorana"`): each site IS one Majorana mode (index `i`);
  Γ is `L×L` and `L` must be even (a pure Gaussian state has an even number
  of Majoranas). Same covariance-matrix machinery, same gate types — only
  the site→Majorana index mapping (`site_majoranas`) changes.
"""
mutable struct GaussianBackend <: AbstractBackend
    corr::Union{Matrix{Float64}, Nothing}     # N×N Majorana covariance matrix Γ (antisymmetric), N = L·majoranas_per_site
    scratch::Union{Matrix{Float64}, Nothing}  # preallocated scratch buffer (same size)
    purify_tol::Float64                      # re-purification trigger threshold (default 1e-10)
    majoranas_per_site::Int                  # 2 = fermionic mode per site (default), 1 = Majorana chain
end
function GaussianBackend(; purify_tol = 1e-10, majoranas_per_site = 2)
    GaussianBackend(nothing, nothing, purify_tol, majoranas_per_site)
end
