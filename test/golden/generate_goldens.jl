# Golden baseline generator — pre-refactor (Task 1, plan api-refactor-v0.1.md)
# Runs on the CURRENT engine; outputs test/golden/*.json.
# MUST be run before any src/ edit. Deterministic: two runs => byte-identical files.
using QuantumCircuitsMPS
using JSON

const GOLDEN_DIR = @__DIR__
const STREAMS = [:born_measurement, :gates_realization, :gates_spacetime, :state_init]  # sorted

# Draw one Float64 from each stream AFTER the run (mutates RNGs — call last).
function rng_fingerprints(registry)
    Dict(String(s) => rand(get_rng(registry, s)) for s in STREAMS)
end

# For fully deterministic nested dicts, serialize sorted-key ordered pairs manually.
function json_sorted(d::Dict)
    "{" * join(["\"$k\":$(JSON.json(v))" for (k, v) in sort(collect(d), by = first)], ",") *
    "}"
end

function write_golden_raw(name::String, ordered::Vector{Pair{String, String}})
    open(joinpath(GOLDEN_DIR, name), "w") do io
        print(io, "{", join(["\"$k\":$v" for (k, v) in ordered], ","), "}")
    end
    println("wrote $name")
end

# ---------- Case A: MIPT (single-outcome compound) ----------
function case_a()
    L, p, n_steps = 8, 0.15, 20
    circuit = Circuit(L = L, bc = :periodic) do c
        apply!(c, HaarRandom(), Bricklayer(:even))
        apply_with_prob!(c; outcomes = [
            (probability = p, gate = Measurement(:Z), geometry = AllSites())])
        apply!(c, HaarRandom(), Bricklayer(:odd))
        apply_with_prob!(c; outcomes = [
            (probability = p, gate = Measurement(:Z), geometry = AllSites())])
    end
    registry = RNGRegistry(gates_spacetime = 42, born_measurement = 1, gates_realization = 2)
    state = SimulationState(L = L, bc = :periodic, maxdim = 64, rng = registry)
    initialize!(state, ProductState(binary_int = 0))
    track!(state, :entropy => EntanglementEntropy(; cut = 4))
    simulate!(circuit, state; n_steps = n_steps, record_when = :every_step)

    entropy = Float64.(state.observables[:entropy])
    z_expect = [2 * born_probability(state, i, 0) - 1 for i in 1:L]
    fps = rng_fingerprints(registry)   # LAST: mutates streams
    write_golden_raw("case_a_mipt.json",
        [
            "params" => json_sorted(Dict("L"=>L, "p"=>p, "n_steps"=>n_steps,
                "seeds"=>"gates_spacetime=42,born_measurement=1,gates_realization=2,state_init=0")),
            "entropy" => JSON.json(entropy),
            "z_expectation" => JSON.json(z_expect),
            "rng_fingerprints" => json_sorted(fps)
        ])
    return entropy
end

# ---------- Case C: CIPT (K=1 categorical) ----------
function case_c()
    L, p_ctrl = 8, 0.5
    n_steps = 2 * L^2
    left, right = StaircaseLeft(1), StaircaseRight(1)
    circuit = Circuit(L = L, bc = :periodic, p_ctrl = p_ctrl) do c
        apply_with_prob!(c;
            outcomes = [
                (probability = c.params[:p_ctrl], gate = Reset(), geometry = left),
                (probability = 1-c.params[:p_ctrl], gate = HaarRandom(), geometry = right)])
    end
    registry = RNGRegistry(gates_spacetime = 42, born_measurement = 1, gates_realization = 2)
    state = SimulationState(L = L, bc = :periodic, maxdim = 64, rng = registry)
    initialize!(state, ProductState(binary_int = 0))
    track!(state, :Mz => Magnetization(:Z))
    simulate!(circuit, state; n_steps = n_steps, record_when = :every_gate)

    mz = Float64.(state.observables[:Mz])
    fps = rng_fingerprints(registry)
    write_golden_raw("case_c_cipt.json",
        [
            "params" => json_sorted(Dict("L"=>L, "p_ctrl"=>p_ctrl, "n_steps"=>n_steps)),
            "Mz" => JSON.json(mz),
            "rng_fingerprints" => json_sorted(fps)
        ])
    return mz
end

# ---------- Case D: deterministic Bricklayer Haar ----------
function case_d()
    L, n_steps = 8, 10
    circuit = Circuit(L = L, bc = :periodic) do c
        apply!(c, HaarRandom(), Bricklayer(:even))
        apply!(c, HaarRandom(), Bricklayer(:odd))
    end
    registry = RNGRegistry(gates_spacetime = 42, born_measurement = 1, gates_realization = 2)
    state = SimulationState(L = L, bc = :periodic, maxdim = 64, rng = registry)
    initialize!(state, ProductState(binary_int = 0))
    track!(state, :entropy => EntanglementEntropy(; cut = 4))
    simulate!(circuit, state; n_steps = n_steps, record_when = :every_step)

    entropy = Float64.(state.observables[:entropy])
    p0 = [born_probability(state, i, 0) for i in 1:L]
    fps = rng_fingerprints(registry)
    write_golden_raw("case_d_haar.json",
        [
            "params" => json_sorted(Dict("L"=>L, "n_steps"=>n_steps)),
            "entropy" => JSON.json(entropy),
            "born_probability_0" => JSON.json(p0),
            "rng_fingerprints" => json_sorted(fps)
        ])
    return entropy
end

# ---------- AKLT p_nn=1.0 (degenerate Case B) ----------
function case_aklt()
    L, bc, p_nn = 12, :periodic, 1.0
    P0, P1 = total_spin_projector(0), total_spin_projector(1)
    proj_gate = SpinSectorProjection(P0 + P1)
    circuit = Circuit(L = L, bc = bc) do c
        apply_with_prob!(c;
            outcomes = [
                (probability = p_nn, gate = proj_gate, geometry = Bricklayer(:nn)),
                (probability = 1-p_nn, gate = proj_gate, geometry = Bricklayer(:nnn))])
    end
    registry = RNGRegistry(gates_spacetime = 42, gates_realization = 2, born_measurement = 3)
    state = SimulationState(L = L, bc = bc, site_type = "S=1", maxdim = 128, rng = registry)
    initialize!(state, ProductState(spin_state = "Z0"))
    track!(state, :entropy => EntanglementEntropy(cut = L÷2, renyi_index = 1, base = 2))
    track!(state, :string_order => StringOrder(1, L÷2+1, order = 1))
    simulate!(circuit, state; n_steps = L, record_when = :every_step)

    S = Float64(state.observables[:entropy][end])
    SO = Float64(state.observables[:string_order][end])
    fps = rng_fingerprints(registry)
    write_golden_raw("case_aklt_pnn1.json",
        [
            "params" => json_sorted(Dict("L"=>L, "p_nn"=>p_nn, "n_steps"=>L)),
            "final_entropy" => JSON.json(S),
            "string_order" => JSON.json(SO),
            "rng_fingerprints" => json_sorted(fps)
        ])
    return S, SO
end

eA = case_a();
println("Case A entropy: first=$(eA[1]) last=$(eA[end])")
mz = case_c();
println("Case C Mz: first=$(mz[1]) last=$(mz[end]) (n=$(length(mz)))")
eD = case_d();
println("Case D entropy: first=$(eD[1]) last=$(eD[end])")
S, SO = case_aklt();
println("AKLT: S=$S |SO|=$(abs(SO))")
println("GOLDENS: DONE")
