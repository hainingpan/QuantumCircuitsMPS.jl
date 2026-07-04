# === State-Vector Gate Application Engine (Tier 1 / "vanilla") ===
# Core apply_gate_sv! implementing reshape + permutedims + matrix-multiply
# gate application on a dense state vector, plus the _apply_single! dispatch
# method that wires it into the EXISTING, UNMODIFIED execute!/apply! chain
# (see src/Core/apply.jl) for SimulationState{StateVectorBackend}.

using LinearAlgebra

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
   multi-site index matches gate_matrix's "first site in the gate's
   argument list = slowest/most-significant digit" convention).
3. Permute dimensions so the (reversed) target dims come first, followed by
   all other dims (in ascending order).
4. Reshape the permuted tensor to 2D: (d^n, d^(L-n)) where n = length(target_sites).
5. Left-multiply by U: new_mat = U * A_mat.
6. Reshape back to L dims (d,d,...,d), then permutedims with the INVERSE
   of the original permutation.
7. `vec(...)` the result back to a flat Vector{ComplexF64}.

Handles 1-site AND n-site gates (adjacent or non-adjacent) UNIFORMLY — no
special-casing needed for adjacent vs non-adjacent target sites.
"""
function apply_gate_sv!(ψ::Vector{ComplexF64}, U::Matrix{ComplexF64}, target_sites::Vector{Int}, L::Int, d::Int)
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

# === gate_matrix resolution dispatch ===
# gate_matrix has ONE signature for most gates (no extra args), but HaarRandom
# needs (gate, rng; local_dim) — dispatch via multiple methods, not an if/isa check.

_resolve_gate_matrix_sv(gate::AbstractGate, state::SimulationState) = gate_matrix(gate)
_resolve_gate_matrix_sv(gate::HaarRandom, state::SimulationState) = gate_matrix(gate, get_rng(state.rng_registry, :gates_realization); local_dim=state.local_dim)

# === _apply_single! for the state-vector backend ===
# NEW, more-specific method: Julia's multiple dispatch routes
# SimulationState{StateVectorBackend} calls here and SimulationState{MPSBackend}
# calls to the EXISTING (untouched) method in src/Core/apply.jl.

"""
    _apply_single!(state::SimulationState{StateVectorBackend}, gate::AbstractGate, phy_sites::Vector{Int})

Apply gate to specific physical sites on a dense state-vector backend.
Internal workhorse (Tier 1 / vanilla engine — see apply_gate_sv!).

Steps:
1. Validate support matches site count
2. Convert physical sites to RAM indices (identity for SV, kept for
   code-path consistency with the MPS backend)
3. Resolve the gate's dense matrix (HaarRandom needs rng + local_dim)
4. Apply via apply_gate_sv!, reassigning state.backend.ψ
5. Normalize iff `needs_normalization(gate)` (trait, Contract 3.5) — there
   is NO truncate! equivalent for state vectors (no bond dimension)
"""
function _apply_single!(state::SimulationState{StateVectorBackend}, gate::AbstractGate, phy_sites::Vector{Int})
    if support(gate) != length(phy_sites)
        throw(ArgumentError("Gate support $(support(gate)) does not match sites $(length(phy_sites))"))
    end

    ram_sites = [state.phy_ram[ps] for ps in phy_sites]   # identity for SV, but keep the lookup for code-path consistency

    U = _resolve_gate_matrix_sv(gate, state)
    state.backend.ψ = apply_gate_sv!(state.backend.ψ, U, ram_sites, state.L, state.local_dim)

    if needs_normalization(gate)
        normalize!(state.backend.ψ)
    end
    return nothing
end
