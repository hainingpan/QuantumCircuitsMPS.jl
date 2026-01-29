module Observables

using ITensors
using ITensorMPS: MPS, orthogonalize, expect

using ..Core: AbstractObservable, current_state

export MagnetizationZ,
       MagnetizationZiAll,
       EntanglementEntropy,
       Entropy,
       MaxBondDim

struct MagnetizationZ <: AbstractObservable end
struct MagnetizationZiAll <: AbstractObservable end
struct EntanglementEntropy <: AbstractObservable
    cut::Int
    order::Int
end
struct MaxBondDim <: AbstractObservable end

Entropy(cut::Int; order::Int=1) = EntanglementEntropy(cut, order)

function _ensure_obs!(state, key::Symbol)
    get!(state.observables, key) do
        Vector{Any}()
    end
end

function _zi(state)
    sZ = expect(state._mps, "Sz")[state._phy_ram][state._phy_list]
    return real.(sZ) * 2
end

function _von_neumann_entropy(
    mps::MPS,
    i::Int;
    n::Int=1,
    positivedefinite::Bool=false,
    threshold::Float64=1e-16,
    sv::Bool=false,
)
    mps_ = orthogonalize(mps, i)
    _, S = svd(mps_[i], (linkind(mps_, i),))
    if sv
        return array(diag(S))
    end
    p = positivedefinite ? max.(diag(S), threshold) : max.(diag(S), threshold) .^ 2
    if n == 1
        return -sum(p .* log.(p))
    elseif n == 0
        return log(length(p))
    end
    return log(sum(p .^ n)) / (1 - n)
end

function (obs::MagnetizationZiAll)()
    state = current_state()
    sZi = _zi(state)
    vec = _ensure_obs!(state, :Zi)
    push!(vec, sZi)
    return sZi
end

function (obs::MagnetizationZ)()
    state = current_state()
    sZi = _zi(state)
    value = real(sum(sZi)) / state.L
    vec = _ensure_obs!(state, :Z)
    push!(vec, value)
    return value
end

function (obs::EntanglementEntropy)()
    state = current_state()
    1 <= obs.cut < state.L || throw(ArgumentError("cut must satisfy 1 <= cut < L"))
    ram_cut = state._phy_ram[obs.cut]
    value = _von_neumann_entropy(state._mps, ram_cut; n=obs.order)
    vec = _ensure_obs!(state, :entropy)
    push!(vec, value)
    return value
end

function (obs::MaxBondDim)()
    state = current_state()
    max_dim = 0
    for i in 1:(length(state._mps) - 1)
        dim = commonind(state._mps[i], state._mps[i + 1])
        max_dim = max(max_dim, space(dim))
    end
    vec = _ensure_obs!(state, :max_bond_dim)
    push!(vec, max_dim)
    return max_dim
end

end
