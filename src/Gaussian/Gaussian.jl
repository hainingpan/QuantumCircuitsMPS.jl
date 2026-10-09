# === Gaussian Gate-Application Engine (free-fermion covariance-matrix backend) ===
# _apply_single! methods dispatching each Gaussian-compatible gate directly
# onto the 2L×2L Majorana covariance matrix Γ (state.backend.corr):
#   - GaussianHaar: Haar-random O ∈ SO(4) conjugation on the 4 Majoranas of
#     the two target sites (DIRECT conjugation — exact for unitaries; the
#     Choi/contraction kernel `gaussian_contraction!` is reserved for
#     measurements).
#   - AbstractGate fallback: informative ArgumentError (mirrors the Clifford
#     backend's rejecting fallback in src/Clifford/Clifford.jl).
#   - Reset: rejected by a dedicated `execute!` override BEFORE the Born
#     draw (the generic Reset measures first and only then applies PauliX,
#     which this backend does not have — see the method's docstring).
#
# Qubit PauliX has no Gaussian implementation on purpose. The only
# occupation flip a covariance matrix can represent is the reflection of a
# single Majorana, i.e. conjugation by γ_{2i} — a parity-ODD operator. No
# closed fermionic system evolves under such a unitary (fermion-parity
# superselection), so it is rejected like every other non-Gaussian gate.
#
# DISPATCH NOTE: the AbstractGate catch-all below (specializing on `state`'s
# type parameter only) is AMBIGUOUS against any un-parameterized
# `_apply_single!(state::SimulationState, gate::SpecificGate, ...)` method
# (specializing on `gate`'s type only) — exactly the bug class previously hit
# by the StateVector/Clifford catch-alls vs the GaussianHaar/BondParity
# rejection fallbacks in src/Gates/gaussian_haar.jl & bond_parity.jl. The
# GaussianHaar implementation below resolves its pair automatically (it is
# strictly more specific than both); BondParity needs the explicit
# disambiguating method below. Verified via
# `Test.detect_ambiguities(QuantumCircuitsMPS; recursive=true)`.

@doc raw"""
    _apply_single!(state::SimulationState{GaussianBackend}, gate::GaussianHaar, phy_sites::Vector{Int})

Apply a Haar-random SO(n) Majorana rotation to the two sites in `phy_sites`,
where `n` is the total number of Majorana indices carried by the two sites
(resolved granularity-aware via [`site_majoranas`](@ref)):

- fermionic-mode granularity (default, `majoranas_per_site == 2`): the two
  sites carry 4 Majoranas `ix = [2a-1, 2a, 2b-1, 2b]` → Haar-``SO(4)``.
- Majorana-chain granularity (`site_type="Majorana"`,
  `majoranas_per_site == 1`): the two sites ARE two Majoranas `ix = [a, b]`
  → Haar-``SO(2)``. Haar on SO(2) is EXACTLY the uniform-angle rotation
  ``\exp(\theta\,\gamma_a\gamma_b)`` with ``\theta \sim U[0,2\pi)`` (``SO(2)\cong U(1)``, Haar = uniform angle) —
  the class-DIII unitary `K_U` of Pan, Shapourian, Jian, arXiv:2411.04191 (Eq. S-III.1; Python reference
  `GTN.measure_all_tri_op`'s `Υ = kraus((0, cos φ, sin φ))` branch). The
  φ ↔ rotation convention, matching the reference Python implementation
  (cross-checked in `test/gaussian/test_majorana_chain.jl`): contracting
  `kraus((0, cos φ, sin φ))` on the Majorana pair `(a, b)` equals direct
  conjugation ``\Gamma \leftarrow R\,\Gamma\,R^T`` with ``R = \begin{pmatrix}\cos\varphi & -\sin\varphi\\ \sin\varphi & \cos\varphi\end{pmatrix}`` on
  rows/columns `(a, b)` (exact to machine precision). Since ``\varphi \sim U[0,2\pi)``
  makes R uniform over SO(2), the two parameterizations define the SAME
  ensemble.

The orthogonal matrix `O = haar_orthogonal(rng, n)` is drawn from the
`:gates_realization` RNG stream (one draw per application, mirroring
`RandomClifford` on the Clifford backend) and conjugated DIRECTLY onto the
covariance matrix at the Majorana rows/columns `ix`:

```math
\Gamma[\mathrm{ix},:] = O\,\Gamma[\mathrm{ix},:] \\
\Gamma[:,\mathrm{ix}] = \Gamma[:,\mathrm{ix}]\,O^T
```

i.e. ``\Gamma \leftarrow R\,\Gamma\,R^T`` with ``R = O \oplus I`` — exact for Gaussian unitaries (no
contraction kernel involved). The result is re-antisymmetrized and, if the
purity diagnostic ``\max\lvert\mathrm{diag}(\Gamma^2)+1\rvert`` exceeds `state.backend.purify_tol`,
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

@doc raw"""
    execute!(state::SimulationState{GaussianBackend}, gate::Reset, region::Vector{Int})

Always throws an `ArgumentError`: `Reset` is not available on the Gaussian
backend, on either site granularity.

`Reset` is "measure, then `PauliX` if the outcome is 1", and the flip is
the problem. A covariance matrix can only flip one occupation by reflecting
a single Majorana (conjugation by ``\gamma_{2i}``), which is a parity-odd
operator: it changes the fermion parity of the state, something no closed
fermionic system can do. Rather than ship a flip that is physically
meaningless for fermions, both `PauliX` and `Reset` are rejected.

The generic `execute!(::SimulationState, ::Reset, ...)` in `src/Core/apply.jl`
would Born-sample the site FIRST and only then fail on `PauliX` (for
outcome 1 — and silently succeed for outcome 0). This override exists so the
rejection happens before anything changes: the covariance matrix and the
`:born_measurement` stream are untouched when it throws.

To project a mode onto a definite occupation use `Measure(:Z)` (random
outcome); to prepare an occupation pattern use `initialize!` with
`ProductState(bitstring=...)`. For the qubit `Reset`, use `backend=:mps` or
`backend=:statevector`.
"""
function execute!(state::SimulationState{GaussianBackend}, gate::Reset, region::Vector{Int})
    throw(ArgumentError(
        "Reset is not supported on the Gaussian backend (the state is unchanged): resetting " *
        "a fermionic mode would require a single-Majorana occupation flip, which is parity-odd " *
        "and not a fermionic Gaussian operation. The Gaussian backend supports GaussianHaar, " *
        "Measure(:Z), and BondParity only. Use Measure(:Z) for a projective occupation " *
        "measurement, ProductState(bitstring=...) to prepare an occupation pattern, or " *
        "backend=:mps / backend=:statevector for Reset."
    ))
end

"""
    _apply_single!(state::SimulationState{GaussianBackend}, gate::BondParity, phy_sites::Vector{Int})

Dispatch disambiguator (always throws). `BondParity` is a projective
measurement: on the Gaussian backend it is executed through the `execute!`
measurement protocol (Gaussian `execute!` override), never through the `_apply_single!` gate path. This method exists so
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
Hadamard, CNOT, Haar-random qubit unitaries, and PauliX — see the file
header) are not Gaussian and have no covariance-matrix representation.
Throws an informative `ArgumentError` naming the offending gate type and
suggesting the dense-backend alternatives.
"""
function _apply_single!(state::SimulationState{GaussianBackend}, gate::AbstractGate, phy_sites::Vector{Int})
    throw(ArgumentError(
        "Gaussian backend only supports fermionic Gaussian operations " *
        "(GaussianHaar, Measure(:Z), BondParity). " *
        "Received: $(typeof(gate)). " *
        "Please switch to backend=:mps or backend=:statevector for non-Gaussian gates."
    ))
end
