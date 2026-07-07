# === Pauli-String Expectation Observable ===
#
# Computes ⟨∏ᵢ Pᵢ⟩ for a product of single-qubit Pauli operators acting on
# distinct sites, e.g. ⟨Z₁ Z₄⟩ or ⟨X₂ Y₃ Z₅⟩. Identity on all unlisted sites.
#
# Backend implementations:
#   - MPS (this file): local `op` insertions on a copy of the MPS + `inner`
#     contraction (mirrors string_order.jl's technique)
#   - StateVector (src/StateVector/pauli_string.jl): direct Pauli action on a
#     copy of ψ, then ⟨ψ|Pψ⟩
#   - Clifford (src/Clifford/pauli_string.jl): QuantumClifford.expect on the
#     stabilizer tableau (poly-time; expectation ∈ {-1, 0, +1})

using ITensors
using ITensorMPS

"""
    PauliString(ops::Pair{Int,Symbol}...)

Expectation value ⟨∏ᵢ Pᵢ⟩ of a product of single-qubit Pauli operators.

Each argument is a `site => pauli` pair with `pauli ∈ (:X, :Y, :Z)`;
identity is implied on every site not listed. Sites must be distinct and
positive; range validation against the system size happens at evaluation
time. Supported on all three backends (MPS, state vector, Clifford).

Qubit-only in v0.4.0: evaluating on a non-qubit state (e.g.
`site_type="S=1"`) throws an `ArgumentError` (spin-S operator strings are
on the roadmap).

# Sign convention
Matches `Magnetization`: ⟨Zᵢ⟩ = +1 on |0⟩ and -1 on |1⟩ at site `i`.

# Examples
```julia
state = SimulationState(L=4, bc=:open,
    rng=RNGRegistry(gates_spacetime=1, gates_realization=2, born_measurement=3))
initialize!(state, ProductState(binary_int=0))

PauliString(1 => :Z)(state)                    # ⟨Z₁⟩ = +1.0 on |0000⟩
PauliString(1 => :Z, 4 => :Z)(state)           # ⟨Z₁Z₄⟩ = +1.0
track!(state, :zz => PauliString(1 => :Z, 2 => :Z))  # record during simulate!
```
"""
struct PauliString <: AbstractObservable
    sites::Vector{Int}
    paulis::Vector{Symbol}

    function PauliString(ops::Pair{Int, Symbol}...)
        isempty(ops) &&
            throw(ArgumentError("PauliString requires at least one site => pauli pair, e.g. PauliString(1 => :Z)"))
        sites = Int[first(p) for p in ops]
        paulis = Symbol[last(p) for p in ops]
        for (s, p) in zip(sites, paulis)
            s > 0 || throw(ArgumentError("PauliString site must be positive, got $s"))
            p in (:X, :Y, :Z) ||
                throw(ArgumentError("PauliString operator must be :X, :Y, or :Z, got :$p (identity is implied by omission)"))
        end
        allunique(sites) ||
            throw(ArgumentError("PauliString sites must be distinct, got $sites"))
        perm = sortperm(sites)
        new(sites[perm], paulis[perm])
    end
end

"""
    _validate_pauli_string(obs::PauliString, state) -> nothing

Shared evaluation-time validation for all backends: qubit-only (v0.4.0)
and site indices within `1:L`.
"""
function _validate_pauli_string(obs::PauliString, state)
    state.local_dim == 2 ||
        throw(ArgumentError(
            "PauliString is qubit-only in v0.4.0 (got site_type=\"$(state.site_type)\", " *
            "local_dim=$(state.local_dim)). Spin-S operator strings are on the roadmap; " *
            "use a qubit (local_dim=2) state."
        ))
    for s in obs.sites
        s <= state.L ||
            throw(ArgumentError("PauliString site $s exceeds system size L=$(state.L)"))
    end
    return nothing
end

"""
    (obs::PauliString)(state::SimulationState) -> Float64

MPS implementation: apply each Pauli `op` to a copy of the MPS at its
RAM-mapped site, then contract ⟨ψ|Pψ⟩ via `inner`. The imaginary part is
asserted ≤ 1e-12 (Pauli strings are Hermitian) and the real part returned.
"""
function (obs::PauliString)(state::SimulationState)
    _validate_pauli_string(obs, state)

    psi_copy = copy(state.backend.mps)
    for (s_phys, p) in zip(obs.sites, obs.paulis)
        s_ram = state.phy_ram[s_phys]
        P = op(String(p), state.backend.sites[s_ram])
        psi_copy[s_ram] = psi_copy[s_ram] * P
    end
    noprime!(psi_copy)

    val = inner(state.backend.mps, psi_copy)
    abs(imag(val)) <= 1e-12 ||
        error("PauliString expectation has non-negligible imaginary part $(imag(val)); " *
              "Pauli strings are Hermitian — this indicates a bug or an unnormalized state")
    return real(val)
end
