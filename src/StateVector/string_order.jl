# === String Order Parameter — State-Vector Backend ===
#
# More-specific method for SimulationState{StateVectorBackend} that exploits
# the DIAGONAL structure of the string order operator in the computational
# (Z) basis:  ⟨ψ|O|ψ⟩ = Σ_n |ψ_n|² · eigenvalue_n
#
# The operator O = Sz[i] · (Π_k exp(iπ·Sz[k])) · Sz[j]  (order=1)
# does NOT create superpositions — it multiplies each basis state by a real
# eigenvalue determined solely by the Sz values at the relevant sites.

"""
    (obs::StringOrder)(state::SimulationState{StateVectorBackend}) -> Float64

State-vector implementation of the `StringOrder` observable via diagonal
eigenvalue summation over the dense state vector.

# Eigenvalue table (S=1, `local_dim=3`)
- digit 0 ("Up", Sz=+1): `sz=+1`, `expsz=exp(iπ)=-1`
- digit 1 ("Z0", Sz=0):  `sz=0`,  `expsz=exp(0)=+1`
- digit 2 ("Dn", Sz=-1): `sz=-1`, `expsz=exp(-iπ)=-1`

# Eigenvalue table (qubit, `local_dim=2`)
- digit 0 (|0⟩, Sz=+1): `sz=+1`, `expsz=exp(iπ)=-1`
- digit 1 (|1⟩, Sz=-1): `sz=-1`, `expsz=exp(-iπ)=-1`

For qubits, `expsz = -1` unconditionally (both digits give -1), so the
string part contributes `(-1)^(number_of_string_sites)`.
"""
function (obs::StringOrder)(state::SimulationState{StateVectorBackend})
    i_phys = obs.i
    j_phys = obs.j
    L = state.L
    d = state.local_dim

    if i_phys > L || j_phys > L
        throw(ArgumentError("StringOrder sites ($i_phys, $j_phys) exceed system size L=$L"))
    end

    ψ = state.backend.ψ

    # Sz eigenvalue for a given local digit
    # S=1 (d=3): digit 0→+1, digit 1→0, digit 2→-1  i.e. sz = 1 - digit
    # Qubit (d=2): digit 0→+1, digit 1→-1
    @inline _sz(digit::Int) = d == 3 ? Float64(1 - digit) : (digit == 0 ? 1.0 : -1.0)

    # exp(iπ·Sz) eigenvalue for a given local digit
    # S=1 (d=3): diag(-1, +1, -1)  → digit==1 gives +1, else -1
    # Qubit (d=2): both digits give exp(±iπ) = -1 unconditionally
    @inline _expsz(digit::Int) = d == 3 ? (digit == 1 ? 1.0 : -1.0) : -1.0

    # Digit extraction: site 1 = MSB convention (matches all other SV
    # observables); loop-invariant strides d^(L-s) hoisted out of the n0 loop
    # (shared _sv_digit helper, see src/StateVector/StateVector.jl).
    stride_i = d^(L - i_phys)
    stride_j = d^(L - j_phys)

    total = 0.0
    if obs.order == 1
        # O¹(i,j) = Sz[i] · Π_{k=i+1}^{j-1} exp(iπ·Sz[k]) · Sz[j]
        string_strides = [d^(L - k) for k in (i_phys + 1):(j_phys - 1)]
        @inbounds for n0 in 0:(length(ψ) - 1)
            di = _sv_digit(n0, stride_i, d)
            dj = _sv_digit(n0, stride_j, d)
            eigenvalue = _sz(di) * _sz(dj)
            for stride in string_strides
                dk = _sv_digit(n0, stride, d)
                eigenvalue *= _expsz(dk)
            end
            total += abs2(ψ[n0 + 1]) * eigenvalue
        end
    else  # order == 2
        # O²(n,m) = Sz[n]·Sz[n+1] · Π_{k=n+2}^{m-2} exp(iπ·Sz[k]) · Sz[m-1]·Sz[m]
        stride_ip1 = d^(L - (i_phys + 1))
        stride_jm1 = d^(L - (j_phys - 1))
        string_strides = [d^(L - k) for k in (i_phys + 2):(j_phys - 2)]
        @inbounds for n0 in 0:(length(ψ) - 1)
            di = _sv_digit(n0, stride_i, d)
            dip1 = _sv_digit(n0, stride_ip1, d)
            djm1 = _sv_digit(n0, stride_jm1, d)
            dj = _sv_digit(n0, stride_j, d)
            eigenvalue = _sz(di) * _sz(dip1) * _sz(djm1) * _sz(dj)
            for stride in string_strides
                dk = _sv_digit(n0, stride, d)
                eigenvalue *= _expsz(dk)
            end
            total += abs2(ψ[n0 + 1]) * eigenvalue
        end
    end
    return total
end
