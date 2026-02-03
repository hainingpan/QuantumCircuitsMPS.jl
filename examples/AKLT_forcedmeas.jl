#!/usr/bin/env julia
# AKLT Forced Measurement with NN+NNN Projections
# Run with: julia -t auto examples/AKLT_forcedmeas.jl

using QuantumCircuitsMPS
using ITensorMPS
using Printf
using Statistics
using Plots

# Setup
bc = :periodic
maxdim = 128
P0 = total_spin_projector(0)
P1 = total_spin_projector(1)
proj_gate = SpinSectorProjection(P0 + P1)

# Parameter sweep: L × p × seed (parallel)
L_list = [8, 16]
p_list = 0:0.1:1.0 |> collect
seeds = 1:10

nL, np, ns = length(L_list), length(p_list), length(seeds)
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
    initialize!(state, ProductState(spin_state="Z0"))
    
    track!(state, :S => EntanglementEntropy(cut=L÷2, renyi_index=1, base=2))
    track!(state, :SO_nn => StringOrder(1, L÷2+1, order=1))
    track!(state, :SO_nnn => StringOrder(1, L÷2+1, order=2))
    
    simulate!(circuit, state; n_circuits=L, record_when=:final_only)
    
    (state.observables[:S][end], 
     abs(state.observables[:SO_nn][end]),
     abs(state.observables[:SO_nnn][end]))
end

println("Running $(length(configs)) configs on $(Threads.nthreads()) threads...")
@time raw = fetch.([Threads.@spawn run_sim(cfg) for cfg in configs])

# Reshape to 3D tensors: (seed, p, L) then aggregate over seeds
S_raw = reshape([r[1] for r in raw], ns, np, nL)
SO_nn_raw = reshape([r[2] for r in raw], ns, np, nL)
SO_nnn_raw = reshape([r[3] for r in raw], ns, np, nL)

S_mean = dropdims(mean(S_raw, dims=1), dims=1)         # (p, L)
S_std = dropdims(std(S_raw, dims=1), dims=1)
SO_nn_mean = dropdims(mean(SO_nn_raw, dims=1), dims=1)
SO_nn_std = dropdims(std(SO_nn_raw, dims=1), dims=1)
SO_nnn_mean = dropdims(mean(SO_nnn_raw, dims=1), dims=1)
SO_nnn_std = dropdims(std(SO_nnn_raw, dims=1), dims=1)

println("Done!")

# Results table
for (iL, L) in enumerate(L_list)
    println("\nL=$L:")
    println("  p_nn    S          |SO_nn|     |SO_nnn|")
    for (ip, p) in enumerate(p_list)
        @printf("  %.1f   %.2f±%.2f   %.3f±%.3f   %.3f±%.3f\n", 
                p, S_mean[ip,iL], S_std[ip,iL], 
                SO_nn_mean[ip,iL], SO_nn_std[ip,iL], 
                SO_nnn_mean[ip,iL], SO_nnn_std[ip,iL])
    end
end

# Plots
colors = cgrad(:viridis, nL, categorical=true)
p_ee = plot(xlabel="p_nn", ylabel="S", title="Entanglement Entropy", legend=:topright)
for (iL, L) in enumerate(L_list)
    plot!(p_ee, p_list, S_mean[:,iL], ribbon=S_std[:,iL], fillalpha=0.2, 
          label="L=$L", color=colors[iL], lw=2, marker=:o, ms=4)
end
hline!(p_ee, [2.0, 4.0], ls=:dash, color=:gray, alpha=0.5, label="")

colors = cgrad(:plasma, nL, categorical=true)
p_so = plot(xlabel="p_nn", ylabel="|SO|", title="NN Order (order=1)", legend=:topright)
for (iL, L) in enumerate(L_list)
    plot!(p_so, p_list, SO_nn_mean[:,iL], ribbon=SO_nn_std[:,iL], fillalpha=0.2,
          label="L=$L", color=colors[iL], lw=2, marker=:s, ms=4)
end
hline!(p_so, [4/9], ls=:dash, color=:gray, alpha=0.5, label="4/9")

colors = cgrad(:inferno, nL, categorical=true)
p_nnn = plot(xlabel="p_nn", ylabel="|SO|", title="NNN Order (order=2)", legend=:topright)
for (iL, L) in enumerate(L_list)
    plot!(p_nnn, p_list, SO_nnn_mean[:,iL], ribbon=SO_nnn_std[:,iL], fillalpha=0.2,
          label="L=$L", color=colors[iL], lw=2, marker=:d, ms=4)
end
hline!(p_nnn, [(4/9)^2], ls=:dash, color=:gray, alpha=0.5, label="(4/9)²")

p_combined = plot(p_ee, p_so, p_nnn, layout=(1,3), size=(1500, 400))
savefig(p_combined, "aklt_phase_diagram.png")
println("\nSaved: aklt_phase_diagram.png")
