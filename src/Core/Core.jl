module Core

include("types.jl")
include("context.jl")

export AbstractGate,
       AbstractMeasurement,
       AbstractObservable,
       AbstractPattern,
       AbstractCircuit,
       SimulationState,
       with_state,
       current_state,
       simulate,
       forward

end
