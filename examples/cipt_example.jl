# cipt_example.jl — script mirror of examples/cipt_example.ipynb
# Run with: julia --project=. -t auto examples/cipt_example.jl
# See examples/cipt_example.ipynb for the full interactive tutorial.

using Pkg; Pkg.activate(dirname(@__DIR__))
using QuantumCircuitsMPS
using Printf
using Statistics
using Plots
using ProgressMeter
using Luxor

# --- Section 1: Setup and Parameters ---

# Define system parameters
const L = 8                    # System size (number of qubits)
const bc = :periodic           # Boundary conditions
const n_steps = 2 * L^2        # Total timesteps (staircase sweeps)
const p_ctrl = 0.5             # Control probability

println("Parameters:")
println("  L = $L (system size)")
println("  bc = $bc (boundary conditions)")
println("  n_steps = $n_steps (circuit timesteps)")
println("  p_ctrl = $p_ctrl (control probability)")

# --- Section 2: Building the CIPT Circuit ---

# Build circuit: at each step, coin flip decides Reset (left) or Haar (right).
# Reset() is sugar for Measure(:Z; feedback=OnOutcome(1 => PauliX())) —
# it Born-samples the qubit, then flips it back to |0⟩ if the outcome was 1.
# For a custom feedback variant, replace Reset() with e.g.
#   Measure(:Z; feedback=OnOutcome(1 => Ry(π/4)))
left = StaircaseLeft(1)
right = StaircaseRight(1)

circuit = Circuit(L=L, bc=bc, p_ctrl=p_ctrl) do c
    apply_with_prob!(c; outcomes=[
        (probability=c.params[:p_ctrl], gate=Reset(), geometry=left),
        (probability=1-c.params[:p_ctrl], gate=HaarRandom(), geometry=right)
    ])
end

println("Circuit built successfully")
println("  System size: $(circuit.L) qubits")
println("  Boundary conditions: $(circuit.bc)")

# Circuit visualization: inspect the gate layout before running the simulation
plot_circuit(circuit; gates_spacetime=42, n_steps=6, filename=joinpath(@__DIR__, "cipt_circuit.svg"))

# --- Section 3: Simulation with Magnetization Tracking ---

println("Running simulation...")
println()

# Create simulation state with RNG registry
state = SimulationState(
    L=L,
    bc=bc,
    maxdim=64,
    rng=RNGRegistry(gates_spacetime=42, born_measurement=1, gates_realization=2)
)

# Initialize to product state |0>^L
initialize!(state, ProductState(binary_int=0))

# Track magnetization
track!(state, :Mz => Magnetization(:Z))

# Run simulation: n_steps controls how many times the circuit do-block runs
# record_when=:every_gate records after each gate (1 gate per step)
simulate!(circuit, state; n_steps=n_steps, record_when=:every_gate)

# Extract magnetization values
mz_vals = state.observables[:Mz]

println("Simulation complete")
println("  Recorded $(length(mz_vals)) magnetization values")
println("  Initial Mz = $(Printf.@sprintf("%.4f", mz_vals[1]))")
println("  Final   Mz = $(Printf.@sprintf("%.4f", mz_vals[end]))")

# Trajectory plot
p_traj = plot(mz_vals, xlabel="Step", ylabel="Mz", title="CIPT Magnetization (p_ctrl=$p_ctrl)",
     legend=false, lw=1.5)
savefig(p_traj, joinpath(@__DIR__, "cipt_mz_trajectory.png"))

# --- Section 4: Steady-State Phase Diagram ---

function run_cipt(; L, p_ctrl, seed, bc=:periodic, n_steps=L^2, maxdim=2^20)
    left = StaircaseLeft(1)
    right = StaircaseRight(1)

    circuit = Circuit(L=L, bc=bc, p_ctrl=p_ctrl) do c
        apply_with_prob!(c; outcomes=[
            (probability=c.params[:p_ctrl], gate=Reset(), geometry=left),
            (probability=1-c.params[:p_ctrl], gate=HaarRandom(), geometry=right)
        ])
    end

    state = SimulationState(L=L, bc=bc, maxdim=maxdim, cutoff = 1e-6,
        rng=RNGRegistry(gates_spacetime=seed, born_measurement=seed+100, gates_realization=seed+200))
    initialize!(state, ProductState(binary_int=0))
    track!(state, :Mz => Magnetization(:Z))

    simulate!(circuit, state; n_steps=n_steps, record_when=:final_only)
    return state.observables[:Mz][end]
end

# Sweep parameters (reduced for a quick demo run)
L_list = [4, 6, 8]  # notebook: [4, 6, 8, 10]
# Coarse grid over full range + fine grid near the critical point p_c = 0.5
p_list = sort(union(0.1:0.1:0.9, 0.4:0.02:0.6))  # keep fine grid for collapse plot
ensemble_size = 50  # notebook production value: 1000

configs = [(L=L, p=p, seed=s) for L in L_list for p in p_list for s in 1:ensemble_size]
raw = Vector{Float64}(undef, length(configs))

# Run with `julia -t auto` for multithreaded execution
println("Running $(length(configs)) configs on $(Threads.nthreads()) threads...")
prog = Progress(length(configs))
Threads.@threads for i in eachindex(configs)
    c = configs[i]
    raw[i] = run_cipt(L=c.L, p_ctrl=c.p, seed=c.seed)
    next!(prog)
end
finish!(prog)

# Reshape to (seed, p, L) and average over seeds
ns, np, nL = ensemble_size, length(p_list), length(L_list)
Mz_raw = reshape(raw, ns, np, nL)
Mz_mean = dropdims(mean(Mz_raw, dims=1), dims=1)
Mz_sem  = dropdims(std(Mz_raw, dims=1), dims=1) ./ sqrt(size(Mz_raw, 1))

println("Done!")

# Phase-diagram plot
p_fig = plot(xlabel="p_ctrl", ylabel=raw"$\langle Mz \rangle$", title=raw"CIPT Steady-State (t=$L^2$) Magnetization", legend=:topleft)
for (iL, L) in enumerate(L_list)
    plot!(p_fig, p_list, Mz_mean[:, iL], ribbon=Mz_sem[:, iL], fillalpha=0.2,
          label="L=$L", lw=2, marker=:o, ms=4)
end
savefig(p_fig, joinpath(@__DIR__, "cipt_phase_diagram.png"))

# CSV export
# NOTE: notebook writes cipt_Mz_data.csv (production data consumed by cipt_fss.ipynb);
# demo filename avoids overwriting it.
open(joinpath(@__DIR__, "cipt_Mz_data_demo.csv"), "w") do io
    println(io, "# CIPT steady-state Mz, n_steps=L^2, ensemble_size=$ensemble_size, maxdim=2^20, cutoff=1e-6")
    println(io, "p,L,Mz_mean,Mz_sem")
    for (iL, L) in enumerate(L_list), (ip, p) in enumerate(p_list)
        println(io, "$p,$L,$(Mz_mean[ip, iL]),$(Mz_sem[ip, iL])")
    end
end

# Rescaled collapse plot: x-axis rescaled as (p - p_c) * L
p_fig2 = plot(xlabel="p_ctrl", ylabel=raw"$\langle Mz \rangle$", title=raw"CIPT Steady-State (t=$L^2$) Magnetization", legend=:topleft)
for (iL, L) in enumerate(L_list)
    plot!(p_fig2, (p_list .- 0.5) * L, Mz_mean[:, iL], ribbon=Mz_sem[:, iL], fillalpha=0.2,
          label="L=$L", lw=2, marker=:o, ms=4)
end
savefig(p_fig2, joinpath(@__DIR__, "cipt_collapse.png"))
