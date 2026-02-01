# === String Order Parameter Observable for AKLT Chains ===
#
# Computes the string order parameter:
#   O_string(i,j) = ⟨Sz[i] * exp(iπ Σ_{k=i+1}^{j-1} Sz[k]) * Sz[j]⟩
#
# For AKLT ground state: |O_string| ≈ 4/9 ≈ 0.444

using ITensors
using ITensorMPS

"""
    StringOrder(i::Int, j::Int)

String order parameter observable for spin-1 chains.

Computes: ⟨Sz[i] * exp(iπ Σ_{k=i+1}^{j-1} Sz[k]) * Sz[j]⟩

# Arguments
- `i`: First site index (physical indexing)
- `j`: Second site index (physical indexing, must be j > i)

# Physics
For AKLT ground state on spin-1 chain:
- Nearest neighbors: |O_string| ≈ 4/9 ≈ 0.444
- Next-nearest neighbors: |O_string| ≈ (4/9)² ≈ 0.198

# Example
```julia
s = SimulationState(L=8, bc=:periodic, site_type="S=1")
initialize!(s, ProductState(binary_int=0))
# ... apply AKLT protocol ...
so = compute(StringOrder(1, 5), s)  # Half-chain separation
```

# References
- AKLT (1987): Rigorous results on valence-bond ground states
- String order distinguishes Haldane phase from trivial phases
"""
struct StringOrder <: AbstractObservable
    i::Int
    j::Int
    
    function StringOrder(i::Int, j::Int)
        i > 0 || throw(ArgumentError("i must be positive, got $i"))
        j > i || throw(ArgumentError("j must be > i, got j=$j, i=$i"))
        new(i, j)
    end
end

"""
    (obs::StringOrder)(state::SimulationState) -> Float64

Compute string order parameter via MPS contraction.
"""
function (obs::StringOrder)(state::SimulationState)
    i_phys = obs.i
    j_phys = obs.j
    L = state.L
    
    # Validate sites are in bounds
    if i_phys > L || j_phys > L
        throw(ArgumentError(
            "StringOrder sites ($i_phys, $j_phys) exceed system size L=$L"
        ))
    end
    
    # Convert physical sites to RAM indices
    i_ram = state.phy_ram[i_phys]
    j_ram = state.phy_ram[j_phys]
    
    # Get site indices
    site_i = state.sites[i_ram]
    site_j = state.sites[j_ram]
    
    # Build operator string: Sz[i] * ∏_{k=i+1}^{j-1} exp(iπSz[k]) * Sz[j]
    # Start with identity
    psi_copy = copy(state.mps)
    
    # Apply Sz at site i
    Sz_i = op("Sz", site_i)
    psi_copy[i_ram] = psi_copy[i_ram] * Sz_i
    
    # Apply exp(iπ Sz) to all sites between i and j
    for k_phys in (i_phys+1):(j_phys-1)
        k_ram = state.phy_ram[k_phys]
        site_k = state.sites[k_ram]
        
        # exp(iπ Sz) for spin-1: diag(-1, 1, -1) for |+1⟩, |0⟩, |-1⟩
        # ITensor S=1 basis: "Up" (m=+1), "Z0" (m=0), "Dn" (m=-1)
        # exp(iπ Sz) = exp(iπ m) = (-1)^m for m ∈ {-1, 0, +1}
        # Result: diag(-1, 1, -1)
        expSz_k = op("expSz", site_k)
        psi_copy[k_ram] = psi_copy[k_ram] * expSz_k
    end
    
    # Apply Sz at site j
    Sz_j = op("Sz", site_j)
    psi_copy[j_ram] = psi_copy[j_ram] * Sz_j
    
    # Compute expectation value: ⟨ψ|O|ψ⟩ = inner(ψ', O|ψ⟩)
    # Need to prime the bra to match the operator application
    result = real(inner(prime(state.mps), psi_copy))
    
    return result
end

# === Define custom ITensor operator for exp(iπ Sz) ===

"""
Define exp(iπ Sz) operator for S=1 sites.

For spin-1: Sz = diag(+1, 0, -1) in basis |+1⟩, |0⟩, |-1⟩
exp(iπ Sz) = diag(exp(iπ), exp(0), exp(-iπ))
           = diag(-1, 1, -1)

This is a diagonal operator in the Sz basis.
"""
function ITensors.op(::OpName"expSz", ::SiteType"S=1")
    return [
        -1.0  0.0  0.0;   # |Up⟩ (m=+1): exp(iπ·1) = -1
         0.0  1.0  0.0;   # |Z0⟩ (m=0):  exp(iπ·0) = +1
         0.0  0.0 -1.0    # |Dn⟩ (m=-1): exp(iπ·(-1)) = -1
    ]
end
