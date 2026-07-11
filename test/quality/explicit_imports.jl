# === QUALITY GATE: ExplicitImports.jl — Task 29 (standing check) ===
#
# Guards the explicit-import discipline established in T29: every name the
# package uses from a dependency is imported explicitly (`using X: name`) in
# the header block of src/QuantumCircuitsMPS.jl — no implicit `using X`
# reliance — and no explicitly-imported name is stale (imported but unused).
#
# Deliberately NOT enforced here (both are advisory findings we accept, see
# .sisyphus/evidence/v04/task-29-explicitimports-after.log):
#   - `check_all_qualified_accesses_via_owners`: flags `Random.rand`/
#     `Random.randn` (owner: Base) in the SentinelRNG overload block of
#     src/Core/rng.jl. That block is frozen by the v0.4 plan guardrail (no
#     SentinelRNG changes), and `Random.rand === Base.rand` anyway.
#   - `check_all_explicit_imports_are_public`: flags the `ITensors.op`/
#     `ITensors.state` SiteType hook definitions in src/Core/spin_sites.jl.
#     Defining `ITensors.op(::OpName"...", ::SiteType"...")` is the official
#     documented ITensors custom-site-type extension idiom, even though those
#     bindings are not formally marked `public` in ITensors 0.9.

using Test
using ExplicitImports
using QuantumCircuitsMPS

@testset "QUALITY ExplicitImports (T29)" begin
    # `check_*` functions return `nothing` when clean, throw otherwise —
    # the `=== nothing` form surfaces the diagnostic as a test error.
    @test check_no_implicit_imports(QuantumCircuitsMPS) === nothing
    @test check_no_stale_explicit_imports(QuantumCircuitsMPS) === nothing
end
