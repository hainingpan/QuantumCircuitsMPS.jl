"""
    EntanglementEntropy(; cut::Int, order::Int=1, threshold::Float64=1e-16)

Entanglement entropy observable.

Computes the entanglement entropy across a specified cut in the MPS.

# Arguments
- `cut::Int`: Physical site where the cut is made (must satisfy 1 <= cut < L)
- `order::Int=1`: Order of the entropy measure (must be >= 1)
  - `order=1`: von Neumann entropy S₁ = -Σᵢ λᵢ log(λᵢ) (default)
  - `order=2`: Rényi-2 entropy S₂ = log(Σᵢ λᵢ²) / (1-2)
  - `order=n`: Rényi-n entropy Sₙ = log(Σᵢ λᵢⁿ) / (1-n)
- `threshold::Float64=1e-16`: Minimum threshold for singular values (default: 1e-16)

!!! note "Hartley entropy (order=0) is NOT supported"
    Hartley entropy (order=0) measures log₂(Schmidt rank), but is not available via 
    this interface because:
    - MPS compression retains singular values above a cutoff threshold (~1e-10)
    - Numerically, "zero" singular values are never truly zero in floating-point arithmetic
    - This makes `log(rank)` give `log(maxdim)` instead of `log(true_rank)`
    - Result is threshold-dependent and unreliable
    
    **Alternative**: Access MPS singular values directly via `orthogonalize!` + `svd`,
    then apply your own threshold to determine the Schmidt rank.

# Implementation
The entropy is computed by:
1. Converting the physical cut position to RAM ordering
2. Orthogonalizing the MPS at the cut site
3. Performing SVD to obtain Schmidt values
4. Computing the entropy from the Schmidt spectrum

# Example
```julia
ee = EntanglementEntropy(; cut=2, order=1)
entropy = ee(state)
```
"""
struct EntanglementEntropy <: AbstractObservable
    cut::Int
    order::Int
    threshold::Float64
    
    function EntanglementEntropy(; cut::Int, order::Int=1, threshold::Float64=1e-16)
        cut >= 1 || throw(ArgumentError("EntanglementEntropy cut must be >= 1"))
        order >= 1 || throw(ArgumentError("EntanglementEntropy order must be >= 1"))
        threshold > 0 || throw(ArgumentError("EntanglementEntropy threshold must be > 0"))
        new(cut, order, threshold)
    end
end

# Callable struct interface
function (ee::EntanglementEntropy)(state)
    # Validate cut is in valid range
    1 <= ee.cut < state.L || throw(ArgumentError("cut must satisfy 1 <= cut < L"))
    
    # Convert physical cut to RAM ordering
    ram_cut = state.phy_ram[ee.cut]
    
    # Compute entropy using internal helper
    return _von_neumann_entropy(state.mps, ram_cut; n=ee.order, threshold=ee.threshold)
end

"""
    _von_neumann_entropy(mps::MPS, i::Int; n::Int=1, threshold::Float64=1e-16) -> Float64

Compute entanglement entropy at bond i of an MPS.

Arguments:
- mps: The MPS state
- i: The bond index (site index) where entropy is computed
- n: Order of entropy (1=von Neumann, 0=Hartley, n=Rényi)
- threshold: Minimum threshold for singular values to avoid log(0)

Returns:
- Entanglement entropy value

The function:
1. Orthogonalizes the MPS to site i
2. Performs SVD on the tensor to extract Schmidt values
3. Computes probabilities from Schmidt values (squared)
4. Returns entropy based on order:
   - n=1: von Neumann entropy S₁ = -Σ p log(p)
   - n=0: Hartley entropy S₀ = log(rank)
   - n≠1: Rényi entropy Sₙ = log(Σ pⁿ) / (1-n)
"""
function _von_neumann_entropy(
    mps::MPS,
    i::Int;
    n::Int=1,
    threshold::Float64=1e-16,
)
    # Orthogonalize MPS to site i
    mps_ = orthogonalize(mps, i)
    
    # Perform SVD on the link between site i and i+1
    # Extract singular values from the bond
    _, S = svd(mps_[i], (linkind(mps_, i),))
    
    # Get singular values and compute probabilities (squared for normalization)
    # Apply threshold to avoid numerical issues with log(0)
    singular_vals = diag(S)
    p = max.(singular_vals, threshold) .^ 2
    
    # Compute entropy based on order
    if n == 1
        # von Neumann entropy: S₁ = -Σ p log(p)
        return -sum(p .* log.(p))
    elseif n == 0
        # Hartley entropy: S₀ = log(rank)
        return log(length(p))
    else
        # Rényi entropy: Sₙ = log(Σ pⁿ) / (1-n)
        return log(sum(p .^ n)) / (1 - n)
    end
end
