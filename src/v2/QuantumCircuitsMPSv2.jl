module QuantumCircuitsMPSv2

using ITensors
using ITensorMPS
using Random
using LinearAlgebra

# Core
include("Core/basis.jl")
include("Core/rng.jl")  # Task 2

# State
include("State/State.jl")
include("State/initialization.jl")

# Gates (Task 3)
include("Gates/Gates.jl")

# Geometry (Task 5)
include("Geometry/Geometry.jl")

# Core apply! (after Gates and Geometry)
include("Core/apply.jl")  # Task 5

# Observables (Task 6)
include("Observables/Observables.jl")

# API (Task 7)
include("API/imperative.jl")
include("API/functional.jl")
include("API/context.jl")
include("API/probabilistic.jl")

# Exports
export SimulationState, initialize!
export ProductState, RandomMPS
export compute_basis_mapping, physical_to_ram, ram_to_physical
export RNGRegistry, get_rng
export AbstractGate, support
export PauliX, PauliY, PauliZ, Projection
export HaarRandom, CZ, Reset
export build_operator
export AbstractObservable, DomainWall, BornProbability
export track!, record!, born_probability
# Geometry (Task 5)
export AbstractGeometry, get_sites
export SingleSite, AdjacentPair, Bricklayer, AllSites
export StaircaseLeft, StaircaseRight, current_position
export apply!
# API (Task 7)
export simulate, with_state, current_state, apply_with_prob!

end # module
