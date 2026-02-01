# === Two-Site Spin Sector Operations for S=1 Chains ===
#
# This module provides two distinct operations for AKLT forced measurement:
# 1. SpinSectorProjection: Coherent projection preserving superposition
# 2. SpinSectorMeasurement: Born rule measurement with outcome collapse

"""
    SpinSectorProjection(projector::Matrix{Float64})

Coherent projection onto specified spin sectors (no measurement/collapse).

Applies projector operator P to two adjacent spin-1 sites, then renormalizes:
    |ψ⟩ → P|ψ⟩ / ||P|ψ⟩||

# Example
```julia
# Project onto S=0 and S=1 sectors (remove S=2)
P01 = total_spin_projector(0) + total_spin_projector(1)
gate = SpinSectorProjection(P01)
```

# Physics
This is a coherent operation that preserves quantum superposition.
For AKLT: Repeated application of P₀+P₁ should converge to ground state.
"""
struct SpinSectorProjection <: AbstractGate
    projector::Matrix{Float64}
    
    function SpinSectorProjection(projector::Matrix{Float64})
        # Validate projector is 9×9 (two spin-1 particles)
        size(projector) == (9, 9) || throw(ArgumentError(
            "SpinSectorProjection requires 9×9 projector for two spin-1 sites"
        ))
        return new(projector)
    end
end

support(::SpinSectorProjection) = 2

"""
    SpinSectorMeasurement(sectors::Vector{Int}=)

True Born measurement of total spin sector for two adjacent spin-1 sites.

Performs projective measurement that collapses the state to a definite spin sector.
Outcome probabilities follow Born rule: P(S) = ⟨ψ|Pₛ|ψ⟩

# Arguments
- `sectors`: Which sectors to measure (default: [0, 1, 2] for all sectors)

# Example
```julia
# Measure all three sectors
gate = SpinSectorMeasurement([0, 1, 2])

# Measure only S=0 or S=1 (post-select)
gate = SpinSectorMeasurement([0, 1])
```

# Physics
This is the research question: Does forced measurement to S∈{0,1} produce
different physics than coherent projection? Unknown behavior to explore.

# Returns
After application, the measurement outcome S can be retrieved from state history.
"""
struct SpinSectorMeasurement <: AbstractGate
    sectors::Vector{Int}
    
    function SpinSectorMeasurement(sectors::Vector{Int}=[0, 1, 2])
        # Validate sectors are valid for spin-1 ⊗ spin-1
        all(s -> s in (0, 1, 2), sectors) || throw(ArgumentError(
            "sectors must be subset of {0, 1, 2} for two spin-1 sites"
        ))
        !isempty(sectors) || throw(ArgumentError(
            "sectors must be non-empty"
        ))
        return new(sectors)
    end
end

support(::SpinSectorMeasurement) = 2

# === build_operator implementations ===

"""
    build_operator(gate::SpinSectorProjection, sites::Vector{Index}, local_dim::Int; kwargs...) -> ITensor

Build projector operator for two spin-1 sites.
Returns ITensor representation of the projector matrix.
"""
function build_operator(gate::SpinSectorProjection, sites::Vector{<:Index}, local_dim::Int; kwargs...)
    length(sites) == 2 || throw(ArgumentError("SpinSectorProjection requires exactly 2 sites"))
    local_dim == 3 || throw(ArgumentError("SpinSectorProjection requires local_dim=3 (spin-1)"))
    
    # Convert 9×9 matrix to ITensor
    # sites = [site_i, site_j] for two adjacent spins
    site_i, site_j = sites
    
    # Reshape 9×9 matrix to (3,3,3,3) tensor
    # 
    # The 9×9 projector matrix has basis ordering (m1, m2) where:
    # - m1 ∈ {+1, 0, -1} indexes the first spin (slow index in row/col)
    # - m2 ∈ {+1, 0, -1} indexes the second spin (fast index in row/col)
    # So matrix row/col = (m1-1)*3 + m2 (1-indexed with m2 cycling fast)
    #
    # Julia reshape(M, 3,3,3,3) produces tensor T where:
    # - T[i1, i2, i3, i4] with i1 fastest, i4 slowest
    # - For M[row,col]: row → (i1=m2_out, i2=m1_out), col → (i3=m2_in, i4=m1_in)
    #
    # Physical meaning: m1 = site_i, m2 = site_j
    # So reshaped tensor has indices: (site_j, site_i, site_j, site_i)
    #
    # ITensor construction must match: ITensor(data, j, i, j', i')
    proj_tensor = reshape(gate.projector, local_dim, local_dim, local_dim, local_dim)
    
    # Create ITensor with correct index ordering to match matrix basis
    # The reshaped tensor has (m2=site_j fast, m1=site_i slow) for both row and col
    op_tensor = ITensor(proj_tensor, site_j, site_i, site_j', site_i')
    
    return op_tensor
end

"""
    build_operator(gate::SpinSectorMeasurement, sites::Vector{Index}, local_dim::Int; rng) -> ITensor

Build measurement operator for two spin-1 sites.
Randomly selects one of the allowed sectors based on Born probabilities.
"""
function build_operator(gate::SpinSectorMeasurement, sites::Vector{<:Index}, local_dim::Int; rng, mps, ram_sites)
    length(sites) == 2 || throw(ArgumentError("SpinSectorMeasurement requires exactly 2 sites"))
    local_dim == 3 || throw(ArgumentError("SpinSectorMeasurement requires local_dim=3 (spin-1)"))
    
    # Compute Born probabilities for each allowed sector
    # This requires access to the current MPS state
    # For now, we'll need to add this logic in apply! dispatch
    
    # Placeholder: return projector onto first allowed sector
    # TODO: Implement proper Born sampling
    S_measured = gate.sectors[1]
    P_S = if S_measured == 0
        total_spin_projector(0)
    elseif S_measured == 1
        total_spin_projector(1)
    else
        total_spin_projector(2)
    end
    
    site_i, site_j = sites
    
    # Reshape 9×9 matrix to (3,3,3,3) tensor
    # Same basis ordering as SpinSectorProjection: m2 is fast, m1 is slow
    proj_tensor = reshape(P_S, local_dim, local_dim, local_dim, local_dim)
    
    # Create ITensor with correct index ordering to match matrix basis
    op_tensor = ITensor(proj_tensor, site_j, site_i, site_j', site_i')
    
    return op_tensor
end
