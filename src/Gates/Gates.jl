"""
    AbstractGate

Abstract base type for all quantum gates (unitaries, projections, and
measurement-like operations).

A gate type plugs into the backends through a small protocol:

- `support(gate) -> Int`: number of sites the gate acts on (required).
- `build_operator(gate, site_or_sites, local_dim; kwargs...) -> ITensor`:
  operator construction for the MPS backend.
- `gate_matrix(gate) -> Matrix{ComplexF64}`: dense matrix for the
  state-vector backend (random gates use `gate_matrix(gate, rng; local_dim)`).
- `needs_normalization(gate) -> Bool` (trait, default `false`): `true` for
  non-unitary gates (e.g. `Projection`) — backends renormalize (and, for
  MPS, truncate) after applying such a gate.
- `is_measurement(gate) -> Bool` (trait): `true` for gates that Born-sample
  via the `:born_measurement` RNG stream (e.g. `Measure`, `Reset`).
- Gates with non-operator semantics (Born sampling + classical feedback)
  override `execute!(state, gate, region)` instead — see `Measure` in
  `src/Core/apply.jl`.

The Clifford backend supports only Clifford-group gates, via per-gate
`_apply_single!` methods; any other gate is rejected with an
`ArgumentError` (see `src/Clifford/Clifford.jl`).
"""
abstract type AbstractGate end

"""
    support(gate::AbstractGate) -> Int

Return the number of sites this gate acts on (1 for single-qubit, 2 for two-qubit).
"""
function support end

"""
    build_operator(gate, site_or_sites, local_dim; kwargs...) -> ITensor

Build the operator tensor for a gate acting on given site(s).
"""
function build_operator end

# === Gate traits (v0.1 execute! protocol) ===
# Method-based traits replace hardcoded gate-type checks in the engine.
# User-defined gates opt in by adding a method, e.g.:
#     QuantumCircuitsMPS.needs_normalization(::MyGate) = true

"""
    needs_normalization(gate::AbstractGate) -> Bool

Trait: does applying this gate require renormalizing (and truncating) the MPS
afterwards? Default `false` (unitaries preserve the norm).

`true` for projective/collapsing gates (`Projection`, `SpinSectorProjection`,
`SpinSectorMeasurement`). User-defined non-unitary gates opt in with:

```julia
QuantumCircuitsMPS.needs_normalization(::MyProjectiveGate) = true
```

Renormalization is only possible when the gate leaves something to
renormalize: if the applied operator annihilates the state (a postselection
onto an outcome of zero Born probability), the backends throw an
`ArgumentError` and leave the state unchanged — see
[`POSTSELECTION_PROB_TOL`](@ref).
"""
needs_normalization(::AbstractGate) = false

@doc raw"""
    POSTSELECTION_PROB_TOL

Smallest squared norm ``\lVert P\psi\rVert^2`` a gate with
`needs_normalization(gate) == true` may leave behind (`1e-14`). For a
normalized input ``\lVert P\psi\rVert^2`` is the Born probability of the
requested branch; below this threshold there is no normalized conditional
state (renormalizing would only amplify rounding noise into a fake state), so
the MPS and state-vector backends reject the operation with an
`ArgumentError` and leave the state unchanged — see
[`_check_postselection`](@ref). `SpinSectorMeasurement` applies the same
threshold to the total probability of its allowed sectors.
"""
const POSTSELECTION_PROB_TOL = 1e-14

@doc raw"""
    _check_postselection(norm2::Real, gate::AbstractGate, sites::Vector{Int})

Guard shared by the MPS and state-vector `_apply_single!` methods for gates
with `needs_normalization(gate) == true`: `norm2` is the squared norm
``\lVert P\psi\rVert^2`` of the state *after* applying `gate` on the physical
`sites`. Throws an `ArgumentError` naming the gate, the sites, and `norm2`
when it is below [`POSTSELECTION_PROB_TOL`](@ref); returns `nothing`
otherwise. Callers run it before committing the new tensors/vector, so a
rejected gate leaves the state exactly as it was.
"""
function _check_postselection(norm2::Real, gate::AbstractGate, sites::Vector{Int})
    norm2 < POSTSELECTION_PROB_TOL || return nothing
    # Name the gate by value when that is short (`Projection(1)`); by type
    # when the value would dump a matrix (SpinSectorProjection, MatrixGate).
    label = repr(gate)
    length(label) <= 48 || (label = string(typeof(gate)))
    throw(ArgumentError(
        "$label on site(s) $(sites) annihilates the state: ‖Pψ‖² = $(norm2) < " *
        "$(POSTSELECTION_PROB_TOL), i.e. the requested outcome has zero Born " *
        "probability, so no normalized post-selected state exists. The state is unchanged."))
end

"""
    is_measurement(gate::AbstractGate) -> Bool

Trait: does this gate perform a Born-rule measurement (consuming the
`:born_measurement` RNG stream and collapsing the state)? Default `false`.

`true` for `Measurement` and `SpinSectorMeasurement`. Note `Reset` is a
derived operation (measure + conditional flip) implemented via its own
`execute!` method; it reports `false` here because the gate as a whole is a
deterministic-outcome channel, not an outcome-reporting measurement.
"""
is_measurement(::AbstractGate) = false

# Include gate implementations
include("matrix_gate.jl")    # defines gate_matrix — MUST come before single_qubit.jl/two_qubit.jl which add methods to it
include("single_qubit.jl")
include("two_qubit.jl")
include("random_clifford.jl")
include("parametrized.jl")
include("composite.jl")
include("feedback.jl")       # Measure + AbstractFeedback/OnOutcome/CallbackFeedback (v0.1)
include("spin_projectors.jl")
include("spin_measurement.jl")
include("gaussian_haar.jl")  # GaussianHaar: type + generic MPS/SV rejection (backend=:gaussian only)
include("bond_parity.jl")    # BondParity: type + generic MPS/SV rejection (backend=:gaussian only)
