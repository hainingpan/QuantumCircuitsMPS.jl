"""
    BornProbability(site::Int, outcome::Int)

Observable for Born rule probability P(measurement outcome | state) at a physical site.
"""
struct BornProbability <: AbstractObservable
    site::Int      # Physical site index
    outcome::Int   # level index 0 .. local_dim-1 (0 or 1 for qubits)

    function BornProbability(site::Int, outcome::Int)
        outcome >= 0 || throw(ArgumentError(
            "outcome must be a non-negative level index, got $outcome"))
        new(site, outcome)
    end
end

# Callable struct interface
function (bp::BornProbability)(state)
    return born_probability(state, bp.site, bp.outcome)
end

"""
    born_probability(state::SimulationState{MPSBackend}, physical_site::Int, outcome::Int) -> Float64

Compute Born probability P(outcome | state) at a physical site.
Converts physical site to RAM index for MPS access.

This is the MPS-backend implementation. `SimulationState{StateVectorBackend}`
and `SimulationState{CliffordBackend}` have their own, more specific
overrides (see `src/StateVector/measurement.jl`, `src/Clifford/measurement.jl`);
narrowing this signature to `MPSBackend` ensures any future/unknown backend
gets a clear `MethodError` here instead of silently crashing on a
backend-specific field (`state.backend.mps`) that doesn't exist.
"""
function born_probability(state::SimulationState{MPSBackend}, physical_site::Int, outcome::Int)
    # Convert physical site to RAM index
    ram_idx = state.phy_ram[physical_site]

    # Use ITensorMPS expect() with the per-level projector operator
    # ProjK = |k⟩⟨k| (defined for Qubit by ITensors; for spin site types by
    # src/Core/spin_sites.jl). For outcome ∈ (0, 1) this is the historical
    # "Proj0"/"Proj1" string exactly.
    proj_op = "Proj$(outcome)"

    # expect() returns Vector for all sites, index by RAM position
    # Divide by ⟨ψ|ψ⟩ to handle slight norm drift; for normalized MPS this is a no-op.
    mps_norm_sq = real(inner(state.backend.mps, state.backend.mps))
    all_probs = expect(state.backend.mps, proj_op)
    return real(all_probs[ram_idx]) / mps_norm_sq
end
