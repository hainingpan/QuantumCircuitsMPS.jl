#!/usr/bin/env julia

# CIPT (Control-Induced Phase Transition) Example
# =================================================
# This example demonstrates the control-induced phase transition (CIPT) in a
# 1D quantum circuit with conditional Reset/Haar gates on staircase geometries.
#
# CIPT Physics Background:
# =========================
# The Control-Induced Phase Transition arises from competition between:
# - Reset gates (probability p_ctrl): Project qubit to |0⟩, moving LEFT
# - Haar random unitaries (probability 1-p_ctrl): Entangle neighboring qubits, moving RIGHT
#
# At each timestep, a coin flip determines which operation is applied.
# The staircase geometry creates a "sweep" across the chain.
#
# Observable: Magnetization Mz = (1/L) Σᵢ ⟨Zᵢ⟩
# - Large p_ctrl: Mz → +1 (resets dominate, qubits in |0⟩)
# - Small p_ctrl: Mz → 0 (unitaries dominate, random state)

using Pkg; Pkg.activate(dirname(@__DIR__))
using QuantumCircuitsMPS
using Printf
using Statistics
using Plots
using ProgressMeter

# ═══════════════════════════════════════════════════════════════════
# SECTION 1: Parameters
# ═══════════════════════════════════════════════════════════════════

L = 8                      # System size (number of qubits)
bc = :periodic             # Boundary conditions
n_steps = 2 * L^2          # Total timesteps (staircase sweeps)
p_ctrl = 0.5               # Control probability

println("Parameters:")
println("  L = $L (system size)")
println("  bc = $bc (boundary conditions)")
println("  n_steps = $n_steps (circuit timesteps)")
println("  p_ctrl = $p_ctrl (control probability)")
println()

# ═══════════════════════════════════════════════════════════════════
# SECTION 2: Build Circuit
# ═══════════════════════════════════════════════════════════════════
# The circuit uses declarative do-block syntax.
# n_steps defines how many timesteps the staircase sweeps through.
# Each timestep: coin flip → apply Reset (left staircase) OR Haar (right staircase).
#
# IMPORTANT: n_steps must equal the total number of timesteps, NOT 1.
# The staircase position is computed from the step number — with n_steps=1,
# the staircase would never advance. We run n_circuits=1 with the full
# n_steps inside the circuit.

left = StaircaseLeft(L)
right = StaircaseRight(L)

circuit = Circuit(L=L, bc=bc, n_steps=n_steps, p_ctrl=p_ctrl) do c
    apply_with_prob!(c; rng=:gates_spacetime, outcomes=[
        (probability=c.params[:p_ctrl], gate=Reset(), geometry=left),
        (probability=1-c.params[:p_ctrl], gate=HaarRandom(), geometry=right)
    ])
end

println("Circuit built: $(circuit.n_steps) steps, $(circuit.L) qubits")
println()

# ═══════════════════════════════════════════════════════════════════
# SECTION 3: Run Simulation with Magnetization
# ═══════════════════════════════════════════════════════════════════

state = SimulationState(L=L, bc=bc, maxdim=64,
    rng=RNGRegistry(gates_spacetime=42, born_measurement=1, gates_realization=2))
initialize!(state, ProductState(binary_int=0))
track!(state, :Mz => Magnetization(:Z))

# n_circuits=1: the circuit already contains all n_steps internally
simulate!(circuit, state; n_circuits=1, record_when=:every_gate)

mz_vals = state.observables[:Mz]
println("Magnetization time series: $(length(mz_vals)) points")
println("  Initial Mz = $(Printf.@sprintf("%.4f", mz_vals[1]))")
println("  Final   Mz = $(Printf.@sprintf("%.4f", mz_vals[end]))")
println()

# ═══════════════════════════════════════════════════════════════════
# SECTION 4: Steady-State Phase Diagram
# ═══════════════════════════════════════════════════════════════════
# Sweep p_ctrl to map out the phase diagram: Mz(p_ctrl) for multiple L.
# Each point is averaged over `ensemble_size` random seeds.
# Run with `julia -t auto` for multithreaded execution.

function run_cipt(; L, p_ctrl, seed, bc=:periodic, n_steps=2*L^2, maxdim=64)
    left = StaircaseLeft(L)
    right = StaircaseRight(L)

    circuit = Circuit(L=L, bc=bc, n_steps=n_steps, p_ctrl=p_ctrl) do c
        apply_with_prob!(c; rng=:gates_spacetime, outcomes=[
            (probability=c.params[:p_ctrl], gate=Reset(), geometry=left),
            (probability=1-c.params[:p_ctrl], gate=HaarRandom(), geometry=right)
        ])
    end

    state = SimulationState(L=L, bc=bc, maxdim=maxdim,
        rng=RNGRegistry(gates_spacetime=seed, born_measurement=seed+100, gates_realization=seed+200))
    initialize!(state, ProductState(binary_int=0))
    track!(state, :Mz => Magnetization(:Z))

    simulate!(circuit, state; n_circuits=1, record_when=:final_only)
    return state.observables[:Mz][end]
end

# Sweep parameters
L_list = [4, 6]
p_list = 0.05:0.05:0.95 |> collect
ensemble_size = 100

configs = [(L=L, p=p, seed=s) for L in L_list for p in p_list for s in 1:ensemble_size]
raw = Vector{Float64}(undef, length(configs))

println("Running $(length(configs)) configs on $(Threads.nthreads()) threads...")
@time @showprogress Threads.@threads for i in eachindex(configs)
    c = configs[i]
    raw[i] = run_cipt(L=c.L, p_ctrl=c.p, seed=c.seed)
end

# Reshape to (seed, p, L) and average over seeds
ns, np, nL = ensemble_size, length(p_list), length(L_list)
Mz_raw = reshape(raw, ns, np, nL)
Mz_mean = dropdims(mean(Mz_raw, dims=1), dims=1)
Mz_std  = dropdims(std(Mz_raw, dims=1), dims=1)

println("Done!")

# Plot
p_fig = plot(xlabel="p_ctrl", ylabel="⟨Mz⟩", title="CIPT Steady-State Magnetization", legend=:topleft)
for (iL, L) in enumerate(L_list)
    plot!(p_fig, p_list, Mz_mean[:, iL], ribbon=Mz_std[:, iL], fillalpha=0.2,
          label="L=$L", lw=2, marker=:o, ms=4)
end
savefig(p_fig, "cipt_phase_diagram.png")
println("Saved: cipt_phase_diagram.png")
