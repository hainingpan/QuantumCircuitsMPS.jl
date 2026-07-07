# === Pauli-String Expectation — State-Vector Backend ===
#
# Direct Pauli-matrix action on a COPY of ψ, then ⟨ψ|Pψ⟩.
# Basis convention (matches all other SV observables): site 1 = MSB of the
# basis index; digit 0 ↦ |0⟩ (⟨Z⟩ = +1), digit 1 ↦ |1⟩ (⟨Z⟩ = -1).
#
# Per-basis-state action (qubit, bit b at the site):
#   Z: coefficient ×(+1) for b=0, ×(-1) for b=1 (diagonal)
#   X: flips the bit (|0⟩↔|1⟩), coefficient unchanged
#   Y: flips the bit; coefficient ×(+i) for b=0 (Y|0⟩ = i|1⟩),
#      ×(-i) for b=1 (Y|1⟩ = -i|0⟩)

"""
    (obs::PauliString)(state::SimulationState{StateVectorBackend}) -> Float64

State-vector implementation of `PauliString`: builds Pψ by applying the
Pauli string amplitude-by-amplitude to a copy of the dense state vector,
then returns ⟨ψ|Pψ⟩. The imaginary part is asserted ≤ 1e-12 (Pauli strings
are Hermitian) and the real part returned.
"""
function (obs::PauliString)(state::SimulationState{StateVectorBackend})
    _validate_pauli_string(obs, state)

    L = state.L
    ψ = state.backend.ψ
    Pψ = zeros(ComplexF64, length(ψ))

    @inbounds for n0 in 0:(length(ψ) - 1)
        c = one(ComplexF64)
        m = n0
        for (s, p) in zip(obs.sites, obs.paulis)
            b = (n0 >> (L - s)) & 1
            if p === :Z
                if b == 1
                    c = -c
                end
            elseif p === :X
                m ⊻= 1 << (L - s)
            else  # :Y
                m ⊻= 1 << (L - s)
                c *= (b == 0 ? im : -im)
            end
        end
        Pψ[m + 1] += c * ψ[n0 + 1]
    end

    val = sum(conj(ψ[k]) * Pψ[k] for k in eachindex(ψ))
    abs(imag(val)) <= 1e-12 ||
        error("PauliString expectation has non-negligible imaginary part $(imag(val)); " *
              "Pauli strings are Hermitian — this indicates a bug or an unnormalized state")
    return real(val)
end
