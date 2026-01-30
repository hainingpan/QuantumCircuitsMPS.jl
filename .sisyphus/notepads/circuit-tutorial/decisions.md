# Circuit Tutorial - Decisions

## [2026-01-30T04:10:36Z] Initial Decisions

### Format Decision
- Creating BOTH `.jl` script AND `.ipynb` notebook (user choice)
- Script is canonical (tested, CI-ready)
- Notebook mirrors script structure for interactive use

### Content Scope
- Circuit API only (no imperative comparison - user excluded)
- BOTH ASCII and SVG visualization (user included both)
- Progressive structure: Build → Visualize → Simulate

### Technical Approach
- Follow `ct_model_circuit_style.jl` formatting (section separators, comment style)
- Use only built-in gates (Reset, HaarRandom, Hadamard, PauliX)
- Luxor section is opt-in (check availability, graceful degradation)
