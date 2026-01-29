using ITensors: Index
using ITensorMPS: MPS, siteinds, randomMPS
using Random
using LinearAlgebra

abstract type AbstractGate end
abstract type AbstractMeasurement end
abstract type AbstractObservable end
abstract type AbstractPattern end
abstract type AbstractCircuit end

const _MAXDIM0 = 10

mutable struct SimulationState{I<:Index}
    L::Int
    current_site::Int
    observables::Dict{Symbol,Vector{Any}}

    _mps::MPS
    _qubit_sites::Vector{I}
    _phy_ram::Vector{Int}
    _ram_phy::Vector{Int}
    _phy_list::Vector{Int}
    _rng_circuit::MersenneTwister
    _rng_meas::MersenneTwister
    _cutoff::Float64
    _maxdim::Int
end

function _dec2bin(x::Real, L::Int)::BigInt
    @assert 0 <= x < 1 "$x is not in [0,1)"
    return BigInt(floor(x * (BigInt(1) << L)))
end

function _initialize_basis(L::Int, ancilla::Int, folded::Bool)
    ancilla == 0 || error("v1 supports ancilla=0 only")
    qubit_sites = siteinds("Qubit", L + ancilla)

    ram_phy = folded ? [i for pairs in zip(1:(L ÷ 2), reverse((L ÷ 2 + 1):L)) for i in pairs] : collect(1:L)
    phy_ram = fill(0, L + ancilla)
    for (ram, phy) in enumerate(ram_phy)
        phy_ram[phy] = ram
    end

    phy_list = collect(1:L)
    return qubit_sites, ram_phy, phy_ram, phy_list
end

function _initialize_vector(
    L::Int,
    ancilla::Int,
    x0::Union{Rational{Int},Rational{BigInt},Nothing},
    folded::Bool,
    qubit_sites::Vector{I},
    ram_phy::Vector{Int},
    phy_ram::Vector{Int},
    phy_list::Vector{Int},
    rng_vec::Random.AbstractRNG,
    cutoff::Float64,
    maxdim0::Int,
) where {I<:Index}
    ancilla == 0 || error("v1 supports ancilla=0 only")
    if x0 !== nothing
        vec_int = _dec2bin(x0, L)
        vec_int_pos = [string(s) for s in lpad(string(vec_int, base=2), L, "0")]
        return MPS(ComplexF64, qubit_sites, [vec_int_pos[ram_phy[i]] for i in 1:L])
    end

    return randomMPS(rng_vec, qubit_sites, linkdims=maxdim0)
end

function SimulationState(
    ; L::Int,
    seed_circuit::Int=0,
    seed_meas::Int=0,
    x0::Union{Rational{Int},Rational{BigInt},Nothing}=nothing,
    cutoff::Float64=1e-10,
    maxdim::Int=typemax(Int),
)
    isodd(L) && throw(ArgumentError("L must be even for v1"))

    folded = true
    ancilla = 0
    rng_circuit = MersenneTwister(seed_circuit)
    rng_meas = MersenneTwister(seed_meas)
    rng_vec = rng_circuit

    qubit_sites, ram_phy, phy_ram, phy_list = _initialize_basis(L, ancilla, folded)
    mps = _initialize_vector(L, ancilla, x0, folded, qubit_sites, ram_phy, phy_ram, phy_list, rng_vec, cutoff, _MAXDIM0)

    observables = Dict{Symbol,Vector{Any}}()
    return SimulationState(
        L,
        L,
        observables,
        mps,
        qubit_sites,
        phy_ram,
        ram_phy,
        phy_list,
        rng_circuit,
        rng_meas,
        cutoff,
        maxdim,
    )
end
