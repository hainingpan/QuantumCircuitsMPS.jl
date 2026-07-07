# Benchmark suite for QuantumCircuitsMPS.jl.
#
# AirspeedVelocity-compatible: this file defines a top-level `SUITE::BenchmarkGroup`.
# Run locally via `julia --project=benchmark benchmark/runbenchmarks.jl`.
#
# Scope is EXACTLY the 10-entry table from the v0.4.0 plan (task 12) — do NOT add
# scaling studies, memory profiling, or package comparisons here:
#
#   | #  | Benchmark                                   | Backend  | L   | Params                           |
#   |----|---------------------------------------------|----------|-----|----------------------------------|
#   | 1  | simulate! 1 MIPT step                       | MPS      | 20  | maxdim=64, Haar + p=0.15 measure |
#   | 2  | simulate! 1 MIPT step                       | SV       | 8   | same structure                   |
#   | 3  | simulate! 1 step RandomClifford+Measure     | Clifford | 100 | —                                |
#   | 4  | apply! HaarRandom(2) one bond               | MPS      | 20  | maxdim=64                        |
#   | 5  | apply! HaarRandom(2) one bond               | SV       | 8   | —                                |
#   | 6  | apply! RandomClifford(2) one bond           | Clifford | 100 | —                                |
#   | 7  | EntanglementEntropy(cut=L÷2)                | MPS L=20 / SV L=8 / Clifford L=100   |
#   | 8  | Magnetization(:Z)                           | MPS L=20 / SV L=8 / Clifford L=100   |
#   | 9  | elements(Bricklayer(:even), 100, :periodic) | —        | 100 | geometry-only micro-bench        |
#   | 10 | CZ build+apply one bond                     | MPS      | 12  | targets T21                      |
#
# Conventions:
# - All states use bc=:open with fixed RNGRegistry seeds, so gate/measurement draws
#   are deterministic and every sample measures identical work. The geometry
#   micro-bench (row 9) uses :periodic, as the scope table demands.
# - Mutating benchmarks (simulate!/apply!) use `setup` + `evals=1` so every
#   evaluation starts from a freshly initialized state.
# - Observable benchmarks (rows 7–8) run on a lightly entangled fixture (one even
#   bricklayer of entangling gates) so entropies/expectations are non-trivial.

using BenchmarkTools
using QuantumCircuitsMPS

const SUITE = BenchmarkGroup()

# ---------------------------------------------------------------------------
# Fixtures (setup helpers — never measured)
# ---------------------------------------------------------------------------

_rng() = RNGRegistry(gates_spacetime = 42, gates_realization = 2, born_measurement = 1)

function mps_state(L; maxdim = 64)
    state = SimulationState(L = L, bc = :open, maxdim = maxdim, rng = _rng())
    initialize!(state, ProductState(binary_int = 0))
    return state
end

function sv_state(L)
    state = SimulationState(L = L, bc = :open, backend = :statevector, rng = _rng())
    initialize!(state, ProductState(binary_int = 0))
    return state
end

function clifford_state(L)
    state = SimulationState(L = L, bc = :open, backend = :clifford, rng = _rng())
    initialize!(state, ProductState(binary_int = 0))
    return state
end

"One MIPT step: entangling even bricklayer + stochastic Z-measurement sublayer (p=0.15)."
function mipt_circuit(L, entangler)
    return Circuit(L = L, bc = :open) do c
        apply!(c, entangler, Bricklayer(:even))
        apply_with_prob!(c;
            outcomes = [(probability = 0.15, gate = Measure(:Z), geometry = AllSites())])
    end
end

"Apply one even bricklayer of `entangler` gates so observables see a non-trivial state."
function entangled(state, entangler)
    apply!(state, entangler, Bricklayer(:even))
    return state
end

const MIPT_MPS = mipt_circuit(20, HaarRandom(2))
const MIPT_SV = mipt_circuit(8, HaarRandom(2))
const MIPT_CLIFFORD = mipt_circuit(100, RandomClifford(2))

# ---------------------------------------------------------------------------
# Rows 1–3: simulate! one step
# ---------------------------------------------------------------------------

SUITE["simulate!"] = BenchmarkGroup()
SUITE["simulate!"]["mipt_step_mps_L20"] = @benchmarkable simulate!($MIPT_MPS, state;
    n_steps = 1) setup=(state = mps_state(20)) evals=1
SUITE["simulate!"]["mipt_step_sv_L8"] = @benchmarkable simulate!($MIPT_SV, state;
    n_steps = 1) setup=(state = sv_state(8)) evals=1
SUITE["simulate!"]["clifford_step_L100"] = @benchmarkable simulate!($MIPT_CLIFFORD, state;
    n_steps = 1) setup=(state = clifford_state(100)) evals=1

# ---------------------------------------------------------------------------
# Rows 4–6: apply! a single two-site gate on one bond
# ---------------------------------------------------------------------------

SUITE["apply!"] = BenchmarkGroup()
SUITE["apply!"]["haar2_one_bond_mps_L20"] = @benchmarkable apply!(state, $(HaarRandom(2)),
    $(AdjacentPair(10))) setup=(state = mps_state(20)) evals=1
SUITE["apply!"]["haar2_one_bond_sv_L8"] = @benchmarkable apply!(state, $(HaarRandom(2)),
    $(AdjacentPair(4))) setup=(state = sv_state(8)) evals=1
SUITE["apply!"]["randomclifford2_one_bond_clifford_L100"] = @benchmarkable apply!(state,
    $(RandomClifford(2)), $(AdjacentPair(50))) setup=(state = clifford_state(100)) evals=1

# ---------------------------------------------------------------------------
# Row 7: EntanglementEntropy(cut = L ÷ 2) on all 3 backends
# ---------------------------------------------------------------------------

const EE_MPS_STATE = entangled(mps_state(20), HaarRandom(2))
const EE_SV_STATE = entangled(sv_state(8), HaarRandom(2))
const EE_CLIFFORD_STATE = entangled(clifford_state(100), RandomClifford(2))

SUITE["entanglement_entropy"] = BenchmarkGroup()
SUITE["entanglement_entropy"]["mps_L20"] = @benchmarkable $(EntanglementEntropy(cut = 10))($EE_MPS_STATE)
SUITE["entanglement_entropy"]["sv_L8"] = @benchmarkable $(EntanglementEntropy(cut = 4))($EE_SV_STATE)
SUITE["entanglement_entropy"]["clifford_L100"] = @benchmarkable $(EntanglementEntropy(cut = 50))($EE_CLIFFORD_STATE)

# ---------------------------------------------------------------------------
# Row 8: Magnetization(:Z) on all 3 backends
# ---------------------------------------------------------------------------

const MZ_MPS_STATE = entangled(mps_state(20), HaarRandom(2))
const MZ_SV_STATE = entangled(sv_state(8), HaarRandom(2))
const MZ_CLIFFORD_STATE = entangled(clifford_state(100), RandomClifford(2))

SUITE["magnetization"] = BenchmarkGroup()
SUITE["magnetization"]["mps_L20"] = @benchmarkable $(Magnetization(:Z))($MZ_MPS_STATE)
SUITE["magnetization"]["sv_L8"] = @benchmarkable $(Magnetization(:Z))($MZ_SV_STATE)
SUITE["magnetization"]["clifford_L100"] = @benchmarkable $(Magnetization(:Z))($MZ_CLIFFORD_STATE)

# ---------------------------------------------------------------------------
# Row 9: geometry-only micro-benchmark (targets T23 elements() caching)
# ---------------------------------------------------------------------------

SUITE["geometry"] = BenchmarkGroup()
SUITE["geometry"]["elements_bricklayer_even_L100_periodic"] = @benchmarkable elements($(Bricklayer(:even)),
    100, :periodic)

# ---------------------------------------------------------------------------
# Row 10: CZ build+apply on one bond (targets T21 vectorized gate construction)
# ---------------------------------------------------------------------------

SUITE["gates"] = BenchmarkGroup()
SUITE["gates"]["cz_build_apply_one_bond_mps_L12"] = @benchmarkable apply!(state, $(CZ()),
    $(AdjacentPair(6))) setup=(state = mps_state(12)) evals=1
