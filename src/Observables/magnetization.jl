"""
    Magnetization(axis::Symbol)

Average single-site expectation value along `axis`.

Computes Mₐ = (1/L) Σᵢ ⟨axis_i⟩ where axis ∈ {:X, :Y, :Z}.

# Example
```julia
track!(state, :Mz => Magnetization(:Z))
```
"""
struct Magnetization <: AbstractObservable
    axis::Symbol

    function Magnetization(axis::Symbol)
        axis in (:X, :Y, :Z) ||
            throw(ArgumentError("Magnetization axis must be :X, :Y, or :Z"))
        new(axis)
    end
end

function (m::Magnetization)(state)
    # Spin site types with d > 2 ("S=1", "S=3/2", ...) define no "Z"/"X"/"Y"
    # ops — route :Z to "Sz" (eigenvalues m = -S..S). "Qubit" and "S=1/2"
    # keep the historical Pauli path (eigenvalues ±1) unchanged.
    spin_s = _parse_spin_site_type(state.site_type)
    if spin_s !== nothing && state.local_dim > 2
        m.axis == :Z || throw(ArgumentError(
            "Magnetization on spin site types (site_type=$(state.site_type)) currently only supports the :Z axis, got $(m.axis)"))
        vals = expect(state.backend.mps, "Sz")
    else
        vals = expect(state.backend.mps, String(m.axis))
    end
    return real(sum(vals)) / length(vals)
end
