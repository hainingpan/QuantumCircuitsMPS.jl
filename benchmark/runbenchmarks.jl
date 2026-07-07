# Runner for the QuantumCircuitsMPS.jl benchmark suite (see benchmarks.jl for scope).
#
# Usage:
#   julia --project=benchmark benchmark/runbenchmarks.jl [output.json]
#
# Runs SUITE and writes BenchmarkTools-format JSON results to
# benchmark/results/baseline-<shortsha>.json (or to the explicit [output.json]
# argument), and prints a human-readable median table to stdout.
#
# Compare two result files later with:
#   using BenchmarkTools
#   a = BenchmarkTools.load("old.json")[1]; b = BenchmarkTools.load("new.json")[1]
#   judge(median(b), median(a))

using Pkg
Pkg.activate(@__DIR__)
Pkg.develop(PackageSpec(path = dirname(@__DIR__)))
Pkg.instantiate()

using BenchmarkTools

include(joinpath(@__DIR__, "benchmarks.jl"))

const RESULTS = run(SUITE; verbose = true)

shortsha = try
    strip(read(`git -C $(dirname(@__DIR__)) rev-parse --short HEAD`, String))
catch
    "unknown"
end

outpath = if isempty(ARGS)
    joinpath(@__DIR__, "results", "baseline-$(shortsha).json")
else
    abspath(ARGS[1])
end
mkpath(dirname(outpath))
BenchmarkTools.save(outpath, RESULTS)

println()
println("Benchmark medians (commit $(shortsha)):")
println(rpad("benchmark", 62), lpad("median time", 14), lpad("memory", 14),
    lpad("allocs", 10))
println("-"^100)
for (keys, trial) in sort(collect(BenchmarkTools.leaves(RESULTS));
    by = p -> join(first(p), "/"))
    m = median(trial)
    println(rpad(join(keys, "/"), 62),
        lpad(BenchmarkTools.prettytime(time(m)), 14),
        lpad(BenchmarkTools.prettymemory(memory(m)), 14),
        lpad(string(allocs(m)), 10))
end
println("-"^100)
println("Results written to: $(outpath)")
