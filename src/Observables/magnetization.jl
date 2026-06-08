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
        axis in (:X, :Y, :Z) || throw(ArgumentError("Magnetization axis must be :X, :Y, or :Z"))
        new(axis)
    end
end

function (m::Magnetization)(state)
    vals = expect(state.mps, String(m.axis))
    return real(sum(vals)) / length(vals)
end
