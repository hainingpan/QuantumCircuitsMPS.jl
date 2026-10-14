# === State-Vector Gate Application Engine (Tier 1 / "vanilla") ===
# Core apply_gate_sv! implementing reshape + permutedims + matrix-multiply
# gate application on a dense state vector, plus the _apply_single! dispatch
# method that wires it into the EXISTING, UNMODIFIED execute!/apply! chain
# (see src/Core/apply.jl) for SimulationState{StateVectorBackend}.

"""
    apply_gate_sv!(ψ, U, target_sites, L, d) -> Vector{ComplexF64}

Apply a d^n × d^n gate matrix U to `target_sites` (physical site numbers,
1-indexed, site 1 = MSB) of a length-d^L state vector ψ. Returns the new
state vector (caller reassigns `state.backend.ψ = result`, does NOT mutate
ψ's contents in-place — matches the existing `state.backend.mps = ...`
reassignment pattern used elsewhere in the codebase).

Algorithm (verified numerically across multiple test cases, including an
asymmetric CNOT gate applied in both site-argument orders):
1. Reshape ψ into an L-dimensional tensor of shape (d,d,...,d). Due to
   Julia's column-major array layout, tensor dimension `k` corresponds to
   PHYSICAL SITE `L - k + 1` (site 1/MSB is the LAST dimension, site L/LSB
   is the FIRST dimension).
2. Convert each target physical site `s` to its Julia array dimension via
   `L - s + 1`, then REVERSE the resulting list (required so the merged
   multi-site index matches `gate_matrix`'s "first site in the gate's
   argument list = slowest/most-significant digit" convention).
3. Permute dimensions so the (reversed) target dims come first, followed by
   all other dims (in ascending order).
4. Reshape the permuted tensor to 2D: (d^n, d^(L-n)) where `n = length(target_sites)`.
5. Left-multiply by U: `new_mat = U * A_mat`.
6. Reshape back to L dims (d,d,...,d), then permutedims with the INVERSE
   of the original permutation.
7. `vec(...)` the result back to a flat Vector{ComplexF64}.

Handles 1-site AND n-site gates (adjacent or non-adjacent) UNIFORMLY — no
special-casing needed for adjacent vs non-adjacent target sites.
"""
function apply_gate_sv!(ψ::Vector{ComplexF64}, U::Matrix{ComplexF64},
        target_sites::Vector{Int}, L::Int, d::Int)
    n = length(target_sites)
    dims = ntuple(_ -> d, L)
    A = reshape(ψ, dims)
    target_dims = reverse([L - s + 1 for s in target_sites])
    other_dims = [k for k in 1:L if !(k in target_dims)]
    perm = vcat(target_dims, other_dims)
    A_perm = permutedims(A, perm)
    A_mat = reshape(A_perm, (d^n, d^(L - n)))
    new_mat = U * A_mat
    new_perm = reshape(new_mat, dims)
    new_A = permutedims(new_perm, invperm(perm))
    return vec(new_A)
end

# === Shared digit-extraction helper for SV observables ===

"""
    _sv_digit(n0, stride, d) -> Int

Extract the base-`d` digit of the 0-indexed basis integer `n0` at the
physical site whose precomputed stride is `stride = d^(L - s)` (site 1 = MSB
convention shared by all state-vector observables). Callers hoist the
loop-invariant `d^(L - s)` power out of their inner loops and pass it in.
"""
@inline _sv_digit(n0::Int, stride::Int, d::Int) = (n0 ÷ stride) % d

# === gate_matrix resolution dispatch ===
# gate_matrix has ONE signature for most gates (no extra args), but HaarRandom
# needs (gate, rng; local_dim) — dispatch via multiple methods, not an if/isa check.

_resolve_gate_matrix_sv(gate::AbstractGate, state::SimulationState) = gate_matrix(gate)
function _resolve_gate_matrix_sv(gate::HaarRandom, state::SimulationState)
    gate_matrix(gate, get_rng(state.rng_registry, :gates_realization); local_dim = state.local_dim)
end
function _resolve_gate_matrix_sv(gate::RandomClifford, state::SimulationState)
    gate_matrix(gate, get_rng(state.rng_registry, :gates_realization); local_dim = state.local_dim)
end
# Projection is d-dependent (per-level projector on spin sites): build the
# d×d matrix from the state's local dimension. At d=2 this equals
# gate_matrix(gate) exactly (same values, same type) — qubit path unchanged.
function _resolve_gate_matrix_sv(gate::Projection, state::SimulationState)
    _projection_matrix(gate.outcome, state.local_dim)
end

# === Closed-form ‖Pψ‖² for the postselection guard (optimized engine) ===
# The optimized engine applies gates in place, so for a projective gate the
# guard has to run BEFORE the kernel touches ψ — which needs ‖Pψ‖² without
# applying P. Gates with a closed form provide it here; the default `nothing`
# makes `_apply_single!` apply the gate to a copy instead.

@doc raw"""
    _sv_projected_norm2(gate, state::SimulationState{StateVectorBackend}, phy_sites) -> Union{Float64, Nothing}

Squared norm ``\lVert P\psi\rVert^2`` of the state after `gate` acts on
`phy_sites`, computed WITHOUT applying the gate, or `nothing` when `gate` has
no closed form (the caller then applies it to a copy of ``\psi``).
`Projection(k)` keeps exactly the amplitudes whose digit at the site is `k`,
so its value is the Born probability `born_probability(state, site, k)`: one
read-only pass over ``\psi``, no allocation. This is the `Measure`/`Reset`
hot path.
"""
_sv_projected_norm2(::AbstractGate, ::SimulationState{StateVectorBackend}, ::Vector{Int}) = nothing
function _sv_projected_norm2(gate::Projection, state::SimulationState{StateVectorBackend},
        phy_sites::Vector{Int})
    return born_probability(state, phy_sites[1], gate.outcome)
end

# === _apply_single! for the state-vector backend ===
# NEW, more-specific method: Julia's multiple dispatch routes
# SimulationState{StateVectorBackend} calls here and SimulationState{MPSBackend}
# calls to the EXISTING (untouched) method in src/Core/apply.jl.

"""
    _apply_single!(state::SimulationState{StateVectorBackend}, gate::AbstractGate, phy_sites::Vector{Int})

Apply gate to specific physical sites on a dense state-vector backend.
Internal workhorse for both engines (see `apply_gate_sv!` and
`apply_gate_sv_optimized!`).

Steps:
1. Validate support matches site count
2. Convert physical sites to RAM indices (identity for SV, kept for
   code-path consistency with the MPS backend)
3. Resolve the gate's dense matrix (HaarRandom needs rng + `local_dim`)
4. Apply via `apply_gate_sv_optimized!` (Tier 2, the default, in place) or
   `apply_gate_sv!` (Tier 1, `state.backend.engine == :builtin`, returns a
   fresh vector), then store the result in state.backend.ψ
5. Normalize iff `needs_normalization(gate)` (trait, Contract 3.5) — there
   is NO truncate! equivalent for state vectors (no bond dimension). Such a
   gate is rejected with an `ArgumentError` that leaves the state unchanged
   when it annihilates the state — postselection onto a zero-probability
   outcome, see `_check_postselection`. The guard gets the Born probability
   ‖Pψ‖²/‖ψ‖² (same contract as the MPS backend); a state vector stays
   normalized, so the ratio only differs from ‖Pψ‖² by rounding here.
   Because the Tier 2 kernel mutates ψ in place, the guard runs BEFORE it
   when ‖Pψ‖² has a closed form (`_sv_projected_norm2`; `Projection`, i.e.
   `Measure`/`Reset`), and the kernel works on a copy of ψ otherwise
   (`SpinSectorProjection`, user-defined projective gates). Tier 1 always
   returns a fresh vector, so it checks after applying.
"""
function _apply_single!(state::SimulationState{StateVectorBackend}, gate::AbstractGate, phy_sites::Vector{Int})
    if support(gate) != length(phy_sites)
        throw(ArgumentError("Gate support $(support(gate)) does not match sites $(length(phy_sites))"))
    end

    ram_sites = [state.phy_ram[ps] for ps in phy_sites]   # identity for SV, but keep the lookup for code-path consistency

    U = _resolve_gate_matrix_sv(gate, state)
    ψ = state.backend.ψ
    checked = false   # postselection guard already run (before an in-place apply)
    if state.backend.engine == :optimized
        if needs_normalization(gate)
            norm2_out = _sv_projected_norm2(gate, state, phy_sites)
            if norm2_out === nothing
                # No closed form: work on a copy so that a rejected
                # (zero-probability) postselection leaves state.backend.ψ untouched.
                ψ = copy(ψ)
            else
                # Guard first, then mutate: a rejected postselection throws
                # here with state.backend.ψ untouched. No copy.
                _check_postselection(norm2_out, norm(ψ)^2, gate, phy_sites)
                checked = true
            end
        end
        apply_gate_sv_optimized!(ψ, U, ram_sites, state.L, state.local_dim)
    else
        ψ = apply_gate_sv!(ψ, U, ram_sites, state.L, state.local_dim)   # returns a fresh vector
    end

    if needs_normalization(gate)
        # Unless the guard ran above, state.backend.ψ is still the input
        # (fresh vector / copy), so its norm is ‖ψ‖². Throws before the store below.
        checked || _check_postselection(norm(ψ)^2, norm(state.backend.ψ)^2, gate, phy_sites)
        normalize!(ψ)
    end
    state.backend.ψ = ψ
    return nothing
end
