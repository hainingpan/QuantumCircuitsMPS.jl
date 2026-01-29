# === Composite Gates ===

"""
    Reset

Reset gate: projects to |0⟩ or |1⟩ based on Born probability, then flips to |0⟩ if needed.
Equivalent to measure + conditional X.
"""
struct Reset <: AbstractGate end
support(::Reset) = 1

# Note: Reset doesn't have a simple build_operator because it requires
# measurement + conditional logic. It's handled specially in apply!.
# We provide a stub that throws to catch misuse.
function build_operator(gate::Reset, site::Index, local_dim::Int; kwargs...)
    error("Reset gate cannot be built as a single operator. Use apply!(state, Reset(), geo) instead.")
end
