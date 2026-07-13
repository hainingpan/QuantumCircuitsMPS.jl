```@meta
CurrentModule = QuantumCircuitsMPS
```

# API Reference

The public API is organized below by module area, mirroring the package's
source layout (`src/State/`, `src/Gates/`, `src/Geometry/`, `src/Observables/`,
`src/Circuit/`, `src/Core/rng.jl`). Every exported name appears in exactly one
section. Backend-specific implementation notes (which methods exist per
backend, which fall through to an MPS-assumed generic, RNG stream
obligations) live in the [Backend Interface Contract](@ref) developer page,
not here.

## State

Construction, initialization, and the opt-in event log.

```@docs
SimulationState
initialize!
ProductState
RandomMPS
RandomStateVector
RandomGaussianState
events
measurements
```

## Backends

Backend-payload structs are internal (`MPSBackend`, `StateVectorBackend`,
`CliffordBackend` are accessed only via `state.backend` + duck typing, never
exported). `GaussianBackend` is a deliberate exception, exported so
`state.backend isa GaussianBackend` works with a plain `using
QuantumCircuitsMPS`. See the [Gaussian Backend](@ref) page for usage and the
[Backend Interface Contract](@ref) for the full struct/method contract.

```@docs
GaussianBackend
```

## RNG

Reproducible, independently-seeded RNG streams (see the
[Backend Interface Contract](@ref)'s [RNG expectations](@ref backend-interface-rng)
for the full stream table).

```@docs
RNGRegistry
get_rng
expected_draws
```

## Gates

Unitary and non-unitary (measurement/projection) single- and two-site
operations, plus the spin-sector projector/measurement machinery for AKLT-
style protocols.

```@docs
AbstractGate
PauliX
PauliY
PauliZ
Hadamard
PhaseGate
Rx
Ry
Rz
CZ
CNOT
SWAP
HaarRandom
RandomClifford
GaussianHaar
BondParity
MatrixGate
ProductGate
Projection
Reset
Measure
OnOutcome
total_spin_projector
verify_spin_projectors
SpinSectorProjection
SpinSectorMeasurement
```

## Geometry

Site-selection vocabulary — broadcast ("distribution") vs. set ("region")
geometries; see [Design Philosophy](@ref) for the conceptual split.

!!! note "1D only"
    All geometries address sites on a one-dimensional chain (`1:L`).
    Higher-dimensional (2D+) circuit geometries are a planned future
    direction — see the project
    [ROADMAP](https://github.com/hainingpan/QuantumCircuitsMPS.jl/blob/main/ROADMAP.md).

```@docs
AbstractGeometry
SingleSite
AdjacentPair
Sites
AllSites
EachSite
Bricklayer
StaircaseLeft
StaircaseRight
Pointer
move!
elements
element_count
is_broadcast
```

## Observables

Callable-struct observables (`obs(state)`), tracked via `track!`/`record!`.
See [Observables Catalog](@ref) below for a backend-support summary of the
new v0.4.0 observables, and [Custom Observables](@ref) for writing your own.

```@docs
AbstractObservable
EntanglementEntropy
Magnetization
BornProbability
born_probability
StringOrder
DomainWall
PauliString
MutualInformation
Correlator
EntropyProfile
TripartiteMutualInformation
MagnetizationFluctuations
track!
record!
list_observables
```

### Observables Catalog

New in v0.4.0: `PauliString` and `MutualInformation` (T24/T25), plus four
observables composed on top of them (T38). All six are supported on **all
three backends** (MPS, state vector, Clifford):

| Observable | Formula | Backend notes |
|---|---|---|
| [`PauliString`](@ref) | ``\langle \textstyle\prod_k P_k \rangle`` for a product of single-qubit Paulis on distinct sites | Qubit-only; MPS via local `op` insertion, SV via direct amplitude action, Clifford via `QuantumClifford.expect` (poly-time, exact ∈ {−1,0,+1}) |
| [`MutualInformation`](@ref) | ``I(A\!:\!B) = S(A)+S(B)-S(A\cup B)`` for two contiguous, disjoint regions | Physical-site regions on every backend, cross-backend unambiguous under both boundary conditions (unlike `EntanglementEntropy`'s PBC `cut`); MPS size-guarded at `d^{|A|+|B|} \le 256` |
| [`Correlator`](@ref) | ``C(i,j)=\langle P_iP_j\rangle-\langle P_i\rangle\langle P_j\rangle`` | Pure composition of three `PauliString` calls; `i == j` rejected |
| [`EntropyProfile`](@ref) | ``[S(\text{cut}=x)\ \text{for}\ x=1..L-1]`` (vector-valued) | Composition of `EntanglementEntropy` at every cut; inherits its MPS PBC RAM-bond caveat — use `bc=:open` for cross-backend comparison |
| [`TripartiteMutualInformation`](@ref) | ``I_3 = I(A\!:\!B)+I(A\!:\!C)-I(A\!:\!BC)`` (Gullans–Huse convention) | Composition of three `MutualInformation` calls; `B∪C` must be contiguous; standard MIPT usage is four quarters with a fourth region traced out |
| [`MagnetizationFluctuations`](@ref) | ``\mathrm{Var}(M)`` for ``M=\sum_{i\in R}P_i`` | ``O(\lvert R\rvert^2)`` composition of `PauliString`; diagonal ``P_i^2=I`` special-cased analytically |

Vector-valued observables (`EntropyProfile`) record through the same
`track!`/`record!`/`simulate!` pipeline as scalar ones — the storage
container transparently widens from `Vector{Float64}` to `Vector{Any}` at
the first vector-valued record (see [Custom Observables](@ref) and
`track!`'s docstring).

## Circuit

The lazy-mode `do`-block circuit builder, its expansion into a flat
operation list, and the eager/lazy gate-application entry points.

```@docs
apply!
apply_with_prob!
Circuit
expand_circuit
expand_circuit_grouped
simulate!
ExpandedOp
RecordingContext
every_n_gates
every_n_steps
print_circuit
plot_circuit
```

## Arbitrary Spin-S Support

New in v0.4.0 (T39): `SimulationState(...; site_type="S=k/2")` for any
half-integer or integer spin `S` up to `S=10`, on the MPS and state-vector
backends (`local_dim = 2S+1`). The Clifford backend remains qubit-only.

**The `"Z<m>"` label convention.** Basis states are indexed by two
equivalent coordinates:

- a **level index** `k = 0, 1, …, 2S` (0-based, descending magnetic
  quantum number), and
- the **magnetic quantum number** `m = S - k` (so level 0 = `m = +S`,
  level `2S` = `m = -S`).

`ProductState` initial-state labels and `Projection`/measurement outcomes
use the level index `k` (matching the qubit `"Proj0"`/`"Proj1"` convention
and the state-vector digit convention); `initialize!`'s `spin_state` keyword
and ITensors `state(...)` calls use the `"Z<m>"` string form, where `<m>` is
written as a plain integer for integer spins (`"Z1"`, `"Z0"`, `"Z-1"`) and as
a `<numerator>/2` fraction for half-integer spins (`"Z3/2"`, `"Z-1/2"`).
`"Up"`/`"Dn"` alias the two extremal levels (`m = +S` / `m = -S`) at every
spin. Per-level projector operators follow the same level-index naming:
`"Proj0"`, …, `"Proj$(2S)"`.

```julia
using QuantumCircuitsMPS

# Spin-3/2 chain: state_type "S=3/2" ⇒ local_dim = 4, levels 0..3 ↔ m = 3/2, 1/2, -1/2, -3/2
state = SimulationState(L=6, bc=:open, site_type="S=3/2",
    rng=RNGRegistry(gates_spacetime=1, gates_realization=2, born_measurement=3))
initialize!(state, ProductState(spin_state="Z1/2"))   # every site at level 1 (m = 1/2)

# Categorical (2S+1)-outcome measurement — same Measure(:Z) API as qubits
apply!(state, Measure(:Z), SingleSite(1))

# Sz-weighted Magnetization: ⟨Sz⟩ ∈ [-S, S] on spin sites (vs. ±1 Pauli convention on qubits)
Magnetization(:Z)(state)
```

`total_spin_projector(S; s=1)` and `SpinSectorProjection`/
`SpinSectorMeasurement` generalize the AKLT forced-measurement machinery to
arbitrary spin-`s` pairs (`s=1` keeps its original hardcoded S=0/1/2
projector polynomials for bitwise regression stability; `s≠1` uses the
Lagrange/Casimir eigenvalue-product formula) — see
[AKLT Example: Forced Measurement Protocol](@ref) in the tutorials for the
spin-1 case and the `Gates` section above for the full signatures.

## Developer Documentation

- [Backend Interface Contract](@ref) — the contract a new backend
  (`AbstractBackend` subtype) must satisfy: required methods, RNG stream
  rules, indexing conventions.
- [Custom Observables](@ref) — the `track!`-any-callable contract, public
  building blocks, and three worked examples (closure, composed struct,
  `record_value`-hook override).
- [Private / Internal API](@ref) — unexported names with docstrings, for
  contributors reading or extending the source.
