# === Tripartite Mutual Information Observable ===
#
# I₃(A:B:C) = I(A:B) + I(A:C) − I(A:BC) — the standard Gullans–Huse MIPT
# convention, composed from three MutualInformation evaluations, so it
# inherits MutualInformation's per-backend dispatch (MPS, state vector,
# Clifford) and its region constraints/size guards.

"""
    TripartiteMutualInformation(A, B, C; renyi_index=1, threshold=1e-16, base=ℯ)

Tripartite mutual information I₃ = I(A:B) + I(A:C) − I(A:BC) between three
site regions (Gullans–Huse MIPT convention).

Each region must be a CONTIGUOUS, non-empty range of physical sites, the
three regions must be pairwise DISJOINT, and `B ∪ C` must itself be
contiguous (i.e. B and C adjacent) — inherited from `MutualInformation`'s
contiguous-region constraint on the I(A:BC) term. Note that A and C need NOT
be adjacent: I(A:C) uses `MutualInformation`'s two disjoint blocks.

# Sign convention (MIPT usage)
The standard diagnostic partitions the chain into four QUARTERS A, B, C, D
and computes I₃(A:B:C) with D traced out — NOT equal thirds of the whole
system: for ANY pure state, a full tripartition (A∪B∪C = everything) gives
I₃ ≡ 0 identically, so it carries no information (useful only as a
consistency check). With a fourth region traced out, scrambled volume-law
states give I₃ ≤ 0 (the MIPT scrambling diagnostic), while e.g. GHZ-type
global correlations give I₃ > 0: GHZ(L=8) with A=1:2, B=3:4, C=5:6
(D=7:8 traced) gives I₃ = +log 2.

# Arguments
- `A`, `B`, `C`: the three site regions (contiguous, pairwise disjoint,
  B and C adjacent)
- `renyi_index::Int=1`, `threshold::Float64=1e-16`, `base::Real=ℯ`:
  forwarded to all three `MutualInformation` terms (see its docstring;
  Rényi-n I₃ for n≥2 is a diagnostic, not a proper mutual information)

# Backend cost
Inherits `MutualInformation`: on the MPS backend the largest term I(A:BC)
requires d^(|A|+|B|+|C|) ≤ 256 (e.g. ≤ 8 qubits combined); state vector is
exact dense (L ≲ 20); Clifford is poly-time.

# Examples
```julia
tmi = TripartiteMutualInformation(1:2, 3:4, 5:6)   # quarters of L=8
value = tmi(state)
track!(state, :I3 => TripartiteMutualInformation(1:2, 3:4, 5:6; base=2))
```
"""
struct TripartiteMutualInformation <: AbstractObservable
    mi_ab::MutualInformation
    mi_ac::MutualInformation
    mi_abc::MutualInformation

    function TripartiteMutualInformation(A, B, C; renyi_index::Int = 1,
            threshold::Float64 = 1e-16, base::Real = ℯ)
        rA = _mi_contiguous_region(A, "region A")
        rB = _mi_contiguous_region(B, "region B")
        rC = _mi_contiguous_region(C, "region C")
        for (n1, r1, n2, r2) in (("A", rA, "B", rB), ("A", rA, "C", rC),
            ("B", rB, "C", rC))
            isempty(intersect(r1, r2)) ||
                throw(ArgumentError(
                    "TripartiteMutualInformation regions must be pairwise disjoint; " *
                    "$n1=$r1 and $n2=$r2 overlap at sites $(intersect(r1, r2))"))
        end
        lo, hi = min(first(rB), first(rC)), max(last(rB), last(rC))
        length(rB) + length(rC) == hi - lo + 1 ||
            throw(ArgumentError(
                "TripartiteMutualInformation requires B ∪ C to be contiguous " *
                "(B and C adjacent) for the I(A:BC) term, got B=$rB, C=$rC. " *
                "Non-contiguous regions are not supported (inherited from " *
                "MutualInformation)."))
        kw = (renyi_index = renyi_index, threshold = threshold, base = base)
        new(MutualInformation(rA, rB; kw...), MutualInformation(rA, rC; kw...),
            MutualInformation(rA, lo:hi; kw...))
    end
end

"""
    (tmi::TripartiteMutualInformation)(state::SimulationState) -> Float64

Evaluate I₃ = I(A:B) + I(A:C) − I(A:BC) as three `MutualInformation`
evaluations, on whatever backend `state` uses.
"""
function (tmi::TripartiteMutualInformation)(state)
    return tmi.mi_ab(state) + tmi.mi_ac(state) - tmi.mi_abc(state)
end
