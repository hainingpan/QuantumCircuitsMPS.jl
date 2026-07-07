"""
Compute physical-to-RAM and RAM-to-physical site mappings.

For OBC: identity mapping (1:L -> 1:L)
For PBC: folded mapping - interleaves sites zig-zagging outward from `pbc_fold_start`

Parameters:
- L: system size
- bc: boundary condition (:open or :periodic)
- pbc_fold_start: physical site the PBC zig-zag fold starts from (default `L÷4+1`,
  the middle-aligned choice giving a contiguous half-cut). Ignored for `bc == :open`.
  Must satisfy `1 <= pbc_fold_start <= L` for `bc == :periodic`.

Returns: (phy_ram, ram_phy) where:
- phy_ram[physical_site] = ram_index
- ram_phy[ram_index] = physical_site
"""
function compute_basis_mapping(L::Int, bc::Symbol; pbc_fold_start::Int = L÷4+1)
    bc in (:open, :periodic) ||
        throw(ArgumentError("bc must be :open or :periodic, got $bc"))

    if bc == :open
        # OBC: direct mapping (identity); pbc_fold_start is ignored
        return collect(1:L), collect(1:L)
    else
        # PBC: folded mapping
        # PBC requires even L for the folded basis algorithm
        iseven(L) || throw(ArgumentError("PBC folded basis requires even L, got L=$L"))
        (pbc_fold_start < 1 || pbc_fold_start > L) &&
            throw(ArgumentError("pbc_fold_start must be between 1 and L=$L, got $pbc_fold_start"))

        # Zig-zag folded mapping starting from pbc_fold_start: interleave clockwise
        # and counter-clockwise neighbors around the ring, e.g. for pbc_fold_start=1:
        # ram_phy = [1, L, 2, L-1, 3, L-2, ...]
        # This places physical neighbors near each other in RAM for efficient MPS operations
        ram_phy = Int[]
        for i in 1:(L ÷ 2)
            push!(ram_phy, mod1(pbc_fold_start + (i - 1), L))   # clockwise
            push!(ram_phy, mod1(pbc_fold_start - i, L))          # counter-clockwise
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
