```@meta
CurrentModule = QuantumCircuitsMPS
```

# QuantumCircuitsMPS.jl

Documentation for [QuantumCircuitsMPS.jl](https://github.com/hainingpan/QuantumCircuitsMPS.jl), a
quantum circuit simulation package for MIPT/CIPT research.

**"PyTorch for Quantum Circuits"** — a pure Julia library for simulating **one-dimensional (1D)**
quantum circuits with four interchangeable backends: Matrix Product States (MPS, via ITensors.jl,
`L=100+`), an exact dense state vector (`L≲25`, for cross-validation), a stabilizer tableau
(Clifford-only gates, `L=100-1000+`), and a fermionic Gaussian (free-fermion
Majorana-covariance-matrix) backend for Gaussian-preserving circuits, exact and polynomial-time.
It's purpose-built for researchers studying Measurement-Induced (MIPT) and Control-Induced (CIPT)
Phase Transitions in monitored quantum circuits, where feedback, measurements, and unitary dynamics
compete to create distinct entanglement phases.

Physicists write `apply!(state, HaarRandom(), Bricklayer(:odd))` and never see ITensor index
objects, SVD calls, or tensor contractions — one shared simulation engine (the "One Model, Four
Backends" design described in [Design Philosophy](@ref)) manages the gap between physics intent
(Gates + Geometry) and the numerical representation actually doing the work underneath.

!!! note "Scope: 1D circuits"
    The package currently supports **one-dimensional (1D)** circuits only —
    all geometries and backends operate on a chain of `L` sites.
    Higher-dimensional (2D+) circuits are a planned future direction; see the
    [ROADMAP](https://github.com/hainingpan/QuantumCircuitsMPS.jl/blob/main/ROADMAP.md).

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

**Dependencies**: ITensors.jl, ITensorMPS.jl, QuantumClifford.jl (required); Luxor.jl (optional,
circuit visualization). Julia 1.12+. For interactive development, `Pkg.add("Revise")` globally and
add `using Revise` before `using QuantumCircuitsMPS`.

## Quick Example

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

Haar gates entangle, measurements disentangle: below `p_c` the system is volume-law, above it,
area-law. Full walkthroughs (CIPT, AKLT, feedback, all four backends) live in the [Tutorials](@ref)
page and the notebooks in
[`examples/`](https://github.com/hainingpan/QuantumCircuitsMPS.jl/tree/dev/examples).

## Documentation

- [Design Philosophy](@ref) — the layered-abstraction diagram, the unified stochastic rule, and
  broadcast-vs-set geometry semantics.
- Backends: [MPS Backend](@ref), [State Vector Backend](@ref), [Clifford Backend](@ref),
  [Gaussian Backend](@ref).
- [Tutorials](@ref) — full walkthroughs (CIPT, AKLT, feedback, all four backends).
- [API Reference](@ref) — the full list of exported types and functions.

This documentation is published in two versions: [stable](https://hainingpan.github.io/QuantumCircuitsMPS.jl/stable/)
(the latest tagged release) and [dev](https://hainingpan.github.io/QuantumCircuitsMPS.jl/dev/) (the
`dev` branch, may include unreleased changes).

## Citation

```bibtex
@software{quantumcircuitsmps,
  author = {Pan, Haining and Pixley, Jedediah H},
  title = {QuantumCircuitsMPS.jl: MPS-based Quantum Circuit Simulation},
  url = {https://github.com/hainingpan/QuantumCircuitsMPS.jl},
  year = {2026}
}
```

## Known Limitations

- **1D circuits only**: the entire geometry vocabulary (`Bricklayer`, `AllSites`, `SingleSite`,
  ...), boundary conditions (`:open`/`:periodic`), and all four backends assume a one-dimensional
  chain of sites. Higher-dimensional (2D+) circuit geometries are a planned future direction — see
  [ROADMAP.md](https://github.com/hainingpan/QuantumCircuitsMPS.jl/blob/main/ROADMAP.md).
- **RNG stream name hardcoded**: the stochastic engine always draws from `:gates_spacetime`.
  Independently-named streams per probabilistic operation are deferred until a concrete research
  use case requires it.

See [ROADMAP.md](https://github.com/hainingpan/QuantumCircuitsMPS.jl/blob/main/ROADMAP.md) for
planned features and the [Changelog](@ref) for the full release history.
