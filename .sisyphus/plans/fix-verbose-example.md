# Fix Verbose Example Script

## TL;DR

> **Quick Summary**: Replace 194-line `examples/ct_model.jl` with ~55-line version that properly uses existing package API.
> 
> **Deliverables**: 
> - Updated `examples/ct_model.jl` (~55 lines instead of 194)
> 
> **Estimated Effort**: Quick (single file replacement)
> **Parallel Execution**: NO - single task

---

## Context

### The Problem
The current `examples/ct_model.jl` is 194 lines - LONGER than the original CT.jl reference (141 lines). This defeats the purpose of the package.

### Root Cause
The example manually reimplemented the algorithm instead of using existing abstractions like `born_probability()`, `apply!()`, `Projection()`, `PauliX()`, etc.

### The Fix
Use existing API properly:
- `born_probability(state, site, outcome)` - already exists
- `apply!(state, gate, geometry)` - already exists
- `Projection(outcome)` + `PauliX()` - already exists (this IS the Reset operation)
- Manual pointer tracking with `AdjacentPair(i)` and `SingleSite(i)` - simpler than bidirectional staircase

---

## TODOs

- [x] 1. Replace examples/ct_model.jl content

  **What to do**:
  Replace the entire file content with this concise version:

  ```julia
  # CT Model - Concise Version
  # Uses QuantumCircuitsMPS v2 API properly
  # Compare: CT.jl run_CT_MPS_C_m_T.jl is ~141 lines, this should be ~55 lines

  using Pkg; Pkg.activate(dirname(@__DIR__))
  using QuantumCircuitsMPS
  using JSON

  """
      run_dw_t(L, p_ctrl, p_proj, seed_C, seed_m) -> Dict

  Run CT model simulation. Reproduces CT.jl's random_control! algorithm.
  """
  function run_dw_t(L::Int, p_ctrl::Float64, p_proj::Float64, seed_C::Int, seed_m::Int)
      # Setup state with CT-compatible RNG
      rng = RNGRegistry(Val(:ct_compat), circuit=seed_C, measurement=seed_m)
      state = SimulationState(L=L, bc=:periodic, rng=rng)
      initialize!(state, ProductState(x0=1//2^L))
      
      # Pointer starts at L, DW results storage
      i, tf = L, 2*L^2
      dw = zeros(tf+1, 2)
      dw[1,:] = [DomainWall(order=1)(state, 1), DomainWall(order=2)(state, 1)]
      
      # Main simulation loop
      for t in 1:tf
          if rand(get_rng(rng, :ctrl)) < p_ctrl
              # CONTROL: measure → reset → move LEFT
              p_0 = born_probability(state, i, 0)
              outcome = rand(get_rng(rng, :born)) < p_0 ? 0 : 1
              apply!(state, Projection(outcome), SingleSite(i))
              outcome == 1 && apply!(state, PauliX(), SingleSite(i))  # Reset to |0⟩
              i = mod(i - 2, L) + 1  # Move left
          else
              # BERNOULLI: Haar → move RIGHT → optional projection
              apply!(state, HaarRandom(), AdjacentPair(i))
              i = mod(i, L) + 1  # Move right
              if p_proj > 0
                  for pos in [mod(i-2, L)+1, i]
                      if rand(get_rng(rng, :proj)) < p_proj
                          p_0 = born_probability(state, pos, 0)
                          outcome = rand(get_rng(rng, :born)) < p_0 ? 0 : 1
                          apply!(state, Projection(outcome), SingleSite(pos))
                      end
                  end
              end
          end
          dw[t+1,:] = [DomainWall(order=1)(state, (i%L)+1), DomainWall(order=2)(state, (i%L)+1)]
      end
      
      Dict("L"=>L, "p_ctrl"=>p_ctrl, "p_proj"=>p_proj, "seed_C"=>seed_C, 
           "seed_m"=>seed_m, "DW1"=>dw[:,1], "DW2"=>dw[:,2])
  end

  # Run verification
  if abspath(PROGRAM_FILE) == @__FILE__
      result = run_dw_t(10, 0.5, 0.0, 42, 123)
      mkpath(joinpath(dirname(@__DIR__), "examples/output"))
      open(joinpath(dirname(@__DIR__), "examples/output/ct_model_L10_sC42_sm123.json"), "w") do f
          JSON.print(f, result, 4)
      end
      println("Done! DW1[1:5]: ", result["DW1"][1:5])
  end
  ```

  **Acceptance Criteria**:
  - [ ] File is ~55 lines (not 194)
  - [ ] Run `julia examples/ct_model.jl` completes without error
  - [ ] Run `julia test/verify_ct_match.jl` still passes (relative error < 1e-5)

  **Commit**: YES
  - Message: `refactor(examples): reduce ct_model.jl from 194 to ~55 lines using proper API`
  - Files: `examples/ct_model.jl`

---

## Success Criteria

```bash
# Line count should be ~55, not 194
wc -l examples/ct_model.jl  # Expected: ~55

# Should still produce correct physics
julia examples/ct_model.jl  # Expected: completes without error

# Verification should still pass
julia test/verify_ct_match.jl  # Expected: relative error < 1e-5
```
