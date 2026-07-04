# === Named Parametrized Single-Qubit Gates ===
#
# Rotation convention (API contract, standard quantum-computing convention):
#   Rx(θ) = exp(-iθX/2), Ry(θ) = exp(-iθY/2), Rz(θ) = exp(-iθZ/2)

"""
    Rx(θ)

Single-qubit rotation about the X axis, convention `Rx(θ) = exp(-iθX/2)`:

    [ cos(θ/2)     -i·sin(θ/2) ]
    [ -i·sin(θ/2)   cos(θ/2)   ]
"""
struct Rx <: AbstractGate
    θ::Float64
end
support(::Rx) = 1
gate_matrix(g::Rx) = ComplexF64[cos(g.θ/2) -im*sin(g.θ/2); -im*sin(g.θ/2) cos(g.θ/2)]

"""
    Ry(θ)

Single-qubit rotation about the Y axis, convention `Ry(θ) = exp(-iθY/2)`:

    [ cos(θ/2)  -sin(θ/2) ]
    [ sin(θ/2)   cos(θ/2) ]
"""
struct Ry <: AbstractGate
    θ::Float64
end
support(::Ry) = 1
gate_matrix(g::Ry) = ComplexF64[cos(g.θ/2) -sin(g.θ/2); sin(g.θ/2) cos(g.θ/2)]

"""
    Rz(θ)

Single-qubit rotation about the Z axis, convention `Rz(θ) = exp(-iθZ/2)`:

    [ exp(-iθ/2)   0         ]
    [ 0            exp(iθ/2) ]
"""
struct Rz <: AbstractGate
    θ::Float64
end
support(::Rz) = 1
gate_matrix(g::Rz) = ComplexF64[exp(-im*g.θ/2) 0; 0 exp(im*g.θ/2)]

"""
    Hadamard()

Single-qubit Hadamard gate, `H = (X + Z)/√2`:

    (1/√2) [ 1   1 ]
           [ 1  -1 ]

Satisfies `H² = I`.
"""
struct Hadamard <: AbstractGate end
support(::Hadamard) = 1
gate_matrix(::Hadamard) = ComplexF64[1 1; 1 -1] ./ sqrt(2)

# === build_operator implementation (shared) ===

const _NamedQubitGate = Union{Rx, Ry, Rz, Hadamard}

"""
    build_operator(gate::Union{Rx,Ry,Rz,Hadamard}, site::Index, local_dim::Int) -> ITensor

Build the exact 2×2 matrix operator: `ITensor(M, site', site)` with primed =
output. Qubit-only (`local_dim == 2`).
"""
function build_operator(gate::_NamedQubitGate, site::Index, local_dim::Int; kwargs...)
    local_dim == 2 || throw(ArgumentError(
        "$(nameof(typeof(gate))) is a qubit gate (local_dim = 2); state has local_dim = $local_dim"))
    return ITensor(gate_matrix(gate), prime(site), site)
end
