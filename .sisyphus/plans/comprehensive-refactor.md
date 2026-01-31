# Comprehensive Repository Refactor v2

## TL;DR

> **Quick Summary**: Three-level cleanup of QuantumCircuitsMPS.jl - archive messy history to separate branch, create clean `main` and `dev` branches (both identical initially), keep only CIPT + MIPT examples, refactor code.
>
> **Deliverables**:
> - `archive` branch with full messy history + legacy files
> - Clean `main` branch tagged v0.0.1
> - Clean `dev` branch (identical to main, for ongoing development)
> - Only 4 example files: cipt_example.jl, cipt_tutorial.ipynb, mipt_example.jl, mipt_tutorial.ipynb
> - 843 lines of deprecated code deleted
> - Refactored code with shared helpers
>
> **Estimated Effort**: Large (multi-session)
> **Parallel Execution**: YES - 3 waves
> **Critical Path**: Phase 1 (Git) → Phase 2 (Examples) → Phase 3 (Delete Deprecated) → Phase 4-5 (Refactors)

---

## Context

### Original Request
User wants comprehensive cleanup after extensive development:
1. Clean git history for release (v0.0.1, NOT v1.0.0)
2. Both `main` AND `dev` should have clean refactored code
3. Messy history goes to `archive` branch
4. Keep ONLY 2 physics models: CIPT and MIPT examples
5. Delete deprecated code and reduce complexity

### Interview Summary
**Key Corrections from User**:
- Version: **v0.0.1** (not v1.0.0 - early stage software)
- `dev` is NOT a garbage can - it should have clean code too
- Archive branch (`archive`) for messy history
- Only CIPT + MIPT examples in main/dev
- `circuit_tutorial` content should merge into `cipt_tutorial.ipynb`
- Canonical CIPT pattern: `StaircaseLeft(1)` for Reset, `StaircaseRight(1)` for HaarRandom

**Research Findings**:
- Librarian: Trunk-based development recommended for Julia packages
- Librarian: Use tags for archiving, not orphan branches
- Explorer: 12 example files exist, only 2 physics models needed
- Explorer: `ct_model.jl` uses wrong step size (L instead of 1)

### Metis Review
**Gaps Addressed**:
- No remote configured → Will add remote
- Dirty working tree → Commit to archive branch first
- No .gitignore → Will create
- CIPT pattern inconsistency → Will fix to step=1

### Pre-requisite Work Completed (circuit-engine-mipt plan)
**Status**: ✅ COMPLETED on 2026-01-31

The following work was completed as a prerequisite before this refactor:
1. ✅ Extended `simulate!` for Bricklayer/AllSites compound geometries
2. ✅ Extended `expand_circuit` for Bricklayer/AllSites compound geometries  
3. ✅ Added tests for compound geometry circuit execution (244 tests passing)
4. ✅ Rewrote `mipt_example.jl` to use Circuit do-block API
5. ✅ Fixed `mipt_tutorial.ipynb` to use correct API
6. ✅ Full test suite verification
7. ✅ Clarified EntanglementEntropy docstring for Hartley entropy

**Commit**: `feat(circuit): extend simulate! and expand_circuit for Bricklayer/AllSites geometries`

**Current State**:
- MIPT examples (`mipt_example.jl`, `mipt_tutorial.ipynb`) are now correct and working
- All 244 tests passing (up from 212)
- Ready for Phase 1: Git Restructure

---

## Work Objectives

### Core Objective
Create clean, parallel `main` and `dev` branches with only essential physics examples (CIPT + MIPT), while preserving full development history in an archive branch.

### Concrete Deliverables
1. `archive` branch: Full 61+ commit history, all .sisyphus, all legacy examples
2. `main` branch: Clean code, v0.0.1 tag, only CIPT+MIPT examples
3. `dev` branch: Identical to main initially, for ongoing development
4. 4 example files total: cipt_example.jl, cipt_tutorial.ipynb, mipt_example.jl, mipt_tutorial.ipynb
5. No `src/_deprecated/` directory
6. Shared compound geometry helpers extracted
7. Reduced complexity in simulate!/expand_circuit

### Definition of Done
- [ ] `git branch --list` shows `main`, `dev`, `archive`
- [ ] `git tag --list` shows `v0.0.1` and `pre-refactor`
- [ ] `ls examples/*.jl examples/*.ipynb | wc -l` outputs `4`
- [ ] `test ! -d src/_deprecated` returns success
- [ ] `julia --project -e 'using Pkg; Pkg.test()'` passes
- [ ] `.gitignore` contains `.sisyphus/`

### Must Have
- All existing tests pass after refactor
- Full history preserved in archive branch
- Clean identical code in both main and dev
- Only CIPT + MIPT physics examples

### Must NOT Have (Guardrails)
- NO v1.0.0 version (use v0.0.1)
- NO treating dev as garbage can (dev = clean code)
- NO legacy examples in main/dev
- NO new features during refactor
- NO API changes
- NO force push without explicit confirmation

---

## Verification Strategy

### Test Decision
- **Infrastructure exists**: YES
- **Approach**: TDD - tests must pass after each phase
- **Command**: `julia --project -e 'using Pkg; Pkg.test()'`

---

## Execution Strategy

### Parallel Execution Waves

```
Wave 1 (Sequential - Git Setup):
├── 1.1 Commit dirty files to current branch
├── 1.2 Create archive branch + tag
├── 1.3 Create orphan main branch
├── 1.4 Create .gitignore
└── 1.5 Add remote

Wave 2 (After Git Setup):
├── 2.1 Consolidate examples (CIPT + MIPT only)
├── 2.2 Delete deprecated code
└── 2.3 Clean up stale files

Wave 3 (After Cleanup):
├── 3.1 Extract compound geometry helpers
├── 3.2 Refactor complexity (best effort)
├── 4.1 Create dev branch from main
└── 4.2 Push all branches

Critical Path: 1.x → 2.x → 3.x → 4.x
```

---

## TODOs

---

### Phase 1: Git Restructure

- [ ] 1.1. Commit all dirty files to current branch

  **What to do**:
  - Stage all modified and untracked files
  - Commit with message: `chore: archive development session state`
  - This preserves all work-in-progress before branching

  **Must NOT do**:
  - Do not selectively commit
  - Do not push yet

  **Recommended Agent Profile**:
  - **Category**: `quick`
  - **Skills**: [`git-master`]

  **Parallelization**:
  - **Blocked By**: None (first task)
  - **Blocks**: 1.2

  **References**:
  - Current state: `git status` shows 38 dirty files

  **Acceptance Criteria**:
  ```bash
  git status --porcelain | wc -l
  # Assert: Output is "0"
  ```

  **Commit**: YES
  - Message: `chore: archive development session state`
  - Files: All (`git add -A`)

---

- [ ] 1.2. Create archive branch and safety tag

  **What to do**:
  - Create tag `pre-refactor` at current HEAD
  - Create branch `archive` at current HEAD
  - This preserves the full messy history

  **Must NOT do**:
  - Do not delete main yet
  - Do not push yet

  **Recommended Agent Profile**:
  - **Category**: `quick`
  - **Skills**: [`git-master`]

  **Parallelization**:
  - **Blocked By**: 1.1
  - **Blocks**: 1.3

  **References**:
  - Current branch: `main` with 62+ commits after 1.1

  **Acceptance Criteria**:
  ```bash
  git tag --list | grep "pre-refactor"
  # Assert: Shows "pre-refactor"
  
  git branch --list | grep "archive"
  # Assert: Shows "archive"
  ```

  **Commit**: NO (tag/branch only)

---

- [ ] 1.3. Create clean orphan main branch

  **What to do**:
  - Rename current main: `git branch -m main old-main`
  - Create orphan: `git checkout --orphan main`
  - Reset staging: `git reset --hard`
  - Checkout files from old-main: `git checkout old-main -- .`
  - Remove from staging (do NOT delete from filesystem yet):
    - `.sisyphus/` (will be gitignored)
    - `src/_deprecated/`
    - All legacy examples (keep only mipt_example.jl, mipt_tutorial.ipynb, ct_model.jl, circuit_tutorial.ipynb for now)
  - Do NOT commit yet (Phase 2 will modify examples first)

  **Must NOT do**:
  - Do not delete files from filesystem
  - Do not commit yet

  **Recommended Agent Profile**:
  - **Category**: `quick`
  - **Skills**: [`git-master`]

  **Parallelization**:
  - **Blocked By**: 1.2
  - **Blocks**: Phase 2

  **References**:
  - Orphan branch: Creates branch with no parent commits

  **Acceptance Criteria**:
  ```bash
  git branch --list | grep -E "main|old-main|archive"
  # Assert: Shows main, old-main, archive
  ```

  **Commit**: NO (staging only)

---

- [ ] 1.4. Create .gitignore file

  **What to do**:
  - Create `.gitignore` with Julia + OpenCode patterns:
    ```gitignore
    # Julia
    *.jl.cov
    *.jl.*.cov
    *.jl.mem
    Manifest.toml
    docs/build/
    
    # OpenCode session artifacts
    .sisyphus/
    
    # IDE
    .vscode/
    .idea/
    
    # OS
    .DS_Store
    Thumbs.db
    
    # Generated outputs
    examples/output/
    *.bin
    ```
  - Stage the file: `git add .gitignore`

  **Must NOT do**:
  - Do not commit yet

  **Recommended Agent Profile**:
  - **Category**: `quick`
  - **Skills**: []

  **Parallelization**:
  - **Blocked By**: 1.3
  - **Blocks**: Phase 2

  **References**:
  - Standard Julia .gitignore patterns

  **Acceptance Criteria**:
  ```bash
  test -f .gitignore && grep ".sisyphus/" .gitignore
  # Assert: File exists and contains .sisyphus/
  ```

  **Commit**: NO (will be part of Phase 2 commit)

---

- [ ] 1.5. Add GitHub remote

  **What to do**:
  - Add remote: `git remote add origin https://github.com/hainingpan/QuantumCircuitsMPS.jl.git`

  **Must NOT do**:
  - Do not push yet

  **Recommended Agent Profile**:
  - **Category**: `quick`
  - **Skills**: [`git-master`]

  **Parallelization**:
  - **Blocked By**: 1.4
  - **Blocks**: Phase 4

  **References**:
  - GitHub URL: `https://github.com/hainingpan/QuantumCircuitsMPS.jl.git`

  **Acceptance Criteria**:
  ```bash
  git remote -v | grep "origin"
  # Assert: Shows the GitHub URL
  ```

  **Commit**: NO

---

### Phase 2: Consolidate Examples

- [ ] 2.1. Rename ct_model.jl to cipt_example.jl and fix pattern

  **What to do**:
  - Rename: `examples/ct_model.jl` → `examples/cipt_example.jl`
  - **CRITICAL**: Fix the staircase step size:
    - Change `StaircaseLeft(L)` → `StaircaseLeft(1)`
    - Change `StaircaseRight(L)` → `StaircaseRight(1)`
  - Update any comments to say "CIPT" instead of "CT Model"

  **Must NOT do**:
  - Do not change the physics logic
  - Do not change observable tracking

  **Recommended Agent Profile**:
  - **Category**: `quick`
  - **Skills**: []

  **Parallelization**:
  - **Blocked By**: Phase 1
  - **Blocks**: 2.3

  **References**:
  - Source: `examples/ct_model.jl`
  - Canonical pattern (from circuit_tutorial.jl lines 69-70):
    ```julia
    (probability=p_reset, gate=Reset(), geometry=StaircaseLeft(1)),
    (probability=1-p_reset, gate=HaarRandom(), geometry=StaircaseRight(1))
    ```

  **Acceptance Criteria**:
  ```bash
  test -f examples/cipt_example.jl && echo "EXISTS"
  # Assert: EXISTS
  
  grep "StaircaseLeft(1)" examples/cipt_example.jl
  # Assert: Shows the corrected pattern
  
  test ! -f examples/ct_model.jl && echo "RENAMED"
  # Assert: RENAMED
  ```

  **Commit**: NO (part of Phase 2 combined commit)

---

- [ ] 2.2. Create cipt_tutorial.ipynb from circuit_tutorial.ipynb

  **What to do**:
  - Rename: `examples/circuit_tutorial.ipynb` → `examples/cipt_tutorial.ipynb`
  - Update title/headers to say "CIPT Tutorial" instead of "Circuit Tutorial"
  - Ensure it uses the canonical CIPT pattern (step=1)
  - Clear cell outputs for clean notebook

  **Must NOT do**:
  - Do not change the tutorial structure
  - Do not remove educational content

  **Recommended Agent Profile**:
  - **Category**: `quick`
  - **Skills**: []

  **Parallelization**:
  - **Blocked By**: Phase 1
  - **Blocks**: 2.3

  **References**:
  - Source: `examples/circuit_tutorial.ipynb`
  - Already uses correct pattern (lines 152-153 in JSON)

  **Acceptance Criteria**:
  ```bash
  test -f examples/cipt_tutorial.ipynb && echo "EXISTS"
  # Assert: EXISTS
  
  test ! -f examples/circuit_tutorial.ipynb && echo "RENAMED"
  # Assert: RENAMED
  ```

  **Commit**: NO (part of Phase 2 combined commit)

---

- [ ] 2.3. Remove legacy examples from staging

  **What to do**:
  - Remove these files from git staging (they stay on filesystem but won't be committed to clean branches):
    - `examples/circuit_tutorial.jl` (superseded by cipt_tutorial.ipynb)
    - `examples/ct_model_styles.jl`
    - `examples/ct_model_circuit_style.jl`
    - `examples/ct_model_simulation_styles.jl`
    - `examples/monitored_circuit.jl`
    - `examples/monitored_circuit_dw.jl`
    - `examples/verify_ct_match.jl`
    - `examples/ct_model_v0.jl.tmp`
    - `examples/ct_model_v1.jl.tmp`
    - `examples/ct_results.bin`
    - `examples/examples/` (nested directory)
    - `examples/output/` (generated artifacts)

  **Must NOT do**:
  - Do not delete from filesystem (they exist in archive branch)
  - Keep: mipt_example.jl, mipt_tutorial.ipynb, cipt_example.jl, cipt_tutorial.ipynb

  **Recommended Agent Profile**:
  - **Category**: `quick`
  - **Skills**: [`git-master`]

  **Parallelization**:
  - **Blocked By**: 2.1, 2.2
  - **Blocks**: 2.4

  **References**:
  - Files to keep: 4 (cipt_example.jl, cipt_tutorial.ipynb, mipt_example.jl, mipt_tutorial.ipynb)

  **Acceptance Criteria**:
  ```bash
  git ls-files examples/ | wc -l
  # Assert: 4 files staged
  
  git ls-files examples/ | sort
  # Assert: cipt_example.jl, cipt_tutorial.ipynb, mipt_example.jl, mipt_tutorial.ipynb
  ```

  **Commit**: NO (part of Phase 2 combined commit)

---

- [ ] 2.4. Delete src/_deprecated/ from staging

  **What to do**:
  - Remove from staging: `git rm -rf --cached src/_deprecated/`
  - This removes 843 lines of deprecated code from clean branches

  **Must NOT do**:
  - Do not delete from filesystem
  - Do not remove any non-deprecated code

  **Recommended Agent Profile**:
  - **Category**: `quick`
  - **Skills**: [`git-master`]

  **Parallelization**:
  - **Blocked By**: 2.3
  - **Blocks**: 2.5

  **References**:
  - 12 files in src/_deprecated/ (843 lines)

  **Acceptance Criteria**:
  ```bash
  git ls-files src/_deprecated/ | wc -l
  # Assert: 0
  ```

  **Commit**: NO (part of combined commit)

---

- [ ] 2.5. Remove deprecated reference from probabilistic.jl

  **What to do**:
  - Edit `src/API/probabilistic.jl`
  - Remove line 9: `# - src/_deprecated/probabilistic_styles/ (alternative implementations)`

  **Must NOT do**:
  - Do not change functional code

  **Recommended Agent Profile**:
  - **Category**: `quick`
  - **Skills**: []

  **Parallelization**:
  - **Blocked By**: 2.4
  - **Blocks**: 2.6

  **References**:
  - File: `src/API/probabilistic.jl:9`

  **Acceptance Criteria**:
  ```bash
  grep "_deprecated" src/API/probabilistic.jl || echo "CLEANED"
  # Assert: CLEANED
  ```

  **Commit**: NO (part of combined commit)

---

- [ ] 2.6. Commit clean main branch with v0.0.1 tag

  **What to do**:
  - Stage all prepared changes
  - Commit: `git commit -m "v0.0.1: Clean release with CIPT + MIPT examples"`
  - Tag: `git tag v0.0.1`
  - Run tests to verify

  **Must NOT do**:
  - Do not use v1.0.0

  **Recommended Agent Profile**:
  - **Category**: `quick`
  - **Skills**: [`git-master`]

  **Parallelization**:
  - **Blocked By**: 2.5
  - **Blocks**: Phase 3

  **References**:
  - Version: v0.0.1 (NOT v1.0.0)

  **Acceptance Criteria**:
  ```bash
  git log main --oneline | head -1
  # Assert: Shows v0.0.1 commit
  
  git tag --list | grep "v0.0.1"
  # Assert: Shows v0.0.1
  
  julia --project -e 'using Pkg; Pkg.test()'
  # Assert: All tests pass
  ```

  **Commit**: YES
  - Message: `v0.0.1: Clean release with CIPT + MIPT examples`
  - Tag: `v0.0.1`

---

### Phase 3: Code Refactoring

- [ ] 3.1. Extract compound geometry helpers to shared module

  **What to do**:
  - Create `src/Geometry/compound.jl` with:
    - `is_compound_geometry(::AbstractGeometry)` → Bool
    - `get_compound_elements(geo, L, bc)` → Vector{Vector{Int}}
  - Update `src/Circuit/execute.jl`: Remove local definitions, use shared
  - Update `src/Circuit/expand.jl`: Remove `_expand` suffix versions, use shared
  - Update `src/Geometry/Geometry.jl`: Include and export new functions

  **Must NOT do**:
  - Do not change function signatures
  - Do not change behavior

  **Recommended Agent Profile**:
  - **Category**: `unspecified-low`
  - **Skills**: []

  **Parallelization**:
  - **Blocked By**: Phase 2
  - **Blocks**: 3.2

  **References**:
  - Duplicate in execute.jl: lines 4-31
  - Duplicate in expand.jl: lines 9-36
  - Target: `src/Geometry/compound.jl`

  **Acceptance Criteria**:
  ```bash
  test -f src/Geometry/compound.jl && echo "CREATED"
  # Assert: CREATED
  
  grep "is_compound_geometry_expand" src/Circuit/expand.jl || echo "REMOVED"
  # Assert: REMOVED
  
  julia --project -e 'using Pkg; Pkg.test()'
  # Assert: All tests pass
  ```

  **Commit**: YES
  - Message: `refactor: extract compound geometry helpers to shared module`

---

- [ ] 3.2. Refactor simulate! complexity (best effort)

  **What to do**:
  - Extract repeated recording logic to helper functions
  - Reduce nesting where possible with early returns
  - Goal: Improve readability, not perfection

  **Must NOT do**:
  - Do not change behavior
  - Do not spend excessive time (best effort)

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
  - **Skills**: []

  **Parallelization**:
  - **Blocked By**: 3.1
  - **Blocks**: Phase 4

  **References**:
  - File: `src/Circuit/execute.jl:128-287` (160 lines)
  - Recording patterns: lines 161-169, 206-216, 225-228, 257-269

  **Acceptance Criteria**:
  ```bash
  julia --project -e 'using Pkg; Pkg.test()'
  # Assert: All tests pass
  ```

  **Commit**: YES
  - Message: `refactor: reduce complexity in simulate!`

---

### Phase 4: Finalize Branches and Push

- [ ] 4.1. Create dev branch from main

  **What to do**:
  - Create dev branch: `git branch dev main`
  - Both branches now have identical clean code

  **Must NOT do**:
  - Do not put messy code in dev

  **Recommended Agent Profile**:
  - **Category**: `quick`
  - **Skills**: [`git-master`]

  **Parallelization**:
  - **Blocked By**: Phase 3
  - **Blocks**: 4.2

  **Acceptance Criteria**:
  ```bash
  git branch --list | grep -E "main|dev"
  # Assert: Both branches exist
  
  git log main --oneline | head -1
  git log dev --oneline | head -1
  # Assert: Same commit on both
  ```

  **Commit**: NO (branch only)

---

- [ ] 4.2. Delete old-main branch

  **What to do**:
  - Delete: `git branch -D old-main`
  - Only archive keeps the messy history now

  **Must NOT do**:
  - Do not delete archive

  **Recommended Agent Profile**:
  - **Category**: `quick`
  - **Skills**: [`git-master`]

  **Parallelization**:
  - **Blocked By**: 4.1
  - **Blocks**: 4.3

  **Acceptance Criteria**:
  ```bash
  git branch --list | grep "old-main" || echo "DELETED"
  # Assert: DELETED
  ```

  **Commit**: NO

---

- [ ] 4.3. Push all branches (with user confirmation)

  **What to do**:
  - **ASK USER BEFORE PUSHING**
  - Push main: `git push -u origin main`
  - Push dev: `git push -u origin dev`
  - Push archive: `git push -u origin archive`
  - Push tags: `git push --tags`

  **Must NOT do**:
  - Do not force push
  - Do not push without user confirmation

  **Recommended Agent Profile**:
  - **Category**: `quick`
  - **Skills**: [`git-master`]

  **Parallelization**:
  - **Blocked By**: 4.2
  - **Blocks**: None (final)

  **Acceptance Criteria**:
  ```bash
  git ls-remote --heads origin
  # Assert: Shows main, dev, archive
  
  git ls-remote --tags origin
  # Assert: Shows v0.0.1 and pre-refactor
  ```

  **Commit**: NO (push only)

---

## Commit Strategy

| Phase | After Task | Message | Tag |
|-------|------------|---------|-----|
| 1 | 1.1 | `chore: archive development session state` | - |
| 2 | 2.6 | `v0.0.1: Clean release with CIPT + MIPT examples` | `v0.0.1` |
| 3 | 3.1 | `refactor: extract compound geometry helpers to shared module` | - |
| 3 | 3.2 | `refactor: reduce complexity in simulate!` | - |

---

## Success Criteria

### Final Branch Structure
```
archive     main (v0.0.1)        dev
        │                      │                │
        │                      │                │
   [62 commits]           [3 commits]     [3 commits]
   [full history]         [clean code]    [clean code]
   [all .sisyphus]        [.gitignored]   [.gitignored]
   [all examples]         [4 examples]    [4 examples]
```

### Verification Commands
```bash
# Branch structure
git branch --list
# Expected: archive, dev, main

# Tags
git tag --list
# Expected: pre-refactor, v0.0.1

# Examples count
ls examples/*.jl examples/*.ipynb | wc -l
# Expected: 4

# No deprecated code
test ! -d src/_deprecated && echo "CLEAN"
# Expected: CLEAN

# Tests pass
julia --project -e 'using Pkg; Pkg.test()'
# Expected: All pass
```

---

## Disk Memory (For Future Reference)

**IMPORTANT CONVENTIONS ESTABLISHED**:

1. **Version**: v0.0.1 (early stage, not v1.0.0)
2. **Branch Strategy**: 
   - `main` = release (clean, tagged)
   - `dev` = development (clean, same base as main)
   - `archive/*` = historical preservation
3. **Examples Policy**: Only CIPT + MIPT physics examples
4. **CIPT Canonical Pattern**: 
   ```julia
   StaircaseLeft(1) for Reset
   StaircaseRight(1) for HaarRandom
   # step=1, NOT step=L
   ```
5. **.sisyphus**: Always gitignored, never in main/dev
