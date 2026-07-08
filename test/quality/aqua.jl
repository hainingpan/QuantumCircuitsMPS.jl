# === QUALITY GATE: Aqua.jl (Auto QUality Assurance) — Task 29 ===
#
# Runs the full Aqua battery. Three checks carry TARGETED exclusions, each
# justified below; everything else runs at full strictness (method
# ambiguities for all other functions, unbound type parameters, undefined
# exports, Project.toml/test/Project.toml consistency, stale deps for all
# other packages, compat bounds, piracy for all other methods, persistent
# tasks).
#
# T2 baseline (pre-fix): 9 pass / 2 fail —
# .sisyphus/evidence/v04/task-2-aqua-baseline.log. The two failures were
# resolved as: JSON removed from root [deps] (genuinely unused in src/ and
# ext/; it is a test-only dep and lives in test/Project.toml), and the two
# documented exclusions below (SentinelRNG ambiguities, Luxor stale-dep
# false positive). The piracy exclusion covers T39's spin-S SiteType
# extension (added after the T2 baseline).

using Test
using Aqua
using Random
using ITensors
using QuantumCircuitsMPS

@testset "QUALITY Aqua.test_all (T29)" begin
    Aqua.test_all(QuantumCircuitsMPS;
        # --- ambiguities: exclude ONLY `rand`/`randn` ------------------------
        # SentinelRNG (src/Core/rng.jl, guarded-stream mechanism) deliberately
        # defines catch-all `Random.rand`/`Random.randn` overloads mirroring
        # Random's entry points so that ANY draw attempt on a guarded stream
        # errors with a prescriptive message instead of an obscure MethodError.
        # Aqua reports these catch-alls as ambiguous against specialized
        # rand/randn methods in Random/RandomExtensions/AbstractAlgebra/Nemo/
        # StaticArrays (transitive deps of QuantumClifford) — 150+ reports,
        # all one pattern. Any call actually hitting an ambiguity would error
        # by design anyway (that is the sentinel's entire purpose), and the
        # v0.4 plan guardrail forbids modifying SentinelRNG. Ambiguity
        # checking stays ACTIVE for every other function in the package.
        ambiguities = (exclude = [Random.rand, Random.randn],),
        # --- stale_deps: ignore ONLY Luxor -----------------------------------
        # Luxor is the [extensions] trigger for QuantumCircuitsMPSLuxorExt,
        # declared as a STRONG dep (in [deps], no [weakdeps]) — the supported
        # Julia 1.11+ "strong dep + extension" pattern that guarantees the
        # plotting extension always loads for users. src/ itself never does
        # `using Luxor` (by design — the ext does), which Aqua's stale_deps
        # check cannot distinguish from a genuinely unused dep. Known Aqua
        # false-positive pattern for weak-dep-via-strong-dep extensions.
        stale_deps = (ignore = [:Luxor],),
        # --- piracies: treat the ITensors SiteType hooks as own --------------
        # src/Core/spin_sites.jl registers the "S=3/2".."S=10" site types by
        # defining methods on ITensors.space/op/state/val — the OFFICIAL,
        # documented ITensors extension mechanism ("Extending ITensors"
        # docs). Dispatch is value-namespaced by the SiteType"S=k/2"
        # singleton parameter, which only this package registers (native
        # "S=1/2"/"S=1" behavior is NOT redefined — strictly additive), so no
        # foreign behavior can be altered. Aqua's ownership analysis sees
        # foreign function + foreign argument types and cannot recognize the
        # value-namespacing. Piracy checking stays ACTIVE for all other
        # methods.
        piracies = (treat_as_own = [ITensors.space, ITensors.op,
            ITensors.state, ITensors.val],))
end
