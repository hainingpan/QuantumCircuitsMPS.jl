using ITensors
using ITensorMPS
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
