# Clifford Backend

`QuantumCircuitsMPS.jl` also ships a stabilizer-tableau backend, built on [QuantumClifford.jl](https://github.com/QuantumSavory/QuantumClifford.jl), for circuits built entirely out of Clifford-group gates. Instead of an MPS or a dense state vector, the state is stored as a `MixedDestabilizer` tableau, a compact `O(L)`-generator representation that only Clifford operations can update. `apply!`, `track!`, `record!`, and `simulate!` all work exactly as on the other two backends; only the `SimulationState(...)` constructor call changes.

**When to use it**: MIPT/CIPT studies that only need Clifford gates (Pauli twirls, random Clifford circuits, stabilizer measurements) and want to reach system sizes `L = 100-1000+`, far beyond what MPS or the state-vector backend can practically reach.

**When not to use it**: any circuit that needs a non-Clifford gate, `HaarRandom`, `Rx`/`Ry`/`Rz`, `MatrixGate`, or a general `Projection`/`SpinSectorProjection`. Use `backend=:mps` (see [MPS Backend](@ref)) or `backend=:statevector` (see [State Vector Backend](@ref)) for those. The Clifford backend is also qubit-only — arbitrary spin-`S` sites (see [Arbitrary Spin-S Support](@ref)) are MPS/state-vector-only.

## Quick Example

```julia
using QuantumCircuitsMPS

# Stabilizer-tableau simulation: scales to L=100-1000+ qubits for Clifford-only circuits
L = 100
state = SimulationState(L=L, bc=:open, backend=:clifford,
    rng=RNGRegistry(gates_spacetime=1, gates_realization=2, born_measurement=3))
initialize!(state, ProductState(binary_int=0))
track!(state, :entropy => EntanglementEntropy(cut=L÷2))

apply!(state, RandomClifford(2), Bricklayer(:odd))
apply!(state, RandomClifford(2), Bricklayer(:even))
apply!(state, Measure(:Z), SingleSite(1))
record!(state)
println("Entropy after one layer + measurement: $(state.observables[:entropy][end])")
```

**Physics**: `RandomClifford(2)` draws an independent random two-qubit Clifford operator for each bond (from the `:gates_realization` stream) and applies it natively to the tableau, no dense matrix is ever built, so the entangling layer costs the same whether `L` is 8 or 800.

## Scalability

Unlike the state-vector backend's `2^L` memory or the MPS backend's bond-dimension-dependent cost, the stabilizer-tableau representation scales polynomially: `O(L²)` memory (`L` stabilizer generators, each an `L`-bit string) and `O(L²)`-`O(L³)` per gate or measurement update. In practice, a full even+odd `RandomClifford(2)` bricklayer sweep over all `L` qubits completes in well under a second at `L=500` or `L=1000` on a single core, sizes that are simply unreachable for a dense state vector (`2^500` amplitudes) and impractical for MPS once entanglement growth forces `maxdim` up.

| Backend | Memory scaling | Practical qubit range |
|---------|-----------------|------------------------|
| State vector | `2^L` (exponential) | `L ≲ 25-27` |
| MPS | Bond-dimension dependent (`maxdim`) | `L = 100+` |
| **Clifford** | `O(L²)` (polynomial) | **`L = 100-1000+`** |

## Supported Gates

| Category | Gates |
|----------|-------|
| Single-qubit Clifford | `PauliX()`, `PauliY()`, `PauliZ()`, `Hadamard()`, `PhaseGate()` |
| Two-qubit Clifford | `CZ()`, `CNOT()`, `SWAP()` |
| Random Clifford | `RandomClifford(n)` — an `n`-qubit random Clifford operator, sampled from `:gates_realization` and applied natively to the tableau |
| Measurement & feedback | `Measure(:Z; feedback=...)`, `Reset()`, `OnOutcome(...)`, closure feedback — identical semantics to the MPS/state-vector backends |

Observable coverage: `EntanglementEntropy`, `Magnetization(:Z)`, `BornProbability`, `PauliString`, and `MutualInformation` all work on the Clifford backend (poly-time via the stabilizer formalism). `StringOrder` and `DomainWall` are MPS/state-vector only and raise an informative `ArgumentError` on Clifford states — see the [Backend Interface Contract](@ref)'s observable support matrix.

## Gate Validation

Any gate outside the supported set, `HaarRandom`, `Rx`/`Ry`/`Rz`, `MatrixGate`, `Projection`, `SpinSectorProjection`, has no stabilizer-tableau representation and raises an informative error rather than being silently approximated:

```julia
using QuantumCircuitsMPS

state = SimulationState(L=4, bc=:open, backend=:clifford,
    rng=RNGRegistry(gates_spacetime=1, gates_realization=2, born_measurement=3))
initialize!(state, ProductState(binary_int=0))
apply!(state, HaarRandom(), SingleSite(1))
```
```
ArgumentError: Clifford backend only supports Clifford gates (PauliX, PauliY, PauliZ, Hadamard, PhaseGate, CZ, CNOT, SWAP, RandomClifford, Measure, Reset). Received: HaarRandom. Please switch to backend=:mps or backend=:statevector for non-Clifford gates.
```

## Entanglement Spectrum

Stabilizer states have an exactly flat entanglement spectrum: for any bipartition, every nonzero Schmidt coefficient has the same magnitude. As a direct consequence, every Rényi-n entropy, including the von Neumann limit, is identical for a stabilizer state, so the `renyi_index` keyword on `EntanglementEntropy` is automatically satisfied for any value:

```julia
using QuantumCircuitsMPS

state = SimulationState(L=4, bc=:open, backend=:clifford,
    rng=RNGRegistry(gates_spacetime=1, gates_realization=2, born_measurement=3))
initialize!(state, ProductState(binary_int=0))
apply!(state, Hadamard(), SingleSite(1))
apply!(state, CNOT(), Sites([1,2]))
apply!(state, CNOT(), Sites([2,3]))
apply!(state, CNOT(), Sites([3,4]))  # GHZ state
for r in (1, 2, 3, 5)
    println("renyi_index=$r -> S = $(EntanglementEntropy(cut=2, renyi_index=r)(state))")
end
```
```
renyi_index=1 -> S = 1.0
renyi_index=2 -> S = 1.0
renyi_index=3 -> S = 1.0
renyi_index=5 -> S = 1.0
```

## Cross-Backend RNG Reproducibility (Redundant Draw)

Every measurement consumes **exactly one** `:born_measurement` draw per
measured site — on the Clifford backend just like on MPS and state-vector.
This is a deliberate **redundant draw**: for a stabilizer state the tableau
often fixes the outcome in advance (probability exactly 0 or 1), and in that
deterministic case the drawn value is simply **discarded**. The draw is made
anyway so that the `:born_measurement` stream position advances identically
on all three backends.

This redundancy is what buys *absolute* cross-backend reproducibility: with
the same `RNGRegistry` seeds, the measurement record (sites, outcomes, and
every downstream stochastic branch) is identical whether you run the circuit
on the Clifford, MPS, or state-vector backend. You can prototype at small
`L` on the exact state-vector backend, then rerun the *same seeded
trajectory* at `L = 1000` on Clifford.

!!! warning "One-time historical break (pre-v0.4.0 Clifford seeds)"
    Before v0.4.0, the Clifford backend skipped the draw entirely for
    deterministic outcomes, so its stream position drifted ahead of MPS/SV
    after the first deterministic measurement. Seeded Clifford trajectories
    generated with earlier versions are therefore **not reproducible** under
    the current contract. This was a deliberate one-time break in favor of
    the cross-backend guarantee above; see CHANGELOG 0.4.0.

See the [Backend Interface Contract](@ref)'s `_measure_single_site!` section
for the full contract wording.
