# Backend Interface Contract

This page is the developer contract for simulation backends: the fields a
backend struct must hold, the methods it must implement, the RNG streams its
primitives may consume, and the indexing conventions it must respect. It is
derived from — and verifiable against — the three shipped backends
(`MPSBackend`, `StateVectorBackend`, `CliffordBackend`). Every method table
below can be cross-checked with `methods()`; see
[Verifying this document](@ref backend-interface-verify).

Audience: developers adding a new backend or modifying an existing one. Users
never interact with this layer — `apply!`, `track!`, `record!`, and
`simulate!` are backend-agnostic.

## Dispatch architecture

`SimulationState{B<:AbstractBackend}` is parametrically typed on its backend
(`src/State/State.jl`). Backend selection is ordinary multiple dispatch on
that type parameter — there is no `if backend == ...` branching anywhere in
the engine.

**The "generic = MPS-assumed" pattern (and its trap).** For historical
reasons, the *unparameterized* generic methods — e.g.
`_apply_single!(state::SimulationState, gate, sites)` in `src/Core/apply.jl`,
or the observable callables in `src/Observables/` — implement the **MPS**
path: they reach directly for `state.backend.mps` / `state.backend.sites`.
Backends other than MPS work by adding *more-specific* methods on
`SimulationState{StateVectorBackend}` / `SimulationState{CliffordBackend}`
that shadow those generics.

Consequence, and the single most important rule on this page:

> **RULE — override or reject, never fall through.** For every entry point
> listed below, a non-MPS backend MUST either (a) provide its own method, or
> (b) provide a method that throws an informative `ArgumentError`. Anything
> left unhandled falls through to an MPS-assumed generic and crashes with a
> raw `FieldError` (`type CliffordBackend has no field mps`). This exact
> failure mode shipped as the v0.3 Clifford `StringOrder`/`DomainWall` crash,
> fixed in v0.4.0 by adding explicit rejection methods
> (`src/Clifford/observables.jl`).

## Backend structs

A backend is a `mutable struct <: AbstractBackend` (`src/Backend/Backend.jl`)
whose numerical payload starts as `nothing` and is populated by
`initialize!`:

| Backend | Payload field | Other fields | Representation |
|---|---|---|---|
| `MPSBackend` | `mps::Union{MPS, Nothing}` | `sites::Vector{Index}`, `cutoff::Float64`, `maxdim::Int` | ITensorMPS.jl matrix product state |
| `StateVectorBackend` | `ψ::Union{Vector{ComplexF64}, Nothing}` | `engine::Symbol` (`:builtin` or `:optimized`) | dense state vector, `local_dim^L` amplitudes |
| `CliffordBackend` | `tableau::Union{MixedDestabilizer, Nothing}` | — | QuantumClifford.jl stabilizer tableau |

### Constructor wiring

The `SimulationState(; backend=...)` keyword constructor
(`src/State/State.jl`) owns backend construction. A new backend must be wired
in there, deciding:

- **Basis mapping**: `phy_ram`/`ram_phy` vectors. MPS uses
  `compute_basis_mapping(L, bc; pbc_fold_start)` (`src/Core/basis.jl`), which
  zig-zag-folds periodic chains; StateVector and Clifford use the identity
  mapping. Even identity-mapped backends must keep the
  `state.phy_ram[site]` lookup in their primitives, for code-path
  consistency.
- **Constructor validation**: reject unsupported configurations loudly at
  construction time — e.g. `CliffordBackend` throws `ArgumentError` for
  `local_dim != 2` (stabilizer formalism is qubit-only).
- **Keyword semantics**: `cutoff`/`maxdim`/`pbc_fold_start` are meaningful
  only for `:mps`; `engine` only for `:statevector`. Irrelevant keywords are
  accepted and ignored for cross-backend API consistency.

## Required methods

### 1. `initialize!(state, init)` — one method per supported initial-state type

Populates the backend payload from an `AbstractInitialState` spec. Current
method table (5 methods):

| Method | Defined in | Serves |
|---|---|---|
| `initialize!(::SimulationState, ::ProductState)` | `src/State/initialization.jl` | generic fallback = **MPS** |
| `initialize!(::SimulationState, ::RandomMPS)` | `src/State/initialization.jl` | generic fallback = **MPS** |
| `initialize!(::SimulationState{StateVectorBackend}, ::ProductState)` | `src/StateVector/initialization.jl` | StateVector |
| `initialize!(::SimulationState{StateVectorBackend}, ::RandomStateVector)` | `src/StateVector/initialization.jl` | StateVector |
| `initialize!(::SimulationState{CliffordBackend}, ::ProductState)` | `src/Clifford/initialization.jl` | Clifford |

Contract obligations:

- `ProductState` support is mandatory. The `binary_int` / `binary_decimal` /
  `bitstring` → bit-pattern-string derivation must match the reference logic
  in `src/State/initialization.jl` exactly (site 1 = MSB). Unsupported
  sub-modes are rejected with `ArgumentError` (Clifford rejects
  `spin_state`, which is S=1/qudit-oriented).
- Random initializers (`RandomMPS`, `RandomStateVector`) MUST draw from the
  registry's `:state_init` stream via
  `get_rng(state.rng_registry, :state_init)` — never the global RNG — and
  must throw `ArgumentError` when no registry is attached. Same seed ⇒
  identical state, bitwise.
- Backends with a non-identity basis mapping must reorder the per-site data
  to RAM order via `state.ram_phy` (see the MPS `ProductState` method).

### 2. `_apply_single!(state, gate, phy_sites)` — the gate-application primitive

The internal workhorse: applies one gate to one concrete list of physical
sites. Two implementation styles exist; both are valid:

- **Generic resolver** (MPS, StateVector): ONE method for all
  `gate::AbstractGate` that resolves the gate to an operator and applies it.
- **Per-gate methods + rejecting fallback** (Clifford): one method per
  supported gate type, plus a `gate::AbstractGate` fallback that throws an
  informative `ArgumentError` naming the offending gate and the alternative
  backends.

Current method table (12 methods):

| # | Method (dispatch on state × gate) | Defined in |
|---|---|---|
| 1 | `(::SimulationState, ::AbstractGate)` — generic = **MPS**: `build_operator` → `apply_op_internal!` | `src/Core/apply.jl` |
| 2 | `(::SimulationState{StateVectorBackend}, ::AbstractGate)`: `gate_matrix` → `apply_gate_sv!`/`apply_gate_sv_optimized!` | `src/StateVector/StateVector.jl` |
| 3–11 | `(::SimulationState{CliffordBackend}, G)` for `G` ∈ `PauliX`, `PauliY`, `PauliZ`, `Hadamard`, `PhaseGate`, `CZ`, `CNOT`, `SWAP`, `RandomClifford` — native tableau ops | `src/Clifford/Clifford.jl` |
| 12 | `(::SimulationState{CliffordBackend}, ::AbstractGate)` — fallback: informative `ArgumentError` | `src/Clifford/Clifford.jl` |

Contract obligations (every implementation):

1. Validate `support(gate) == length(phy_sites)`; throw `ArgumentError` on
   mismatch (exact message convention: see any existing method).
2. Map physical → internal indices via `state.phy_ram` before touching the
   payload.
3. Resolve gate content through the gate protocol appropriate to the
   representation (see table below) — never hardcode gate matrices in the
   backend.
4. Honor the `needs_normalization(gate)` trait after applying:
   MPS → `normalize!` + `truncate!(; cutoff)`; StateVector → `normalize!`;
   Clifford → not applicable (all supported operations preserve stabilizer
   states).
5. Random-content gates draw from `:gates_realization` (see
   [RNG expectations](@ref backend-interface-rng)).

| Backend | Gate-content protocol | Application kernel |
|---|---|---|
| MPS | `build_operator(gate, site_index(es), local_dim; rng, mps, ram_sites) -> ITensor` | `apply_op_internal!` (contract + SVD chain, respects `cutoff`/`maxdim`) |
| StateVector | `gate_matrix(gate) -> Matrix{ComplexF64}`; random gates via `gate_matrix(gate, rng; local_dim)` (dispatch in `_resolve_gate_matrix_sv`) | `apply_gate_sv!` (`:builtin`) or `apply_gate_sv_optimized!` (`:optimized`) |
| Clifford | none — symbolic ops (`QuantumClifford.sX`, `sCPHASE`, `sCNOT`, ..., `random_clifford`) | `QuantumClifford.apply!(tableau, op[, indices])` |

### 3. `_measure_single_site!(state, site) -> Int` — the measurement primitive

Born-samples a Z measurement of one site, collapses the state, and returns
the outcome (`0` or `1`). Current method table (2 methods):

| Method | Defined in | Serves |
|---|---|---|
| `(::SimulationState, ::Int)` — generic | `src/Core/apply.jl` | **MPS and StateVector** |
| `(::SimulationState{CliffordBackend}, ::Int)` | `src/Clifford/measurement.jl` | Clifford |

The generic implementation is representation-agnostic — it composes
`born_probability` (backend-dispatched), one scalar `:born_measurement` draw,
and `_apply_single!(state, Projection(outcome), [site])`. **A new backend
gets measurement for free** if it implements `born_probability` and can apply
`Projection`; it only needs its own override when `Projection` has no
representation (the Clifford case, which uses `QuantumClifford.projectZ!`
instead).

Contract obligations for overrides:

- Return `Int` outcome `0`/`1`; leave the post-measurement state normalized.
- Draw outcomes from `:born_measurement` ONLY, as scalar `rand(rng)` calls
  (SCALAR-DRAW CONTRACT, `src/Core/rng.jl`), with the
  `rand(rng) < p₀ ? 0 : 1` threshold convention.
- **REDUNDANT-DRAW CONTRACT (cross-backend lockstep)**: consume exactly ONE
  `:born_measurement` draw per measured site — *unconditionally*, even when
  the backend can determine the outcome without randomness. If the outcome
  is deterministic, draw anyway and **discard** the value. This is what
  keeps the `:born_measurement` stream position identical across backends,
  so "same seed ⇒ same trajectory" holds backend-independently. The generic
  method satisfies this structurally (it always draws before the cumulative
  probability loop); the Clifford override satisfies it with an explicit
  redundant draw before `projectZ!` (`src/Clifford/measurement.jl`).
  Guarded by `test/audit/born_measurement.jl` (e) and
  `test/audit/cross_backend.jl` (b). (Historical note: pre-v0.4.0-release
  Clifford consumed zero draws for deterministic outcomes — a resolved
  divergence, one-time trajectory break documented in CHANGELOG 0.4.0.)
- Emit the event exactly like the generic does: when
  `state.event_log !== nothing`, push
  `MeasurementOutcome(state.event_step, state.event_op_idx, [site], outcome)`
  via `log_event!`.

### 4. `born_probability(state, site, outcome) -> Float64`

Read-only, non-destructive single-site Born probability. Required: the
default measurement primitive and the `BornProbability` observable both call
it. Current method table (3 methods — fully typed on all backends, no generic
fallback):

| Method | Defined in |
|---|---|
| `(::SimulationState{MPSBackend}, ::Int, ::Int)` | `src/Observables/born.jl` |
| `(::SimulationState{StateVectorBackend}, ::Int, ::Int)` | `src/StateVector/measurement.jl` |
| `(::SimulationState{CliffordBackend}, ::Int, ::Int)` | `src/Clifford/measurement.jl` |

Must not mutate the state (the Clifford method operates on a tableau copy).

### 5. Observables — implement or reject, per observable

Observables are callable structs (see `AbstractObservable`): the generic call
`(obs)(state)` is the MPS path; backends add specific methods or explicit
`ArgumentError` rejections. Support matrix as shipped:

| Observable | MPS | StateVector | Clifford |
|---|---|---|---|
| `EntanglementEntropy` | ✓ generic (`src/Observables/entanglement.jl`) | ✓ (`src/StateVector/entanglement.jl`) | ✓ GF(2)-rank formula (`src/Clifford/entanglement.jl`) |
| `Magnetization` | ✓ `:X`/`:Y`/`:Z` via `expect` | `:Z` only; `:X`/`:Y` → `ArgumentError` (`src/StateVector/magnetization.jl`) | `:Z` only; `:X`/`:Y` → `ArgumentError` (`src/Clifford/magnetization.jl`) |
| `BornProbability` | ✓ | ✓ | ✓ (one generic callable in `src/Observables/born.jl`; backend dispatch happens inside, via `born_probability`) |
| `StringOrder` | ✓ generic (`src/Observables/string_order.jl`) | ✓ (`src/StateVector/string_order.jl`) | ✗ `ArgumentError` rejection (`src/Clifford/observables.jl`) |
| `DomainWall` | ✓ generic callable + `domain_wall(state, i1, order)` helper | ✓ via `domain_wall` override (`src/StateVector/domain_wall.jl`) | ✗ `ArgumentError` rejection (`src/Clifford/observables.jl`) |

Method-count fingerprint (what `methods()` reports on an instance): 3 for
`EntanglementEntropy`, 3 for `Magnetization`, 3 for `StringOrder`, 4 for
`DomainWall` (generic + Clifford, ×2 each from the optional `i1` argument),
1 for `BornProbability`; plus 2 methods of the `domain_wall` function.

Two override styles, both used:

- **Override the callable**: `(obs::StringOrder)(state::SimulationState{StateVectorBackend})`.
- **Override an inner helper**: `DomainWall`'s generic callable delegates to
  `domain_wall(state, i1, order)`, and the StateVector backend specializes
  that function instead. Either level works; pick whichever avoids
  duplicating shared logic.

Rejections must be `ArgumentError`s that name the observable, the backend,
and the working alternatives (pattern: `src/Clifford/observables.jl`).

### What backends must NOT touch

The following layers are backend-agnostic and dispatch to the primitives
above — a backend never overrides them:

- `apply!` and the `_apply_dispatch!` geometry handlers (`src/Core/apply.jl`)
- the `execute!` protocol layer, including the `Measure`/`Reset` overrides
  (`src/Core/apply.jl`) — these route through `_measure_single_site!` and
  `_apply_single!` and work on every backend automatically
- the circuit engine (`src/Circuit/execute.jl`), stochastic rule
  (`src/API/probabilistic.jl`), and `track!`/`record!`/`simulate!`
- feedback plumbing (`apply_feedback!`, `with_guarded_stream`)

## [RNG expectations](@id backend-interface-rng)

Backend primitives may only touch the streams below, always via
`get_rng(state.rng_registry, stream)` and scalar draws (never vectorized
`rand(rng, n)` for decisions — SCALAR-DRAW CONTRACT, `src/Core/rng.jl`):

| Stream | Consumed by (backend-side) | Contract |
|---|---|---|
| `:state_init` | `RandomMPS` / `RandomStateVector` `initialize!` | only at initialization; same seed ⇒ identical state |
| `:gates_realization` | random-content gates: `HaarRandom` (`build_operator` / `gate_matrix`), `RandomClifford` (native sampling on Clifford; `gate_matrix` on SV) | one gate draw per application, independent of measurement outcomes |
| `:born_measurement` | `_measure_single_site!` (and `SpinSectorMeasurement`) | exactly ONE scalar draw per measured site on ALL backends — a redundant, discarded draw when the outcome is deterministic (REDUNDANT-DRAW CONTRACT, see §3): stream positions stay in cross-backend lockstep |
| `:gates_spacetime` | **NEVER** | engine-owned: `apply_with_prob!` categorical coins. During measurement feedback it is actively guarded — `with_guarded_stream` swaps in a `SentinelRNG` that throws on any draw |

## Conventions a backend must respect

- **Site 1 = MSB.** Bit patterns, `kron` order, and state-vector digit
  extraction (`(n ÷ d^(L-s)) % d`) all follow the CT.jl convention: physical
  site 1 is the most significant digit.
- **Physical vs RAM indexing.** All public API and all geometry expansion
  speak PHYSICAL sites; primitives translate via `state.phy_ram` (and
  reorder init data via `state.ram_phy`). Identity for StateVector/Clifford;
  a zig-zag fold for MPS under PBC.
- **PBC `EntanglementEntropy(cut=k)` semantics differ by design** (v0.4.0
  audit finding): the MPS backend interprets `cut` as a RAM bond of the
  folded MPS (only `cut = L÷2` is fold-aligned with a physical bipartition),
  while StateVector/Clifford use the physical `{1..k}` bipartition. Under
  OBC all three agree at every cut. Cross-backend entropy comparisons under
  PBC must use `cut = L÷2` or OBC.
- **`state.mps` / `state.sites` / `state.cutoff` / `state.maxdim` are
  supported API on `SimulationState{MPSBackend}`** — property forwarding to
  `state.backend.<field>`, kept deliberately (v0.4.0 decision; see
  `Base.getproperty(::SimulationState{MPSBackend}, ::Symbol)` in
  `src/State/State.jl`). It is MPS-only: other backends intentionally raise
  `FieldError` on these names. New backends must NOT add analogous
  forwarding; internal (`src/`) code must use `state.backend.<field>`
  directly.

## [Verifying this document](@id backend-interface-verify)

The method tables above are checkable mechanically:

```julia
using QuantumCircuitsMPS
const QCM = QuantumCircuitsMPS

length(methods(QCM._apply_single!))        # == 12  (1 MPS generic + 1 SV + 10 Clifford)
length(methods(QCM._measure_single_site!)) # == 2   (generic MPS/SV + Clifford)
length(methods(QCM.initialize!))           # == 5   (2 MPS generic + 2 SV + 1 Clifford)
length(methods(QCM.born_probability))      # == 3   (MPS + SV + Clifford)

length(methods(EntanglementEntropy(cut = 1)))  # == 3
length(methods(Magnetization(:Z)))             # == 3
length(methods(StringOrder(1, 5)))             # == 3
length(methods(DomainWall(order = 1)))         # == 4
length(methods(BornProbability(1, 0)))         # == 1
length(methods(QCM.domain_wall))               # == 2
```

If a count changes, this page is stale: update the corresponding table in
the same PR that adds/removes the method.
