"""
Circuit types and execution for lazy-mode API.

Provides:
- Circuit: Lazy representation of symbolic operations
- expand_circuit: Expands symbolic operations to concrete operations
- simulate!: Executes circuit with chosen simulation style
"""

# Circuit types and internal operation representation
include("types.jl")

# CircuitBuilder and do-block API
include("builder.jl")

# Circuit expansion (symbolic → concrete)
include("expand.jl")

# Circuit executor
# include("execute.jl")  # Task 8
