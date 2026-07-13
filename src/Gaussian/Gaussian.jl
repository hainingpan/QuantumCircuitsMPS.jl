# === Gaussian Gate-Application Engine (free-fermion covariance-matrix backend) ===
# _apply_single! methods dispatching each Gaussian-compatible gate directly
# onto the 2L×2L Majorana covariance matrix Γ (state.backend.corr):
#   - GaussianHaar: Haar-random O ∈ SO(4) conjugation on the 4 Majoranas of
#     the two target sites (DIRECT conjugation — exact for unitaries; the
#     Choi/contraction kernel `gaussian_contraction!` is reserved for
#     measurements, which a later task wires up).
#   - PauliX: fermionic occupation flip (single-Majorana reflection).
#   - AbstractGate fallback: informative ArgumentError (mirrors the Clifford
#     backend's rejecting fallback in src/Clifford/Clifford.jl).
#
# DISPATCH NOTE (see .sisyphus/notepads/gaussian-backend/learnings.md, Task 3
# follow-up fix): the AbstractGate catch-all below (specializing on `state`'s
# type parameter only) is AMBIGUOUS against any un-parameterized
# `_apply_single!(state::SimulationState, gate::SpecificGate, ...)` method
# (specializing on `gate`'s type only) — exactly the bug class previously hit
# by the StateVector/Clifford catch-alls vs the GaussianHaar/BondParity
# rejection fallbacks in src/Gates/gaussian_haar.jl & bond_parity.jl. The
# GaussianHaar implementation below resolves its pair automatically (it is
# strictly more specific than both); BondParity needs the explicit
# disambiguating method below. Verified via
# `Test.detect_ambiguities(QuantumCircuitsMPS; recursive=true)`.

"""
    _apply_single!(state::SimulationState{GaussianBackend}, gate::GaussianHaar, phy_sites::Vector{Int})

Apply a Haar-random SO(n) Majorana rotation to the two sites in `phy_sites`,
where `n` is the total number of Majorana indices carried by the two sites
(resolved granularity-aware via [`site_majoranas`](@ref)):

- fermionic-mode granularity (default, `majoranas_per_site == 2`): the two
  sites carry 4 Majoranas `ix = [2a-1, 2a, 2b-1, 2b]` → Haar-SO(4).
- Majorana-chain granularity (`site_type="Majorana"`,
  `majoranas_per_site == 1`): the two sites ARE two Majoranas `ix = [a, b]`
  → Haar-SO(2). Haar on SO(2) is EXACTLY the uniform-angle rotation
  `exp(θ γ_a γ_b)` with θ ~ U[0, 2π) (SO(2) ≅ U(1), Haar = uniform angle) —
  the class-DIII unitary `K_U` of Pan, Shapourian, Jian, arXiv:2411.04191 (Eq. S-III.1; Python reference
  `GTN.measure_all_tri_op`'s `Υ = kraus((0, cos φ, sin φ))` branch). The
  φ ↔ rotation convention, DERIVED EMPIRICALLY from the Python golden
  cross-check (test/gaussian/test_majorana_chain.jl): contracting
  `kraus((0, cos φ, sin φ))` on the Majorana pair `(a, b)` equals direct
  conjugation `Γ ← R Γ Rᵀ` with `R = [[cos φ, −sin φ], [sin φ, cos φ]]` on
  rows/columns `(a, b)` (exact to machine precision). Since φ ~ U[0, 2π)
  makes R uniform over SO(2), the two parameterizations define the SAME
  ensemble.

The orthogonal matrix `O = haar_orthogonal(rng, n)` is drawn from the
`:gates_realization` RNG stream (one draw per application, mirroring
`RandomClifford` on the Clifford backend) and conjugated DIRECTLY onto the
covariance matrix at the Majorana rows/columns `ix`:

    Γ[ix, :] = O · Γ[ix, :]
    Γ[:, ix] = Γ[:, ix] · Oᵀ

i.e. `Γ ← R Γ Rᵀ` with `R = O ⊕ I` — exact for Gaussian unitaries (no
contraction kernel involved). The result is re-antisymmetrized and, if the
purity diagnostic `max |diag(Γ²) + 1|` exceeds `state.backend.purify_tol`,
re-purified via [`purify!`](@ref).
"""
function _apply_single!(state::SimulationState{GaussianBackend}, gate::GaussianHaar, phy_sites::Vector{Int})
    if support(gate) != length(phy_sites)
        throw(ArgumentError("Gate support $(support(gate)) does not match sites $(length(phy_sites))"))
    end
    Γ = state.backend.corr
    Γ === nothing && throw(ArgumentError(
        "Gaussian state is not initialized — call initialize!(state, ...) before applying gates."))

    # Granularity-aware Majorana index resolution (fermionic: 4 indices →
    # SO(4); Majorana chain: 2 indices → SO(2)).
    ix = vcat(collect.((site_majoranas(state, phy_sites[1]),
                        site_majoranas(state, phy_sites[2])))...)

    rng = get_rng(state.rng_registry, :gates_realization)
    O = haar_orthogonal(rng, length(ix))

    Γ[ix, :] .= O * Γ[ix, :]
    Γ[:, ix] .= Γ[:, ix] * O'
    Γ .= (Γ .- transpose(Γ)) ./ 2

    if maximum(abs.(diag(Γ * Γ) .+ 1)) > state.backend.purify_tol
        purify!(Γ)
    end
    return nothing
end

"""
    _apply_single!(state::SimulationState{GaussianBackend}, gate::PauliX, phy_sites::Vector{Int})

Fermionic OCCUPATION FLIP on the single site in `phy_sites` — NOT the
Jordan-Wigner qubit Pauli-X. Implemented as the reflection of one on-site
Majorana: the sign of row and column `2i` of Γ is flipped (`i` = RAM index
of the site), which negates the on-site element `Γ[2i-1, 2i] = ⟨iγ_{2i-1}γ_{2i}⟩`
and therefore flips the occupation `⟨c†c⟩ = (1 - Γ[2i-1,2i])/2` between 0
and 1. A reflection `Γ ← RΓR` with `R = diag(1,…,-1,…,1)` is exactly
orthogonal, so the pure-state invariant `Γ² = -I` is preserved to machine
precision (no re-purification needed).

This is the operation that lets the generic `Reset` gate (measure, then
flip if occupied — `src/Core/apply.jl`) work on the Gaussian backend:
vacuum + `PauliX(site i)` ⇒ site `i` measures occupied with probability 1.

On the Majorana chain (`site_type="Majorana"`, `majoranas_per_site == 1`)
this throws an informative `ArgumentError`: a site is a single Majorana
mode and no single-Majorana occupation flip exists.
"""
function _apply_single!(state::SimulationState{GaussianBackend}, gate::PauliX, phy_sites::Vector{Int})
    if support(gate) != length(phy_sites)
        throw(ArgumentError("Gate support $(support(gate)) does not match sites $(length(phy_sites))"))
    end
    state.backend.majoranas_per_site == 1 && throw(ArgumentError(
        "PauliX is not defined on a Majorana chain (site_type=\"Majorana\"): a site is a " *
        "single Majorana mode and no single-Majorana occupation flip exists (occupation " *
        "lives on a PAIR of Majoranas). Use fermionic-mode granularity (site_type=\"Qubit\")."))
    Γ = state.backend.corr
    Γ === nothing && throw(ArgumentError(
        "Gaussian state is not initialized — call initialize!(state, ...) before applying gates."))

    i = last(site_majoranas(state, phy_sites[1]))  # second Majorana (2r) of the mode
    Γ[i, :] .*= -1
    Γ[:, i] .*= -1   # diagonal element Γ[i,i] is flipped twice — stays 0
    return nothing
end

"""
    _apply_single!(state::SimulationState{GaussianBackend}, gate::BondParity, phy_sites::Vector{Int})

Dispatch disambiguator (always throws). `BondParity` is a projective
measurement: on the Gaussian backend it is executed through the `execute!`
measurement protocol (Gaussian `execute!` override, added by the measurement
task), never through the `_apply_single!` gate path. This method exists so
the `AbstractGate` catch-all below (specializing on `state`'s type
parameter) is not ambiguous against the un-parameterized
`_apply_single!(state::SimulationState, gate::BondParity, ...)` rejection
fallback in `src/Gates/bond_parity.jl` (specializing on `gate`'s type) —
the same ambiguity bug class previously fixed for the StateVector/Clifford
backends (see the disambiguating overrides in that file).
"""
function _apply_single!(state::SimulationState{GaussianBackend}, gate::BondParity, phy_sites::Vector{Int})
    throw(ArgumentError(
        "BondParity is a projective measurement, not a unitary gate: on the " *
        "Gaussian backend it is executed via the `execute!` measurement " *
        "protocol, not the `_apply_single!` gate path."
    ))
end

"""
    _apply_single!(state::SimulationState{GaussianBackend}, gate::AbstractGate, phy_sites::Vector{Int})

Fallback for any gate NOT handled by one of the specific `_apply_single!`
methods above. The Gaussian (free-fermion covariance-matrix) backend can
only represent fermionic Gaussian operations; generic qubit gates (e.g.
Hadamard, CNOT, Haar-random qubit unitaries) are not Gaussian and have no
covariance-matrix representation. Throws an informative `ArgumentError`
naming the offending gate type and suggesting the dense-backend
alternatives.
"""
function _apply_single!(state::SimulationState{GaussianBackend}, gate::AbstractGate, phy_sites::Vector{Int})
    throw(ArgumentError(
        "Gaussian backend only supports fermionic Gaussian operations " *
        "(GaussianHaar, PauliX, Measure(:Z), BondParity, Reset). " *
        "Received: $(typeof(gate)). " *
        "Please switch to backend=:mps or backend=:statevector for non-Gaussian gates."
    ))
end
