# API Refinement - Decisions

## [2026-01-29T06:40:00Z] Task: api-refinement-final

### Architecture Decisions

#### 1. Probabilistic API Naming
**Decision**: Rename `apply_branch!` → `apply_with_prob!`
**Rationale**: 
- "with_prob" is more descriptive for physicists
- Clearer that it's about probabilistic selection
- "branch" could be confused with other concepts (git, control flow)

#### 2. Probability Sum Semantics
**Decision**: Allow sum ≤ 1 with implicit "do nothing" branch
**Rationale**:
- Common pattern in quantum circuits (measurement + post-selection)
- Avoids boilerplate Identity gates
- More intuitive for physicists

**Implementation**:
```julia
if total_prob > 1.0 + 1e-10
    error("Probabilities sum to $total_prob (must be ≤ 1)")
end
# ... if r >= sum(probs), do nothing
```

#### 3. DomainWall i1_fn Design
**Decision**: Add optional `i1_fn::Union{Function, Nothing}` field
**Rationale**:
- Sampling site calculation is constant for a simulation
- Passing it repeatedly in every `record!` call is repetitive
- Optional field maintains backwards compatibility

**Alternative Considered**: Make `i1_fn` required
**Rejected Because**: Would break existing code using explicit `i1`

#### 4. record! Signature
**Decision**: Keep `i1` as optional parameter, check `i1_fn` first
**Rationale**:
- Backwards compatible with existing `record!(state; i1=...)`
- DomainWall with `i1_fn` gets clean API: `record!(state)`
- Clear error when neither provided

#### 5. Backwards Compatibility Strategy
**Decision**: Keep `apply_branch!` as deprecated alias
**Rationale**:
- Existing user code continues working
- Deprecation warning guides users to new API
- `maxlog=1` prevents warning spam

**Alternative Considered**: Remove `apply_branch!` entirely
**Rejected Because**: Would break user code, bad for adoption

### Trade-offs

#### Verbosity vs. Clarity
- **Chose**: Clarity (named parameters in Style C)
- **Trade-off**: More typing, but self-documenting code
- **Result**: User selected this style despite verbosity

#### Flexibility vs. Simplicity
- **Chose**: Flexibility (optional `i1_fn` in DomainWall)
- **Trade-off**: Two ways to achieve same thing (i1_fn vs explicit i1)
- **Result**: Both patterns supported for different use cases

### Lessons Learned

1. **User feedback is critical**: Initial API worked, but refinements made it much cleaner
2. **Backwards compatibility pays off**: Deprecated aliases prevent user pain
3. **Optional function parameters**: `Union{Function, Nothing}` pattern is powerful for Julia
4. **Atomic commits matter**: Separate core changes from examples for clean history
