# === Pauli-String Expectation — Clifford (stabilizer-tableau) Backend ===
#
# For a stabilizer state, the expectation value of any Pauli string is
# exactly +1, -1, or 0, computable in POLYNOMIAL time via stabilizer-group
# membership — QuantumClifford.jl provides this natively as
# `expect(::PauliOperator, ::AbstractStabilizer)`.
#
# NAMESPACE NOTE (same as Clifford.jl / measurement.jl): bare
# `import QuantumClifford` + fully-qualified calls only.
import QuantumClifford

"""
    (obs::PauliString)(state::SimulationState{CliffordBackend}) -> Float64

Clifford implementation of `PauliString` via
`QuantumClifford.expect(PauliOperator, tableau)` — poly-time for stabilizer
states, returning exactly +1.0, -1.0, or 0.0. Sites are mapped through
`phy_ram` consistently with the rest of the Clifford code. The result is
normalized to `Float64` (QuantumClifford may return integer/complex types);
any imaginary component ≤ 1e-12 is asserted away (Pauli strings are
Hermitian).
"""
function (obs::PauliString)(state::SimulationState{CliffordBackend})
    _validate_pauli_string(obs, state)

    L = state.L
    xs = fill(false, L)
    zs = fill(false, L)
    for (s_phys, p) in zip(obs.sites, obs.paulis)
        s_ram = state.phy_ram[s_phys]
        if p === :X
            xs[s_ram] = true
        elseif p === :Z
            zs[s_ram] = true
        else  # :Y
            xs[s_ram] = true
            zs[s_ram] = true
        end
    end
    pauli_op = QuantumClifford.PauliOperator(0x0, xs, zs)

    val = ComplexF64(QuantumClifford.expect(pauli_op, state.backend.tableau))
    abs(imag(val)) <= 1e-12 ||
        error("PauliString expectation has non-negligible imaginary part $(imag(val)); " *
              "Pauli strings are Hermitian — this indicates a bug in the stabilizer expectation")
    return Float64(real(val))
end
