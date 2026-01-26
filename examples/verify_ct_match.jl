using Test

using Serialization

const REPO_ROOT = dirname(@__DIR__)
const CT_ROOT = joinpath(dirname(REPO_ROOT), "CT_MPS")
const CT_SCRIPT = joinpath(CT_ROOT, "run_CT_MPS_C_m_O_T.jl")
const CT_OUTPUT = joinpath(REPO_ROOT, "examples/ct_results.bin")

ct_expr = "using Serialization; cd(\"$(CT_ROOT)\"); include(\"$(CT_SCRIPT)\"); serialize(\"$(CT_OUTPUT)\", run_Oi_t(10, 0.5, 0.0, 42, 123))"
ct_cmd = `julia --project=$(joinpath(CT_ROOT, "CT")) -e $ct_expr`
run(ct_cmd)

ct_results = deserialize(CT_OUTPUT)

using QuantumCircuitsMPS
include(joinpath(REPO_ROOT, "examples/monitored_circuit.jl"))

new_results = simulate(
    MonitoredCircuit(10, 0.5, 0.0, 100),
    seed_circuit=42,
    seed_meas=123,
    x0=1 // big(2)^10,
)

ct_Oi = ct_results["Oi"]
new_Oi = reduce(hcat, new_results.observables[:Zi])'
max_diff = maximum(abs.(ct_Oi .- new_Oi))

@test size(ct_Oi) == size(new_Oi) == (101, 10)
@test max_diff < 1e-10

println("Maximum difference: $max_diff")
println("SUCCESS: Results match CT.jl within 1e-10")
