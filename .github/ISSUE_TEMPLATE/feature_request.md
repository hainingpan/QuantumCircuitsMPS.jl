---
name: Feature request
about: Suggest a new gate, observable, geometry, backend capability, or other enhancement
title: ""
labels: enhancement
---

**What problem does this solve?**
Describe the research or workflow need this would address. If it's already
listed in [ROADMAP.md](../../ROADMAP.md), feel free to link it and add
context instead of re-describing it from scratch.

**Proposed API (if you have one in mind)**
Sketch the function/type signature you'd expect, e.g.:

```julia
NewObservable(region; kwarg=default)
```

**Which backend(s) should this apply to?**
`:mps` / `:statevector` / `:clifford` / all three — note if a backend is
infeasible for physical reasons (e.g. the Clifford backend is qubit-only).

**Alternatives considered**
Any existing workaround, or other API shapes you considered.

**Additional context**
Anything else relevant (references, related packages, papers).
