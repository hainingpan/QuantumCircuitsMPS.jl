# === MatrixGate: user-supplied explicit matrix gate ===

"""
    gate_matrix(gate::AbstractGate) -> Matrix{ComplexF64}

Return the explicit matrix of a gate whose action is defined by a fixed
matrix (e.g. [`MatrixGate`](@ref), [`Rx`](@ref), [`Ry`](@ref), [`Rz`](@ref),
[`Hadamard`](@ref)). Matrix convention: `U[out, in] = ⟨out|U|in⟩` with
Kronecker (row-major site) ordering — the FIRST site of the region is the
slowest basis digit, so `kron(A, B)` acts with `A` on the first site.
"""
function gate_matrix end

"""
    MatrixGate(U::AbstractMatrix)

Gate defined by an explicit `d^n × d^n` matrix `U` acting on `n` sites of
local dimension `d`.

# Size-inference rule (API contract)
The number of sites `n` and local dimension `d` are inferred from the matrix
size `N`:
- `N = 2^n` (n ≥ 1) → `n`-site **qubit** gate (`d = 2`)
- `N = 3^n` (n ≥ 2) → `n`-site **spin-1** gate (`d = 3`)
- anything else → `ArgumentError`

The two families are disjoint (powers of 2 are even, powers of 3 are odd),
so inference is unambiguous. Single-site spin-1 matrices (3×3) are NOT
accepted: v0.1 introduces no new single-site qudit machinery (S=1 support is
preserved only for the existing two-site sector operations). The inferred
`d` is validated against the state's local dimension at apply time.

# Matrix convention
`U[out, in] = ⟨out|U|in⟩` with standard Kronecker ordering:
`U = kron(A, B)` acts with `A` on the FIRST site of the region and `B` on
the second, i.e. basis states `|b₁ b₂ … bₙ⟩` are ordered with the LAST site
as the fastest digit.

# Notes
- `MatrixGate` assumes `U` is unitary: NO normalization is applied after
  application (matching all other unitary gates).
- To apply the same single/multi-site unitary at many places, combine with a
  broadcast geometry; for one specific region use `Sites(collection)`:
  `apply!(state, MatrixGate(U), Sites(1:2))`.

# Example
```julia
X = [0 1; 1 0]
apply!(state, MatrixGate(kron(X, [1 0; 0 1])), Sites(1:2))  # X on site 1
```
"""
struct MatrixGate <: AbstractGate
    U::Matrix{ComplexF64}
    n::Int
    d::Int

    function MatrixGate(U::AbstractMatrix)
        size(U, 1) == size(U, 2) || throw(ArgumentError(
            "MatrixGate requires a square matrix, got size $(size(U))"))
        N = size(U, 1)
        d, n = _infer_matrix_gate_dims(N)
        new(Matrix{ComplexF64}(U), n, d)
    end
end

support(g::MatrixGate) = g.n
gate_matrix(g::MatrixGate) = copy(g.U)

"""
    _infer_matrix_gate_dims(N::Int) -> (d, n)

Infer (local dimension, site count) from a MatrixGate size `N` per the
documented rule: `2^n` (n ≥ 1) → qubits; `3^n` (n ≥ 2) → spin-1; otherwise
`ArgumentError`.
"""
function _infer_matrix_gate_dims(N::Int)
    if N >= 2
        n2 = round(Int, log2(N))
        2^n2 == N && return (2, n2)
        n3 = round(Int, log(3, N))
        (n3 >= 2 && 3^n3 == N) && return (3, n3)
    end
    throw(ArgumentError(
        "MatrixGate size $N×$N does not match d^n sites: expected 2^n (qubits, n ≥ 1) " *
        "or 3^n (spin-1, n ≥ 2). Single-site spin-1 (3×3) gates are not supported in v0.1."))
end

# === build_operator implementations ===

"""
    build_operator(gate::MatrixGate, sites::Vector{Index}, local_dim::Int) -> ITensor

Reshape the stored `d^n × d^n` matrix into a `2n`-index ITensor. Column-major
reshape puts the LAST site of the region on the fastest matrix digit, so the
tensor dims map to `(sₙ', …, s₁', sₙ, …, s₁)` with primed = output (row) and
unprimed = input (column).
"""
function build_operator(gate::MatrixGate, sites::Vector{<:Index}, local_dim::Int; kwargs...)
    length(sites) == gate.n || throw(ArgumentError(
        "MatrixGate acts on $(gate.n) site(s), got $(length(sites)) sites"))
    local_dim == gate.d || throw(ArgumentError(
        "MatrixGate was built for local dimension $(gate.d), but the state has local dimension $local_dim"))

    d, n = gate.d, gate.n
    T = reshape(gate.U, ntuple(_ -> d, 2 * n))
    # Row (output) digits: sites[n] fastest … sites[1] slowest; same for columns.
    out_inds = [prime(s) for s in Iterators.reverse(sites)]
    in_inds = collect(Iterators.reverse(sites))
    return ITensor(T, out_inds..., in_inds...)
end

"""
    build_operator(gate::MatrixGate, site::Index, local_dim::Int) -> ITensor

Single-site MatrixGate: `ITensor(U, site', site)` with primed = output.
"""
function build_operator(gate::MatrixGate, site::Index, local_dim::Int; kwargs...)
    gate.n == 1 || throw(ArgumentError(
        "MatrixGate acts on $(gate.n) sites, but was applied to a single site"))
    local_dim == gate.d || throw(ArgumentError(
        "MatrixGate was built for local dimension $(gate.d), but the state has local dimension $local_dim"))
    return ITensor(gate.U, prime(site), site)
end
