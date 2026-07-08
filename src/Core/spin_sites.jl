# === Arbitrary Spin-S Site Types (ITensors SiteType extension) ===
#
# ITensors ships only "S=1/2" and "S=1" spin site types natively. This file
# defines "S=k/2" site types for higher spins (S = 3/2, 2, 5/2, ..., 10) via
# ONE generic @eval loop (space/state/val/op methods), plus the per-level
# projector ops needed by categorical single-site measurement.
#
# Conventions (matching ITensors' native spin types):
# - Basis ordering: DESCENDING m — level index k (0-based) ↔ m = S - k,
#   so level 0 = |m=+S⟩ ("Up") and level 2S = |m=-S⟩ ("Dn").
# - State names: "Z<m>" for every level, with <m> written as an integer for
#   integer spins ("Z2", "Z1", "Z0", "Z-1", "Z-2") and as a fraction for
#   half-integer spins ("Z3/2", "Z1/2", "Z-1/2", "Z-3/2"). "Up"/"Dn" alias
#   the extremal levels m = ±S.
# - Ops: "Sz", "S+", "S-" (standard ladder formulas), and per-level
#   projectors "Proj0" ... "Proj<2S>" (level-index naming, matching the
#   Qubit convention "Proj0"/"Proj1" and the measurement digit convention).
#
# The native "S=1" and "S=1/2" types are NOT redefined (strictly additive):
# for "S=1" only the missing "Proj0"/"Proj1"/"Proj2" ops and "Z1"/"Z-1"
# state names are added; "S=1/2" already delegates every op/state to Qubit
# (which has "Proj0"/"Proj1" and "Z").

using LinearAlgebra

"""
    _parse_spin_site_type(site_type::AbstractString) -> Union{Nothing, Rational{Int}}

Parse a spin site-type string of the form `"S=<n>"` or `"S=<k>/2"` and return
the spin `S` as a `Rational{Int}` (e.g. `"S=1"` → `1//1`, `"S=3/2"` → `3//2`).
Returns `nothing` for any string that is not a spin site type (e.g. `"Qubit"`,
`"Qudit"`), so callers can use it as a pattern test.
"""
function _parse_spin_site_type(site_type::AbstractString)
    m = match(r"^S=(\d+)(/2)?$", site_type)
    m === nothing && return nothing
    num = parse(Int, m.captures[1])
    s = m.captures[2] === nothing ? num // 1 : num // 2
    s >= 1 // 2 || return nothing
    return s
end

"""
    _spin_m_label(m::Rational) -> String

Format a magnetic quantum number `m` for use in `"Z<m>"` state names:
integers render without denominator (`"1"`, `"-2"`), half-integers as
`"<2m>/2"` fractions (`"3/2"`, `"-1/2"`).
"""
function _spin_m_label(m::Rational)
    return denominator(m) == 1 ? string(numerator(m)) :
           string(numerator(m), "/", denominator(m))
end

"""
    spin_operators(s) -> (Sz, Sp, Sm)

Return the spin-`s` operators Sz, S+, S- as dense `(2s+1)×(2s+1)` matrices in
the descending-m basis |s,s⟩, |s,s-1⟩, ..., |s,-s⟩ (matching ITensors' spin
site conventions and `spin1_operators`).

Standard ladder formulas: Sz|s,m⟩ = m|s,m⟩ and
S±|s,m⟩ = √(s(s+1) − m(m±1)) |s,m±1⟩.

`s` may be any positive integer or half-integer (`3//2`, `1.5`, `2`, ...).
"""
function spin_operators(s::Real)
    srat = Rational{Int}(s)
    (srat >= 1 // 2 && denominator(srat) <= 2) ||
        throw(ArgumentError("spin s must be a positive integer or half-integer, got $s"))
    d = Int(2 * srat + 1)
    mvals = [Float64(srat - k) for k in 0:(d - 1)]  # descending m
    Sz = diagm(mvals)
    Sp = zeros(Float64, d, d)
    sf = Float64(srat)
    for k in 2:d
        m = mvals[k]  # S+ maps level k (m) to level k-1 (m+1)
        Sp[k - 1, k] = sqrt(sf * (sf + 1) - m * (m + 1))
    end
    Sm = collect(Sp')
    return Sz, Sp, Sm
end

# === Generic SiteType method generation ===
# One mechanism, applied over the supported spin range. "S=1/2" and "S=1" are
# native to ITensors and skipped here (no method overwrites); spins above
# S=10 raise ITensors' standard "space not defined" error at siteinds time.

"""
Largest spin for which `"S=k/2"` site types are pre-defined (S = 3/2 to 10 in
half-integer steps; "S=1/2" and "S=1" are native to ITensors).
"""
const MAX_SPIN_SITE_S = 10 // 1

# NOTE on type parameters: `SiteType`/`StateName`/`ValName` are parametrized
# by an ITensors `SmallString`, while `OpName` is parametrized by a `Symbol`
# — always build the concrete singleton types through the string constructors
# (exactly what the `SiteType"..."` string macros expand to).
for s in (3 // 2):(1 // 2):MAX_SPIN_SITE_S
    ST = typeof(SiteType("S=" * _spin_m_label(s)))
    d = Int(2 * s + 1)
    Sz, Sp, Sm = spin_operators(s)
    @eval ITensors.space(::$ST) = $d
    @eval ITensors.op(::OpName"Sz", ::$ST) = $Sz
    @eval ITensors.op(::OpName"S+", ::$ST) = $Sp
    @eval ITensors.op(::OpName"S-", ::$ST) = $Sm
    for k in 0:(d - 1)
        zlabel = "Z" * _spin_m_label(s - k)
        PN = typeof(OpName("Proj$k"))
        ZS = typeof(StateName(zlabel))
        ZV = typeof(ValName(zlabel))
        v = zeros(Float64, d)
        v[k + 1] = 1.0
        P = zeros(Float64, d, d)
        P[k + 1, k + 1] = 1.0
        @eval ITensors.op(::$PN, ::$ST) = $P
        @eval ITensors.state(::$ZS, ::$ST) = $v
        @eval ITensors.val(::$ZV, ::$ST) = $(k + 1)
    end
    let vup = [i == 1 ? 1.0 : 0.0 for i in 1:d], vdn = [i == d ? 1.0 : 0.0 for i in 1:d]
        @eval ITensors.state(::StateName"Up", ::$ST) = $vup
        @eval ITensors.state(::StateName"Dn", ::$ST) = $vdn
        @eval ITensors.val(::ValName"Up", ::$ST) = 1
        @eval ITensors.val(::ValName"Dn", ::$ST) = $d
    end
end

# === Additive extensions for the NATIVE "S=1" type ===
# ITensors defines no per-level projector ops and no "Z1"/"Z-1" state names
# for "S=1" (only "Up"/"Z0"/"Dn" and "Z+"/"Z-"). These additions make the
# generic "Z<m>" label convention and categorical measurement work uniformly.
ITensors.op(::OpName"Proj0", ::SiteType"S=1") = [1.0 0.0 0.0; 0.0 0.0 0.0; 0.0 0.0 0.0]
ITensors.op(::OpName"Proj1", ::SiteType"S=1") = [0.0 0.0 0.0; 0.0 1.0 0.0; 0.0 0.0 0.0]
ITensors.op(::OpName"Proj2", ::SiteType"S=1") = [0.0 0.0 0.0; 0.0 0.0 0.0; 0.0 0.0 1.0]
ITensors.state(::StateName"Z1", ::SiteType"S=1") = [1.0, 0.0, 0.0]
ITensors.state(::StateName"Z-1", ::SiteType"S=1") = [0.0, 0.0, 1.0]
