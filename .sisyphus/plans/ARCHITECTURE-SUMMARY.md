# QuantumCircuitsMPS.jl v2 - Architecture Summary

## Core Philosophy

**"PyTorch for Quantum Circuits"** - Physicists code as they speak, focusing on physics (Gates + Geometry) without touching MPS implementation details.

```julia
# What users write (high-level physics):
apply!(state, HaarRandom(), Bricklayer(:odd))
apply!(state, Projection(0), SingleSite(1))
dw = DomainWall(order=1)(state, i1)

# What they DON'T see (hidden MPS details):
# - phy_ram/ram_phy index mappings
# - ITensor index management
# - SVD truncation internals
# - Normalization decisions
```

---

## Abstraction Hierarchy

```
┌─────────────────────────────────────────────────────────────┐
│                      USER-FACING API                        │
│  SimulationState │ Gates │ Geometry │ Observables │ RNG    │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                     INTERNAL ENGINE                         │
│  apply!() → build_operator() → apply_op_internal!()        │
│  Physical sites → RAM indices → ITensor Index objects       │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                   ITENSOR/ITENSORMPS                        │
│  MPS │ ITensor │ siteinds │ SVD │ orthogonalize!           │
└─────────────────────────────────────────────────────────────┘
```

---

## Key Abstractions

### 1. SimulationState

The central container holding everything:

```julia
mutable struct SimulationState
    mps::Union{MPS, Nothing}           # The actual MPS (set by initialize!)
    sites::Vector{Index}                # ITensor site indices (RAM order)
    phy_ram::Vector{Int}                # physical_site → RAM_index
    ram_phy::Vector{Int}                # RAM_index → physical_site
    L::Int                              # System size
    bc::Symbol                          # :open or :periodic
    local_dim::Int                      # Qubit dimension (default 2)
    cutoff::Float64                     # SVD cutoff
    maxdim::Int                         # Max bond dimension
    rng_registry::Union{RNGRegistry, Nothing}  # RNG streams
    observables::Dict{Symbol, Vector}   # Tracked observable values
    observable_specs::Dict{Symbol, Any} # Observable specifications
end
```

**Initialization Flow:**
1. `SimulationState(L=10, bc=:periodic)` → computes `phy_ram`/`ram_phy`, creates `sites`, `mps=nothing`
2. `state.rng_registry = RNGRegistry(...)` → attach RNG (optional, needed for HaarRandom)
3. `initialize!(state, ProductState(x0=...))` → creates the actual MPS

### 2. Gates

Pure tensor factories - they only know how to build operators, not where to apply them:

| Gate | Support | Needs RNG | Normalization After |
|------|---------|-----------|---------------------|
| `PauliX/Y/Z` | 1 | No | NO |
| `Projection(outcome)` | 1 | No | YES (+ truncate) |
| `HaarRandom` | 2 | Yes (`:haar`) | NO |
| `CZ` | 2 | No | NO |
| `Reset` | 1 | No | (inherits from Projection) |

**CNOT is OUT OF MVP SCOPE** - not used by CT.jl target.

### 3. Geometry

Specifies WHERE gates apply - completely separate from WHAT the gate does:

| Geometry | Returns | Iteration |
|----------|---------|-----------|
| `SingleSite(i)` | `[i]` | Single |
| `AdjacentPair(i)` | `[i, next(i)]` | Single |
| `Bricklayer(:odd)` | (1,2), (3,4), ... | Multi (internal) |
| `Bricklayer(:even)` | (2,3), (4,5), ... + (L,1) for PBC | Multi (internal) |
| `AllSites` | 1, 2, ..., L | Multi (internal) |
| `StaircaseLeft(start)` | `[ptr, next(ptr)]`, ptr moves left | Single + advances |
| `StaircaseRight(start)` | `[ptr, next(ptr)]`, ptr moves right | Single + advances |

**Staircase Pointer API:**
- `current_position(staircase)` → read-only accessor (public)
- `advance!(staircase, state)` → internal, called by `apply!`

### 4. Observables

Compute physics quantities from state:

| Observable | API | Notes |
|------------|-----|-------|
| `born_probability(state, site, outcome)` | Function | P(site=outcome) |
| `BornProbability(site, outcome)(state)` | Callable struct | Same as above |
| `DomainWall(order)(state, i1)` | Callable struct | Requires `i1` parameter |

**DomainWall `i1` semantics:** `i1 = (returned_pointer % L) + 1` (CT sampling site, not raw pointer)

### 5. RNG Registry

Clean 4-stream design (replaces CT.jl's mangled 2-stream):

| Stream | Purpose |
|--------|---------|
| `:ctrl` | p_ctrl decisions (control vs unitary branch) |
| `:proj` | p_proj decisions (apply projection?) |
| `:haar` | Haar random unitary generation |
| `:born` | Born rule measurement outcomes |
| `:state_init` | RandomMPS initialization (optional) |

**CT-Compat Mode** (for verification only):
```julia
# Aliases :ctrl, :proj, :haar to SAME underlying RNG (matches CT.jl's interleaved pattern)
rng = RNGRegistry(Val(:ct_compat), circuit=42, measurement=123)
```

---

## Site Indexing Contract

**Users ALWAYS use physical site indices 1:L. Internal RAM mapping is hidden.**

```
Physical sites:  1   2   3   4   5   6   7   8   9   10   (user sees this)
                 │   │   │   │   │   │   │   │   │   │
                 ▼   ▼   ▼   ▼   ▼   ▼   ▼   ▼   ▼   ▼
RAM indices:     ?   ?   ?   ?   ?   ?   ?   ?   ?   ?    (hidden from user)
```

**OBC:** `phy_ram = ram_phy = [1,2,3,...,L]` (identity)

**PBC (folded):** Interleaved from ends: `ram_phy = [1, L, 2, L-1, 3, L-2, ...]`
- Example L=4: `ram_phy = [1,4,2,3]`, `phy_ram = [1,3,4,2]`

**PBC requires even L** - odd L throws `ArgumentError` at construction.

---

## apply! Flow

```
apply!(state, gate, geometry)
         │
         ▼
┌─────────────────────────────┐
│ 1. get_sites(geo, state)    │  → physical sites (e.g., [10, 1] for wrap)
└─────────────────────────────┘
         │
         ▼
┌─────────────────────────────┐
│ 2. phy_ram lookup           │  → RAM indices (e.g., [2, 1])
└─────────────────────────────┘
         │
         ▼
┌─────────────────────────────┐
│ 3. build_operator(gate,     │  → ITensor operator (indices in PHYSICAL PAIR order)
│    [sites[ram_i], sites[ram_j]], │
│    local_dim; rng=...)      │
└─────────────────────────────┘
         │
         ▼
┌─────────────────────────────┐
│ 4. apply_op_internal!(mps,  │  → SVD-based MPS contraction
│    op, state.sites;         │     (extracts indices, SORTS for SVD sweep)
│    cutoff, maxdim)          │
└─────────────────────────────┘
         │
         ▼
┌─────────────────────────────┐
│ 5. apply_post!(state, gate) │  → Gate-class-dependent normalization
└─────────────────────────────┘
```

**Critical:** Operator built in **physical pair order** (qubit assignment), SVD sweep in **sorted RAM order**.

---

## File Structure (After Implementation)

```
src/
├── QuantumCircuitsMPS.jl      # Module entry (REPLACED in Task 9)
├── Core/
│   ├── rng.jl                 # RNGRegistry
│   ├── basis.jl               # compute_basis_mapping (OBC/PBC)
│   └── apply.jl               # apply!, apply_op_internal!, apply_post!
├── State/
│   ├── State.jl               # SimulationState struct
│   └── initialization.jl      # initialize!, ProductState, RandomMPS
├── Gates/
│   ├── Gates.jl               # AbstractGate
│   ├── single_qubit.jl        # PauliX/Y/Z, Projection
│   ├── two_qubit.jl           # HaarRandom, CZ
│   └── composite.jl           # Reset
├── Geometry/
│   ├── Geometry.jl            # AbstractGeometry
│   ├── static.jl              # SingleSite, AdjacentPair, Bricklayer, AllSites
│   └── staircase.jl           # StaircaseLeft, StaircaseRight
├── Observables/
│   ├── Observables.jl         # AbstractObservable, track!, record!
│   ├── domain_wall.jl         # DomainWall (xj=Set([0]) only)
│   └── born.jl                # BornProbability, born_probability
├── API/
│   ├── imperative.jl          # apply! (explicit state)
│   ├── functional.jl          # simulate()
│   └── context.jl             # with_state, current_state, apply_with_prob!
└── _deprecated/               # Archived old code (after Task 9)
```

---

## Coexistence Strategy (Contract 1)

**Phase 1 (Tasks 0-8):** New code in `src/v2/`, old code untouched
```julia
# Testing during development:
include("src/v2/QuantumCircuitsMPSv2.jl")
using .QuantumCircuitsMPSv2
```

**Phase 2 (Task 9, after verification):**
1. Archive old → `src/_deprecated/`
2. Move v2 → `src/`
3. Replace module entry
4. `using QuantumCircuitsMPS` now loads v2

---

## CT.jl Verification Strategy

**Goal:** Bit-for-bit match with CT.jl's `run_CT_MPS_C_m_T.jl` output.

**Key Parameters:** `L=10, p_ctrl=0.5, p_proj=0.0, seed_C=42, seed_m=123`

**Why p_proj=0.0:** Eliminates `:proj` stream consumption, simplifying RNG matching.

**CT.jl Patch Required:**
```julia
# Line ~402: if rand(ct.rng_C) < p_proj
# Change to: if p_proj > 0 && rand(ct.rng_C) < p_proj
```

**Verification uses CT-compat RNG mode** - streams aliased to match CT.jl's interleaved consumption.

**Acceptance:** `maximum(abs.(new_dw - ref_dw)) < 1e-10`

---

## Execution Waves

```
Wave 0: Task 0 (scaffold)           ─────────────────────────────────────►
Wave 1: Task 1 (State) ║ Task 2 (RNG) ║ Task 10 (CT ref)  ───────────────►
Wave 2: Task 3 (Gates) ║ Task 4 (Basis) ║ Task 6 (Observables) ──────────►
Wave 3: Task 5 (Geometry + apply!) ──────────────────────────────────────►
Wave 4: Task 7 (API) ║ Task 8 (CT example) ──────────────────────────────►
Wave 5: Task 9 (Verification + cleanup) ─────────────────────────────────►

Critical Path: 0 → 1 → 3 → 5 → 7 → 8 → 9
```

---

## Guardrails (Must NOT Have)

| Exclusion | Reason |
|-----------|--------|
| ❌ Ancilla support | Deferred (not in MVP target) |
| ❌ TCI integration | Not needed |
| ❌ adder_MPO | Only for xj={1/3, 2/3}, not our target |
| ❌ CNOT gate | Not used by CT.jl target script |
| ❌ >2 type hierarchy levels | Keep it flat |
| ❌ Multi-threading | Out of scope |
| ❌ Custom ITensor index parsing | Use native Index matching |

---

## API Styles Supported

**Style A1 - OO Explicit (Primary):**
```julia
state = SimulationState(L=10, bc=:periodic, rng=RNGRegistry(ctrl=1, proj=2, haar=3, born=4))
initialize!(state, ProductState(x0=1//1024))
apply!(state, HaarRandom(), Bricklayer(:odd))
dw = DomainWall(order=1)(state, i1)
```

**Style B - Functional:**
```julia
results = simulate(
    L=10, bc=:periodic,
    init=ProductState(x0=1//1024),
    circuit!=(state, t) -> apply!(state, HaarRandom(), Bricklayer(:odd)),
    steps=100,
    observables=[:dw1 => DomainWall(1)],
    rng=RNGRegistry(ctrl=1, proj=2, haar=3, born=4),
    i1_fn=(state, t) -> (current_position(staircase) % L) + 1
)
```

**Style C - Context (Implicit State):**
```julia
with_state(state) do
    apply!(HaarRandom(), Bricklayer(:odd))  # uses current_state() internally
end
```

---

## Quick Reference: Key Decisions

| Decision | Resolution |
|----------|------------|
| Site indexing | Physical 1:L everywhere (internal RAM mapping hidden) |
| Geometry naming | `Bricklayer(:odd/:even)` |
| Staircase OBC | Reset/bounce instead of error |
| Gate terminology | `support` (not "arity") |
| RNG streams | `:ctrl`, `:proj`, `:haar`, `:born`, `:state_init` |
| CT.jl verification | CT-compat RNG mode + patch CT.jl for p_proj=0 |
| Probabilistic apply | `apply_with_prob!(state, gate, geo, prob; rng=:ctrl)` |
| Multi-apply | `apply!` handles internally (no manual iteration) |
| PBC odd-L | ERROR at construction (not supported) |
| CNOT | OUT OF MVP SCOPE (not used by CT.jl target) |

---

This architecture ensures physicists write physics-level code while all MPS complexity is handled internally, with CT.jl compatibility for verification.
