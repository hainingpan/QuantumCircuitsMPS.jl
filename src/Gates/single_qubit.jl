# === Single-Qubit Gates ===

"""Pauli X gate (NOT gate, bit flip)."""
struct PauliX <: AbstractGate end
support(::PauliX) = 1
gate_matrix(::PauliX) = ComplexF64[0 1; 1 0]

"""Pauli Y gate."""
struct PauliY <: AbstractGate end
support(::PauliY) = 1
gate_matrix(::PauliY) = ComplexF64[0 -im; im 0]

"""Pauli Z gate (phase flip)."""
struct PauliZ <: AbstractGate end
support(::PauliZ) = 1
gate_matrix(::PauliZ) = ComplexF64[1 0; 0 -1]

"""
    Projection(outcome::Int)

Projector onto computational basis state |outcome⟩.
outcome=0 projects onto |0⟩, outcome=1 projects onto |1⟩.
"""
struct Projection <: AbstractGate
    outcome::Int
    
    function Projection(outcome::Int)
        outcome in (0, 1) || throw(ArgumentError("Projection outcome must be 0 or 1, got $outcome"))
        new(outcome)
    end
end
support(::Projection) = 1
needs_normalization(::Projection) = true  # projector shrinks the norm
gate_matrix(g::Projection) = g.outcome == 0 ? ComplexF64[1 0; 0 0] : ComplexF64[0 0; 0 1]

# === build_operator implementations ===

"""
    build_operator(gate::PauliX, site::Index, local_dim::Int) -> ITensor

Build Pauli X operator tensor.
"""
function build_operator(gate::PauliX, site::Index, local_dim::Int; kwargs...)
    # Use ITensors' built-in op function
    return op("X", site)
end

"""
    build_operator(gate::PauliY, site::Index, local_dim::Int) -> ITensor

Build Pauli Y operator tensor.
"""
function build_operator(gate::PauliY, site::Index, local_dim::Int; kwargs...)
    return op("Y", site)
end

"""
    build_operator(gate::PauliZ, site::Index, local_dim::Int) -> ITensor

Build Pauli Z operator tensor.
"""
function build_operator(gate::PauliZ, site::Index, local_dim::Int; kwargs...)
    return op("Z", site)
end

"""
    build_operator(gate::Projection, site::Index, local_dim::Int) -> ITensor

Build projection operator |outcome⟩⟨outcome|.
"""
function build_operator(gate::Projection, site::Index, local_dim::Int; kwargs...)
    if gate.outcome == 0
        return op("Proj0", site)  # |0⟩⟨0|
    else
        return op("Proj1", site)  # |1⟩⟨1|
    end
end
