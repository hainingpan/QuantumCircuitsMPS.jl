# Learnings: SVG Notebook Fixes v3

## Conventions & Patterns

## Architectural Decisions

## Technical Gotchas

## Task 1: SVG Auto-Display Implementation

### Luxor API Pattern
- `Drawing(width, height, :svg)` creates in-memory SVG context (no filename)
- `Drawing(width, height, filename)` writes to file
- Call sequence: `Drawing()` → drawing operations → `finish()` → `svgstring()`
- **CRITICAL**: `svgstring()` must be called AFTER `finish()`, extracts from implicit global context

### Julia Extension Module Patterns
- Extensions cannot export types to parent module
- Types defined in extensions are extension-local
- Access pattern: return value duck typing or `typeof(obj).name.name` comparison
- MIME show methods work for auto-display without explicit exports

### Jupyter/IJulia Display Protocol
- Implement `Base.show(io::IO, ::MIME"image/svg+xml", img::CustomType)`
- Write SVG string directly to io: `write(io, img.data)`
- Enables automatic inline rendering in notebooks

### SVG Text Rendering
- Luxor converts text to SVG glyph paths (not `<text>` elements)
- Tests should check for glyph references, not literal text strings
- Example: "q1" becomes `glyph-0-0` (q) + `glyph-0-1` (1) references

## Task 2: Demo A/B Circuit API Rewrite (2026-01-30)

Successfully rewrote Demo A and Demo B cells to use Circuit API pattern with `simulate!()`.

### Key Pattern Implemented
```julia
demo_circuit = Circuit(L=4, bc=:periodic, n_steps=1) do c
    apply!(c, HaarRandom(), StaircaseRight(1))
end

state = SimulationState(L=4, bc=:periodic, rng=RNGRegistry(ctrl=1, proj=2, haar=3, born=4))
initialize!(state, ProductState(x0=1//16))
track!(state, :dw => DomainWall(; order=1, i1_fn=() -> 1))

simulate!(demo_circuit, state; n_circuits=3, record_initial=false, record_every=N)
```

### Recording Formula Verified
- `record_every=1` → Records at circuits 1, 2, 3 (3 recordings)
- `record_every=3` → Records at circuit 1 (since (1-1)%3==0) and circuit 3 (final) (2 recordings)
- Formula: `(circuit_idx - 1) % record_every == 0` OR `circuit_idx == n_circuits`

### Demo Distinction
- **Demo A**: Dense recording (`record_every=1`) - captures every circuit execution
- **Demo B**: Sparse recording (`record_every=3`) - captures strategic snapshots

### Test Results
All automated tests passed:
- Demo A: 3 recordings verified ✓
- Demo B: 2 recordings verified ✓

## Task 3: Notebook Cell Cleanup
- **Pattern**: JSON-based cell deletion by source content matching
- **Approach**: Load notebook as JSON, identify cells by exact source string match
- **Key Insight**: Deleting in reverse order (highest index first) prevents index shifting issues
- **Section Renumbering**: Simple string replacement in markdown cells works reliably
- **Validation**: Python JSON module provides robust structure validation
