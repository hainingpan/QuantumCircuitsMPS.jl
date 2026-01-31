# MIPT Example - Measurement-Induced Phase Transition

## TL;DR

> **Quick Summary**: Create a canonical MIPT example demonstrating the measurement-induced entanglement phase transition using bricklayer Haar-random unitaries and probabilistic Z-measurements. Requires adding `Measurement` gate (fundamental) and `EntanglementEntropy` observable.
>
> **Deliverables**:
> - `src/Gates/composite.jl` - New `Measurement` gate (fundamental projective measurement)
> - `src/Core/apply.jl` - Measurement dispatch methods + refactored Reset
> - `src/Observables/entanglement.jl` - Revived EntanglementEntropy observable
> - `examples/mipt_example.jl` - Standalone Julia script
> - `examples/mipt_tutorial.ipynb` - Jupyter notebook version
> - `test/entanglement_test.jl` - Unit tests for EntanglementEntropy
>
> **Estimated Effort**: Medium
> **Parallel Execution**: YES - 2 waves
> **Critical Path**: Task 1 (Measurement gate) → Task 3 (observable) → Task 5 (examples)

---

## Context

### Original Request
User requested an MIPT example demonstrating: "A 1D chain is driven by alternating (bricklayer) two-qubit scrambling gates; after each layer, each site is 'checked' by a local projective measurement with probability p." Two versions requested: standalone .jl and Jupyter notebook.

### Interview Summary
**Key Discussions**:
- **Circuit structure**: Sequential `apply!()` calls - unitaries first, then probabilistic measurements
- **Bricklayer pattern**: Both `:odd` and `:even` parities within each timestep (standard MIPT)
- **Observable choice**: Add EntanglementEntropy (revive from deprecated module)
- **CRITICAL CORRECTION**: `Reset()` is WRONG for MIPT - it resets to |0⟩ after measurement. MIPT requires pure projective measurement that leaves qubit in measured state.

**Research Findings**:
- `Bricklayer(:odd)` and `Bricklayer(:even)` work with Circuit API for HaarRandom
- Current `Reset()` does: measure → project → reset to |0⟩ (WRONG for MIPT physics)
- Need `Measurement(:Z)` that does: measure → project → DONE (pure measurement)
- Proper hierarchy: `Measurement(:Z)` is fundamental, `Reset` = `Measurement(:Z)` + conditional X

### Metis Review
**Identified Gaps** (addressed):
- **Reset vs Measurement**: Critical physics error - Reset resets to |0⟩, MIPT needs pure measurement
- **Gate hierarchy**: `Measurement` should be fundamental, `Reset` built on top
- **API design**: `Measurement(:Z)` with axis parameter (extensible to :X, :Y later)

---

## Work Objectives

### Core Objective
Create a complete MIPT example demonstrating measurement-induced phase transition physics with proper observable tracking and physically correct measurement gates.

### Concrete Deliverables
- `src/Gates/composite.jl` - New `Measurement` struct (fundamental projective measurement)
- `src/Core/apply.jl` - Measurement dispatch methods + refactored Reset to use Measurement
- `src/Observables/entanglement.jl` - New file with EntanglementEntropy struct and callable
- `examples/mipt_example.jl` - Runnable MIPT script using `Measurement(:Z)`
- `examples/mipt_tutorial.ipynb` - Pedagogical notebook
- `test/entanglement_test.jl` - Unit tests

### Definition of Done
- [x] `julia -e 'using QuantumCircuitsMPS; apply!(state, Measurement(:Z), SingleSite(1))'` works
- [x] `julia -e 'using QuantumCircuitsMPS; track!(state, :ee => EntanglementEntropy(; cut=2))'` works
- [x] `julia examples/mipt_example.jl` exits with code 0
- [x] All existing tests still pass: `julia --project -e 'using Pkg; Pkg.test()'`

### Must Have
- `Measurement` gate as FUNDAMENTAL type (pure Born sampling + projection, NO reset)
- `Reset` refactored to use `Measurement(:Z)` + conditional X (derived, not fundamental)
- EntanglementEntropy observable matching DomainWall API pattern
- Working MIPT example in both .jl and .ipynb formats
- Basic unit tests for EntanglementEntropy

### Must NOT Have (Guardrails)
- No premature generalization (no MIPTCircuit struct, no configurable gate types)
- No over-parameterization (single standard protocol: Haar + Z-measurement)
- No plotting libraries added (use simple println for .jl, defer plots to user)
- No phase diagram computation (single trajectory at fixed p)
- No deprecated `current_state()` API pattern
- **CRITICAL**: No use of `Reset()` in MIPT example - use `Measurement(:Z)` only

---

## Verification Strategy (MANDATORY)

### Test Decision
- **Infrastructure exists**: YES (test/runtests.jl exists with Pkg.test())
- **User wants tests**: YES (TDD for observable, API tests for example)
- **Framework**: Julia's Test module (existing pattern)

### Automated Verification Approach

Each TODO includes EXECUTABLE verification:

| Type | Verification Method |
|------|---------------------|
| Measurement gate | `julia --project -e 'using QuantumCircuitsMPS; Measurement(:Z)'` |
| Observable (entanglement.jl) | `julia --project -e 'include("test/entanglement_test.jl")'` |
| Example (.jl) | `julia --project examples/mipt_example.jl` → exit code 0 |
| Notebook (.ipynb) | Execute via Jupyter: `jupyter nbconvert --execute` |

---

## Execution Strategy

### Parallel Execution Waves

```
Wave 1 (Start Immediately):
├── Task 1: Add Measurement gate (fundamental) [no dependencies]
├── Task 2: Refactor Reset to use Measurement [depends: 1, but same file - do together]
└── Task 3: Add EntanglementEntropy observable [no dependencies]

Wave 2 (After Wave 1):
├── Task 4: Create mipt_example.jl [depends: 1, 3]
├── Task 5: Create mipt_tutorial.ipynb [depends: 1, 3]
└── Task 6: Add entanglement_test.jl [depends: 3]

Wave 3 (After Wave 2):
└── Task 7: Final verification [depends: 4, 5, 6]

Critical Path: Task 1 → Task 4 → Task 7
Parallel Speedup: ~40% faster than sequential
```

### Dependency Matrix

| Task | Depends On | Blocks | Can Parallelize With |
|------|------------|--------|---------------------|
| 1 | None | 2, 4, 5 | 3 |
| 2 | 1 | 4, 5 | (same commit as 1) |
| 3 | None | 4, 5, 6 | 1, 2 |
| 4 | 1, 2, 3 | 7 | 5, 6 |
| 5 | 1, 2, 3 | 7 | 4, 6 |
| 6 | 3 | 7 | 4, 5 |
| 7 | 4, 5, 6 | None | None (final) |

### Agent Dispatch Summary

| Wave | Tasks | Recommended Agents |
|------|-------|-------------------|
| 1 | 1+2, 3 | delegate_task(category="quick", run_in_background=true) |
| 2 | 4, 5, 6 | dispatch parallel after Wave 1 completes |
| 3 | 7 | final integration task |

---

## TODOs

- [x] 1. Add Measurement gate (fundamental projective measurement)

  **What to do**:
  - Add to `src/Gates/composite.jl`:
    - New `Measurement` struct with `axis::Symbol` field (`:Z` only for now)
    - `support(::Measurement) = 1`
    - `build_operator` stub that throws (like Reset - handled in apply!)
  - Export `Measurement` from `src/QuantumCircuitsMPS.jl`

  **Implementation Specification** (CRITICAL):
  
  ```julia
  # In src/Gates/composite.jl - ADD BEFORE Reset definition
  
  """
      Measurement(axis::Symbol)
  
  Pure projective measurement in the specified basis.
  
  - `Measurement(:Z)` - Z-basis measurement: projects to |0⟩ or |1⟩ based on Born probability
  
  This is a FUNDAMENTAL operation. Unlike `Reset`, measurement leaves the qubit
  in the measured state (|0⟩ or |1⟩) without resetting it.
  
  # Physics
  1. Compute Born probability P(0|ψ) for the qubit
  2. Sample outcome ∈ {0, 1} according to Born rule
  3. Apply projection operator to collapse wavefunction
  4. Normalize the state
  
  # Example
  ```julia
  apply!(state, Measurement(:Z), SingleSite(1))  # Measure qubit 1 in Z-basis
  apply!(state, Measurement(:Z), AllSites())     # Measure all qubits
  ```
  """
  struct Measurement <: AbstractGate
      axis::Symbol
      
      function Measurement(axis::Symbol)
          axis == :Z || throw(ArgumentError("Only :Z axis supported currently. Got: $axis"))
          new(axis)
      end
  end
  
  support(::Measurement) = 1
  
  # Measurement requires Born sampling - cannot be a simple operator
  function build_operator(gate::Measurement, site::Index, local_dim::Int; kwargs...)
      error("Measurement gate cannot be built as a single operator. Use apply!(state, Measurement(:Z), geo) instead.")
  end
  ```

  **Must NOT do**:
  - Do NOT implement :X or :Y axis yet (scope creep)
  - Do NOT modify existing Reset definition (that's Task 2)

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Small struct definition with validation
  - **Skills**: `[]`
    - No special skills needed

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 1 (with Task 3)
  - **Blocks**: Tasks 2, 4, 5
  - **Blocked By**: None (can start immediately)

  **References**:
  
  **Pattern References** (existing code to follow):
  - `src/Gates/composite.jl:1-17` - Reset struct pattern (use same structure)
  - `src/Gates/single_qubit.jl:4-6` - Simple gate struct pattern
  
  **Export Reference**:
  - `src/QuantumCircuitsMPS.jl:51` - Gate exports line

  **Acceptance Criteria**:

  **Automated Verification**:
  ```bash
  # Agent runs:
  julia --project -e '
    using QuantumCircuitsMPS
    using Test
    
    # Test 1: Measurement is exported and constructable
    m = Measurement(:Z)
    @test m isa AbstractGate
    @test m.axis == :Z
    @test support(m) == 1
    
    # Test 2: Only :Z is valid
    @test_throws ArgumentError Measurement(:X)
    @test_throws ArgumentError Measurement(:Y)
    
    println("✓ Measurement gate struct tests passed")
  '
  # Assert: exit code = 0
  # Assert: "Measurement gate struct tests passed" in output
  ```

  **Evidence to Capture:**
  - [ ] Terminal output showing tests passed

  **Commit**: YES (combined with Task 2)
  - Message: `feat(gates): add Measurement gate as fundamental projective measurement`
  - Files: `src/Gates/composite.jl`, `src/QuantumCircuitsMPS.jl`
  - Pre-commit: `julia --project -e 'using Pkg; Pkg.test()'`

---

- [x] 2. Add Measurement dispatch methods and refactor Reset

  **What to do**:
  - Add to `src/Core/apply.jl`:
    - Helper function `_measure_single_site!(state, site)` that does Born sampling + projection
    - Dispatch methods for `Measurement` with: `SingleSite`, `AllSites`, `AbstractStaircase`, `Pointer`
    - Refactor ALL Reset dispatches to use `_measure_single_site!` + conditional X

  **Implementation Specification** (CRITICAL):
  
  ```julia
  # In src/Core/apply.jl - REPLACE the Reset section (lines 71-123)
  
  # === Internal helper for Born-sampled projection ===
  
  """
      _measure_single_site!(state::SimulationState, site::Int) -> Int
  
  Perform Born-sampled projective measurement on a single site.
  Returns the measurement outcome (0 or 1).
  
  This is the FUNDAMENTAL measurement operation:
  1. Compute Born probability P(0|ψ)
  2. Sample outcome using :born RNG stream
  3. Apply Projection operator
  4. Return outcome (for conditional logic in Reset)
  """
  function _measure_single_site!(state::SimulationState, site::Int)
      p_0 = born_probability(state, site, 0)
      born_rng = get_rng(state.rng_registry, :born)
      outcome = rand(born_rng) < p_0 ? 0 : 1
      _apply_single!(state, Projection(outcome), [site])
      return outcome
  end
  
  # === Measurement gate dispatch (FUNDAMENTAL - pure projection) ===
  
  function _apply_dispatch!(state::SimulationState, gate::Measurement, geo::SingleSite)
      site = get_sites(geo, state)[1]
      _measure_single_site!(state, site)
      return nothing
  end
  
  function _apply_dispatch!(state::SimulationState, gate::Measurement, geo::AllSites)
      all_sites = get_all_sites(geo, state)
      for site in all_sites
          _measure_single_site!(state, site)  # Independent per-site sampling
      end
      return nothing
  end
  
  function _apply_dispatch!(state::SimulationState, gate::Measurement, geo::AbstractStaircase)
      site = geo._position
      _measure_single_site!(state, site)
      advance!(geo, state.L, state.bc)
      return nothing
  end
  
  function _apply_dispatch!(state::SimulationState, gate::Measurement, geo::Pointer)
      site = geo._position
      _measure_single_site!(state, site)
      # NO advance! - user explicitly calls move!()
      return nothing
  end
  
  # === Reset gate dispatch (DERIVED - measurement + conditional X) ===
  
  function _apply_dispatch!(state::SimulationState, gate::Reset, geo::SingleSite)
      site = get_sites(geo, state)[1]
      outcome = _measure_single_site!(state, site)
      if outcome == 1
          _apply_single!(state, PauliX(), [site])
      end
      return nothing
  end
  
  function _apply_dispatch!(state::SimulationState, gate::Reset, geo::AllSites)
      all_sites = get_all_sites(geo, state)
      for site in all_sites
          outcome = _measure_single_site!(state, site)
          if outcome == 1
              _apply_single!(state, PauliX(), [site])
          end
      end
      return nothing
  end
  
  function _apply_dispatch!(state::SimulationState, gate::Reset, geo::AbstractStaircase)
      site = geo._position
      outcome = _measure_single_site!(state, site)
      if outcome == 1
          _apply_single!(state, PauliX(), [site])
      end
      advance!(geo, state.L, state.bc)
      return nothing
  end
  
  function _apply_dispatch!(state::SimulationState, gate::Reset, geo::Pointer)
      site = geo._position
      outcome = _measure_single_site!(state, site)
      if outcome == 1
          _apply_single!(state, PauliX(), [site])
      end
      # NO advance!
      return nothing
  end
  ```

  **Why this design**:
  - `_measure_single_site!` is the fundamental operation (reusable)
  - `Measurement` dispatch just calls the helper (pure measurement)
  - `Reset` dispatch calls helper + conditional X (derived from measurement)
  - DRY: measurement logic written once, used by both gates
  - Extensible: future Measurement(:X) just needs different projection basis

  **Must NOT do**:
  - Do NOT change existing API behavior (Reset still resets to |0⟩)
  - Do NOT add Bricklayer dispatch for Measurement (use AllSites for per-site)

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Pattern-following dispatch methods
  - **Skills**: `[]`
    - No special skills needed

  **Parallelization**:
  - **Can Run In Parallel**: NO (depends on Task 1, same commit)
  - **Parallel Group**: Wave 1 (with Task 1)
  - **Blocks**: Tasks 4, 5
  - **Blocked By**: Task 1

  **References**:
  
  **Pattern References** (existing code to follow):
  - `src/Core/apply.jl:57-62` - AllSites dispatch loop pattern
  - `src/Core/apply.jl:73-92` - CURRENT Reset+SingleSite (will be refactored)
  - `src/Core/apply.jl:94-109` - CURRENT Reset+Staircase (will be refactored)
  
  **API References**:
  - `born_probability(state, site, outcome)` - in `src/Observables/born.jl`
  - `get_rng(registry, :born)` - in `src/Core/rng.jl`

  **Acceptance Criteria**:

  **Automated Verification**:
  ```bash
  # Agent runs:
  julia --project -e '
    using QuantumCircuitsMPS
    using Test
    
    # Setup
    rng = RNGRegistry(ctrl=1, proj=2, haar=3, born=4)
    
    # Test 1: Measurement(:Z) + SingleSite - qubit stays in measured state
    state = SimulationState(L=4, bc=:open, rng=rng)
    initialize!(state, ProductState(x0=1//2))  # Superposition |+⟩
    
    apply!(state, Measurement(:Z), SingleSite(1))
    
    # After measurement, qubit 1 should be in |0⟩ OR |1⟩ (not superposition)
    p0 = born_probability(state, 1, 0)
    @test p0 ≈ 1.0 || p0 ≈ 0.0  # Collapsed to eigenstate
    
    # Test 2: Measurement(:Z) + AllSites - all qubits measured independently
    state2 = SimulationState(L=4, bc=:open, rng=RNGRegistry(ctrl=10, proj=20, haar=30, born=40))
    initialize!(state2, ProductState(x0=1//2))
    
    apply!(state2, Measurement(:Z), AllSites())
    
    for site in 1:4
        p0 = born_probability(state2, site, 0)
        @test p0 ≈ 1.0 || p0 ≈ 0.0  # Each collapsed
    end
    
    # Test 3: Reset still works (backward compatible) - always ends at |0⟩
    state3 = SimulationState(L=4, bc=:open, rng=RNGRegistry(ctrl=100, proj=200, haar=300, born=400))
    initialize!(state3, ProductState(x0=1//2))
    
    apply!(state3, Reset(), AllSites())
    
    for site in 1:4
        p0 = born_probability(state3, site, 0)
        @test p0 ≈ 1.0 atol=1e-10  # Reset always ends at |0⟩
    end
    
    # Test 4: Measurement vs Reset difference
    # Run same circuit twice with same seed - Measurement keeps measured state, Reset resets
    rng_m = RNGRegistry(ctrl=42, proj=42, haar=42, born=42)
    rng_r = RNGRegistry(ctrl=42, proj=42, haar=42, born=42)
    
    state_m = SimulationState(L=1, bc=:open, rng=rng_m)
    state_r = SimulationState(L=1, bc=:open, rng=rng_r)
    
    # Start with |1⟩ state
    initialize!(state_m, ProductState(x0=1))
    initialize!(state_r, ProductState(x0=1))
    
    apply!(state_m, Measurement(:Z), SingleSite(1))
    apply!(state_r, Reset(), SingleSite(1))
    
    # Measurement: stays at |1⟩ (measured outcome was 1)
    # Reset: goes to |0⟩ (measured 1, then flipped)
    p0_m = born_probability(state_m, 1, 0)
    p0_r = born_probability(state_r, 1, 0)
    
    @test p0_m ≈ 0.0 atol=1e-10  # Measurement kept |1⟩
    @test p0_r ≈ 1.0 atol=1e-10  # Reset went to |0⟩
    
    # Test 5: Measurement(:Z) + StaircaseRight - advances pointer after measurement
    state5 = SimulationState(L=4, bc=:open, rng=RNGRegistry(ctrl=200, proj=200, haar=200, born=200))
    initialize!(state5, ProductState(x0=1//2))
    stair = StaircaseRight(1)
    
    # Apply Measurement via staircase
    apply!(state5, Measurement(:Z), stair)
    @test current_position(stair) == 2  # Should have advanced
    
    # Measured site should be collapsed
    p0_s = born_probability(state5, 1, 0)
    @test p0_s ≈ 1.0 || p0_s ≈ 0.0
    
    # Test 6: Reset regression - multiple random states all end at |0⟩
    for seed in [999, 1001, 1234, 5678]
        state_reg = SimulationState(L=4, bc=:open, rng=RNGRegistry(ctrl=seed, proj=seed, haar=seed, born=seed))
        initialize!(state_reg, ProductState(x0=rand()))  # Random initial
        apply!(state_reg, Reset(), AllSites())
        for site in 1:4
            @test born_probability(state_reg, site, 0) ≈ 1.0 atol=1e-10
        end
    end
    
    println("✓ Measurement dispatch tests passed")
  '
  # Assert: exit code = 0
  # Assert: "Measurement dispatch tests passed" in output
  ```

  **Evidence to Capture:**
  - [ ] Terminal output showing all 6 tests passed

  **Commit**: YES (combined with Task 1)
  - Message: `feat(gates): add Measurement gate as fundamental projective measurement`
  - Files: `src/Gates/composite.jl`, `src/Core/apply.jl`, `src/QuantumCircuitsMPS.jl`
  - Pre-commit: `julia --project -e 'using Pkg; Pkg.test()'`

---

- [x] 3. Add EntanglementEntropy observable

  **What to do**:
  - Create `src/Observables/entanglement.jl` with:
    - `EntanglementEntropy` struct with fields: `cut::Int`, `order::Int` (default 1), `threshold::Float64` (default 1e-16)
    - Callable `(ee::EntanglementEntropy)(state)` that computes von Neumann entropy
    - Internal helper `_von_neumann_entropy(mps, i; n, threshold)` ported from deprecated module
  - Update `src/Observables/Observables.jl`:
    - Add `include("entanglement.jl")`
    - Add "EntanglementEntropy" to `list_observables()` return value
  - Export from `src/QuantumCircuitsMPS.jl`:
    - Add `EntanglementEntropy` to observable exports

  **Implementation Specification** (CRITICAL):
  
  The callable takes `state::SimulationState`, extracts `mps` and `phy_ram`, then calls internal helper:
  
  ```julia
  # Struct definition (keyword constructor with optional threshold)
  struct EntanglementEntropy <: AbstractObservable
      cut::Int
      order::Int
      threshold::Float64
      
      function EntanglementEntropy(; cut::Int, order::Int=1, threshold::Float64=1e-16)
          order >= 1 || throw(ArgumentError("order must be >= 1"))
          threshold > 0 || throw(ArgumentError("threshold must be positive"))
          new(cut, order, threshold)
      end
  end
  
  # Callable: takes state, validates cut, computes entropy
  function (ee::EntanglementEntropy)(state)
      1 <= ee.cut < state.L || throw(ArgumentError("cut must satisfy 1 <= cut < L"))
      ram_cut = state.phy_ram[ee.cut]  # Convert physical site to RAM index
      return _von_neumann_entropy(state.mps, ram_cut; n=ee.order, threshold=ee.threshold)
  end
  
  # Internal helper: takes MPS directly (not state) - ported from deprecated
  function _von_neumann_entropy(mps::MPS, i::Int; n::Int=1, threshold::Float64=1e-16)
      mps_ = orthogonalize(mps, i)
      _, S = svd(mps_[i], (linkind(mps_, i),))
      p = max.(diag(S), threshold) .^ 2  # Singular values → probabilities
      if n == 1
          return -sum(p .* log.(p))  # von Neumann entropy
      elseif n == 0
          return log(length(p))  # Hartley entropy
      end
      return log(sum(p .^ n)) / (1 - n)  # Rényi entropy
  end
  ```
  
  **Threshold parameter**: Optional with default 1e-16 (Float64 precision limit). Most users won't need to change this. Exposed for edge cases where different precision is needed (e.g., higher-precision arithmetic or debugging numerical issues).

  **Must NOT do**:
  - Do NOT use `current_state()` global pattern (use explicit state passing)
  - Do NOT add MagnetizationZ or MaxBondDim (out of scope)

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Single file creation following established pattern
  - **Skills**: `[]`
    - No special skills needed - straightforward Julia code

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 1 (with Tasks 1, 2)
  - **Blocks**: Tasks 4, 5, 6
  - **Blocked By**: None (can start immediately)

  **References**:
  
  **Pattern References** (existing code to follow):
  - `src/Observables/domain_wall.jl:17-25` - Struct definition pattern with callable
  - `src/Observables/domain_wall.jl:28-40` - Callable struct implementation pattern
  - `src/Observables/Observables.jl:22-27` - track! integration pattern
  - `src/Observables/Observables.jl:73-75` - list_observables() registration

  **Implementation References** (code to port):
  - `src/_deprecated/Observables/Observables.jl:35-55` - _von_neumann_entropy implementation
  - `src/_deprecated/Observables/Observables.jl:74-82` - EntanglementEntropy callable (adapt to new API)

  **API/Type References**:
  - `src/State/State.jl` - SimulationState struct for accessing mps, L, phy_ram
  - ITensorMPS API: `orthogonalize(mps, i)`, `svd()`, `linkind()`

  **Export References**:
  - `src/QuantumCircuitsMPS.jl:57` - Observable export location

  **Acceptance Criteria**:

  **Automated Verification**:
  ```bash
  # Agent runs:
  julia --project -e '
    using QuantumCircuitsMPS
    using Test
    
    # Test 1: EntanglementEntropy is exported and constructable
    ee = EntanglementEntropy(; cut=2, order=1)
    @test ee isa AbstractObservable
    @test ee.cut == 2
    @test ee.order == 1
    @test ee.threshold == 1e-16  # Default threshold
    
    # Test 2: Custom threshold works
    ee_custom = EntanglementEntropy(; cut=2, order=1, threshold=1e-12)
    @test ee_custom.threshold == 1e-12
    
    # Test 3: list_observables includes EntanglementEntropy
    obs_list = list_observables()
    @test "EntanglementEntropy" in obs_list
    
    # Test 4: Callable works with SimulationState
    rng = RNGRegistry(ctrl=1, proj=2, haar=3, born=4)
    state = SimulationState(L=4, bc=:open, rng=rng)
    initialize!(state, ProductState(x0=0))  # All |0⟩ - product state
    
    # Product state has zero entanglement
    entropy_val = ee(state)
    @test entropy_val ≈ 0.0 atol=1e-10
    
    # Test 5: track!/record! integration works
    track!(state, :entropy => EntanglementEntropy(; cut=2, order=1))
    record!(state)
    @test length(state.observables[:entropy]) == 1
    @test state.observables[:entropy][1] ≈ 0.0 atol=1e-10
    
    # Test 6: Boundary cut values
    @test EntanglementEntropy(; cut=1, order=1)(state) >= 0.0  # Valid at boundary
    @test_throws ArgumentError EntanglementEntropy(; cut=0, order=1)  # cut must be >= 1
    @test_throws ArgumentError EntanglementEntropy(; cut=4, order=1)(state)  # cut must be < L
    
    println("✓ EntanglementEntropy tests passed")
  '
  # Assert: exit code = 0
  # Assert: "EntanglementEntropy tests passed" in output
  ```

  **Evidence to Capture:**
  - [ ] Terminal output showing all 6 tests passed

  **Commit**: YES
  - Message: `feat(observables): add EntanglementEntropy observable`
  - Files: `src/Observables/entanglement.jl`, `src/Observables/Observables.jl`, `src/QuantumCircuitsMPS.jl`
  - Pre-commit: `julia --project -e 'using Pkg; Pkg.test()'`

---

- [x] 4. Create mipt_example.jl

  **What to do**:
  - Create `examples/mipt_example.jl` implementing standard MIPT protocol:
    - Parameters: L=20, p=0.15, n_steps=50, cut=L÷2, bc=:periodic
    - Circuit structure per step:
      1. `apply!(c, HaarRandom(), Bricklayer(:odd))`
      2. `apply!(c, HaarRandom(), Bricklayer(:even))`
      3. `apply_with_prob!(c; rng=:ctrl, outcomes=[(probability=p, gate=Measurement(:Z), geometry=AllSites())])`
    - Track EntanglementEntropy at cut=L÷2
    - Use `record_when=:every_step` to record after each circuit step
    - **Print format**: `"Step $t: Entanglement entropy = $(Printf.@sprintf("%.6f", entropy_vals[end]))"`
    - Print every 10 steps AND at final step
  - Follow `examples/circuit_tutorial.jl` header comment style

  **Physics Background** (MUST include in example header comments):
  
  ```julia
  # MIPT Physics Background:
  # =========================
  # The Measurement-Induced Phase Transition (MIPT) arises from competition between:
  # - Unitary evolution (Bricklayer Haar gates): Creates entanglement between qubits
  # - Projective measurements (Z-basis): Destroys entanglement locally
  #
  # CRITICAL: We use Measurement(:Z), NOT Reset()!
  # - Measurement(:Z): Pure projective measurement - qubit stays in measured state
  # - Reset(): Measurement + reset to |0⟩ - WRONG for MIPT physics!
  #
  # Circuit structure per step:
  # 1. Bricklayer(:odd)  - Haar random gates on pairs (1,2), (3,4), (5,6), ...
  # 2. Bricklayer(:even) - Haar random gates on pairs (2,3), (4,5), (L,1)...
  # 3. Z-measurements    - Each site measured with probability p (using Measurement(:Z))
  #
  # Phase diagram (at late times):
  # - p < p_c ≈ 0.16: Volume-law phase (S ~ L, highly entangled)
  # - p > p_c ≈ 0.16: Area-law phase (S ~ const, weakly entangled)
  # - p = p_c: Critical point with logarithmic scaling (S ~ log(L))
  #
  # This example uses p=0.15 (near criticality) to show non-trivial entropy evolution.
  ```
  
  **API Verification** (CONFIRMED):
  - `apply_with_prob!` signature verified in `src/Circuit/builder.jl:81-106`
  - `record_when=:every_step` verified in `test/recording_test.jl`

  **Must NOT do**:
  - Do NOT use `Reset()` - use `Measurement(:Z)` only!
  - Do NOT add plotting (keep terminal-only)
  - Do NOT add phase diagram computation (single trajectory only)
  - Do NOT add command-line argument parsing (hardcoded params fine)

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Example file creation with clear structure
  - **Skills**: `[]`
    - No special skills needed

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 2 (with Tasks 5, 6)
  - **Blocks**: Task 7
  - **Blocked By**: Tasks 1, 2, 3

  **References**:
  
  **Pattern References** (existing code to follow):
  - `examples/circuit_tutorial.jl:1-50` - Header comment style and parameter setup
  - `examples/circuit_tutorial.jl:67-72` - Circuit do-block with apply_with_prob!
  - `examples/circuit_tutorial.jl:83-100` - SimulationState setup and simulate!

  **API References**:
  - `src/Circuit/builder.jl:81-106` - apply_with_prob! signature
  - `src/Geometry/static.jl:41-48` - Bricklayer geometry
  - `src/Circuit/recording.jl` - record_when options

  **Physics References** (for comments):
  - MIPT occurs at p_c ≈ 0.16 for Haar circuits
  - Below p_c: volume-law entanglement (S ~ L)
  - Above p_c: area-law entanglement (S ~ const)

  **Acceptance Criteria**:

  **Automated Verification**:
  ```bash
  # Agent runs:
  cd /mnt/d/Rutgers/QuantumCircuitsMPS.jl
  timeout 120 julia --project examples/mipt_example.jl 2>&1 | tee /tmp/mipt_output.txt
  
  # Assert: exit code = 0 (completed within 120 seconds)
  grep -c "Step.*Entanglement entropy" /tmp/mipt_output.txt
  # Assert: returns at least 5 (entropy printed at steps 10, 20, 30, 40, 50)
  
  grep -i "error\|exception" /tmp/mipt_output.txt
  # Assert: returns 0 (no errors)
  
  # Verify no deprecated warnings
  grep -i "deprecated" /tmp/mipt_output.txt
  # Assert: returns 0 (no deprecated warnings)
  ```

  **Evidence to Capture:**
  - [ ] Terminal output with entropy values at multiple timesteps (format: "Step N: Entanglement entropy = X.XXXXXX")
  - [ ] No errors, exceptions, or deprecation warnings

  **Commit**: YES
  - Message: `docs(examples): add MIPT example demonstrating measurement-induced phase transition`
  - Files: `examples/mipt_example.jl`
  - Pre-commit: `julia --project examples/mipt_example.jl`

---

- [x] 5. Create mipt_tutorial.ipynb

  **What to do**:
  - Create `examples/mipt_tutorial.ipynb` as pedagogical notebook:
    - Markdown cells explaining MIPT physics:
      - What is MIPT (measurement-induced phase transition)
      - Volume-law vs area-law entanglement
      - Critical measurement rate p_c ≈ 0.16
      - **CRITICAL**: Explain difference between Measurement(:Z) and Reset()
    - Code cells mirroring mipt_example.jl structure
    - Add "Exercises" cell suggesting: "Try p=0.05, 0.15, 0.3 and compare"
  - Follow `examples/circuit_tutorial.ipynb` structure

  **Must NOT do**:
  - Do NOT use `Reset()` anywhere - only `Measurement(:Z)`
  - Do NOT add plotting cells (defer to user)
  - Do NOT add multi-trajectory averaging
  - Do NOT make cells dependent on external plotting libraries

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Notebook creation mirroring .jl file
  - **Skills**: `[]`
    - No special skills needed

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 2 (with Tasks 4, 6)
  - **Blocks**: Task 7
  - **Blocked By**: Tasks 1, 2, 3

  **References**:
  
  **Pattern References** (existing code to follow):
  - `examples/circuit_tutorial.ipynb` - Complete notebook structure pattern
  - `examples/circuit_tutorial.ipynb:5-23` - Markdown introduction pattern
  - `examples/circuit_tutorial.ipynb:47-50` - Package activation cell

  **Content References**:
  - Task 4 (mipt_example.jl) - Code to convert to notebook cells

  **Acceptance Criteria**:

  **Automated Verification**:
  ```bash
  # Agent runs:
  cd /mnt/d/Rutgers/QuantumCircuitsMPS.jl
  
  # Check notebook is valid JSON
  python3 -c "import json; json.load(open('examples/mipt_tutorial.ipynb'))"
  # Assert: exit code = 0
  
  # Check notebook has expected structure
  python3 -c "
  import json
  nb = json.load(open('examples/mipt_tutorial.ipynb'))
  cells = nb['cells']
  
  # Has markdown and code cells
  has_markdown = any(c['cell_type'] == 'markdown' for c in cells)
  has_code = any(c['cell_type'] == 'code' for c in cells)
  
  # Has MIPT-related content
  content = ' '.join(str(c.get('source', '')) for c in cells)
  has_mipt = 'MIPT' in content or 'measurement-induced' in content.lower()
  has_bricklayer = 'Bricklayer' in content
  has_entropy = 'Entropy' in content or 'entropy' in content
  has_measurement = 'Measurement(:Z)' in content or 'Measurement(:\\'Z' in content
  
  # CRITICAL: Must NOT have Reset in measurement context
  uses_measurement_correctly = 'Measurement(:Z)' in content
  
  assert has_markdown, 'Missing markdown cells'
  assert has_code, 'Missing code cells'
  assert has_mipt, 'Missing MIPT explanation'
  assert has_bricklayer, 'Missing Bricklayer reference'
  assert has_entropy, 'Missing entropy tracking'
  assert uses_measurement_correctly, 'Must use Measurement(:Z), not Reset()'
  
  print('✓ Notebook structure validated')
  "
  # Assert: exit code = 0
  ```

  **Evidence to Capture:**
  - [ ] Notebook is valid JSON
  - [ ] Notebook contains required content markers
  - [ ] Notebook uses Measurement(:Z), not Reset()

  **Commit**: YES (group with Task 4)
  - Message: `docs(examples): add MIPT tutorial notebook`
  - Files: `examples/mipt_tutorial.ipynb`
  - Pre-commit: Notebook JSON validation

---

- [x] 6. Add entanglement_test.jl

  **What to do**:
  - Create `test/entanglement_test.jl` with:
    - Test: Product state has zero entropy
    - Test: EntanglementEntropy is in list_observables()
    - Test: track!/record! integration works
    - Test: cut validation (1 <= cut < L)
  - Update `test/runtests.jl` to include new test file

  **Must NOT do**:
  - Do NOT add physics validation tests (entropy scaling at criticality)
  - Do NOT add performance benchmarks

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Test file following established pattern
  - **Skills**: `[]`
    - No special skills needed

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 2 (with Tasks 4, 5)
  - **Blocks**: Task 7
  - **Blocked By**: Task 3

  **References**:
  
  **Pattern References** (existing code to follow):
  - `test/circuit_test.jl` - Test file structure pattern
  - `test/recording_test.jl` - Test organization with @testset
  - `test/runtests.jl` - Include pattern for test files

  **Acceptance Criteria**:

  **Automated Verification**:
  ```bash
  # Agent runs:
  julia --project -e '
    using Pkg
    Pkg.test()
  ' 2>&1 | tee /tmp/test_output.txt
  
  # Assert: "Test Summary" in output
  # Assert: No "Error" or "FAILED" in summary line
  grep "entanglement" /tmp/test_output.txt
  # Assert: entanglement tests appear in output
  ```

  **Evidence to Capture:**
  - [ ] All tests pass including new entanglement tests

  **Commit**: YES
  - Message: `test: add EntanglementEntropy unit tests`
  - Files: `test/entanglement_test.jl`, `test/runtests.jl`
  - Pre-commit: `julia --project -e 'using Pkg; Pkg.test()'`

---

- [x] 7. Final verification and documentation update

  **What to do**:
  - Run full test suite to verify all components work together
  - Verify example runs end-to-end
  - Update `examples/README.md` if it exists (add mipt_example entry)

  **Must NOT do**:
  - Do NOT create new README if it doesn't exist
  - Do NOT modify package documentation

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Verification and minor updates
  - **Skills**: `[]`
    - No special skills needed

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Wave 3 (sequential final task)
  - **Blocks**: None (final)
  - **Blocked By**: Tasks 4, 5, 6

  **References**:
  
  **Pattern References**:
  - `test/runtests.jl` - Test execution pattern
  - `examples/` - Check for existing README.md

  **Acceptance Criteria**:

  **Automated Verification**:
  ```bash
  # Agent runs full verification:
  cd /mnt/d/Rutgers/QuantumCircuitsMPS.jl
  
  # 1. Run all tests
  julia --project -e 'using Pkg; Pkg.test()' 2>&1 | tee /tmp/final_test.txt
  # Assert: "Test Summary" with no failures
  
  # 2. Run example
  julia --project examples/mipt_example.jl 2>&1 | tee /tmp/final_example.txt
  # Assert: exit code = 0, no errors
  
  # 3. Verify both gates are accessible
  julia --project -e '
    using QuantumCircuitsMPS
    @assert Measurement(:Z) isa AbstractGate
    @assert Reset() isa AbstractGate
    @assert "EntanglementEntropy" in list_observables()
    println("✓ All new features available in package exports")
  '
  # Assert: confirmation message printed
  ```

  **Evidence to Capture:**
  - [ ] All tests pass
  - [ ] Example runs without error
  - [ ] New features are exported correctly

  **Commit**: YES (if README updated)
  - Message: `docs: update examples README with MIPT entry`
  - Files: `examples/README.md` (only if modified)
  - Pre-commit: Full test suite

---

## Commit Strategy

| After Task | Message | Files | Verification |
|------------|---------|-------|--------------|
| 1+2 | `feat(gates): add Measurement gate as fundamental projective measurement` | composite.jl, apply.jl, QuantumCircuitsMPS.jl | Pkg.test() |
| 3 | `feat(observables): add EntanglementEntropy observable` | entanglement.jl, Observables.jl, QuantumCircuitsMPS.jl | Pkg.test() |
| 4+5 | `docs(examples): add MIPT example and tutorial` | mipt_example.jl, mipt_tutorial.ipynb | Run example |
| 6 | `test: add EntanglementEntropy unit tests` | entanglement_test.jl, runtests.jl | Pkg.test() |
| 7 | (optional) `docs: update examples README` | README.md | N/A |

---

## Success Criteria

### Verification Commands
```bash
# Run all tests
julia --project -e 'using Pkg; Pkg.test()'
# Expected: All tests pass (including new entanglement tests)

# Run MIPT example
julia --project examples/mipt_example.jl
# Expected: Prints entropy at multiple timesteps, exits 0

# Check new features are available
julia --project -e '
  using QuantumCircuitsMPS
  
  # New Measurement gate
  m = Measurement(:Z)
  println("Measurement(:Z) ✓")
  
  # EntanglementEntropy observable
  println(list_observables())
  # Expected: ["DomainWall", "BornProbability", "EntanglementEntropy"]
'
```

### Final Checklist
- [x] `Measurement(:Z)` gate is FUNDAMENTAL (pure Born + projection)
- [x] `Reset` is DERIVED (uses Measurement + conditional X)
- [x] EntanglementEntropy observable follows DomainWall API pattern
- [x] MIPT example uses `Measurement(:Z)`, NOT `Reset()`
- [x] mipt_example.jl runs without error
- [x] mipt_tutorial.ipynb is valid JSON
- [x] All existing tests still pass
- [x] No deprecated `current_state()` pattern used
