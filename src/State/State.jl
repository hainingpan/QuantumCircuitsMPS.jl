using ITensors
using ITensorMPS

# Forward declaration for RNGRegistry (defined in Task 2)
# For now, use Union{Nothing, Any} to avoid dependency
const RNGRegistryType = Any

"""
    SimulationState

Main simulation state container holding MPS and metadata.

Fields:
- mps: The MPS tensor network (Nothing until initialize! called)
- sites: ITensor site indices
- phy_ram: physical site -> RAM index mapping
- ram_phy: RAM index -> physical site mapping
- L: system size
- bc: boundary condition (:open or :periodic)
- local_dim: local Hilbert space dimension (default 2 for qubits)
- cutoff: SVD truncation cutoff
- maxdim: maximum bond dimension
- rng_registry: RNG streams for reproducibility
- observables: tracked observable values
- observable_specs: observable specifications
"""
mutable struct SimulationState
    mps::Union{MPS, Nothing}
    sites::Vector{Index}
    phy_ram::Vector{Int}
    ram_phy::Vector{Int}
    L::Int
    bc::Symbol
    local_dim::Int
    cutoff::Float64
    maxdim::Int
    rng_registry::Union{RNGRegistryType, Nothing}
    observables::Dict{Symbol, Vector}
    observable_specs::Dict{Symbol, Any}
end

"""
    SimulationState(; L, bc, local_dim=2, cutoff=1e-10, maxdim=100, rng=nothing)

Create a new simulation state. MPS is created later via initialize!().
"""
function SimulationState(;
    L::Int,
    bc::Symbol,
    local_dim::Int = 2,
    cutoff::Float64 = 1e-10,
    maxdim::Int = 100,
    rng = nothing  # RNGRegistry, attached later or passed here
)
    # Validate bc
    bc in (:open, :periodic) || throw(ArgumentError("bc must be :open or :periodic, got $bc"))
    
    # Compute basis mapping (OBC works now, PBC throws until Task 4)
    phy_ram, ram_phy = compute_basis_mapping(L, bc)
    
    # Create site indices in RAM order
    sites = siteinds("Qubit", L)
    
    # Return state with MPS=nothing (deferred to initialize!)
    return SimulationState(
        nothing,  # mps - set by initialize!
        sites,
        phy_ram,
        ram_phy,
        L,
        bc,
        local_dim,
        cutoff,
        maxdim,
        rng,
        Dict{Symbol, Vector}(),  # observables
        Dict{Symbol, Any}()      # observable_specs
    )
end
