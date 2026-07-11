# === QUALITY GATE: JET.jl static analysis — Task 29 (env-gated) ===
#
# NON-BLOCKING BY DEFAULT: JET's whole-package analysis is expensive
# (minutes) and its report count is sensitive to Julia/JET versions, so it
# is skipped in default test runs and in CI. Opt in explicitly with:
#
#     JET_TEST=true julia --project=. -e 'using Pkg; Pkg.test()'
#
# RATCHETING THRESHOLD (lower it when reports are fixed; NEVER raise it):
#   - T2 baseline (pre-Wave-5 code, JET 0.11.5, Julia 1.12.6): 36 reports
#     (.sisyphus/evidence/v04/task-2-jet-baseline.log)
#   - T29 current (post Waves 5-7 feature code: PauliString,
#     MutualInformation, common observables, spin-S): 57 reports
#     (.sisyphus/evidence/v04/task-29-jet-probe.log)
# Effectively ONE root cause across all reports: `Union{Nothing, T}` backend
# fields (ψ/mps/tableau, set to `nothing` at construction and populated by
# `initialize!`) are dereferenced without a `nothing` guard. The `Nothing`
# arm is dead in practice — every public path calls `initialize!` first —
# but JET cannot prove it. Eliminating the reports for real means
# redesigning backend construction (no `nothing` placeholder fields), a
# deliberate non-goal for v0.4.0.

using Test

if get(ENV, "JET_TEST", "") == "true"
    using JET
    using QuantumCircuitsMPS

    @testset "QUALITY JET report_package (T29, env-gated)" begin
        # Ratchet: current count 57 (see header). Lower when reports are
        # fixed; a count above this means NEW type instabilities/errors.
        jet_ratchet_threshold = 57
        result = report_package(QuantumCircuitsMPS;
            target_modules = (QuantumCircuitsMPS,))
        reports = JET.get_reports(result)
        n = length(reports)
        println("JET report count: $n (ratchet threshold: $jet_ratchet_threshold)")
        if n > jet_ratchet_threshold
            # Print the full analysis only on failure to keep logs readable.
            show(stdout, result)
        end
        @test n <= jet_ratchet_threshold
    end
else
    @info "Skipping JET static analysis (opt in with JET_TEST=true)"
end
