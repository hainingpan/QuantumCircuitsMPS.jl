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

- [States and Backends](@ref) — `SimulationState`, initialization, event log, `GaussianBackend`
- [Gates](@ref) — unitaries, measurements, projections, spin-sector machinery
- [Geometry](@ref) — site-selection vocabulary (broadcast vs. set geometries)
- [Observables](@ref) — callable-struct observables, tracking, catalog
- [Circuit](@ref) — lazy `do`-block builder, expansion, simulation
- [Random Number Generation](@ref) — reproducible, independently-seeded RNG streams

## Developer Documentation

- [Backend Interface Contract](@ref) — the contract a new backend
  (`AbstractBackend` subtype) must satisfy: required methods, RNG stream
  rules, indexing conventions.
- [Custom Observables](@ref) — the `track!`-any-callable contract, public
  building blocks, and three worked examples (closure, composed struct,
  `record_value`-hook override).
- [Private / Internal API](@ref) — unexported names with docstrings, for
  contributors reading or extending the source.
