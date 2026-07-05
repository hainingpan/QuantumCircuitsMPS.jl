# === Clifford Gate-Application Engine (stabilizer-tableau backend) ===
# _apply_single! methods dispatching each Clifford-compatible gate directly
# onto a QuantumClifford.jl MixedDestabilizer tableau (state.backend.tableau).
#
# NAMESPACE NOTE (see .sisyphus/notepads/clifford-backend/learnings.md, Task 6
# critical-fix section): QuantumCircuitsMPS.jl ITSELF defines and exports its
# own `apply!` (src/Core/apply.jl, `apply!(state::SimulationState, gate, geo)`).
# A selective `using QuantumClifford: apply!` inside this file would bind the
# name `apply!` in THIS module to QuantumClifford's generic function before
# Core/apply.jl (included later) tries to add its own method to the SAME name
# — a namespace collision risk analogous to the `expect` bug that broke 89
# tests in Task 6. To avoid this entirely, we use a bare `import QuantumClifford`
# (no names pulled into scope) and fully-qualify every call as
# `QuantumClifford.apply!(...)`, `QuantumClifford.sX(...)`, etc.
import QuantumClifford

"""
    _apply_single!(state::SimulationState{CliffordBackend}, gate::PauliX, phy_sites::Vector{Int})

Apply a Pauli-X gate to the stabilizer tableau via QuantumClifford's `sX`.
"""
function _apply_single!(state::SimulationState{CliffordBackend}, gate::PauliX, phy_sites::Vector{Int})
    if support(gate) != length(phy_sites)
        throw(ArgumentError("Gate support $(support(gate)) does not match sites $(length(phy_sites))"))
    end
    ram_sites = [state.phy_ram[ps] for ps in phy_sites]   # identity for Clifford, but keep the lookup for code-path consistency
    QuantumClifford.apply!(state.backend.tableau, QuantumClifford.sX(ram_sites[1]))
    return nothing
end

"""
    _apply_single!(state::SimulationState{CliffordBackend}, gate::PauliY, phy_sites::Vector{Int})

Apply a Pauli-Y gate to the stabilizer tableau via QuantumClifford's `sY`.
"""
function _apply_single!(state::SimulationState{CliffordBackend}, gate::PauliY, phy_sites::Vector{Int})
    if support(gate) != length(phy_sites)
        throw(ArgumentError("Gate support $(support(gate)) does not match sites $(length(phy_sites))"))
    end
    ram_sites = [state.phy_ram[ps] for ps in phy_sites]
    QuantumClifford.apply!(state.backend.tableau, QuantumClifford.sY(ram_sites[1]))
    return nothing
end

"""
    _apply_single!(state::SimulationState{CliffordBackend}, gate::PauliZ, phy_sites::Vector{Int})

Apply a Pauli-Z gate to the stabilizer tableau via QuantumClifford's `sZ`.
"""
function _apply_single!(state::SimulationState{CliffordBackend}, gate::PauliZ, phy_sites::Vector{Int})
    if support(gate) != length(phy_sites)
        throw(ArgumentError("Gate support $(support(gate)) does not match sites $(length(phy_sites))"))
    end
    ram_sites = [state.phy_ram[ps] for ps in phy_sites]
    QuantumClifford.apply!(state.backend.tableau, QuantumClifford.sZ(ram_sites[1]))
    return nothing
end

"""
    _apply_single!(state::SimulationState{CliffordBackend}, gate::Hadamard, phy_sites::Vector{Int})

Apply a Hadamard gate to the stabilizer tableau via QuantumClifford's `sHadamard`.
"""
function _apply_single!(state::SimulationState{CliffordBackend}, gate::Hadamard, phy_sites::Vector{Int})
    if support(gate) != length(phy_sites)
        throw(ArgumentError("Gate support $(support(gate)) does not match sites $(length(phy_sites))"))
    end
    ram_sites = [state.phy_ram[ps] for ps in phy_sites]
    QuantumClifford.apply!(state.backend.tableau, QuantumClifford.sHadamard(ram_sites[1]))
    return nothing
end

"""
    _apply_single!(state::SimulationState{CliffordBackend}, gate::PhaseGate, phy_sites::Vector{Int})

Apply an S (phase) gate to the stabilizer tableau via QuantumClifford's `sPhase`.
"""
function _apply_single!(state::SimulationState{CliffordBackend}, gate::PhaseGate, phy_sites::Vector{Int})
    if support(gate) != length(phy_sites)
        throw(ArgumentError("Gate support $(support(gate)) does not match sites $(length(phy_sites))"))
    end
    ram_sites = [state.phy_ram[ps] for ps in phy_sites]
    QuantumClifford.apply!(state.backend.tableau, QuantumClifford.sPhase(ram_sites[1]))
    return nothing
end

"""
    _apply_single!(state::SimulationState{CliffordBackend}, gate::CZ, phy_sites::Vector{Int})

Apply a controlled-Z gate to the stabilizer tableau. NOTE: QuantumClifford.jl
does NOT have a function named `sCZ` — the correct symbolic gate is
`sCPHASE`, verified (via stabilizer conjugation of a `+X_` state) to match
the standard CZ = diag(1,1,1,-1) convention.
"""
function _apply_single!(state::SimulationState{CliffordBackend}, gate::CZ, phy_sites::Vector{Int})
    if support(gate) != length(phy_sites)
        throw(ArgumentError("Gate support $(support(gate)) does not match sites $(length(phy_sites))"))
    end
    ram_sites = [state.phy_ram[ps] for ps in phy_sites]
    QuantumClifford.apply!(state.backend.tableau, QuantumClifford.sCPHASE(ram_sites[1], ram_sites[2]))
    return nothing
end

"""
    _apply_single!(state::SimulationState{CliffordBackend}, gate::CNOT, phy_sites::Vector{Int})

Apply a CNOT gate to the stabilizer tableau via QuantumClifford's `sCNOT`.
"""
function _apply_single!(state::SimulationState{CliffordBackend}, gate::CNOT, phy_sites::Vector{Int})
    if support(gate) != length(phy_sites)
        throw(ArgumentError("Gate support $(support(gate)) does not match sites $(length(phy_sites))"))
    end
    ram_sites = [state.phy_ram[ps] for ps in phy_sites]
    QuantumClifford.apply!(state.backend.tableau, QuantumClifford.sCNOT(ram_sites[1], ram_sites[2]))
    return nothing
end

"""
    _apply_single!(state::SimulationState{CliffordBackend}, gate::SWAP, phy_sites::Vector{Int})

Apply a SWAP gate to the stabilizer tableau via QuantumClifford's `sSWAP`.
"""
function _apply_single!(state::SimulationState{CliffordBackend}, gate::SWAP, phy_sites::Vector{Int})
    if support(gate) != length(phy_sites)
        throw(ArgumentError("Gate support $(support(gate)) does not match sites $(length(phy_sites))"))
    end
    ram_sites = [state.phy_ram[ps] for ps in phy_sites]
    QuantumClifford.apply!(state.backend.tableau, QuantumClifford.sSWAP(ram_sites[1], ram_sites[2]))
    return nothing
end

"""
    _apply_single!(state::SimulationState{CliffordBackend}, gate::RandomClifford, phy_sites::Vector{Int})

Sample a random n-qubit Clifford operator from the `:gates_realization` RNG
stream via `QuantumClifford.random_clifford(rng, gate.n)`, then apply it
NATIVELY to the stabilizer tableau (via `QuantumClifford.apply!(tableau, op,
qubit_indices)`) — no dense-matrix conversion (no `QuantumOpticsBase`
involvement), unlike the MPS/state-vector backends' `gate_matrix` path.
"""
function _apply_single!(state::SimulationState{CliffordBackend}, gate::RandomClifford, phy_sites::Vector{Int})
    if support(gate) != length(phy_sites)
        throw(ArgumentError("Gate support $(support(gate)) does not match sites $(length(phy_sites))"))
    end
    ram_sites = [state.phy_ram[ps] for ps in phy_sites]
    rng = get_rng(state.rng_registry, :gates_realization)
    op = QuantumClifford.random_clifford(rng, gate.n)
    QuantumClifford.apply!(state.backend.tableau, op, reverse(ram_sites))
    return nothing
end

"""
    _apply_single!(state::SimulationState{CliffordBackend}, gate::AbstractGate, phy_sites::Vector{Int})

Fallback for any gate NOT handled by one of the specific `_apply_single!`
methods above. The Clifford (stabilizer-tableau) backend can only represent
Clifford-group operations; non-Clifford gates (e.g. arbitrary rotations,
Haar-random unitaries, or non-Clifford projections) have no native tableau
representation. Throws an informative `ArgumentError` naming the offending
gate type and suggesting the dense-backend alternatives.
"""
function _apply_single!(state::SimulationState{CliffordBackend}, gate::AbstractGate, phy_sites::Vector{Int})
    throw(ArgumentError(
        "Clifford backend only supports Clifford gates (PauliX, PauliY, PauliZ, " *
        "Hadamard, PhaseGate, CZ, CNOT, SWAP, RandomClifford, Measure, Reset). " *
        "Received: $(typeof(gate)). " *
        "Please switch to backend=:mps or backend=:statevector for non-Clifford gates."
    ))
end
