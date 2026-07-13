# Gaussian Backend

`QuantumCircuitsMPS.jl` also ships a fermionic Gaussian (free-fermion / FLO — "fermionic linear optics") backend for circuits built entirely out of Gaussian-preserving gates and parity measurements. Instead of an MPS, a dense state vector, or a stabilizer tableau, the state is stored as a `2L×2L` real antisymmetric **Majorana covariance matrix** `Γ`, and gate/measurement application is a Schur-complement tensor contraction on `Γ` rather than any operation on a Hilbert-space vector. `apply!`, `track!`, `record!`, and `simulate!` all work exactly as on the other three backends; only the `SimulationState(...)` constructor call changes.

**When to use it**: circuits built entirely out of fermionic Gaussian unitaries and parity measurements — measurement-induced phase transitions in free-fermion (class-D/DIII) circuits, entanglement transitions with free fermions, and the staggered class-DIII Majorana-chain protocol of Pan et al. Polynomial-time simulation (`O(L³)` per gate), no truncation error, exact for any circuit depth.

**When not to use it**: any circuit that needs a non-Gaussian gate — `Hadamard`, `CNOT`, `HaarRandom`, `RandomClifford`, generic `Projection`, or anything from the qubit-gate vocabulary. Use `backend=:mps` (see [MPS Backend](@ref)) or `backend=:statevector` (see [State Vector Backend](@ref)) for those. The Gaussian backend is fermionic-mode-only (`local_dim=2`); arbitrary spin-`S` sites (see [Arbitrary Spin-S Support](@ref)) are MPS/state-vector-only.

## Quick Example

```julia
using QuantumCircuitsMPS

state = SimulationState(L=32, bc=:periodic, backend=:gaussian,
    rng=RNGRegistry(gates_spacetime=1, gates_realization=2, born_measurement=3, state_init=4))
initialize!(state, ProductState(binary_int=0))          # vacuum
apply!(state, GaussianHaar(), Bricklayer(:odd))          # random Gaussian circuit
apply!(state, Measure(:Z), SingleSite(5))                # on-site occupation parity measurement
apply!(state, BondParity(), AdjacentPair(3))             # bond parity measurement
track!(state, :entropy => EntanglementEntropy(cut=16))
record!(state)

entropies = state.observables[:entropy]
println("Final entropy: $(entropies[end])")
```

**Physics**: `GaussianHaar()` draws an independent Haar-random `O(4)`/`O(2)` rotation for each bond (from `:gates_realization`) and conjugates it directly onto the Majorana covariance matrix — no dense Hilbert-space unitary is ever built. `Measure(:Z)` and `BondParity()` are projective parity measurements of, respectively, the on-site occupation `iγ_{2i-1}γ_{2i}` and the bond parity spanning two adjacent sites; both collapse `Γ` via the same fermionic-linear-optics contraction kernel used for the unitary case.

## What a Gaussian State Is

A pure fermionic Gaussian state on `L` modes is completely characterized (no exponentially large amplitude vector needed) by its `2L×2L` real antisymmetric **Majorana covariance matrix**

```
Γ[a,b] = (i/2) ⟨[γ_a, γ_b]⟩ ,
```

where `γ_1, …, γ_{2L}` are the Majorana operators (`γ_{2i-1} = c_i + c_i†`, `γ_{2i} = i(c_i† - c_i)` for fermionic mode `i`, with a Jordan–Wigner string on lower-indexed modes). A pure Gaussian state satisfies the invariant

```
Γ² = -I
```

exactly (the eigenvalues of `iΓ` are all `±1`). Every gate and measurement in this backend updates `Γ` while preserving this invariant to machine precision; a re-purification step (`purify!` — eigen-clamp `iΓ`'s spectrum back to `±1`) fires automatically whenever floating-point drift exceeds `state.backend.purify_tol` (default `1e-10`).

## Supported Gates

| Category | Gate | Fermionic-mode (`site_type="Qubit"`, default) | Majorana chain (`site_type="Majorana"`) |
|---|---|---|---|
| Random Gaussian unitary | `GaussianHaar()` | Haar-random `O ∈ SO(4)` on the 4 Majoranas of 2 adjacent sites, from `:gates_realization` | Haar-random `O ∈ SO(2)` on the 2 Majoranas of 2 adjacent sites — exactly `exp(θ γ_iγ_j)`, `θ ~ U[0, 2π)` (the class-DIII unitary `K_U`) |
| Occupation flip | `PauliX()` | fermionic occupation-parity flip (reflects one Majorana row/column) — enables `Reset` | rejected: `ArgumentError` (a single Majorana site has no occupation to flip) |
| On-site measurement | `Measure(:Z)` | projective occupation-parity measurement `iγ_{2i-1}γ_{2i}` | rejected: `ArgumentError` (use `BondParity` instead) |
| Bond measurement | `BondParity()` | projective bond-parity measurement `iγ_{2i}γ_{2i+1}` between adjacent sites (PBC wrap `(L,1)` supported) | projective parity `iγ_iγ_{i+1}` between adjacent Majorana sites (PBC wrap supported) — this IS the class-DIII monitored measurement |
| Feedback | `Reset()` | forces unoccupied (measure, then `PauliX` if occupied) — identical semantics to the other backends | rejected: `ArgumentError` (routes through `Measure(:Z)`, which is rejected) |

Any gate outside this set — `Hadamard`, `CNOT`, `HaarRandom`, `RandomClifford`, `SWAP`, `PhaseGate`, `PauliY`, `PauliZ`, `CZ`, `Projection`, `SpinSectorProjection` — has no covariance-matrix representation and raises an informative error rather than being silently approximated:

```julia
using QuantumCircuitsMPS

state = SimulationState(L=4, bc=:open, backend=:gaussian,
    rng=RNGRegistry(gates_spacetime=1, gates_realization=2, born_measurement=3, state_init=4))
initialize!(state, ProductState(binary_int=0))
apply!(state, CNOT(), AdjacentPair(1))
```
```
ArgumentError: Gaussian backend only supports fermionic Gaussian operations (GaussianHaar, PauliX, Measure(:Z), BondParity, Reset). Received: CNOT. Please switch to backend=:mps or backend=:statevector for non-Gaussian gates.
```

`Measure(:Z)` and `Reset()` do **not** get their own `_apply_single!`/`execute!` overrides on the fermionic-mode granularity: `Measure` flows through the generic engine, which calls this backend's `born_probability` + `_measure_single_site!`; `Reset` composes `Measure` with `PauliX`. `BondParity` gets a dedicated `execute!` override (see [Backend Interface Contract](@ref)) because it measures two sites at once — outside the single-site `born_probability` contract.

## Majorana Chain (`site_type="Majorana"`)

A second site granularity turns each **site into one Majorana mode** rather than one fermionic mode (2 Majoranas). This models the class-DIII monitored Majorana-chain circuit of Pan, Shapourian, Jian et al. directly, with no new gate types: `GaussianHaar` on 2 Majorana sites *is* `exp(θγ_aγ_b)`, `θ ~ U[0,2π)` (Haar on `SO(2) ≅ U(1)` is exactly the uniform-angle rotation), and `BondParity` on 2 Majorana sites *is* the `iγ_iγ_{i+1}` parity measurement — the staggered odd/even-link protocol maps directly onto `Bricklayer(:odd)`/`Bricklayer(:even)`.

```julia
using QuantumCircuitsMPS

mstate = SimulationState(L=8, bc=:periodic, backend=:gaussian, site_type="Majorana",
    rng=RNGRegistry(gates_spacetime=1, gates_realization=2, born_measurement=3, state_init=4))
initialize!(mstate, ProductState(binary_int=0))
apply!(mstate, GaussianHaar(), Bricklayer(:odd))    # odd links: exp(θγγ), θ~U[0,2π)
apply!(mstate, BondParity(), Bricklayer(:even))     # even links: iγγ parity measurement
size(mstate.backend.corr)   # (8, 8) — Γ is L×L, not 2L×2L, on the Majorana chain
```

Key facts:

- `site_type="Majorana"` requires **even `L`** (a pure Gaussian state needs an even number of Majoranas): odd `L` throws `ArgumentError` at construction.
- `Γ` is `L×L` (one Majorana per site) instead of `2L×2L`.
- `ProductState` bit patterns have length `L÷2`: bit `k` sets the parity sign of the consecutive Majorana pair `(γ_{2k-1}, γ_{2k})` (dimerized vacuum when all bits are `0`).
- Rejected on the Majorana chain (informative `ArgumentError`, each naming "Majorana"): `PauliX`, `Measure(:Z)`, `Reset`, `Magnetization`. There is no single-Majorana occupation or `⟨Z⟩` — parity lives on a *pair*.
- `EntanglementEntropy`, `MutualInformation`, and `TripartiteMutualInformation` work unchanged (the site→Majorana index mapping is the identity on this granularity, and arbitrary/wrapped site subsets are still supported).

Physics sanity check on the dimerized vacuum (`ProductState(binary_int=0)`, all pairs unoccupied): even cuts see zero entanglement (the cut falls between dimerized pairs), odd cuts split a pair and see `log(2)/2` nats (half a fermion's worth), and two dimerized-paired Majorana sites have `MI = log(2)`:

```julia
using QuantumCircuitsMPS

mstate = SimulationState(L=8, bc=:periodic, backend=:gaussian, site_type="Majorana",
    rng=RNGRegistry(gates_spacetime=1, gates_realization=2, born_measurement=3, state_init=4))
initialize!(mstate, ProductState(binary_int=0))
EntanglementEntropy(cut=2, base=ℯ)(mstate)   # ≈ 0.0
EntanglementEntropy(cut=1, base=ℯ)(mstate)   # ≈ log(2)/2 ≈ 0.3466
MutualInformation([1], [2])(mstate)          # ≈ log(2) ≈ 0.6931
```

## Supported and Rejected Observables

| Observable | Fermionic-mode | Majorana chain | Notes |
|---|---|---|---|
| `EntanglementEntropy` | ✓ von Neumann only | ✓ | `renyi_index != 1` → `ArgumentError` (never silently falls back) |
| `Magnetization` | ✓ `:Z` only | ✗ `ArgumentError` | `:X`/`:Y` → `ArgumentError` on both granularities |
| `BornProbability` | ✓ | ✗ (via `born_probability` rejection) | non-destructive single-mode read |
| `MutualInformation` | ✓, incl. wrapped/non-contiguous regions | ✓, incl. wrapped/non-contiguous regions | von Neumann only; the only backend that accepts non-contiguous/PBC-wrapped region pairs |
| `TripartiteMutualInformation` | ✓ (composes `MutualInformation`) | ✓ | no Gaussian-specific code — composition "just works" |
| `EntropyProfile` | ✓ (composes `EntanglementEntropy`) | ✓ | no Gaussian-specific code |
| `StringOrder` | ✗ `ArgumentError` | ✗ `ArgumentError` | spin-1 Sz-string MPO formula, no fermionic-Gaussian analog |
| `DomainWall` | ✗ `ArgumentError` | ✗ `ArgumentError` | projector-product MPO/MPS formula |
| `PauliString` | ✗ `ArgumentError` | ✗ `ArgumentError` | qubit MPS/SV/stabilizer expectation; a Pfaffian-based formula is conceivable future work (see [ROADMAP.md](https://github.com/hainingpan/QuantumCircuitsMPS.jl/blob/main/ROADMAP.md)), not implemented |
| `Correlator` | ✗ `ArgumentError` | ✗ `ArgumentError` | pure composition of `PauliString` — permanently unsupported alongside it |
| `MagnetizationFluctuations` | ✗ `ArgumentError` | ✗ `ArgumentError` | pure composition of `PauliString` — same reasoning |

Every rejection is an informative `ArgumentError` naming the observable and suggesting `backend=:mps`/`:statevector` — never a raw field-access crash:

```julia
using QuantumCircuitsMPS

state = SimulationState(L=4, bc=:open, backend=:gaussian,
    rng=RNGRegistry(gates_spacetime=1, gates_realization=2, born_measurement=3, state_init=4))
initialize!(state, ProductState(binary_int=0))
StringOrder(1, 4)(state)
```
```
ArgumentError: StringOrder is not supported on the Gaussian backend: its formula requires spin-1 Sz-expectation-string MPO/MPS contractions, which have no native fermionic-Gaussian (covariance-matrix) representation. Please use backend=:mps or backend=:statevector for StringOrder.
```

## Example: Reproducing the Class-DIII Phase Diagram

[`examples/gaussian_example.ipynb`](https://github.com/hainingpan/QuantumCircuitsMPS.jl/blob/main/examples/gaussian_example.ipynb) reproduces Fig. 1b of Pan et al., "Topological Modes in Monitored Quantum Dynamics": the staggered class-DIII monitored Majorana chain, mutual information vs. measurement probability `p`, at demo system sizes finishing in a few minutes. It uses the Majorana-chain granularity documented above with `Bricklayer(:odd)`/`Bricklayer(:even)` staggering.

## Initialization

Three ways to prepare a Gaussian state, all via `initialize!`:

```julia
using QuantumCircuitsMPS, LinearAlgebra

mkstate() = SimulationState(L=4, bc=:open, backend=:gaussian,
    rng=RNGRegistry(gates_spacetime=1, gates_realization=2, born_measurement=3, state_init=4))

# 1. Vacuum: all modes unoccupied
s1 = mkstate(); initialize!(s1, ProductState(binary_int=0))
s1.backend.corr[1, 2]   # +1.0 (unoccupied convention)

# 2. Arbitrary occupation pattern (site 1 = MSB, same convention as every other backend)
s2 = mkstate(); initialize!(s2, ProductState(bitstring="0101"))   # sites 2, 4 occupied
s2.backend.corr[3, 4]   # -1.0 (occupied)

# 3. Haar-random pure Gaussian state
s3 = mkstate(); initialize!(s3, RandomGaussianState())
norm(s3.backend.corr * s3.backend.corr + I) < 1e-10   # true — purity holds
```

On the Majorana chain (`site_type="Majorana"`), `ProductState` bit patterns have length `L÷2` (one bit per dimerized Majorana pair — see the Majorana Chain section above) and `RandomGaussianState` draws `O ∈ SO(L)` instead of `SO(2L)`.

## Conventions

- **Mode ↔ Majorana mapping**: fermionic mode `i` (1-indexed) ↔ Majorana indices `(2i-1, 2i)`. On the Majorana chain, site `i` IS Majorana `i` directly.
- **Occupation sign**: `Γ[2i-1,2i] = +1` ↔ mode `i` unoccupied; `Γ[2i-1,2i] = -1` ↔ occupied — i.e. `⟨c_i†c_i⟩ = (1 - Γ[2i-1,2i])/2`. Verified empirically against the Python GTN reference implementation's `get_C_f`.
- **Measurement outcome**: `outcome = 0` ↔ unoccupied/parity `+1` result on `Γ`; `outcome = 1` ↔ occupied/parity `-1` result. `ProductState` bit `1` ↔ occupied, matching this convention.
- **Exact-Haar sampler note**: `haar_orthogonal` draws Haar-random `SO(n)` matrices exactly via QR decomposition of a Ginibre matrix (sign-fixed, det-corrected) — this is a **deliberate departure** from the Python GTN reference implementation, whose `get_O` uses `expm` of a random skew-symmetric matrix (an approximation the GTN codebase's own notes flag as not proven exactly Haar). All Gaussian-backend randomness (`GaussianHaar`, `RandomGaussianState`) uses the exact sampler.

## Cross-Backend RNG Reproducibility

Like the other three backends, every measurement (`Measure(:Z)` and `BondParity()`) consumes **exactly one** `:born_measurement` draw per measured site/bond — even for a deterministic outcome, where the draw is discarded (the REDUNDANT-DRAW CONTRACT; see the [Backend Interface Contract](@ref)). Random gate content (`GaussianHaar`) draws from `:gates_realization`; random initial states (`RandomGaussianState`) draw from `:state_init`. Same seeds ⇒ bitwise-identical `Γ` and identical measurement records, within the Gaussian backend:

```julia
using QuantumCircuitsMPS

mkrng(k) = RNGRegistry(gates_spacetime=k, gates_realization=k+10, born_measurement=k+20, state_init=k+30)

sA = SimulationState(L=6, bc=:open, backend=:gaussian, rng=mkrng(7))
initialize!(sA, ProductState(binary_int=0))
apply!(sA, GaussianHaar(), Bricklayer(:odd))

sB = SimulationState(L=6, bc=:open, backend=:gaussian, rng=mkrng(7))
initialize!(sB, ProductState(binary_int=0))
apply!(sB, GaussianHaar(), Bricklayer(:odd))

sA.backend.corr == sB.backend.corr   # true — bitwise identical
```

!!! note "Fermionic semantics are physically distinct — no cross-backend seed lockstep is claimed"
    Unlike MPS/state-vector/Clifford (which agree on the same seeded trajectory because they share the same qubit Hilbert space), the Gaussian backend simulates a *different physical system* (free fermions vs. qubits) and makes **no** claim of matching MPS/SV/Clifford measurement records under the same seeds. Self-reproducibility (same seed ⇒ same `Γ`, on the Gaussian backend) and the redundant-draw stream-position contract are the guarantees.

!!! warning "Purify/eigendecomposition platform caveat"
    Re-purification (`purify!`) eigendecomposes `Γ/i` via `LinearAlgebra.eigen`, which — like any LAPACK-backed eigensolver — can return eigenvectors in a platform/BLAS-dependent order or with an arbitrary sign/phase when eigenvalues are degenerate. This never affects the *physical* state (the reconstructed `Γ` is invariant), but it means bitwise reproducibility across different machines/BLAS backends is not guaranteed once `purify!` has fired (only same-machine, same-BLAS reproducibility is guaranteed) — the same caveat that applies to any eigendecomposition-based computation in this package.

## References

- The fermionic-linear-optics / Majorana-covariance-matrix formalism this backend implements: [bravyi2005lagrangian](@cite).
- The Haar-random `SO(2n)` Gaussian-unitary ensemble and the general contraction formula: [jian2022criticality](@cite); conventions follow [pan2025topological](@cite).
- The class-DIII staggered monitored Majorana-chain protocol reproduced by `examples/gaussian_example.ipynb`: [pan2025topological](@cite).


```@bibliography
Pages = [@__FILE__]
```
