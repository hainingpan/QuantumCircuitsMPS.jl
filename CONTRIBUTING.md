# Contributing to QuantumCircuitsMPS.jl

Thanks for considering a contribution. This project follows the
[SciML/ColPrac](https://github.com/SciML/ColPrac) collaborative practices
guide for general workflow, communication, and conduct expectations — read
that first if you're new to contributing to a Julia package. The notes below
cover what's specific to this repository.

## Branch model

- `main` is the release branch. Every commit on `main` is a tagged release.
- `dev` is the main development branch. It is always ahead of (or equal to)
  the latest `main` release.
- New work happens on a feature branch forked from `dev`, named
  `feat/<short-name>`, `fix/<short-name>`, or similar.
- When a feature is done, it is merged (not squashed) into `dev`.
- Periodically, `dev` is squashed into a single commit and merged into `main`
  for release, then tagged (`git tag vX.Y.Z`, pushed with `git push --tags`
  — tags must be pushed explicitly, a commit message alone does not create a
  GitHub release).
- Not everything that lands on `dev` belongs on `main`: `main` should only
  contain what a user of the released package needs to see. Development,
  debug, and trial-and-error artifacts (scratch notebooks, in-progress audit
  files, etc.) stay on `dev`.

### Commit message format

- On `main`: `[version]: [description]`, e.g. `v0.4.0: quality/hardening pass, arbitrary spin-S`.
- On every other branch: `<type>(<scope>): <description>`, e.g.
  `feat(observables): add MutualInformation`, `fix(clifford): reject non-Clifford gates`,
  `refactor(state): extract shared bit-pattern derivation`. Common types:
  `feat`, `fix`, `refactor`, `perf`, `test`, `docs`, `chore`, `ci`.

If you're opening a pull request, base it on `dev`, not `main`.

## Getting set up

```julia
using Pkg
Pkg.activate(".")
Pkg.instantiate()
using QuantumCircuitsMPS, Revise
```

Test-only dependencies live in `test/Project.toml` (not the root
`Project.toml`) — `Pkg.test()` instantiates that environment automatically.

## Running tests

```julia
using Pkg
Pkg.test()
```

or from the shell: `julia --project=. -e 'using Pkg; Pkg.test()'`.

Two opt-in environment flags extend the default suite (both default to off,
so the fast/default `Pkg.test()` run stays quick):

- `EXTENDED_TESTS=true` — runs golden bit-exact regression comparisons
  (`test/golden/golden_compare.jl`) against pre-refactor reference JSONs.
  Only meaningful when the underlying algorithms haven't intentionally
  changed; if you deliberately change output-affecting behavior, the golden
  files need regenerating (see `test/golden/generate_goldens.jl` — a
  deliberate, manual step, not something to run to "fix" a failing
  comparison).
- `JET_TEST=true` — runs `JET.report_package` static analysis
  (`test/quality/jet.jl`) against a documented, only-decreasing report-count
  ratchet. If your change fixes a JET-flagged issue, lower the ratchet in
  that file; never raise it to make a new issue pass.

```bash
EXTENDED_TESTS=true julia --project=. -e 'using Pkg; Pkg.test()'
JET_TEST=true julia --project=. -e 'using Pkg; Pkg.test()'
```

Every `Pkg.test()` run also includes `test/quality/aqua.jl`
(`Aqua.test_all`) and `test/quality/explicit_imports.jl` — these are
standing gates, not opt-in.

## Formatter

Code is formatted with [JuliaFormatter.jl](https://github.com/domluna/JuliaFormatter.jl)
using [SciML style](https://github.com/SciML/SciMLStyle), pinned to
JuliaFormatter **v2** (the repo is v2-formatted; running v1 against it will
report spurious diffs). Format before committing:

```julia
using Pkg
Pkg.add(Pkg.PackageSpec(name="JuliaFormatter", version="2"))
using JuliaFormatter
format(["src", "test", "ext"], SciMLStyle())
```

CI (`.github/workflows/format-check.yml`) runs the same check with
`overwrite=false` and fails the build if anything is unformatted.

## Docstring conventions

- Every exported public symbol needs a docstring; the Documenter build treats
  missing/broken `@docs` entries as a hard error, not a warning.
- Follow the existing style: a one-line summary, then a blank line, then
  details (arguments, keyword arguments, examples). See any of
  `src/Observables/*.jl` for the established pattern for gates/geometries/observables.
  Plain ` ```julia ` code blocks are fine; most docstrings in this repo are
  **not** doctested (`@example`/`@repl`), so keep examples illustrative and
  correct-by-inspection rather than relying on Documenter to execute them.
- Internal (un-exported) symbols that still carry a docstring are picked up
  by the `Public = false` autodocs block on the internal API docs page —
  documenting them is encouraged but not required.
- Build the docs locally before opening a PR that touches docstrings or `docs/`:

  ```bash
  julia --project=docs docs/make.jl
  ```

  A clean build exits `0` with no warnings (the build treats all Documenter
  warning categories as hard errors, not just missing docs).

## Reporting bugs / requesting features

Use [GitHub Issues](https://github.com/hainingpan/QuantumCircuitsMPS.jl/issues)
with the provided bug report / feature request templates.
