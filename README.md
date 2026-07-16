[![Julia 1.12+](https://img.shields.io/badge/Julia-1.12%2B-blue)](https://julialang.org/)
[![License: BSD-3-Clause](https://img.shields.io/badge/License-BSD--3--Clause-green.svg)](LICENSE)
[![Docs](https://img.shields.io/badge/docs-stable-blue.svg)](https://hainingpan.github.io/QuantumCircuitsMPS.jl/)
[![CI](https://github.com/hainingpan/QuantumCircuitsMPS.jl/actions/workflows/CI.yml/badge.svg)](https://github.com/hainingpan/QuantumCircuitsMPS.jl/actions/workflows/CI.yml)

# QuantumCircuitsMPS.jl

**MPS-based quantum circuit simulation for MIPT/CIPT research**

> ⚠️ Under active development — APIs may change. [Report issues](https://github.com/hainingpan/QuantumCircuitsMPS.jl/issues).

---

**"PyTorch for Quantum Circuits"** — a pure Julia library for simulating **one-dimensional (1D)** quantum circuits with four interchangeable backends: Matrix Product States (MPS, via ITensors.jl, `L=100+`), an exact dense state vector (`L≲25`, for cross-validation), a stabilizer tableau (Clifford-only gates, `L=100-1000+`), and a fermionic Gaussian (free-fermion) backend for Gaussian-preserving circuits. It's purpose-built for researchers studying Measurement-Induced (MIPT) and Control-Induced (CIPT) Phase Transitions in monitored quantum circuits: physicists write `apply!(state, HaarRandom(), Bricklayer(:odd))` without touching ITensor internals, and independent, named RNG streams (`:gates_spacetime`, `:gates_realization`, `:born_measurement`, `:state_init`) make every trajectory reproducible from its seeds, on a backend and across backends alike.

---
## Installation

Not yet registered in the Julia General registry:

```julia
using Pkg
Pkg.add(url="https://github.com/hainingpan/QuantumCircuitsMPS.jl")
```

---
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

Haar gates entangle, measurements disentangle: below `p_c` the system is volume-law, above it, area-law. See [`examples/`](examples/) for further worked notebooks.

---
## Documentation

Full documentation, Design Philosophy, all four backends (MPS, state vector, Clifford, Gaussian), Tutorials, the complete API Reference, and Known Limitations, lives on the docs site:

- **[stable](https://hainingpan.github.io/QuantumCircuitsMPS.jl/stable/)** — the latest tagged release
- **[dev](https://hainingpan.github.io/QuantumCircuitsMPS.jl/dev/)** — the `dev` branch, may include unreleased changes

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
## License and Contributing

Licensed under the [BSD 3-Clause License](LICENSE).

- **Bug reports**: [GitHub Issues](https://github.com/hainingpan/QuantumCircuitsMPS.jl/issues)
- **Contributing**: see [CONTRIBUTING.md](CONTRIBUTING.md)

---
## Related Projects

- [ITensors.jl](https://github.com/ITensor/ITensors.jl) / [ITensorMPS.jl](https://github.com/ITensor/ITensorMPS.jl) — our MPS backend
- [QuantumClifford.jl](https://github.com/QuantumSavory/QuantumClifford.jl) — our Clifford backend
- [PastaQ.jl](https://github.com/GTorlai/PastaQ.jl), [Yao.jl](https://github.com/QuantumBFS/Yao.jl) — related Julia quantum-simulation packages

Acknowledgments for code patterns adapted from these projects: see [CONTRIBUTING.md](CONTRIBUTING.md).

---
## Changelog

| Version | Date | Highlight |
|---|---|---|
| [v0.5.0] | 2026-07-13 | Fermionic Gaussian (free-fermion) backend |
| [v0.4.0] | 2026-07-07 | API consistency audit, new observables, Documenter site, CI/quality gates |
| [v0.3.0] | 2026-07-05 | Clifford (stabilizer-tableau) backend |
| [v0.2.0] | 2026-07-05 | Exact state-vector backend |
| [v0.1.0] | 2026-07-04 | MPS quantum circuit simulation core (initial API) |

See [CHANGELOG.md](CHANGELOG.md) for the full release history including patch releases and detailed notes, and [ROADMAP.md](ROADMAP.md) for planned features.

[v0.5.0]: https://github.com/hainingpan/QuantumCircuitsMPS.jl/compare/v0.4.0...v0.5.0
[v0.4.0]: https://github.com/hainingpan/QuantumCircuitsMPS.jl/compare/v0.3.0...v0.4.0
[v0.3.0]: https://github.com/hainingpan/QuantumCircuitsMPS.jl/compare/v0.2.1...v0.3.0
[v0.2.0]: https://github.com/hainingpan/QuantumCircuitsMPS.jl/compare/v0.1.1...v0.2.0
[v0.1.0]: https://github.com/hainingpan/QuantumCircuitsMPS.jl/compare/v0.0.7...v0.1.0
</content>
