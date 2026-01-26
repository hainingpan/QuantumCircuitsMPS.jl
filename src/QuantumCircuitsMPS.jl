module QuantumCircuitsMPS

include("Core/Core.jl")
include("Gates/Gates.jl")
include("Measurements/Measurements.jl")
include("Observables/Observables.jl")
include("Patterns/Patterns.jl")

using .Core
using .Gates
using .Measurements
using .Observables
using .Patterns

export AbstractGate,
       AbstractMeasurement,
       AbstractObservable,
       AbstractPattern,
       AbstractCircuit,
       SimulationState,
       with_state,
       current_state,
       simulate,
       HaarGate,
       SimplifiedGate,
       ZMeasurement,
       ZMeasure,
       measure!,
       control_step!,
       projection_checks!,
       MagnetizationZ,
       MagnetizationZiAll,
       EntanglementEntropy,
       Entropy,
       MaxBondDim,
       Bricklayer,
       StaircaseStep,
       bricklayer!,
       staircase_step!,
       forward

end
