# Architectural Decisions - Circuit Visualization

## [2026-01-29T23:14:14] Session Start

Key architectural decisions for this plan:
- Circuit uses NamedTuple-based internal representation (NOT custom types like GateOp)
- Pure compute_sites functions to avoid geometry mutation
- Users only see: Circuit, Gates, Geometry, State (no AbstractCircuitOp)

---

