# === Two-Qubit / n-Site Unitary Gates ===

"""
    HaarRandom(n::Int=2)

`n`-site Haar random unitary gate (default: 2-site).

Each application draws a fresh Haar-random unitary of size `d^n × d^n`
(`d` = local dimension) via QR decomposition of a complex Ginibre matrix,
consuming from the `:gates_realization` RNG stream.

RNG contract: for `n = 2` the consumption pattern and produced matrices are
bit-identical to the historical two-site implementation (exact CT.jl `U()`
algorithm) — golden regressions depend on this.
"""
struct HaarRandom <: AbstractGate
    n::Int

    function HaarRandom(n::Int = 2)
        n >= 1 || throw(ArgumentError("HaarRandom requires n >= 1 site(s), got $n"))
        new(n)
    end
end
support(g::HaarRandom) = g.n

"""
    _haar_unitary(N::Int, rng::AbstractRNG) -> Matrix{ComplexF64}

Haar random N×N unitary via QR of a complex Ginibre matrix.
EXACT reproduction of the CT.jl U() algorithm (lines 585-592): two separate
`randn(rng, N, N)` calls (real then imaginary parts), QR, then phase
correction by `diag(R)/|diag(R)|`. Do NOT change the call shape/order —
the `:gates_realization` stream consumption is an API contract (goldens).
"""
function _haar_unitary(N::Int, rng::AbstractRNG)
    # Generate complex Gaussian matrix: real + imag parts separately
    z = randn(rng, N, N) + randn(rng, N, N) * im

    # QR decomposition
    Q, R = qr(z)
    Q = Matrix(Q)  # Convert from QRCompactWY to Matrix

    # Phase correction: multiply by diagonal of R/|R|
    r_diag = diag(R)
    Lambda = Diagonal(r_diag ./ abs.(r_diag))
    return Q * Lambda
end

"""
    gate_matrix(g::HaarRandom, rng::AbstractRNG; local_dim::Int=2) -> Matrix{ComplexF64}

State-vector-path equivalent of `build_operator(gate::HaarRandom, ...)`: draws
a fresh `d^n × d^n` Haar random unitary (`d = local_dim`, `n = g.n`) by
reusing the same `_haar_unitary` core used by the MPS `build_operator` path.
Consumes from whichever RNG stream `rng` is (caller is responsible for
passing the appropriate stream, e.g. `:gates_realization`).
"""
function gate_matrix(g::HaarRandom, rng::AbstractRNG; local_dim::Int = 2)
    _haar_unitary(local_dim^g.n, rng)
end

"""
    CZ

Controlled-Z gate. Symmetric under qubit exchange.
|00⟩→|00⟩, |01⟩→|01⟩, |10⟩→|10⟩, |11⟩→-|11⟩
"""
struct CZ <: AbstractGate end
support(::CZ) = 2
gate_matrix(::CZ) = Matrix(Diagonal(ComplexF64[1, 1, 1, -1]))

"""
    build_operator(gate::HaarRandom, sites::Vector{Index}, local_dim::Int; rng::RNGRegistry) -> ITensor

Build an n-site Haar random unitary operator from the `:gates_realization`
stream. For `gate.n == 2` this is bit-identical to the historical
implementation (same `randn` call shape/order, same index ordering).
"""
function build_operator(
        gate::HaarRandom, sites::Vector{<:Index}, local_dim::Int; rng, kwargs...)
    length(sites) == gate.n || throw(ArgumentError(
        "HaarRandom($(gate.n)) requires exactly $(gate.n) sites, got $(length(sites))"))

    # Get the gates_realization RNG stream
    gates_realization_rng = get_rng(rng, :gates_realization)

    n_sites = length(sites)
    N = local_dim^n_sites  # 4 for two qubits (matches legacy n = local_dim^2)
    U_matrix = _haar_unitary(N, gates_realization_rng)

    # Build ITensor from the N×N matrix, following the same
    # output-primed-first, input-unprimed-second, reverse-site-order
    # convention as MatrixGate (see matrix_gate.jl:107-109) — this ensures
    # U (not U^T) is applied, and produces MPS/state-vector parity for the
    # same RNG seed.
    U_tensor = reshape(U_matrix, ntuple(_ -> local_dim, 2 * n_sites))
    out_inds = [prime(s) for s in Iterators.reverse(sites)]
    in_inds = collect(Iterators.reverse(sites))
    return ITensor(U_tensor, out_inds..., in_inds...)
end

"""
    build_operator(gate::HaarRandom, site::Index, local_dim::Int; rng) -> ITensor

Single-site (`n = 1`) Haar random unitary. Same Ginibre-QR algorithm on a
`d × d` matrix, consuming from `:gates_realization`.
"""
function build_operator(gate::HaarRandom, site::Index, local_dim::Int; rng, kwargs...)
    gate.n == 1 || throw(ArgumentError(
        "HaarRandom($(gate.n)) acts on $(gate.n) sites, but was applied to a single site"))
    U = _haar_unitary(local_dim, get_rng(rng, :gates_realization))
    return ITensor(U, prime(site), site)
end

# Shared qubit-only guard for the named two-qubit gates (T17 decision, audit
# finding T8): CZ/CNOT/SWAP previously accepted any local_dim and silently
# built UNDOCUMENTED qudit generalizations (e.g. the d=3 "CZ" put −1 only on
# |22⟩ — NOT the standard ω^{jk} qudit CZ; "CNOT" flipped the trit by index
# reversal iff the control was in the highest basis state). These accidental
# extensions are physics traps, so non-qubit sites are rejected with the same
# informative error as Rx/Ry/Rz/Hadamard (parametrized.jl). If T39 (arbitrary
# spin-S) wants qudit two-site gates, it should add principled, documented
# generalizations rather than lifting this guard as-is (note: SWAP's generic
# exchange form IS canonical for any d, but gate_matrix(::SWAP) is hardcoded
# 4×4, so the state-vector backend could not apply a qudit SWAP anyway).
function _check_qubit_two_site(gate::AbstractGate, local_dim::Int)
    local_dim == 2 || throw(ArgumentError(
        "$(nameof(typeof(gate))) is a qubit gate (local_dim = 2); state has local_dim = $local_dim"))
    return nothing
end

"""
    build_operator(gate::CZ, sites::Vector{Index}, local_dim::Int) -> ITensor

Build CZ gate operator. Qubit-only (`local_dim == 2`).

Vectorized construction (T21): reshape the fixed `gate_matrix(::CZ)` into a
4-index tensor and hand it directly to `ITensor(...)`, following the same
output-primed-first, input-unprimed-second, reverse-site-order convention as
`MatrixGate` (see `matrix_gate.jl:98-110`) — eliminates the 16 scalar
`setindex!` calls of the previous per-application loop. Verified bitwise
identical to the prior loop-based construction (element-by-element `==`).
"""
function build_operator(
        gate::CZ, sites::Vector{<:Index}, local_dim::Int; rng = nothing, kwargs...)
    length(sites) == 2 || throw(ArgumentError("CZ requires exactly 2 sites"))
    _check_qubit_two_site(gate, local_dim)

    U = gate_matrix(gate)
    T = reshape(U, ntuple(_ -> local_dim, 4))
    out_inds = [prime(s) for s in Iterators.reverse(sites)]
    in_inds = collect(Iterators.reverse(sites))
    return ITensor(T, out_inds..., in_inds...)
end

"""
    CNOT

Controlled-NOT gate. Control = site 1, target = site 2.
|00⟩→|00⟩, |01⟩→|01⟩, |10⟩→|11⟩, |11⟩→|10⟩
"""
struct CNOT <: AbstractGate end
support(::CNOT) = 2
gate_matrix(::CNOT) = ComplexF64[1 0 0 0; 0 1 0 0; 0 0 0 1; 0 0 1 0]

"""
    SWAP

Swap gate. Exchanges the states of the two sites.
|00⟩→|00⟩, |01⟩→|10⟩, |10⟩→|01⟩, |11⟩→|11⟩
"""
struct SWAP <: AbstractGate end
support(::SWAP) = 2
gate_matrix(::SWAP) = ComplexF64[1 0 0 0; 0 0 1 0; 0 1 0 0; 0 0 0 1]

"""
    build_operator(gate::CNOT, sites::Vector{Index}, local_dim::Int) -> ITensor

Build CNOT gate operator. Control = sites[1], target = sites[2].
Qubit-only (`local_dim == 2`).

Vectorized construction (T21): reshape the fixed `gate_matrix(::CNOT)` into a
4-index tensor, same convention as `CZ`/`MatrixGate` above. Verified bitwise
identical to the prior loop-based construction (element-by-element `==`).
"""
function build_operator(
        gate::CNOT, sites::Vector{<:Index}, local_dim::Int; rng = nothing, kwargs...)
    length(sites) == 2 || throw(ArgumentError("CNOT requires exactly 2 sites"))
    _check_qubit_two_site(gate, local_dim)

    U = gate_matrix(gate)
    T = reshape(U, ntuple(_ -> local_dim, 4))
    out_inds = [prime(s) for s in Iterators.reverse(sites)]
    in_inds = collect(Iterators.reverse(sites))
    return ITensor(T, out_inds..., in_inds...)
end

"""
    build_operator(gate::SWAP, sites::Vector{Index}, local_dim::Int) -> ITensor

Build SWAP gate operator. Qubit-only (`local_dim == 2`).

Vectorized construction (T21): reshape the fixed `gate_matrix(::SWAP)` into a
4-index tensor, same convention as `CZ`/`CNOT`/`MatrixGate` above. Verified
bitwise identical to the prior loop-based construction (element-by-element
`==`).
"""
function build_operator(
        gate::SWAP, sites::Vector{<:Index}, local_dim::Int; rng = nothing, kwargs...)
    length(sites) == 2 || throw(ArgumentError("SWAP requires exactly 2 sites"))
    _check_qubit_two_site(gate, local_dim)

    U = gate_matrix(gate)
    T = reshape(U, ntuple(_ -> local_dim, 4))
    out_inds = [prime(s) for s in Iterators.reverse(sites)]
    in_inds = collect(Iterators.reverse(sites))
    return ITensor(T, out_inds..., in_inds...)
end
