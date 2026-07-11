using Pkg

# Make this script self-sufficient: `julia --project=docs docs/make.jl` must
# work standalone (no separate instantiate step required), since Manifest.toml
# is intentionally not tracked in this repo.
Pkg.develop(PackageSpec(path=dirname(@__DIR__)))
Pkg.instantiate()

using Documenter
using QuantumCircuitsMPS

makedocs(;
    modules=[QuantumCircuitsMPS],
    authors="Haining Pan <haining.pan.physics@gmail.com>, Jedediah H Pixley <jed.pixley@physics.rutgers.edu>",
    sitename="QuantumCircuitsMPS.jl",
    format=Documenter.HTML(;
        canonical="https://hainingpan.github.io/QuantumCircuitsMPS.jl",
        edit_link="dev",
        assets=String[],
        # T5 originally raised these to 500/300 KiB to accommodate a single
        # api.md page with the ENTIRE @autodocs (public + private) dump. T30
        # split content across design.md/backends/*.md/tutorials.md/api.md/
        # internals.md; the largest remaining page (internals.md, the
        # `Public=false` catch-all) now renders at ~170 KiB — lowered back
        # toward (but still comfortably above) Documenter's 200 KiB default
        # so future docstring growth doesn't trip `warnonly=false`'s hard-
        # error promotion of the size-threshold warning.
        size_threshold=250 * 1024,
        size_threshold_warn=220 * 1024,
    ),
    pages=[
        "Home" => "index.md",
        "Design Philosophy" => "design.md",
        "Backends" => [
            "backends/mps.md",
            "backends/statevector.md",
            "backends/clifford.md",
        ],
        "Tutorials" => "tutorials.md",
        "Custom Observables" => "custom_observables.md",
        "API Reference" => "api.md",
        "Private / Internal API" => "internals.md",
        "Developer Docs" => [
            "devdocs/backend_interface.md",
        ],
    ],
    # T30 (v0.4.0): docstring coverage is complete (every exported symbol
    # documented, every unexported docstring reachable via internals.md's
    # `@autodocs Public=false` block) — missing_docs is now a HARD ERROR.
    warnonly=false,
    doctest=true,
)

deploydocs(;
    repo="github.com/hainingpan/QuantumCircuitsMPS.jl.git",
    devbranch="dev",
)
