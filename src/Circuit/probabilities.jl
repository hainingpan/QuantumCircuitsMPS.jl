# === Shared probability-schedule resolver ===
#
# `resolve_probability_schedule` turns each outcome's `probability` field
# into a dense `N_outcomes × K` `Matrix{Float64}`; every per-element caller (lazy builder, eager `apply_with_prob!`, engine/expansion) routes through it.

"""
    resolve_probability_schedule(outcomes, K::Int) -> Matrix{Float64}

Resolve every outcome's `probability` field into a dense `N_outcomes × K` `Matrix{Float64}` (row i = outcome i, column k = element k). `probability` may also be an `AbstractVector{<:Real}` with one entry per geometry element (in `elements(geo, L, bc)` order), so each gate location gets its own probability; a scalar broadcasts across all K elements; mixed outcomes and K=1 vectors are fine.

Validates, in order: nonempty outcomes; vector length == K; type/shape
(`Real` or `AbstractVector{<:Real}`); finiteness and `[0,1]` range; and
per-column totals `<= 1 + 1e-10` — the staircase/Pointer unit-sum guard stays with callers.
"""
function resolve_probability_schedule(
        outcomes::AbstractVector{<:NamedTuple{(:probability, :gate, :geometry)}},
        K::Int
)::Matrix{Float64}
    # (1) Nonempty outcomes.
    if isempty(outcomes)
        throw(ArgumentError(
            "resolve_probability_schedule: outcomes cannot be empty"))
    end

    N = length(outcomes)

    # (2) Common K: every AbstractVector-valued outcome's length must equal K.
    for (i, o) in enumerate(outcomes)
        p = o.probability
        if p isa AbstractVector
            len = length(p)
            if len != K
                throw(ArgumentError(
                    "resolve_probability_schedule: outcome $i probability " *
                    "vector has length $len, expected K=$K"))
            end
        end
    end

    # (3) Type/shape: probability must be a Real or AbstractVector{<:Real}.
    for (i, o) in enumerate(outcomes)
        p = o.probability
        if p isa Real
            continue
        elseif p isa AbstractVector
            eltype(p) <: Real && continue
            throw(ArgumentError(
                "resolve_probability_schedule: outcome $i probability " *
                "vector has element type $(eltype(p)), expected <:Real"))
        else
            throw(ArgumentError(
                "resolve_probability_schedule: outcome $i probability has " *
                "type $(typeof(p)), expected Real or AbstractVector{<:Real}"))
        end
    end

    # Materialize the dense matrix: scalars broadcast, vectors are copied.
    M = Matrix{Float64}(undef, N, K)
    for (i, o) in enumerate(outcomes)
        p = o.probability
        if p isa Real
            @views M[i, :] .= Float64(p)
        else
            @views M[i, :] .= p
        end
    end

    # (4) Element finiteness and [0,1] range (NaN checked explicitly).
    for i in 1:N, k in 1:K

        v = M[i, k]
        if !isfinite(v)
            throw(ArgumentError(
                "resolve_probability_schedule: outcome $i element $k " *
                "probability is not finite (got $v)"))
        end
        if v < 0.0 || v > 1.0
            throw(ArgumentError(
                "resolve_probability_schedule: outcome $i element $k " *
                "probability $v is outside [0,1]"))
        end
    end

    # (5) Per-column totals: sum(column) <= 1 + 1e-10 (walker guard stays with callers).
    for k in 1:K
        s = sum(view(M, :, k))
        if s > 1.0 + 1e-10
            throw(ArgumentError(
                "resolve_probability_schedule: column $k probabilities " *
                "sum to $s, must be <= 1 (+1e-10 tolerance)"))
        end
    end

    return M
end
