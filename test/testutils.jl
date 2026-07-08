# test/testutils.jl
#
# Shared test utilities — plain definitions ONLY (no @testset, no side
# effects). Included unconditionally near the top of runtests.jl, so every
# test file in the suite can rely on these being defined. Files that support
# standalone execution (`julia --project=. test/<file>.jl`) guard with:
#
#     @isdefined(reference_select) || include("testutils.jl")
#
# reference_select — reference implementation of the unified stochastic rule
# (Task 7). This is the semantic ORACLE for the engine (Task 9) and migration
# audits (Task 16); its own self-tests live in test/reference_rule.jl.
#
# RNG contract (plan "Oracle Review" refinements):
#   - Per element k = 1..K: exactly ONE scalar rand(rng). Never rand(rng, K).
#   - Consumption is data-independent: K draws always, regardless of outcome.
#   - Selection: cumulative walk over probs with strict `<`.
#   - Returns 1-based outcome index per element, or 0 for identity remainder.
#   - Cumsum snapping: if abs(sum(probs) - 1) <= 1e-10, the LAST cumulative
#     boundary is snapped to exactly 1.0, so float dust in Σp cannot leak
#     spurious identity selections.

using Random

function reference_select(rng, probs::Vector{Float64}, K::Int)::Vector{Int}
    n = length(probs)
    snap = abs(sum(probs) - 1.0) <= 1e-10
    out = Vector{Int}(undef, K)
    for k in 1:K
        r = rand(rng)              # exactly one scalar draw per element
        cumulative = 0.0
        selected = 0               # 0 = identity remainder
        for i in 1:n
            cumulative += probs[i]
            boundary = (snap && i == n) ? 1.0 : cumulative
            if r < boundary        # strict <
                selected = i
                break
            end
        end
        out[k] = selected
    end
    return out
end

# ═══════════════════════════════════════════════════════════════════════════
# Shared cross-validation state builders (T28 DRY extraction)
# ═══════════════════════════════════════════════════════════════════════════
# Single-sourced here from their former duplicated homes:
#   - make_pair                        (ex test/statevector/cross_validation.jl)
#   - _make_state / make_triple        (ex test/clifford/cross_validation.jl)
#   - _mps_state/_sv_state/_*_bin      (ex test/gates/test_new_gates.jl)
#   - inline per-runner construction   (ex test/audit/cross_backend.jl)
# All are thin wrappers around ONE core constructor, `make_backend_state`,
# with each wrapper preserving its original signature and defaults exactly.
# Subdirectory test files that support standalone execution guard with:
#
#     @isdefined(make_backend_state) || include(joinpath(@__DIR__, "..", "testutils.jl"))

"""
    make_backend_state(backend, L; bc=:open, binary_int=0, maxdim=nothing,
                       seeds=(gates_spacetime=42, gates_realization=7, born_measurement=99),
                       kwargs...)

Fresh `SimulationState` of the requested backend (`:mps`, `:statevector`,
`:clifford`), initialized to `ProductState(binary_int=binary_int)`.

`maxdim` is forwarded ONLY for the MPS backend (`nothing` → constructor
default), matching the historical `backend == :mps ? (maxdim=...,) :
(backend=backend,)` pattern. Extra `kwargs` (e.g. `log_events`) pass through
to `SimulationState`.
"""
function make_backend_state(backend::Symbol, L::Int;
        bc = :open, binary_int = 0, maxdim = nothing,
        seeds = (gates_spacetime = 42, gates_realization = 7, born_measurement = 99),
        kwargs...)
    backend_kwargs = if backend == :mps
        maxdim === nothing ? NamedTuple() : (; maxdim = maxdim)
    else
        (; backend = backend)
    end
    state = SimulationState(; L = L, bc = bc, backend_kwargs..., kwargs...,
        rng = RNGRegistry(; seeds...))
    initialize!(state, ProductState(binary_int = binary_int))
    return state
end

# ── Paired MPS + SV states with identical seeds (statevector cross-val) ─────
function make_pair(; L, bc = :open,
        seeds = (gates_spacetime = 42, gates_realization = 7, born_measurement = 99))
    mps_state = make_backend_state(:mps, L; bc = bc, maxdim = 256, seeds = seeds)
    sv_state = make_backend_state(:statevector, L; bc = bc, seeds = seeds)
    return mps_state, sv_state
end

# ── One state of a given backend / the (mps, sv, clifford) triple ───────────
function _make_state(L::Int, backend::Symbol;
        bc = :open, seeds = (
            gates_spacetime = 42, gates_realization = 7, born_measurement = 99))
    return make_backend_state(backend, L; bc = bc, seeds = seeds)
end

function make_triple(; L, bc = :open,
        seeds = (gates_spacetime = 42, gates_realization = 7, born_measurement = 99))
    mps_s = _make_state(L, :mps; bc = bc, seeds = seeds)
    sv_s = _make_state(L, :statevector; bc = bc, seeds = seeds)
    cl_s = _make_state(L, :clifford; bc = bc, seeds = seeds)
    return mps_s, sv_s, cl_s
end

# ── Gate-suite builders (gates/test_new_gates.jl conventions) ────────────────
# Fresh |0...0⟩ MPS state (matches gates_api.jl convention)
function _mps_state(L::Int; bc = :open,
        seeds = (gates_spacetime = 11, gates_realization = 22, born_measurement = 33))
    return make_backend_state(:mps, L; bc = bc, maxdim = 64, seeds = seeds)
end

# Fresh |0...0⟩ SV state
function _sv_state(L::Int; bc = :open,
        seeds = (gates_spacetime = 11, gates_realization = 22, born_measurement = 33))
    return make_backend_state(:statevector, L; bc = bc, seeds = seeds)
end

# Fresh MPS state initialized to a given binary_int
function _mps_state_bin(L::Int, bin::Int;
        seeds = (gates_spacetime = 11, gates_realization = 22, born_measurement = 33))
    return make_backend_state(:mps, L; maxdim = 64, binary_int = bin, seeds = seeds)
end

# Fresh SV state initialized to a given binary_int
function _sv_state_bin(L::Int, bin::Int;
        seeds = (gates_spacetime = 11, gates_realization = 22, born_measurement = 33))
    return make_backend_state(:statevector, L; binary_int = bin, seeds = seeds)
end
