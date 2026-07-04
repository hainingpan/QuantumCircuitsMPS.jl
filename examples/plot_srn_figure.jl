# plot_srn_figure.jl — final MIPT phase-diagram figure (SRN protocol)
# Reads examples/data/mipt_phase_diagram_srn.csv (produced by run_srn_figure.jl)
# and overlays the digitized SRN Fig 13(a) points.
# Run with: julia --project=. examples/plot_srn_figure.jl

using Pkg; Pkg.activate(dirname(@__DIR__))
using Plots

const DATA_PATH = joinpath(@__DIR__, "data", "mipt_phase_diagram_srn.csv")
const SRN_PATH = joinpath(@__DIR__, "data", "srn_fig13a_digitized.csv")
const OUT_PATH = joinpath(@__DIR__, "mipt_phase_diagram.png")

# Our data: L,p,n_seeds,S_fresh_mean,S_fresh_sem
ours = Dict{Int,Vector{NamedTuple}}()
for (k, line) in enumerate(eachline(DATA_PATH))
    k == 1 && continue
    f = split(line, ',')
    L = parse(Int, f[1])
    push!(get!(ours, L, NamedTuple[]),
          (p=parse(Float64, f[2]), m=parse(Float64, f[4]), s=parse(Float64, f[5])))
end

# SRN digitized: L,p,S1_bits,precision
srn = Dict{Int,Vector{NamedTuple}}()
for (k, line) in enumerate(eachline(SRN_PATH))
    k == 1 && continue
    f = split(line, ',')
    L = parse(Int, f[1])
    push!(get!(srn, L, NamedTuple[]),
          (p=parse(Float64, f[2]), m=parse(Float64, f[3])))
end

L_list = sort(collect(keys(ours)))
colors = palette(:default)
srn_markers = Dict(6 => :circle, 8 => :rect, 10 => :diamond, 12 => :utriangle)

fig = plot(xlabel="p", ylabel="S_{L/2} (bits)",
           title="MIPT Phase Diagram — SRN protocol (OBC, cut-layer snapshot)",
           legend=:topright, size=(750, 550))

for (iL, L) in enumerate(L_list)
    rows = sort(ours[L], by=r -> r.p)
    plot!(fig, [r.p for r in rows], [r.m for r in rows],
          ribbon=[r.s for r in rows], fillalpha=0.2,
          label="L=$L", color=colors[iL], lw=2, marker=:o, ms=4)
end

first_srn = true
for L in L_list
    haskey(srn, L) || continue
    rows = sort(srn[L], by=r -> r.p)
    scatter!(fig, [r.p for r in rows], [r.m for r in rows],
             marker=srn_markers[L], ms=6, markercolor=:white,
             markerstrokecolor=:black, markerstrokewidth=1.5,
             label=first_srn ? "SRN PRX 9, 031009 (digitized)" : "")
    global first_srn = false
end

savefig(fig, OUT_PATH)
println("Saved figure: $OUT_PATH")
