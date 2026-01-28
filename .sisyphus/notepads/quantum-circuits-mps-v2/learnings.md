# Learnings from Tasks 0-6, 10

## [2026-01-28T20:00:00Z] Pre-Task-5 Accumulated Wisdom

### Key Conventions

1. **Module Loading (Contract 6)**:
   ```julia
   cd("/mnt/d/Rutgers/QuantumCircuitsMPS.jl")
   include("src/v2/QuantumCircuitsMPSv2.jl")
   using .QuantumCircuitsMPSv2
   using ITensors, ITensorMPS
   ```

2. **Basis Mapping (Tasks 1, 4)**:
   - OBC: identity mapping `phy_ram = ram_phy = [1,2,3,...,L]`
   - PBC: folded mapping implemented in `compute_basis_mapping(L, :periodic)`
   - Always use `state.phy_ram[physical_site]` to convert physical → RAM indices

3. **RNG Streams (Task 2)**:
   - `:ctrl` - control map decisions
   - `:proj` - projection decisions  
   - `:haar` - Haar random unitary generation (EXACT CT.jl algorithm)
   - `:born` - Born measurement outcomes
   - `:state_init` - RandomMPS initialization

4. **Gate Support (Task 3)**:
   - Single-qubit: `support() = 1` (PauliX/Y/Z, Projection)
   - Two-qubit: `support() = 2` (HaarRandom, CZ)
   - Composite: Reset = Projection + conditional PauliX

5. **build_operator Signatures**:
   ```julia
   # Single-qubit: site is Index
   build_operator(gate::PauliX, site::Index, local_dim::Int; kwargs...)
   
   # Two-qubit: sites is Vector{Index}
   build_operator(gate::HaarRandom, sites::Vector{Index}, local_dim::Int; rng::RNGRegistry)
   ```

### Critical Contracts for Task 5

#### Contract 3.5: Normalization by Gate Class
- **Unitaries (HaarRandom, CZ, PauliX/Y/Z)**: NO normalize after apply
- **Projections**: YES normalize after apply (`normalize!(state.mps)`)
- **Reset**: Projection already normalizes, PauliX doesn't need it

#### Contract 3.6: Index Matching (NOT Tag Parsing)
```julia
function get_site_number(op_index::Index, state_sites::Vector{Index}) -> Int
    for (ram_idx, site_idx) in enumerate(state_sites)
        if noprime(op_index) == noprime(site_idx)
            return ram_idx
        end
    end
    error("Index not found")
end
```

#### Contract 2.1: Support Validation
```julia
if support(gate) != length(sites)
    throw(ArgumentError("Gate support $(support(gate)) does not match sites $(length(sites))"))
end
```

### CT.jl apply_op! Algorithm (Lines 147-172)

**Single-site**:
```julia
orthogonalize!(mps, ram_site)
mps[ram_site] = mps[ram_site] * op
noprime!(mps[ram_site])
```

**Multi-site**:
```julia
i_list = sort(ram_sites)  # SVD sweep order
orthogonalize!(mps, i_list[1])
mps_ij = mps[i_list[1]]
for idx in i_list[1]+1:i_list[end]
    mps_ij *= mps[idx]
end
mps_ij *= op
noprime!(mps_ij)

# SVD chain reconstruction
lefttags = (i_list[1]==1) ? nothing : tags(linkind(mps,i_list[1]-1))
for idx in i_list[1]:i_list[end]-1
    inds1 = (idx==1) ? [siteind(mps,1)] : [findindex(mps[idx-1],lefttags), findindex(mps[idx],"Site")]
    lefttags = tags(linkind(mps,idx))
    U, S, V = svd(mps_ij, inds1, cutoff=cutoff, lefttags=lefttags, maxdim=maxdim)
    mps[idx] = U
    mps_ij = S * V
end
mps[i_list[end]] = mps_ij
```

### Gotchas

1. **Operator Construction vs SVD Order**: Build operator with indices in PHYSICAL PAIR order (e.g., [10, 1] for PBC wrap), but apply_op_internal! sorts for SVD sweep.

2. **Staircase Advancement**: Must happen AFTER apply!, not before. Pointer is read-only to users via `current_position()`.

3. **Bricklayer Pairs**:
   - `:odd` → (1,2), (3,4), (5,6), ...
   - `:even` → (2,3), (4,5), ... plus (L,1) for PBC

4. **AllSites vs Bricklayer**: apply! should loop internally for these iterating geometries.

### Files Created So Far

- `src/v2/QuantumCircuitsMPSv2.jl` (Task 0)
- `src/v2/State/State.jl`, `State/initialization.jl` (Task 1)
- `src/v2/Core/basis.jl` (Tasks 1, 4)
- `src/v2/Core/rng.jl` (Task 2)
- `src/v2/Gates/Gates.jl`, `single_qubit.jl`, `two_qubit.jl`, `composite.jl` (Task 3)
- `src/v2/Observables/Observables.jl`, `domain_wall.jl`, `born.jl` (Task 6)
- `test/reference/ct_reference_L10.json` (Task 10)

### Next: Task 5

Need to create:
- `src/v2/Geometry/Geometry.jl`
- `src/v2/Geometry/static.jl` 
- `src/v2/Geometry/staircase.jl`
- `src/v2/Core/apply.jl`

## [2026-01-28T22:00:00Z] Task 5: Geometry and apply! Engine

### Files Created

- `src/v2/Geometry/Geometry.jl` - AbstractGeometry type, get_sites() function, includes
- `src/v2/Geometry/static.jl` - SingleSite, AdjacentPair, Bricklayer, AllSites
- `src/v2/Geometry/staircase.jl` - StaircaseLeft, StaircaseRight with mutable _position
- `src/v2/Core/apply.jl` - apply!() overloads and apply_op_internal!()

### Implementation Details

1. **Geometry Type Hierarchy**:
   - `AbstractGeometry` (abstract base)
   - `AbstractStaircase <: AbstractGeometry` (abstract for staircases)
   - Static: SingleSite, AdjacentPair, Bricklayer, AllSites
   - Dynamic: StaircaseRight, StaircaseLeft

2. **CT.jl apply_op! Algorithm Ported**:
   - `apply_op_internal!(mps, op, sites, cutoff, maxdim)` 
   - Single-site: orthogonalize, contract, noprime, assign
   - Multi-site: orthogonalize to first, contract range, apply op, SVD chain

3. **Index Matching (Contract 3.6)**:
   - `get_op_ram_sites()` uses Index comparison via `noprime(op_idx) == noprime(site_idx)`
   - NO tag parsing - avoids CT.jl's fragile string manipulation

4. **Normalization Dispatch (Contract 3.5)**:
   - `gate isa Projection` → `normalize!(state.mps)` after apply
   - Unitaries (HaarRandom, CZ, PauliX/Y/Z) → NO normalization

5. **Staircase Pointer**:
   - `_position` field is private (mutable struct)
   - `current_position(geo)` is read-only accessor
   - `advance!(geo, L, bc)` called internally by apply! AFTER gate application
   - StaircaseRight: pos → pos+1, wraps L → 1 (PBC) or L-1 → 1 (OBC)
   - StaircaseLeft: pos → pos-1, wraps 1 → L (PBC) or 1 → L-1 (OBC)

6. **Bricklayer and AllSites**:
   - apply! dispatches loop internally over all pairs/sites
   - `get_pairs(geo::Bricklayer, state)` returns all pairs for pattern
   - `get_all_sites(geo::AllSites, state)` returns 1:L

### Manual Verification: ALL PASS

- Test 1 (PauliX SingleSite): Sz +0.5 → -0.5 ✓
- Test 2 (Staircase): pointer advances 1 → 2 after apply ✓
- Test 3 (Support validation): ArgumentError thrown for mismatch ✓
- Test 4 (Projection normalization): MPS norm = 1.0 after Projection ✓

### Module Updates

- Uncommented `include("Geometry/Geometry.jl")` and `include("Core/apply.jl")`
- Added exports: AbstractGeometry, get_sites, SingleSite, AdjacentPair, Bricklayer, AllSites, StaircaseLeft, StaircaseRight, current_position, apply!

### Gotchas Discovered

- Include order matters: Geometry before apply.jl (apply.jl uses geometry types)
- svd() requires keyword syntax: `cutoff=cutoff` not positional
- findindex with tags needs string matching from linkind

## [2026-01-28T20:16:00Z] Task 5: Geometry and apply! - COMPLETE

### Files Created
- `src/v2/Geometry/Geometry.jl` - AbstractGeometry, get_sites protocol
- `src/v2/Geometry/static.jl` - SingleSite, AdjacentPair, Bricklayer, AllSites
- `src/v2/Geometry/staircase.jl` - StaircaseLeft/Right with mutable pointer
- `src/v2/Core/apply.jl` - apply!() overloads and apply_op_internal!()

### Implementation Details

**Geometry Types**:
- SingleSite(site): returns [site]
- AdjacentPair(first): returns [first, mod(first, L) + 1] for PBC wrap
- Bricklayer(:odd): pairs (1,2), (3,4), ...
- Bricklayer(:even): pairs (2,3), (4,5), ... plus (L,1) for PBC
- StaircaseRight/Left: mutable pointer, `current_position()` read-only, `advance!()` internal

**apply! Dispatch**:
1. `apply!(state, gate, geo::AbstractGeometry)` - validates support, gets sites, calls physical version
2. `apply!(state, gate, sites::Vector{Int})` - main workhorse, converts physical→RAM, builds op, contracts MPS
3. `apply!(state, gate, geo::Bricklayer)` - loops over pairs internally
4. `apply!(state, gate, geo::AllSites)` - loops over all sites internally

**apply_op_internal! Algorithm** (ported from CT.jl lines 147-172):
```julia
i_list = sort(ram_sites)  # SVD sweep order
orthogonalize!(mps, i_list[1])
mps_ij = mps[i_list[1]]
for idx in i_list[1]+1:i_list[end]
    mps_ij *= mps[idx]
end
mps_ij *= op
noprime!(mps_ij)

if length(i_list) == 1
    mps[i_list[1]] = mps_ij
else
    # SVD chain with cutoff/maxdim
    lefttags = ...
    for idx in i_list[1]:i_list[end]-1
        U, S, V = svd(mps_ij, inds1, cutoff=cutoff, lefttags=lefttags, maxdim=maxdim)
        mps[idx] = U
        mps_ij = S * V
    end
    mps[i_list[end]] = mps_ij
end
```

**Normalization Dispatch**:
```julia
if gate isa Projection
    normalize!(state.mps)
end
# Unitaries: NO normalization
```

**Index Matching** (Contract 3.6):
```julia
function get_site_number(op_index, state_sites)
    for (ram_idx, site_idx) in enumerate(state_sites)
        if noprime(op_index) == noprime(site_idx)
            return ram_idx
        end
    end
end
```

### Manual Verification: ALL PASS ✓
1. PauliX SingleSite: Sz +0.5 → -0.5
2. Staircase pointer: 1 → 2 after apply
3. Support validation: ArgumentError for mismatch
4. Projection normalization: MPS norm = 1.0

### Key Gotchas Resolved
- Operator construction uses PHYSICAL PAIR order (e.g., [10,1] for PBC wrap)
- apply_op_internal! sorts internally for SVD sweep (sorted RAM order)
- Staircase advancement happens AFTER apply!, not before
- Module exports updated with all geometry types

### Next Tasks
- Task 7: API wrappers (context, functional, apply_with_prob!)
- Task 8: CT model example
- Task 9: Verification against CT.jl

## [2026-01-28T20:15:00Z] Task 7: API Wrappers

### Files Created
- `src/v2/API/imperative.jl` - Documentation of imperative style
- `src/v2/API/functional.jl` - `simulate()` function
- `src/v2/API/context.jl` - `with_state()` and implicit `apply!()` overloads
- `src/v2/API/probabilistic.jl` - `apply_with_prob!()` function

### Implementation Details

1. **Functional API (`simulate`)**:
   - Encapsulates state creation, initialization, tracking, and the simulation loop.
   - Supports `record_at` modes: `:every`, `:final`, `:custom`.
   - Handles `i1_fn` for dynamic DomainWall sampling sites.

2. **Context API (`with_state`)**:
   - Uses a thread-local `Ref` (`CURRENT_STATE`) to store the active state.
   - Provides implicit `apply!(gate, geo)` overloads that fetch the state from context.
   - Ensures state is restored even if the block errors (via `try...finally`).

3. **Probabilistic API (`apply_with_prob!`)**:
   - **CRITICAL**: Always draws from the RNG stream *before* checking the probability.
   - This ensures deterministic RNG advancement (Contract 4.4).
   - Default stream is `:ctrl`.

### Manual Verification: ALL PASS ✓
1. **Imperative API**: Direct `apply!(state, gate, geo)` works.
2. **Context API**: `with_state(state) do; apply!(gate, geo); end` works.
3. **RNG Consumption**: `apply_with_prob!` advances RNG even when `prob=0.0`.
4. **Functional API**: `simulate()` runs full loop and returns results Dict.

### Module Updates
- Included all 4 API files.
- Exported: `simulate`, `with_state`, `current_state`, `apply_with_prob!`.

