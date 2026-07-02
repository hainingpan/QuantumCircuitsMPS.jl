# mipt_example.jl — script mirror of examples/mipt_example.ipynb
# Run with: julia --project=. -t auto examples/mipt_example.jl
# See examples/mipt_example.ipynb for the full interactive tutorial.

using Pkg; Pkg.activate(dirname(@__DIR__))
using QuantumCircuitsMPS
using Printf
using Statistics
using Plots
using ProgressMeter
using Luxor

# --- Section 1: Setup and Parameters ---
const L = 8                   # System size (number of qubits)
const bc = :periodic           # Boundary conditions
const n_steps = L             # Total timesteps for simulation (passed to simulate!(n_steps=n_steps))
const p = 0.5                 # Measurement probability (near critical p_c ≈ 0.16)
const cut = L ÷ 2              # Entanglement cut position

println("Parameters:")
println("  L = $L (system size)")
println("  bc = $bc (boundary conditions)")
println("  n_steps = $n_steps (circuit timesteps)")
println("  p = $p (measurement probability)")
println("  cut = $cut (entanglement cut position)")

# --- Section 2: Building the MIPT Circuit ---
# Build circuit (one full MIPT cycle per do-block execution: even+measure+odd+measure)
circuit = Circuit(L=L, bc=bc, p=p) do c
    apply!(c, HaarRandom(), Bricklayer(:even))
    apply_with_prob!(c; rng=:gates_spacetime, outcomes=[
        (probability=c.params[:p], gate=Measurement(:Z), geometry=AllSites())
    ])
    apply!(c, HaarRandom(), Bricklayer(:odd))
    apply_with_prob!(c; rng=:gates_spacetime, outcomes=[
        (probability=c.params[:p], gate=Measurement(:Z), geometry=AllSites())
    ])
end

println("Circuit built successfully")
println("Circuit parameters: L=$(circuit.L), bc=$(circuit.bc)")
println("System size: $(circuit.L) qubits")
println("Boundary conditions: $(circuit.bc)")

# Circuit visualization
plot_circuit(circuit; gates_spacetime=0, n_steps=4, filename=joinpath(@__DIR__, "mipt_circuit.svg"))

# --- Section 3: Simulation with Entanglement Tracking ---
# Create simulation state with RNG registry
state = SimulationState(
    L=L,
    bc=bc,
    maxdim=64,
    rng=RNGRegistry(gates_spacetime=0, born_measurement=0, gates_realization=2)
)

# Initialize to product state |0⟩⊗L
initialize!(state, ProductState(binary_int=0))

# Track entanglement entropy at the central cut
track!(state, :entropy => EntanglementEntropy(; cut=cut))

# Run simulation: execute circuit n_steps times (n_steps=n_steps)
simulate!(circuit, state; n_steps=n_steps, record_when=:every_step)

# Extract entropy values from state
entropy_vals = state.observables[:entropy]

println("✓ Simulation complete")
println("  Recorded $(length(entropy_vals)) entropy values")
println()

p_traj = plot(entropy_vals, xlabel="Step", ylabel="Half-cut entanglement entropy", title="(p=$p)",
     legend=false, lw=1.5)
savefig(p_traj, joinpath(@__DIR__, "mipt_entropy_trajectory.png"))

# --- Section 4: Steady-State Phase Diagram ---
# NOTE on comparing S across system sizes:
# With a fixed end-of-cycle recording phase, the half-cut bond (L/2, L/2+1) is
# refreshed by the :even or :odd brick sublayer depending on L, producing an
# L mod 4 parity artifact in S(L) (largest deep in the area-law phase, p >= 0.3).
# The package itself is verified against exact statevector evolution to machine
# precision. Full analysis + quantitative reproduction of Skinner-Ruhman-Nahum
# PRX 9, 031009 Fig. 13(a): see the `validation-srn` branch.
function run_mipt(; L, p, seed, bc=:periodic, n_steps=2*L, maxdim=2^20)
    circuit = Circuit(L=L, bc=bc, p=p) do c
        apply!(c, HaarRandom(), Bricklayer(:even))
        apply_with_prob!(c; rng=:gates_spacetime, outcomes=[
            (probability=c.params[:p], gate=Measurement(:Z), geometry=AllSites())
        ])
        apply!(c, HaarRandom(), Bricklayer(:odd))
        apply_with_prob!(c; rng=:gates_spacetime, outcomes=[
            (probability=c.params[:p], gate=Measurement(:Z), geometry=AllSites())
        ])
    end

    state = SimulationState(L=L, bc=bc, maxdim=maxdim, cutoff = 1e-10,
        # non-overlapping streams across trajectories
        rng=RNGRegistry(gates_spacetime=3*(seed-1)+1, born_measurement=3*(seed-1)+2, gates_realization=3*(seed-1)+3))
    initialize!(state, ProductState(binary_int=0))
    track!(state, :entropy => EntanglementEntropy(; cut=L÷2))

    simulate!(circuit, state; n_steps=n_steps, record_when=:final_only)
    return state.observables[:entropy][end]
end

# Sweep parameters (reduced for a quick script run)
L_list = [6, 8, 10]
p_list = [0, 0.1, 0.2, 0.3, 0.4, 0.5]
ensemble_size = 100  # notebook production value: 2000

configs = [(L=L, p=p, seed=s) for L in L_list for p in p_list for s in 1:ensemble_size]
raw = Vector{Float64}(undef, length(configs))

# Run with `julia -t auto` for multithreaded execution
println("Running $(length(configs)) configs on $(Threads.nthreads()) threads...")
@time @showprogress Threads.@threads for i in eachindex(configs)
    c = configs[i]
    raw[i] = run_mipt(L=c.L, p=c.p, seed=c.seed)
end

# Reshape to (seed, p, L) and average over seeds
ns, np, nL = ensemble_size, length(p_list), length(L_list)
S_raw = reshape(raw, ns, np, nL)
S_mean = dropdims(mean(S_raw, dims=1), dims=1)
S_sem  = dropdims(std(S_raw, dims=1), dims=1) ./ sqrt(size(S_raw, 1))

println("Done!")

p_fig = plot(xlabel="p", ylabel=raw"$S_{L/2}$ (bits)", title=raw"MIPT Steady-State (t=2L) Entanglement Entropy", legend=:topright)
for (iL, L) in enumerate(L_list)
    plot!(p_fig, p_list, S_mean[:, iL], ribbon=S_sem[:, iL], fillalpha=0.2,
          label="L=$L", lw=2, marker=:o, ms=4, ylims=(0,5))
end
savefig(p_fig, joinpath(@__DIR__, "mipt_phase_diagram.png"))
