```@meta
CurrentModule = QuantumCircuitsMPS
```

# Gates

Unitary and non-unitary (measurement/projection) single- and two-site
operations, plus the spin-sector projector/measurement machinery for AKLT-
style protocols.

To define your own gate type, see [Custom Gates](@ref).

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
