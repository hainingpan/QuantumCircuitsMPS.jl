# === Magnetization-Fluctuations Observable ===
#
# Var(M) for M = Σ_{i∈R} Pᵢ (P = Z by default), composed from PauliString
# expectations, so it inherits per-backend dispatch (MPS, SV, Clifford).
#
# Formula: Var(M) = ⟨M²⟩ − ⟨M⟩² with M² = Σᵢ Pᵢ² + Σ_{i≠j} PᵢPⱼ and Pᵢ² = I
# for Pauli operators, so the DIAGONAL contributes exactly |R| — it is
# special-cased analytically (PauliString rejects repeated sites, so the
# i = j term must NOT be evaluated as a PauliString).

"""
    MagnetizationFluctuations(region; axis=:Z)

Variance of the total magnetization M = Σ_{i∈R} Pᵢ over the site region `R`,
with P the Pauli operator selected by `axis` (`:X`, `:Y`, or `:Z`).

Computed as

    Var(M) = |R| + Σ_{i≠j} ⟨PᵢPⱼ⟩ − (Σᵢ ⟨Pᵢ⟩)²

using Pᵢ² = I for the diagonal of ⟨M²⟩ (the analytic constant |R|), so the
formula never evaluates a same-site Pauli-string product. This is
O(|R|²) `PauliString` evaluations. Supported on all three backends
(composition of `PauliString`, which dispatches per backend); qubit-only in
v0.4.0 (inherited from `PauliString`).

`region` may be any collection of distinct positive sites (a range like
`1:6`, an `Int`, or a vector — contiguity is NOT required, since M is a sum
of single-site operators).

# Properties (analytic anchors)
- Product Z-basis state, `axis=:Z`: Var = 0 (M is sharp)
- GHZ(L=6), R=1:6, `axis=:Z`: ⟨ZᵢZⱼ⟩=1 for all i≠j and ⟨Zᵢ⟩=0, so
  Var = 6 + 30 − 0 = 36 exactly

# Examples
```julia
vm = MagnetizationFluctuations(1:6)          # Var of Σ Zᵢ over sites 1..6
value = vm(state)
track!(state, :varM => MagnetizationFluctuations(2:5; axis=:X))
```
"""
struct MagnetizationFluctuations <: AbstractObservable
    sites::Vector{Int}
    axis::Symbol

    function MagnetizationFluctuations(region; axis::Symbol = :Z)
        axis in (:X, :Y, :Z) ||
            throw(ArgumentError(
                "MagnetizationFluctuations axis must be :X, :Y, or :Z, got :$axis"))
        sites = region isa Integer ? [Int(region)] : Int.(vec(collect(region)))
        isempty(sites) &&
            throw(ArgumentError("MagnetizationFluctuations region must be non-empty"))
        allunique(sites) ||
            throw(ArgumentError(
                "MagnetizationFluctuations region has repeated sites: $sites"))
        all(s -> s >= 1, sites) ||
            throw(ArgumentError(
                "MagnetizationFluctuations region sites must be positive, got $sites"))
        new(sort!(sites), axis)
    end
end

"""
    (vm::MagnetizationFluctuations)(state::SimulationState) -> Float64

Evaluate Var(M) = |R| + Σ_{i≠j} ⟨PᵢPⱼ⟩ − (Σᵢ ⟨Pᵢ⟩)² via `PauliString`
expectations (the diagonal |R| is analytic — Pᵢ² = I is never sent to
`PauliString`, which rejects repeated sites). Works on every backend that
supports `PauliString`.
"""
function (vm::MagnetizationFluctuations)(state)
    R = vm.sites
    p = vm.axis
    singles = [PauliString(i => p)(state) for i in R]
    off_diag = 0.0
    for a in 1:length(R), b in (a + 1):length(R)
        # ⟨PᵢPⱼ⟩ is symmetric in i,j: count each unordered pair twice.
        off_diag += 2 * PauliString(R[a] => p, R[b] => p)(state)
    end
    return length(R) + off_diag - sum(singles)^2
end
