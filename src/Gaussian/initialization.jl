# src/Gaussian/initialization.jl
# initialize! methods for the Gaussian (free-fermion covariance-matrix)
# backend. Builds the 2L×2L Majorana covariance matrix Γ in
# `state.backend.corr` and preallocates the same-size `state.backend.scratch`
# buffer used by the gate-application kernel (src/Gaussian/kernel.jl).

"""
    initialize!(state::SimulationState{GaussianBackend}, init::ProductState)

Initialize a Gaussian-backend `SimulationState` with a computational-basis
(occupation-number) product state, based on the specified initialization
method (`binary_int`, `binary_decimal`, or `bitstring`). Reuses the EXACT
SAME bit-pattern-string derivation logic as the MPS/state-vector/Clifford
paths (`_bit_pattern_string` in `src/State/initialization.jl`).

`init.spin_state` is NOT supported: the Gaussian backend is fermionic-mode
only (`local_dim=2`, enforced at construction time in `src/State/State.jl`),
while `spin_state` is an S=1/qudit-oriented field.

Site 1 = MSB (most significant bit) — identical convention to the other
backends. Bit `1` at site `i` means mode `i` is OCCUPIED (⟨cᵢ†cᵢ⟩ = 1,
covariance block `Γ[2i−1,2i] = −1`); bit `0` means unoccupied
(`Γ[2i−1,2i] = +1`). Since `ram_phy`/`phy_ram` are the IDENTITY for the
Gaussian backend, no physical-to-RAM reordering is applied — physical site i
directly corresponds to Majorana pair (2i−1, 2i).

**Majorana-chain granularity** (`site_type="Majorana"`,
`state.backend.majoranas_per_site == 1`): each site is ONE Majorana mode
and the product-state covariance is the DIMERIZED pairing
⊕ₖ [[0,1],[−1,0]] over consecutive site pairs `(γ_{2k−1}, γ_{2k})`,
k = 1..L÷2. The bit pattern therefore has length **L÷2** (NOT L): bit `k`
sets the parity sign of the pair `(γ_{2k−1}, γ_{2k})` — bit `0` ⇒
`Γ[2k−1,2k] = +1` (parity `iγγ = −1`, the "vacuum" sign), bit `1` ⇒
`Γ[2k−1,2k] = −1`. The pattern is derived by the shared
`_bit_pattern_string` helper with length L÷2, so `binary_int` is padded to
L÷2 binary digits and an explicit `bitstring` is padded/truncated to
exactly L÷2 characters — i.e. the pattern length is always exactly L÷2.

Allocates `state.backend.corr` (via [`occupation_covariance`](@ref); `2L×2L`
fermionic, `L×L` Majorana chain) and a zeroed same-size
`state.backend.scratch` buffer. Returns `state`.
"""
function initialize!(state::SimulationState{GaussianBackend}, init::ProductState)
    L = state.L

    if init.spin_state !== nothing
        throw(ArgumentError(
            "Gaussian backend does not support spin_state initialization " *
            "(fermionic modes only, use binary_int/bitstring/binary_decimal instead)"
        ))
    end

    # Total Majorana count and number of dimerized pairs: fermionic mode
    # granularity has n_maj = 2L (L pairs, one per site); the Majorana chain
    # has n_maj = L (L÷2 pairs spanning consecutive site pairs; L is even,
    # validated at construction in src/State/State.jl).
    n_maj = L * state.backend.majoranas_per_site
    n_pairs = n_maj ÷ 2

    # Convert init specification to bit pattern string (shared with the
    # MPS/SV/Clifford paths via `_bit_pattern_string`, defined in
    # src/State/initialization.jl). Fermionic: bit_pattern_str[i] is the bit
    # value at PHYSICAL site i (MSB at site 1). Majorana chain: bit k sets
    # the parity sign of the consecutive Majorana pair (2k−1, 2k).
    bit_pattern_str = _bit_pattern_string(init, n_pairs, state.local_dim)

    # bit '1' ⇒ pair sign flipped (Γ[2k−1,2k] = −1), '0' ⇒ vacuum sign (+1)
    bits = [c == '1' for c in bit_pattern_str]

    state.backend.corr = occupation_covariance(bits)
    state.backend.scratch = zeros(Float64, n_maj, n_maj)

    return state
end

"""
    initialize!(state::SimulationState{GaussianBackend}, init::RandomGaussianState)

Initialize a Gaussian-backend `SimulationState` with a Haar-random pure
fermionic Gaussian state: draw `O ∈ SO(N)` exactly Haar-distributed (via
[`haar_orthogonal`](@ref)), with `N` the total Majorana count
(`N = 2L` fermionic-mode granularity; `N = L` for the Majorana chain,
`site_type="Majorana"`), and rotate the vacuum covariance matrix,
`Γ = O·Γ₀·Oᵀ`, which preserves purity (`Γ² = −I`) and antisymmetry.

Requires an `RNGRegistry` attached to the state; the orthogonal matrix is
drawn deterministically from the registry's `:state_init` stream — the same
seed produces a bitwise-identical Γ.

Allocates `state.backend.corr` and a zeroed `2L×2L` `state.backend.scratch`
buffer. Returns `state`.
"""
function initialize!(state::SimulationState{GaussianBackend}, init::RandomGaussianState)
    if state.rng_registry === nothing
        throw(ArgumentError(
            "RandomGaussianState requires RNGRegistry with :state_init stream. " *
            "Attach RNG before calling initialize! via: " *
            "state = SimulationState(..., rng=RNGRegistry(...))"
        ))
    end

    L = state.L
    n_maj = L * state.backend.majoranas_per_site
    rng = get_rng(state.rng_registry, :state_init)

    O = haar_orthogonal(rng, n_maj)
    Γ = O * vacuum_covariance(n_maj ÷ 2) * transpose(O)
    # Explicitly antisymmetrize to scrub floating-point drift from the
    # similarity transform (Γ is antisymmetric up to roundoff already).
    Γ .= (Γ .- transpose(Γ)) ./ 2

    state.backend.corr = Γ
    state.backend.scratch = zeros(Float64, n_maj, n_maj)

    return state
end
