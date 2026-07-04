# run_srn_figure.jl — MIPT phase-diagram sweep using the SRN boundary-eligibility
# protocol, ported to the v0.1 API (Circuit + record!(c) markers + EachSite).
#
# Protocol: see `run_mipt_srn` in examples/mipt_example.jl (which this script
# `include`s and calls directly — see examples/diagnostics/SRN_protocol.md for
# the full literature audit trail against Skinner-Ruhman-Nahum, PRX 9, 031009).
# This script is a thin `Threads.@threads` seed-parallel sweep over
# `run_mipt_srn`; each seed gets a fresh Circuit + SimulationState (built fresh
# inside run_mipt_srn itself), so the sweep is thread-safe with no extra
# copying needed.
#
# Run with:
#   julia --project=. -t 4 examples/run_srn_figure.jl 2>&1 \
#     | tee .sisyphus/evidence/srn-figure-run.txt
#
# Smoke mode (1 seed, 1 point, <2 min, writes to a scratch CSV — NEVER the
# ground-truth path):
#   julia --project=. examples/run_srn_figure.jl --smoke
#
# Outputs (full mode only):
#   examples/data/mipt_phase_diagram_srn.csv  (incremental per (L,p) block)
#   examples/data/srn_comparison.csv          (final comparison vs digitized SRN Fig 13a)
#   Verdict lines: SRN-MATCH-FINAL, ZIGZAG-CHECK, COLLAPSE-CHECK, P0-PAGE-CHECK
#
# CSV schema (byte-identical to the pre-port version): L,p,n_seeds,S_fresh_mean,S_fresh_sem

using Pkg; Pkg.activate(dirname(@__DIR__))
include(joinpath(@__DIR__, "mipt_example.jl"))  # defines run_mipt_srn (and run_mipt); demo/sweep code inside is guarded, so including this only defines functions
using Statistics
using Printf

const SMOKE = "--smoke" in ARGS

# --- Parameters ---
const L_LIST = SMOKE ? [6] : [6, 8, 10, 12]
const P_LIST = SMOKE ? [0.10] : [0.00, 0.05, 0.10, 0.15, 0.20, 0.25, 0.30, 0.40, 0.50]
const N_SEEDS_HI = SMOKE ? 1 : 300     # p >= 0.2
const N_SEEDS_LO = SMOKE ? 1 : 200     # p <  0.2
const N_SEEDS_HI_FLOOR = 150
const N_SEEDS_LO_FLOOR = 100
const SEED_OFFSET = 50_000
const BC = :open
const CUTOFF = 1e-10
const MAXDIM = 2^20
const TIME_BUDGET_S = 25 * 60.0

const CSV_PATH = SMOKE ? joinpath(tempdir(), "mipt_phase_diagram_srn_smoke.csv") :
                         joinpath(@__DIR__, "data", "mipt_phase_diagram_srn.csv")
const CMP_PATH = SMOKE ? joinpath(tempdir(), "srn_comparison_smoke.csv") :
                         joinpath(@__DIR__, "data", "srn_comparison.csv")
const SRN_PATH = joinpath(@__DIR__, "data", "srn_fig13a_digitized.csv")

sem(x) = std(x) / sqrt(length(x))

n_seeds_for(p, hi, lo) = p >= 0.2 ? hi : lo

function load_srn(path)
    srn = Dict{Tuple{Int,Float64},Float64}()
    for (k, line) in enumerate(eachline(path))
        k == 1 && continue
        f = split(line, ',')
        srn[(parse(Int, f[1]), parse(Float64, f[2]))] = parse(Float64, f[3])
    end
    return srn
end

function main()
    println("="^72)
    println("SRN-protocol MIPT phase diagram  (bc=$BC, cutoff=$CUTOFF, maxdim=$MAXDIM)")
    println("Grid: L in $(L_LIST), p in $(P_LIST), n_periods=4L")
    if SMOKE
        println("SMOKE MODE: $(N_SEEDS_LO) seed(s)/point, output -> $(CSV_PATH)")
    else
        println("Seeds/point: $(N_SEEDS_HI) (p>=0.2), $(N_SEEDS_LO) (p<0.2); offset $(SEED_OFFSET)")
    end
    println("Threads: $(Threads.nthreads())")
    println("="^72)

    grid = [(L=L, p=p) for L in L_LIST for p in P_LIST]

    n_hi, n_lo = N_SEEDS_HI, N_SEEDS_LO

    if !SMOKE
        # --- Pilot guard: cheap anchor (L=6, p=0.5) and expensive anchor (L=12, p=0.05) ---
        println("\n--- Pilot (10 seeds each at L=6 p=0.5 and L=12 p=0.05, seed range 99000+) ---")
        n_pilot = 10
        t0 = time()
        for s in 1:n_pilot
            run_mipt_srn(L=6, p=0.5, seed=99_000 + s, n_periods=4 * 6, maxdim=MAXDIM, cutoff=CUTOFF)
        end
        t_cheap = (time() - t0) / n_pilot
        t0 = time()
        for s in 1:n_pilot
            run_mipt_srn(L=12, p=0.05, seed=99_100 + s, n_periods=4 * 12, maxdim=MAXDIM, cutoff=CUTOFF)
        end
        t_exp = (time() - t0) / n_pilot
        @printf("  pilot L= 6 p=0.50: %.3f s/traj\n", t_cheap)
        @printf("  pilot L=12 p=0.05: %.3f s/traj\n", t_exp)

        # Geometric interpolation between anchors: lambda in [0,1] mixes cheap->expensive
        est_traj(L, p) = begin
            lam = ((L - 6) / 6 + (0.5 - p) / 0.5) / 2
            t_cheap^(1 - lam) * t_exp^lam
        end
        proj_serial = sum(est_traj(g.L, g.p) * n_seeds_for(g.p, N_SEEDS_HI, N_SEEDS_LO) for g in grid)
        proj_wall = proj_serial / max(Threads.nthreads(), 1) * 1.3   # 30% overhead margin
        @printf("Projected serial %.1f s, projected wall %.1f s (budget %.0f s)\n",
                proj_serial, proj_wall, TIME_BUDGET_S)

        if proj_wall > TIME_BUDGET_S
            n_hi, n_lo = N_SEEDS_HI_FLOOR, N_SEEDS_LO_FLOOR
            println("PILOT-GUARD: projected wall exceeds budget -> downscaling seeds to $(n_hi) (p>=0.2) / $(n_lo) (p<0.2)")
        else
            println("PILOT-GUARD: projection within budget, keeping $(n_hi)/$(n_lo) seeds/point")
        end
    end

    # --- Sweep with incremental CSV writes ---
    open(CSV_PATH, "w") do io
        println(io, "L,p,n_seeds,S_fresh_mean,S_fresh_sem")
    end

    results = Dict{Tuple{Int,Float64},NamedTuple}()
    t_start = time()

    for (gi, g) in enumerate(grid)
        L, p = g.L, g.p
        n_periods = 4L
        n_seeds = n_seeds_for(p, n_hi, n_lo)
        fr = zeros(n_seeds)
        t0 = time()
        Threads.@threads for s in 1:n_seeds
            seed = SEED_OFFSET + N_SEEDS_HI * (gi - 1) + s
            fr[s] = run_mipt_srn(L=L, p=p, seed=seed, n_periods=n_periods, maxdim=MAXDIM, cutoff=CUTOFF)
        end
        @printf("block L=%2d p=%.2f: %d seeds in %.1f s\n", L, p, n_seeds, time() - t0)

        r = (m=mean(fr), s=sem(fr), n=n_seeds)
        results[(L, p)] = r
        open(CSV_PATH, "a") do io
            @printf(io, "%d,%.2f,%d,%.8f,%.8f\n", L, p, n_seeds, r.m, r.s)
        end
    end
    wall = time() - t_start
    @printf("\nTotal sweep wall time: %.1f s\n", wall)
    println("Done. CSV: $CSV_PATH")

    if SMOKE
        println("SMOKE-RUN-OK")
        return
    end

    # --- SRN comparison over ALL digitized points (tolerance = 0.05 + 2*SEM) ---
    srn = load_srn(SRN_PATH)
    keys_sorted = sort(collect(keys(srn)), by=k -> (k[1], k[2]))
    println("\n--- SRN comparison (tolerance = 0.05 + 2*SEM per point) ---")
    println("L    p     S_SRN   S_fresh          delta     tol      match")
    n_ok = 0
    open(CMP_PATH, "w") do io
        println(io, "L,p,S_package,sem_package,S_srn,srn_precision,delta,within_combined_unc")
        for (L, p) in keys_sorted
            haskey(results, (L, p)) || continue
            r = results[(L, p)]
            sref = srn[(L, p)]
            delta = r.m - sref
            tol = 0.05 + 2 * r.s
            ok = abs(delta) < tol
            n_ok += ok
            @printf("%-4d %.2f  %.2f    %.3f±%.3f     %+.3f    %.3f    %s\n",
                    L, p, sref, r.m, r.s, delta, tol, ok ? "YES" : "no")
            @printf(io, "%d,%.2f,%.6f,%.6f,%.2f,0.05,%.6f,%s\n",
                    L, p, r.m, r.s, sref, delta, ok)
        end
    end
    n_total = length(keys_sorted)
    @printf("SRN-MATCH-FINAL: %d/%d within tol  [%s]\n", n_ok, n_total,
            n_ok >= 24 ? "PASS" : "FAIL")

    # --- Zigzag check at p=0.5: spread across all four L ---
    vals = [results[(L, 0.5)].m for L in L_LIST]
    sems = [results[(L, 0.5)].s for L in L_LIST]
    spread = maximum(vals) - minimum(vals)
    thresh = max(3 * sum(sems), 0.08)
    @printf("ZIGZAG-CHECK p=0.5: %s (spread=%.4f, threshold=%.4f, S={%s})\n",
            spread < thresh ? "PASS" : "FAIL", spread, thresh,
            join([@sprintf("%.4f", v) for v in vals], ", "))

    # --- Collapse check: area-law S is L-independent at p=0.4 and p=0.5 ---
    collapse_ok = true
    for p in (0.4, 0.5)
        v = [results[(L, p)].m for L in L_LIST]
        s = [results[(L, p)].s for L in L_LIST]
        sp = maximum(v) - minimum(v)
        th = max(3 * sum(s), 0.08)
        ok = sp < th
        collapse_ok &= ok
        @printf("  collapse p=%.1f: spread=%.4f, threshold=%.4f -> %s\n", p, sp, th, ok ? "ok" : "FAIL")
    end
    println("COLLAPSE-CHECK p=0.4/0.5: ", collapse_ok ? "PASS" : "FAIL")

    # --- p=0 Page check: S(p=0) should equal Page value L/2 - 1/(2 ln 2) within 5% ---
    page_ok = true
    for L in L_LIST
        r = results[(L, 0.0)]
        page = L / 2 - 1 / (2 * log(2))
        rel = abs(r.m - page) / page
        ok = rel < 0.05
        page_ok &= ok
        @printf("  p=0 L=%2d: S=%.4f±%.4f, Page=%.4f, rel.dev=%.2f%% -> %s\n",
                L, r.m, r.s, page, 100rel, ok ? "ok" : "FAIL")
    end
    println("P0-PAGE-CHECK: ", page_ok ? "PASS" : "FAIL")

    @printf("\nTotal wall time (sweep): %.1f s\n", wall)
    println("Comparison CSV: $CMP_PATH")
end

main()
