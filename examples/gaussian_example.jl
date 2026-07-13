# gaussian_example.jl — script mirror of examples/gaussian_example.ipynb
# Run with: julia --project=. -t auto examples/gaussian_example.jl
# See examples/gaussian_example.ipynb for the full interactive tutorial.
#
# Class-DIII staggered monitored Majorana chain — reproduces Fig. 1b of
# H. Pan, H. Shapourian, C.-M. Jian, "Topological Modes in Monitored Quantum
# Dynamics", Phys. Rev. B 112, 144301 (2025), arXiv:2411.04191.
#
# This file defines `build_diii_circuit`, `antipodal_mi`, and `run_diii`,
# which other scripts can `include(...)` to reuse; the demo/sweep code below
# is guarded by `if abspath(PROGRAM_FILE) == @__FILE__`.

using Pkg; Pkg.activate(dirname(@__DIR__))
using QuantumCircuitsMPS
using Printf
using Statistics

# --- Circuit: one time step = two staggered half-layers on the Majorana ring ---
#
# Simulated at Majorana-site granularity (site_type="Majorana"): each of the
# L sites is ONE Majorana operator γ_i, so L here IS the paper's Majorana
# count. Fig. 1a of the paper maps directly onto the geometry system:
#
#   half-layer 1 — ODD links (γ1γ2), (γ3γ4), ... = Bricklayer(:odd):
#       with prob p     -> BondParity()    (measure i γ_i γ_{i+1})
#       with prob 1 - p -> GaussianHaar()  (SO(2) rotation exp(θ γ_i γ_{i+1}), θ ~ Haar)
#   half-layer 2 — EVEN links (γ2γ3), ..., (γ_L γ_1) = Bricklayer(:even), PBC wrap:
#       with prob 1 - p -> BondParity()
#       with prob p     -> GaussianHaar()
#
# i.e. p_odd = p and p_even = 1 - p (the paper's staggering; GTN reference:
# measure_all_tri_op(p_list=p, even=True) then (p_list=1-p, even=False)).
function build_diii_circuit(; L, p, bc=:periodic)
    return Circuit(L=L, bc=bc, p=p) do c
        # Half-layer 1: odd links, measurement probability p
        apply_with_prob!(c; outcomes=[
            (probability=p,     gate=BondParity(),  geometry=Bricklayer(:odd)),
            (probability=1 - p, gate=GaussianHaar(), geometry=Bricklayer(:odd)),
        ])
        # Half-layer 2: even links (incl. PBC wrap), measurement probability 1 - p
        apply_with_prob!(c; outcomes=[
            (probability=1 - p, gate=BondParity(),  geometry=Bricklayer(:even)),
            (probability=p,     gate=GaussianHaar(), geometry=Bricklayer(:even)),
        ])
    end
end

# --- Shift-averaged antipodal-quarter mutual information ---
#
# A = Majorana sites 1..L/4, B = sites L/2+1..3L/4 (antipodal quarters),
# averaged over all L/2 cyclic shifts of the (A, B) pair on the PBC ring
# (shifted regions WRAP around; the Gaussian MutualInformation override
# accepts arbitrary/wrapped site subsets). Result in nats (base = e).
function antipodal_mi(state; L=state.L)
    A0 = collect(1:(L ÷ 4))
    B0 = collect((L ÷ 2 + 1):(3L ÷ 4))
    vals = Vector{Float64}(undef, L ÷ 2)
    for shift in 0:(L ÷ 2 - 1)
        A = mod1.(A0 .+ shift, L)
        B = mod1.(B0 .+ shift, L)
        vals[shift + 1] = MutualInformation(A, B)(state)
    end
    return mean(vals)
end

# --- Single-trajectory runner: t = L full time steps, MI tracked at final time ---
function run_diii(; L, p, seed, t=L, bc=:periodic)
    circuit = build_diii_circuit(L=L, p=p, bc=bc)
    state = SimulationState(L=L, bc=bc, backend=:gaussian, site_type="Majorana",
        # 4 disjoint RNG streams per trajectory (mipt_example's offset idiom,
        # widened from 3 to 4 streams since we also draw :state_init)
        rng=RNGRegistry(gates_spacetime=4 * (seed - 1) + 1,
                        born_measurement=4 * (seed - 1) + 2,
                        gates_realization=4 * (seed - 1) + 3,
                        state_init=4 * (seed - 1) + 4))
    initialize!(state, RandomGaussianState())   # paper: random Gaussian initial state
    track!(state, :mi => antipodal_mi)
    simulate!(circuit, state; n_steps=t, record_when=:final_only)
    return state.observables[:mi][end]
end

if abspath(PROGRAM_FILE) == @__FILE__
    # === Sweep parameters (mirror of the notebook's Section 3) ===
    # L = number of MAJORANA sites (paper's curves use L = 32..256; reduced here)
    L_list = [16, 32, 64]
    p_list = collect(range(0, 1, length=11))
    n_realizations = 50           # paper uses 1000; reduced for a <5 min demo

    # --- Stagger sanity check: dimerized limits must have ~zero antipodal MI ---
    println("Stagger sanity check (L=32, seed=1):")
    mi0 = run_diii(L=32, p=0.0, seed=1)
    mi5 = run_diii(L=32, p=0.5, seed=1)
    mi1 = run_diii(L=32, p=1.0, seed=1)
    @printf("  MI(p=0.0) = %.6f   MI(p=0.5) = %.6f   MI(p=1.0) = %.6f\n", mi0, mi5, mi1)
    @assert mi0 < 1e-8 && mi1 < 1e-8 "dimerized limits must give zero antipodal MI"
    @assert mi5 > 10 * max(mi0, mi1, 1e-12) "p=0.5 must be far above the dimerized limits"
    println("  OK: p=0 and p=1 are area-law dimer states; p=0.5 is critical.\n")

    # === Ensemble sweep ===
    configs = [(L=L, p=p, seed=s) for L in L_list for p in p_list for s in 1:n_realizations]
    raw = Vector{Float64}(undef, length(configs))

    println("Running $(length(configs)) configs on $(Threads.nthreads()) threads...")
    t_elapsed = @elapsed Threads.@threads for i in eachindex(configs)
        c = configs[i]
        raw[i] = run_diii(L=c.L, p=c.p, seed=c.seed)
    end
    @printf("Sweep wall-clock: %.1f s\n", t_elapsed)

    # Reshape to (seed, p, L) and average over seeds
    ns, np, nL = n_realizations, length(p_list), length(L_list)
    MI_raw = reshape(raw, ns, np, nL)
    MI_mean = dropdims(mean(MI_raw, dims=1), dims=1)
    MI_sem = dropdims(std(MI_raw, dims=1), dims=1) ./ sqrt(ns)

    println("\nSteady-state antipodal-quarter MI (nats), rows = p, cols = L $(L_list):")
    for (ip, p) in enumerate(p_list)
        @printf("  p=%.3f  ", p)
        for iL in 1:nL
            @printf("%.4f±%.4f  ", MI_mean[ip, iL], MI_sem[ip, iL])
        end
        println()
    end

    # Qualitative Fig. 1b structure checks
    for iL in 1:nL
        imax = argmax(MI_mean[:, iL])
        pmax = p_list[imax]
        @printf("L=%-3d  max MI = %.4f at p = %.3f\n", L_list[iL], MI_mean[imax, iL], pmax)
    end
end
