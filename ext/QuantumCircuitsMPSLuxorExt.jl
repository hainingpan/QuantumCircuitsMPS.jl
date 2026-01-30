module QuantumCircuitsMPSLuxorExt

using Luxor
using QuantumCircuitsMPS
using QuantumCircuitsMPS: Circuit, expand_circuit, ExpandedOp

# Extension provides plot_circuit when Luxor is loaded
function QuantumCircuitsMPS.plot_circuit(circuit::Circuit; seed::Int=0, filename::String="circuit.svg")
    # Placeholder - Task 9 will implement
    error("plot_circuit implementation pending - see Task 9")
end

end # module
