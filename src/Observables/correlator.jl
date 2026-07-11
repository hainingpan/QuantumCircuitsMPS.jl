# === Connected Two-Point Correlator Observable ===
#
# C(i,j) = ⟨PᵢPⱼ⟩ − ⟨Pᵢ⟩⟨Pⱼ⟩ — a pure COMPOSITION of three PauliString
# expectation evaluations, so it inherits PauliString's per-backend dispatch
# (MPS, state vector, Clifford) with no backend-specific code of its own.
# The Clifford PauliString method already normalizes QuantumClifford.expect's
# mixed Int/Complex {0, ±1, ±i} returns to a real Float64.

"""
    Correlator(pi::Pair{Int,Symbol}, pj::Pair{Int,Symbol})

Connected two-point correlator C(i,j) = ⟨PᵢPⱼ⟩ − ⟨Pᵢ⟩⟨Pⱼ⟩.

Each argument is a `site => pauli` pair with `pauli ∈ (:X, :Y, :Z)`, matching
`PauliString`'s argument style. The two sites must be DISTINCT (the
self-correlation C(i,i) with Pᵢ² = I is identically 1 − ⟨Pᵢ⟩² and is not
computed here — an `ArgumentError` is thrown for i == j).

Supported on all three backends (composition of three `PauliString`
evaluations, which dispatch per backend). Qubit-only in v0.4.0 (inherited
from `PauliString`).

# Properties (analytic anchors)
- Product state |0…0⟩: C(i,j) = 1 − 1·1 = 0 for Z operators
- Bell pair, `Correlator(1 => :Z, 2 => :Z)` = 1 − 0·0 = 1

# Examples
```julia
c = Correlator(1 => :Z, 4 => :Z)
value = c(state)
track!(state, :czz => Correlator(1 => :Z, 2 => :Z))
```
"""
struct Correlator <: AbstractObservable
    pair_string::PauliString
    single_i::PauliString
    single_j::PauliString

    function Correlator(pi::Pair{Int, Symbol}, pj::Pair{Int, Symbol})
        first(pi) != first(pj) ||
            throw(ArgumentError(
                "Correlator sites must be distinct, got i == j == $(first(pi)). " *
                "The self-correlation C(i,i) = 1 - ⟨Pᵢ⟩² is trivial (Pᵢ² = I) " *
                "and is not computed by this observable."))
        # PauliString validates site positivity / pauli symbols / distinctness.
        new(PauliString(pi, pj), PauliString(pi), PauliString(pj))
    end
end

"""
    (c::Correlator)(state::SimulationState) -> Float64

Evaluate the connected correlator as three `PauliString` expectations:
⟨PᵢPⱼ⟩ − ⟨Pᵢ⟩⟨Pⱼ⟩. Works on every backend that supports `PauliString`.
"""
function (c::Correlator)(state)
    return c.pair_string(state) - c.single_i(state) * c.single_j(state)
end
