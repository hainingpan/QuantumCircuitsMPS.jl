"""
    (m::Magnetization)(state::SimulationState{StateVectorBackend}) -> Float64

State-vector implementation of the `Magnetization` observable.

Computes Mz = (1/L) Σᵢ ⟨Zᵢ⟩ via direct basis-state summation over the dense
state vector `state.backend.ψ`. For each physical site `j` (1-indexed, site 1
is the most-significant digit of the basis index), ⟨Zⱼ⟩ = P(bit_j=0) -
P(bit_j=1) = 2*P(bit_j=0) - 1.

Implementation: a single O(d^L) pass (each amplitude is read exactly once)
replaces the former L independent O(d^L) scans. The probabilities
`a_n = |ψ_n|²` are reduced hierarchically: one sweep builds contiguous
block sums of size d, d², …, d^(L-1), and P(digit_k = 0) for site k is the
sum of the first size-d^(L-k) sub-block of every size-d^(L-k+1) block —
i.e. exactly the same addends in the same ascending basis-index order as the
old per-site scans, only grouped into contiguous partial sums. The grouping
changes floating-point rounding by at most O(L·eps) relative to the old
implementation (verified ≤ 1e-13 old-vs-new on random states; typically
≤ 1e-15), while reducing the work from O(L·d^L) integer divisions to
~d^L/(d-1)·(d+1) additions total.

Only the `:Z` axis is currently supported for the state-vector backend;
`:X`/`:Y` throw an informative `ArgumentError` (they are allowed by the
`Magnetization` struct's own validation since it is shared with the MPS
backend, but no state-vector implementation exists for them yet).
"""
function (m::Magnetization)(state::SimulationState{StateVectorBackend})
    m.axis == :Z ||
        throw(ArgumentError("Magnetization for the state-vector backend currently only supports :Z axis, got $(m.axis)"))
    L = state.L
    d = state.local_dim
    ψ = state.backend.ψ
    N = length(ψ)

    p0 = Vector{Float64}(undef, L)   # p0[site] = P(digit_site = 0)

    # --- Level 1 (site L, the least-significant digit) ---
    # P(digit_L = 0) = Σ_m a[m*d]  (0-indexed: first element of each d-block);
    # simultaneously build the size-d block sums c[m+1] = Σ_r a[m*d + r].
    nblocks = N ÷ d
    c = Vector{Float64}(undef, nblocks)
    sL = 0.0
    @inbounds for m in 0:(nblocks - 1)
        base = m * d
        first_a = abs2(ψ[base + 1])
        sL += first_a
        blk = first_a
        for r in 1:(d - 1)
            blk += abs2(ψ[base + r + 1])
        end
        c[m + 1] = blk
    end
    p0[L] = sL

    # --- Levels 2..L (sites L-1 down to 1) ---
    # At the step for site k, `c[1:len]` holds the size-d^(L-k) block sums.
    # P(digit_k = 0) = Σ_m c[m*d + 1] (first sub-block of each size-d^(L-k+1)
    # block); the merged sums are compacted in place (write index m+1 never
    # overtakes read index m*d+1).
    len = nblocks
    for k in (L - 1):-1:1
        n = len ÷ d
        s = 0.0
        @inbounds for m in 0:(n - 1)
            base = m * d
            first_c = c[base + 1]
            s += first_c
            blk = first_c
            for r in 1:(d - 1)
                blk += c[base + r + 1]
            end
            c[m + 1] = blk
        end
        p0[k] = s
        len = n
    end

    total = 0.0
    for site in 1:L
        total += (2 * p0[site] - 1)   # <Z> = P(0) - P(1) = 2*P(0) - 1
    end
    return total / L
end
