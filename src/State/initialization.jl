using ITensors
using ITensorMPS

"""
Abstract type for initial state specifications.
"""
abstract type AbstractInitialState end

"""
    ProductState(; x0::Rational)

Product state specified by a rational number x0 ∈ [0, 1).
The binary representation determines qubit values.

CT.jl bit ordering (MSB at site 1, LSB at site L):
- x0 = 1//2^L means site L has "1", all others "0"
- x0 = 1//2 means site 1 has "1", all others "0"
"""
struct ProductState <: AbstractInitialState
    x0::Rational{BigInt}
    
    function ProductState(; x0::Union{Rational, Integer})
        x0_rational = x0 isa Integer ? Rational{BigInt}(x0) : Rational{BigInt}(x0)
        return new(x0_rational)
    end
end

# Allow ProductState(x0=...) syntax
ProductState(x0) = ProductState(; x0=x0)

"""
    RandomMPS(; bond_dim::Int)

Random MPS with specified bond dimension.
Requires RNGRegistry with :state_init stream.
"""
struct RandomMPS <: AbstractInitialState
    bond_dim::Int
    
    function RandomMPS(; bond_dim::Int = 1)
        return new(bond_dim)
    end
end

"""
    initialize!(state::SimulationState, init::ProductState)

Initialize state with a product state based on x0 bit pattern.
Uses CT.jl MSB ordering: site 1 = MSB, site L = LSB.
"""
function initialize!(state::SimulationState, init::ProductState)
    L = state.L
    
    # Convert x0 to integer bit pattern (CT.jl dec2bin)
    # x0 = numerator / 2^L, so vec_int = floor(x0 * 2^L) = numerator (if denominator is 2^L)
    vec_int = BigInt(floor(init.x0 * (BigInt(1) << L)))
    
    # Convert to binary string, padded to L digits
    vec_int_pos = [string(s) for s in lpad(string(vec_int, base=2), L, "0")]
    # vec_int_pos[i] is the bit value at PHYSICAL site i (MSB at site 1)
    
    # Reorder to RAM order using ram_phy
    # ram_bits[ram_idx] = bit value for RAM site ram_idx
    ram_bits = [vec_int_pos[state.ram_phy[i]] for i in 1:L]
    
    # Create MPS from bit strings
    state.mps = MPS(state.sites, ram_bits)
    
    return nothing
end

"""
    initialize!(state::SimulationState, init::RandomMPS)

Initialize state with a random MPS.
Requires RNGRegistry with :state_init stream attached to state.
"""
function initialize!(state::SimulationState, init::RandomMPS)
    if state.rng_registry === nothing
        throw(ArgumentError(
            "RandomMPS requires RNGRegistry with :state_init stream. " *
            "Attach RNG before calling initialize! via: " *
            "state = SimulationState(..., rng=RNGRegistry(...))"
        ))
    end
    
    # Use ITensorMPS randomMPS with specified bond dimension
    # Note: ITensorMPS 0.3+ uses Random.default_rng() internally
    # For reproducibility with our RNG, we'd need to seed it
    # For now, just use the specified bond_dim
    state.mps = randomMPS(state.sites; linkdims=init.bond_dim)
    
    return nothing
end
