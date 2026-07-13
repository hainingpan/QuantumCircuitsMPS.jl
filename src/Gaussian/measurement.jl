# === Gaussian Born Probability + Measurement ===
# Occupation (Z-basis) measurement support for SimulationState{GaussianBackend}.
#
# Like the Clifford backend, the Gaussian backend does NOT go through the
# generic Projection-based `_measure_single_site!` path (Core/apply.jl):
# `Projection` is not a Gaussian gate and is rejected by Gaussian.jl's
# fallback `_apply_single!`. Instead we override `born_probability` (a
# direct, non-destructive covariance-matrix read) and
# `_measure_single_site!` (parity projection via the contraction kernel).
# `Measure(:Z)` and `Reset` then flow through the EXISTING generic
# `execute!` methods in Core/apply.jl unchanged.
#
# Occupation convention (VERIFIED empirically, see kernel.jl header and
# .sisyphus/notepads/gaussian-backend/learnings.md, Task 2):
#   ⟨cᵢ†cᵢ⟩ = (1 − Γ[2i−1, 2i]) / 2
#   Γ[2i−1,2i] = +1 ⇒ unoccupied (outcome 0);  −1 ⇒ occupied (outcome 1).

"""
    born_probability(state::SimulationState{GaussianBackend}, site::Int, outcome::Int) -> Float64

Compute the Born probability of measuring occupation `outcome` (0 =
unoccupied, 1 = occupied) at physical `site` for a fermionic Gaussian state.

For a Gaussian state the on-site occupation probability is an affine
function of a SINGLE covariance-matrix element `g = Γ[2i−1, 2i]` (with `i`
the RAM-mapped mode index):

    P(0) = (1 + g) / 2        P(1) = (1 − g) / 2

(equivalently `P(1) = ⟨cᵢ†cᵢ⟩`, verified convention: vacuum has `g = +1`
⇒ `P(0) = 1.0` exactly). This is a NON-DESTRUCTIVE, read-only query — a
single matrix-element read, no copies, `state.backend.corr` is untouched.

The raw affine value is returned without clamping: for a purified state
`|g| ≤ 1` up to machine precision, so any excursion outside `[0, 1]` is
at the 1e-15 level and harmless to the `rand() < p₀` threshold convention.
"""
function born_probability(state::SimulationState{GaussianBackend}, site::Int, outcome::Int)
    state.backend.majoranas_per_site == 1 && throw(ArgumentError(
        "born_probability is not defined on a Majorana chain (site_type=\"Majorana\"): a " *
        "single Majorana site has no parity; use BondParity on an adjacent pair instead."))
    outcome in (0, 1) || throw(ArgumentError(
        "Gaussian born_probability outcome must be 0 (unoccupied) or 1 (occupied), got $outcome"))
    1 <= site <= length(state.phy_ram) || throw(ArgumentError(
        "site $site out of range 1:$(length(state.phy_ram))"))
    Γ = state.backend.corr
    Γ === nothing && throw(ArgumentError(
        "Gaussian state is not initialized — call initialize!(state, ...) before measuring."))
    a, b = site_majoranas(state, site)
    g = Γ[a, b]
    return outcome == 0 ? (1 + g) / 2 : (1 - g) / 2
end

"""
    _measure_single_site!(state::SimulationState{GaussianBackend}, site::Int) -> Int

Override the default (Projection-based) `_measure_single_site!` for the
Gaussian backend. Born-samples the occupation of `site` and collapses the
covariance matrix onto the observed parity sector via
[`gaussian_contraction!`](@ref) with the projector
[`parity_projection_upsilon`](@ref), mutating `state.backend.corr` in place.

**Draw contract (REDUNDANT-DRAW, cross-backend lockstep):** exactly ONE
scalar `:born_measurement` draw is consumed per measured site — always,
unconditionally, BEFORE any probability computation — matching the generic
MPS/SV `_measure_single_site!` (Core/apply.jl) and the Clifford override
(src/Clifford/measurement.jl) draw-for-draw. The outcome uses the shared
threshold convention `outcome = r < p₀ ? 0 : 1`; probabilities are
continuous here, so no deterministic branch is needed — the draw is always
genuinely consumed by the comparison (for a deterministic site `p₀ ∈ {0,1}`
and the comparison is vacuous, i.e. the draw is redundant, exactly as on
the Clifford backend).

**Outcome → parity sign mapping (VERIFIED empirically, T2/T8):** the kernel
projector `parity_projection_upsilon(s)` leaves the post-measurement state
with `Γ[2i−1, 2i] = −s`. To end with `Γ[2i−1,2i] = +1` (outcome 0,
unoccupied) we contract with `s = −1`; for `Γ[2i−1,2i] = −1` (outcome 1,
occupied), `s = +1`. I.e. `s = 2·outcome − 1`.

Throws `ArgumentError` if the sampled outcome has probability ≤ 1e-15
(probability-zero branch — cannot be projected onto);
`gaussian_contraction!` additionally raises its own singular-matrix
`ArgumentError` as a second line of defense.

Logs a `MeasurementOutcome` event exactly like the default implementation
(Core/apply.jl) does, and returns the outcome (0 or 1).
"""
function _measure_single_site!(state::SimulationState{GaussianBackend}, site::Int)
    state.backend.majoranas_per_site == 1 && throw(ArgumentError(
        "Measure(:Z)/Reset are not defined on a Majorana chain (site_type=\"Majorana\"): a " *
        "single Majorana site has no parity; use BondParity on an adjacent pair instead."))
    Γ = state.backend.corr
    Γ === nothing && throw(ArgumentError(
        "Gaussian state is not initialized — call initialize!(state, ...) before measuring."))
    # REDUNDANT-DRAW CONTRACT: draw BEFORE computing any probability, exactly
    # one scalar per measured site (mirrors Core/apply.jl line-for-line), so
    # the :born_measurement stream advances identically on all backends.
    born_measurement_rng = get_rng(state.rng_registry, :born_measurement)
    r = rand(born_measurement_rng)
    p0 = born_probability(state, site, 0)
    outcome = r < p0 ? 0 : 1
    p_outcome = outcome == 0 ? p0 : 1 - p0
    p_outcome > 1e-15 || throw(ArgumentError(
        "measurement collapse onto outcome $outcome at site $site has vanishing " *
        "probability ($p_outcome) — cannot project onto a probability-zero branch."))
    # outcome=0 (unoccupied, target Γ[2i-1,2i]=+1) ⇒ s=-1; outcome=1 ⇒ s=+1.
    s = 2 * outcome - 1
    ix = collect(site_majoranas(state, site))
    gaussian_contraction!(Γ, parity_projection_upsilon(s), ix;
        scratch = state.backend.scratch, purify_tol = state.backend.purify_tol)
    if state.event_log !== nothing
        log_event!(state, MeasurementOutcome(state.event_step, state.event_op_idx, [site], outcome))
    end
    return outcome
end

"""
    execute!(state::SimulationState{GaussianBackend}, gate::BondParity, phy_sites::Vector{Int})

Projective measurement of the BOND fermion parity `i γ_a γ_b` on the two
INNER Majoranas of an adjacent-site bond, for the fermionic Gaussian backend.

**Inner-Majorana convention:** site `i` carries Majoranas `(2i−1, 2i)`
(RAM-mapped). For the bond between sites `(i, i+1)` the measured pair is
`ix = [2i, 2i+1]` — site `i`'s SECOND Majorana and site `i+1`'s FIRST
Majorana. For the periodic wrap bond `(L, 1)` (only valid when
`state.bc == :periodic`) the pair is `ix = [2L, 1]` — site `L`'s second
Majorana and site `1`'s first. Sites may be passed in either order
(`[i, i+1]` or `[i+1, i]`); non-adjacent pairs throw `ArgumentError`, as
does the wrap bond under `bc = :open`.

**Majorana-chain granularity** (`site_type="Majorana"`,
`majoranas_per_site == 1`): each site IS one Majorana, so the bond
`(i, i+1)` measures the pair `ix = [i, i+1]` directly — this is the
`i γ_i γ_{i+1}` parity measurement of the class-DIII monitored Majorana
chain (wrap bond `(L, 1)` → `ix = [L, 1]` under PBC). Same Born rule, same
kernel, same draw contract — only the site→Majorana index mapping (via
[`site_majoranas`](@ref)) differs.

**Born rule (VERIFIED empirically vs the T5 ED/Pfaffian oracle, T9):** the
covariance element `g = Γ[ix₁, ix₂]` satisfies `⟨i γ̂_{ix₁} γ̂_{ix₂}⟩ = −g`,
so with the outcome encoding `outcome ∈ (0, 1) ↔ parity eigenvalue
s = 2·outcome − 1 ∈ (−1, +1)`:

    P(outcome = 0) = (1 + g)/2        P(outcome = 1) = (1 − g)/2

— the SAME affine structure as the on-site occupation measurement
(`_measure_single_site!`), because on-site occupation is itself the bond
parity of the intra-mode pair (`n = (1 + iγ₁γ₂)/2`). The kernel `s` IS the
measured parity eigenvalue: contracting `parity_projection_upsilon(s)`
leaves `Γ[ix₁, ix₂] = −s`, i.e. `⟨i γ̂ γ̂⟩ = s` post-measurement.

**Draw contract (REDUNDANT-DRAW, cross-backend lockstep):** exactly ONE
scalar `:born_measurement` draw is consumed per BondParity application —
always, unconditionally, BEFORE any probability computation — matching
`_measure_single_site!` draw-for-draw.

Throws `ArgumentError` if the sampled outcome has probability ≤ 1e-15.
Logs a `MeasurementOutcome` event exactly like `Measure`'s `execute!`
(via `_measure_single_site!`) does. Returns `nothing`.
"""
function execute!(state::SimulationState{GaussianBackend}, gate::BondParity, phy_sites::Vector{Int})
    if support(gate) != length(phy_sites)
        throw(ArgumentError("Gate support $(support(gate)) does not match sites $(length(phy_sites))"))
    end
    Γ = state.backend.corr
    Γ === nothing && throw(ArgumentError(
        "Gaussian state is not initialized — call initialize!(state, ...) before measuring."))
    L = length(state.phy_ram)
    a, b = phy_sites
    (1 <= a <= L && 1 <= b <= L) || throw(ArgumentError(
        "BondParity sites $phy_sites out of range 1:$L"))
    # Normalize orientation to the ordered bond (lo, lo+1), or the PBC wrap
    # bond (L, 1). Plain adjacency wins over the wrap interpretation (only
    # relevant at L=2 periodic, where (1,2)/(2,1) is the inner bond).
    local lo::Int, hi::Int
    if b == a + 1
        lo, hi = a, b
    elseif a == b + 1
        lo, hi = b, a
    elseif state.bc == :periodic && ((a == L && b == 1) || (a == 1 && b == L))
        lo, hi = L, 1  # PBC wrap bond
    else
        throw(ArgumentError(
            "BondParity requires two ADJACENT sites (|a−b| == 1, or the (L, 1) wrap " *
            "bond under bc=:periodic). Got sites $phy_sites with L=$L, bc=$(state.bc)."))
    end
    # Inner Majoranas of the bond, granularity-aware via site_majoranas:
    # fermionic — lower site's SECOND Majorana, upper site's FIRST (RAM-
    # mapped): [2·lo, 2·hi − 1], wrap bond (L, 1) → [2L, 1]. Majorana chain
    # (majoranas_per_site == 1) — each site IS one Majorana: bond (i, i+1)
    # → [i, i+1], wrap bond (L, 1) → [L, 1].
    ix = [last(site_majoranas(state, lo)), first(site_majoranas(state, hi))]
    # REDUNDANT-DRAW CONTRACT: draw BEFORE computing any probability, exactly
    # one scalar per measurement (mirrors _measure_single_site! line-for-line).
    born_measurement_rng = get_rng(state.rng_registry, :born_measurement)
    r = rand(born_measurement_rng)
    g = Γ[ix[1], ix[2]]
    p0 = (1 + g) / 2          # P(outcome 0, bond parity iγγ = −1); verified vs oracle
    outcome = r < p0 ? 0 : 1
    p_outcome = outcome == 0 ? p0 : 1 - p0
    p_outcome > 1e-15 || throw(ArgumentError(
        "BondParity collapse onto outcome $outcome on bond ($lo, $hi) has vanishing " *
        "probability ($p_outcome) — cannot project onto a probability-zero branch."))
    s = 2 * outcome - 1       # measured parity eigenvalue; post Γ[ix₁,ix₂] = −s
    gaussian_contraction!(Γ, parity_projection_upsilon(s), ix;
        scratch = state.backend.scratch, purify_tol = state.backend.purify_tol)
    if state.event_log !== nothing
        log_event!(state, MeasurementOutcome(state.event_step, state.event_op_idx, [lo, hi], outcome))
    end
    return nothing
end
