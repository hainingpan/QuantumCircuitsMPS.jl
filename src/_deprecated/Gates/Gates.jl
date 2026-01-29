module Gates

using ITensors
using ITensorMPS: MPS, orthogonalize!, siteind, linkind
using Random
using LinearAlgebra

using ..Core: AbstractGate, current_state

export HaarGate,
       SimplifiedGate,
       apply!

struct HaarGate <: AbstractGate end
struct SimplifiedGate <: AbstractGate end

const CZ_mat = [1.0 0.0 0.0 0.0;
                0.0 1.0 0.0 0.0;
                0.0 0.0 1.0 0.0;
                0.0 0.0 0.0 -1.0 + 0im]

function Rx(theta::Float64)
    return [cos(theta / 2) -im * sin(theta / 2);
            -im * sin(theta / 2) cos(theta / 2)]
end

function Rz(theta::Float64)
    return [exp(-im * theta / 2) 0;
            0 exp(im * theta / 2)]
end

function U(n::Int, rng::Random.AbstractRNG=MersenneTwister(nothing))
    z = randn(rng, n, n) + randn(rng, n, n) * im
    Q, R = qr(z)
    r_diag = diag(R)
    Lambda = Diagonal(r_diag ./ abs.(r_diag))
    Q *= Lambda
    return Q
end

function U_simp(CZ::Bool, rng::Random.AbstractRNG, theta::Union{Vector{Any},Nothing}=nothing)
    if theta === nothing
        theta = rand(rng, 12) * 2 * pi
    end

    U1 = kron(Rx(theta[1]), Rx(theta[4]))
    U2 = kron(Rz(theta[2]), Rz(theta[5]))
    U3 = kron(Rx(theta[3]), Rx(theta[6]))
    U4 = CZ ? CZ_mat : Matrix{ComplexF64}(I, 4, 4)
    U5 = kron(Rx(theta[7]), Rx(theta[10]))
    U6 = kron(Rz(theta[8]), Rz(theta[11]))
    U7 = kron(Rx(theta[9]), Rx(theta[12]))

    U_final = U7 * U6 * U5 * U4 * U3 * U2 * U1
    return collect(transpose(U_final))
end

function apply_op!(mps::MPS, op::ITensor, cutoff::Float64, maxdim::Int)
    i_list = [parse(Int, replace(string(tags(inds(op)[i])[length(tags(inds(op)[i]))]), "n=" => ""))
              for i in 1:div(length(op.tensor.inds), 2)]
    sort!(i_list)
    orthogonalize!(mps, i_list[1])
    mps_ij = mps[i_list[1]]
    for idx in i_list[1] + 1:i_list[end]
        mps_ij *= mps[idx]
    end
    mps_ij *= op
    noprime!(mps_ij)

    if length(i_list) == 1
        mps[i_list[1]] = mps_ij
    else
        lefttags = (i_list[1] == 1) ? nothing : tags(linkind(mps, i_list[1] - 1))
        for idx in i_list[1]:i_list[end]-1
            inds1 = (idx == 1) ? [siteind(mps, 1)] : [findindex(mps[idx - 1], lefttags), findindex(mps[idx], "Site")]
            lefttags = tags(linkind(mps, idx))
            U_, S, V = svd(mps_ij, inds1, cutoff=cutoff, lefttags=lefttags, maxdim=maxdim)
            mps[idx] = U_
            mps_ij = S * V
        end
        mps[i_list[end]] = mps_ij
    end
    return
end

function _validate_pair(L::Int, i::Int, j::Int)
    if j == i + 1
        return
    end
    if i == L && j == 1
        return
    end
    throw(ArgumentError("Gate pair must be adjacent physical sites or (L, 1); got ($i, $j)"))
end

function _apply_two_site!(U_4_mat::AbstractMatrix{<:Complex}, i::Int, j::Int)
    state = current_state()
    _validate_pair(state.L, i, j)

    ram_idx = [state._phy_ram[i], state._phy_ram[j]]
    U_4 = reshape(U_4_mat, 2, 2, 2, 2)
    U_4_tensor = ITensor(
        U_4,
        state._qubit_sites[ram_idx[1]],
        state._qubit_sites[ram_idx[2]],
        state._qubit_sites[ram_idx[1]]',
        state._qubit_sites[ram_idx[2]]',
    )
    apply_op!(state._mps, U_4_tensor, state._cutoff, state._maxdim)
    return
end

function apply!(::HaarGate, i::Int, j::Int)
    state = current_state()
    U_4_mat = U(4, state._rng_circuit)
    _apply_two_site!(U_4_mat, i, j)
    return
end

function apply!(::SimplifiedGate, i::Int, j::Int)
    state = current_state()
    CZ = i != state.L
    U_4_mat = U_simp(CZ, state._rng_circuit)
    _apply_two_site!(U_4_mat, i, j)
    return
end

end
