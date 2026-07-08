[![Julia 1.11+](https://img.shields.io/badge/Julia-1.11%2B-blue)](https://julialang.org/)
[![License: BSD-3-Clause](https://img.shields.io/badge/License-BSD--3--Clause-green.svg)](LICENSE)
[![Docs](https://img.shields.io/badge/docs-stable-blue.svg)](https://hainingpan.github.io/QuantumCircuitsMPS.jl/)
[![CI](https://github.com/hainingpan/QuantumCircuitsMPS.jl/actions/workflows/CI.yml/badge.svg)](https://github.com/hainingpan/QuantumCircuitsMPS.jl/actions/workflows/CI.yml)

# QuantumCircuitsMPS.jl

**MPS-based quantum circuit simulation for MIPT/CIPT research**

> ⚠️ Under active development — APIs may change. [Report issues](https://github.com/hainingpan/QuantumCircuitsMPS.jl/issues).

---
## What is QuantumCircuitsMPS.jl?

**"PyTorch for Quantum Circuits"** — a pure Julia library for simulating quantum circuits with three interchangeable backends: Matrix Product States (MPS, via ITensors.jl, `L=100+`), an exact dense state vector (`L≲25`, for cross-validation), and a stabilizer tableau (Clifford-only gates, `L=100-1000+`). It's purpose-built for researchers studying Measurement-Induced (MIPT) and Control-Induced (CIPT) Phase Transitions in monitored quantum circuits, where feedback, measurements, and unitary dynamics compete to create distinct entanglement phases.

Physicists write `apply!(state, HaarRandom(), Bricklayer(:odd))` and never see ITensor index objects, SVD calls, or tensor contractions — the package manages the gap between physics intent (Gates + Geometry) and low-level backend details. Independent, named RNG streams (`:gates_spacetime`, `:gates_realization`, `:born_measurement`, `:state_init`) give every trajectory reproducibility on a given backend.

---
## Comparison with Existing Julia Quantum Libraries

| Feature | ITensors.jl | PastaQ.jl | Yao.jl | **This Package** |
|---|---|---|---|---|
| **Primary focus** | Tensor networks | Tomography & benchmarking | Variational algorithms | **MIPT/CIPT dynamics** |
| **Backend** | MPS/MPO | MPS/MPO | State vector | **MPS + state vector + Clifford tableau** |
| **MIPT/CIPT support** | Build from scratch | Manual logic | State-vector limited | **First-class** |
| **Scalability** | N=100+ | N=100+ | ~30 qubits | **N=100+ (N=1000+ Clifford-only)** |
| **API level** | Tensor-level | Circuit + Tomography | Block-level | **Physics-level** |

---
## Installation

Not yet registered in the Julia General registry:

```julia
using Pkg
Pkg.add(url="https://github.com/hainingpan/QuantumCircuitsMPS.jl")
```

**Local development**: `cd /path/to/QuantumCircuitsMPS.jl && julia --project=.`, then:

```julia
using Pkg
Pkg.instantiate()
using QuantumCircuitsMPS
```

**Dependencies**: ITensors.jl, ITensorMPS.jl, QuantumClifford.jl (required); Luxor.jl (optional, circuit visualization). Julia 1.11+. For interactive development, `Pkg.add("Revise")` globally and add `using Revise` before `using QuantumCircuitsMPS`.

---
## Quick Start: MIPT Example

```julia
using QuantumCircuitsMPS

L = 12                   # 12 qubits
p = 0.15                 # Measurement probability (near critical point p_c ≈ 0.16)
n_steps = 50              # Time evolution steps

circuit = Circuit(L=L, bc=:periodic) do c
    apply!(c, HaarRandom(), Bricklayer(:even))
    apply_with_prob!(c; outcomes=[(probability=p, gate=Measure(:Z), geometry=AllSites())])
    record!(c, :entropy)
    apply!(c, HaarRandom(), Bricklayer(:odd))
    apply_with_prob!(c; outcomes=[(probability=p, gate=Measure(:Z), geometry=AllSites())])
    record!(c, :entropy)
end

state = SimulationState(L=L, bc=:periodic, maxdim=64,
    rng=RNGRegistry(gates_spacetime=42, born_measurement=1, gates_realization=2))
initialize!(state, ProductState(binary_int=0))
track!(state, :entropy => EntanglementEntropy(; cut=L÷2))

simulate!(circuit, state; n_steps=n_steps, record_when=:marks)

entropies = state.observables[:entropy]
println("Final entropy: $(entropies[end])")
```

Haar gates entangle, measurements disentangle: below `p_c` the system is volume-law, above it, area-law. Full walkthroughs (CIPT, AKLT, feedback, all 3 backends) live in the [Tutorials](https://hainingpan.github.io/QuantumCircuitsMPS.jl/tutorials/) docs page and the notebooks in [`examples/`](examples/).

---
## Core Concepts

`SimulationState` holds the quantum state (any backend) plus RNG streams and tracked observables. Circuits are built from **Gates** (`HaarRandom`, `Measure`, `PauliX`, ...) applied over **Geometry** (`Bricklayer(:odd)`, `AllSites()`, `SingleSite(i)`, ...), and every probabilistic choice — from a single measurement to a multi-outcome control protocol — goes through ONE unified categorical draw from the `:gates_spacetime` stream (`apply_with_prob!`). Geometries are either **broadcast** (many independent elements, e.g. `Bricklayer`) or **set** (one region, e.g. `Sites(1:4)`); `record!` markers inside a `Circuit` do-block control when tracked observables snapshot.

See [Design Philosophy](https://hainingpan.github.io/QuantumCircuitsMPS.jl/design/) for the layered-abstraction diagram, the unified stochastic rule, and broadcast-vs-set geometry semantics.

Beyond qubits, `SimulationState(...; site_type="S=k/2")` supports arbitrary spin-`S` chains (any half-integer or integer `S` up to 10) — initialization, `Sz`/`S±` operators, and generalized total-spin projectors work on the MPS and state-vector backends; see [API Reference](https://hainingpan.github.io/QuantumCircuitsMPS.jl/api/#Arbitrary-Spin-S-Support).

---
## Backends

`apply!`, `track!`, `record!`, `simulate!` work identically on all three backends — only the `SimulationState(...; backend=...)` constructor call changes.

- **MPS** (default, `backend=:mps`): tensor-network state via ITensors.jl, bond-dimension-limited (`maxdim`), scales to `L=100+` for generic circuits. [MPS Backend →](https://hainingpan.github.io/QuantumCircuitsMPS.jl/backends/mps/)
- **State vector** (`backend=:statevector`): exact, dense `Vector{ComplexF64}`, zero truncation error, the reference every correctness check is validated against. [State Vector Backend →](https://hainingpan.github.io/QuantumCircuitsMPS.jl/backends/statevector/)
- **Clifford** (`backend=:clifford`): stabilizer tableau via QuantumClifford.jl, polynomial scaling, Clifford-group gates only. [Clifford Backend →](https://hainingpan.github.io/QuantumCircuitsMPS.jl/backends/clifford/)

| Backend | Memory scaling | Practical qubit range |
|---|---|---|
| State vector | `2^L` (exponential) | `L ≲ 25-27` |
| MPS | Bond-dimension dependent (`maxdim`) | `L = 100+` |
| **Clifford** | `O(L²)` (polynomial) | **`L = 100-1000+`** |

---
## Key Functions

| Function | Purpose |
|---|---|
| `apply!(state, gate, geometry)` | Apply a gate to specified sites |
| `apply_with_prob!(c_or_state; outcomes)` | Unified per-element categorical gate application |
| `simulate!(circuit, state; n_steps, record_when)` | Run a circuit `n_steps` times |
| `track!(state, name => observable)` | Register an observable for recording |
| `EntanglementEntropy(; cut)` / `Magnetization(:Z)` | Entropy / magnetization observables |
| `PauliString(1=>:X, 3=>:Z)` | Multi-site Pauli-string expectation ⟨∏Pₖ⟩ (all 3 backends) |
| `MutualInformation(A, B)` | I(A:B) between two regions (all 3 backends) |
| `Correlator(i=>:P, j=>:P)` / `EntropyProfile()` | Connected correlator / entropy at every cut |
| `TripartiteMutualInformation(A, B, C)` | I₃, tripartite mutual information (MIPT order parameter) |
| `MagnetizationFluctuations(region)` | Var(M) over a region |

See [API Reference](https://hainingpan.github.io/QuantumCircuitsMPS.jl/api/) for the full list, and [Custom Observables](https://hainingpan.github.io/QuantumCircuitsMPS.jl/custom_observables/) for writing your own (`track!` accepts any `f(state)` callable).

---
## Citation

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

- [ITensors.jl](https://github.com/ITensor/ITensors.jl) / [ITensorMPS.jl](https://github.com/ITensor/ITensorMPS.jl) — our MPS backend
- [QuantumClifford.jl](https://github.com/QuantumSavory/QuantumClifford.jl) — our Clifford backend
- [PastaQ.jl](https://github.com/GTorlai/PastaQ.jl), [Yao.jl](https://github.com/QuantumBFS/Yao.jl) — related Julia quantum-simulation packages

Acknowledgments for code patterns adapted from these projects: see [CONTRIBUTING.md](CONTRIBUTING.md).

---
## Known Limitations

- **RNG stream name hardcoded**: the stochastic engine always draws from `:gates_spacetime`. Independently-named streams per probabilistic operation are deferred until a concrete research use case requires it.

See [ROADMAP.md](ROADMAP.md) for planned features and [CHANGELOG.md](CHANGELOG.md) for what changed in v0.4.0.

---
## License and Contributing

Licensed under the [BSD 3-Clause License](LICENSE).

- **Bug reports**: [GitHub Issues](https://github.com/hainingpan/QuantumCircuitsMPS.jl/issues)
- **Contributing**: see [CONTRIBUTING.md](CONTRIBUTING.md)
