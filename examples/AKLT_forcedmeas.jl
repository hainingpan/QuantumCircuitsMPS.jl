#!/usr/bin/env julia
# AKLT Forced Measurement with NN+NNN Projections
# Run with: julia -t auto examples/AKLT_forcedmeas.jl

using QuantumCircuitsMPS
using ITensorMPS
using Printf
using Statistics
using Plots

# ═══════════════════════════════════════════════════════════════════════════
# Setup
# ═══════════════════════════════════════════════════════════════════════════

bc = :periodic
maxdim = 128

# Gate: project out S=2 sector
P0 = total_spin_projector(0)
P1 = total_spin_projector(1)
proj_gate = SpinSectorProjection(P0 + P1)

# ═══════════════════════════════════════════════════════════════════════════
# Parameter Sweep: L × p × seed (parallel)
# ═══════════════════════════════════════════════════════════════════════════

L_list = [8, 16]
p_list = 0:0.1:1.0 |> collect
seeds = 1:10

configs = [(L=L, p=p, seed=s) for L in L_list for p in p_list for s in seeds]

function run_sim(cfg)
    L, p, seed = cfg.L, cfg.p, cfg.seed
    
    circuit = Circuit(L=L, bc=bc, n_steps=1, p_nn=p, proj_gate=proj_gate) do c
        apply_with_prob!(c; rng=:ctrl, outcomes=[
            (probability=c.params[:p_nn], gate=c.params[:proj_gate], geometry=Bricklayer(:nn)),
            (probability=1-c.params[:p_nn], gate=c.params[:proj_gate], geometry=Bricklayer(:nnn))
        ])
    end
    
    rng = RNGRegistry(ctrl=seed, proj=seed+100, haar=seed+200, born=seed+300)
    state = SimulationState(L=L, bc=bc, site_type="S=1", maxdim=maxdim, rng=rng)
    state.mps = MPS(state.sites, ["Z0" for _ in 1:L])
    
    # Track all observables
    track!(state, :S => EntanglementEntropy(cut=L÷2, order=1, base=2))
    track!(state, :SO_nn => StringOrder(1, L÷2+1, order=1))
    track!(state, :SO_nnn => StringOrder(1, L÷2+1, order=2))
    
    simulate!(circuit, state; n_circuits=L, record_when=:final_only)
    
    (L=L, p=p, seed=seed, 
     S=state.observables[:S][end], 
     SO_nn=abs(state.observables[:SO_nn][end]),
     SO_nnn=abs(state.observables[:SO_nnn][end]))
end

println("Running $(length(configs)) configs on $(Threads.nthreads()) threads...")
@time raw = fetch.([Threads.@spawn run_sim(cfg) for cfg in configs])

# Aggregate
results = Dict(
    (L, p) => (
        S_mean = mean(r.S for r in raw if r.L == L && r.p == p),
        S_std = std(r.S for r in raw if r.L == L && r.p == p),
        SO_nn_mean = mean(r.SO_nn for r in raw if r.L == L && r.p == p),
        SO_nn_std = std(r.SO_nn for r in raw if r.L == L && r.p == p),
        SO_nnn_mean = mean(r.SO_nnn for r in raw if r.L == L && r.p == p),
        SO_nnn_std = std(r.SO_nnn for r in raw if r.L == L && r.p == p)
    )
    for L in L_list for p in p_list
)
println("Done!")

# ═══════════════════════════════════════════════════════════════════════════
# Results Table
# ═══════════════════════════════════════════════════════════════════════════

for L in L_list
    println("\nL=$L:")
    println("  p_nn    S          |SO_nn|     |SO_nnn|")
    for p in p_list
        r = results[(L, p)]
        @printf("  %.1f   %.2f±%.2f   %.3f±%.3f   %.3f±%.3f\n", 
                p, r.S_mean, r.S_std, r.SO_nn_mean, r.SO_nn_std, r.SO_nnn_mean, r.SO_nnn_std)
    end
end

# ═══════════════════════════════════════════════════════════════════════════
# Plots
# ═══════════════════════════════════════════════════════════════════════════

# Entanglement Entropy
colors = cgrad(:viridis, length(L_list), categorical=true)
p_ee = plot(xlabel="p_nn", ylabel="S", title="Entanglement Entropy", legend=:topright)
for (i, L) in enumerate(L_list)
    S_vals = [results[(L, p)].S_mean for p in p_list]
    S_errs = [results[(L, p)].S_std for p in p_list]
    plot!(p_ee, p_list, S_vals, ribbon=S_errs, fillalpha=0.2, 
          label="L=$L", color=colors[i], lw=2, marker=:o, ms=4)
end
hline!(p_ee, [2.0, 4.0], ls=:dash, color=:gray, alpha=0.5, label="")

# NN Order Parameter
colors = cgrad(:plasma, length(L_list), categorical=true)
p_so = plot(xlabel="p_nn", ylabel="|SO|", title="NN Order (order=1)", legend=:topright)
for (i, L) in enumerate(L_list)
    SO_vals = [results[(L, p)].SO_nn_mean for p in p_list]
    SO_errs = [results[(L, p)].SO_nn_std for p in p_list]
    plot!(p_so, p_list, SO_vals, ribbon=SO_errs, fillalpha=0.2,
          label="L=$L", color=colors[i], lw=2, marker=:s, ms=4)
end
hline!(p_so, [4/9], ls=:dash, color=:gray, alpha=0.5, label="4/9")

# NNN Order Parameter
colors = cgrad(:inferno, length(L_list), categorical=true)
p_nnn = plot(xlabel="p_nn", ylabel="|SO|", title="NNN Order (order=2)", legend=:topright)
for (i, L) in enumerate(L_list)
    SO_vals = [results[(L, p)].SO_nnn_mean for p in p_list]
    SO_errs = [results[(L, p)].SO_nnn_std for p in p_list]
    plot!(p_nnn, p_list, SO_vals, ribbon=SO_errs, fillalpha=0.2,
          label="L=$L", color=colors[i], lw=2, marker=:d, ms=4)
end
hline!(p_nnn, [(4/9)^2], ls=:dash, color=:gray, alpha=0.5, label="(4/9)²")

# Combined
p_combined = plot(p_ee, p_so, p_nnn, layout=(1,3), size=(1500, 400))
savefig(p_combined, "aklt_phase_diagram.png")
println("\nSaved: aklt_phase_diagram.png")
