```@meta
CurrentModule = QuantumCircuitsMPS
```

# Circuit

The lazy-mode `do`-block circuit builder, its expansion into a flat
operation list, and the eager/lazy gate-application entry points.

```@docs
apply!
apply_with_prob!
Circuit
expand_circuit
expand_circuit_grouped
simulate!
ExpandedOp
RecordingContext
every_n_gates
every_n_steps
print_circuit
plot_circuit
```
