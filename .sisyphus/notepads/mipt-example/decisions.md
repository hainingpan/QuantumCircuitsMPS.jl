# Architectural Decisions - MIPT Example

## [2026-01-31T00:53:21] Gate Hierarchy
- `Measurement(:Z)` is FUNDAMENTAL (pure Born sampling + projection)
- `Reset` is DERIVED (Measurement + conditional X)
- Helper `_measure_single_site!()` is the reusable core operation

## [2026-01-31T00:53:21] EntanglementEntropy Design
- Optional `threshold` parameter with default 1e-16
- Keyword-only constructor
- Validates cut: 1 <= cut < L

## Task 3: EntanglementEntropy Observable (2026-01-31)

### Constructor Validation Strategy
- **Decision**: Validate cut >= 1 in constructor, cut < L at call time
- **Rationale**: cut >= 1 is state-independent (always true), cut < L depends on system size
- **Impact**: Earlier error detection for invalid cuts, consistent with other observables

### Threshold Default Value
- **Decision**: Use threshold=1e-16 (same as deprecated implementation)
- **Rationale**: Proven value from existing codebase, prevents log(0) issues
- **Impact**: Numerical stability for small singular values

### Helper Function Visibility
- **Decision**: Keep `_von_neumann_entropy` as internal helper (underscore prefix)
- **Rationale**: Not part of public API, implementation detail
- **Impact**: Clean public interface, flexibility to refactor internally

