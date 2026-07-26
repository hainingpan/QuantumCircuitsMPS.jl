# Custom Gates

Every built-in gate in QuantumCircuitsMPS.jl — `PauliX`, `Hadamard`,
`HaarRandom`, `Projection`, `Measure`, … — is a subtype of the exported
[`AbstractGate`](@ref), and `apply!` accepts **any** conforming subtype:
your own types travel through `apply!` / `Circuit` / `simulate!` exactly
like the built-ins.

There is no plugin framework and no registration macro — the contract below
IS the extension mechanism. It is exercised by the package's own test suite
with **zero `src/` edits** (`test/execute_protocol.jl`), which is where the
examples on this page come from.

One thing to know up front: the protocol *functions* are **not exported**
(only the `AbstractGate` type is). An extension therefore writes the
module-qualified name:

```julia
QuantumCircuitsMPS.support(::MyGate) = 1        # ✓ adds a method to the protocol
support(::MyGate) = 1                           # ✗ defines a NEW local function
```

The second form silently creates an unrelated function in your own module,
and `apply!` fails later with a `MethodError`. Qualify **every** protocol
method: `QuantumCircuitsMPS.support`, `.build_operator`, `.gate_matrix`,
`.needs_normalization`, `.is_measurement`, `.execute!`.

If all you want is one specific unitary — no new type, no dispatch — you do
not need any of this: the built-in [`MatrixGate`](@ref) takes an explicit
matrix directly (`apply!(state, MatrixGate(U), SingleSite(1))`). Define your
own gate type when the gate carries parameters you want visible in dispatch,
needs a trait, or needs non-operator execution semantics.

## The gate contract

A gate type participates through a small, method-based protocol. Nothing is
registered; each method you define is simply found by dispatch.

1. **Always required** — `QuantumCircuitsMPS.support(gate) -> Int`: the
   number of sites the gate acts on (`1` for single-site, `2` for two-site).
   The engine validates this against the region resolved from the geometry.
2. **MPS backend** —
   `QuantumCircuitsMPS.build_operator(gate, site_or_sites, local_dim; kwargs...) -> ITensor`:
   the operator tensor, with the **primed** index as output. The single-site
   method takes one `Index`, the two-site method a `Vector{<:Index}` in RAM
   order. The signature **must** end in `; kwargs...`: the engine always
   passes `rng=`, and for two-site gates additionally `mps=` and
   `ram_sites=`; a signature without `kwargs...` is a `MethodError`.
3. **State-vector backend** —
   `QuantumCircuitsMPS.gate_matrix(gate) -> Matrix{ComplexF64}`: the dense
   matrix, `U[out, in] = ⟨out|U|in⟩`, in Kronecker (row-major site) ordering
   — the FIRST site of the region is the slowest basis digit, so
   `kron(A, B)` acts with `A` on the first site.
4. **Opt-in traits** (both default to `false`, so unitaries need neither) —
   `QuantumCircuitsMPS.needs_normalization(gate) -> Bool`: `true` for
   non-unitary gates, so the backend renormalizes after applying (and, on
   MPS, truncates); `QuantumCircuitsMPS.is_measurement(gate) -> Bool`:
   `true` for gates that Born-sample via the `:born_measurement` RNG stream.
5. **Full override** —
   `QuantumCircuitsMPS.execute!(state, gate, region::Vector{Int})`: replaces
   the default `build_operator` → apply → (maybe) normalize path entirely,
   for gates whose semantics are not "multiply by an operator" (Born
   sampling, classical feedback, composite sequences).

Which of these you need depends on where the gate must run:

- `backend = :mps` (default): `support` + `build_operator`.
- `backend = :statevector`: `support` + `gate_matrix`.
- both: define all three, as in example (a) below.
- an `execute!` override replaces requirements 2–3 on whichever backends the
  override itself supports.

## Example (a): a custom unitary gate

`SqrtX` is the "square root of NOT": `U² = X`, and `U|0⟩` has equal weight
on `|0⟩` and `|1⟩`. Defining `build_operator` **and** `gate_matrix` makes
one type run unchanged on both dense backends.

```julia
using QuantumCircuitsMPS
using ITensors

struct SqrtX <: QuantumCircuitsMPS.AbstractGate end

QuantumCircuitsMPS.support(::SqrtX) = 1

const U = 0.5 * ComplexF64[1+im 1-im; 1-im 1+im]

# MPS backend. `ITensor(U, prime(site), site)` is the generic arbitrary-matrix
# pattern (primed index = output) — the same one `MatrixGate` uses. Do NOT
# reach for `op("...")` here: that only works for operator names ITensors
# already knows, not for a matrix you invented.
function QuantumCircuitsMPS.build_operator(::SqrtX, site::Index, local_dim::Int; kwargs...)
    return ITensor(U, prime(site), site)
end

# State-vector backend: the same matrix, dense.
QuantumCircuitsMPS.gate_matrix(::SqrtX) = U

state = SimulationState(L=2, bc=:open, maxdim=16,
    rng=RNGRegistry(gates_spacetime=1, gates_realization=2, born_measurement=3))
initialize!(state, ProductState(binary_int=0))
apply!(state, SqrtX(), SingleSite(1))
println("P0_mps = ", born_probability(state, 1, 0))

state2 = SimulationState(L=2, bc=:open, backend=:statevector,
    rng=RNGRegistry(gates_spacetime=1, gates_realization=2, born_measurement=3))
initialize!(state2, ProductState(binary_int=0))
apply!(state2, SqrtX(), SingleSite(1))
println("P0_sv = ", born_probability(state2, 1, 0))
```

Both lines print `0.5` — the same gate, the same physics, on the MPS and
state-vector backends. No trait is needed: `SqrtX` is unitary, so the
default `needs_normalization(gate) == false` is correct and the backends
skip renormalization.

## Example (b): a custom projective gate

Non-unitary gates shrink the norm, so they must opt into renormalization
with the `needs_normalization` trait. `MyProjection` is the projector
`|0⟩⟨0|` on one site — here `build_operator` *can* use `op("Proj0", site)`,
because `"Proj0"` is a name the qubit site type already defines. (It is
written `ITensors.op` below because `ITensors` does not export `op` at top
level; `ITensor`, `Index`, and `prime` in example (a) are exported.)

```julia
using QuantumCircuitsMPS
using ITensors

struct MyProjection <: QuantumCircuitsMPS.AbstractGate end

QuantumCircuitsMPS.support(::MyProjection) = 1

function QuantumCircuitsMPS.build_operator(::MyProjection, site::Index, local_dim::Int; kwargs...)
    return ITensors.op("Proj0", site)
end

# Non-unitary ⇒ opt in. Without this line the state stays un-normalized and
# every subsequent Born probability is wrong.
QuantumCircuitsMPS.needs_normalization(::MyProjection) = true

state = SimulationState(L=2, bc=:open, maxdim=16,
    rng=RNGRegistry(gates_spacetime=1, gates_realization=2, born_measurement=3))
initialize!(state, ProductState(binary_int=0))
apply!(state, Hadamard(), SingleSite(1))      # |+⟩ on site 1: P(0) = 0.5
apply!(state, MyProjection(), SingleSite(1))
println("P0_proj = ", born_probability(state, 1, 0))
```

This prints `1.0`: applying `|0⟩⟨0|` to `|+⟩` leaves a state of norm
`1/√2`, and the trait tells the backend to fix that. Concretely, the MPS
backend renormalizes **and** truncates at the state's `cutoff` after such a
gate, while the state-vector backend only renormalizes (a state vector has
no bond dimension to truncate). The trait is the only difference between a
projector that produces correct probabilities and one that quietly does not.

Note that `needs_normalization` and `is_measurement` are independent:
`is_measurement` marks gates that *Born-sample* (consuming the
`:born_measurement` stream), which a deterministic projector does not do.

## Example (c): overriding execute! (advanced path)

Some gates are not "multiply the state by an operator" at all. When the
semantics involve Born sampling, classical feedback, or a composition of
several primitive steps, override `QuantumCircuitsMPS.execute!` instead of
`build_operator` — this is exactly how the in-repo `Measure` and `Reset`
gates are implemented. `region` is the vector of physical sites already
resolved from the geometry.

```julia
using QuantumCircuitsMPS

struct MyFlip <: QuantumCircuitsMPS.AbstractGate end

QuantumCircuitsMPS.support(::MyFlip) = 1

function QuantumCircuitsMPS.execute!(state::SimulationState, ::MyFlip, region::Vector{Int})
    # Delegate to the default path with a stock PauliX — overrides compose.
    QuantumCircuitsMPS.execute!(state, PauliX(), region)
    return nothing
end

state = SimulationState(L=2, bc=:open, maxdim=16,
    rng=RNGRegistry(gates_spacetime=1, gates_realization=2, born_measurement=3))
initialize!(state, ProductState(binary_int=0))
apply!(state, MyFlip(), SingleSite(1))
println("P1_flip = ", born_probability(state, 1, 1))
```

This prints `1.0`. Reach for the override when your gate needs to:

- **Born-sample** an outcome and branch on it (the `Measure` pattern),
- **apply classical feedback** after an outcome (`Measure` with
  `OnOutcome` / a callback),
- **compose several gates** into one logical operation (the `Reset`
  pattern: measure, then conditionally flip).

Because an override can delegate to `execute!` on other gates, composite
semantics stay backend-agnostic: the delegated primitives take whichever
backend path they already support.

## Per-backend support

| Backend | What a custom gate must define | Reach |
|---|---|---|
| `:mps` (default) | `support` + `build_operator` | Generic path — any conforming gate runs |
| `:statevector` | `support` + `gate_matrix` | Generic path — any conforming gate runs |
| `:clifford` | — (closed whitelist) | Unknown gates rejected with `ArgumentError` |
| `:gaussian` | — (closed whitelist) | Unknown gates rejected with `ArgumentError` |

The two dense backends are open: they resolve *any* `AbstractGate` subtype
through the protocol above. The Clifford and Gaussian backends are not.
A stabilizer tableau can only represent Clifford-group operations, and a
covariance matrix only fermionic Gaussian ones, so both ship a rejecting
fallback rather than silently approximating:

- Clifford accepts `PauliX`, `PauliY`, `PauliZ`, `Hadamard`, `PhaseGate`,
  `CZ`, `CNOT`, `SWAP`, `RandomClifford`, `Measure`, `Reset`.
- Gaussian accepts `GaussianHaar`, `PauliX`, `Measure(:Z)`, `BondParity`,
  `Reset`.

Anything else raises an `ArgumentError` naming the offending gate type; the
verbatim Clifford message is shown in the next section.

**The whitelist gates the default application path, not the gate type.**
It is enforced in the backends' generic apply step, so a gate that overrides
`execute!` and is composed purely of whitelisted primitives also runs there.
Example (c)'s `MyFlip` delegates to `PauliX`, so it works on the Clifford
backend, and on the Gaussian backend at its **default** fermionic-mode
granularity — but **not** with `site_type="Majorana"`, where `PauliX` itself
is rejected with an `ArgumentError` (a single Majorana site has no
occupation to flip; see the [Gaussian Backend](@ref) page).

For anything more exotic on Clifford or Gaussian, the supported escape hatch
is `backend=:mps` or `backend=:statevector`. Per-backend application methods
are technically reachable via open dispatch, but they are underscore-private
internal API with no stability guarantee — do not build on them.

## Error behavior

A gate the Clifford backend cannot represent is rejected loudly at apply
time, naming the offending type:

```julia
using QuantumCircuitsMPS

struct NotClifford <: QuantumCircuitsMPS.AbstractGate end
QuantumCircuitsMPS.support(::NotClifford) = 1

state = SimulationState(L=2, bc=:open, backend=:clifford,
    rng=RNGRegistry(gates_spacetime=1, gates_realization=2, born_measurement=3))
initialize!(state, ProductState(binary_int=0))
apply!(state, NotClifford(), SingleSite(1))
```
```
ArgumentError: Clifford backend only supports Clifford gates (PauliX, PauliY, PauliZ, Hadamard, PhaseGate, CZ, CNOT, SWAP, RandomClifford, Measure, Reset). Received: NotClifford. Please switch to backend=:mps or backend=:statevector for non-Clifford gates.
```

The Gaussian backend behaves identically with its own gate list. Note that
the error names your concrete type, so a typo'd or missing method is easy to
localize — whereas a *missing* `QuantumCircuitsMPS.` qualification produces
a `MethodError` on `support` or `build_operator` instead, on every backend.

## See Also

- [Custom Observables](@ref) — the same open-contract philosophy for what
  you measure, with three worked examples
- [Backend Interface Contract](@ref) — the developer-side contract each
  backend implements, and which generic paths a custom gate rides
- [API Reference](@ref) — every exported gate, geometry, and observable
- [Tutorials](@ref) — end-to-end circuits, including `MatrixGate` and
  feedback in context
