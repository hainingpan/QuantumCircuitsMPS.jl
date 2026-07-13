# === Gaussian backend: clean rejections for observables with no fermionic- ===
# === Gaussian (covariance-matrix) implementation                            ===
#
# StringOrder and DomainWall are formulated as MPS/MPO-style tensor
# contractions (Sz expectation strings / projector-product MPOs). PauliString
# is a qubit MPS/state-vector/stabilizer expectation value with no
# fermionic-Gaussian (covariance-matrix) formula implemented (a Pfaffian-based
# approach is conceivable future work — intentionally NOT implemented here).
# Correlator and MagnetizationFluctuations are pure COMPOSITIONS of
# PauliString evaluations (see `src/Observables/correlator.jl` and
# `src/Observables/magnetization_fluctuations.jl`), so they inherit
# PauliString's non-support permanently — they are rejected explicitly here
# (rather than left to fall through to the nested PauliString rejection) so
# the error names the actually-requested observable, not an internal
# implementation detail.
#
# The GaussianBackend has no `mps`/`sites` fields, so without an explicit
# method here, calling any of these five observables on a
# `SimulationState{GaussianBackend}` would silently fall through to the
# MPS-typed generic implementations in `src/Observables/*.jl` and crash with
# a raw field-access error (`type GaussianBackend has no field mps`) instead
# of an informative message — this exact failure mode previously happened
# for the Clifford backend (see `src/Clifford/observables.jl` and
# `.sisyphus/notepads/v04-findings.md`, T9 findings), motivating exhaustive
# rejection coverage here. These typed overrides intercept the call before
# the generic runs, mirroring `src/Clifford/observables.jl`'s style.
#
# NOT rejected here (handled elsewhere, do not add a Gaussian rejection for
# these — see .sisyphus/notepads/gaussian-backend/learnings.md, Task 12):
#   - BornProbability: `born_probability(state::SimulationState{GaussianBackend}, ...)`
#     implemented in `src/Gaussian/measurement.jl` (T8).
#   - EntanglementEntropy, Magnetization: pending a Gaussian-specific
#     covariance-matrix override (T10) — NOT yet landed as of this task, but
#     intentionally left unrejected since they are permanently supportable
#     (not deferred/rejected) fermionic-Gaussian quantities.
#   - EntropyProfile: a pure composition of EntanglementEntropy — no
#     rejection needed; it will work automatically once T10's
#     EntanglementEntropy override lands (composition, not its own
#     backend-specific code).
#   - MutualInformation, TripartiteMutualInformation: reserved for a future
#     task (T11) that will add real Gaussian (covariance-matrix subsystem
#     entropy) implementations — explicitly NOT rejected here per this
#     task's instructions, even though no Gaussian override exists yet.

"""
    (obs::StringOrder)(state::SimulationState{GaussianBackend})

`StringOrder` is not supported on the Gaussian (fermionic covariance-matrix)
backend: its formula requires spin-1 Sz-expectation-string MPO/MPS
contractions with no native fermionic-Gaussian representation. Throws an
informative `ArgumentError` naming the required backends instead of
crashing on a missing `mps` field.
"""
function (obs::StringOrder)(state::SimulationState{GaussianBackend})
    throw(ArgumentError(
        "StringOrder is not supported on the Gaussian backend: " *
        "its formula requires spin-1 Sz-expectation-string MPO/MPS contractions, " *
        "which have no native fermionic-Gaussian (covariance-matrix) representation. " *
        "Please use backend=:mps or backend=:statevector for StringOrder."
    ))
end

"""
    (dw::DomainWall)(state::SimulationState{GaussianBackend}, i1::Union{Int, Nothing}=nothing)

`DomainWall` is not supported on the Gaussian (fermionic covariance-matrix)
backend: its formula requires projector-product MPO/MPS-style expectation
values, which have no native fermionic-Gaussian implementation. Throws an
informative `ArgumentError` naming the required backends instead of
crashing on a missing `sites` field.
"""
function (dw::DomainWall)(state::SimulationState{GaussianBackend}, i1::Union{Int, Nothing} = nothing)
    throw(ArgumentError(
        "DomainWall is not supported on the Gaussian backend: " *
        "its formula requires projector-product MPO/MPS-style expectation values, " *
        "which have no native fermionic-Gaussian (covariance-matrix) implementation. " *
        "Please use backend=:mps or backend=:statevector for DomainWall."
    ))
end

"""
    (obs::PauliString)(state::SimulationState{GaussianBackend})

`PauliString` is not supported on the Gaussian (fermionic covariance-matrix)
backend: Pauli-string expectation values require a qubit MPS/state-vector/
stabilizer representation with no native fermionic-Gaussian implementation
(a Pfaffian-based formula is conceivable future work, deliberately not
implemented here). Throws an informative `ArgumentError` naming the
required backends instead of crashing on a missing `mps`/`sites` field.
"""
function (obs::PauliString)(state::SimulationState{GaussianBackend})
    throw(ArgumentError(
        "PauliString is not supported on the Gaussian backend: " *
        "Pauli-string expectation values require a qubit MPS/state-vector/stabilizer " *
        "representation, which has no native fermionic-Gaussian (covariance-matrix) " *
        "implementation. Please use backend=:mps or backend=:statevector for PauliString."
    ))
end

"""
    (c::Correlator)(state::SimulationState{GaussianBackend})

`Correlator` is not supported on the Gaussian backend: it is a pure
composition of `PauliString` expectation values (see
`src/Observables/correlator.jl`), which are themselves not supported on
this backend. Throws an informative `ArgumentError` naming `Correlator`
directly, rather than deferring to the nested `PauliString` rejection.
"""
function (c::Correlator)(state::SimulationState{GaussianBackend})
    throw(ArgumentError(
        "Correlator is not supported on the Gaussian backend: " *
        "it is composed of PauliString expectation values, which have no " *
        "native fermionic-Gaussian (covariance-matrix) implementation. " *
        "Please use backend=:mps or backend=:statevector for Correlator."
    ))
end

"""
    (vm::MagnetizationFluctuations)(state::SimulationState{GaussianBackend})

`MagnetizationFluctuations` is not supported on the Gaussian backend: it is
a pure composition of `PauliString` expectation values (see
`src/Observables/magnetization_fluctuations.jl`), which are themselves not
supported on this backend. Throws an informative `ArgumentError` naming
`MagnetizationFluctuations` directly, rather than deferring to the nested
`PauliString` rejection.
"""
function (vm::MagnetizationFluctuations)(state::SimulationState{GaussianBackend})
    throw(ArgumentError(
        "MagnetizationFluctuations is not supported on the Gaussian backend: " *
        "it is composed of PauliString expectation values, which have no " *
        "native fermionic-Gaussian (covariance-matrix) implementation. " *
        "Please use backend=:mps or backend=:statevector for MagnetizationFluctuations."
    ))
end
