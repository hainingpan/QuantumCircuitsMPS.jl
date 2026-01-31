# API Refinement - Learnings

## [2026-01-29T06:40:00Z] Task: api-refinement-final

### Key Decisions

1. **Renamed `apply_branch!` → `apply_with_prob!`**
   - More physically meaningful name
   - Better reflects the probabilistic nature of the operation
   - "with_prob" clearer than "branch" for quantum physics context

2. **Allow sum(probabilities) ≤ 1**
   - Implicit "do nothing" branch when sum < 1
   - Cleaner than requiring explicit Identity gates
   - Validated with error when sum > 1 + 1e-10

3. **DomainWall i1_fn parameter**
   - Captures sampling site function at registration time
   - Eliminates repetitive `i1` passing in every `record!` call
   - Optional for backwards compatibility

4. **Simplified record! API**
   - Automatically calls `i1_fn()` when available
   - Falls back to explicit `i1` parameter for backwards compat
   - Clear error messages when neither provided

### Implementation Patterns

#### Backwards Compatibility
```julia
# Deprecated function kept as alias
function apply_branch!(state; rng=:ctrl, outcomes)
    @warn "apply_branch! is deprecated, use apply_with_prob! instead" maxlog=1
    apply_with_prob!(state; rng=rng, outcomes=outcomes)
end
```

#### Optional Function Parameter
```julia
struct DomainWall <: AbstractObservable
    order::Int
    i1_fn::Union{Function, Nothing}  # Optional function
end

# Callable checks i1_fn first, falls back to explicit i1
function (dw::DomainWall)(state, i1::Union{Int, Nothing}=nothing)
    actual_i1 = if dw.i1_fn !== nothing
        dw.i1_fn()
    elseif i1 !== nothing
        i1
    else
        throw(ArgumentError("Need either i1_fn or i1"))
    end
    return domain_wall(state, actual_i1, dw.order)
end
```

### Verification Approach

1. **Unit tests for new semantics**
   - Test sum < 1 (do nothing branch)
   - Test sum > 1 (error)
   - Test DomainWall with/without i1_fn
   - Test record! with/without i1

2. **Integration tests**
   - Full simulation examples run
   - Physics verification (all styles produce identical results)
   - Backwards compatibility tests

### Atomic Commits Strategy

Split into 2 commits:
1. Core API changes (4 source files)
2. Example updates (2 example files)

This separation makes it easy to:
- Understand the scope of each change
- Revert examples without touching core
- Review API changes independently

### Success Metrics

✅ Module loads without error
✅ All examples run successfully
✅ Physics verification passes (identical results across styles)
✅ Backwards compatibility maintained
✅ Clean, physicist-friendly API achieved

### User Feedback Integration

User selected Style C (Named Parameters) from 4 options, then requested refinements:
- More physical naming
- Cleaner API for common patterns
- Remove verbose boilerplate

Final API achieves all goals while maintaining backwards compatibility.
