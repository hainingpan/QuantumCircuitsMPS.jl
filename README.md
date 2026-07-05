[![Julia 1.11+](https://img.shields.io/badge/Julia-1.11%2B-blue)](https://julialang.org/)
[![License: BSD-3-Clause](https://img.shields.io/badge/License-BSD--3--Clause-green.svg)](LICENSE)

# QuantumCircuitsMPS.jl

**MPS-based quantum circuit simulation for MIPT/CIPT research**

MIPT (Measurement-Induced Phase Transition) and CIPT (Control-Induced Phase Transition) are emergent phenomena in monitored quantum circuits where feedback, measurements, and unitary dynamics compete to create distinct entanglement phases.

---
## What is QuantumCircuitsMPS.jl?

- **"PyTorch for Quantum Circuits"** — Physicists code as they speak: focusing on physics without touching implementation details.
- A pure Julia library for simulating quantum circuits using Matrix Product State (MPS) methods, with an exact state-vector backend and a stabilizer-tableau (Clifford) backend alongside it. It's purpose-built for researchers studying measurement-induced and control-induced phase transitions in monitored quantum systems.

> ⚠️ **Note**: This package is under active development. APIs may change and bugs may exist. Please report issues on [GitHub](https://github.com/hainingpan/QuantumCircuitsMPS.jl/issues).

**Why use this package?**

1. **Pure Julia MPS simulation**: Native Julia performance with ITensors.jl backend, scaling to 100+ qubits.
2. **Physics-first API**: Write circuits using intuitive abstractions (Gates + Geometry) without managing MPS bond dimensions, index orderings, or truncation schemes. The library handles tensor network details internally.
3. **Reproducible randomness**: Independent RNG streams for each source (`:gates_spacetime`, `:gates_realization`, `:born_measurement`, `:state_init`) enable reproducible trajectories. Useful in cross entropy benchmark and study quantum flucutuations.

**Philosophy**: Users write `apply!(state, HaarRandom(), Bricklayer(:odd))` and never see ITensor index objects, SVD calls, or orthogonalization centers. The package manages the gap between high-level physics intent and low-level tensor manipulations.

---
## Why QuantumCircuitsMPS.jl?

### Comparison with Existing Julia Quantum Libraries

| Feature | ITensors.jl | PastaQ.jl | Yao.jl | Qiskit.jl | **This Package** |
|---------|-------------|-----------|--------|-----------|------------------|
| **Primary Focus** | Tensor networks | Tomography & benchmarking | Variational algorithms | Circuit construction | **MIPT/CIPT dynamics** |
| **Backend** | MPS/MPO (via ITensorMPS) | MPS/MPO | State vector (+ YaoToEinsum) | No simulation* | **MPS (via ITensors) + state vector (builtin/optimized) + Clifford stabilizer tableau** |
| **MIPT/CIPT Support** | Build from scratch | Manual logic | State vector limited | N/A | **First-class** |
| **Scalability** | N=100+ | N=100+ | ~30 qubits | N/A | **N=100+ (N=1000+ for Clifford-only circuits)** |
| **API Level** | Tensor-level | Circuit + Tomography | Block-level | Circuit construction | **Physics-level** |
| **Learning Curve** | Steep | Medium | Gentle | N/A | **Gentle** |

**\*Note:** Qiskit.jl is a circuit construction wrapper; MPS simulation requires Python Qiskit Aer.

---
## Design Philosophy

```mermaid
flowchart TB
    subgraph "User-Facing API"
        A[SimulationState] --> B[Gates]
        B --> C[Geometry]
        C --> D[Observables]
    end
    subgraph "Internal Engine"
        E[apply!] --> F[build_operator]
        F --> G[apply_op_internal!]
    end
    subgraph "Backend"
        H[ITensors.jl] --> I[ITensorMPS.jl]
    end
    D --> E
    G --> H
```

### Layered Abstraction

- **User-Facing API**: Physicists work with `SimulationState`, `Gates` (PauliX, HaarRandom, Projection), `Geometry` (Bricklayer, AllSites, StaircaseLeft), and `Observables` (EntanglementEntropy, Magnetization). No tensor network concepts exposed.
- **Internal Engine**: The `apply!` function translates high-level physics operations into ITensor calls. It manages physical-to-RAM index mappings (`phy_ram`/`ram_phy`), operator construction, and MPS updates. Users never interact with this layer.
- **Backend**: ITensors.jl and ITensorMPS.jl handle tensor contractions, SVD truncations, and gauge management. All low-level optimizations (bond dimensions, cutoffs, orthogonality centers) are managed automatically.
- **Key Insight**: Users write physics in three lines of code; the package executes hundreds of tensor operations behind the scenes, enabling rapid prototyping without sacrificing performance or scalability.

### The Unified Stochastic Rule

Every probabilistic operation in the package, from a single measurement to a multi-outcome control protocol, follows ONE rule: `apply_with_prob!(c; outcomes=[(probability=p, gate=g, geometry=geo), ...])` expands each outcome's `geometry` into a list of elements (site groups), and every outcome must expand to the SAME element count `K`. For each element `k = 1..K`, the engine draws exactly one coin from the `:gates_spacetime` stream and makes a categorical selection among the outcomes at that element; the remainder `1 - Σp` selects identity (nothing applied). There is no separate "independent Bernoulli per outcome" code path and no second RNG scheme hiding in a compound geometry — one rule, one selection function, everywhere.
This single rule is what makes exclusive per-bond gate choices natural: `outcomes=[(probability=0.5, gate=HaarRandom(), geometry=Bricklayer(:even)), (probability=0.5, gate=CZ(), geometry=Bricklayer(:even))]` guarantees every even bond gets EXACTLY one of `HaarRandom()` or `CZ()`, never both and never neither (when `Σp = 1`). Correlated layers (the SAME coin choosing an entire layer, not per-bond) are expressed with `ProductGate`, not with a second probabilistic construct.

### Broadcast vs. Set Geometry

Geometries fall into two families, and knowing which one you're holding tells you exactly how it behaves inside `apply_with_prob!` and `apply!`:

- **Broadcast** ("distribution") geometries expand to `K ≥ 1` independent elements, each getting its own gate application (and, inside a stochastic op, its own coin): `AllSites()`, `Bricklayer(parity)`, `EachSite(collection)`.
- **Set** ("region") geometries denote ONE region of sites, a single element: `SingleSite(i)`, `AdjacentPair(i)`, `Sites(collection)`, `StaircaseLeft`/`StaircaseRight`, `Pointer`.
`is_broadcast(geo)` reports the trait, and `elements(geo, L, bc)` returns the canonical enumeration either way, always `Vector{Vector{Int}}`. This vocabulary is also why `EachSite(2:L-1)` and `Sites(2:L-1)` look similar but mean opposite things: `EachSite` applies a single-site gate independently at each of sites 2 through L-1 (K = L-2 coins, K = L-2 possible applications), while `Sites(2:L-1)` is ONE region spanning sites 2 through L-1 for a single gate whose support equals `L-2`.

---
## Installation

`QuantumCircuitsMPS.jl` is not yet registered in the Julia General registry.

```julia
using Pkg
Pkg.add(url="https://github.com/hainingpan/QuantumCircuitsMPS.jl")
```
**Local development**: `cd /path/to/QuantumCircuitsMPS.jl && julia --project=.`, then:
```julia
using Pkg
Pkg.instantiate()
using QuantumCircuitsMPS, Revise
```
**Dependencies**: ITensors.jl, ITensorMPS.jl, JSON.jl (required); Luxor.jl (optional, for circuit visualization). Julia 1.11+ required.

---
## Quick Start

### MIPT Example: Measurement-Induced Phase Transition

```julia
using QuantumCircuitsMPS

# System parameters
L = 12                  # 12 qubits
p = 0.15               # Measurement probability (near critical point)
n_steps = 50           # Time evolution steps

# Haar random unitaries + stochastic measurements; record! marks snapshot points
circuit = Circuit(L=L, bc=:periodic) do c
    # Even gates → measure → odd gates → measure per timestep
    apply!(c, HaarRandom(), Bricklayer(:even))
    apply_with_prob!(c; outcomes=[
        (probability=p, gate=Measure(:Z), geometry=AllSites())
    ])
    record!(c, :entropy)
    apply!(c, HaarRandom(), Bricklayer(:odd))
    apply_with_prob!(c; outcomes=[
        (probability=p, gate=Measure(:Z), geometry=AllSites())
    ])
    record!(c, :entropy)
end

# Initialize state and track entanglement entropy
state = SimulationState(
    L=L, bc=:periodic, maxdim=64,
    rng=RNGRegistry(gates_spacetime=42, born_measurement=1, gates_realization=2)
)
initialize!(state, ProductState(binary_int=0))
track!(state, :entropy => EntanglementEntropy(; cut=L÷2))

# record_when=:marks fires at each record!(c, ...) marker, twice per step
simulate!(circuit, state; n_steps=n_steps, record_when=:marks)

# Extract entropy trajectory
entropies = state.observables[:entropy]
println("Final entropy: $(entropies[end])")

# See examples/mipt_example.ipynb for the full tutorial
```

**Physics**: The competition between entangling Haar gates and disentangling measurements creates a phase transition at critical measurement rate p_c ≈ 0.16. Below p_c, the system exhibits volume-law entanglement; above p_c, area-law entanglement emerges.

### CIPT Example: Control-Induced Phase Transition

```julia
using QuantumCircuitsMPS

# System parameters
L = 8                   # Number of qubits
p_ctrl = 0.5            # Control probability (critical point p_c ≈ 0.5)
n_steps = 2 * L^2       # Timesteps (staircase sweeps)

# Build circuit: each step, a coin flip applies Reset (moving left) or Haar (moving right)
left = StaircaseLeft(1)
right = StaircaseRight(1)

circuit = Circuit(L=L, bc=:periodic, p_ctrl=p_ctrl) do c
    apply_with_prob!(c; outcomes=[
        (probability=c.params[:p_ctrl], gate=Reset(), geometry=left),
        (probability=1-c.params[:p_ctrl], gate=HaarRandom(), geometry=right)
    ])
end

# Initialize state and track magnetization Mz = (1/L) Σᵢ ⟨Zᵢ⟩
state = SimulationState(L=L, bc=:periodic, maxdim=64,
    rng=RNGRegistry(gates_spacetime=42, born_measurement=1, gates_realization=2))
initialize!(state, ProductState(binary_int=0))
track!(state, :Mz => Magnetization(:Z))

# Run simulation
simulate!(circuit, state; n_steps=n_steps, record_when=:every_gate)

mz_vals = state.observables[:Mz]
println("Final Mz: $(mz_vals[end])")

# See examples/cipt_example.ipynb for the full tutorial
```

**Physics**: The competition between Reset gates (which project qubits to |0⟩) and Haar random unitaries (which entangle qubits) drives a phase transition at p_c ≈ 0.5. In the reset-dominated phase (p_ctrl > 0.5), the magnetization Mz → +1 as qubits are repeatedly reset to |0⟩. In the unitary-dominated phase (p_ctrl < 0.5), Mz → 0 as random unitaries scramble the state. The staircase geometries sweep in opposite directions, creating the spatial competition that drives the transition.

`Reset()` above is sugar: it's exactly `Measure(:Z; feedback=OnOutcome(1 => PauliX()))` (measure, then flip back to |0⟩ if the outcome was 1) — see the "Feedback & Custom Gates" section below for the general form, which lets you swap the flip for any gate, or for an arbitrary closure.

### AKLT Example: Forced Measurement Protocol

```julia
using QuantumCircuitsMPS

# System parameters
L = 12                    # Chain length
bc = :periodic            # Boundary conditions
p_nn = 1.0               # Pure NN projections (set to 0.0 for NNN)

# Create spin projection gate (projects out S=2 quintet sector)
P0, P1 = total_spin_projector(0), total_spin_projector(1)
proj_gate = SpinSectorProjection(P0 + P1)

# Build circuit: apply projections to all NN pairs
circuit = Circuit(L=L, bc=bc) do c
    apply_with_prob!(c; outcomes=[
        (probability=p_nn, gate=proj_gate, geometry=Bricklayer(:nn)),
        (probability=1-p_nn, gate=proj_gate, geometry=Bricklayer(:nnn))
    ])
end

# Initialize state and track observables
state = SimulationState(L=L, bc=bc, site_type="S=1", maxdim=128,
    rng=RNGRegistry(gates_spacetime=42, gates_realization=2, born_measurement=3))
initialize!(state, ProductState(spin_state="Z0"))

track!(state, :entropy => EntanglementEntropy(cut=L÷2, renyi_index=1, base=2))
track!(state, :string_order => StringOrder(1, L÷2+1, order=1))

# Run L layers of projections
simulate!(circuit, state; n_steps=L, record_when=:every_step)

# Results: NN AKLT converges to S ≈ 2.0, |SO| ≈ 0.444
println("Entropy: $(state.observables[:entropy][end])")
println("|String Order|: $(abs(state.observables[:string_order][end]))")

# See examples/AKLT_forcedmeas.ipynb for the full tutorial with NNN support
```

**Physics**: The AKLT (Affleck-Kennedy-Lieb-Tasaki) state is a paradigmatic example of symmetry-protected topological order. By projecting out the S=2 quintet sector from adjacent spin-1 pairs, the protocol converges to the AKLT ground state characterized by string order parameter |O| ≈ 4/9.

### Feedback & Custom Gates

Measurement feedback, arbitrary unitaries, and correlated layers are all first-class:

```julia
using QuantumCircuitsMPS

# --- 1. Closure feedback: adaptive random-unitary response ---
L = 6
circuit = Circuit(L=L, bc=:open) do c
    apply!(c, HaarRandom(), Bricklayer(:odd))
    apply_with_prob!(c; outcomes=[
        (probability=1.0,
         gate=Measure(:Z; feedback=(state, sites, outcome) ->
             outcome == 1 && apply!(state, HaarRandom(1), SingleSite(sites[1]))),
         geometry=EachSite(2:L-1))
    ])
end

state = SimulationState(L=L, bc=:open, maxdim=32,
    rng=RNGRegistry(gates_spacetime=7, gates_realization=8, born_measurement=9, state_init=1),
    log_events=true)
initialize!(state, ProductState(binary_int=0))
simulate!(circuit, state; n_steps=3)
n_outcomes = length(QuantumCircuitsMPS.measurements(state))
println("Feedback circuit ran 3 steps, $(n_outcomes) measurement outcomes logged")

# --- 2. MatrixGate: any hand-supplied unitary as a gate ---
state2 = SimulationState(L=2, bc=:open, maxdim=16,
    rng=RNGRegistry(gates_spacetime=1, gates_realization=2, born_measurement=3))
initialize!(state2, ProductState(binary_int=0))
apply!(state2, MatrixGate([0.0 1.0; 1.0 0.0]), SingleSite(1))
println("MatrixGate(X) flipped site 1: P(site1=1) = $(born_probability(state2, 1, 1))")

# --- 3. ProductGate: ONE coin governs an entire correlated layer ---
pg_haar = ProductGate(HaarRandom(), Bricklayer(:even))
state3 = SimulationState(L=4, bc=:open, maxdim=16,
    rng=RNGRegistry(gates_spacetime=1, gates_realization=2, born_measurement=3))
initialize!(state3, ProductState(binary_int=0))
track!(state3, :entropy => EntanglementEntropy(; cut=2))
apply!(state3, pg_haar)  # geometry omitted — fills in Sites(union) automatically
record!(state3)
println("ProductGate layer applied: entropy = $(state3.observables[:entropy][end])")
```

---
## Core API

### Main Abstractions

| Concept | Description | Examples |
|---------|-------------|----------|
| **Gates** | Quantum operations applied to qubits | `HaarRandom()`, `HaarRandom(n)`, `PauliX()`, `Reset()`, `Measure(:Z; feedback=...)`, `MatrixGate(U)`, `Rx(θ)`/`Ry(θ)`/`Rz(θ)`, `Hadamard()`, `ProductGate(gate, geometry)`, `Projection(0)`, `SpinSectorProjection()` |
| **Feedback** | Classical response to a `Measure` outcome | `OnOutcome(1 => PauliX())` (declarative), `(state, sites, outcome) -> ...` (closure escape hatch) |
| **Geometry** | Which qubits to apply gates to (broadcast vs. set — see Design Philosophy) | `Bricklayer(:odd)`, `Bricklayer(:even)`, `Bricklayer(:nn)`, `Bricklayer(:nnn)`, `AllSites()`, `EachSite(2:L-1)`, `SingleSite(3)`, `Sites(1:4)`, `StaircaseLeft(1)` |
| **Recording markers** | Explicit `record!(c[, names...])` positions inside a `Circuit` do-block | `record!(c)` (all tracked observables), `record!(c, :entropy)` (selective) |
| **Observables** | Quantities to measure during simulation | `EntanglementEntropy(; cut=L÷2)`, `DomainWall(order=1)`, `BornProbability(1, 0)`, `Magnetization(:Z)`, `StringOrder(i, j; order=1)` |
| **SimulationState** | The quantum state + tracking | Holds MPS, RNG streams, recorded observables, opt-in event log (`log_events=true`) |

### Bricklayer Geometry Parities

The `Bricklayer` geometry supports multiple parities for different gate application patterns:

| Parity | Description | Pairs (L=12 periodic) |
|--------|-------------|----------------------|
| `:odd` | NN sublayer 1 | (1,2), (3,4), (5,6), (7,8), (9,10), (11,12) |
| `:even` | NN sublayer 2 | (2,3), (4,5), (6,7), (8,9), (10,11), (12,1) |
| **`:nn`** | All NN pairs (combines :odd + :even) | All 12 NN bonds |
| `:nnn_odd_1` | NNN sublayer 1 | (1,3), (5,7), (9,11) |
| `:nnn_odd_2` | NNN sublayer 2 | (3,5), (7,9), (11,1) |
| `:nnn_even_1` | NNN sublayer 3 | (2,4), (6,8), (10,12) |
| `:nnn_even_2` | NNN sublayer 4 | (4,6), (8,10), (12,2) |
| **`:nnn`** | All NNN pairs (combines all 4 sublayers) | All 12 NNN bonds |

### String Order Observable

The `StringOrder` observable measures the non-local string order parameter for spin-1 chains:

```julia
using QuantumCircuitsMPS
StringOrder(1, 7; order=1)  # order=1 (default) for NN AKLT, order=2 for NNN AKLT
```

| Parameter | Formula | Expected Value |
|-----------|---------|----------------|
| `order=1` | ⟨Sz[i] · exp(iπΣ) · Sz[j]⟩ | \|O¹\| ≈ 4/9 ≈ 0.444 |
| `order=2` | ⟨Sz[n]·Sz[n+1] · exp(iπΣ) · Sz[m-1]·Sz[m]⟩ | \|O²\| ≈ (4/9)² ≈ 0.198 |

Note: `order=2` requires `j >= i+4` for non-overlapping endpoint pairs.

### Key Functions

| Function | Purpose | Example |
|----------|---------|---------|
| `apply!(state, gate, geometry)` | Apply a gate to specified sites | `apply!(state, HaarRandom(), Bricklayer(:odd))` |
| `apply_with_prob!(c_or_state; outcomes)` | Unified per-element categorical gate application (builder or eager form; all coins from `:gates_spacetime`) | `apply_with_prob!(c; outcomes=[(probability=p, gate=Measure(:Z), geometry=AllSites())])` |
| `record!(c::CircuitBuilder[, names...])` | Insert a recording marker inside a `Circuit` do-block | `record!(c)`, `record!(c, :entropy)` |
| `simulate!(circuit, state; n_steps=50, record_when=:every_step)` | Run circuit n_steps times; `record_when ∈ {:every_step, :every_gate, :final_only, :marks, predicate}` | See Quick Start |
| `track!(state, obs)` | Register observable for recording | `track!(state, :S => EntanglementEntropy(; cut=6))` |
| `record!(state; i1=nothing)` | Record current observable values (eager form) | `record!(state)` |
| `events(state)` / `measurements(state)` | Typed event-log accessors (requires `log_events=true`) | Post-selection: `all(m -> m.outcome == 0, measurements(state))` |
| `expected_draws(circuit, n_steps)` | Fixed `:gates_spacetime` coin consumption for a circuit run | Draw-count invariant checks |
| `plot_circuit(circuit; filename)` | Export circuit diagram to SVG | Requires `using Luxor` |
| `print_circuit(circuit)` | ASCII circuit visualization | Prints to console |

### Simulation Workflow

```julia
using QuantumCircuitsMPS
circuit = Circuit(L=12, bc=:periodic) do c
    apply!(c, HaarRandom(), Bricklayer(:even))
    apply!(c, HaarRandom(), Bricklayer(:odd))
end
state = SimulationState(L=12, bc=:periodic, maxdim=64, rng=RNGRegistry(gates_spacetime=42, gates_realization=1, born_measurement=2))
initialize!(state, ProductState(binary_int=0))
track!(state, :entropy => EntanglementEntropy(; cut=6))
simulate!(circuit, state; n_steps=50, record_when=:every_step)
state.observables[:entropy]
```

Circuit definition (declarative) is kept separate from execution. For complete API documentation, see the source code docstrings.
---
## State Vector Backend

Alongside the default MPS backend, `QuantumCircuitsMPS.jl` also ships an exact, dense state-vector backend. It stores the full wavefunction as a `Vector{ComplexF64}` and applies gates by direct matrix multiplication, no SVD, no bond-dimension truncation, no `cutoff`/`maxdim` bookkeeping. Every gate, measurement, and observable that works on the MPS backend works identically here (`apply!`, `track!`, `record!`, `simulate!` are all backend-agnostic); only the `SimulationState(...)` constructor call changes.

**When to use it**:
- Cross-validating MPS results against an exact reference with zero truncation error
- Small systems (`L ≲ 25` qubits) where the dense wavefunction fits comfortably in RAM
- Producing exact reference trajectories for debugging suspected MPS truncation artifacts

**When not to use it**: anything beyond `L ≈ 25-27` qubits, or whenever you need the MPS backend's `L=100+` scalability. Memory grows as `local_dim^L`, exponentially, with no way around it for a dense representation.

### Quick Example

```julia
using QuantumCircuitsMPS

# Exact state-vector simulation for small systems (L ≲ 25)
L = 8
state = SimulationState(L=L, bc=:open, backend=:statevector,
    rng=RNGRegistry(gates_spacetime=1, gates_realization=2, born_measurement=3))
initialize!(state, ProductState(binary_int=0))
track!(state, :entropy => EntanglementEntropy(cut=L÷2))

apply!(state, HaarRandom(2), AdjacentPair(L÷2))
record!(state)
println("Entropy: $(state.observables[:entropy][end])")
```

**Physics**: `AdjacentPair(L÷2)` places the Haar-random two-qubit gate directly across the entanglement cut at `L÷2`, so the resulting nonzero entropy is the exact entanglement generated by that single gate, no truncation, unlike an MPS run at finite `maxdim`.

### Memory Requirements

The state vector is dense: `local_dim^L × 16 bytes` (`ComplexF64`, 16 bytes per amplitude), with no compression:

| System | `local_dim` | Memory |
|--------|-------------|--------|
| L=20 qubits | 2 | ≈ 16 MB |
| L=25 qubits | 2 | ≈ 512 MB |
| L=30 qubits | 2 | ≈ 16 GB |

The MPS backend's memory usage instead scales with bond dimension (`maxdim`), staying roughly flat in `L` — this is why MPS remains the default for `L=100+` production runs, while the state-vector backend serves as an exact, small-`L` cross-validation and debugging tool.

### Engine Selection

The state-vector backend has two interchangeable gate-application engines, chosen via the `engine` keyword:

- **`engine=:builtin`** (default): reshape → matrix-multiply → reshape-back. Simple and easy to audit; the reference implementation every correctness check is validated against.
- **`engine=:optimized`**: a stride-loop gate-application kernel that skips the reshape/permute overhead, faster for larger `L`. Produces bitwise-identical results to `engine=:builtin` on the same input (see "Related Projects" for the Yao.jl pattern it's based on).

```julia
state = SimulationState(L=20, bc=:open, backend=:statevector, engine=:optimized,
    rng=RNGRegistry(gates_spacetime=1, gates_realization=2, born_measurement=3))
```

Use `:builtin` when auditability matters most (e.g. debugging an observable formula); reach for `:optimized` once you're pushing `L` toward the upper end of the state-vector backend's practical range and want faster gate application.

---
## Clifford Backend

`QuantumCircuitsMPS.jl` also ships a stabilizer-tableau backend, built on [QuantumClifford.jl](https://github.com/QuantumSavory/QuantumClifford.jl), for circuits built entirely out of Clifford-group gates. Instead of an MPS or a dense state vector, the state is stored as a `MixedDestabilizer` tableau, a compact `O(L)`-generator representation that only Clifford operations can update. `apply!`, `track!`, `record!`, and `simulate!` all work exactly as on the other two backends; only the `SimulationState(...)` constructor call changes.

**When to use it**: MIPT/CIPT studies that only need Clifford gates (Pauli twirls, random Clifford circuits, stabilizer measurements) and want to reach system sizes `L = 100-1000+`, far beyond what MPS or the state-vector backend can practically reach.

**When not to use it**: any circuit that needs a non-Clifford gate, `HaarRandom`, `Rx`/`Ry`/`Rz`, `MatrixGate`, or a general `Projection`/`SpinSectorProjection`. Use `backend=:mps` or `backend=:statevector` for those.

### Quick Example

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

### Scalability

Unlike the state-vector backend's `2^L` memory or the MPS backend's bond-dimension-dependent cost, the stabilizer-tableau representation scales polynomially: `O(L²)` memory (`L` stabilizer generators, each an `L`-bit string) and `O(L²)`-`O(L³)` per gate or measurement update. In practice, a full even+odd `RandomClifford(2)` bricklayer sweep over all `L` qubits completes in well under a second at `L=500` or `L=1000` on a single core, sizes that are simply unreachable for a dense state vector (`2^500` amplitudes) and impractical for MPS once entanglement growth forces `maxdim` up.

| Backend | Memory scaling | Practical qubit range |
|---------|-----------------|------------------------|
| State vector | `2^L` (exponential) | `L ≲ 25-27` |
| MPS | Bond-dimension dependent (`maxdim`) | `L = 100+` |
| **Clifford** | `O(L²)` (polynomial) | **`L = 100-1000+`** |

### Supported Gates

| Category | Gates |
|----------|-------|
| Single-qubit Clifford | `PauliX()`, `PauliY()`, `PauliZ()`, `Hadamard()`, `PhaseGate()` |
| Two-qubit Clifford | `CZ()`, `CNOT()`, `SWAP()` |
| Random Clifford | `RandomClifford(n)` — an `n`-qubit random Clifford operator, sampled from `:gates_realization` and applied natively to the tableau |
| Measurement & feedback | `Measure(:Z; feedback=...)`, `Reset()`, `OnOutcome(...)`, closure feedback — identical semantics to the MPS/state-vector backends |

### Gate Validation

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

### Entanglement Spectrum

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

---
## Citation

If you use QuantumCircuitsMPS.jl in your research, please cite:

```bibtex
@software{quantumcircuitsmps,
  author = {Pan, Haining and Pixley, Jedediah H},
  title = {QuantumCircuitsMPS.jl: MPS-based Quantum Circuit Simulation},
  url = {https://github.com/hainingpan/QuantumCircuitsMPS.jl},
  year = {2026}
}
```

---
## Related Projects

- **[ITensors.jl](https://github.com/ITensor/ITensors.jl)**: General tensor network library (our backend)
- **[ITensorMPS.jl](https://github.com/ITensor/ITensorMPS.jl)**: MPS/MPO algorithms and optimizations
- **[PastaQ.jl](https://github.com/GTorlai/PastaQ.jl)**: Quantum tomography and circuit simulation
- **[Yao.jl](https://github.com/QuantumBFS/Yao.jl)**: Quantum algorithm simulation and variational methods
- **[QuantumClifford.jl](https://github.com/QuantumSavory/QuantumClifford.jl)**: Stabilizer-tableau simulation of Clifford circuits (our Clifford backend)

The optimized state-vector engine (`engine=:optimized`) uses the stride-loop gate-application pattern popularized by [Yao.jl](https://github.com/QuantumBFS/Yao.jl) (MIT License). We acknowledge Roger Luo and the Yao.jl team for their foundational work on efficient quantum circuit simulation in Julia.

The Clifford backend is built directly on [QuantumClifford.jl](https://github.com/QuantumSavory/QuantumClifford.jl) (MIT License) for its stabilizer-tableau representation and gate/measurement primitives. We acknowledge Stefan Krastanov and the QuantumClifford.jl contributors for this foundational stabilizer-formalism package.

---

## Known Limitations / Future Work

- **RNG stream name hardcoded**: The stochastic engine always draws from `:gates_spacetime`. In principle, different probabilistic operations could use independently named streams — this is deferred until a concrete research use case requires it.
- **`HaarRandom` MPS/state-vector parity**: cross-validation between the two backends is verified **exact** for every gate type, including `HaarRandom` — the same RNG seed produces bit-identical trajectories across backends.
- **Clifford backend scope**: qubit-only (`local_dim=2`, no qudit/`S=1` support) and gate set is limited to the Clifford group plus `Measure`/`Reset`/feedback — no noise channels (Kraus/channel-style gates) and no non-Clifford gates; see the "Clifford Backend" section for the exact supported list and error behavior.

---
## License and Contributing

QuantumCircuitsMPS.jl is licensed under the [BSD 3-Clause License](LICENSE).

- **Bug Reports**: [GitHub Issues](https://github.com/hainingpan/QuantumCircuitsMPS.jl/issues)
- **Contributions**: Welcome — fork the repository and submit a pull request with tests for new features.
- **Development Status**: Active development; APIs may change before reaching version 1.0.
