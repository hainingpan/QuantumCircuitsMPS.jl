# === Circuit Type ===
# Lazy/symbolic representation of quantum circuit operations

"""
    Circuit(; L::Int, bc::Symbol, operations=NamedTuple[])

Lazy representation of a quantum circuit as a sequence of symbolic operations.

A `Circuit` does NOT execute immediately - it stores operations symbolically and
expands them to concrete gate applications only when passed to `simulate!`.

A `Circuit` always represents ONE time step. Repeat execution is controlled by
`simulate!(circuit, state; n_steps=...)`.

# Fields
- `L::Int`: Number of physical sites in the system
- `bc::Symbol`: Boundary conditions (`:periodic` or `:open`)
- `operations::Vector{NamedTuple}`: Internal symbolic operation list
- `params::Dict{Symbol,Any}`: User-defined parameters (default: empty Dict)

# Operation Representation
Operations are stored as NamedTuples with different formats:

**Deterministic gates:**
```julia
(type = :deterministic, gate = gate, geometry = geometry)
```

**Stochastic outcomes (apply_with_prob!):**
```julia
(type = :stochastic, rng = :gates_spacetime, outcomes = [(probability=p, gate=g, geometry=geo), ...])
```

# Construction
Users construct circuits via the do-block API (see `CircuitBuilder`):

```julia
circuit = Circuit(L=10, bc=:periodic) do c
    apply!(c, Hadamard(), SingleSite(1))
    apply!(c, CNOT(), StaircaseRight(1), steps=5)
end
```

# Execution
Pass the circuit to `simulate!` to execute:

```julia
state = SimulationState(...)
simulate!(circuit, state; n_steps=50)  # Runs the circuit 50 times
```

# See Also
- `expand_circuit`: Expands symbolic operations to concrete site lists
- `simulate!`: Executes a circuit on a simulation state
"""
Base.@kwdef struct Circuit
    L::Int
    bc::Symbol
    operations::Vector{NamedTuple} = NamedTuple[]
    params::Dict{Symbol, Any} = Dict{Symbol, Any}()
end

"""
    Base.copy(circuit::Circuit) -> Circuit

Deep copy of a circuit, including its geometries. This is THE per-trajectory
pattern for thread safety: staircase/`Pointer` geometries are mutable (their
positions advance during `simulate!`), so concurrent trajectories must each
own a private copy of the circuit.

`copy` is implemented as `deepcopy`, which preserves INTRA-circuit geometry
aliasing: if the same staircase object appears in several operations of the
original, the copies also share one (new) object — required for CIPT-style
shared random-walk positions.

```julia
Threads.@threads for seed in seeds
    c = copy(circuit)                       # private geometry state
    st = SimulationState(...; rng=RNGRegistry(gates_spacetime=seed, ...))
    initialize!(st, ProductState(binary_int=0))
    simulate!(c, st; n_steps=n)
end
```
"""
Base.copy(circuit::Circuit) = deepcopy(circuit)
