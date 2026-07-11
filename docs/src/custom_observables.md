# Custom Observables

Every built-in observable in QuantumCircuitsMPS.jl — `EntanglementEntropy`,
`Magnetization`, `PauliString`, … — is a *callable struct*: an instance holds
the observable's parameters and is evaluated on a state as `obs(state)`.
The tracking API generalizes this all the way down: **`track!` accepts any
callable** `f(state)`, not just the built-in types. A closure, a plain
function, or a struct of your own all work identically through
`track!` / `record!` / `simulate!`, on all three backends (MPS, state
vector, Clifford).

```julia
track!(state, :edge => s -> born_probability(s, 1, 0))   # that's it
simulate!(circuit, state; n_steps = 50, record_when = :every_step)
state.observables[:edge]                                  # 50 recorded values
```

There is no plugin framework and no registration macro — the contract below
IS the extension mechanism.

## The callable contract

A tracked callable `f` is invoked as `f(state)` at every record point (an
eager `record!(state)` call, or the points selected by `simulate!`'s
`record_when` policy). It must obey three rules:

1. **Read-only physics.** `f` may freely *read* the state — through the
   building blocks below, or `state.L`, `state.bc`, `state.local_dim`, the
   event log, … — but it must NOT mutate the quantum state: no `apply!`, no
   measurements, no RNG draws. Recording an observable must never change
   the trajectory.
2. **Return a scalar or a vector.** `f(state)` returns a `Number` (typically
   `Float64`) or an `AbstractVector` (e.g. a per-site profile). Each record
   point appends exactly ONE entry to `state.observables[name]` — a returned
   vector is stored as a single element, not splatted.
3. **Errors propagate.** An exception thrown by `f` aborts the `record!`
   call. For custom callables it is wrapped in an `ErrorException` naming
   the observable key (with the original exception attached as
   `caused by:`), so a failing tracker is diagnosable among many.

Storage: generic callables record into a `Vector{Any}`; built-in
(`AbstractObservable`) instances keep the scalar `Vector{Float64}`
container (transparently widened to `Vector{Any}` if such an observable
returns a vector).

## Public building blocks

Custom observables are compositions of the same public pieces the built-ins
use. Since built-in observables are callable structs, any instance can be
evaluated inline inside your own callable:

| Building block | What it computes |
|---|---|
| `born_probability(state, site, outcome)` | Born probability ``P(\text{outcome})`` at a physical site |
| `PauliString(i => :Z, j => :Z, ...)(state)` | ``\langle \prod_k P_k \rangle`` for any single-qubit Pauli product |
| `EntanglementEntropy(cut = k, renyi_index = n)(state)` | Rényi-``n`` / von Neumann entropy across a cut |
| `MutualInformation` (new in v0.4.0) | mutual information ``I(A\!:\!B)`` between two regions |
| `Magnetization(:Z)(state)` | ``\tfrac{1}{L}\sum_i \langle Z_i \rangle`` |
| `StringOrder(i, j; order)(state)` | spin-1 string order parameter |
| `measurements(state)`, `events(state)` | typed event log (requires `SimulationState(...; log_events = true)`) |

The three worked examples below go from a one-line closure to a fully
dispatched struct observable.

## Example (a): a custom order parameter from a closure

An edge-polarization imbalance ``\Delta = P(q_1{=}0) - P(q_L{=}0)`` —
useful, for instance, to watch how a control protocol pins the chain ends —
is a one-liner composed from `born_probability`:

```julia
using QuantumCircuitsMPS

L = 8
circuit = Circuit(L = L, bc = :open) do c
    apply!(c, HaarRandom(), Bricklayer(:odd))
    apply_with_prob!(c; outcomes = [
        (probability = 0.2, gate = Measure(:Z), geometry = AllSites()),
    ])
end

state = SimulationState(L = L, bc = :open, maxdim = 64,
    rng = RNGRegistry(gates_spacetime = 42, gates_realization = 2,
        born_measurement = 3))
initialize!(state, ProductState(binary_int = 0))

# ANY callable f(state) — closures included. `s.L` reads the system size.
edge_imbalance = s -> born_probability(s, 1, 0) - born_probability(s, s.L, 0)
track!(state, :edge => edge_imbalance)

simulate!(circuit, state; n_steps = 10, record_when = :every_step)
state.observables[:edge]    # 10 values, one per step
```

Vector returns work the same way — track a full Born-probability profile
and each record point appends one `Vector{Float64}`:

```julia
track!(state, :profile => s -> [born_probability(s, i, 0) for i in 1:s.L])
```

## Example (b): a custom correlator composing `PauliString`

`PauliString` evaluates ``\langle \prod_k P_k \rangle`` for arbitrary Pauli
products, which makes connected correlation functions
``C(i,j) = \langle Z_i Z_j \rangle - \langle Z_i \rangle \langle Z_j \rangle``
a three-line composition. Writing a small *factory function* keeps the
site indices as parameters:

```julia
using QuantumCircuitsMPS

connected_correlator(i, j) = state ->
    PauliString(i => :Z, j => :Z)(state) -
    PauliString(i => :Z)(state) * PauliString(j => :Z)(state)

# Bell pair on sites (1, 2): ⟨Z₁Z₂⟩ = 1, ⟨Z₁⟩ = ⟨Z₂⟩ = 0 ⇒ C(1,2) = 1
state = SimulationState(L = 2, bc = :open, backend = :statevector,
    rng = RNGRegistry(gates_spacetime = 1, gates_realization = 2,
        born_measurement = 3))
initialize!(state, ProductState(binary_int = 0))
apply!(state, Hadamard(), SingleSite(1))
apply!(state, CNOT(), Sites([1, 2]))

track!(state, :c12 => connected_correlator(1, 2))
record!(state)
state.observables[:c12]     # Any[1.0]
```

The same factory works tracked through `simulate!`, and — because
`PauliString` is implemented on all three backends — on `:mps`,
`:statevector`, and `:clifford` states alike.

## Example (c): a struct-based observable (advanced path)

When a custom observable carries parameters you want visible in dispatch,
or needs recording-time behavior beyond a plain call, subtype
[`AbstractObservable`](@ref) and (optionally) override the
`record_value` hook — exactly the pattern the built-in `DomainWall` uses to
resolve its sampling site at record time:

```julia
using QuantumCircuitsMPS

"""
    ClampedProbability(site)

Born probability P(site = 0), clamped to [0, 1] at record time to scrub
float dust (e.g. 1.0000000000000002 from an MPS contraction).
"""
struct ClampedProbability <: QuantumCircuitsMPS.AbstractObservable
    site::Int
end

# the observable's call protocol — same as every built-in
(obs::ClampedProbability)(state) = born_probability(state, obs.site, 0)

# OPTIONAL: hook the recording step itself (record! consumes this, not
# obs(state) directly). Keep the `i1` keyword in the signature.
function QuantumCircuitsMPS.record_value(obs::ClampedProbability, state;
        i1 = nothing)
    return clamp(obs(state), 0.0, 1.0)
end

state = SimulationState(L = 4, bc = :open, maxdim = 16,
    rng = RNGRegistry(gates_spacetime = 1, gates_realization = 2,
        born_measurement = 3))
initialize!(state, ProductState(binary_int = 0))
track!(state, :p1 => ClampedProbability(1))
record!(state)
state.observables[:p1]      # [1.0] — stored in a Vector{Float64}
```

What subtyping buys you over a closure:

- **Scalar storage**: `AbstractObservable` specs record into a
  `Vector{Float64}` instead of a `Vector{Any}`.
- **The `record_value` hook**: recording-time context (like `record!`'s
  `i1` keyword) and value post-processing live in one overridable method.
- **Backend dispatch**: you can provide per-backend methods
  (`(obs::MyObs)(state::SimulationState{StateVectorBackend}) = ...`) or
  throw an informative `ArgumentError` on unsupported backends, exactly
  like the built-ins (see the developer docs on the backend interface).

For everything else, a closure is the shorter path.

## Error behavior

A tracked callable that throws does not fail silently and does not record a
placeholder — the error aborts `record!` and names the offending key:

```julia
track!(state, :bad => s -> error("boom"))
record!(state)
# ERROR: record!: custom observable :bad (var"#3#4") threw while recording —
# see the underlying exception below (`caused by:`).
# ...
# caused by: boom
```

Built-in observables are not wrapped: they throw their own typed,
documented errors (e.g. `DomainWall`'s `ArgumentError` when no sampling
site is available, or `StringOrder`'s rejection on the Clifford backend).
