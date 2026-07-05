using ITensors
using ITensorMPS

"""
Abstract base type for all simulation backends.
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
