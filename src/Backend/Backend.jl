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
"""
mutable struct StateVectorBackend <: AbstractBackend
    ψ::Union{Vector{ComplexF64}, Nothing}
end
