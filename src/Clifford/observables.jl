# === Clifford backend: clean rejections for observables with no stabilizer- ===
# === tableau implementation                                                 ===
#
# StringOrder and DomainWall are formulated as MPS/MPO-style tensor
# contractions (Sz expectation strings / projector-product MPOs). The
# Clifford (stabilizer-tableau) backend has no `mps`/`sites` fields, so
# without an explicit method here, calling either observable on a
# `SimulationState{CliffordBackend}` silently falls through to the
# MPS-typed generic implementations in
# `src/Observables/{string_order,domain_wall}.jl` and crashes with a raw
# field-access error (`type CliffordBackend has no field mps` for
# StringOrder; `... has no field sites` for DomainWall, via
# `compute_projector_product_expectation`) — see
# `.sisyphus/notepads/v04-findings.md` (T9 findings) for the exact observed
# messages. These typed overrides intercept the call before the generic
# runs, mirroring the informative-error style used for unsupported gates in
# `src/Clifford/Clifford.jl:162-168`.
#
# NOTE: DomainWall-on-Clifford (via stabilizer Born probabilities of
# projector products) is feasible future work — intentionally NOT
# implemented here; deferred to ROADMAP.md.

"""
    (obs::StringOrder)(state::SimulationState{CliffordBackend})

`StringOrder` is not supported on the Clifford (stabilizer-tableau) backend:
its formula requires spin-1 Sz-expectation-string MPO/MPS contractions with
no native stabilizer-tableau representation. Throws an informative
`ArgumentError` naming the required backends instead of crashing on a
missing `mps` field.
"""
function (obs::StringOrder)(state::SimulationState{CliffordBackend})
    throw(ArgumentError(
        "StringOrder is not supported on the Clifford (stabilizer-tableau) backend: " *
        "its formula requires spin-1 Sz-expectation-string MPO/MPS contractions, " *
        "which have no native stabilizer-tableau representation. " *
        "Please use backend=:mps or backend=:statevector for StringOrder."
    ))
end

"""
    (dw::DomainWall)(state::SimulationState{CliffordBackend}, i1::Union{Int, Nothing}=nothing)

`DomainWall` is not yet implemented for the Clifford (stabilizer-tableau)
backend: its formula requires projector-product MPO/MPS-style expectation
values, which have no native stabilizer-tableau implementation today.
Throws an informative `ArgumentError` naming the required backends instead
of crashing on a missing `sites` field.
"""
function (dw::DomainWall)(state::SimulationState{CliffordBackend}, i1::Union{Int, Nothing} = nothing)
    throw(ArgumentError(
        "DomainWall is not yet implemented for the Clifford (stabilizer-tableau) backend: " *
        "its formula requires projector-product MPO/MPS-style expectation values, " *
        "which have no native stabilizer-tableau implementation today. " *
        "Please use backend=:mps or backend=:statevector for DomainWall."
    ))
end
