# src/Gaussian/kernel.jl
# Pure numerical kernel for the Gaussian (free-fermion covariance-matrix)
# backend. Line-by-line port of ~/GTN/GTN.py: P_contraction_2 (L1063-1102),
# purify (L1131-1136), correlation_matrix (L29-55, non-op branch), kraus
# (L105-118). No SimulationState dependency — pure functions on matrices.
#
# Conventions (matching the reference Python implementation get_C_f, GTN.py:1518-1523):
# - Γ[a,b] = (i/2)⟨[γ_a, γ_b]⟩ = ⟨i γ_a γ_b⟩ (a ≠ b), with Majoranas
#   γ_{2i−1} = c_i + c_i†, γ_{2i} = −i(c_i† − c_i) (Bravyi's convention), so
#   Γ[2i−1,2i] = ⟨i γ_{2i−1} γ_{2i}⟩ = 1 − 2⟨c_i†c_i⟩.
# - Mode i (1-based) ↔ Majorana indices (2i−1, 2i).
# - 2×2 block [[0,1],[−1,0]] on a mode ⇒ ⟨c†c⟩ = 0 (unoccupied / vacuum).
# - 2×2 block [[0,−1],[1,0]] on a mode ⇒ ⟨c†c⟩ = 1 (occupied).
# - kraus n=(s,0,0) projection onto the parity sector iγ_iγ_j = −s ⇒
#   post-measurement Γ[i,j] = −s; the vacuum pair (Γ[2i−1,2i] = +1) is the
#   s = −1 outcome.

using LinearAlgebra: Hermitian, cond, det, eigen, issuccess, lu

"""
    majorana_indices(site::Int) -> (Int, Int)

Majorana indices `(2site-1, 2site)` for 1-based fermionic mode `site`.
"""
majorana_indices(site::Int) = (2site - 1, 2site)

"""
    site_majoranas(state, site::Int) -> NTuple{N,Int}

Majorana indices carried by physical `site` of a Gaussian-backend
`SimulationState`, RAM-mapped through `state.phy_ram` (identity on the
Gaussian backend, kept for protocol uniformity). THE single source of truth
for the site → Majorana index mapping — every Gaussian gate / measurement /
observable resolves sites through this helper:

- fermionic-mode granularity (`state.backend.majoranas_per_site == 2`,
  default): returns `(2r−1, 2r)` — the pair of one fermionic mode.
- Majorana-chain granularity (`majoranas_per_site == 1`,
  `site_type="Majorana"`): returns `(r,)` — the site IS one Majorana mode.

Duck-typed on `state` (needs only `phy_ram` and
`backend.majoranas_per_site`) so this pure-kernel file keeps no
`SimulationState` dependency.
"""
function site_majoranas(state, site::Int)
    r = state.phy_ram[site]
    return state.backend.majoranas_per_site == 1 ? (r,) : (2r - 1, 2r)
end

@doc raw"""
    _kraus(n::NTuple{3,<:Real}) -> Matrix{Float64}

``4\times4`` Gaussian gate tensor ``\Upsilon`` parameterized by ``n = (n_1,n_2,n_3)`` — port of
`GTN.kraus` (`GTN.py:105-118`) with `c = [1,1,1]`. Unitary 2-Majorana rotation for ``\|n\| = 1``; parity projection for ``n = (\pm1,0,0)``.
"""
function _kraus(n::NTuple{3, <:Real})
    n1, n2, n3 = float.(n)
    return [0.0 n1 n2 n3;
            -n1 0.0 -n3 n2;
            -n2 n3 0.0 -n1;
            -n3 -n2 n1 0.0]
end

@doc raw"""
    parity_projection_upsilon(s::Int) -> Matrix{Float64}

4×4 Υ projecting a Majorana pair `(i,j)` onto the parity sector
``i\gamma_i\gamma_j = -s``, ``s \in \{+1,-1\}``, i.e. `_kraus((s,0,0))`. The post-measurement
state has ``\Gamma[i,j] = \langle i\gamma_i\gamma_j\rangle = -s`` (matching the Python reference's
sign convention for `s`: the vacuum `Γ[2i−1,2i] = +1` is the `s = −1` outcome;
contracting the vacuum pair with `s = +1` is the probability-zero outcome and
throws).
"""
function parity_projection_upsilon(s::Int)
    s in (-1, 1) || throw(ArgumentError("parity outcome s must be +1 or -1, got $s"))
    return _kraus((s, 0, 0))
end

@doc raw"""
    vacuum_covariance(L::Int) -> Matrix{Float64}

`2L×2L` Majorana covariance matrix ``\Gamma_0 = \bigoplus_i \begin{pmatrix}0&1\\-1&0\end{pmatrix}`` of the all-modes-
unoccupied vacuum (port of `correlation_matrix`, `GTN.py:29-55`, non-op
branch). Matches the Python reference `get_C_f`: every mode has ``\langle c^\dagger c\rangle = 0``.
"""
function vacuum_covariance(L::Int)
    Γ = zeros(Float64, 2L, 2L)
    for i in 1:L
        a, b = majorana_indices(i)
        Γ[a, b] = 1.0
        Γ[b, a] = -1.0
    end
    return Γ
end

@doc raw"""
    occupation_covariance(bits::AbstractVector{Bool}) -> Matrix{Float64}

Product-state covariance matrix for occupations `bits`: mode `i` gets block
[[0,1],[−1,0]] when `bits[i] == false` (``\langle c^\dagger c\rangle = 0``) and the sign-flipped block ``\begin{pmatrix}0&-1\\1&0\end{pmatrix}`` when `bits[i] == true` (``\langle c^\dagger c\rangle = 1``). Sign ↔ occupation mapping
matches the Python reference `get_C_f` (`GTN.py:1518-1523`).
"""
function occupation_covariance(bits::AbstractVector{Bool})
    L = length(bits)
    Γ = zeros(Float64, 2L, 2L)
    for i in 1:L
        a, b = majorana_indices(i)
        sign = bits[i] ? -1.0 : 1.0
        Γ[a, b] = sign
        Γ[b, a] = -sign
    end
    return Γ
end

@doc raw"""
    antisymmetrize!(Γ::AbstractMatrix{Float64}) -> Γ

In-place ``\Gamma \leftarrow (\Gamma - \Gamma^T)/2``: every off-diagonal pair becomes
``(\Gamma_{ij} - \Gamma_{ji})/2`` and ``(\Gamma_{ji} - \Gamma_{ij})/2``, the diagonal becomes
zero. Bit-for-bit the same result as the broadcast
`Γ .= (Γ .- transpose(Γ)) ./ 2`, without the temporary copy of
`transpose(Γ)` that broadcast allocates to avoid aliasing. Both halves of a
pair are computed from their own subtraction rather than as `v` and `-v`:
the two agree for every nonzero value, but a pair of exact zeros gives
`+0.0`/`+0.0` under subtraction and `+0.0`/`-0.0` under negation, and the
sign of a zero changes LAPACK's Householder sign choices downstream
(`eigvals` of ``i\Gamma_A`` moved by 1e-14 before this was pinned). Returns `Γ`.
"""
function antisymmetrize!(Γ::AbstractMatrix{Float64})
    N = size(Γ, 1)
    size(Γ, 2) == N || throw(DimensionMismatch("Γ must be square, got $(size(Γ))"))
    @inbounds for j in 1:N
        Γ[j, j] = 0.0
        for i in (j + 1):N
            a = Γ[i, j]
            b = Γ[j, i]
            Γ[i, j] = (a - b) / 2
            Γ[j, i] = (b - a) / 2
        end
    end
    return Γ
end

@doc raw"""
    antisymmetrize!(Γ::AbstractMatrix{Float64}, rows) -> Γ

[`antisymmetrize!`](@ref) restricted to the pairs ``(i, j)`` with ``i`` or ``j``
in `rows`. For a `Γ` that was exactly antisymmetric before an update touching
only those rows and columns (a Majorana rotation ``\Gamma \leftarrow R\Gamma R^T`` with
``R = O \oplus I``), this is bit-for-bit the full pass: on the untouched block
the full pass computes ``(a - (-a))/2 = a``, an identity, so skipping it
changes nothing. ``O(N\,\lvert\mathrm{rows}\rvert)`` instead of ``O(N^2)``.
"""
function antisymmetrize!(Γ::AbstractMatrix{Float64}, rows)
    N = size(Γ, 1)
    size(Γ, 2) == N || throw(DimensionMismatch("Γ must be square, got $(size(Γ))"))
    @inbounds for i in rows
        Γ[i, i] = 0.0
        for j in 1:N
            j == i && continue
            a = Γ[i, j]
            b = Γ[j, i]
            Γ[i, j] = (a - b) / 2
            Γ[j, i] = (b - a) / 2
        end
    end
    return Γ
end

@doc raw"""
    _purity_drift(Γ::AbstractMatrix{Float64}) -> Float64

Purity diagnostic ``\max_i\lvert(\Gamma^2)_{ii} + 1\rvert`` (zero for a pure state,
``\Gamma^2 = -I``) of an antisymmetric covariance matrix, computed from the
diagonal only: ``(\Gamma^2)_{ii} = \sum_j \Gamma_{ij}\Gamma_{ji} = -\sum_j \Gamma_{ji}^2``, i.e.
``\max_i\lvert 1 - \lVert\Gamma_{:,i}\rVert^2\rvert`` — ``O(N^2)``, allocation-free, and a
contiguous (vectorizable) column sweep, instead of forming the full ``O(N^3)``
product ``\Gamma\Gamma``. Same quantity as `maximum(abs.(diag(Γ * Γ) .+ 1))` up to
summation order and up to any roundoff-level asymmetry of `Γ` (which enters
only at first order, far below any sensible `purify_tol`).
"""
function _purity_drift(Γ::AbstractMatrix{Float64})
    N = size(Γ, 1)
    worst = 0.0
    @inbounds for i in 1:N
        acc = 0.0
        @simd for j in 1:N
            acc += Γ[j, i] * Γ[j, i]
        end
        worst = max(worst, abs(1 - acc))
    end
    return worst
end

@doc raw"""
    purify!(Γ::Matrix{Float64}) -> Matrix{Float64}

Project a (numerically drifted) covariance matrix back onto the manifold of
pure Gaussian states (``\Gamma^2 = -I``) — port of `purify` (`GTN.py:1131-1136`, see
App. B2 of PhysRevB.106.134206). Eigendecomposes the Hermitian matrix Γ/i,
clamps eigenvalues to ±1, reconstructs ``-\mathrm{Im}(V\,\mathrm{diag}(\mathrm{vals})\,V^\dagger)``, then
antisymmetrizes. In-place; returns `Γ`.
"""
function purify!(Γ::Matrix{Float64})
    vals, vecs = eigen(Hermitian(Γ ./ im))
    clamped = [v < 0 ? -1.0 : (v > 0 ? 1.0 : 0.0) for v in vals]
    Γ .= .-imag.(vecs * Diagonal(clamped) * vecs')
    antisymmetrize!(Γ)
    return Γ
end

@doc raw"""
    gaussian_contraction!(Γ, Υ, ix; scratch=nothing, purify_tol=1e-10) -> Γ

Contract the Gaussian gate tensor `Υ` (2m×2m for m = length(ix) Majorana
legs) into the covariance matrix `Γ` at Majorana indices `ix` (1-based),
in place — line-by-line port of `P_contraction_2` (`GTN.py:1063-1102`):

```math
C = (\Gamma_{RR}\Upsilon_{LL}+I)^{-1}\\
\Gamma[\bar{ix},\bar{ix}] \mathrel{+}= \Gamma_{LR}(\Upsilon_{LL}C)\Gamma_{LR}^T\\
\Gamma[ix,\bar{ix}] = \Upsilon_{RL}C\Gamma_{LR}^T\\
\Gamma[ix,ix] = \Upsilon_{RR}+\Upsilon_{RL}(\Gamma_{RR}C^T)\Upsilon_{RL}^T\\
\Gamma[\bar{ix},ix] = -\Gamma[ix,\bar{ix}]^T
```

Throws `ArgumentError` when ``\Gamma_{RR}\Upsilon_{LL}+I`` is singular (a probability-zero
measurement outcome) — no least-squares fallback. If the result drifts off
the pure-state manifold beyond `purify_tol` (``\max\lvert\mathrm{diag}(\Gamma^2)+1\rvert``,
see [`_purity_drift`](@ref)), calls [`purify!`](@ref) and re-antisymmetrizes.
`scratch` (same size as Γ) is an optional preallocated buffer for the
ix̄-block update.
"""
function gaussian_contraction!(Γ::Matrix{Float64}, Υ::AbstractMatrix,
        ix::Vector{Int};
        scratch::Union{Matrix{Float64}, Nothing} = nothing,
        purify_tol::Float64 = 1e-10)
    N = size(Γ, 1)
    m = length(ix)
    size(Υ) == (2m, 2m) ||
        throw(ArgumentError("Upsilon must be $(2m)x$(2m) for length(ix)=$m, got $(size(Υ))"))
    ix_bar = [k for k in 1:N if !(k in ix)]

    Γ_RR = Γ[ix, ix]
    Γ_LR = Γ[ix_bar, ix]
    Υ_LL = @view Υ[1:m, 1:m]
    Υ_RR = @view Υ[(m + 1):(2m), (m + 1):(2m)]
    Υ_RL = @view Υ[(m + 1):(2m), 1:m]

    M = Γ_RR * Υ_LL + I
    F = lu(M; check = false)
    if !issuccess(F) || cond(M, 1) > 1e12
        throw(ArgumentError("contraction would produce a vanishing state (probability-zero outcome)"))
    end
    C = inv(F)

    A = Υ_LL * C
    D = Γ_RR * transpose(C)

    if scratch === nothing
        _add_block!(Γ, ix_bar, Γ_LR * A * transpose(Γ_LR))
    else
        buf = @view scratch[1:(N - m), 1:(N - m)]
        mul!(@view(scratch[1:(N - m), (N - m + 1):N]), Γ_LR, A)
        mul!(buf, @view(scratch[1:(N - m), (N - m + 1):N]), transpose(Γ_LR))
        _add_block!(Γ, ix_bar, buf)
    end
    Γ[ix, ix_bar] = Υ_RL * C * transpose(Γ_LR)
    Γ[ix, ix] = Υ_RR + Υ_RL * D * transpose(Υ_RL)
    Γ[ix_bar, ix] = -transpose(Γ[ix, ix_bar])

    if _purity_drift(Γ) > purify_tol
        purify!(Γ)   # ends with antisymmetrize!
    end
    return Γ
end

# Γ[ix_bar, ix_bar] .+= P without the (N-m)² temporary that broadcast
# allocates for the right-hand-side `getindex`.
function _add_block!(Γ::Matrix{Float64}, ix_bar::Vector{Int}, P::AbstractMatrix{Float64})
    @inbounds for (jj, j) in enumerate(ix_bar), (ii, i) in enumerate(ix_bar)

        Γ[i, j] += P[ii, jj]
    end
    return Γ
end

@doc raw"""
    conjugate_rows_cols!(Γ, O, ix, scratch) -> Γ

In-place ``\Gamma \leftarrow R\,\Gamma\,R^T`` with ``R = O \oplus I`` acting on the Majorana
indices `ix` (`O` is `m×m`, `m = length(ix)`): `Γ[ix, :] = O * Γ[ix, :]`
followed by `Γ[:, ix] = Γ[:, ix] * O'`, which is the direct (exact) action of
a Gaussian unitary on the covariance matrix. The row and column blocks are
staged in `scratch` (the ``N\times N`` `state.backend.scratch`) so that no
temporaries are allocated; the two products are the same BLAS `gemm` calls
as the slice form and give the same floating-point result. When the buffer
cannot hold the ``2m \times N`` / ``N \times 2m`` staging blocks (``N < 2m``: fewer
than four fermionic modes, or fewer than four Majoranas on a Majorana chain),
the allocating slice form is used instead. Only rows and columns `ix` are modified; the result is not
re-antisymmetrized here (see [`antisymmetrize!`](@ref)`(Γ, ix)`).
"""
function conjugate_rows_cols!(Γ::Matrix{Float64}, O::AbstractMatrix{Float64},
        ix::AbstractVector{Int}, scratch::Matrix{Float64})
    N = size(Γ, 1)
    m = length(ix)
    size(O) == (m, m) || throw(DimensionMismatch("O must be $(m)×$(m), got $(size(O))"))
    if size(scratch, 1) < max(N, 2m) || size(scratch, 2) < max(N, 2m)
        Γ[ix, :] .= O * Γ[ix, :]
        Γ[:, ix] .= Γ[:, ix] * O'
        return Γ
    end
    # Rows: B = Γ[ix, :] (m×N), C = O*B, written back into rows ix.
    B = @view scratch[1:m, 1:N]
    C = @view scratch[(m + 1):(2m), 1:N]
    @inbounds for j in 1:N, (k, i) in enumerate(ix)

        B[k, j] = Γ[i, j]
    end
    mul!(C, O, B)
    @inbounds for j in 1:N, (k, i) in enumerate(ix)

        Γ[i, j] = C[k, j]
    end
    # Columns: B = Γ[:, ix] (N×m), C = B*Oᵀ, written back into columns ix.
    Bc = @view scratch[1:N, 1:m]
    Cc = @view scratch[1:N, (m + 1):(2m)]
    @inbounds for (k, j) in enumerate(ix), i in 1:N

        Bc[i, k] = Γ[i, j]
    end
    mul!(Cc, Bc, O')
    @inbounds for (k, j) in enumerate(ix), i in 1:N

        Γ[i, j] = Cc[i, k]
    end
    return Γ
end

@doc raw"""
    parity_projection!(Γ, a, b, s; purify_tol=1e-10) -> Γ

Collapse the covariance matrix `Γ` onto the parity sector ``i\gamma_a\gamma_b = -s``
(``s \in \{+1,-1\}``) of the Majorana pair `(a, b)`, in place. This is
[`gaussian_contraction!`](@ref) with `Υ = parity_projection_upsilon(s)`
evaluated in closed form: for that projector ``\Upsilon_{RL} = 0`` and
``\Gamma_{RR}\Upsilon_{LL} + I = (1 - s\,g)\,I`` with ``g = \Gamma_{ab}``, so the general
Schur-complement update collapses to a rank-2 update of the complement block,

```math
\Gamma_{ij} \leftarrow \Gamma_{ij} + \frac{s}{1 - s\,g}\left(\Gamma_{ia}\Gamma_{jb} - \Gamma_{ib}\Gamma_{ja}\right)
\qquad (i, j \notin \{a, b\}),
```

after which rows and columns `a`, `b` are zeroed except ``\Gamma_{ab} = -s``,
``\Gamma_{ba} = s``. The denominator ``1 - s\,g = 2\,P(\text{outcome})`` is twice the
Born probability of the selected sector. ``O(N^2)`` and allocation-free: no
index-set complement, no slices, no `lu`/`inv`/`cond` on 2×2 blocks, and no
BLAS calls — one contiguous sweep over the complement block plus the purity
check. The closed form reads only ``g = \Gamma_{ab}`` and assumes the
antisymmetric structure ``\Gamma_{ba} = -g``, ``\Gamma_{aa} = \Gamma_{bb} = 0`` (a
roundoff-level asymmetry perturbs the result at roundoff level); every
operation in this backend leaves `Γ` exactly antisymmetric, and so does this
one: the ``(i,j)`` and ``(j,i)`` updates use the same two products in opposite
order, which round identically.

Throws `ArgumentError` for ``1 - s\,g \le 0`` (a probability-zero outcome —
the "vanishing state" of the general kernel); like
[`gaussian_contraction!`](@ref), calls [`purify!`](@ref) when the purity
drift ([`_purity_drift`](@ref)) exceeds `purify_tol`. Agrees with the general
kernel to roundoff (``\sim 10^{-15}``, not bitwise: different floating-point
operation order).
"""
function parity_projection!(Γ::Matrix{Float64}, a::Int, b::Int, s::Int;
        purify_tol::Float64 = 1e-10)
    s in (-1, 1) || throw(ArgumentError("parity outcome s must be +1 or -1, got $s"))
    N = size(Γ, 1)
    (1 <= a <= N && 1 <= b <= N && a != b) || throw(ArgumentError(
        "parity_projection! needs two distinct Majorana indices in 1:$N, got ($a, $b)"))
    g = Γ[a, b]
    denom = 1 - s * g                     # = 2·P(outcome)
    denom > 0 || throw(ArgumentError(
        "parity projection would produce a vanishing state (probability-zero outcome)"))
    c = s / denom

    # Complement block, column by column (column-major, contiguous in i).
    # Rows a, b of the complement columns receive garbage here and are
    # overwritten below; columns a, b are never written inside the loop, so
    # every read Γ[·, a], Γ[·, b] sees the pre-measurement values.
    @inbounds for j in 1:N
        (j == a || j == b) && continue
        gja = Γ[j, a]
        gjb = Γ[j, b]
        for i in 1:N
            Γ[i, j] += c * (Γ[i, a] * gjb - Γ[i, b] * gja)
        end
    end
    @inbounds for k in 1:N
        Γ[k, a] = 0.0
        Γ[k, b] = 0.0
        Γ[a, k] = 0.0
        Γ[b, k] = 0.0
    end
    Γ[a, b] = -s
    Γ[b, a] = s

    if _purity_drift(Γ) > purify_tol
        purify!(Γ)   # ends with antisymmetrize!
    end
    return Γ
end

@doc raw"""
    haar_orthogonal(rng::AbstractRNG, n::Int) -> Matrix{Float64}

Exact Haar-random special-orthogonal matrix ``Q \in SO(n)``: QR-decompose a
Ginibre matrix, fix the R-diagonal sign ambiguity (``Q \leftarrow Q\,\mathrm{diag}(\mathrm{sign}(\mathrm{diag}(R)))``,
required for Haar on O(n)), then flip the first column if `det(Q) < 0` to
land in SO(n).
"""
function haar_orthogonal(rng::AbstractRNG, n::Int)
    A = randn(rng, n, n)
    F = qr(A)
    Q = Matrix(F.Q)
    Q .= Q * Diagonal(sign.(diag(F.R)))
    if det(Q) < 0
        Q[:, 1] .= .-Q[:, 1]
    end
    return Q
end
