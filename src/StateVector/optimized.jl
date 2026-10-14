# === State-Vector Gate Application Engine (Tier 2 / "optimized") ===
#
# Hand-written stride-loop kernels (Yao.jl `u1apply!`-inspired, no external
# dependency), generalized to arbitrary `local_dim`. This is the default
# engine; `SimulationState(...; backend=:statevector, engine=:builtin)` selects
# the Tier 1 reference instead — see `StateVectorBackend.engine`
# (src/Backend/Backend.jl) and the dispatch in `_apply_single!`
# (src/StateVector/StateVector.jl).
#
# Tier 1's `apply_gate_sv!` (src/StateVector/StateVector.jl) is the GROUND
# TRUTH. Every kernel here reproduces Tier 1's output to rounding (the
# amplitudes are summed in a different order, so the two engines agree to
# ~1e-15, not bitwise); test/statevector/engine_agreement.jl pins this on
# random gates, sites and local dimensions.

"""
    _sv_matvec!(out, U, buf, m) -> out

`out = U * buf` for the `m`-dimensional gate block (`m = d^n`), as explicit
loops. `mul!` would dispatch to a BLAS `gemv` for every block, and the
per-call overhead of that dominates a 2×2 or 4×4 product; the stride kernels
call this once per block, `d^(L-n)` times per gate.
"""
@inline function _sv_matvec!(out::Vector{ComplexF64}, U::Matrix{ComplexF64},
        buf::Vector{ComplexF64}, m::Int)
    @inbounds for i in 1:m
        acc = zero(ComplexF64)
        for j in 1:m
            acc += U[i, j] * buf[j]
        end
        out[i] = acc
    end
    return out
end

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
            _sv_matvec!(newvals, U, buf, d)
            for k in 0:(d - 1)
                ψ[j + i + k * step + 1] = newvals[k + 1]
            end
        end
        j += step_d
    end
    return ψ
end

"""
    apply_gate_sv_optimized_2site!(ψ, U, s1, s2, L, d) -> ψ

In-place 2-site gate application (adjacent or not) by the same digit-stride
pattern as the 1-site kernel. The `d²` amplitudes mixed by `U` at a base index
`n0` (both target digits zero) sit at `n0 + i*st1 + j*st2`, where
`st = d^(L - s)` is the stride of each target site; the merged gate index is
`i*d + j` with `i` the digit of `s1`, the FIRST site in the gate's argument
list — the "first site = most-significant digit" convention of `gate_matrix`
and Tier 1's `apply_gate_sv!`. The three nested loops enumerate exactly the
base indices, so there is no per-amplitude digit test and no copy of `ψ`.
"""
function apply_gate_sv_optimized_2site!(ψ::Vector{ComplexF64}, U::Matrix{ComplexF64},
        s1::Int, s2::Int, L::Int, d::Int)
    st1 = d^(L - s1)
    st2 = d^(L - s2)
    hi, lo = max(st1, st2), min(st1, st2)   # hi ≥ lo*d: distinct powers of d
    n = length(ψ)
    m = d * d
    buf = Vector{ComplexF64}(undef, m)
    out = Vector{ComplexF64}(undef, m)
    @inbounds for a in 0:(n ÷ (hi * d) - 1), b in 0:(hi ÷ (lo * d) - 1), c in 0:(lo - 1)
        n0 = a * hi * d + b * lo * d + c
        for i in 0:(d - 1), j in 0:(d - 1)

            buf[i * d + j + 1] = ψ[n0 + i * st1 + j * st2 + 1]
        end
        _sv_matvec!(out, U, buf, m)
        for i in 0:(d - 1), j in 0:(d - 1)

            ψ[n0 + i * st1 + j * st2 + 1] = out[i * d + j + 1]
        end
    end
    return ψ
end

"""
    apply_gate_sv_optimized_nsite!(ψ, U, target_sites, L, d) -> ψ

n-site (n >= 3) fallback for the optimized engine: adjacent AND non-adjacent
target sites, using the SAME reshape + permutedims + matmul algorithm as
Tier 1's `apply_gate_sv!` (guaranteeing bitwise-identical results by
construction), but mutating `ψ` IN PLACE via `ψ .= vec(new_A)` rather than
allocating and returning a fresh vector. No built-in gate has support ≥ 3
(only a user `MatrixGate` can), so this path is off the hot loop; the 1- and
2-site stride kernels above cover every gate the circuits ship with.
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

Tier 2 entry point: dispatches to the zero-allocation stride-loop kernels for
1-site and 2-site gates, or the reshape/permutedims fallback for n-site
(n>=3) gates. Mutates `ψ` in place and returns it (caller reassigns
`state.backend.ψ = apply_gate_sv_optimized!(...)`, matching Tier 1's
reassignment call-site pattern even though Tier 2 itself mutates in place).
"""
function apply_gate_sv_optimized!(ψ::Vector{ComplexF64}, U::Matrix{ComplexF64},
        target_sites::Vector{Int}, L::Int, d::Int)
    n = length(target_sites)
    if n == 1
        apply_gate_sv_optimized_1site!(ψ, U, target_sites[1], L, d)
    elseif n == 2
        apply_gate_sv_optimized_2site!(ψ, U, target_sites[1], target_sites[2], L, d)
    else
        apply_gate_sv_optimized_nsite!(ψ, U, target_sites, L, d)
    end
    return ψ
end
