# Issues & Gotchas - MIPT Example

## [2026-01-31T00:53:21] Critical Physics Distinction
- MIPT requires **pure measurement** (qubit stays in measured state)
- Reset is WRONG for MIPT (resets to |0⟩)
- Examples MUST use Measurement(:Z), NOT Reset()
## [2026-01-30] Bricklayer Not Circuit API Compatible

### Issue
Bricklayer geometry is missing `compute_sites` implementation required by Circuit API.

**Error**: MethodError: no method matching compute_sites(::Bricklayer, ::Int64, ::Int64, ::Symbol)

**Root Cause**:
- Bricklayer only implements `get_pairs(geo, state)` for imperative apply! (used during execution)
- Circuit API requires `compute_sites(geo, step, L, bc)` for symbolic expansion (used by expand_circuit)
- compute_sites_dispatch calls compute_sites for non-Staircase geometries (line 147 in expand.jl)

**Current Bricklayer Implementation**:
- `src/Geometry/static.jl:41-77` - Has get_pairs method only
- Works with imperative `apply!(state, gate, Bricklayer(:odd))`
- FAILS with Circuit API `Circuit() do c; apply!(c, gate, Bricklayer(:odd)); end`

**Workaround**: NONE - Bricklayer cannot be used with Circuit API until compute_sites is implemented.

**Recommendation**: 
- EITHER: Implement compute_sites for Bricklayer (returns all pairs as flat list of sites)
- OR: Update plan to use imperative API instead of Circuit API for MIPT example

