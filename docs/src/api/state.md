```@meta
CurrentModule = QuantumCircuitsMPS
```

# States and Backends

## State

Construction, initialization, and the opt-in event log.

```@docs
SimulationState
initialize!
ProductState
RandomMPS
RandomStateVector
RandomGaussianState
events
measurements
```

## Backends

Backend-payload structs are internal (`MPSBackend`, `StateVectorBackend`,
`CliffordBackend` are accessed only via `state.backend` + duck typing, never
exported). `GaussianBackend` is a deliberate exception, exported so
`state.backend isa GaussianBackend` works with a plain `using
QuantumCircuitsMPS`. See the [Gaussian Backend](@ref) page for usage and the
[Backend Interface Contract](@ref) for the full struct/method contract.

```@docs
GaussianBackend
```
