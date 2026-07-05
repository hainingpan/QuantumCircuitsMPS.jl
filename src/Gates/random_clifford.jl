# === Random Clifford Gate ===

import QuantumClifford
import QuantumOpticsBase

"""
    RandomClifford(n::Int=2)

`n`-site Haar-random *Clifford group* element gate (default: 2-site).

Each application draws a fresh Haar-random element of the `n`-qubit Clifford
group (via `QuantumClifford.random_clifford`) and exposes it as a dense
`d^n × d^n` unitary matrix (`d` = local dimension), consuming from the
`:gates_realization` RNG stream — exactly like `HaarRandom`, but restricted to
the (finite) Clifford group instead of the full continuous unitary group.

This gate is the MPS/state-vector-backend-facing dense-matrix representation
of a random Clifford operator. The Clifford backend itself samples and applies
random Clifford operators directly on its tableau representation (native
`QuantumClifford.apply!`/`random_clifford`), never going through this dense
matrix path.
"""
struct RandomClifford <: AbstractGate
    n::Int

    function RandomClifford(n::Int=2)
        n >= 1 || throw(ArgumentError("RandomClifford requires n >= 1 site(s), got $n"))
        new(n)
    end
end
support(g::RandomClifford) = g.n

"""
    _random_clifford_unitary(n::Int, rng::AbstractRNG; local_dim::Int=2) -> Matrix{ComplexF64}

Sample a Haar-random `n`-qubit Clifford operator via
`QuantumClifford.random_clifford(rng, n)` and convert it to a dense
`local_dim^n × local_dim^n` unitary matrix.

Conversion path: `QuantumClifford.CliffordOperator` → `QuantumOpticsBase.Operator`
(via the `QuantumCliffordQOpticsExt` package extension, triggered by having both
`QuantumClifford` and `QuantumOpticsBase` loaded) → dense `.data` matrix. This is
the officially documented conversion route in QuantumClifford.jl (no direct
`Matrix(::CliffordOperator)` method exists in QuantumClifford.jl itself).
"""
function _random_clifford_unitary(n::Int, rng::AbstractRNG; local_dim::Int=2)
    local_dim == 2 || throw(ArgumentError(
        "RandomClifford only supports local_dim = 2 (qubits), got local_dim = $local_dim"))
    op = QuantumClifford.random_clifford(rng, n)
    U = QuantumOpticsBase.Operator(op)
    return Matrix{ComplexF64}(U.data)
end

"""
    gate_matrix(g::RandomClifford, rng::AbstractRNG; local_dim::Int=2) -> Matrix{ComplexF64}

State-vector-path equivalent of `build_operator(gate::RandomClifford, ...)`:
draws a fresh `d^n × d^n` Haar-random Clifford unitary (`d = local_dim`,
`n = g.n`) by reusing the same `_random_clifford_unitary` core used by the
MPS `build_operator` path. Consumes from whichever RNG stream `rng` is
(caller is responsible for passing the appropriate stream, e.g.
`:gates_realization`).
"""
gate_matrix(g::RandomClifford, rng::AbstractRNG; local_dim::Int=2) =
    _random_clifford_unitary(g.n, rng; local_dim=local_dim)

"""
    build_operator(gate::RandomClifford, sites::Vector{Index}, local_dim::Int; rng) -> ITensor

Build an n-site random Clifford unitary operator from the `:gates_realization`
stream. Follows the same index-ordering convention as `HaarRandom`'s
`build_operator` (see `two_qubit.jl`): output-primed-first, input-unprimed-second,
reverse-site-order.
"""
function build_operator(gate::RandomClifford, sites::Vector{<:Index}, local_dim::Int; rng, kwargs...)
    length(sites) == gate.n || throw(ArgumentError(
        "RandomClifford($(gate.n)) requires exactly $(gate.n) sites, got $(length(sites))"))

    # Get the gates_realization RNG stream
    gates_realization_rng = get_rng(rng, :gates_realization)

    n_sites = length(sites)
    N = local_dim^n_sites
    U_matrix = _random_clifford_unitary(n_sites, gates_realization_rng; local_dim=local_dim)

    # Build ITensor from the N×N matrix, following the same
    # output-primed-first, input-unprimed-second, reverse-site-order
    # convention as HaarRandom's build_operator (see two_qubit.jl:88-96).
    U_tensor = reshape(U_matrix, ntuple(_ -> local_dim, 2 * n_sites))
    out_inds = [prime(s) for s in Iterators.reverse(sites)]
    in_inds = collect(Iterators.reverse(sites))
    return ITensor(U_tensor, out_inds..., in_inds...)
end

"""
    build_operator(gate::RandomClifford, site::Index, local_dim::Int; rng) -> ITensor

Single-site (`n = 1`) random Clifford unitary. Same conversion path on a
`d × d` matrix, consuming from `:gates_realization`.
"""
function build_operator(gate::RandomClifford, site::Index, local_dim::Int; rng, kwargs...)
    gate.n == 1 || throw(ArgumentError(
        "RandomClifford($(gate.n)) acts on $(gate.n) sites, but was applied to a single site"))
    U = _random_clifford_unitary(1, get_rng(rng, :gates_realization); local_dim=local_dim)
    return ITensor(U, prime(site), site)
end
