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

Projector onto computational basis state |outcome⟩ (level index, 0-based).
outcome=0 projects onto |0⟩, outcome=1 onto |1⟩; on spin sites of local
dimension d, any level `0 ≤ outcome ≤ d-1` is valid (level k ↔ m = S-k).
The outcome is validated against the state's local dimension at apply time.
"""
struct Projection <: AbstractGate
    outcome::Int

    function Projection(outcome::Int)
        outcome >= 0 ||
            throw(ArgumentError("Projection outcome must be a non-negative level index, got $outcome"))
        new(outcome)
    end
end
support(::Projection) = 1
needs_normalization(::Projection) = true  # projector shrinks the norm
gate_matrix(g::Projection) = _projection_matrix(g.outcome, 2)

"""
    _projection_matrix(outcome::Int, d::Int) -> Matrix{ComplexF64}

Dense d×d projector |outcome⟩⟨outcome| (0-based level index), validated
against the local dimension `d`.
"""
function _projection_matrix(outcome::Int, d::Int)
    outcome < d || throw(ArgumentError(
        "Projection outcome $outcome requires local_dim ≥ $(outcome + 1), got local_dim=$d"))
    P = zeros(ComplexF64, d, d)
    P[outcome + 1, outcome + 1] = 1
    return P
end

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

Build projection operator |outcome⟩⟨outcome| via the site type's per-level
`"Proj<k>"` op string (defined for Qubit/"S=1/2" by ITensors and for all
spin site types by `src/Core/spin_sites.jl`).
"""
function build_operator(gate::Projection, site::Index, local_dim::Int; kwargs...)
    gate.outcome < local_dim || throw(ArgumentError(
        "Projection outcome $(gate.outcome) requires local_dim ≥ $(gate.outcome + 1), got local_dim=$local_dim"))
    return op("Proj$(gate.outcome)", site)
end

"""Phase gate (S gate, √Z), diag(1, i)."""
struct PhaseGate <: AbstractGate end
support(::PhaseGate) = 1
gate_matrix(::PhaseGate) = ComplexF64[1 0; 0 im]

"""
    build_operator(gate::PhaseGate, site::Index, local_dim::Int) -> ITensor

Build Phase (S) operator tensor.
"""
function build_operator(gate::PhaseGate, site::Index, local_dim::Int; kwargs...)
    return op("S", site)
end
