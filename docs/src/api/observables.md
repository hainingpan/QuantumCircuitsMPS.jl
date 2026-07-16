```@meta
CurrentModule = QuantumCircuitsMPS
```

# Observables

Callable-struct observables (`obs(state)`), tracked via `track!`/`record!`.
See [Observables Catalog](@ref) below for a backend-support summary of the
new v0.4.0 observables, and [Custom Observables](@ref) for writing your own.

```@docs
AbstractObservable
EntanglementEntropy
Magnetization
BornProbability
born_probability
StringOrder
DomainWall
PauliString
MutualInformation
Correlator
EntropyProfile
TripartiteMutualInformation
MagnetizationFluctuations
track!
record!
list_observables
```

## Observables Catalog

New in v0.4.0: `PauliString` and `MutualInformation` (T24/T25), plus four
observables composed on top of them (T38). All six are supported on **all
three backends** (MPS, state vector, Clifford):

| Observable | Formula | Backend notes |
|---|---|---|
| [`PauliString`](@ref) | ``\langle \textstyle\prod_k P_k \rangle`` for a product of single-qubit Paulis on distinct sites | Qubit-only; MPS via local `op` insertion, SV via direct amplitude action, Clifford via `QuantumClifford.expect` (poly-time, exact ∈ {−1,0,+1}) |
| [`MutualInformation`](@ref) | ``I(A\!:\!B) = S(A)+S(B)-S(A\cup B)`` for two contiguous, disjoint regions | Physical-site regions on every backend, cross-backend unambiguous under both boundary conditions (unlike `EntanglementEntropy`'s PBC `cut`); MPS size-guarded at `d^{|A|+|B|} \le 256` |
| [`Correlator`](@ref) | ``C(i,j)=\langle P_iP_j\rangle-\langle P_i\rangle\langle P_j\rangle`` | Pure composition of three `PauliString` calls; `i == j` rejected |
| [`EntropyProfile`](@ref) | ``[S(\text{cut}=x)\ \text{for}\ x=1..L-1]`` (vector-valued) | Composition of `EntanglementEntropy` at every cut; inherits its MPS PBC RAM-bond caveat — use `bc=:open` for cross-backend comparison |
| [`TripartiteMutualInformation`](@ref) | ``I_3 = I(A\!:\!B)+I(A\!:\!C)-I(A\!:\!BC)`` (Gullans–Huse convention) | Composition of three `MutualInformation` calls; `B∪C` must be contiguous; standard MIPT usage is four quarters with a fourth region traced out |
| [`MagnetizationFluctuations`](@ref) | ``\mathrm{Var}(M)`` for ``M=\sum_{i\in R}P_i`` | ``O(\lvert R\rvert^2)`` composition of `PauliString`; diagonal ``P_i^2=I`` special-cased analytically |

Vector-valued observables (`EntropyProfile`) record through the same
`track!`/`record!`/`simulate!` pipeline as scalar ones — the storage
container transparently widens from `Vector{Float64}` to `Vector{Any}` at
the first vector-valued record (see [Custom Observables](@ref) and
`track!`'s docstring).
