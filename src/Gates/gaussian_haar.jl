# === GaussianHaar Gate (fermionic Gaussian backend) ===
# Type definition + generic (MPS/state-vector) rejection ONLY. The actual
# Gaussian-backend behavior (Haar-random SO(4) rotation on the Majorana
# covariance matrix) is added by a LATER task via a
# `_apply_single!(state::SimulationState{GaussianBackend}, gate::GaussianHaar, ...)`
# override, which Julia's method dispatch prefers over the generic fallback
# defined in this file (more specific on `state`'s type parameter).

"""
    GaussianHaar()

2-site fermionic Gaussian unitary gate: a Haar-random orthogonal rotation
`O ∈ SO(4)` acting on the 4 Majorana operators of the two sites (Majorana
indices `(2i-1, 2i, 2i+1, 2i+2)` for adjacent sites `i, i+1` — see
`QuantumCircuitsMPS.majorana_indices`), drawn from the `:gates_realization`
RNG stream via `QuantumCircuitsMPS.haar_orthogonal`.

This is the fermionic-Gaussian analog of a 2-qubit Haar-random unitary
(`HaarRandom(2)`), restricted to the Gaussian (free-fermion) subgroup that
preserves the Majorana-covariance-matrix (Γ) representation of the state —
see Jian, Bauer, Fisher (and related free-fermion measurement-induced-phase-
transition literature) for the covariance-matrix formalism this gate acts on.

Only supported on `backend=:gaussian`: `GaussianHaar` has no dense
`gate_matrix`/`build_operator` representation (the Gaussian backend never
materializes dense unitaries), so applying it on the MPS or state-vector
backends throws an `ArgumentError`.
"""
struct GaussianHaar <: AbstractGate end

support(::GaussianHaar) = 2

"""
    _apply_single!(state::SimulationState, gate::GaussianHaar, phy_sites::Vector{Int})

Generic (MPS/state-vector-backend) rejection fallback: `GaussianHaar` has no
`gate_matrix`/`build_operator` representation and is only implemented on
`backend=:gaussian`. A later task adds the Gaussian-specific
`_apply_single!(state::SimulationState{GaussianBackend}, ::GaussianHaar, ...)`
override; Julia's dispatch prefers that method (more specific on `state`)
over this fallback whenever the state actually uses `GaussianBackend`. The
`CliffordBackend`'s own `AbstractGate` fallback (`src/Clifford/Clifford.jl`)
independently rejects `GaussianHaar` on the Clifford backend with its own
message (more specific on `state` there too).
"""
function _apply_single!(state::SimulationState, gate::GaussianHaar, phy_sites::Vector{Int})
    throw(ArgumentError(
        "GaussianHaar is only supported on backend=:gaussian. " *
        "Received backend $(typeof(state.backend)). " *
        "Use SimulationState(...; backend=:gaussian) or a different gate."
    ))
end

# === Disambiguating overrides ===
# StateVectorBackend and CliffordBackend each define their OWN
# `_apply_single!(state::SimulationState{TheirBackend}, gate::AbstractGate, ...)`
# catch-all (specializing on `state`'s type parameter only), which is
# neither more nor less specific than the generic-`state`/`GaussianHaar`-
# specific method above (specializing on `gate`'s type only) — an ambiguous
# pair for exactly those two backends (verified via
# `Test.detect_ambiguities`). Explicit methods here, specializing on BOTH
# `state`'s type parameter AND `gate`'s type, resolve the ambiguity by being
# strictly more specific than both competing methods. `MPSBackend` has no
# such catch-all (the generic `Core/apply.jl` fallback IS its implementation)
# and `GaussianBackend` has no catch-all yet either, so neither needs an
# override here.
function _apply_single!(state::SimulationState{StateVectorBackend}, gate::GaussianHaar, phy_sites::Vector{Int})
    throw(ArgumentError(
        "GaussianHaar is only supported on backend=:gaussian. " *
        "Received backend $(typeof(state.backend)). " *
        "Use SimulationState(...; backend=:gaussian) or a different gate."
    ))
end

function _apply_single!(state::SimulationState{CliffordBackend}, gate::GaussianHaar, phy_sites::Vector{Int})
    throw(ArgumentError(
        "GaussianHaar is only supported on backend=:gaussian. " *
        "Received backend $(typeof(state.backend)). " *
        "Use SimulationState(...; backend=:gaussian) or a different gate."
    ))
end
