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
        # The single-page api.md @autodocs block (~100% export coverage) renders
        # well above Documenter's 200 KiB default threshold; raised here since
        # this is expected scaffold behavior, not a docs bloat regression.
        size_threshold=500 * 1024,
        size_threshold_warn=300 * 1024,
    ),
    pages=[
        "Home" => "index.md",
        "API Reference" => "api.md",
    ],
    # T30 tightens this to `false` once docstring coverage is finalized.
    warnonly=[:missing_docs],
    doctest=true,
)

deploydocs(;
    repo="github.com/hainingpan/QuantumCircuitsMPS.jl.git",
    devbranch="dev",
)
