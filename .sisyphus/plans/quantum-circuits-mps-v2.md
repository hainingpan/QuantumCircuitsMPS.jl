# QuantumCircuitsMPS.jl v2 - Complete Rewrite

## TL;DR

> **Quick Summary**: Complete rewrite of QuantumCircuitsMPS.jl to create a "PyTorch for Quantum Circuits" - a physicist-friendly MPS simulator where users focus on physics (Gates + Geometry) without worrying about MPS implementation details.
> 
> **Deliverables**:
> - New layered architecture with clean abstractions (Gate, Geometry, Observable, State)
> - Multiple API styles (OO explicit, OO imperative, Functional)
> - Support for both PBC and OBC boundary conditions
> - `examples/ct_model.jl` reproducing `run_CT_MPS_C_m_T.jl` from CT.jl
> - Physics verification passing against CT.jl reference
> 
> **Estimated Effort**: Large (architecture + implementation + verification)
> **Parallel Execution**: YES - 3 waves
> **Critical Path**: Task 1 (State) → Task 3 (Gates) → Task 5 (Geometry) → Task 8 (CT Example) → Task 9 (Verification)

---

## CRITICAL CONTRACTS (Momus Blockers Resolved)

### Contract 1: v2 vs Current Code Coexistence

**Strategy**: PARALLEL NAMESPACE then REPLACE

1. **Phase 1 (Tasks 1-8)**: Create v2 code in `src/v2/` subdirectory
   - `src/v2/State/State.jl`
   - `src/v2/Core/rng.jl`, `src/v2/Core/basis.jl`, `src/v2/Core/apply.jl`
   - `src/v2/Gates/*.jl`
   - `src/v2/Geometry/*.jl`
   - `src/v2/Observables/*.jl`
   - `src/v2/API/*.jl`
   - `src/v2/QuantumCircuitsMPSv2.jl` (temporary module name)

2. **Phase 2 (Task 9 - after verification passes)**:
   - Archive old code to `src/_deprecated/`
   - Move v2 code from `src/v2/` to `src/`
   - Rename module back to `QuantumCircuitsMPS`
   - Update `src/QuantumCircuitsMPS.jl` to export v2 API

**Rationale**: This ensures old code remains untouched until new code is proven correct.

---

### Contract 2: Public Site Indexing & Boundary Condition Behavior

**USER-FACING SITE IDS ARE ALWAYS PHYSICAL 1:L**

Users never see RAM indices. All geometry APIs use physical site numbers.

| Geometry | OBC Behavior | PBC Behavior |
|----------|--------------|--------------|
| `SingleSite(i)` | i ∈ 1:L, else ERROR | i ∈ 1:L, else ERROR |
| `AdjacentPair(i)` | Applies to (i, i+1); i=L → ERROR | Applies to (i, mod(i,L)+1); i=L → (L,1) wraps |
| `Bricklayer(:odd)` | Pairs: (1,2), (3,4), ..., (L-1,L) if L even; else (1,2)...(L-2,L-1) skips last | Same as OBC; **WARNING if L is odd** (unexpected wrap behavior) |
| `Bricklayer(:even)` | Pairs: (2,3), (4,5), ...; first and last sites skipped | Same, but (L,1) pair added for PBC |
| `AllSites` | Sites 1,2,...,L sequentially | Same |
| `StaircaseLeft` | Pointer moves i → i-1; at i=1 → **RESET to L** (bounce back) | Pointer moves i → mod(i-2,L)+1 (wraps) |
| `StaircaseRight` | Pointer moves i → i+1; at i=L → **RESET to 1** (bounce back) | Pointer moves i → mod(i,L)+1 (wraps) |

**Bricklayer Naming Convention**:
- `:odd` means first site of each pair is odd: (1,2), (3,4), (5,6)...
- `:even` means first site of each pair is even: (2,3), (4,5), (6,7)...

**Odd-L PBC Constraint**: PBC with odd L is **not supported** and throws `ArgumentError` at state construction time (see Task 4). This is enforced in `compute_basis_mapping()`, not in Bricklayer, because the folded basis algorithm requires even L.

---

### Contract 2.1: Geometry Interface (CANONICAL - Momus Blocker #1 Resolution)

**SINGLE CANONICAL CONTRACT**: Every geometry type returns sites for ONE application.

```julia
# CANONICAL: Returns physical sites for a SINGLE gate application
# Returns Vector{Int} of length 1 (single-qubit) or 2 (two-qubit)
get_sites(geo::AbstractGeometry, state::SimulationState) -> Vector{Int}
```

**Geometry Semantics by Type:**

| Geometry Type | `get_sites` Returns | Support | Iteration? |
|---------------|---------------------|---------|------------|
| `SingleSite(i)` | `[i]` | 1 | NO - single application |
| `AdjacentPair(i)` | `[i, wrap_next(i,L,bc)]` | 2 | NO - single application |
| `Bricklayer(parity)` | N/A - see below | 2 | YES - yields multiple pairs |
| `AllSites` | N/A - see below | 1 | YES - yields all sites |
| `StaircaseLeft/Right` | `[pointer, wrap_next(pointer,L,bc)]` | 2 | NO - single application (pointer advances after) |

**Multi-Application Geometries (Bricklayer, AllSites) - Momus Blocker #2 Resolution:**

**Problem**: The original plan used invalid Julia iteration signatures like `Base.iterate(geo, state::SimulationState)`.

**Resolution**: Multi-application geometries do NOT implement Julia's iteration protocol directly. Instead, `apply!` loops internally.

**Implementation: apply! handles multi-application internally**
```julia
# apply! detects multi-application geometries and loops
function apply!(state::SimulationState, gate::AbstractGate, geo::Bricklayer)
    # NOTE: No odd-L PBC warning needed here because Task 4's compute_basis_mapping()
    # already throws ArgumentError for odd L with PBC at state construction time.
    # Users cannot reach this code with odd-L PBC states.
    for sites in each_site_set(geo, state)  # internal helper
        apply!(state, gate, sites)  # dispatch to Vector{Int} version
    end
end

function apply!(state::SimulationState, gate::AbstractGate, geo::AllSites)
    for site in 1:state.L
        apply!(state, gate, [site])
    end
end
```

**Bricklayer Pair Generation Table (CANONICAL):**

| L | bc | parity | Pairs Generated |
|---|-----|--------|-----------------|
| 4 | :open | :odd | `[(1,2), (3,4)]` |
| 4 | :open | :even | `[(2,3)]` |
| 4 | :periodic | :odd | `[(1,2), (3,4)]` |
| 4 | :periodic | :even | `[(2,3), (4,1)]` ← **PBC wrap for even parity** |
| 6 | :open | :odd | `[(1,2), (3,4), (5,6)]` |
| 6 | :open | :even | `[(2,3), (4,5)]` |
| 6 | :periodic | :odd | `[(1,2), (3,4), (5,6)]` |
| 6 | :periodic | :even | `[(2,3), (4,5), (6,1)]` ← **PBC wrap for even parity** |

**Key Rules**: 
- `:odd` = first site of pair is odd (1,2), (3,4)...
- `:even` = first site of pair is even (2,3), (4,5)...
- For PBC with `:even` parity, the wrap pair `(L, 1)` is added at the end.
- For OBC, no wrap pairs are ever added.

**Canonical Usage (what users should do):**
```julia
# SIMPLE: Just use apply! with the geometry
apply!(state, HaarRandom(), Bricklayer(:odd))  # applies to all odd-start pairs
apply!(state, PauliX(), AllSites())            # applies X to all sites
```

**What NOT to do:**
```julia
# INVALID: Bricklayer/AllSites are NOT directly iterable without state
for sites in Bricklayer(:odd)  # ERROR: needs state.L, state.bc
    ...
end
```

**Support Validation:**
```julia
# In apply!(state, gate, sites::Vector{Int}):
num_sites = support(gate)  # 1 for single-qubit, 2 for two-qubit
if length(sites) != num_sites
    throw(ArgumentError("Gate $(typeof(gate)) requires $num_sites sites, got $(length(sites))"))
end
```

| Gate Type | `support` | Valid Geometries |
|-----------|-----------|------------------|
| `PauliX/Y/Z` | 1 | `SingleSite`, `AllSites` |
| `Projection` | 1 | `SingleSite`, `AllSites` |
| `HaarRandom` | 2 | `AdjacentPair`, `Bricklayer`, `Staircase` |
| `CZ` | 2 | `AdjacentPair`, `Bricklayer`, `Staircase` |

**Error Cases:**
- `apply!(state, HaarRandom(), AllSites())` → `ArgumentError: Gate HaarRandom requires 2 sites, got 1`
- `apply!(state, PauliX(), AdjacentPair(1))` → `ArgumentError: Gate PauliX requires 1 site, got 2`

---

### Contract 2.2: Staircase Pointer API (Momus Blocker #2 Resolution)

**Problem**: Task 8 needs the pointer value to compute DW sampling index `(i % L) + 1`, but the plan says "do NOT expose pointer variable to users."

**Resolution**: The pointer VALUE is readable but not user-settable. The FIELD is private, but we provide a read-only accessor.

**Staircase Struct:**
```julia
mutable struct StaircaseLeft <: AbstractGeometry
    pointer::Int  # PRIVATE: do not access directly
end

mutable struct StaircaseRight <: AbstractGeometry
    pointer::Int  # PRIVATE: do not access directly
end

# Constructors with explicit starting position
StaircaseLeft(start::Int) = StaircaseLeft(start)
StaircaseRight(start::Int) = StaircaseRight(start)
```

**Public API:**
```julia
# READ-ONLY accessor (Momus-approved public API)
current_position(geo::StaircaseLeft) -> Int   # Returns pointer value
current_position(geo::StaircaseRight) -> Int  # Returns pointer value

# Mutation (internal, called by apply!)
advance!(geo::StaircaseLeft, state::SimulationState) -> Nothing  # pointer -= 1 (wrapped)
advance!(geo::StaircaseRight, state::SimulationState) -> Nothing # pointer += 1 (wrapped)

# get_sites uses pointer WITHOUT advancing
get_sites(geo::StaircaseLeft, state) = [geo.pointer, wrap_next(geo.pointer, state.L, state.bc)]
get_sites(geo::StaircaseRight, state) = [geo.pointer, wrap_next(geo.pointer, state.L, state.bc)]
```

**Usage in Task 8 (CT example):**
```julia
staircase = StaircaseRight(starting_position)  # or StaircaseLeft

for t in 1:T
    # ... apply gates using staircase ...
    pointer = current_position(staircase)  # READ pointer after apply!
    i1 = (pointer % L) + 1                 # Compute DW sampling index
    record!(state; i1=i1)                  # Record observables
end
```

**Why this resolves the blocker:**
- Users get the pointer value via `current_position()` (read-only)
- Users cannot SET the pointer directly (no `set_position!` function)
- `advance!` is internal (called by `apply!`)
- This matches CT.jl's pattern where `random_control!` returns the pointer value

**Implementation Note**: Geometry's `get_sites` returns current sites based on pointer. `apply!` calls `advance!` AFTER applying the gate. This matches CT.jl where movement happens after each operation.

---

### Contract 3: RNG Design (NEW CLEAN DESIGN - Replaces CT.jl Mangled Streams)

**Design Principle**: One RNG stream per probability source. Each source of randomness has its own independent stream for clarity and reproducibility.

**OLD CT.jl Design (problematic)**:
- `:circuit` mangled p_ctrl decisions, p_proj decisions, AND Haar random generation
- `:measurement` used only for Born rule outcomes
- Led to confusing "consume seed just for consistency" patterns

**NEW CLEAN DESIGN**:
- `:ctrl` - decisions about whether to apply control operations (p_ctrl)
- `:proj` - decisions about whether to apply projections (p_proj)
- `:haar` - Haar random unitary generation
- `:born` - Born rule measurement outcomes
- `:state_init` - random initial state generation (optional)

```
EACH TIMESTEP in circuit (NEW DESIGN):

1. DECISION: rand(rng, :ctrl) < p_ctrl?  [consumes from :ctrl]

IF CONTROL BRANCH:
  2. BORN PROB: Compute ⟨ψ|P_0|ψ⟩ at site i  [NO RNG consumed]
  3. OUTCOME: rand(rng, :born) < p_0 ? 0 : 1  [consumes from :born]
  4. APPLY: P!(outcome)  [NO RNG consumed]
  5. MOVE: pointer update  [NO RNG consumed]

IF UNITARY BRANCH:
  2. HAAR: Generate U(4, get_rng(rng, :haar))  [consumes from :haar]
  3. APPLY: U to sites (i, i+1)  [NO RNG consumed]
  4. MOVE: pointer update  [NO RNG consumed]
  5. PROJ DECISION 1: rand(rng, :proj) < p_proj?  [consumes from :proj]
     IF YES:
       5a. BORN PROB at affected site  [NO RNG consumed]
       5b. OUTCOME: rand(rng, :born)  [consumes from :born]
       5c. APPLY P!  [NO RNG consumed]
  6. PROJ DECISION 2: rand(rng, :proj) < p_proj?  [consumes from :proj]
     IF YES: (same as above)
```

**Why This is Better**:
- Each probability parameter has its OWN seed: changing `seed_proj` only affects projection decisions
- No "dummy consumption" to maintain stream alignment
- Easy to reason about: "I seeded :haar with 42, so I'll get the same random unitaries"
- Can add new randomness sources without breaking existing streams

---

### Contract 3.0.1: CT.jl Bit-for-Bit Verification Compatibility (CRITICAL FOR VERIFICATION)

**Problem**: Our clean 4-stream design (`:ctrl`, `:proj`, `:haar`, `:born`) differs from CT.jl's mangled 2-stream design (`rng_C` for all circuit ops, `rng_m` for measurement outcomes). This makes bit-for-bit verification challenging.

**Solution**: Verification uses `p_proj = 0.0`, which eliminates `:proj` stream consumption.

**Why This Works**:

CT.jl's `random_control!` RNG consumption pattern (per iteration):
```
IF control branch (rand(rng_C) < p_ctrl):
  → consumes 1 from rng_C (for decision)
  → consumes 1 from rng_m (for Born outcome)
  → NO Haar consumption
  
IF Bernoulli branch (rand(rng_C) >= p_ctrl):
  → consumes 1 from rng_C (for decision)
  → consumes N from rng_C (for Haar U(4, rng_C))
  IF p_proj > 0:
    → consumes 1-2 from rng_C (for proj decisions)  ← ELIMINATED when p_proj=0
    → consumes 0-2 from rng_m (for proj outcomes)
```

**With p_proj = 0.0**, CT.jl's `rng_C` consumption is: `[ctrl_decision, maybe_haar_draws, ctrl_decision, maybe_haar_draws, ...]`

**Our design with same seed**: `ctrl=SEED, haar=SEED` creates two independent MersenneTwister instances.

**KEY INSIGHT**: Even with same seed, the streams consume independently and diverge immediately!

**SOLUTION**: For verification, we need CT.jl to NOT call `rand(ct.rng_C)` for proj decisions when `p_proj=0`.

**CT.jl Patch Required** (temporary, for verification only):

In `/mnt/d/Rutgers/CT_MPS/CT/src/CT.jl` line 402, change:
```julia
# BEFORE (original CT.jl):
if rand(ct.rng_C) < p_proj

# AFTER (patched for verification):
if p_proj > 0 && rand(ct.rng_C) < p_proj
```

This ensures when `p_proj=0`, no random draw is consumed for proj decisions, making the consumption pattern match our clean design.

**Verification Mapping (with patch + p_proj=0)**:

| CT.jl | Our Design | Seed |
|-------|------------|------|
| `rng_C` for ctrl decisions | `:ctrl` | `seed_C` |
| `rng_C` for Haar | `:haar` | `seed_C` (SAME as ctrl!) |
| `rng_m` for Born outcomes | `:born` | `seed_m` |
| (not consumed when p_proj=0) | `:proj` | (any value) |

**CRITICAL**: For verification, use `RNGRegistry(ctrl=42, proj=999, haar=42, born=123)` where ctrl and haar have SAME seed.

**But wait** - same seed still means independent streams! The real solution:

**ACTUAL SOLUTION**: Use stream ALIASING in RNGRegistry for CT-compat mode:

```julia
# Special constructor for CT.jl verification (NOT the normal API)
function RNGRegistry(::Val{:ct_compat}; circuit::Int, measurement::Int)
    # ctrl and haar SHARE the same RNG object (alias)
    shared_circuit_rng = MersenneTwister(circuit)
    streams = Dict{Symbol, AbstractRNG}(
        :ctrl => shared_circuit_rng,  # ALIAS
        :proj => shared_circuit_rng,  # ALIAS (unused when p_proj=0)
        :haar => shared_circuit_rng,  # ALIAS - same object!
        :born => MersenneTwister(measurement),
        :state_init => MersenneTwister(0)
    )
    return RNGRegistry(streams)
end

# Usage for verification:
rng = RNGRegistry(Val(:ct_compat), circuit=42, measurement=123)
```

**This aliasing ensures `:ctrl` and `:haar` consume from the SAME underlying RNG, matching CT.jl's interleaved pattern.**

**Verification Test Case Parameters**:
- L=10, p_ctrl=0.5, p_proj=0.0, seed_C=42, seed_m=123
- Use CT-compat RNG mode in our code
- Apply CT.jl patch (line 402)
- Result: bit-for-bit match within 1e-10

**After Verification**: Remove CT.jl patch, use normal RNGRegistry for all other purposes.

---

### Contract 3.1: RNG Registry API (NEW CLEAN DESIGN)

**RNGRegistry Struct:**
```julia
struct RNGRegistry
    streams::Dict{Symbol, AbstractRNG}
end

# CANONICAL Constructor - all physics-relevant streams required
function RNGRegistry(; 
    ctrl::Int,       # for p_ctrl decisions
    proj::Int,       # for p_proj decisions
    haar::Int,       # for Haar random unitary generation
    born::Int,       # for Born rule measurement outcomes
    state_init::Int=0  # for random initial states (optional)
)
    streams = Dict{Symbol, AbstractRNG}(
        :ctrl => MersenneTwister(ctrl),
        :proj => MersenneTwister(proj),
        :haar => MersenneTwister(haar),
        :born => MersenneTwister(born),
        :state_init => MersenneTwister(state_init)
    )
    return RNGRegistry(streams)
end
```

**IMPORTANT**: `ctrl`, `proj`, `haar`, and `born` are all REQUIRED keyword arguments.
This ensures users explicitly seed each randomness source for reproducibility.

**INCORRECT usages (will error):**
```julia
RNGRegistry(ctrl=42)                          # ERROR: missing proj, haar, born
RNGRegistry(42, 123, 456, 789)                # ERROR: positional args not supported
RNGRegistry(circuit=42, measurement=123)      # ERROR: old CT.jl style, not supported
```

**CORRECT usage:**
```julia
RNGRegistry(ctrl=1, proj=2, haar=3, born=4)                    # OK - minimal
RNGRegistry(ctrl=1, proj=2, haar=3, born=4, state_init=5)     # OK - with state_init
```

**CT-COMPAT MODE** (for verification - see Contract 3.0.1):
```julia
# Special constructor that aliases ctrl/proj/haar to SAME underlying RNG
# This matches CT.jl's mangled consumption pattern for verification
function RNGRegistry(::Val{:ct_compat}; circuit::Int, measurement::Int)
    shared_circuit_rng = MersenneTwister(circuit)
    streams = Dict{Symbol, AbstractRNG}(
        :ctrl => shared_circuit_rng,  # ALIAS - same RNG object
        :proj => shared_circuit_rng,  # ALIAS
        :haar => shared_circuit_rng,  # ALIAS
        :born => MersenneTwister(measurement),
        :state_init => MersenneTwister(0)
    )
    return RNGRegistry(streams)
end

# Usage (Task 8 CT example):
rng = RNGRegistry(Val(:ct_compat), circuit=42, measurement=123)
```

**API Functions:**

```julia
# LOW-LEVEL: Get the raw AbstractRNG stream (for passing to randn, etc.)
get_rng(registry::RNGRegistry, stream::Symbol) -> AbstractRNG

# MID-LEVEL: Draw from registry by stream name
rand(registry::RNGRegistry, stream::Symbol) -> Float64
randn(registry::RNGRegistry, stream::Symbol) -> Float64
randn(registry::RNGRegistry, stream::Symbol, dims...) -> Array{Float64}

# HIGH-LEVEL: Draw from state (convenience wrapper)
rand(state::SimulationState, stream::Symbol) -> Float64
randn(state::SimulationState, stream::Symbol, dims...) -> Array{Float64}
# Implementation: delegates to state.rng_registry
```

**Stream Assignment by Operation:**

| Operation | Stream | Rationale |
|-----------|--------|-----------|
| Control branch decision (`rand() < p_ctrl`) | `:ctrl` | Separate seed for control decisions |
| Projection decision (`rand() < p_proj`) | `:proj` | Separate seed for projection decisions |
| HaarRandom unitary generation | `:haar` | Separate seed for unitary generation |
| Born measurement outcome | `:born` | Separate seed for measurement outcomes |
| ProductState initialization | N/A | Deterministic (no RNG needed) |
| RandomMPS initialization | `:state_init` | Initial state preparation |

**RandomMPS RNG Requirement:**
- `RandomMPS` initialization **requires** `state.rng_registry` to be set with `:state_init` stream
- If `state.rng_registry === nothing`, `initialize!(state, RandomMPS(...))` throws `ArgumentError("RandomMPS requires RNGRegistry with :state_init stream. Attach RNG before calling initialize!")`
- `ProductState` does NOT require RNG (deterministic bit pattern)

**HaarRandom Implementation (uses :haar stream):**
```julia
function build_operator(gate::HaarRandom, sites::Vector{Index}, state::SimulationState)
    # Get the actual AbstractRNG stream for randn calls
    haar_rng = get_rng(state.rng_registry, :haar)
    num_qudits = support(gate)  # default 2 for two-qubit gates
    local_dim = 2  # qubit dimension (could be parameterized for qudits)
    n = local_dim^num_qudits  # e.g., 2^2 = 4 for two qubits
    
    # CT.jl U(n, rng) algorithm:
    z = randn(haar_rng, n, n) + randn(haar_rng, n, n) * im
    Q, R = qr(z)
    r_diag = diag(R)
    Lambda = Diagonal(r_diag ./ abs.(r_diag))
    U_matrix = Q * Lambda
    
    # Build ITensor from matrix...
    return ITensor(U_matrix, sites[1], sites[2], sites[1]', sites[2]')
end
```

**Acceptance Criteria Update (Task 2):**
```julia
# Test both APIs
rng = RNGRegistry(ctrl=1, proj=2, haar=3, born=4)

# Mid-level: rand from registry
v1 = rand(rng, :haar)

# Low-level: get raw RNG
haar_rng = get_rng(rng, :haar)
v2 = rand(haar_rng)  # uses Julia's rand(::AbstractRNG)

# Verify reproducibility
rng2 = RNGRegistry(ctrl=1, proj=2, haar=3, born=4)
v3 = rand(rng2, :haar)
@assert v1 == v3 "Reproducibility failed"
```

**CRITICAL**: The Haar random implementation must use the EXACT algorithm from CT.jl (line 585-592):
```julia
# From CT.jl U(n, rng) function - VERBATIM:
function U(n, rng)
    z = randn(rng, n, n) + randn(rng, n, n) * im  # TWO randn calls (real + imag separately)
    Q, R = qr(z)
    r_diag = diag(R)
    Lambda = Diagonal(r_diag ./ abs.(r_diag))  # Phase fix via r/|r|, NOT sign()
    Q *= Lambda
    return Q
end
```

**RNG Consumption Note**: The exact number of values consumed by Julia's `randn(rng, n, n)` depends on the RNG implementation. Do NOT hardcode counts. Instead, implement the algorithm exactly as above and rely on identical seeding for reproducibility.

---

### Contract 3.5: Normalization/Truncation Behavior Per Gate Class (CRITICAL for CT match)

**CT.jl's apply_op!() behavior**: SVD-based splitting with cutoff/maxdim truncation but NO normalization.

**Per-gate-class behavior (from CT.jl source)**:

| Gate Class | apply_op! call | Post-operation | CT.jl Function |
|------------|----------------|----------------|----------------|
| **Unitary (HaarRandom)** | `apply_op!(mps, op, cutoff, maxdim)` | **NO** normalize | `S!()` line 206-208 |
| **Projection** | `apply_op!(mps, op, cutoff, maxdim)` | `normalize!(mps)` then `truncate!` | `P!()` line 265-270 |
| **Pauli X** | `apply_op!(mps, op, cutoff, maxdim)` | **NO** normalize | `X!()` line 274-277 |
| **Reset** | Calls `P!()` then conditionally `X!()` | normalize inherited from P! | `R!()` |

**Implementation Rule**:
```julia
# In apply!(state, gate::AbstractGate, geo)
# 1. Build operator tensor
# 2. Call internal apply_op_internal! (SVD split with truncation)
# 3. Dispatch normalization based on gate type:

apply_post!(state, ::HaarRandom) = nothing  # NO normalize
apply_post!(state, ::Projection) = begin normalize!(state.mps); truncate!(state.mps, cutoff=state.cutoff) end
apply_post!(state, ::PauliX) = nothing  # NO normalize
apply_post!(state, ::PauliY) = nothing  # NO normalize  
apply_post!(state, ::PauliZ) = nothing  # NO normalize
apply_post!(state, ::Reset) = nothing  # P! already normalized, X! doesn't need it
```

**DO NOT use ITensorMPS.apply() for CT match**: Use custom `apply_op_internal!` matching CT.jl's SVD algorithm (line 147-172) to ensure identical truncation behavior.

**apply_op_internal! signature** (per Contract 3.6 - state_sites required):
```julia
# Internal function that ALL gates use for MPS contraction
# The operator is ALREADY BUILT with its indices - we extract and sort them for SVD sweep
# state_sites is passed to enable Index matching (Contract 3.6)
function apply_op_internal!(mps::MPS, op::ITensor, state_sites::Vector{Index}; cutoff::Float64=1e-10, maxdim::Int=100)
    # 1. Extract RAM site indices via get_site_number() (Contract 3.6)
    # 2. Sort for orthogonalization order (like CT.jl line 149)
    # 3. Orthogonalize, contract, SVD split (CT.jl lines 151-170)
    # Mutates mps in-place
    # Does NOT normalize (normalization is caller's responsibility per gate class)
    return nothing
end
```

**CRITICAL: Operator Construction vs SVD Sweep Order (CT.jl EXACT Match)**:

CT.jl has TWO distinct orderings that must be understood separately:

**1. Operator Construction Order** (preserved from physical pair order):
```julia
# CT.jl S!() lines 202-203:
ram_idx = ct.phy_ram[[physical_i, physical_j]]  # e.g., [5, 2] for PBC wrap
U_4_tensor = ITensor(U_4, site[ram_idx[1]], site[ram_idx[2]], site[ram_idx[1]]', site[ram_idx[2]]')
# Operator indices are in PHYSICAL PAIR ORDER, NOT sorted!
# The 4x4 Haar matrix's first qubit corresponds to physical site i, second to physical site j
```

**2. SVD Sweep Order** (sorted for orthogonalization):
```julia
# CT.jl apply_op!() lines 148-149:
i_list = [extract_site_number_from_index_tags...]  # e.g., [5, 2]
sort!(i_list)  # becomes [2, 5] for SVD sweep
orthogonalize!(mps, i_list[1])  # orthogonalize to leftmost RAM site
# SVD sweeps from left to right in sorted order
```

**KEY DISTINCTION**: The operator's qubit-basis assignment is determined by construction order (physical pair), but the MPS manipulation (orthogonalize, contract, SVD) uses sorted order.

**Worked Example: L=10 PBC, AdjacentPair(10)**:

| Step | Value | Notes |
|------|-------|-------|
| Physical sites | (10, 1) | Wrap: site 10 paired with site 1 |
| `phy_ram` lookup | `[phy_ram[10], phy_ram[1]]` | Say returns `[2, 1]` for this PBC |
| Operator construction | `ITensor(U_4, sites[2], sites[1], sites[2]', sites[1]')` | **Indices in physical pair order** |
| Haar matrix meaning | U_4[a,b,c,d]: a=site10 out, b=site1 out, c=site10 in, d=site1 in | First qubit = physical site 10 |
| apply_op_internal! | Extracts indices from op → `[2, 1]`, sorts → `[1, 2]` | SVD sweep order |
| Orthogonalization | `orthogonalize!(mps, 1)` | Leftmost in sorted order |
| Result | Operator applied correctly; truncation follows sorted sweep | CT-compatible |

**Contract for apply!**:
```julia
function apply!(state, gate::HaarRandom, geo::AdjacentPair)
    i, j = get_physical_sites(geo, state)  # e.g., (10, 1) for wrap
    ram_i, ram_j = state.phy_ram[i], state.phy_ram[j]  # e.g., (2, 1)
    
    # Build operator with PHYSICAL PAIR ORDER indices (NOT sorted!)
    op = build_operator(gate, [state.sites[ram_i], state.sites[ram_j]], state.local_dim; 
                        rng=state.rng_registry)
    
    # apply_op_internal! extracts indices from op, sorts internally for SVD
    # NOTE: Pass state.sites per Contract 3.6 signature
    apply_op_internal!(state.mps, op, state.sites; cutoff=state.cutoff, maxdim=state.maxdim)
    apply_post!(state, gate)  # normalize if needed
end
```

**Why this matters**: For non-symmetric 2-qubit gates, the qubit assignment affects the physics. A Haar random matrix is symmetric under qubit swap (statistically), but CNOT/CZ are not. Building the operator in the wrong order would silently swap control/target.

**apply_op_internal! SVD Algorithm** (matching CT.jl lines 147-172):

---

### Contract 3.6: Index-to-Site Mapping (Momus Blocker #5 Resolution)

**Problem**: The plan says "no custom ITensor index parsing" but uses `parse_site_from_index(idx)`.

**Resolution**: We DO need index-to-site mapping, but use ITensors' native API rather than manual tag parsing.

**Approved Method: Match indices against `state.sites`**
```julia
function get_site_number(op_index::Index, state_sites::Vector{Index}) -> Int
    # Find which site this index corresponds to by matching against state.sites
    # Use noprime to compare regardless of prime level
    for (ram_idx, site_idx) in enumerate(state_sites)
        if noprime(op_index) == noprime(site_idx)
            return ram_idx
        end
    end
    error("Index $op_index not found in state sites")
end

function get_affected_ram_sites(op::ITensor, state_sites::Vector{Index}) -> Vector{Int}
    # Get all site indices from operator (unprimed = input)
    op_site_inds = filter(idx -> hasplev(idx, 0), inds(op))  # unprimed indices
    return [get_site_number(idx, state_sites) for idx in op_site_inds]
end
```

**Why This Is Different From "Custom Parsing":**
- We compare Index objects directly, not parse tag strings
- Uses ITensors' `noprime()` and index equality
- No regex or string manipulation
- Relies on the fact that operators are built with indices from `state.sites`

**Updated apply_op_internal! Algorithm (EXACT CT.jl lines 147-172):**

**CRITICAL DISTINCTION: Contraction Range vs Operator Sites**

CT.jl iterates `i_list[1]+1:i_list[end]` - a **CONTIGUOUS RAM RANGE** from first to last affected site.
This is **NOT** the same as `i_list[2:end]` which would only iterate over operator sites.

**Why This Matters for Folded PBC:**
For AdjacentPair(10) with L=10 PBC: physical sites (10,1) → RAM sites [2,1] → sorted [1,2]
- `i_list = [1, 2]` (operator acts on RAM sites 1 and 2)
- Contraction range: `2:2` (= `i_list[1]+1 : i_list[end]` = `1+1:2`)
- This contracts MPS tensors 1 and 2 together

For a hypothetical 3-site gate on RAM sites [1, 4]:
- `i_list = [1, 4]` (sorted)
- Contraction range: `2:4` (= `1+1:4`)
- This contracts MPS tensors 1, 2, 3, and 4 together (including intermediate sites!)

```julia
function apply_op_internal!(mps::MPS, op::ITensor, state_sites::Vector{Index}; cutoff=1e-10, maxdim=100)
    # Extract RAM site indices using approved method (Contract 3.6)
    i_list = get_affected_ram_sites(op, state_sites)
    sort!(i_list)  # CT.jl line 149
    
    # === VERBATIM from CT.jl lines 151-172 ===
    
    # CT.jl line 151: Orthogonalize to leftmost site
    orthogonalize!(mps, i_list[1])
    
    # CT.jl lines 152-155: Contract MPS tensors in CONTIGUOUS RANGE
    mps_ij = mps[i_list[1]]
    for idx in i_list[1]+1:i_list[end]  # NOTE: CONTIGUOUS RANGE, not i_list[2:end]!
        mps_ij *= mps[idx]
    end
    
    # CT.jl line 156: Contract with operator
    mps_ij *= op
    
    # CT.jl line 157: Remove primes
    noprime!(mps_ij)
    
    # CT.jl lines 159-171: SVD decomposition to split back into MPS tensors
    if length(i_list) == 1
        mps[i_list[1]] = mps_ij
    else
        lefttags = (i_list[1] == 1) ? nothing : tags(linkind(mps, i_list[1]-1))
        for idx in i_list[1]:i_list[end]-1
            inds1 = (idx == 1) ? [siteind(mps, 1)] : [findindex(mps[idx-1], lefttags), findindex(mps[idx], "Site")]
            lefttags = tags(linkind(mps, idx))
            U, S, V = svd(mps_ij, inds1, cutoff=cutoff, lefttags=lefttags, maxdim=maxdim)
            mps[idx] = U
            mps_ij = S * V
        end
        mps[i_list[end]] = mps_ij
    end
    return nothing
end
```

**Key Invariants (from CT.jl):**
- `op` indices must come from `state.sites` (so Index matching works)
- Unprimed indices = input, primed indices = output
- Contraction range is `i_list[1]+1:i_list[end]` (CONTIGUOUS), not `i_list[2:end]`
- SVD loop iterates `i_list[1]:i_list[end]-1` to decompose back to MPS form

**Signature:** `apply_op_internal!(mps, op, state_sites; cutoff, maxdim)` takes `state_sites` for Index matching without tag parsing.

---

### Contract 3.7: ITensor Operator Naming for CT.jl Compatibility (CORRECTED Round 10)

**Verified from CT.jl Source:**
- CT.jl uses `siteinds("Qubit", L+ancilla)` at line 83
- CT.jl calls `expect(ct.mps, "Sz")` at line 504

**Resolution: Use "Sz" for CT.jl Compatibility**

For ITensor's "Qubit" site type, BOTH "Z" and "Sz" are valid:
- `"Z"` → returns expectation of Pauli-Z: ⟨σz⟩ ∈ [-1, 1]
- `"Sz"` → returns expectation of spin-z: ⟨Sz⟩ = ⟨σz⟩/2 ∈ [-0.5, 0.5]

**CT.jl uses "Sz", so we MUST use "Sz" for physics match:**
```julia
# CORRECT - matches CT.jl line 504
sZ = expect(state.mps, "Sz")

# WRONG - different scaling factor
# sZ = expect(state.mps, "Z")  # Returns 2x the CT.jl value!
```

**ITensor "Qubit" Site Type Operators:**
| Operator String | Matrix | Notes |
|-----------------|--------|-------|
| `"Z"` | diag(1, -1) | Pauli Z |
| `"Sz"` | diag(0.5, -0.5) | Spin-z (= Z/2) - **USE THIS for CT.jl match** |
| `"X"` | [[0,1],[1,0]] | Pauli X |
| `"Y"` | [[0,-i],[i,0]] | Pauli Y |
| `"Proj0"` or `"projUp"` | [[1,0],[0,0]] | |0⟩⟨0| projector |
| `"Proj1"` or `"projDn"` | [[0,0],[0,1]] | |1⟩⟨1| projector |

**Site Type:** Use `siteinds("Qubit", L)` (same as CT.jl)

**Observable Strings:** Use `"Sz"` (same as CT.jl) for CT.jl physics verification

**CANONICAL: Single-Site Expectation at Specific RAM Site:**
```julia
# ITensorMPS expect() returns a Vector for all sites when given a string operator
# To get expectation at a specific site, index the result

# CANONICAL PATTERN (verified against CT.jl line 504):
all_sz = expect(state.mps, "Sz")        # Returns Vector{Float64} of length L
sz_at_ram_site = all_sz[ram_site_index] # Get value at specific RAM site

# Example: Get Sz at physical site 1
ram_idx = state.phy_ram[1]
sz_at_site1 = expect(state.mps, "Sz")[ram_idx]

# For |0⟩ state: Sz = +0.5 (spin up)
# For |1⟩ state: Sz = -0.5 (spin down)
```

**DO NOT use** `expect(mps, "Sz"; sites=...)` - this is not the standard API for string operators.

---

### OBSOLETE SECTION REMOVED - apply_op_internal! SVD Algorithm

> **This section was removed (Momus Round 10 fix).**
> 
> The canonical `apply_op_internal!` specification is in **Contract 3.6** (lines ~486-534).
> It uses `get_site_number()` with Index matching, NOT `parse_site_from_index()`.
> 
> **Canonical signature:** `apply_op_internal!(mps, op, state_sites; cutoff, maxdim)`

---

### Contract 6: Phase 1 Module Loading (How to Run v2 Code)

**During Phase 1 (Tasks 1-8), v2 code lives in `src/v2/` and is NOT yet exported by main module.**

**Dependency Policy for v2**:
The v2 module uses ONLY these dependencies (all should already be in Project.toml from existing code):
- `ITensors` - tensor network operations
- `ITensorMPS` - MPS-specific operations
- `Random` - stdlib, always available
- `LinearAlgebra` - stdlib, always available

**JSON is NOT a v2 module dependency**. JSON serialization is only used in:
- `examples/ct_model.jl` - example script (uses `import JSON` locally)
- `test/verify_ct_match.jl` - test script (uses `import JSON` locally)

If JSON is not in Project.toml, add it via: `julia --project=. -e 'using Pkg; Pkg.add("JSON")'`
But this is only needed when running examples/tests, not for the core module.

**How to load v2 for testing**:
```julia
# Option 1: Direct include (RECOMMENDED for manual verification)
cd("/mnt/d/Rutgers/QuantumCircuitsMPS.jl")
include("src/v2/QuantumCircuitsMPSv2.jl")
using .QuantumCircuitsMPSv2  # Note the dot - local module

# Option 2: Add to load path (for REPL sessions)
push!(LOAD_PATH, "src/v2")
using QuantumCircuitsMPSv2
```

**Manual Verification Snippet Template (REPLACE all existing snippets)**:
```julia
# At start of EVERY manual verification:
cd("/mnt/d/Rutgers/QuantumCircuitsMPS.jl")
include("src/v2/QuantumCircuitsMPSv2.jl")
using .QuantumCircuitsMPSv2
using ITensors, ITensorMPS

# Then run task-specific tests...
```

**After Phase 2 (Task 9 verification passes)**:
- `src/QuantumCircuitsMPS.jl` will be updated to include/re-export v2
- Then `using QuantumCircuitsMPS` works normally

---

### Contract 4: Core API Shapes (Consistent Method Signatures)

---

### Contract 4.1: Basis Mapping Initialization Timing (Momus Blocker #4 Resolution)

**Problem**: Task 1 says "do NOT implement basis mapping yet" but needs `phy_ram`/`ram_phy` fields. Task 4 defines `compute_basis_mapping` but doesn't state WHEN it's called.

**Resolution**: Basis mapping is computed in the `SimulationState` CONSTRUCTOR, not in `initialize!`.

**Initialization Flow:**
```julia
# 1. SimulationState constructor computes basis mapping IMMEDIATELY
state = SimulationState(L=10, bc=:periodic)
# At this point:
#   - state.phy_ram, state.ram_phy are POPULATED (from compute_basis_mapping)
#   - state.sites is POPULATED (siteinds("Qubit", L))
#   - state.mps is NOTHING (no MPS yet)
#   - state.rng_registry is NOTHING (no RNG yet)

# 2. RNG is attached (optional, needed for HaarRandom gates)
state.rng_registry = RNGRegistry(ctrl=1, proj=2, haar=3, born=4)
# OR: passed to constructor as kwarg
state = SimulationState(L=10, bc=:periodic, rng=RNGRegistry(ctrl=1, proj=2, haar=3, born=4))

# 3. initialize! creates the MPS using existing phy_ram/ram_phy
initialize!(state, ProductState(x0=1//1024))
# At this point:
#   - state.mps is POPULATED (the actual MPS tensor network)
```

**SimulationState Constructor (Momus-approved specification):**
```julia
function SimulationState(;
    L::Int,
    bc::Symbol,  # :open or :periodic
    local_dim::Int = 2,
    cutoff::Float64 = 1e-10,
    maxdim::Int = 100,
    rng::Union{RNGRegistry, Nothing} = nothing  # NOTE: kwarg is `rng`, field is `rng_registry`
)
    # Validate bc
    bc in (:open, :periodic) || throw(ArgumentError("bc must be :open or :periodic, got $bc"))
    
    # Compute basis mapping IMMEDIATELY (Task 4's function)
    phy_ram, ram_phy = compute_basis_mapping(L, bc)
    
    # Create site indices in RAM order (independent of bc)
    sites = siteinds("Qubit", L)
    
    # Return state with MPS=nothing (deferred to initialize!)
    return SimulationState(
        nothing,  # mps - set by initialize!
        sites,
        phy_ram,
        ram_phy,
        L,
        bc,
        local_dim,
        cutoff,
        maxdim,
        rng,
        Dict{Symbol,Vector}(),  # observables
        Dict{Symbol,Any}()      # observable_specs
    )
end
```

**Why This Order:**
- Basis mapping depends on `L` and `bc` only (no MPS needed)
- `initialize!` needs `phy_ram`/`ram_phy` to create MPS in correct order
- User can inspect mapping before creating MPS
- RNG can be attached before or after constructor

---

### Contract 4.1.1: Task 1 vs Task 4 Dependency Resolution (Momus Blocker #1 Resolution)

**Problem**: Task 1 says "do NOT implement basis mapping yet" but the constructor needs `compute_basis_mapping()`.

**Resolution**: Task 1 includes a WORKING stub for `compute_basis_mapping()` that handles OBC only. Task 4 replaces this stub with full PBC support.

**Task 1 Implementation Strategy:**
```julia
# In src/v2/Core/basis.jl (Task 1 creates this file with OBC stub)
function compute_basis_mapping(L::Int, bc::Symbol)
    bc in (:open, :periodic) || throw(ArgumentError("bc must be :open or :periodic"))
    
    if bc == :open
        # OBC: direct mapping (identity)
        return collect(1:L), collect(1:L)
    else
        # PBC: Task 4 will implement folded mapping
        error("PBC basis mapping not implemented. Complete Task 4 first.")
    end
end
```

**What This Enables:**
- Task 1 acceptance criteria can use `bc=:open` and pass
- Task 4 replaces the `bc == :periodic` branch with the actual folded algorithm
- Tasks 1, 2, 3 can all be completed before Task 4 (with OBC testing only)
- After Task 4, full PBC testing becomes possible

**Task Dependency Update:**
- **Task 1**: Includes `compute_basis_mapping` with OBC support AND working `initialize!` for OBC. Acceptance uses `bc=:open`.
- **Task 4**: REPLACES the PBC error branch with actual folded mapping. Acceptance tests both OBC and PBC.

**Canonical Task 1 Scope (SINGLE SOURCE OF TRUTH):**
```julia
# Task 1 acceptance uses OBC ONLY (PBC available after Task 4)
state = SimulationState(L=10, bc=:open)  # Works in Task 1
@assert state.phy_ram == collect(1:10)    # Identity for OBC
@assert state.sites !== nothing           # Sites created
@assert state.mps === nothing             # MPS not yet created (before initialize!)

# initialize! MUST WORK for OBC in Task 1
initialize!(state, ProductState(x0=0))
@assert state.mps !== nothing             # MPS created after initialize!
@assert length(state.mps) == 10           # Correct size
```

---

### Contract 4.2: build_operator signatures

**build_operator signatures**:
```julia
# Single-qubit gates: site is a single Index
build_operator(gate::PauliX, site::Index, local_dim::Int) -> ITensor
build_operator(gate::Projection, site::Index, local_dim::Int) -> ITensor

# Two-qubit gates: sites is a Vector of 2 Index objects
build_operator(gate::HaarRandom, sites::Vector{Index}, local_dim::Int; rng::RNGRegistry) -> ITensor

# The RNG is passed via keyword argument ONLY for gates that need it
# Gates that don't need RNG (Pauli, Projection) don't have rng kwarg
```

**apply! signatures** (ALL defined in `src/v2/Core/apply.jl`):
```julia
# Primary interface (geometry determines sites) - EXPLICIT state
apply!(state::SimulationState, gate::AbstractGate, geo::AbstractGeometry) -> Nothing

# Direct site specification (physical site numbers, converted internally) - EXPLICIT state
apply!(state::SimulationState, gate::AbstractGate, sites::Vector{Int}) -> Nothing
apply!(state::SimulationState, gate::AbstractGate, site::Int) -> Nothing  # single-site sugar

# All conversions happen inside apply!:
# 1. geo.get_sites(state) → physical sites
# 2. physical sites → RAM indices via state.phy_ram
# 3. RAM indices → ITensor Index objects via state.sites
# 4. build_operator(gate, itensor_indices, state.local_dim; rng=state.rng_registry)
# 5. contract operator with MPS, truncate, normalize
```

**Context API signatures** (defined in `src/v2/API/context.jl`):
```julia
# Thread-local current state management
const CURRENT_STATE = Ref{Union{SimulationState, Nothing}}(nothing)

function with_state(fn::Function, state::SimulationState)
    old = CURRENT_STATE[]
    CURRENT_STATE[] = state
    try
        fn()
    finally
        CURRENT_STATE[] = old
    end
end

function current_state()::SimulationState
    s = CURRENT_STATE[]
    s === nothing && error("No current state. Use with_state(state) do ... end")
    return s
end

# IMPLICIT state versions (use current_state() internally)
# These are convenience wrappers for use inside with_state blocks
apply!(gate::AbstractGate, geo::AbstractGeometry) = apply!(current_state(), gate, geo)
apply!(gate::AbstractGate, sites::Vector{Int}) = apply!(current_state(), gate, sites)
apply!(gate::AbstractGate, site::Int) = apply!(current_state(), gate, site)

# Exported from context.jl: with_state, current_state, apply! (implicit versions)
```

**IMPORTANT**: The implicit `apply!(gate, geo)` methods are ONLY usable inside a `with_state` block.
Calling them without a current state throws an error. This prevents accidental misuse.

**Task 1 ProductState clarification** (SINGLE SOURCE OF TRUTH):
- `ProductState(x0::Rational)` stores the x0 value
- `initialize!(state, ::ProductState)` is **FULLY WORKING in Task 1** for OBC
- Task 1 acceptance criteria INCLUDES `initialize!` producing correct MPS for ProductState
- **RandomMPS**: The TYPE is created in Task 1, but runtime requires RNG → tested in Post-Task-2 integration
- PBC initialization works automatically after Task 4 provides `phy_ram/ram_phy`

---

### Contract 5: Objective Acceptance Criteria (Replacing Subjective Checks)

**Task 5 (apply!) - OBJECTIVE verification WITHOUT dependencies on Task 6**:

Task 5 verification uses ITensorMPS's `expect()` function to compute expectation values directly, avoiding dependency on Task 6's `born_probability`:

```julia
# Test: Apply X to |0⟩ → |1⟩, verify via ITensorMPS expect()
using ITensors, ITensorMPS

state = SimulationState(L=2, bc=:open)
initialize!(state, ProductState(x0=0))  # |00⟩ (MSB ordering, all zeros)

# Verify initial state: expect Sz = +0.5 at site 1 (spin up = |0⟩)
# Sz = 0.5 * (|0⟩⟨0| - |1⟩⟨1|) = diag(0.5, -0.5)
# For |0⟩: ⟨0|Sz|0⟩ = +0.5
ram_site1 = state.phy_ram[1]
sz_before = expect(state.mps, "Sz")[ram_site1]  # Canonical pattern per Contract 3.7
@assert abs(sz_before - 0.5) < 1e-10 "Before X: Sz expectation should be +0.5 (spin up)"

apply!(state, PauliX(), SingleSite(1))  # |00⟩ → |10⟩ (site 1 flipped)

# After X: Sz expectation should be -0.5 (spin down = |1⟩)
sz_after = expect(state.mps, "Sz")[ram_site1]  # Canonical pattern per Contract 3.7
@assert abs(sz_after + 0.5) < 1e-10 "After X: Sz expectation should be -0.5 (spin down)"

println("Task 5 apply! verification: PASS")
```

**Alternative verification using op() directly**:
```julia
# If expect() isn't suitable, build projector manually:
site1_idx = state.sites[state.phy_ram[1]]
# Use ITensors op() which properly handles index tagging
P1 = op("Proj1", site1_idx)  # |1⟩⟨1| projector, properly constructed

# Compute ⟨ψ|P|ψ⟩ using inner with MPO form
P1_mpo = MPO([P1], [site1_idx])  # Single-site MPO
p_value = real(inner(state.mps', P1_mpo, state.mps))
```

**Task 6 (Observables) - OBJECTIVE verification with known values**:
```julia
# Use Contract 6 loading first
cd("/mnt/d/Rutgers/QuantumCircuitsMPS.jl")
include("src/v2/QuantumCircuitsMPSv2.jl")
using .QuantumCircuitsMPSv2
using ITensors, ITensorMPS

# Domain wall for |0001⟩ (L=4, x0=1//16) at i1=1:
# With MSB ordering: x0=1//16 means site 4 has "1", sites 1-3 have "0"
# DW = Σ_j (L-j+1)^order * ⟨ψ| (Π_{k=1}^{j-1} P_0^k) P_1^j |ψ⟩
# For |0001⟩: only j=4 contributes (first "1" at position 4)
# DW_order1 = (4-4+1)^1 * 1 = 1
# DW_order2 = (4-4+1)^2 * 1 = 1

state = SimulationState(L=4, bc=:open)
initialize!(state, ProductState(x0=1//16))  # |0001⟩ (site 4 = "1")
dw1 = DomainWall(order=1)(state, 1)
dw2 = DomainWall(order=2)(state, 1)
@assert abs(dw1 - 1.0) < 1e-10 "DW1 for |0001⟩ should be 1"
@assert abs(dw2 - 1.0) < 1e-10 "DW2 for |0001⟩ should be 1"

# Born probability for |0001⟩ (using CT.jl MSB ordering):
# Site 1 = "0", Site 4 = "1"
@assert abs(born_probability(state, 1, 0) - 1.0) < 1e-10 "P(site1=0) should be 1"
@assert abs(born_probability(state, 4, 1) - 1.0) < 1e-10 "P(site4=1) should be 1"

println("Task 6 observable verification: PASS")
```

**Task 10 - EXACT output filename**:
CT.jl script produces filename: `MPS_(0,1)_L10_pctrl0.500_pproj0.000_sC42_sm123_x01_DW_T.json`
Must copy this to `test/reference/ct_reference_L10.json`

---

## Context

### Original Request
User wants to restart QuantumCircuitsMPS.jl from scratch because the current implementation has wrong abstraction levels, messy architecture, and doesn't match their mental model of State → Gate → Geometry → Observable.

### Interview Summary
**Key Discussions**:
- Current code is "too low-level in the wrong places" with disorganized module structure
- User's mental model: Gate = tensor/MPO only, Geometry = where gates apply, Observable = auto-tracked
- "PyTorch for Quantum Circuits" philosophy: physicists code as they speak
- Fresh start preferred over refactoring existing mess
- Both PBC and OBC needed in MVP

**Research Findings**:
- CT.jl uses folded basis for PBC with `phy_ram`/`ram_phy` mapping
- `random_control!` is a probabilistic staircase (left on control, right on Bernoulli)
- Key operations: Haar random, Projection, X gate, Reset, Born probability
- Domain wall observable specific to CT model with `xj = Set([0])`

### Metis Review
**Identified Gaps** (addressed):
- Context API ambiguity → Support BOTH explicit and implicit, explicit as primary
- Pointer management → Hidden from user, encapsulated in Geometry
- Verification strategy → Compare directly to CT.jl physics results
- OBC support scope → Include in MVP

---

## Work Objectives

### Core Objective
Create a physicist-friendly quantum circuit simulator using MPS where users specify physics (Gate + Geometry) without touching MPS implementation details.

### Concrete Deliverables
- `src/v2/QuantumCircuitsMPSv2.jl` - Temporary module during development (per Contract 1)
- `src/v2/Core/` - apply!, basis mapping, RNG registry
- `src/v2/State/` - SimulationState, initialization
- `src/v2/Gates/` - AbstractGate, HaarRandom, Projection, PauliX/Y/Z, Reset
- `src/v2/Geometry/` - AbstractGeometry, SingleSite, AdjacentPair, Bricklayer, Staircase
- `src/v2/Observables/` - AbstractObservable, DomainWall, BornProbability
- `src/v2/API/` - Multiple API style wrappers
- `examples/ct_model.jl` - CT.jl reproduction using new API

### Definition of Done
- [ ] `examples/ct_model.jl` produces DW1/DW2 matching CT.jl within 1e-10
- [ ] All three API styles (OO-explicit, OO-imperative, Functional) work
- [ ] Both PBC and OBC boundary conditions work
- [ ] RNG reproducibility: same seeds → identical results

### Must Have
- Clean State → Gate → Geometry → Observable abstraction hierarchy
- Hidden MPS details (user never sees phy_ram, ITensor indices)
- Auto-tracked observables
- Extensibility for user-defined gates/observables

### Must NOT Have (Guardrails)
- ❌ Ancilla support (deferred)
- ❌ TCI integration (not needed)
- ❌ adder_MPO from CT.jl (only for xj={1/3, 2/3}, not our target)
- ❌ More than 2 levels of type hierarchy
- ❌ Multi-threading support (out of scope)
- ❌ Custom ITensor index parsing (use native tags)

---

## Verification Strategy

### Test Decision
- **Infrastructure exists**: NO (fresh start)
- **User wants tests**: Manual verification against CT.jl
- **Framework**: Julia's Test stdlib for basic assertions
- **QA approach**: Physics verification via direct comparison to CT.jl outputs

### Verification Procedure

**For CT.jl Match**:
1. Run CT.jl: `run_dw_t(L=10, p_ctrl=0.5, p_proj=0.0, seed_C=42, seed_m=123)`
2. Capture DW1, DW2 arrays to reference file
3. Run new `examples/ct_model.jl` with same parameters
4. Assert: `maximum(abs.(new_dw1 .- ref_dw1)) < 1e-10`

**Evidence Required**:
- Terminal output showing comparison results
- Saved reference data from CT.jl

---

## Execution Strategy

### Parallel Execution Waves

```
Wave 1 (Start Immediately):
├── Task 1: Core State Infrastructure
├── Task 2: RNG Registry
└── Task 10: Generate CT.jl Reference Data

Wave 2 (After Wave 1):
├── Task 3: Gate System
├── Task 4: Basis Mapping (PBC/OBC)
└── Task 6: Observable System

Wave 3 (After Wave 2):
├── Task 5: Geometry System
└── Task 6 continues (if not finished in Wave 2)

Wave 4 (After Wave 3 - Task 5 complete):
├── Task 7: API Wrappers (depends on Task 5)
└── Task 8: CT Model Example (depends on Tasks 5, 6, 7)

Wave 5 (After Wave 4):
└── Task 9: Verification & Cleanup

Critical Path: Task 1 → Task 3 → Task 5 → Task 7 → Task 8 → Task 9
Parallel Speedup: ~35% faster than sequential
```

### Dependency Matrix

| Task | Depends On | Blocks | Can Parallelize With |
|------|------------|--------|---------------------|
| 0 | None | ALL | None (must be first) |
| 1 | 0 | 3, 4, 5, 6 | 2, 10 |
| 2 | 0 | 3 | 1, 10 |
| 3 | 1, 2 | 5, 7, 8 | 4, 6 |
| 4 | 1 | 5, 8 | 3, 6 |
| 5 | 3, 4 | 7, 8 | 6 |
| 6 | 1 | 8 | 3, 4, 5 |
| 7 | 3, 5 | 8 | None (after 5) |
| 8 | 3, 4, 5, 6, 7 | 9 | None |
| 9 | 8, 10 | None | None |
| 10 | 0 | 9 | 1, 2 |

### Agent Dispatch Summary

| Wave | Tasks | Recommended Agents |
|------|-------|-------------------|
| 0 | 0 | `delegate_task(category="quick", ...)` - module scaffold |
| 1 | 1, 2, 10 | `delegate_task(category="quick", ...)` for each |
| 2 | 3, 4, 6 | `delegate_task(category="unspecified-high", ...)` |
| 3 | 5, 7, 8 | `delegate_task(category="unspecified-high", ...)` |
| 4 | 9 | `delegate_task(category="quick", ...)` |

---

## TODOs

### Task 0: Module Entrypoint Scaffold (MUST BE FIRST)

- [ ] 0. Create v2 module entrypoint for Contract 6 loading

  **What to do**:
  - Create `src/v2/QuantumCircuitsMPSv2.jl` module file with:
    ```julia
    module QuantumCircuitsMPSv2
    
    using ITensors
    using ITensorMPS
    using Random
    using LinearAlgebra
    # NOTE: JSON is NOT imported here - only used in examples/tests
    
    # Core (will be added by subsequent tasks)
    # include("Core/rng.jl")
    # include("Core/basis.jl")
    # include("Core/apply.jl")
    
    # State (will be added by subsequent tasks)
    # include("State/State.jl")
    # include("State/initialization.jl")
    
    # Gates (will be added by subsequent tasks)
    # include("Gates/Gates.jl")
    
    # Geometry (will be added by subsequent tasks)
    # include("Geometry/Geometry.jl")
    
    # Observables (will be added by subsequent tasks)
    # include("Observables/Observables.jl")
    
    # API (will be added by subsequent tasks)
    # include("API/imperative.jl")
    # include("API/functional.jl")
    # include("API/context.jl")
    
    # Exports will be added as components are implemented
    
    end # module
    ```
  - Create directory structure: `src/v2/Core/`, `src/v2/State/`, `src/v2/Gates/`, `src/v2/Geometry/`, `src/v2/Observables/`, `src/v2/API/`
  - **Each subsequent task UNcomments its include() and adds exports**

  **Must NOT do**:
  - Do NOT implement any functionality (just scaffold)
  - Do NOT modify existing `src/QuantumCircuitsMPS.jl`

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Pure scaffold, no logic
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Wave 0 (must be first)
  - **Blocks**: ALL subsequent tasks
  - **Blocked By**: None

  **Acceptance Criteria**:
  - [ ] `src/v2/QuantumCircuitsMPSv2.jl` exists and defines `module QuantumCircuitsMPSv2`
  - [ ] All subdirectories exist: `src/v2/Core/`, `src/v2/State/`, etc.
  - [ ] `include("src/v2/QuantumCircuitsMPSv2.jl"); using .QuantumCircuitsMPSv2` succeeds in Julia REPL

  **Manual Verification**:
  ```julia
  cd("/mnt/d/Rutgers/QuantumCircuitsMPS.jl")
  include("src/v2/QuantumCircuitsMPSv2.jl")
  using .QuantumCircuitsMPSv2
  println("Module scaffold: PASS")
  ```

  **Commit**: YES
  - Message: `chore(v2): scaffold module entrypoint and directory structure`
  - Files: `src/v2/QuantumCircuitsMPSv2.jl`, `src/v2/Core/.gitkeep`, `src/v2/State/.gitkeep`, etc.

---

### Task 1: Core State Infrastructure

- [ ] 1. Create SimulationState struct and initialization

  **What to do**:
  - Create `src/v2/State/State.jl` with `SimulationState` mutable struct
  - Fields (note Union types for deferred initialization):
    - `mps::Union{MPS,Nothing}` - starts as `nothing`, set by `initialize!`
    - `sites::Union{Vector{Index},Nothing}` - ITensor site indices (created during construction)
    - `phy_ram::Vector{Int}` - physical-to-RAM mapping (set by `compute_basis_mapping`)
    - `ram_phy::Vector{Int}` - RAM-to-physical mapping (set by `compute_basis_mapping`)
    - `L::Int` - system size
    - `bc::Symbol` - boundary condition (`:open` or `:periodic`)
    - `local_dim::Int` - qubit dimension (default 2)
    - `cutoff::Float64` - SVD cutoff (default 1e-10)
    - `maxdim::Int` - max bond dimension (default 100)
    - `rng_registry::Union{RNGRegistry,Nothing}` - starts as `nothing`, set by Task 2 integration
    - `observables::Dict{Symbol,Vector}` - tracked observable values
    - `observable_specs::Dict{Symbol,Any}` - observable specifications
  - Create `src/v2/Core/basis.jl` with OBC stub per Contract 4.1.1:
    ```julia
    function compute_basis_mapping(L::Int, bc::Symbol)
        bc in (:open, :periodic) || throw(ArgumentError("bc must be :open or :periodic"))
        if bc == :open
            return collect(1:L), collect(1:L)  # Identity for OBC
        else
            error("PBC basis mapping not implemented. Complete Task 4 first.")
        end
    end
    ```
  - Constructor calls `compute_basis_mapping()` to set `phy_ram` and `ram_phy`, creates `sites`
  - Create `src/v2/State/initialization.jl` with abstract type `AbstractInitialState` and implementations: `RandomMPS`, `ProductState`, `CustomState`
  - Use multiple dispatch: `initialize!(state, ::RandomMPS)`, `initialize!(state, ::ProductState)`, etc.
  - **CRITICAL: `initialize!` must be FULLY WORKING for OBC in Task 1** (not just types). This includes:
    - `ProductState`: Create MPS with correct MSB/LSB bit ordering per CT.jl (see bit ordering table below) - **TESTED IN TASK 1**
    - `RandomMPS`: Create random MPS using ITensorMPS's `randomMPS()` - **DEFERRED TO POST-TASK-2** (requires RNG)
    - RAM reordering: Use `state.ram_phy` to map physical bits to RAM order
  - **PBC will automatically work** once Task 4 provides the correct `phy_ram/ram_phy` mapping
  - **Note on RandomMPS**: The TYPE is created in Task 1, but runtime verification is deferred to post-Task-2 integration test because it requires RNGRegistry

  **Must NOT do**:
  - Do NOT implement PBC basis mapping (Task 4 replaces the error branch)
  - Do NOT implement RNG registry yet (Task 2)
  - Do NOT add ancilla support

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Single struct definition and basic initialization, <50 lines core code
  - **Skills**: []
    - No special skills needed for basic Julia struct creation

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 1 (with Tasks 2, 10)
  - **Blocks**: Tasks 3, 4, 5, 6
  - **Blocked By**: None

  **References**:

  **Pattern References**:
  - `/mnt/d/Rutgers/CT_MPS/CT/src/CT.jl:15-47` - `CT_MPS` struct fields (reference for what state needs to track)
  - `/mnt/d/Rutgers/CT_MPS/CT/src/CT.jl:105-139` - `_initialize_vector` function (RandomMPS vs ProductState logic)

  **External References**:
  - ITensorMPS.jl `randomMPS` (ITensorMPS v0.3+ signature):
    ```julia
    # EXACT signature for ITensorMPS 0.3+:
    randomMPS(sites::Vector{<:Index}; linkdims::Union{Int,Vector{Int}}=1) -> MPS
    
    # Usage in initialize!:
    state.mps = randomMPS(state.sites; linkdims=init.bond_dim)
    ```
    - Creates random MPS with specified bond dimension across all links
    - **RNG Handling**: ITensorMPS 0.3+ uses `Random.default_rng()` internally
    - To use `:state_init` stream from our RNGRegistry, temporarily set default RNG:
      ```julia
      function initialize!(state::SimulationState, init::RandomMPS)
          state.rng_registry === nothing && throw(ArgumentError(
              "RandomMPS requires RNGRegistry with :state_init stream. Attach RNG before calling initialize!"))
          
          # Temporarily replace default RNG with our :state_init stream
          old_rng = Random.default_rng()
          try
              Random.seed!(get_rng(state.rng_registry, :state_init))
              state.mps = randomMPS(state.sites; linkdims=init.bond_dim)
          finally
              Random.seed!(old_rng)  # Restore
          end
      end
      ```
    - Example: `randomMPS(state.sites; linkdims=10)` creates MPS with bond dim 10
  - ITensorMPS `MPS` constructor: `MPS(sites, states::Vector{String}) -> MPS` - creates product state MPS
    - Example: `MPS(state.sites, ["0", "0", "1", "0"])` creates |0010⟩
    - State strings: "0" = spin up, "1" = spin down for "Qubit" site type

  **Acceptance Criteria** (per Contract 4.1.1 - OBC only in Task 1):
  - [ ] `SimulationState(L=10, bc=:open)` creates valid state struct with working OBC basis mapping
  - [ ] `state.phy_ram == collect(1:10)` (identity mapping for OBC)
  - [ ] `state.sites !== nothing` (sites created during construction)
  - [ ] `state.mps === nothing` (MPS not yet created - deferred to `initialize!`)
  - [ ] `state.L`, `state.bc`, `state.local_dim` are accessible
  - [ ] `ProductState(x0=1//1024)` creates the ProductState TYPE (stores x0 only)
  - [ ] `RandomMPS(bond_dim=10)` creates the RandomMPS TYPE (stores bond_dim only)
  - [ ] `SimulationState(L=10, bc=:periodic)` throws error "PBC basis mapping not implemented. Complete Task 4 first."
  - [ ] **`initialize!` works for OBC** (CRITICAL - not deferred):
    - `initialize!(state, ProductState(x0=0))` creates all-zero MPS
    - `state.mps !== nothing` after initialize!
    - `length(state.mps) == state.L`

  **Manual Verification** (use Contract 6 loading):
  ```julia
  cd("/mnt/d/Rutgers/QuantumCircuitsMPS.jl")
  include("src/v2/QuantumCircuitsMPSv2.jl")
  using .QuantumCircuitsMPSv2
  using ITensorMPS  # For inner()
  
  # Test OBC struct creation (works in Task 1 per Contract 4.1.1)
  state = SimulationState(L=10, bc=:open)
  @assert state.L == 10
  @assert state.bc == :open
  @assert state.phy_ram == collect(1:10)  # Identity for OBC
  @assert state.sites !== nothing          # Sites created
  @assert state.mps === nothing            # MPS not created yet
  
  # === CRITICAL: Test initialize! works for OBC ===
  initialize!(state, ProductState(x0=0))   # All zeros (x0=0 means integer 0)
  @assert state.mps !== nothing "MPS should be created after initialize!"
  @assert length(state.mps) == 10 "MPS should have L tensors"
  
  # Verify it's actually all-zeros by checking norm is 1 and expectation
  @assert abs(inner(state.mps, state.mps) - 1.0) < 1e-10 "MPS should be normalized"
  
  # NOTE: RandomMPS runtime verification DEFERRED to post-Task-2 integration test
  # because it requires RNGRegistry which is implemented in Task 2.
  # Here we only verify the TYPE can be created:
  init2 = RandomMPS(bond_dim=10)
  @assert init2.bond_dim == 10
  
  # Test PBC throws until Task 4
  try
      SimulationState(L=10, bc=:periodic)
      error("Should have thrown!")
  catch e
      @assert occursin("PBC basis mapping not implemented", e.msg)
  end
  
  # Test initialization type creation
  init = ProductState(x0=1//1024)
  @assert init.x0 == 1//1024
  
  init2 = RandomMPS(bond_dim=10)
  @assert init2.bond_dim == 10
  
  println("Task 1 State struct: PASS")
  ```
  
  **Post-Task 2 Integration Test** (run after Task 2 completes - tests RandomMPS):
  ```julia
  cd("/mnt/d/Rutgers/QuantumCircuitsMPS.jl")
  include("src/v2/QuantumCircuitsMPSv2.jl")
  using .QuantumCircuitsMPSv2
  using ITensorMPS
  
  # After Task 2, RNGRegistry exists and RandomMPS can be tested:
  state = SimulationState(L=8, bc=:open, rng=RNGRegistry(ctrl=1, proj=2, haar=3, born=4, state_init=5))
  initialize!(state, RandomMPS(bond_dim=4))
  @assert state.mps !== nothing "RandomMPS should create MPS"
  @assert length(state.mps) == 8
  
  # Test RandomMPS throws without RNG
  state2 = SimulationState(L=8, bc=:open)  # No RNG attached
  try
      initialize!(state2, RandomMPS(bond_dim=4))
      error("Should have thrown!")
  catch e
      @assert occursin("RandomMPS requires RNGRegistry", string(e))
  end
  
  println("RandomMPS integration: PASS")
  ```
  
  **Post-Task 4 Integration Test** (run after Task 4 completes):
  ```julia
  cd("/mnt/d/Rutgers/QuantumCircuitsMPS.jl")
  include("src/v2/QuantumCircuitsMPSv2.jl")
  using .QuantumCircuitsMPSv2
  
  # After Task 4, PBC works:
  state = SimulationState(L=10, bc=:periodic)
  @assert state.phy_ram != collect(1:10)  # Folded mapping for PBC
  initialize!(state, ProductState(x0=1//1024))  # NOW creates MPS
  @assert state.mps !== nothing
  @assert length(state.sites) == 10
  println("State initialization integration: PASS")
  ```

  **Commit**: YES
  - Message: `feat(state): add SimulationState struct with OBC basis mapping stub`
  - Files: `src/v2/State/State.jl`, `src/v2/State/initialization.jl`, `src/v2/Core/basis.jl`

---

### Task 2: RNG Registry System

- [ ] 2. Create RNG registry for reproducible randomness

  **What to do** (per Contract 3.1 - canonical API):
  - Create `src/v2/Core/rng.jl` with `RNGRegistry` struct
  - Fields: `streams::Dict{Symbol, AbstractRNG}`
  - **Canonical constructor**: `RNGRegistry(; ctrl::Int, proj::Int, haar::Int, born::Int, state_init::Int=0)` - first 4 kwargs REQUIRED
  - Functions: `get_rng(registry, name)` returns raw RNG, `rand(registry, name)` convenience wrapper, `randn(registry, name, dims...)` for matrices
  - Pre-populated streams: `:ctrl`, `:proj`, `:haar`, `:born`, `:state_init` from constructor

  **Must NOT do**:
  - Do NOT add `register_rng!` function (streams are fixed at construction per Contract 3.1)
  - Do NOT support tuple seeding syntax (use keyword args only)
  - Do NOT add thread-safety locks (out of scope)
  - Do NOT implement custom RNG types

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Simple Dict wrapper with convenience functions
  - **Skills**: []
    - Basic Julia programming

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 1 (with Tasks 1, 10)
  - **Blocks**: Task 3
  - **Blocked By**: None

  **References**:

  **Pattern References**:
  - `/mnt/d/Rutgers/CT_MPS/CT/src/CT.jl:69-72` - RNG initialization pattern from CT.jl (note: CT.jl uses old mangled design, we use clean design)
  - `/mnt/d/Rutgers/CT_MPS/CT/src/CT.jl:29-32` - RNG field declarations

  **External References**:
  - Julia Random stdlib: `MersenneTwister`, `AbstractRNG`

  **Acceptance Criteria** (per Contract 3.1):
  - [ ] `RNGRegistry(ctrl=1, proj=2, haar=3, born=4)` creates registry with named streams
  - [ ] `rand(registry, :haar)` returns Float64 (mid-level API)
  - [ ] `get_rng(registry, :haar)` returns AbstractRNG (low-level API)
  - [ ] Same seed → same sequence guaranteed
  - [ ] `randn(registry, :haar, 4, 4)` returns 4x4 array (for Haar random)

  **Manual Verification** (use Contract 6 loading):
  ```julia
  cd("/mnt/d/Rutgers/QuantumCircuitsMPS.jl")
  include("src/v2/QuantumCircuitsMPSv2.jl")
  using .QuantumCircuitsMPSv2
  
  # Test mid-level API
  rng = RNGRegistry(ctrl=1, proj=2, haar=3, born=4)
  v1 = rand(rng, :haar)
  
  # Test reproducibility
  rng2 = RNGRegistry(ctrl=1, proj=2, haar=3, born=4)
  v2 = rand(rng2, :haar)
  @assert v1 == v2 "RNG reproducibility FAILED"
  
  # Test low-level API (Contract 3.1)
  rng3 = RNGRegistry(ctrl=1, proj=2, haar=3, born=4)
  haar_rng = get_rng(rng3, :haar)
  v3 = rand(haar_rng)  # Julia's rand(::AbstractRNG)
  @assert v3 == v1 "Low-level API should match mid-level"
  
  # Test randn for Haar random
  rng4 = RNGRegistry(ctrl=1, proj=2, haar=3, born=4)
  _ = rand(rng4, :haar)  # consume one value to sync
  m1 = randn(rng4, :haar, 4, 4)
  @assert size(m1) == (4, 4) "randn should return matrix"
  
  println("RNG Registry: PASS")
  ```

  **Commit**: YES
  - Message: `feat(core): add RNGRegistry for reproducible randomness`
  - Files: `src/v2/Core/rng.jl`

---

### Task 3: Gate System

- [ ] 3. Create gate type hierarchy and implementations

  **What to do**:
  - Create `src/v2/Gates/Gates.jl` with `AbstractGate` abstract type
  - Create `src/v2/Gates/single_qubit.jl`: `PauliX`, `PauliY`, `PauliZ`, `Projection(outcome::Int)`
  - Create `src/v2/Gates/two_qubit.jl`: `HaarRandom`, `CZ`
  - **CNOT is OUT OF MVP SCOPE**: Not used by CT.jl target script. Can be added later if needed.
  - Create `src/v2/Gates/composite.jl`: `Reset` (projection + conditional X)
  
  **CZ Gate Specification (from CT.jl line 594-597):**
  ```julia
  # CZ matrix (control-Z): diagonal with -1 in bottom-right
  # |00⟩ → |00⟩, |01⟩ → |01⟩, |10⟩ → |10⟩, |11⟩ → -|11⟩
  CZ_mat = [1.0  0.0  0.0  0.0;
            0.0  1.0  0.0  0.0;
            0.0  0.0  1.0  0.0;
            0.0  0.0  0.0 -1.0+0im]
  
  # Site order: sites[1] = control, sites[2] = target (for CZ, symmetric so order doesn't matter)
  # For asymmetric gates (like CNOT if added later), document control/target convention
  ```
  - Implement `build_operator(gate::AbstractGate, sites, local_dim)` returning ITensor
  - HaarRandom must use RNG from state

  **Must NOT do**:
  - Do NOT implement apply! yet (that's Task 5)
  - Do NOT implement adder_MPO
  - Do NOT add gate parameters beyond what CT.jl needs

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
    - Reason: Multiple files, ITensor integration, needs careful matrix definitions
  - **Skills**: []
    - Julia + ITensors knowledge needed

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 2 (with Tasks 4, 6)
  - **Blocks**: Tasks 5, 7, 8
  - **Blocked By**: Tasks 1, 2

  **References**:

  **Pattern References**:
  - `/mnt/d/Rutgers/CT_MPS/CT/src/CT.jl:182-217` - `S!()` Haar random implementation
  - `/mnt/d/Rutgers/CT_MPS/CT/src/CT.jl:259-277` - `P!()` and `X!()` implementations
  - `/mnt/d/Rutgers/CT_MPS/CT/src/CT.jl:232-245` - `R!()` reset implementation

  **API References**:
  - ITensors.jl `op()` function for standard operators
  - Haar random unitary: `U(4, rng)` generates 4x4 Haar random matrix

  **Acceptance Criteria**:
  - [ ] `build_operator(PauliX(), sites[1], 2)` returns correct σ_x ITensor
  - [ ] `build_operator(Projection(0), sites[1], 2)` returns |0⟩⟨0| projector
  - [ ] `build_operator(HaarRandom(), [sites[1], sites[2]], 2; rng=rng)` returns 4x4 unitary ITensor
  - [ ] Haar random is deterministic given same RNG

  **Manual Verification** (use Contract 6 loading):
  ```julia
  cd("/mnt/d/Rutgers/QuantumCircuitsMPS.jl")
  include("src/v2/QuantumCircuitsMPSv2.jl")
  using .QuantumCircuitsMPSv2
  using ITensors, ITensorMPS
  
  sites = siteinds("Qubit", 2)
  
  # PauliX - verify using ITensor's element access with IndexVal
  X = build_operator(PauliX(), sites[1], 2)
  # X should be: |0⟩⟨1| + |1⟩⟨0| = off-diagonal ones
  # Access element: X[out_index => out_val, in_index => in_val]
  # For "Qubit" sites, values are 1-indexed (1=|0⟩, 2=|1⟩)
  @assert abs(X[sites[1]' => 1, sites[1] => 2] - 1) < 1e-10 "PauliX[0,1] should be 1"
  @assert abs(X[sites[1]' => 2, sites[1] => 1] - 1) < 1e-10 "PauliX[1,0] should be 1"
  
  # Projection - |0⟩⟨0| projector
  P0 = build_operator(Projection(0), sites[1], 2)
  @assert abs(P0[sites[1]' => 1, sites[1] => 1] - 1) < 1e-10 "Proj0[0,0] should be 1"
  @assert abs(P0[sites[1]' => 2, sites[1] => 2]) < 1e-10 "Proj0[1,1] should be 0"
  
  # HaarRandom reproducibility (per Contract 3.1 and 4.2)
  # Per Contract 4.2: build_operator(::HaarRandom, sites::Vector{Index}, local_dim; rng::RNGRegistry)
  rng1 = RNGRegistry(ctrl=1, proj=2, haar=3, born=4)
  H1 = build_operator(HaarRandom(), [sites[1], sites[2]], 2; rng=rng1)
  
  rng2 = RNGRegistry(ctrl=1, proj=2, haar=3, born=4)
  H2 = build_operator(HaarRandom(), [sites[1], sites[2]], 2; rng=rng2)
  @assert norm(H1 - H2) < 1e-10 "HaarRandom not reproducible"
  
  println("Gate system: PASS")
  ```

  **Commit**: YES
  - Message: `feat(gates): add gate type hierarchy with Pauli, Projection, HaarRandom`
  - Files: `src/v2/Gates/Gates.jl`, `src/v2/Gates/single_qubit.jl`, `src/v2/Gates/two_qubit.jl`, `src/v2/Gates/composite.jl`

---

### Task 4: Basis Mapping (PBC/OBC)

- [ ] 4. Implement phy_ram/ram_phy mapping for PBC (complete the stub from Task 1)

  **What to do**:
  - **UPDATE** `src/v2/Core/basis.jl` (already exists from Task 1 with OBC stub per Contract 4.1.1)
  - **REPLACE** the error branch `error("PBC basis mapping not implemented...")` with actual PBC folded mapping
  - **CRITICAL CONSTRAINT**: **PBC requires even L**. If `bc=:periodic` and L is odd, throw `ArgumentError("PBC folded basis requires even L")`. This matches CT.jl's assumption.
  - **Naming convention**:
    - `phy_ram[physical_site] = ram_index` (physical → RAM lookup)
    - `ram_phy[ram_index] = physical_site` (RAM → physical lookup)
  - **Return order**: `(phy_ram, ram_phy)` - phy_ram first
  - **OBC (bc=:open)**: Already works from Task 1 - direct mapping `[1,2,3,...,L]`
  - **PBC (bc=:periodic)**: Folded mapping where `ram_phy = [1, L, 2, L-1, 3, L-2, ...]` (interleaved from ends)
    - CT.jl formula: `ram_phy = [i for pairs in zip(1:L÷2, reverse((L÷2+1):L)) for i in pairs]`
    - Then `phy_ram` is the inverse: `phy_ram[ram_phy[i]] = i for i in 1:L`
  - **Accepted bc symbols**: `:open` and `:periodic` ONLY. Error on any other value.
  - Add `physical_to_ram(state, phy_site)` and `ram_to_physical(state, ram_site)` helpers

  **Must NOT do**:
  - Do NOT change the folded algorithm from CT.jl (it's correct)
  - Do NOT add ancilla support

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Small, well-defined index manipulation
  - **Skills**: []
    - Basic algorithm understanding

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 2 (with Tasks 3, 6)
  - **Blocks**: Tasks 5, 8
  - **Blocked By**: Task 1

  **References**:

  **Pattern References**:
  - `/mnt/d/Rutgers/CT_MPS/CT/src/CT.jl:81-103` - `_initialize_basis()` EXACT algorithm to replicate

  **How initialize! uses basis mapping** (CRITICAL for ProductState - CT.jl Exact Match):
  
  **CT.jl bit ordering** (from `/mnt/d/Rutgers/CT_MPS/CT/src/CT.jl:105-113`):
  ```julia
  # CT.jl's _initialize_vector:
  vec_int = dec2bin(x0, L)  # e.g., dec2bin(1//1024, 10) = 1
  vec_int_pos = [string(s) for s in lpad(string(vec_int, base=2), L, "0")]  # e.g., ["0","0","0","0","0","0","0","0","0","1"]
  # vec_int_pos[i] is the bit value at PHYSICAL site i
  # MPS created with: [vec_int_pos[ram_phy[i]] for i in 1:L]
  ```
  
  **CRITICAL**: CT.jl uses **MSB at site 1, LSB at site L** ordering.
  - `x0 = 1//2^L` means the "1" is at physical site L (the last site)
  - `x0 = 1//2` means the "1" is at physical site 1 (the first site)
  
  **Truth Table Example (L=4)**:
  | x0 | dec2bin | lpad binary | vec_int_pos | Site 1 | Site 2 | Site 3 | Site 4 |
  |----|---------|-------------|-------------|--------|--------|--------|--------|
  | 1//16 (=1/2^4) | 1 | "0001" | ["0","0","0","1"] | 0 | 0 | 0 | 1 |
  | 1//8 (=2/2^4) | 2 | "0010" | ["0","0","1","0"] | 0 | 0 | 1 | 0 |
  | 1//2 (=8/2^4) | 8 | "1000" | ["1","0","0","0"] | 1 | 0 | 0 | 0 |
  | 3//16 | 3 | "0011" | ["0","0","1","1"] | 0 | 0 | 1 | 1 |
  
  **Implementation in initialize!**:
  ```julia
  function initialize!(state, init::ProductState)
      L = state.L
      vec_int = BigInt(floor(init.x0 * (BigInt(1) << L)))  # dec2bin
      vec_int_pos = [string(s) for s in lpad(string(vec_int, base=2), L, "0")]
      # vec_int_pos[i] is bit at physical site i (MSB at site 1)
      
      # Reorder to RAM order using ram_phy
      ram_bits = [vec_int_pos[state.ram_phy[i]] for i in 1:L]
      state.mps = MPS(ComplexF64, state.sites, ram_bits)
  end
  ```
  
  **Verification for x0=1//2^L (CT script's x01 label)**:
  - For L=10, x0=1//1024: `vec_int_pos = ["0","0","0","0","0","0","0","0","0","1"]`
  - Physical site 10 has value "1", all others "0"
  - This is the starting state used in CT model verification (Task 10)

  **Acceptance Criteria**:
  - [ ] `compute_basis_mapping(4, :open)` returns `([1,2,3,4], [1,2,3,4])` where both are identity
  - [ ] `compute_basis_mapping(4, :periodic)` returns `(phy_ram=[1,3,4,2], ram_phy=[1,4,2,3])`
    - `ram_phy = [1,4,2,3]` from CT.jl formula (RAM position → physical site)
    - `phy_ram` is inverse: physical site 1→RAM 1, site 2→RAM 3, site 3→RAM 4, site 4→RAM 2
  - [ ] `compute_basis_mapping(6, :periodic)` matches CT.jl output

  **Manual Verification** (use Contract 6 loading):
  ```julia
  cd("/mnt/d/Rutgers/QuantumCircuitsMPS.jl")
  include("src/v2/QuantumCircuitsMPSv2.jl")
  using .QuantumCircuitsMPSv2
  
  # OBC - direct (both are identity)
  phy_ram, ram_phy = compute_basis_mapping(4, :open)
  @assert phy_ram == [1,2,3,4] "OBC phy_ram"
  @assert ram_phy == [1,2,3,4] "OBC ram_phy"
  
  # PBC - folded
  # CT.jl: ram_phy = [i for pairs in zip(1:L÷2, reverse((L÷2+1):L)) for i in pairs]
  # L=4: zip([1,2], [4,3]) → [1,4,2,3]
  phy_ram_p, ram_phy_p = compute_basis_mapping(4, :periodic)
  
  # ram_phy[ram_index] = physical_site
  @assert ram_phy_p == [1,4,2,3] "PBC ram_phy: RAM[1]→PHY1, RAM[2]→PHY4, RAM[3]→PHY2, RAM[4]→PHY3"
  
  # phy_ram[physical_site] = ram_index (inverse of ram_phy)
  # PHY1→RAM1, PHY2→RAM3, PHY3→RAM4, PHY4→RAM2
  @assert phy_ram_p == [1,3,4,2] "PBC phy_ram: inverse of ram_phy"
  
  println("Basis mapping: PASS")
  ```

  **Commit**: YES
  - Message: `feat(core): add basis mapping for PBC (folded) and OBC`
  - Files: `src/v2/Core/basis.jl`

---

### Task 5: Geometry System and apply!

- [ ] 5. Create geometry types and implement apply!

  **What to do**:
  - Create `src/v2/Geometry/Geometry.jl` with `AbstractGeometry`
  - Implement: `SingleSite(site)`, `AdjacentPair(first)`, `Bricklayer(parity)` where parity is `:odd` or `:even`, `AllSites`
  - Implement `Staircase` with internal pointer: `StaircaseLeft`, `StaircaseRight`
  - Create `src/v2/Core/apply.jl` with `apply!(state, gate, geometry)` and `apply!(state, gate, sites::Vector{Int})`
  - apply! must: get sites from geometry, build operator, contract with MPS via custom SVD (per Contract 3.5)
  - Normalization is gate-class-dependent per Contract 3.5 (unitaries: NO normalize, projections: YES normalize)

  **Must NOT do**:
  - Do NOT make pointer field directly settable by users (internal field, not public API)
  - Do NOT implement probabilistic branching yet (that's Task 7)
  - Do NOT add conditional gates
  
  **Pointer API Clarification**: The internal pointer is NOT user-settable, but a read-only accessor `current_position(staircase)` is REQUIRED per Contract 2.2. This is safe because users can observe but not manipulate pointer state.

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
    - Reason: Core engine, MPS contraction logic, multiple geometry types
  - **Skills**: []
    - ITensor MPS operations expertise needed

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 3 (can run with Task 6 if not yet complete)
  - **Blocks**: Tasks 7, 8
  - **Blocked By**: Tasks 3, 4

  **References**:

  **Pattern References**:
  - `/mnt/d/Rutgers/CT_MPS/CT/src/CT.jl:147-173` - `apply_op!()` MPS contraction algorithm
  - `/mnt/d/Rutgers/CT_MPS/CT/src/CT.jl:363-414` - Staircase pointer movement in `random_control!`

  **API References**:
  - ITensorMPS `apply(op, mps; cutoff, maxdim)` - DO NOT USE (see Contract 3.5 - use custom apply_op_internal!)

  **Acceptance Criteria**:
  - [ ] `apply!(state, PauliX(), SingleSite(1))` modifies state.mps correctly (NO normalize per Contract 3.5)
  - [ ] `apply!(state, HaarRandom(), AdjacentPair(1))` applies to sites (1,2) (NO normalize per Contract 3.5)
  - [ ] `apply!(state, Projection(0), SingleSite(1))` normalizes MPS (per Contract 3.5)
  - [ ] Staircase geometry tracks position internally
  - [ ] After apply with StaircaseRight, internal pointer moved right
  - [ ] `current_position(staircase)` returns pointer value (per Contract 2.2)
  - [ ] `support(HaarRandom())` returns 2; `support(PauliX())` returns 1 (per Contract 2.1)
  - [ ] Support mismatch throws `ArgumentError` (per Contract 2.1)

  **Manual Verification** (use Contract 6 loading - independent of Task 6):
  ```julia
  cd("/mnt/d/Rutgers/QuantumCircuitsMPS.jl")
  include("src/v2/QuantumCircuitsMPSv2.jl")
  using .QuantumCircuitsMPSv2
  using ITensors, ITensorMPS
  
  state = SimulationState(L=4, bc=:periodic)  # L=4 for PBC testing
  initialize!(state, ProductState(x0=0))  # |0000⟩ (all zeros, MSB ordering)
  
  # Verify using ITensorMPS expect() - Sz expectation value (per Contract 3.7)
  # For |0⟩: Sz = +0.5 (spin up), For |1⟩: Sz = -0.5 (spin down)
  ram_site1 = state.phy_ram[1]  # RAM index for physical site 1
  
  # Before X: site 1 should have Sz = +0.5 (it's in |0⟩ state)
  sz_before = expect(state.mps, "Sz")[ram_site1]  # Canonical pattern per Contract 3.7
  @assert abs(sz_before - 0.5) < 1e-10 "Before X: Sz should be +0.5 (|0⟩)"
  
  # Apply X to site 1: |0000⟩ → |1000⟩
  apply!(state, PauliX(), SingleSite(1))
  
  # After X: site 1 should have Sz = -0.5 (now in |1⟩ state)
  sz_after = expect(state.mps, "Sz")[ram_site1]  # Canonical pattern per Contract 3.7
  @assert abs(sz_after + 0.5) < 1e-10 "After X: Sz should be -0.5 (|1⟩)"
  
  # Test Staircase pointer API (Contract 2.2)
  staircase = StaircaseRight(1)  # Start at position 1
  @assert current_position(staircase) == 1 "Initial pointer should be 1"
  
  state3 = SimulationState(L=4, bc=:periodic, rng=RNGRegistry(ctrl=1, proj=2, haar=3, born=4))
  initialize!(state3, ProductState(x0=0))
  
  apply!(state3, HaarRandom(), staircase)  # Apply at (1,2), then pointer moves right
  @assert current_position(staircase) == 2 "After apply, pointer should be 2"
  
  # Test support validation (Contract 2.1)
  try
      apply!(state3, HaarRandom(), AllSites())  # 2-qubit gate on 1-site geometry
      @assert false "Should have thrown ArgumentError"
  catch e
      @assert e isa ArgumentError "Should be ArgumentError"
  end
  
  println("apply! with Staircase and support: PASS")
  ```

  **Commit**: YES
  - Message: `feat(geometry): add geometry types and apply! engine`
  - Files: `src/v2/Geometry/Geometry.jl`, `src/v2/Geometry/static.jl`, `src/v2/Geometry/staircase.jl`, `src/v2/Core/apply.jl`

---

### Task 6: Observable System

- [ ] 6. Create observable tracking system

  **What to do**:
  - Create `src/v2/Observables/Observables.jl` with `AbstractObservable`
  - Implement: `DomainWall(order)`, `BornProbability`
  - **MagnetizationZ is OUT OF SCOPE** - use ITensorMPS `expect(mps, "Sz")` directly if needed
  - Create `track!(state, :name => Observable)` to register observables
  - Create `record!(state; i1=nothing)` to compute and store all registered observables
  - Domain wall must match CT.jl `dw()` function exactly
  
  **CRITICAL: DomainWall i1 Parameter Semantics**:
  
  The `i1` parameter for DomainWall is the **CT sampling site**, NOT the raw pointer value.
  
  From CT.jl's usage (`run_CT_MPS_C_m_T.jl:44`):
  ```julia
  i = CT.random_control!(ct, i, p_ctrl, p_proj)  # i = returned pointer
  dw_list[idx+1,:] = collect(CT.dw(ct, (i % ct.L) + 1))  # DW at (i%L)+1
  ```
  
  **i1 computation rule**: `i1 = (returned_pointer % L) + 1`
  
  | Returned Pointer | L | i1 (sampling site) |
  |-----------------|---|-------------------|
  | 9 | 10 | (9%10)+1 = 10 |
  | 10 | 10 | (10%10)+1 = 1 |
  | 1 | 10 | (1%10)+1 = 2 |
  
  **API Semantics**:
  - `DomainWall(order=1)(state, i1)` - `i1` is the CT sampling site (already computed)
  - `record!(state; i1=i1)` - same: pass the CT sampling site
  - The caller (Task 8's CT example) computes `i1 = (pointer % L) + 1` before calling
  
  **If i1 not provided**: ERROR with message "DomainWall requires i1 parameter (the CT sampling site)"
  
  **DomainWall Scope (MVP)**:
  - **ONLY for `xj=Set([0])` case** (the CT model target)
  - CT.jl's `dw()` function (lines 749-765) has `xj` parameter, but we only implement the `xj=Set([0])` branch
  - Other `xj` values (like `Set([1/3, 2/3])`) require `adder_MPO` which is explicitly out of scope
  - If user needs other `xj`, they must extend `AbstractObservable` themselves
  
  **API clarification**:
  - `DomainWall(order=1)` creates an observable SPEC (no state/position yet)
  - `DomainWall(order=1)(state, i1)` computes DW immediately and returns scalar (direct call)
  - `track!(state, :dw1 => DomainWall(order=1))` registers for batch recording
  - `record!(state; i1=3)` computes ALL tracked observables at position i1, appends to `state.observables`
  - `born_probability(state, site, outcome)` is the canonical function API (convenience)
  - `BornProbability(site, outcome)(state)` is equivalent (callable struct style)
  
  ---
  
  ### Contract 6.1: Physical-to-RAM Mapping in Observables (CRITICAL for PBC)
  
  **ALL observables operate on PHYSICAL site indices (user-facing) but must internally convert to RAM indices for MPS operations.**
  
  **Mapping Rule (same as CT.jl's `inner_prob`, line 477):**
  ```julia
  # Physical site → RAM index
  ram_idx = state.phy_ram[physical_site]
  ```
  
  **BornProbability Implementation:**
  ```julia
  function born_probability(state::SimulationState, physical_site::Int, outcome::Int)
      # Convert physical site to RAM index for MPS access
      ram_idx = state.phy_ram[physical_site]
      
      # Build projector for the RAM site
      proj_op = outcome == 0 ? "Proj0" : "Proj1"
      
      # Use ITensorMPS expect() indexed at RAM position
      # NOTE: expect() returns Vector for all sites, index by RAM position
      all_probs = expect(state.mps, proj_op)
      return real(all_probs[ram_idx])
  end
  ```
  
  **DomainWall Implementation (xj=Set([0]) case - port CT.jl dw_FM verbatim):**
  
  **Option A: Port CT.jl's `dw_FM` function directly** (RECOMMENDED):
  ```julia
  # From CT.jl lines 688-720 - dw_FM builds MPO directly without OpSum
  # This is the EXACT algorithm to replicate for CT.jl match
  
  function domain_wall(state::SimulationState, i1::Int, order::Int)
      L = state.L
      
      # Port CT.jl's dw_FM directly:
      # Creates projector product operators for each j ∈ 1:L
      # Weight (L-j+1)^order for first "1" found at position j
      
      # See CT.jl dw_FM() for exact ITensor construction
      # Key: Use ITensor's op() to build individual projectors, 
      # then contract into single tensor for each term
      
      # For implementation details, reference:
      # /mnt/d/Rutgers/CT_MPS/CT/src/CT.jl:688-720 (dw_FM function)
      # /mnt/d/Rutgers/CT_MPS/CT/src/CT.jl:740-747 (dw function calling dw_FM)
  end
  ```
  
  **Option B: Use OpSum with correct syntax**:
  ```julia
  function domain_wall(state::SimulationState, i1::Int, order::Int)
      L = state.L
      phy_list = collect(1:L)
      
      dw_ops = OpSum()
      for j in 1:L
          # i_list: physical sites from i1 to i1+j-1 (wrapped)
          i_list = phy_list[mod.(collect(1:j) .+ (i1-1) .- 1, L) .+ 1]
          weight = Float64((L - j + 1)^order)
          
          # Convert physical sites to RAM indices
          ram_sites = [state.phy_ram[i] for i in i_list]
          
          # OpSum syntax: add each operator with its site index
          # For j=1: just "Proj1" at first site
          # For j>1: "Proj0" at sites 1..j-1, then "Proj1" at site j
          
          if j == 1
              dw_ops += (weight, "Proj1", ram_sites[1])
          else
              # Build term: (weight, "Proj0", ram_sites[1], "Proj0", ram_sites[2], ..., "Proj1", ram_sites[end])
              # OpSum requires flat argument list
              term_args = Any[weight]
              for k in 1:j-1
                  push!(term_args, "Proj0")
                  push!(term_args, ram_sites[k])
              end
              push!(term_args, "Proj1")
              push!(term_args, ram_sites[end])
              dw_ops += tuple(term_args...)
          end
      end
      
      dw_mpo = MPO(dw_ops, state.sites)
      return real(inner(state.mps', dw_mpo, state.mps))
  end
  ```
  
  **IMPLEMENTATION NOTE**: Option A (porting CT.jl's dw_FM) is recommended because:
  1. It's proven to work with CT.jl
  2. OpSum syntax can be tricky with variable-length operator products
  3. Direct ITensor construction matches what CT.jl does
  
  **Reference for exact CT.jl algorithm**: `/mnt/d/Rutgers/CT_MPS/CT/src/CT.jl:688-720`
  
  **Key Insight:** The `state.phy_ram` mapping is used **inside** observable implementations to convert physical site indices to RAM positions. Users always specify physical sites.
  
  **Verification Test (PBC folded mapping):**
  ```julia
  # For L=4 PBC: ram_phy = [1,4,2,3], phy_ram = [1,3,4,2]
  # Physical site 1 → RAM 1, Physical site 2 → RAM 3, etc.
  
  state = SimulationState(L=4, bc=:periodic)
  initialize!(state, ProductState(x0=1//16))  # |0001⟩ = site 4 has "1"
  
  # Site 4 (physical) → RAM 2 (because phy_ram[4]=2)
  # Born probability at physical site 4, outcome 1 should be 1.0
  p = born_probability(state, 4, 1)
  @assert abs(p - 1.0) < 1e-10 "P(physical_site_4 = 1) should be 1.0"
  
  # DomainWall at i1=1 for |0001⟩ should give specific value
  # (verify against CT.jl reference)
  ```
  
  ---

  **Must NOT do**:
  - Do NOT implement entanglement entropy yet (not in MVP target)
  - Do NOT add TCI-based observables

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
    - Reason: Domain wall MPO construction is non-trivial
  - **Skills**: []
    - ITensor MPO construction knowledge

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 2 (with Tasks 3, 4)
  - **Blocks**: Task 8
  - **Blocked By**: Task 1

  **References**:

  **Pattern References**:
  - `/mnt/d/Rutgers/CT_MPS/CT/src/CT.jl:740-765` - `dw()` and `dw_MPO()` implementations
  - `/mnt/d/Rutgers/CT_MPS/CT/src/CT.jl:475-490` - `inner_prob()` Born probability

  **Acceptance Criteria**:
  - [ ] `DomainWall(order=1)(state, i1)` returns correct scalar (direct call)
  - [ ] `born_probability(state, site, 0)` returns ⟨ψ|P_0|ψ⟩ (canonical function API)
  - [ ] `BornProbability(site, 0)(state)` returns same as `born_probability` (callable struct wrapper)
  - [ ] `track!(state, :dw1 => DomainWall(1))` registers observable
  - [ ] `record!(state; i1=1)` appends values to `state.observables[:dw1]` (requires i1 for DomainWall)

  **Manual Verification** (use Contract 6 loading):
  ```julia
  cd("/mnt/d/Rutgers/QuantumCircuitsMPS.jl")
  include("src/v2/QuantumCircuitsMPSv2.jl")
  using .QuantumCircuitsMPSv2
  using ITensors, ITensorMPS
  
  state = SimulationState(L=4, bc=:periodic)
  initialize!(state, ProductState(x0=1//16))
  track!(state, :dw1 => DomainWall(order=1))
  
  # record! requires i1 for DomainWall
  record!(state; i1=1)
  @assert haskey(state.observables, :dw1)
  @assert length(state.observables[:dw1]) == 1
  
  # Test both API styles for BornProbability
  p1 = born_probability(state, 1, 0)  # canonical function
  p2 = BornProbability(1, 0)(state)   # callable struct
  @assert abs(p1 - p2) < 1e-10 "Both APIs should return same value"
  
  println("Observable tracking: PASS")
  ```

  **Commit**: YES
  - Message: `feat(observables): add DomainWall, BornProbability with auto-tracking`
  - Files: `src/v2/Observables/Observables.jl`, `src/v2/Observables/domain_wall.jl`, `src/v2/Observables/born.jl`

---

### Task 7: API Wrappers (Multiple Styles)

- [ ] 7. Create multiple API style wrappers

  **What to do**:
  - Create `src/v2/API/imperative.jl`: Direct `apply!(state, gate, geometry)` (already done in Task 5)
  - Create `src/v2/API/functional.jl`: `simulate(...)` wrapper (see Contract 4.3 below)
  - Create `src/v2/API/context.jl`: `with_state(fn, state)` and `current_state()` for implicit access
  - Create `rand(state, :stream)` convenience that delegates to RNGRegistry
  - Create probabilistic helpers: `apply_with_prob!(state, gate, geo, prob; rng::Symbol)` where `rng` is a stream key (e.g., `:ctrl`, `:proj`) to look up in `state.rng_registry`

  ---

  ### Contract 4.3: simulate(...) / Circuit Contract (Momus Blocker #5 Resolution)

  **Problem**: Task 7 says `simulate(L, bc, circuit, steps, observables)` but doesn't define what `circuit` is.

  **Resolution**: `circuit` is a **callable** (function or callable struct) that takes `(state, t)` and mutates state.

  **simulate() Signature:**
  ```julia
  function simulate(;
      L::Int,
      bc::Symbol,
      init::AbstractInitialState,
      circuit!::Function,           # f(state, t) -> Nothing, mutates state
      steps::Int,
      observables::Vector{Pair{Symbol,AbstractObservable}},
      rng::RNGRegistry,
      record_at::Symbol = :every,   # :every | :final | :custom
      record_fn::Union{Function,Nothing} = nothing  # for :custom
  ) -> Dict{Symbol, Vector}
  ```

  **Circuit Calling Convention:**
  ```julia
  # circuit! is called as: circuit!(state, t) for t in 1:steps
  # It should mutate state in place and return nothing
  # The `t` parameter is the current timestep (1-indexed)

  # Example circuit function:
  function my_circuit!(state, t)
      apply!(state, HaarRandom(), AdjacentPair(t % state.L + 1))
      apply!(state, Projection(0), SingleSite(1))
  end
  ```

  **record_at Options:**
  - `:every` - `record!(state; ...)` called after every timestep (default)
  - `:final` - `record!(state; ...)` called only after last timestep
  - `:custom` - `record_fn(state, t)` called; user decides when to record

  **Return Value:**
  ```julia
  # Returns Dict with observable names as keys, Vector of values as values
  # Shape of each Vector depends on record_at:
  #   :every -> length = steps + 1 (includes t=0)
  #   :final -> length = 1
  #   :custom -> length = depends on record_fn

  Dict{Symbol, Vector}(
      :dw1 => [1.0, 0.95, 0.92, ...],  # length depends on record_at
      :dw2 => [1.0, 0.90, 0.85, ...],
  )
  ```

  **Full simulate() Implementation Spec:**
  ```julia
  function simulate(;
      L::Int,
      bc::Symbol,
      init::AbstractInitialState,
      circuit!::Function,
      steps::Int,
      observables::Vector{Pair{Symbol,AbstractObservable}},
      rng::RNGRegistry,
      record_at::Symbol = :every,
      record_fn::Union{Function,Nothing} = nothing,
      i1_fn::Union{Function,Nothing} = nothing  # f(state, t) -> Int for DomainWall
  )
      # 1. Create and initialize state
      state = SimulationState(L=L, bc=bc, rng=rng)
      initialize!(state, init)
      
      # 2. Register observables
      for (name, obs) in observables
          track!(state, name => obs)
      end
      
      # 3. Initial recording (t=0) if :every
      if record_at == :every
          i1 = i1_fn !== nothing ? i1_fn(state, 0) : 1
          record!(state; i1=i1)
      end
      
      # 4. Main simulation loop
      for t in 1:steps
          circuit!(state, t)
          
          if record_at == :every
              i1 = i1_fn !== nothing ? i1_fn(state, t) : 1
              record!(state; i1=i1)
          elseif record_at == :custom && record_fn !== nothing
              record_fn(state, t)
          end
      end
      
      # 5. Final recording if :final
      if record_at == :final
          i1 = i1_fn !== nothing ? i1_fn(state, steps) : 1
          record!(state; i1=i1)
      end
      
      # 6. Return observables dict
      return state.observables
  end
  ```

  **Why No Circuit Struct:**
  - A function `circuit!(state, t)` is maximally flexible
  - User can close over any variables they need (p_ctrl, staircase geometry, etc.)
  - No need to learn a circuit DSL
  - Easy to debug (just a Julia function)
  - Task 8's CT example will show how to structure complex circuits as functions

  **Task 8 Example Usage:**
  ```julia
  # In examples/ct_model.jl
  function ct_circuit!(state, t)
      # ... CT.jl random_control! logic using state and closures
  end

  results = simulate(
      L = 10,
      bc = :periodic,
      init = ProductState(x0=1//1024),
      circuit! = ct_circuit!,
      steps = 200,
      observables = [:dw1 => DomainWall(1), :dw2 => DomainWall(2)],
      rng = RNGRegistry(ctrl=42, proj=43, haar=44, born=123),
      i1_fn = (state, t) -> (current_position(staircase) % L) + 1
  )
  ```

  ---

  ### Contract 4.4: apply_with_prob! Probabilistic Gate Helper (Momus Round 13 Fix, Round 17 Clarified)

  **Problem**: Need a helper to apply gates probabilistically.

  **Resolution**: `rng` is a **Symbol key** (e.g., `:ctrl`, `:proj`) used to look up the stream in `state.rng_registry`.

  **TWO MODES with different RNG consumption semantics:**

  **Mode 1: Normal Mode (default)** - Always draws RNG:
  ```julia
  function apply_with_prob!(
      state::SimulationState,
      gate::AbstractGate,
      geo::AbstractGeometry,
      prob::Float64;
      rng::Symbol = :ctrl  # Stream key, NOT RNGRegistry
  )
      # Get the actual RNG from state's registry
      actual_rng = get_rng(state.rng_registry, rng)
      
      # ALWAYS draw random number (ensures deterministic RNG advancement)
      r = rand(actual_rng)
      
      # Conditionally apply based on drawn value
      if r < prob
          apply!(state, gate, geo)
      end
      return nothing
  end
  ```

  **Mode 2: CT-Compat Mode** - Short-circuits when prob=0.0 to match patched CT.jl:
  
  For **Task 8 CT verification ONLY**, when using `RNGRegistry(Val(:ct_compat), ...)` and `p_proj=0.0`:
  
  ```julia
  # Task 8 does NOT use apply_with_prob! for projection decisions when p_proj=0.0
  # Instead, it uses explicit CT.jl-matching logic:
  
  # CT.jl pattern (after patch): if p_proj > 0 && rand(ct.rng_C) < p_proj
  # Our matching code in Task 8 (NOT apply_with_prob!):
  if p_proj > 0.0
      if rand(get_rng(state.rng_registry, :proj)) < p_proj
          apply!(state, Projection(outcome), SingleSite(site))
      end
  end
  # When p_proj=0.0, NO RNG draw occurs - matching patched CT.jl
  ```

  **Why Two Approaches:**
  - `apply_with_prob!` is the **general-purpose API** for users - always draws for determinism
  - **Task 8 uses explicit logic** for CT verification - matches CT.jl's short-circuit behavior
  - This avoids complicating `apply_with_prob!` with special modes

  **RNG Draw Verification Acceptance Criterion (Normal Mode):**
  ```julia
  # To prove apply_with_prob! draws from the correct stream:
  rng_reg = RNGRegistry(ctrl=1, proj=2, haar=3, born=4)
  state = SimulationState(L=4, bc=:open, rng=rng_reg)
  initialize!(state, ProductState(x0=0))
  
  # Get expected value from clean RNG with same seed
  test_rng = MersenneTwister(1)  # same seed as :ctrl
  expected_draw = rand(test_rng)
  
  # Call apply_with_prob! with prob=0.0 - draws but never applies
  apply_with_prob!(state, PauliX(), SingleSite(1), 0.0; rng=:ctrl)
  
  # Now state's :ctrl RNG should have advanced by 1 call
  next_expected = rand(test_rng)  # second draw from test_rng
  next_actual = rand(get_rng(state.rng_registry, :ctrl))
  @assert next_expected == next_actual "apply_with_prob! must draw from :ctrl stream"
  ```

  **Critical Implementation Note:**
  - In **normal mode**: `rand(actual_rng)` MUST be called BEFORE checking `prob`
  - In **CT-compat (Task 8)**: Use explicit `if p_proj > 0.0 && ...` pattern, NOT `apply_with_prob!`

  ---

  **Must NOT do**:
  - Do NOT create macro DSL (out of scope)
  - Do NOT implement Circuit struct (can add later)

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Thin wrappers over existing functionality
  - **Skills**: []
    - Basic API design

  **Parallelization**:
  - **Can Run In Parallel**: NO (depends on Task 5)
  - **Parallel Group**: Wave 4 (after Task 5 completes)
  - **Blocks**: Task 8
  - **Blocked By**: Tasks 3, 5

  **References**:

  **API Style Patterns** (for reference during implementation):
  
  **Style A1 (OO Explicit)** - RECOMMENDED, used by this package:
  ```julia
  state = SimulationState(L=10, bc=:periodic, rng=RNGRegistry(ctrl=1, proj=2, haar=3, born=4))
  initialize!(state, ProductState(x0=0))
  apply!(state, HaarRandom(), Bricklayer(:odd))
  apply!(state, Projection(0), SingleSite(1))
  ```
  
  **Style B (Functional)** - simulate() wrapper:
  ```julia
  results = simulate(
      L=10, bc=:periodic,
      init=ProductState(x0=0),
      circuit!=(state, t) -> apply!(state, HaarRandom(), Bricklayer(:odd)),
      steps=100,
      observables=[:dw => DomainWall(1)],
      rng=RNGRegistry(ctrl=1, proj=2, haar=3, born=4)
  )
  ```

  **Acceptance Criteria**:
  - [ ] `apply!(state, gate, geo)` works (imperative)
  - [ ] `simulate(L=4, bc=:open, init=..., circuit!=..., steps=..., ...)` returns results dict (functional, per Contract 4.3)
  - [ ] `with_state(state) do; apply!(gate, geo); end` works (context)
  - [ ] `apply_with_prob!(state, gate, geo, 0.5; rng=:ctrl)` applies probabilistically (per Contract 4.4)
  - [ ] `apply_with_prob!` draws from correct RNG stream (verified per Contract 4.4 acceptance test)
  - [ ] `rand(state, :ctrl)` returns Float64 (high-level convenience)
  - [ ] `get_rng(state.rng_registry, :ctrl)` returns AbstractRNG (low-level access)

  **Manual Verification** (use Contract 6 loading):
  ```julia
  cd("/mnt/d/Rutgers/QuantumCircuitsMPS.jl")
  include("src/v2/QuantumCircuitsMPSv2.jl")
  using .QuantumCircuitsMPSv2
  using ITensors, ITensorMPS
  
  # First initialize a state (requires Task 1, 4 complete)
  state = SimulationState(L=4, bc=:periodic, rng=RNGRegistry(ctrl=1, proj=2, haar=3, born=4))
  initialize!(state, ProductState(x0=0))
  
  # Imperative
  apply!(state, PauliX(), SingleSite(1))
  
  # Context
  with_state(state) do
      apply!(PauliZ(), SingleSite(2))  # uses current_state() implicitly
  end
  
  # Probabilistic (uses state.rng_registry internally)
  apply_with_prob!(state, PauliX(), SingleSite(3), 1.0; rng=:ctrl)  # always applies
  
  # Test simulate() with trivial circuit (Contract 4.3)
  results = simulate(
      L = 4,
      bc = :periodic,
      init = ProductState(x0=0),
      circuit! = (state, t) -> apply!(state, PauliX(), SingleSite(1)),  # trivial circuit
      steps = 2,
      observables = [],  # no observables for this test
      rng = RNGRegistry(ctrl=1, proj=2, haar=3, born=4)
  )
  @assert results isa Dict "simulate should return Dict"
  
  println("API wrappers: PASS")
  ```

  **Commit**: YES
  - Message: `feat(api): add multiple API styles (imperative, functional, context)`
  - Files: `src/v2/API/imperative.jl`, `src/v2/API/functional.jl`, `src/v2/API/context.jl`

---

### Task 8: CT Model Example

- [x] 8. Create examples/ct_model.jl reproducing run_CT_MPS_C_m_T.jl

  **PREREQUISITE: JSON package required**
  ```bash
  # Run BEFORE Task 8 if JSON not in Project.toml
  cd /mnt/d/Rutgers/QuantumCircuitsMPS.jl
  julia --project=. -e 'using Pkg; Pkg.add("JSON")'
  ```

  **What to do**:
  - Create `examples/ct_model.jl` that implements random_control! using package primitives
  - **CRITICAL FOR VERIFICATION**: Use CT-compat RNG mode (per Contract 3.0.1):
    ```julia
    rng = RNGRegistry(Val(:ct_compat), circuit=seed_C, measurement=seed_m)
    ```
    This ensures :ctrl and :haar share the same underlying RNG, matching CT.jl's interleaved consumption.
  - Must use EXACT RNG call order as CT.jl for reproducibility
  - Implement `run_dw_t(L, p_ctrl, p_proj, seed_C, seed_m)` function
  - **Output contract**:
    - Write JSON to: `examples/output/ct_model_L{L}_sC{seed_C}_sm{seed_m}.json`
    - JSON schema: `{"L": Int, "p_ctrl": Float, "p_proj": Float, "seed_C": Int, "seed_m": Int, "DW1": [Float...], "DW2": [Float...]}`
    - DW1/DW2 arrays have length `2*L^2 + 1` (201 for L=10)
  - Show all three API styles (can comment out alternatives)

  **CRITICAL: DomainWall Sampling Index Contract** (from `/mnt/d/Rutgers/CT_MPS/run_CT_MPS_C_m_T.jl:42-44`):
  
  CT.jl computes DW at `(i % L) + 1` where `i` is the pointer AFTER `random_control!` returns:
  ```julia
  # CT.jl pattern:
  for idx in 1:tf
      i = CT.random_control!(ct, i, p_ctrl, p_proj)  # i is UPDATED pointer
      dw_list[idx+1,:] = collect(CT.dw(ct, (i % L) + 1))  # DW at (i%L)+1
  end
  ```
  
  **Step-by-step example for one iteration** (starting i=10, L=10, control branch):
  | Step | Action | Pointer Before | Pointer After | Notes |
  |------|--------|----------------|---------------|-------|
  | 1 | rand(:ctrl) < p_ctrl? YES | i=10 | i=10 | Control branch selected |
  | 2 | Born prob at site i=10 | i=10 | i=10 | No pointer change |
  | 3 | rand(:born) → outcome | i=10 | i=10 | Outcome determined |
  | 4 | Apply P!(outcome), maybe X! | i=10 | i=10 | Reset complete |
  | 5 | Move LEFT: i = mod(i-2,L)+1 | i=10 | i=9 | **Pointer updated to 9** |
  | 6 | random_control! returns i=9 | - | i=9 | Returned value |
  | 7 | Compute DW at (9%10)+1 = 10 | - | - | **DW sampled at site 10** |
  
  **Step-by-step example for one iteration** (starting i=10, L=10, Bernoulli branch):
  | Step | Action | Pointer Before | Pointer After | Notes |
  |------|--------|----------------|---------------|-------|
  | 1 | rand(:ctrl) < p_ctrl? NO | i=10 | i=10 | Bernoulli branch |
  | 2 | Apply HaarRandom to (i,i+1) | i=10 | i=10 | Sites (10,1) for PBC |
  | 3 | Move RIGHT: i = mod(i,L)+1 | i=10 | i=1 | **Pointer updated to 1** |
  | 4 | Maybe proj at site (i-1)=10 (rand(:proj)) | i=1 | i=1 | After move |
  | 5 | Maybe proj at site i=1 (rand(:proj)) | i=1 | i=1 | After move |
  | 6 | random_control! returns i=1 | - | i=1 | Returned value |
  | 7 | Compute DW at (1%10)+1 = 2 | - | - | **DW sampled at site 2** |
  
  **Key Insight**: DW is sampled at the site AHEAD of the returned pointer (circular), not at the pointer itself.

  **Must NOT do**:
  - Do NOT hardcode into package (this is example, not library code)
  - Do NOT deviate from CT.jl RNG call sequence

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
    - Reason: Critical correctness requirement, must match CT.jl exactly
  - **Skills**: []
    - Deep understanding of both CT.jl and new package

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Sequential after Wave 3
  - **Blocks**: Task 9
  - **Blocked By**: Tasks 3, 4, 5, 6, 7

  **References**:

  **Pattern References**:
  - `/mnt/d/Rutgers/CT_MPS/run_CT_MPS_C_m_T.jl:26-57` - EXACT function to reproduce
  - `/mnt/d/Rutgers/CT_MPS/CT/src/CT.jl:363-414` - EXACT RNG call order in `random_control!`

  **Acceptance Criteria**:
  - [ ] `run_dw_t(10, 0.5, 0.0, 42, 123)` runs without error
  - [ ] Output file `examples/output/ct_model_L10_sC42_sm123.json` created
  - [ ] JSON contains keys: `L`, `p_ctrl`, `p_proj`, `seed_C`, `seed_m`, `DW1`, `DW2`
  - [ ] DW1/DW2 arrays have length 201
  - [ ] Results match CT.jl within 1e-10 (verified in Task 9)

  **Manual Verification**:
  ```bash
  cd /mnt/d/Rutgers/QuantumCircuitsMPS.jl
  mkdir -p examples/output
  julia --project=. examples/ct_model.jl --L 10 --p_ctrl 0.5 --p_proj 0.0 --seed_C 42 --seed_m 123
  # Should produce: examples/output/ct_model_L10_sC42_sm123.json
  cat examples/output/ct_model_L10_sC42_sm123.json | jq '.DW1 | length'
  # Expected: 201
  ```

  **Commit**: YES
  - Message: `feat(examples): add CT model example reproducing run_CT_MPS_C_m_T.jl`
  - Files: `examples/ct_model.jl`

---

### Task 9: Verification & Cleanup

- [ ] 9. Verify physics match and clean up

  **What to do**:
  - Create `test/verify_ct_match.jl` that compares new output to CT.jl reference
  - Load reference data from `test/reference/ct_reference_L10.json` (Task 10)
  - Load new output from `examples/output/ct_model_L10_sC42_sm123.json` (Task 8)
  - Assert maximum absolute difference < 1e-10
  - Clean up any temporary files
  - After verification passes: Move v2 code to main namespace per Contract 1 (detailed below)

  **Phase 2: Code Replacement Steps** (ONLY after verification PASSES):
  
  **Current Repository Layout (verified):**
  ```
  src/
  ├── QuantumCircuitsMPS.jl  (module entry - will be REPLACED)
  ├── Core/
  │   ├── Core.jl
  │   ├── types.jl
  │   └── context.jl
  ├── Gates/
  │   └── Gates.jl
  ├── Measurements/
  │   └── Measurements.jl
  ├── Observables/
  │   └── Observables.jl
  └── Patterns/
      └── Patterns.jl
  ```

  **Final Repository Layout (after Task 9):**
  ```
  src/
  ├── QuantumCircuitsMPS.jl  (NEW module entry from v2)
  ├── Core/                   (from v2/Core/)
  │   ├── rng.jl
  │   ├── basis.jl
  │   └── apply.jl
  ├── State/                  (from v2/State/)
  │   ├── State.jl
  │   └── initialization.jl
  ├── Gates/                  (REPLACED from v2/Gates/)
  │   └── Gates.jl
  ├── Geometry/               (from v2/Geometry/)
  │   └── Geometry.jl
  ├── Observables/            (REPLACED from v2/Observables/)
  │   └── Observables.jl
  ├── API/                    (from v2/API/)
  │   ├── imperative.jl
  │   ├── functional.jl
  │   └── context.jl
  └── _deprecated/            (archived old code)
      ├── Core/
      ├── Gates/
      ├── Measurements/
      ├── Observables/
      ├── Patterns/
      └── QuantumCircuitsMPS.jl.bak
  ```

  1. **Archive old code** (preserves existing directories):
     ```bash
     mkdir -p src/_deprecated
     # Move existing directories (NOT the module entry yet)
     mv src/Core src/_deprecated/
     mv src/Gates src/_deprecated/
     mv src/Measurements src/_deprecated/
     mv src/Observables src/_deprecated/
     mv src/Patterns src/_deprecated/
     # Backup the old module entry
     cp src/QuantumCircuitsMPS.jl src/_deprecated/QuantumCircuitsMPS.jl.bak
     ```
  
  2. **Move v2 code to src/** (replaces archived directories):
     ```bash
     # Move v2 subdirectories to src/
     mv src/v2/Core src/
     mv src/v2/State src/
     mv src/v2/Gates src/
     mv src/v2/Geometry src/
     mv src/v2/Observables src/
     mv src/v2/API src/
     # Remove now-empty v2 directory
     rm -r src/v2
     ```
  
  3. **REPLACE src/QuantumCircuitsMPS.jl** with new module entry:
     
     **Option A: Overwrite directly** (recommended):
     ```bash
     # The new module content is written directly to src/QuantumCircuitsMPS.jl
     # (replaces the old content completely)
     ```
     
     **New module content:**
     ```julia
     module QuantumCircuitsMPS
     
     using ITensors
     using ITensorMPS
     using Random
     using LinearAlgebra
     
     # Core
     include("Core/rng.jl")
     include("Core/basis.jl")
     include("Core/apply.jl")
     
     # State
     include("State/State.jl")
     include("State/initialization.jl")
     
     # Gates
     include("Gates/Gates.jl")
     
     # Geometry
     include("Geometry/Geometry.jl")
     
     # Observables
     include("Observables/Observables.jl")
     
     # API
     include("API/imperative.jl")
     include("API/functional.jl")
     include("API/context.jl")
     
     # === PUBLIC API EXPORTS ===
     # State
     export SimulationState, initialize!, ProductState, RandomMPS
     # RNG
     export RNGRegistry, get_rng  # NOTE: rand is extended, not exported
     # Gates
     export AbstractGate, PauliX, PauliY, PauliZ, Projection, HaarRandom, Reset
     # Geometry
     export AbstractGeometry, SingleSite, AdjacentPair, Bricklayer, AllSites
     export StaircaseLeft, StaircaseRight
     # Observables
     export AbstractObservable, DomainWall, BornProbability
     export track!, record!
     # API
     export apply!, simulate, with_state, current_state, apply_with_prob!
     
     # === INTERNAL EXPORTS (for CT.jl parity/debugging) ===
     # These are exported for testing/verification but not public API
     export advance!, get_sites, current_position  # Geometry internals
     export apply_op_internal!, apply_post!        # Apply internals  
     export born_probability                       # Observable internals
     
     end # module
     ```
  
  **Post-Move Verification Checklist:**
  - [ ] `using Pkg; Pkg.activate("."); using QuantumCircuitsMPS` loads without error
  - [ ] `names(QuantumCircuitsMPS)` shows expected exports
  - [ ] No stale includes of old submodules (grep for "Measurements", "Patterns" - should find nothing)
  - [ ] `src/_deprecated/` contains archived code
  - [ ] `src/v2/` directory no longer exists
  
  4. **Verify module loads**:
     ```julia
     cd("/mnt/d/Rutgers/QuantumCircuitsMPS.jl")
     using Pkg; Pkg.activate(".")
     using QuantumCircuitsMPS
     # Should load without errors
     ```

  **Must NOT do**:
  - Do NOT delete old code until verification passes
  - Do NOT modify algorithms if verification fails (debug instead)
  - Do NOT perform Phase 2 if verification fails

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Comparison script, straightforward
  - **Skills**: []
    - Basic testing

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Final (after all other tasks)
  - **Blocks**: None (final task)
  - **Blocked By**: Tasks 8, 10

  **References**:

  **Pattern References**:
  - Reference data from Task 10

  **Acceptance Criteria**:
  - [ ] `julia test/verify_ct_match.jl` outputs "PASS"
  - [ ] `maximum(abs.(new_dw1 .- ref_dw1)) < 1e-10`
  - [ ] `maximum(abs.(new_dw2 .- ref_dw2)) < 1e-10`
  - [ ] After Phase 2: `using QuantumCircuitsMPS` loads without errors

  **Manual Verification**:
  ```bash
  cd /mnt/d/Rutgers/QuantumCircuitsMPS.jl
  julia --project=. test/verify_ct_match.jl
  # Expected output:
  # DW1 max diff: X.XXe-XX
  # DW2 max diff: X.XXe-XX
  # VERIFICATION: PASS
  ```

  **Commit**: YES (two commits)
  - Message 1: `test: add CT.jl physics verification`
  - Files 1: `test/verify_ct_match.jl`
  - Message 2: `refactor: replace old code with verified v2 implementation`
  - Files 2: `src/_deprecated/` (archive), `src/QuantumCircuitsMPS.jl` (updated exports)

---

### Task 10: Generate CT.jl Reference Data

- [ ] 10. Run CT.jl to generate reference data for verification

  **PREREQUISITE: CT_MPS Environment**
  
  This task requires the CT_MPS project to exist and be runnable:
  - **Location**: `/mnt/d/Rutgers/CT_MPS/`
  - **Project file**: `CT/Project.toml` (activated as `--project=CT`)
  - **Entry script**: `run_CT_MPS_C_m_T.jl`
  
  **If CT_MPS is not available:**
  1. Contact the project owner to obtain the CT_MPS codebase
  2. Ensure it's placed at `/mnt/d/Rutgers/CT_MPS/`
  3. Verify dependencies: `julia --project=CT -e 'using Pkg; Pkg.instantiate()'`
  
  **Verification that CT_MPS exists:**
  ```bash
  # Check CT_MPS exists
  test -f /mnt/d/Rutgers/CT_MPS/run_CT_MPS_C_m_T.jl && echo "CT_MPS found" || echo "CT_MPS NOT FOUND"
  test -f /mnt/d/Rutgers/CT_MPS/CT/Project.toml && echo "Project.toml found" || echo "Project.toml NOT FOUND"
  ```

  **What to do**:
  - **IMPORTANT**: Apply temporary patch to CT.jl for RNG compatibility (see Contract 3.0.1)
  - Run `/mnt/d/Rutgers/CT_MPS/run_CT_MPS_C_m_T.jl` with test parameters
  - Parameters: `L=10, p_ctrl=0.5, p_proj=0.0, seed_C=42, seed_m=123`
  - CT.jl script outputs to: `MPS_(0,1)_L10_pctrl0.500_pproj0.000_sC42_sm123_x01_DW_T.json` (per line 95 of script)
  - Copy/rename this file to: `test/reference/ct_reference_L10.json`
  - Create `test/reference/` directory if it doesn't exist
  - **RESTORE CT.jl to original state after generating reference data**

  **CT.jl Patch for Verification** (per Contract 3.0.1):
  
  In `/mnt/d/Rutgers/CT_MPS/CT/src/CT.jl` around line 402, find:
  ```julia
  if rand(ct.rng_C) < p_proj
  ```
  
  Change to:
  ```julia
  if p_proj > 0 && rand(ct.rng_C) < p_proj
  ```
  
  **Why**: When `p_proj=0`, this prevents CT.jl from consuming an RNG value for proj decisions,
  making the consumption pattern match our clean design where `:proj` stream is not consumed.

  **Must NOT do**:
  - Do NOT forget to restore CT.jl after generating reference data
  - Do NOT use different parameters than specified

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Just running existing code
  - **Skills**: []
    - Basic Julia execution

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 1 (with Tasks 1, 2)
  - **Blocks**: Task 9
  - **Blocked By**: None

  **References**:

  **Pattern References**:
  - `/mnt/d/Rutgers/CT_MPS/run_CT_MPS_C_m_T.jl:95` - Output filename format: `"MPS_$(xj)_L$(L)_pctrl$(round(p_ctrl,digits=3))_pproj$(round(p_proj,digits=3))_sC$(seed_C)_sm$(seed_m)_x0$(x0_idx)_DW_T.json"`

  **Acceptance Criteria**:
  - [ ] `test/reference/ct_reference_L10.json` exists
  - [ ] File contains `DW1` and `DW2` arrays
  - [ ] Arrays have length 201 (2*10^2 + 1)
  - [ ] **CT.jl restored to original state** (verify: `diff CT/src/CT.jl CT/src/CT.jl.backup` shows no differences, then delete backup)

  **Manual Verification**:
  ```bash
  # Step 0: BACKUP original CT.jl
  cd /mnt/d/Rutgers/CT_MPS
  cp CT/src/CT.jl CT/src/CT.jl.backup
  
  # Step 1: Apply patch to CT.jl line ~402 (per Contract 3.0.1)
  # Find: if rand(ct.rng_C) < p_proj
  # Replace with: if p_proj > 0 && rand(ct.rng_C) < p_proj
  # (Use your preferred editor)
  
  # Step 2: Create target directory
  mkdir -p /mnt/d/Rutgers/QuantumCircuitsMPS.jl/test/reference
  
  # Step 3: Run CT.jl script
  cd /mnt/d/Rutgers/CT_MPS
  julia --project=CT run_CT_MPS_C_m_T.jl --L 10 --p_ctrl 0.5 --p_proj 0.0 --seed_C 42 --seed_m 123
  
  # Step 4: CT.jl outputs file named (per run_CT_MPS_C_m_T.jl:95):
  # MPS_(0,1)_L10_pctrl0.500_pproj0.000_sC42_sm123_x01_DW_T.json
  
  # Step 5: Copy/rename to test reference location
  cp "MPS_(0,1)_L10_pctrl0.500_pproj0.000_sC42_sm123_x01_DW_T.json" \
     /mnt/d/Rutgers/QuantumCircuitsMPS.jl/test/reference/ct_reference_L10.json
  
  # Step 6: RESTORE original CT.jl (CRITICAL!)
  mv CT/src/CT.jl.backup CT/src/CT.jl
  
  # Step 7: Verify file content
  cat /mnt/d/Rutgers/QuantumCircuitsMPS.jl/test/reference/ct_reference_L10.json | jq '.DW1 | length'
  # Expected: 201
  ```

  **Commit**: YES
  - Message: `test: add CT.jl reference data for verification`
  - Files: `test/reference/ct_reference_L10.json`

---

## Commit Strategy

| After Task | Message | Files | Verification |
|------------|---------|-------|--------------|
| 1 | `feat(state): add SimulationState struct with OBC basis mapping stub` | src/v2/State/*.jl, src/v2/Core/basis.jl | Manual test |
| 2 | `feat(core): add RNGRegistry for reproducible randomness` | src/v2/Core/rng.jl | Manual test |
| 3 | `feat(gates): add gate type hierarchy` | src/v2/Gates/*.jl | Manual test |
| 4 | `feat(core): complete PBC basis mapping` | src/v2/Core/basis.jl | Manual test |
| 5 | `feat(geometry): add geometry types and apply! engine` | src/v2/Geometry/*.jl, src/v2/Core/apply.jl | Manual test |
| 6 | `feat(observables): add DomainWall, BornProbability` | src/v2/Observables/*.jl | Manual test |
| 7 | `feat(api): add multiple API styles` | src/v2/API/*.jl | Manual test |
| 8 | `feat(examples): add CT model example` | examples/ct_model.jl | Run example |
| 9a | `test: add CT.jl physics verification` | test/verify_ct_match.jl | PASS |
| 9b | `refactor: replace old code with verified v2` | src/_deprecated/*, src/QuantumCircuitsMPS.jl | Module loads |
| 10 | `test: add CT.jl reference data` | test/reference/*.json | File exists |

---

## Success Criteria

### Verification Commands
```bash
# Run full verification
cd /mnt/d/Rutgers/QuantumCircuitsMPS.jl
julia --project=. test/verify_ct_match.jl
# Expected: "VERIFICATION: PASS"

# Run CT model example
julia --project=. examples/ct_model.jl --L 10 --p_ctrl 0.5 --p_proj 0.0 --seed_C 42 --seed_m 123
# Expected: JSON output with DW1, DW2 arrays
```

### Final Checklist
- [ ] All "Must Have" present (clean abstraction, hidden MPS, auto-tracking, extensibility)
- [ ] All "Must NOT Have" absent (no ancilla, no TCI, no adder_MPO, ≤2 type levels)
- [ ] Physics verification PASS (DW1/DW2 match CT.jl within 1e-10)
- [ ] All three API styles work (OO-explicit, OO-imperative, Functional)
- [ ] Both PBC and OBC work
- [ ] RNG reproducibility confirmed
