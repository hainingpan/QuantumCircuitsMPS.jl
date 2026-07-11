# === State-Vector Gate Application Engine (Tier 2 / "optimized") ===
#
# Hand-written stride-loop kernel (Yao.jl `u1apply!`-inspired, no external
# dependency), generalized to arbitrary `local_dim`. Selected via
# `SimulationState(...; backend=:statevector, engine=:optimized)` — see
# `StateVectorBackend.engine` (src/Backend/Backend.jl) and the dispatch in
# `_apply_single!` (src/StateVector/StateVector.jl).
#
# Tier 1's `apply_gate_sv!` (src/StateVector/StateVector.jl) is the GROUND
# TRUTH. Every function here has been numerically verified to reproduce
# Tier 1's output bitwise/to <1e-13 across many (gate, site) combinations
# and multiple L / local_dim values — see
# `.sisyphus/notepads/statevector-backend/learnings.md` (Task 14) and
# `.sisyphus/evidence/task-14-*.txt` for the verification record.

"""
    apply_gate_sv_optimized_1site!(ψ, U, site, L, d) -> ψ

In-place, zero-inner-loop-allocation 1-site gate application via the
bit/digit-stride pattern (Yao.jl's `u1apply!`, generalized from d=2 to
arbitrary local dimension `d`).

`step = d^(L - site)` is the stride between the `d` amplitudes that get
mixed together by `U` at each combined "outer" index — this matches Tier 1's
convention that physical site `s` corresponds to Julia tensor dimension
`L - s + 1` (site 1 = MSB = slowest-varying digit).

Mutates `ψ` in place and also returns it (for chaining / consistency with
the rest of the Tier 2 API).
"""
function apply_gate_sv_optimized_1site!(
        ψ::Vector{ComplexF64}, U::Matrix{ComplexF64}, site::Int, L::Int, d::Int)
    step = d^(L - site)
    step_d = step * d
    n = length(ψ)
    buf = Vector{ComplexF64}(undef, d)
    newvals = Vector{ComplexF64}(undef, d)
    j = 0
    while j < n
        @inbounds for i in 0:(step - 1)
            for k in 0:(d - 1)
                buf[k + 1] = ψ[j + i + k * step + 1]
            end
            mul!(newvals, U, buf)
            for k in 0:(d - 1)
                ψ[j + i + k * step + 1] = newvals[k + 1]
            end
        end
        j += step_d
    end
    return ψ
end

"""
    apply_gate_sv_optimized_nsite!(ψ, U, target_sites, L, d) -> ψ

n-site (n >= 2) fallback for the optimized engine: adjacent AND non-adjacent
target sites, using the SAME reshape + permutedims + matmul algorithm as
Tier 1's `apply_gate_sv!` (guaranteeing bitwise-identical results by
construction), but mutating `ψ` IN PLACE via `ψ .= vec(new_A)` rather than
allocating and returning a fresh vector. A hand-written stride-loop
generalization to arbitrary n-site arity did not prove measurably beneficial
over this approach (per plan Task 14 guidance: "the 1-site stride-loop
alone... can deliver the bulk of the speedup" for the dominant gate types —
Pauli, Hadamard, Rz, single-qubit Haar — so a hand-optimized kernel for
every n-site arity is not required).
"""
function apply_gate_sv_optimized_nsite!(ψ::Vector{ComplexF64}, U::Matrix{ComplexF64},
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
    ψ .= vec(new_A)
    return ψ
end

"""
    apply_gate_sv_optimized!(ψ, U, target_sites, L, d) -> ψ

Tier 2 entry point: dispatches to the zero-allocation stride-loop kernel for
1-site gates, or the reshape/permutedims fallback for n-site (n>=2) gates.
Mutates `ψ` in place and returns it (caller reassigns
`state.backend.ψ = apply_gate_sv_optimized!(...)`, matching Tier 1's
reassignment call-site pattern even though Tier 2 itself mutates in place).
"""
function apply_gate_sv_optimized!(ψ::Vector{ComplexF64}, U::Matrix{ComplexF64},
        target_sites::Vector{Int}, L::Int, d::Int)
    if length(target_sites) == 1
        apply_gate_sv_optimized_1site!(ψ, U, target_sites[1], L, d)
    else
        apply_gate_sv_optimized_nsite!(ψ, U, target_sites, L, d)
    end
    return ψ
end
