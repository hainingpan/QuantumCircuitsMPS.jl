# mipt_example.jl — script mirror of examples/mipt_example.ipynb
# Run with: julia --project=. -t auto examples/mipt_example.jl
# See examples/mipt_example.ipynb for the full interactive tutorial.
#
# This file also defines `run_mipt` and `run_mipt_srn`, which other scripts
# can `include(...)` to reuse without re-running
# the demo/plotting code below — that code is guarded by the
# `if abspath(PROGRAM_FILE) == @__FILE__` block near the bottom of this file,
# so simply `include`-ing this file only defines functions (cheap, fast).

using Pkg; Pkg.activate(dirname(@__DIR__))
using QuantumCircuitsMPS
using Printf
using Statistics

# --- run_mipt: naive periodic-BC variant (pedagogical) ---
# NOTE on comparing S across system sizes:
# With a fixed end-of-cycle recording phase, the half-cut bond (L/2, L/2+1) is
# refreshed by the :even or :odd brick sublayer depending on L, producing an
# L mod 4 parity artifact in S(L) (largest deep in the area-law phase, p >= 0.3).
# The package itself is verified against exact statevector evolution to machine
# precision. `run_mipt_srn` below implements the SRN boundary-eligibility
# protocol (OBC + EachSite bulk-only measurement coins), which avoids this
# artifact.
function run_mipt(; L, p, seed, bc=:periodic, n_steps=2*L, maxdim=2^20)
    circuit = Circuit(L=L, bc=bc, p=p) do c
        apply!(c, HaarRandom(), Bricklayer(:even))
        apply_with_prob!(c; outcomes=[
            (probability=c.params[:p], gate=Measure(:Z), geometry=AllSites())
        ])
        apply!(c, HaarRandom(), Bricklayer(:odd))
        apply_with_prob!(c; outcomes=[
            (probability=c.params[:p], gate=Measure(:Z), geometry=AllSites())
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

# --- run_mipt_srn: SRN (Skinner-Ruhman-Nahum, PRX 9, 031009) boundary-
# eligibility protocol, ported to the v0.1 marker/EachSite API. ---
#
# Protocol (ONE Circuit, TWO record!(c) markers, marker-driven recording only):
#   OBC brickwork. One period = two half-steps.
#     Half-step A: Bricklayer(:even) Haar layer (bulk pairs (2,3),(4,5),...,
#       (L-2,L-1) — does NOT touch the edges under OBC), then a measurement
#       coin with probability p for EACH bulk site 2:L-1 only (boundary sites
#       are not eligible in this half-step — this is the SRN "boundary
#       eligibility" convention: edge sites get only one measurement chance
#       per period, matching the paper's OBC brickwork). record!(c) marks the
#       snapshot right after this half-step settles.
#     Half-step B: Bricklayer(:odd) Haar layer (touches ALL sites (1,2),
#       (3,4),...,(L-1,L) under OBC), then a measurement coin with probability
#       p for EVERY site (AllSites()). record!(c) marks this snapshot.
#   Observable: von Neumann entanglement entropy (base 2) at the central cut,
#   EntanglementEntropy(cut=L÷2).
#   Cut-layer snapshot rule: the half-cut bond is (L/2, L/2+1); this bond
#   belongs to the :odd sublayer when L/2 is odd, and to the :even sublayer
#   when L/2 is even (bond (k,k+1) is :even for k even, :odd for k odd).
#   So we use half-step A's records (right after the :even Haar layer) when
#   L/2 is even, and half-step B's records (right after the :odd Haar layer)
#   when L/2 is odd — this is the "fresh" snapshot, taken immediately after
#   the unitary layer that acts across the cut has last refreshed it.
#   Estimator: mean of the cut-layer records over the LAST 4 periods (steady
#   state; n_periods=4L layers by default is enough for L <= 24 away from the
#   critical point, per the paper's own guidance).
function run_mipt_srn(; L, p, seed, n_periods=4L, maxdim=2^20, cutoff=1e-10)
    iseven(L) || throw(ArgumentError("run_mipt_srn requires even L (got L=$L)"))

    circuit = Circuit(L=L, bc=:open, p=p) do c
        # Half-step A: even Haar bricklayer (bulk-only under OBC), then
        # bulk-only measurement coins (EachSite(2:L-1): K = L-2 independent
        # coins, one per bulk site — boundary sites 1 and L are NOT eligible
        # here, matching the SRN boundary-eligibility convention).
        apply!(c, HaarRandom(), Bricklayer(:even))
        apply_with_prob!(c; outcomes=[
            (probability=c.params[:p], gate=Measure(:Z), geometry=EachSite(2:L-1))
        ])
        record!(c)

        # Half-step B: odd Haar bricklayer (touches all sites under OBC),
        # then all-site measurement coins (AllSites(): K = L coins).
        apply!(c, HaarRandom(), Bricklayer(:odd))
        apply_with_prob!(c; outcomes=[
            (probability=c.params[:p], gate=Measure(:Z), geometry=AllSites())
        ])
        record!(c)
    end

    state = SimulationState(L=L, bc=:open, maxdim=maxdim, cutoff=cutoff,
        rng=RNGRegistry(gates_spacetime=3*(seed-1)+1, born_measurement=3*(seed-1)+2, gates_realization=3*(seed-1)+3))
    initialize!(state, ProductState(binary_int=0))
    track!(state, :entropy => EntanglementEntropy(; cut=L÷2))

    # record_when=:marks fires EXACTLY at the two record!(c) markers above —
    # deterministically 2 records/period regardless of which coins landed.
    simulate!(circuit, state; n_steps=n_periods, record_when=:marks)

    records = state.observables[:entropy]  # length 2*n_periods: [A1,B1,A2,B2,...]
    fresh_phase = iseven(L ÷ 2) ? 1 : 2     # 1 = half-step A (:even), 2 = half-step B (:odd)
    tail = records[end-7:end]               # last 4 periods = last 8 records
    return fresh_phase == 1 ? mean(tail[1:2:end]) : mean(tail[2:2:end])
end

# --- Everything below only runs when this file is executed directly
# (`julia examples/mipt_example.jl`), NOT when `include`-d by another script
# (a script can include this file just to get the two functions
# above, without paying for the demo/plotting/sweep code below). ---
if abspath(PROGRAM_FILE) == @__FILE__

using Plots
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
    apply_with_prob!(c; outcomes=[
        (probability=c.params[:p], gate=Measure(:Z), geometry=AllSites())
    ])
    apply!(c, HaarRandom(), Bricklayer(:odd))
    apply_with_prob!(c; outcomes=[
        (probability=c.params[:p], gate=Measure(:Z), geometry=AllSites())
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
# (run_mipt and run_mipt_srn are defined above this guard block, so they're
# available here without redefinition.)

# Sweep parameters (reduced for a quick script run)
L_list = [6, 8, 10]
p_list = [0, 0.1, 0.2, 0.3, 0.4, 0.5]
ensemble_size = 100  # notebook production value: 2000

configs = [(L=L, p=p, seed=s) for L in L_list for p in p_list for s in 1:ensemble_size]
raw = Vector{Float64}(undef, length(configs))

# Run with `julia -t auto` for multithreaded execution
println("Running $(length(configs)) configs on $(Threads.nthreads()) threads...")
@time Threads.@threads for i in eachindex(configs)
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

# --- Section 5: SRN boundary-eligibility protocol demo ---
# run_mipt_srn implements the OBC/EachSite protocol from Skinner, Ruhman &
# Nahum, PRX 9, 031009 (2019), arXiv:1808.05953 — see the function's
# docstring/comment above for the full protocol.
println("\n--- SRN protocol demo (single trajectory) ---")
S_srn_demo = run_mipt_srn(L=8, p=0.10, seed=1)
println("run_mipt_srn(L=8, p=0.10, seed=1): S_fresh = $S_srn_demo")

end # if abspath(PROGRAM_FILE) == @__FILE__
