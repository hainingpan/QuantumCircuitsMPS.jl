# MPS Backend

The MPS (Matrix Product State) backend is the **default** backend and the
package's namesake: it represents the quantum state as a matrix product
state via [ITensors.jl](https://github.com/ITensor/ITensors.jl) and
[ITensorMPS.jl](https://github.com/ITensor/ITensorMPS.jl), truncating the
bond dimension at every gate application according to `cutoff`/`maxdim`.
This is what lets it scale to `L = 100+` qubits for the entangling-but-not-
maximally-entangling circuits typical of MIPT/CIPT studies, at the cost of a
controlled truncation error.

**When to use it**: the general-purpose default — production runs at
`L = 100+`, or any circuit whose entanglement growth stays bounded by a
reasonable `maxdim` (measurement-induced and control-induced phase
transitions are exactly this regime, by construction: measurements and
resets keep entanglement in check).

**When not to use it**: when you need an *exact* zero-truncation-error
reference (see [State Vector Backend](@ref)), or when the circuit is built
entirely from Clifford-group gates and you want to push `L` into the
hundreds or thousands (see [Clifford Backend](@ref)).

## Quick Example

```julia
using QuantumCircuitsMPS

state = SimulationState(L=12, bc=:periodic, maxdim=64,
    rng=RNGRegistry(gates_spacetime=42, gates_realization=1, born_measurement=2))
initialize!(state, ProductState(binary_int=0))
track!(state, :entropy => EntanglementEntropy(; cut=6))

apply!(state, HaarRandom(), Bricklayer(:even))
apply!(state, HaarRandom(), Bricklayer(:odd))
record!(state)
println("Entropy: $(state.observables[:entropy][end])")
```

`backend=:mps` is the default and can be omitted from `SimulationState(...)`.
`cutoff` (SVD truncation threshold, default `1e-10`) and `maxdim` (maximum
bond dimension, default `100`) are MPS-only keywords — they are silently
ignored on the other two backends for cross-backend API consistency (see the
[Backend Interface Contract](@ref)).

## Internal Engine

Every `apply!` call resolves a gate to an `ITensor` via `build_operator`,
then contracts and truncates it back into the MPS via
`apply_op_internal!` (SVD-based contraction with re-orthogonalization). See
[Design Philosophy](@ref) for the full layered picture and
[Backend Interface Contract](@ref) for the developer-facing method table
every backend (including this one) must implement.

## PBC Indexing Caveat

Under `bc=:periodic`, the MPS backend stores sites in a **folded** RAM
ordering (`src/Core/basis.jl`) so that periodic boundary conditions can be
represented by a 1-D chain topology. All public geometry/gate/observable
APIs speak *physical* site indices and translate transparently — except
`EntanglementEntropy(cut=k)`, whose `cut` is the RAM bond index of the
folded MPS, not the physical bipartition `{1..k}` (only `cut = L÷2` is
fold-aligned). See the [Backend Interface Contract](@ref)'s PBC section and
`EntropyProfile`'s docstring for the full detail; cross-backend entropy
comparisons under PBC should use `cut = L÷2` or `bc=:open`.
