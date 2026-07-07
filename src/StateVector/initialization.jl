using ITensors
using Random
using LinearAlgebra

"""
    RandomStateVector()

Random Haar-random unit-norm state-vector initialization for the state-vector
backend. Mirrors `RandomMPS`'s simplicity (no fields). Requires RNGRegistry
with :state_init stream attached to the SimulationState.
"""
struct RandomStateVector <: AbstractInitialState end

"""
    _local_basis_vector(site_type::String, local_dim::Int, name::String) -> Vector{Float64}

Resolve a single-site ITensor state name (e.g. "0", "1", "Up", "Z0", "Dn") into
a dense local basis vector, WITHOUT constructing a full MPS. Used to build a
state-vector-backend product state site-by-site.

Verified outputs: Qubit "0"->[1,0], "1"->[0,1]; S=1 "Up"->[1,0,0], "Z0"->[0,1,0],
"Dn"->[0,0,1].
"""
function _local_basis_vector(site_type::String, local_dim::Int, name::String)
    single_site = site_type == "Qudit" ? siteinds("Qudit", 1; dim = local_dim)[1] :
                  siteinds(site_type, 1)[1]
    t = ITensors.state(single_site, name)
    return Array(t, single_site)
end

"""
    _product_state_vector(site_type, local_dim, state_names_physical) -> Vector{ComplexF64}

Build the full dense product-state vector via Kronecker product of the L
per-site local basis vectors, with site 1 FIRST in the kron chain (i.e.
`kron(v1, v2, ..., vL)`). This makes physical site 1 the slowest-varying/MSB
tensor index, matching the MPS backend's documented MSB convention
(`bit_pattern_str[1]` is site 1's bit) and the SAME Kronecker convention
documented in `src/Gates/matrix_gate.jl` (used by `gate_matrix`).
"""
function _product_state_vector(site_type::String, local_dim::Int, state_names_physical::Vector{String})
    vecs = [_local_basis_vector(site_type, local_dim, name)
            for name in state_names_physical]
    ψ_real = reduce(kron, vecs)
    return Vector{ComplexF64}(ψ_real)
end

"""
    initialize!(state::SimulationState{StateVectorBackend}, init::ProductState)

Initialize a state-vector-backend `SimulationState` with a product state,
based on the specified initialization method (binary_int, binary_decimal,
bitstring, or spin_state). Reuses the EXACT SAME `state_names_physical`
computation logic as the MPS path (`src/State/initialization.jl`), but builds
a dense `Vector{ComplexF64}` directly instead of an `MPS`.

Since `ram_phy`/`phy_ram` are the IDENTITY for the state-vector backend (Task
5), no physical-to-RAM reordering is applied here — physical site i directly
corresponds to tensor index i.

Site 1 = MSB = slowest-varying tensor index (see `_product_state_vector`).
"""
function initialize!(state::SimulationState{StateVectorBackend}, init::ProductState)
    L = state.L
    site_type = state.site_type
    local_dim = state.local_dim

    # Handle uniform spin_state branch early (no ram_phy reorder needed for SV)
    if init.spin_state !== nothing
        state_names_physical = fill(init.spin_state, L)
        state.backend.ψ = _product_state_vector(site_type, local_dim, state_names_physical)
        return nothing
    end

    # Convert init specification to bit pattern string (identical logic to MPS path)
    bit_pattern_str::String = if init.binary_int !== nothing
        # Convert integer to binary string, padded to L digits
        lpad(string(init.binary_int, base = 2), L, "0")
    elseif init.binary_decimal !== nothing
        # Parse binary decimal: 0.101 → "101"
        decimal_str = string(init.binary_decimal)
        if !startswith(decimal_str, "0.")
            throw(ArgumentError("binary_decimal must be in format 0.xxx (e.g., 0.101)"))
        end
        bitstr = decimal_str[3:end]  # Skip "0."
        # Validate only 0/1
        if !all(c in ('0', '1') for c in bitstr)
            throw(ArgumentError("binary_decimal digits must be 0 or 1"))
        end
        # Pad or truncate to L
        if length(bitstr) < L
            rpad(bitstr, L, "0")
        elseif length(bitstr) > L
            bitstr[1:L]
        else
            bitstr
        end
    elseif init.bitstring !== nothing
        # Use bitstring directly, pad or truncate to L
        bitstr = init.bitstring
        if length(bitstr) < L
            rpad(bitstr, L, "0")
        elseif length(bitstr) > L
            bitstr[1:L]
        else
            bitstr
        end
    else
        throw(ArgumentError("ProductState has no initialization method specified"))
    end

    # bit_pattern_str[i] is the bit value at PHYSICAL site i (MSB at site 1)
    vec_int_pos = [string(c) for c in bit_pattern_str]

    # Map to state names based on site_type
    state_names_physical = if site_type == "Qubit"
        # "0" → "0", "1" → "1"
        vec_int_pos
    elseif site_type == "S=1"
        # For S=1: "0" → "Up" (m=+1), "1" → "Dn" (m=-1)
        # ITensor uses "Up"/"Z0"/"Dn" for m = +1, 0, -1
        # Binary encoding: 0 = spin up, 1 = spin down
        [b == "0" ? "Up" : "Dn" for b in vec_int_pos]
    elseif site_type == "Qudit"
        # Generic qudit: "0" → "1", "1" → "2", etc. (1-indexed states)
        [string(parse(Int, b) + 1) for b in vec_int_pos]
    else
        throw(ArgumentError("Unknown site_type: $site_type"))
    end

    state.backend.ψ = _product_state_vector(site_type, local_dim, state_names_physical)

    return nothing
end

"""
    initialize!(state::SimulationState{StateVectorBackend}, init::RandomStateVector)

Initialize a state-vector-backend `SimulationState` with a Haar-random unit
vector, drawn from the `:state_init` RNG stream.
"""
function initialize!(state::SimulationState{StateVectorBackend}, init::RandomStateVector)
    if state.rng_registry === nothing
        throw(ArgumentError(
            "RandomStateVector requires RNGRegistry with :state_init stream. " *
            "Attach RNG before calling initialize! via: " *
            "state = SimulationState(..., rng=RNGRegistry(...))"
        ))
    end

    rng = get_rng(state.rng_registry, :state_init)
    d = state.local_dim^state.L
    v = randn(rng, ComplexF64, d)
    state.backend.ψ = v ./ norm(v)

    return nothing
end
