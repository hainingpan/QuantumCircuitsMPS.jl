```@meta
CurrentModule = QuantumCircuitsMPS
```

# Private / Internal API

Unexported names with docstrings: helper functions, internal validation
routines, and per-backend dispatch internals. This page exists so that
`missing_docs` build checking (every docstring in the package is reachable
from the manual, exported or not) is satisfied without cluttering the
[API Reference](@ref) with implementation detail — reference material for
contributors reading or extending the source, **not** part of the supported
public API (no stability guarantees; names/signatures may change without a
breaking-version bump).

```@autodocs
Modules = [QuantumCircuitsMPS]
Public = false
```
