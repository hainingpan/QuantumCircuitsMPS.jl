# === Magnetization for GaussianBackend ===
# ⟨Zᵢ⟩ from the on-site covariance element, mirroring the Clifford backend's
# `2·P(0) − 1` definition exactly (src/Clifford/magnetization.jl) so
# cross-backend semantics agree for the same ProductState.

"""
    (m::Magnetization)(state::SimulationState{GaussianBackend}) -> Float64

Gaussian (free-fermion covariance-matrix) implementation of the
`Magnetization` observable.

Under the package's fermionic-mode ↔ qubit dictionary, measurement outcome
`0` ↔ unoccupied and `1` ↔ occupied, so ⟨Zᵢ⟩ = P(0) − P(1) = 2·P(0) − 1 —
the SAME definition the Clifford backend computes via `born_probability`.
With the verified covariance convention (`Γ[2r−1, 2r] = +1` ↔ unoccupied,
`−1` ↔ occupied, i.e. ⟨cᵢ†cᵢ⟩ = (1 − Γ[2r−1, 2r])/2, hence
P(0) = (1 + Γ[2r−1, 2r])/2) this reduces to the direct element read

    ⟨Zᵢ⟩ = 2·P(0) − 1 = Γ[2r−1, 2r] = ⟨i γ_{2r−1} γ_{2r}⟩,

where `r = state.phy_ram[i]` (identity mapping on the Gaussian backend).
Magnetization is (1/L) Σᵢ ⟨Zᵢ⟩.

Only the `:Z` axis is supported on the Gaussian backend: `:X`/`:Y` are not
fermionic-parity-preserving single-mode observables (a single JW-transformed
X/Y is not Gaussian) and throw an informative `ArgumentError` — same pattern
as the Clifford backend (they pass the shared `Magnetization` struct's own
validation, but have no Gaussian implementation).
"""
function (m::Magnetization)(state::SimulationState{GaussianBackend})
    state.backend.majoranas_per_site == 1 && throw(ArgumentError(
        "Magnetization is not defined on a Majorana chain (site_type=\"Majorana\"): a " *
        "single Majorana site has no occupation/⟨Z⟩; use BondParity-based diagnostics or " *
        "fermionic-mode granularity (site_type=\"Qubit\") instead."))
    m.axis == :Z ||
        throw(ArgumentError("Magnetization for the Gaussian backend currently only supports :Z axis, got $(m.axis)"))
    Γ = state.backend.corr
    Γ === nothing && throw(ArgumentError(
        "Gaussian state is not initialized — call initialize!(state, ...) before computing observables."))

    L = state.L
    total = 0.0
    for site in 1:L
        a, b = site_majoranas(state, site)  # fermionic: (2r−1, 2r)
        total += Γ[a, b]   # = ⟨Zᵢ⟩ = 2·P(outcome 0) − 1
    end
    return total / L
end
