import QuantumClifford
using QuantumClifford: MixedDestabilizer, Stabilizer, sX

"""
    initialize!(state::SimulationState{CliffordBackend}, init::ProductState)

Initialize a Clifford-backend `SimulationState` with a computational-basis
product state, based on the specified initialization method (`binary_int`,
`binary_decimal`, or `bitstring`). Reuses the EXACT SAME bit-pattern-string
derivation logic as the MPS/state-vector paths
(`src/State/initialization.jl` / `src/StateVector/initialization.jl`).

`init.spin_state` is NOT supported: the Clifford backend is qubit-only
(`local_dim=2`, enforced at construction time in `src/State/State.jl`), while
`spin_state` is an S=1/qudit-oriented field.

Site 1 = MSB (most significant bit) — identical convention to the MPS/SV
backends. Since `ram_phy`/`phy_ram` are the IDENTITY for the Clifford backend
(Task 7), no physical-to-RAM reordering is applied here — physical site i
directly corresponds to qubit i in the tableau.
"""
function initialize!(state::SimulationState{CliffordBackend}, init::ProductState)
    L = state.L

    if init.spin_state !== nothing
        throw(ArgumentError(
            "Clifford backend does not support spin_state initialization " *
            "(qubit-only, use binary_int/bitstring/binary_decimal instead)"
        ))
    end

    # Convert init specification to bit pattern string (identical logic to
    # MPS/StateVector paths)
    bit_pattern_str::String = if init.binary_int !== nothing
        # Convert integer to binary string, padded to L digits
        lpad(string(init.binary_int, base=2), L, "0")
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
    d = MixedDestabilizer(one(Stabilizer, L))
    for i in 1:L
        if bit_pattern_str[i] == '1'
            QuantumClifford.apply!(d, sX(i))
        end
    end

    state.backend.tableau = d

    return nothing
end
