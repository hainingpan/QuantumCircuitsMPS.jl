# QuantumCircuitsMPS.jl - PyTorch-like Quantum Circuit Simulation Framework

## Context

### Original Request
Create an abstraction layer for the existing CT.jl package to build a PyTorch-like framework for quantum circuit simulation with MPS. The goal is to open-source a package where users can focus on physics ideas while the framework handles technical MPS details.

### Interview Summary
**Key Discussions**:
- **Philosophy**: Physics-first API that hides MPS/ITensor internals
- **PyTorch analogy**: Composable `forward()` pattern with modular gallery
- **API syntax**: Implicit state context - `bricklayer!(HaarGate()); Z()` instead of `apply!(state, ...)`
- **Extensibility**: Users can define custom gates, measurements, observables
- **Organization**: Submodules (Gates, Measurements, Observables, Patterns, Core)
- **RNG**: `seed_circuit` + `seed_meas` with smart defaults, user-extensible
- **Geometry**: `periodic` option for boundary conditions

**Research Findings**:
- Julia uses abstract types + multiple dispatch (not inheritance)
- Package name "QuantumCircuitsMPS.jl" is available
- CT.jl contains all necessary algorithms to port

### Reference Implementation
- CT.jl (`CT/src/CT.jl`) - 1500+ lines of working MPS simulation code
- Example scripts: `run_CT_MPS_*.jl` - 30+ examples showing usage patterns

---

## Critical Design Decisions

### v1 Scope Constraints
**v1 focuses on periodic boundary conditions with even system sizes.** This matches CT.jl's folded MPS approach.

| Feature | v1 Status | Rationale |
|---------|-----------|-----------|
| Even L | REQUIRED | Folded basis uses `zip(1:L÷2, reverse(L÷2+1:L))`, needs even L |
| Odd L | NOT supported | `ArgumentError("L must be even")` thrown by constructor |
| `periodic=true` | REQUIRED | v1 always uses folded MPS (hardcoded) |
| `periodic=false` | NOT supported | Defer to v2 |
| `ancilla=0` | REQUIRED | Standard monitored circuits |
| `ancilla>0` | NOT supported | Defer to v2 |

**SimulationState constructor MUST throw `ArgumentError("L must be even for v1")` if L % 2 != 0.**

### Indexing Convention
**Decision**: Users work with **physical site indices** (1 to L) only. The framework handles RAM/MPS ordering internally.

- CT.jl has `phy_ram` (physical→RAM) and `ram_phy` (RAM→physical) mappings
- These mappings are used internally when `periodic=true` (folded MPS ordering)
- **User API**: All functions accept physical indices 1 to L; conversion happens internally
- **Gate pairs**: Physical sites (i, j) must satisfy:
  - `j == i + 1` (adjacent), OR
  - `(i, j) == (L, 1)` (periodic wrap, L→1 only)
  - **Invalid pairs throw `ArgumentError`**: `(1, L)`, `(1, 5)`, `(3, 7)`, etc.
  - Note: `apply!(gate, L, 1)` is valid; `apply!(gate, 1, L)` is invalid (no auto-canonicalization)

### RNG Seed Mapping (EXACT CT.jl Correspondence)

| QuantumCircuitsMPS | CT.jl | Usage |
|-------------------|-------|-------|
| `seed_circuit` | `seed_C` | Creates `_rng_circuit` (CT's `rng_C`) |
| `seed_meas` | `seed_m` | Creates `_rng_meas` (CT's `rng_m`) |
| `x0` parameter | `x0` | Initial state (e.g., `1//big(2)^L`) |

**RNG consumption order in `random_control!` (CT.jl lines 363-414)**:

```
1. rand(_rng_circuit) < p_ctrl?
   - YES (Control branch):
     a. rand(_rng_meas) for measurement outcome
     b. position moves backward: i = mod(i-2, L) + 1
   - NO (Bernoulli branch):
     a. S! consumes _rng_circuit for unitary matrix
     b. position moves forward: i = mod(i, L) + 1
     c. TWO rand(_rng_circuit) < p_proj checks (ALWAYS, even if p_proj=0.0)
         - For each that passes: rand(_rng_meas) for projection outcome
```

**Critical**: The two `rand(_rng_circuit) < p_proj` checks ALWAYS execute after Bernoulli, consuming 2 random numbers even when p_proj=0. This must be replicated exactly.

### Public API Names (Definitive)
**Exported types** (structs):
- `HaarGate`, `SimplifiedGate` (gate types)
- `ZMeasurement` (measurement type)
- `MagnetizationZ`, `MagnetizationZiAll`, `EntanglementEntropy`, `MaxBondDim` (observable types)
- `Bricklayer`, `StaircaseStep` (pattern types)
- `AbstractCircuit`, `SimulationState` (core types)

**Exported constructor functions** (convenience):
- `ZMeasure(; reset=true)` → returns `ZMeasurement(reset)`
- `Entropy(cut::Int; order=1)` → returns `EntanglementEntropy(cut, order)`

**Usage in examples**: Always use constructor functions (`ZMeasure()`, `Entropy(5)`) not raw types.

### Observable Recording Schema
**Type**: `state.observables::Dict{Symbol,Vector{Any}}` (initialized empty, keys created lazily)

| Key | Value Type | Shape | Created By |
|-----|------------|-------|------------|
| `:Zi` | `Vector{Float64}` per entry | Each entry has length L | `MagnetizationZiAll()()` |
| `:Z` | `Float64` per entry | Scalar | `MagnetizationZ()()` |
| `:entropy` | `Float64` per entry | Scalar | `Entropy(cut)()` |
| `:max_bond_dim` | `Int` per entry | Scalar | `MaxBondDim()()` |

**Lazy initialization**: First call to an observable creates the key with an empty vector, then appends.

### Entropy Semantics
**`Entropy(cut; order=1)` computes entanglement entropy of physical sites 1:cut vs (cut+1):L.**

- `cut` is a **physical index** (user-facing, 1-based)
- For periodic rings: partitions are cyclic; `cut=L÷2` gives half-system entropy
- **Internal mapping**: Convert `cut` to RAM indices using `state._phy_ram`, then compute SVD at the appropriate MPS bond
- **Formula**: For physical cut at position `cut`, find the RAM index `ram_cut = state._phy_ram[cut]`, then compute entropy of MPS bipartition at bond `ram_cut`
- **Valid range**: `1 ≤ cut < L`
- CT.jl reference: `von_Neumann_entropy(mps, i)` computes entropy at RAM bond `i` (line 1419)

### Pattern Constraints (MPS Limitations)
**v1 Patterns** (adjacent pairs only):
- `Bricklayer(offset)` - pairs (1,2), (3,4), ... or (2,3), (4,5), ..., with (L,1) wrap
- `StaircaseStep` - single pair at current position (CT.jl's main loop)

**NOT in v1**: AllToAll, RandomSparse with non-adjacent pairs

---

## Work Objectives

### Core Objective
Create a standalone Julia package `QuantumCircuitsMPS.jl` that provides a PyTorch-like interface for quantum circuit simulation with MPS (periodic boundary conditions, ancilla=0).

### Concrete Deliverables
1. Julia package structure: `QuantumCircuitsMPS/` with Project.toml
2. Core module with abstract types and SimulationState
3. Gates submodule with HaarGate and SimplifiedGate
4. Measurements submodule with ZMeasurement
5. Observables submodule with Z, ZiAll, Entropy, MaxBondDim
6. Patterns submodule with Bricklayer, StaircaseStep
7. Implicit state context mechanism
8. Example reproducing `run_CT_MPS_C_m_O_T.jl` with exact numerical match

### Definition of Done
- [ ] `julia --project=QuantumCircuitsMPS -e "using QuantumCircuitsMPS"` exits code 0
- [ ] Implicit state works: `bricklayer!(HaarGate())` without passing state
- [ ] `examples/verify_ct_match.jl` passes (max diff < 1e-10)

### Must Have
- Abstract types: AbstractGate, AbstractMeasurement, AbstractObservable, AbstractPattern, AbstractCircuit
- HaarGate, SimplifiedGate, ZMeasurement (constructor: `ZMeasure(; reset=true)`), MagnetizationZ, MagnetizationZiAll, EntanglementEntropy (constructor: `Entropy(cut; order=1)`), MaxBondDim
- Bricklayer, StaircaseStep patterns
- Implicit state context via task-local storage
- RNG matching CT.jl exactly (including p_proj=0 consumption)

### Must NOT Have (Guardrails)
- `periodic=false` support (defer to v2)
- `ancilla > 0` support (defer to v2)
- Non-adjacent site gates
- Direct ITensor/MPS exposure (internal fields use `_` prefix)
- CT.jl modification

---

## Verification Strategy

### Test Decision
- **User wants tests**: Minimal
- **QA approach**: Compare to CT.jl outputs

### CT.jl Comparison Procedure

**Running from CT_MPS repository root** (the directory containing both `CT/` and `run_CT_MPS_*.jl`):

1. **CT.jl reference** (uses `run_CT_MPS_C_m_O_T.jl`'s `run_Oi_t` function):
```julia
include("run_CT_MPS_C_m_O_T.jl")
ct_results = run_Oi_t(10, 0.5, 0.0, 42, 123)
# Returns Dict with "Oi" => Matrix{Float64}(101, 10)
```

2. **QuantumCircuitsMPS equivalent**:
```julia
include("QuantumCircuitsMPS/examples/monitored_circuit.jl")
# new_results.observables[:Zi] is Vector{Vector{Float64}} of length 101
```

3. **Comparison**:
```julia
ct_Oi = ct_results["Oi"]  # shape (101, 10)
new_Zi = new_results.observables[:Zi]
new_Oi = reduce(hcat, new_Zi)'  # Convert to (101, 10)
max_diff = maximum(abs.(ct_Oi .- new_Oi))
@assert max_diff < 1e-10
```

---

## Task Flow

```
1. Package Setup
       |
       v
2. Core Types --> 3. State Context
       |                 |
       v                 v
4. Gates ---------> 5. Patterns
       |                 |
       v                 v
6. Measurements --> 7. Observables
                         |
                         v
                    8. Integration Example
```

---

## TODOs

- [ ] 1. Create Julia Package Structure

  **What to do**:
  - Create `QuantumCircuitsMPS/Project.toml`:
    ```toml
    name = "QuantumCircuitsMPS"
    uuid = "..." # Generate with UUIDs.uuid4()
    version = "0.1.0"
    
    [deps]
    ITensors = "9136182c-28ba-11e9-034c-db9fb085ebd5"
    Random = "9a3f8284-a2c9-5f02-9a11-845980a1fd5c"
    LinearAlgebra = "37e2e46d-f89d-539d-b4ee-838fcccc9c8e"
    ```
  - Create directory structure:
    - `QuantumCircuitsMPS/src/QuantumCircuitsMPS.jl`
    - `QuantumCircuitsMPS/src/Core/Core.jl`
    - `QuantumCircuitsMPS/src/Core/types.jl`
    - `QuantumCircuitsMPS/src/Core/context.jl`
    - `QuantumCircuitsMPS/src/Gates/Gates.jl`
    - `QuantumCircuitsMPS/src/Measurements/Measurements.jl`
    - `QuantumCircuitsMPS/src/Observables/Observables.jl`
    - `QuantumCircuitsMPS/src/Patterns/Patterns.jl`
    - `QuantumCircuitsMPS/examples/`
  - Main module includes submodules and re-exports public API
  - **Module wiring (explicit)**:
    - `QuantumCircuitsMPS/src/QuantumCircuitsMPS.jl` defines `module QuantumCircuitsMPS` and includes:
      - `include("Core/Core.jl")`, `include("Gates/Gates.jl")`, `include("Measurements/Measurements.jl")`, `include("Observables/Observables.jl")`, `include("Patterns/Patterns.jl")`
    - `QuantumCircuitsMPS/src/Core/Core.jl` defines `module Core` and includes:
      - `include("types.jl")`, `include("context.jl")`
    - Each submodule file defines its own `module ... end` block
  - **File map (single source of truth)**:
    - `src/QuantumCircuitsMPS.jl` → top-level `module QuantumCircuitsMPS`
    - `src/Core/Core.jl` → `module Core` (includes `types.jl`, `context.jl`)
    - `src/Core/types.jl` → type definitions only (no `module` block)
    - `src/Core/context.jl` → context helpers only (no `module` block)
    - `src/Gates/Gates.jl` → `module Gates`
    - `src/Measurements/Measurements.jl` → `module Measurements`
    - `src/Observables/Observables.jl` → `module Observables`
    - `src/Patterns/Patterns.jl` → `module Patterns`

  **Parallelizable**: NO

  **References**:
  - `CT/Project.toml` - dependency format

  **Acceptance Criteria**:
  - [ ] `julia --project=QuantumCircuitsMPS -e "using Pkg; Pkg.instantiate()"` exits 0
  - [ ] All module files exist and are valid Julia (`Core` + 4 submodules)

  **Commit**: YES - `feat(package): initialize QuantumCircuitsMPS.jl`

---

- [ ] 2. Define Core Abstract Types and SimulationState

  **What to do**:
  - Create `QuantumCircuitsMPS/src/Core/types.jl`:
    ```julia
    abstract type AbstractGate end
    abstract type AbstractMeasurement end
    abstract type AbstractObservable end
    abstract type AbstractPattern end
    abstract type AbstractCircuit end
    
    mutable struct SimulationState
        L::Int
        current_site::Int
        observables::Dict{Symbol,Vector{Any}}
        
        # Internal (underscore prefix)
        _mps::MPS
        _qubit_sites::Vector{Index}
        _phy_ram::Vector{Int}
        _ram_phy::Vector{Int}
        _phy_list::Vector{Int}
        _rng_circuit::MersenneTwister
        _rng_meas::MersenneTwister
        _cutoff::Float64
        _maxdim::Int
    end
    ```
  - Constructor (always folded ordering, v1 periodic-only):
    ```julia
    function SimulationState(; L::Int, seed_circuit::Int=0, seed_meas::Int=0,
                             x0::Union{Rational,Nothing}=nothing,
                             cutoff::Float64=1e-10, maxdim::Int=typemax(Int))
        # Port _initialize_basis and _initialize_vector from CT.jl (folded=true)
    end
    ```
  - Port from CT.jl lines 81-140

  **Parallelizable**: NO (depends on 1)

  **References**:
  - `CT/src/CT.jl:15-47` - CT_MPS struct
  - `CT/src/CT.jl:81-103` - `_initialize_basis` (folded ordering)
  - `CT/src/CT.jl:105-140` - `_initialize_vector` (uses `dec2bin`, `randomMPS`)
  - `CT/src/CT.jl:577-581` - `dec2bin(x, L)` helper for converting x0 to binary
  - `CT/src/CT.jl:64` - `_maxdim0=10` default for initial MPS linkdims

  **Port Dependencies** (must also implement in this task):
  - `_dec2bin(x::Rational, L::Int)::BigInt` - converts rational x0 to L-bit binary
  - Use `linkdims=10` for `randomMPS` when x0 is nothing

  **Acceptance Criteria**:
  - [ ] `SimulationState(L=9)` throws `ArgumentError` (odd L)
  - [ ] Error message contains `"L must be even for v1"`
  - [ ] `state = SimulationState(L=10, seed_circuit=42)` creates valid state
  - [ ] `state.L == 10`, `state.current_site == 10` (initialized to L)
  - [ ] `state.observables == Dict{Symbol,Vector{Any}}()`
  - [ ] `inner(state._mps, state._mps)` returns value within 1e-10 of 1.0
  - [ ] Folded mapping for L=6:
    - `state._ram_phy == [1, 6, 2, 5, 3, 4]`
    - `state._phy_ram == [1, 3, 5, 6, 4, 2]`

  **Commit**: YES - `feat(core): add SimulationState and abstract types`

---

- [ ] 3. Implement Implicit State Context

  **What to do**:
  - Create `QuantumCircuitsMPS/src/Core/context.jl`:
    ```julia
    const _STATE_LOCK = ReentrantLock()
    const _STATE_STACKS = Dict{UInt,Vector{SimulationState}}()
    
    function _get_stack()
        tid = objectid(current_task())
        lock(_STATE_LOCK) do
            get!(() -> SimulationState[], _STATE_STACKS, tid)
        end
    end
    
    function with_state(f, state::SimulationState)
        stack = _get_stack()
        push!(stack, state)
        try
            return f()
        finally
            pop!(stack)
        end
    end
    
    function current_state()
        stack = _get_stack()
        isempty(stack) && error("No active simulation context")
        return stack[end]
    end
    
    function simulate(circuit::AbstractCircuit; seed_circuit::Int=0, 
                      seed_meas::Int=0, x0::Union{Rational,Nothing}=nothing)
        state = SimulationState(L=circuit.L, seed_circuit=seed_circuit,
                                seed_meas=seed_meas, x0=x0)
        with_state(state) do
            forward(circuit)
        end
        return state
    end
    ```

  **Parallelizable**: NO (depends on 2)

  **References**:
  - Julia Base.Threads for ReentrantLock

  **Acceptance Criteria**:
  - [ ] `with_state(s) do; current_state() === s; end` returns true
  - [ ] `current_state()` outside context throws error containing "No active"
  - [ ] Two `Threads.@spawn` tasks don't share state (verified by different `state.L`)

  **Commit**: YES - `feat(core): add thread-safe implicit state context`

---

- [ ] 4. Implement Gates Submodule

  **What to do**:
  - Define `HaarGate`, `SimplifiedGate` types
  - Implement `apply!(gate, i, j)` that:
    1. Gets state via `current_state()`
    2. Validates `|i-j| == 1` or `(i,j) == (L,1)`
    3. Converts to RAM indices via `state._phy_ram`
    4. Generates unitary using `state._rng_circuit`
    5. Applies to MPS via ported `_apply_op!`
  - Port from CT.jl: `U`, `U_simp`, `Rx`, `Rz`, `CZ_mat`, `apply_op!`

  **Parallelizable**: YES (with 5)

  **References**:
  - `CT/src/CT.jl:147-173` - `apply_op!`
  - `CT/src/CT.jl:182-217` - `S!`
  - `CT/src/CT.jl:584-647` - `U`, `U_simp`, `Rx`, `Rz`

  **Acceptance Criteria**:
  - [ ] `typeof(HaarGate()) <: AbstractGate` is true
  - [ ] Same seed + gate sequence produces same `inner(mps1, mps2)` ≈ 1.0
  - [ ] `apply!(HaarGate(), 1, 5)` on L=8 throws ArgumentError

  **Commit**: YES - `feat(gates): add HaarGate and SimplifiedGate`

---

- [ ] 5. Implement Patterns Submodule

  **What to do**:
  - Define `Bricklayer(offset::Int)`, `StaircaseStep`
  - Implement `pairs(pat::Bricklayer, L::Int)`:
    ```julia
    function pairs(pat::Bricklayer, L::Int)
        result = Tuple{Int,Int}[]
        start = 1 + pat.offset
        for i in start:2:(L-1)
            push!(result, (i, i+1))
        end
        if pat.offset == 1 && L > 1
            push!(result, (L, 1))  # Wrap for periodic
        end
        return result
    end
    ```
  - Implement `bricklayer!(gate; offset=0)` and `staircase_step!(gate)`

  **Parallelizable**: YES (with 4)

  **References**:
  - `CT/src/CT.jl:396` - position update logic

  **Acceptance Criteria**:
  - [ ] `pairs(Bricklayer(0), 8) == [(1,2),(3,4),(5,6),(7,8)]`
  - [ ] `pairs(Bricklayer(1), 8) == [(2,3),(4,5),(6,7),(8,1)]`
  - [ ] `staircase_step!` with `current_site=8` on L=8 sets `current_site=1`

  **Commit**: YES - `feat(patterns): add Bricklayer and StaircaseStep`

---

- [ ] 6. Implement Measurements Submodule

  **What to do**:
  - Define `ZMeasurement(reset::Bool)`
  - Implement `measure!(meas, i)`:
    1. Compute Born probability via ported `_inner_prob`
    2. Sample using `state._rng_meas`
    3. Project via ported `_project!`
    4. If reset and outcome=1, apply X
  - Implement `control_step!(meas)` for CT.jl control branch
  - Implement `projection_checks!(p_proj, meas)` that ALWAYS consumes 2 RNG values:
  - **Constructor usage rule**: use `ZMeasure(; reset=...)` everywhere; do not use positional `ZMeasure(true)`
    ```julia
    function projection_checks!(p_proj::Float64, meas::AbstractMeasurement)
        state = current_state()
        i = state.current_site
        for offset in [-1, 0]
            pos = mod1(i + offset, state.L)
            if rand(state._rng_circuit) < p_proj  # ALWAYS called
                measure!(meas, pos)
            end
        end
    end
    ```

  **Parallelizable**: YES (with 7)

  **References**:
  - `CT/src/CT.jl:259-278` - `P!`, `X!`
  - `CT/src/CT.jl:399-409` - projection checks (ALWAYS 2 draws)
  - `CT/src/CT.jl:473-489` - `inner_prob`

  **Acceptance Criteria**:
  - [ ] `measure!(ZMeasure(), 1)` returns 0 or 1 (Int type)
  - [ ] `abs(inner(state._mps, state._mps) - 1.0) < 1e-10` after measure
  - [ ] RNG consumption test for `projection_checks!(0.0, ZMeasure())`:
    ```julia
    # Setup: create state, save RNG copy
    rng_copy = copy(state._rng_circuit)
    # Call function that should consume exactly 2 rand() values
    projection_checks!(0.0, ZMeasure())
    # Advance the copy by 2 to match
    rand(rng_copy); rand(rng_copy)
    # Verify both RNGs are now synchronized (next draw matches)
    @test rand(rng_copy) == rand(state._rng_circuit)
    ```

  **Commit**: YES - `feat(measurements): add ZMeasurement with exact RNG consumption`

---

- [ ] 7. Implement Observables Submodule

  **What to do**:
  - Define `MagnetizationZ`, `MagnetizationZiAll`, `EntanglementEntropy`, `MaxBondDim`
  - Make callable: `(obs::MagnetizationZiAll)()` computes and appends to `state.observables[:Zi]`
  - Port from CT.jl: `Zi`, `Z`, `von_Neumann_entropy`, `max_bond_dim`

  **Parallelizable**: YES (with 6)

  **References**:
  - `CT/src/CT.jl:503-521` - `Zi`, `Z`
  - `CT/src/CT.jl:702-709` - `max_bond_dim`
  - `CT/src/CT.jl:1419-1438` - `von_Neumann_entropy`

  **Acceptance Criteria**:
  - [ ] `MagnetizationZiAll()()` returns `Vector{Float64}` of length L
  - [ ] After call, `length(state.observables[:Zi]) == 1`
  - [ ] For same state, `abs(MagnetizationZ()() - CT.Z(ct)) < 1e-10`

  **Commit**: YES - `feat(observables): add Z, ZiAll, Entropy, MaxBondDim`

---

- [ ] 8. Create Integration Example

  **What to do**:
  - Create `QuantumCircuitsMPS/examples/monitored_circuit.jl`:
    ```julia
    using QuantumCircuitsMPS
    
    struct MonitoredCircuit <: AbstractCircuit
        L::Int
        p_ctrl::Float64
        p_proj::Float64
        T::Int
    end
    
    function QuantumCircuitsMPS.forward(c::MonitoredCircuit)
        MagnetizationZiAll()()  # Record t=0
        for t in 1:c.T
            state = current_state()
            if rand(state._rng_circuit) < c.p_ctrl
                control_step!(ZMeasure(; reset=true))
            else
                staircase_step!(HaarGate())
                projection_checks!(c.p_proj, ZMeasure(; reset=false))
            end
            MagnetizationZiAll()()
        end
    end
    
    # When run as script:
    if abspath(PROGRAM_FILE) == @__FILE__
        results = simulate(MonitoredCircuit(10, 0.5, 0.0, 100),
                          seed_circuit=42, seed_meas=123, 
                          x0=1//big(2)^10)
        println("Recorded $(length(results.observables[:Zi])) Zi snapshots")
    end
    ```
  - Create `QuantumCircuitsMPS/examples/verify_ct_match.jl`:
    ```julia
    # Run from CT_MPS repo root: julia --project=QuantumCircuitsMPS examples/verify_ct_match.jl
    using Test
    
    # Paths relative to CT_MPS root
    const REPO_ROOT = dirname(dirname(@__DIR__))  # Go up from examples/ to QuantumCircuitsMPS/ to CT_MPS/
    
    # Load CT.jl reference (note: CT script activates CT project)
    import Pkg
    const ORIG_PROJECT = Base.active_project()
    try
        include(joinpath(REPO_ROOT, "run_CT_MPS_C_m_O_T.jl"))
        ct_results = run_Oi_t(10, 0.5, 0.0, 42, 123)
    finally
        ORIG_PROJECT === nothing ? Pkg.activate() : Pkg.activate(dirname(ORIG_PROJECT))
    end
    @test Base.active_project() == ORIG_PROJECT
    
    # Load QuantumCircuitsMPS
    push!(LOAD_PATH, joinpath(REPO_ROOT, "QuantumCircuitsMPS"))
    using QuantumCircuitsMPS
    include(joinpath(REPO_ROOT, "QuantumCircuitsMPS/examples/monitored_circuit.jl"))
    
    new_results = simulate(MonitoredCircuit(10, 0.5, 0.0, 100),
                          seed_circuit=42, seed_meas=123,
                          x0=1//big(2)^10)
    
    # Compare
    ct_Oi = ct_results["Oi"]
    new_Oi = reduce(hcat, new_results.observables[:Zi])'
    max_diff = maximum(abs.(ct_Oi .- new_Oi))
    
    @test size(ct_Oi) == size(new_Oi) == (101, 10)
    @test max_diff < 1e-10
    println("Maximum difference: $max_diff")
    println("SUCCESS: Results match CT.jl within 1e-10")
    ```

  **Parallelizable**: NO (depends on all)

  **References**:
  - `run_CT_MPS_C_m_O_T.jl:26-61` - `run_Oi_t` structure

  **Acceptance Criteria**:
  - [ ] `julia --project=QuantumCircuitsMPS QuantumCircuitsMPS/examples/monitored_circuit.jl` exits 0
  - [ ] From repo root: `julia --project=QuantumCircuitsMPS QuantumCircuitsMPS/examples/verify_ct_match.jl` prints "SUCCESS"
  - [ ] After `include("run_CT_MPS_C_m_O_T.jl")`, `Base.active_project()` equals the original QuantumCircuitsMPS project
  - [ ] `monitored_circuit.jl` user code (struct + forward + run) is < 30 lines

  **Commit**: YES - `feat(examples): add monitored circuit with CT.jl verification`

---

## Commit Strategy

| Task | Message | Verification |
|------|---------|--------------|
| 1 | `feat(package): initialize QuantumCircuitsMPS.jl` | Pkg.instantiate exits 0 |
| 2 | `feat(core): add SimulationState and abstract types` | State creates |
| 3 | `feat(core): add thread-safe implicit state context` | Context works |
| 4 | `feat(gates): add HaarGate and SimplifiedGate` | Gates apply |
| 5 | `feat(patterns): add Bricklayer and StaircaseStep` | Pairs correct |
| 6 | `feat(measurements): add ZMeasurement with exact RNG` | RNG consumed |
| 7 | `feat(observables): add Z, ZiAll, Entropy, MaxBondDim` | Values match |
| 8 | `feat(examples): add monitored circuit with CT.jl verification` | SUCCESS printed |

---

## Success Criteria

### Verification Commands (from CT_MPS repo root)
```bash
julia --project=QuantumCircuitsMPS -e "using Pkg; Pkg.instantiate()"
julia --project=QuantumCircuitsMPS -e "using QuantumCircuitsMPS"
julia --project=QuantumCircuitsMPS QuantumCircuitsMPS/examples/monitored_circuit.jl
julia --project=QuantumCircuitsMPS QuantumCircuitsMPS/examples/verify_ct_match.jl
```

### Final Checklist
- [ ] Package loads without errors
- [ ] Internal fields use `_` prefix
- [ ] Implicit state works (no state parameter in forward)
- [ ] CT.jl unchanged
- [ ] verify_ct_match.jl prints "SUCCESS"
- [ ] monitored_circuit.jl < 30 lines of user code
