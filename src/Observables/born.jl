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

Compute the Born probability `P(outcome | state)` at a physical site:

```
P(k) = ⟨ψ|Pₖ|ψ⟩ / ⟨ψ|ψ⟩ ,   Pₖ = |k⟩⟨k| .
```

`physical_site` is converted to its RAM index via `state.phy_ram` (handles the
`:periodic` fold). `ProjK` is defined for `"Qubit"` by ITensors and for the spin
site types by `src/Core/spin_sites.jl`.

Non-mutating (neither the tensors nor the orthogonality limits are touched), and
correctly normalized even when `‖ψ‖² ≠ 1` — e.g. after a truncated unitary layer,
which is not renormalized. Evaluates only the requested site, but still pays the
gauge walk to it, so this is a local query rather than an `O(1)` one. Throws on a
zero-norm MPS.

This is the MPS-backend implementation. `SimulationState{StateVectorBackend}`
and `SimulationState{CliffordBackend}` have their own, more specific
overrides (see `src/StateVector/measurement.jl`, `src/Clifford/measurement.jl`);
narrowing this signature to `MPSBackend` ensures any future/unknown backend
gets a clear `MethodError` here instead of silently crashing on a
backend-specific field (`state.backend.mps`) that doesn't exist.
"""
function born_probability(state::SimulationState{MPSBackend}, physical_site::Int, outcome::Int)
    ram_idx = state.phy_ram[physical_site]
    # An Int `sites` makes expect() return a scalar; it already divides by
    # ⟨ψ|ψ⟩, so no extra norm division here. `real`: Pₖ is Hermitian.
    return real(expect(state.backend.mps, "Proj$(outcome)"; sites = ram_idx))
end
