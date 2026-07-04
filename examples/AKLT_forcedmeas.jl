# AKLT_forcedmeas.jl — script mirror of examples/AKLT_forcedmeas.ipynb
# Run with: julia --project=. -t auto examples/AKLT_forcedmeas.jl
# See examples/AKLT_forcedmeas.ipynb for the full interactive tutorial.

using Pkg; Pkg.activate(dirname(@__DIR__))
using QuantumCircuitsMPS
using Printf
using Statistics
using Plots
using ProgressMeter
using Luxor

# --- Section 1: Setup and Parameters ---
L = 8              # System size (spin-1 sites, divisible by 4 for NNN coverage)
bc = :periodic     # Boundary conditions
n_layers = L       # Number of projection layers
p_nn = 0.9         # Probability of NN projection (1 - p_nn for NNN)
maxdim = 128       # Maximum bond dimension

println("Parameters:")
println("  L = $L (system size)")
println("  bc = $bc (boundary conditions)")
println("  n_layers = $n_layers (projection layers)")
println("  p_nn = $p_nn (NN projection probability)")
println("  maxdim = $maxdim (max bond dimension)")

# --- Section 2: Building the Circuit ---
# Projectors onto total spin sectors of two spin-1's
P0 = total_spin_projector(0)
P1 = total_spin_projector(1)
proj_gate = SpinSectorProjection(P0 + P1)  # removes S=2, keeps S=0/1 coherently

# One layer per do-block execution: NN bricklayer w.p. p_nn, NNN bricklayer w.p. 1-p_nn
circuit = Circuit(L=L, bc=bc, p_nn=p_nn, proj_gate=proj_gate) do c
    apply_with_prob!(c; outcomes=[
        (probability=c.params[:p_nn], gate=c.params[:proj_gate], geometry=Bricklayer(:nn)),
        (probability=1-c.params[:p_nn], gate=c.params[:proj_gate], geometry=Bricklayer(:nnn))
    ])
end

# ── Stochastic semantics in v0.1: per-element exclusive choice ──
# In v0.1, apply_with_prob! requires all outcome geometries to expand to the
# SAME element count K (here K = L for both Bricklayer(:nn) and Bricklayer(:nnn),
# validated at build time).  For each element k = 1..K the engine draws ONE coin
# from :gates_spacetime and makes a CATEGORICAL (exclusive) selection: either
# the :nn projection OR the :nnn projection is applied at that bond slot, never
# both in one layer.  This is a deliberate change from the pre-v0.1 engine, which
# drew independent Bernoulli trials per outcome and could apply BOTH projections
# to the same slot in one layer.
#
# At the endpoints p_nn = 0 or p_nn = 1 the distinction is degenerate (one
# outcome has probability 0), so the physics is BIT-EXACT vs the pre-refactor
# golden.  For 0 < p_nn < 1 the new semantics is the physically intended model:
# each bond slot receives exactly one projection type per layer.
#
# See docs/migration_v0.1.md "Case B findings" for the full audit.

println("Circuit built successfully")
println("  System size: $(circuit.L) sites")
println("  Boundary conditions: $(circuit.bc)")

# Circuit visualization
plot_circuit(circuit; gates_spacetime=3, n_steps=1, filename=joinpath(@__DIR__, "aklt_circuit.svg"))

# --- Section 3: Single Run ---
state = SimulationState(L=L, bc=bc, site_type="S=1", maxdim=maxdim,
    rng=RNGRegistry(gates_spacetime=3, born_measurement=1, gates_realization=2))
initialize!(state, ProductState(spin_state="Z0"))

track!(state, :SO_nn => StringOrder(1, L÷2+1, order=1))
track!(state, :SO_nnn => StringOrder(1, L÷2+1, order=2))

simulate!(circuit, state; n_steps=n_layers, record_when=:every_step)

# Trajectory plots
p_nn_traj = plot(state.observables[:SO_nn], xlabel="Step", ylabel="SO_nn", title="(p_nn=$p_nn)",
     legend=false, lw=1.5)
hline!(p_nn_traj, [-4/9], ls=:dash, color=:gray, label="4/9")
savefig(p_nn_traj, joinpath(@__DIR__, "aklt_SO_nn_trajectory.png"))

p_nnn_traj = plot(state.observables[:SO_nnn], xlabel="Step", ylabel="SO_nnn", title="(p_nn=$p_nn)",
     legend=false, lw=1.5)
hline!(p_nnn_traj, [16/81], ls=:dash, color=:gray, label="(4/9)^2")
savefig(p_nnn_traj, joinpath(@__DIR__, "aklt_SO_nnn_trajectory.png"))

# --- Section 4: Steady-State String Order ---
function run_aklt(; L, p_nn, seed, bc=:periodic, n_layers=L, maxdim=128)
    P0 = total_spin_projector(0)
    P1 = total_spin_projector(1)
    proj_gate = SpinSectorProjection(P0 + P1)

    circuit = Circuit(L=L, bc=bc, p_nn=p_nn, proj_gate=proj_gate) do c
        apply_with_prob!(c; outcomes=[
            (probability=c.params[:p_nn], gate=c.params[:proj_gate], geometry=Bricklayer(:nn)),
            (probability=1-c.params[:p_nn], gate=c.params[:proj_gate], geometry=Bricklayer(:nnn))
        ])
    end

    state = SimulationState(L=L, bc=bc, site_type="S=1", maxdim=maxdim,
        rng=RNGRegistry(gates_spacetime=seed, born_measurement=seed+100, gates_realization=seed+200))
    initialize!(state, ProductState(spin_state="Z0"))
    track!(state, :SO_nn => StringOrder(1, L÷2+1, order=1))
    track!(state, :SO_nnn => StringOrder(1, L÷2+1, order=2))

    simulate!(circuit, state; n_steps=n_layers, record_when=:final_only)
    return (abs(state.observables[:SO_nn][end]), abs(state.observables[:SO_nnn][end]))
end

# Sweep parameters (reduced for a quick run)
L_list = [8]  # notebook: [8, 16]
p_list = 0:0.1:1.0 |> collect
ensemble_size = 10  # already light (same as notebook)

configs = [(L=L, p=p, seed=s) for L in L_list for p in p_list for s in 1:ensemble_size]
raw = Vector{NTuple{2,Float64}}(undef, length(configs))

# Run with `julia -t auto` for multithreaded execution
println("Running $(length(configs)) configs on $(Threads.nthreads()) threads...")
@time @showprogress Threads.@threads for i in eachindex(configs)
    c = configs[i]
    raw[i] = run_aklt(L=c.L, p_nn=c.p, seed=c.seed)
end

# Reshape to (seed, p, L) and average over seeds
ns, np, nL = ensemble_size, length(p_list), length(L_list)
SO_nn_raw  = reshape(first.(raw), ns, np, nL)
SO_nnn_raw = reshape(last.(raw), ns, np, nL)
SO_nn_mean  = dropdims(mean(SO_nn_raw, dims=1), dims=1)
SO_nn_sem   = dropdims(std(SO_nn_raw, dims=1), dims=1) ./ sqrt(ns)
SO_nnn_mean = dropdims(mean(SO_nnn_raw, dims=1), dims=1)
SO_nnn_sem  = dropdims(std(SO_nnn_raw, dims=1), dims=1) ./ sqrt(ns)

println("Done!")

# NN string order sweep plot
p_fig_nn = plot(xlabel="p_nn", ylabel=raw"$|SO_{nn}|$", title="NN String Order", legend=:topleft)
for (iL, L) in enumerate(L_list)
    plot!(p_fig_nn, p_list, SO_nn_mean[:, iL], ribbon=SO_nn_sem[:, iL], fillalpha=0.2,
          label="L=$L", lw=2, marker=:o, ms=4)
end
hline!(p_fig_nn, [4/9], ls=:dash, color=:gray, label="4/9")
savefig(p_fig_nn, joinpath(@__DIR__, "aklt_SO_nn_sweep.png"))

# NNN string order sweep plot
p_fig_nnn = plot(xlabel="p_nn", ylabel=raw"$|SO_{nnn}|$", title="NNN String Order", legend=:topright)
for (iL, L) in enumerate(L_list)
    plot!(p_fig_nnn, p_list, SO_nnn_mean[:, iL], ribbon=SO_nnn_sem[:, iL], fillalpha=0.2,
          label="L=$L", lw=2, marker=:d, ms=4)
end
hline!(p_fig_nnn, [(4/9)^2], ls=:dash, color=:gray, label="(4/9)²")
savefig(p_fig_nnn, joinpath(@__DIR__, "aklt_SO_nnn_sweep.png"))

println("Saved figures: aklt_SO_nn_trajectory.png, aklt_SO_nnn_trajectory.png, aklt_SO_nn_sweep.png, aklt_SO_nnn_sweep.png")
