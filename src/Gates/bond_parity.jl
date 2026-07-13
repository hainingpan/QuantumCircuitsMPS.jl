# === BondParity Gate (fermionic Gaussian backend) ===
# Type definition + generic (MPS/state-vector) rejection ONLY. The actual
# Gaussian-backend measurement behavior is added by a LATER task via a
# Gaussian-specific `_apply_single!`/`execute!` override, which Julia's
# method dispatch prefers over the generic fallback defined in this file.

"""
    BondParity()

Projective measurement of the bond parity `iγ_{2i}γ_{2i+1}` between two
adjacent sites `(i, i+1)` — the parity operator built from the "inner" pair
of Majoranas straddling the bond (site `i`'s second Majorana and site
`i+1`'s first Majorana, in the `QuantumCircuitsMPS.majorana_indices`
convention). This is the natural 2-site projective measurement in the
Majorana-covariance-matrix (Γ) formalism used by the Gaussian backend (see
`QuantumCircuitsMPS.parity_projection_upsilon`).

Like `Measure`, `BondParity` Born-samples via the `:born_measurement` RNG
stream (`is_measurement(::BondParity) = true`) and collapses the state.

Only supported on `backend=:gaussian`: `BondParity` has no dense
`gate_matrix`/`build_operator` representation, so applying it on the MPS or
state-vector backends throws an `ArgumentError`.
"""
struct BondParity <: AbstractGate end

support(::BondParity) = 2
is_measurement(::BondParity) = true  # Born-samples via :born_measurement, like Measure

"""
    _apply_single!(state::SimulationState, gate::BondParity, phy_sites::Vector{Int})

Generic (MPS/state-vector-backend) rejection fallback: `BondParity` has no
`gate_matrix`/`build_operator` representation and is only implemented on
`backend=:gaussian`. A later task adds the Gaussian-specific
`_apply_single!`/`execute!` override (more specific on `state`), which
Julia's dispatch prefers whenever the state actually uses `GaussianBackend`.
The `CliffordBackend`'s own `AbstractGate` fallback independently rejects
`BondParity` on the Clifford backend with its own message.
"""
function _apply_single!(state::SimulationState, gate::BondParity, phy_sites::Vector{Int})
    throw(ArgumentError(
        "BondParity is only supported on backend=:gaussian. " *
        "Received backend $(typeof(state.backend)). " *
        "Use SimulationState(...; backend=:gaussian) or a different gate."
    ))
end

# === Disambiguating overrides ===
# StateVectorBackend and CliffordBackend each define their OWN
# `_apply_single!(state::SimulationState{TheirBackend}, gate::AbstractGate, ...)`
# catch-all (specializing on `state`'s type parameter only), which is
# neither more nor less specific than the generic-`state`/`BondParity`-
# specific method above (specializing on `gate`'s type only) — an ambiguous
# pair for exactly those two backends (verified via
# `Test.detect_ambiguities`). Explicit methods here, specializing on BOTH
# `state`'s type parameter AND `gate`'s type, resolve the ambiguity by being
# strictly more specific than both competing methods. `MPSBackend` has no
# such catch-all (the generic `Core/apply.jl` fallback IS its implementation)
# and `GaussianBackend` has no catch-all yet either, so neither needs an
# override here.
function _apply_single!(state::SimulationState{StateVectorBackend}, gate::BondParity, phy_sites::Vector{Int})
    throw(ArgumentError(
        "BondParity is only supported on backend=:gaussian. " *
        "Received backend $(typeof(state.backend)). " *
        "Use SimulationState(...; backend=:gaussian) or a different gate."
    ))
end

function _apply_single!(state::SimulationState{CliffordBackend}, gate::BondParity, phy_sites::Vector{Int})
    throw(ArgumentError(
        "BondParity is only supported on backend=:gaussian. " *
        "Received backend $(typeof(state.backend)). " *
        "Use SimulationState(...; backend=:gaussian) or a different gate."
    ))
end
