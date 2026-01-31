"""
Compute physical-to-RAM and RAM-to-physical site mappings.

For OBC: identity mapping (1:L -> 1:L)
For PBC: folded mapping - interleaves sites from both ends

Returns: (phy_ram, ram_phy) where:
- phy_ram[physical_site] = ram_index
- ram_phy[ram_index] = physical_site
"""
function compute_basis_mapping(L::Int, bc::Symbol)
    bc in (:open, :periodic) || throw(ArgumentError("bc must be :open or :periodic, got $bc"))
    
    if bc == :open
        # OBC: direct mapping (identity)
        return collect(1:L), collect(1:L)
    else
        # PBC: folded mapping
        # PBC requires even L for the folded basis algorithm
        iseven(L) || throw(ArgumentError("PBC folded basis requires even L, got L=$L"))
        
        # CT.jl folded mapping: interleave from both ends
        # ram_phy = [1, L, 2, L-1, 3, L-2, ...]
        # This places physical neighbors near each other in RAM for efficient MPS operations
        ram_phy = Int[]
        for (a, b) in zip(1:L÷2, reverse((L÷2+1):L))
            push!(ram_phy, a)
            push!(ram_phy, b)
        end

        
        # phy_ram is the inverse: phy_ram[physical_site] = ram_index
        phy_ram = zeros(Int, L)
        for (ram_idx, phy_site) in enumerate(ram_phy)
            phy_ram[phy_site] = ram_idx
        end
        
        return phy_ram, ram_phy
    end
end

# Convenience accessors
physical_to_ram(state, phy_site::Int) = state.phy_ram[phy_site]
ram_to_physical(state, ram_site::Int) = state.ram_phy[ram_site]
