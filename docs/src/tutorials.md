# Tutorials

Four Jupyter notebooks in [`examples/`](https://github.com/hainingpan/QuantumCircuitsMPS.jl/tree/dev/examples) walk through full research workflows end-to-end, re-executed top-to-bottom against the v0.4.0 API:

| Notebook | Topic |
|---|---|
| [`mipt_example.ipynb`](https://github.com/hainingpan/QuantumCircuitsMPS.jl/blob/dev/examples/mipt_example.ipynb) | Measurement-Induced Phase Transition: entanglement entropy vs. measurement rate `p`, full sweep |
| [`cipt_example.ipynb`](https://github.com/hainingpan/QuantumCircuitsMPS.jl/blob/dev/examples/cipt_example.ipynb) | Control-Induced Phase Transition: staircase Reset/Haar competition, writes `cipt_Mz_data.csv` |
| [`cipt_fss.ipynb`](https://github.com/hainingpan/QuantumCircuitsMPS.jl/blob/dev/examples/cipt_fss.ipynb) | Finite-size scaling analysis of the CIPT transition (Python notebook — pandas + `fss`, consumes the CSV from `cipt_example.ipynb`) |
| [`AKLT_forcedmeas.ipynb`](https://github.com/hainingpan/QuantumCircuitsMPS.jl/blob/dev/examples/AKLT_forcedmeas.ipynb) | AKLT ground-state preparation via forced spin-sector projection, including NNN support |

The three quick-start snippets below are the condensed, standalone versions of the Julia notebooks (`mipt_example`, `cipt_example`, `AKLT_forcedmeas`) — enough to run end-to-end in a REPL without opening Jupyter. See the [State Vector Backend](@ref) and [Clifford Backend](@ref) pages for the equivalent snippets on those two backends.

## MIPT Example: Measurement-Induced Phase Transition

```julia
using QuantumCircuitsMPS

# System parameters
L = 12                  # 12 qubits
p = 0.15               # Measurement probability (near critical point)
n_steps = 50           # Time evolution steps

# Haar random unitaries + stochastic measurements; record! marks snapshot points
circuit = Circuit(L=L, bc=:periodic) do c
    # Even gates → measure → odd gates → measure per timestep
    apply!(c, HaarRandom(), Bricklayer(:even))
    apply_with_prob!(c; outcomes=[
        (probability=p, gate=Measure(:Z), geometry=AllSites())
    ])
    record!(c, :entropy)
    apply!(c, HaarRandom(), Bricklayer(:odd))
    apply_with_prob!(c; outcomes=[
        (probability=p, gate=Measure(:Z), geometry=AllSites())
    ])
    record!(c, :entropy)
end

# Initialize state and track entanglement entropy
state = SimulationState(
    L=L, bc=:periodic, maxdim=64,
    rng=RNGRegistry(gates_spacetime=42, born_measurement=1, gates_realization=2)
)
initialize!(state, ProductState(binary_int=0))
track!(state, :entropy => EntanglementEntropy(; cut=L÷2))

# record_when=:marks fires at each record!(c, ...) marker, twice per step
simulate!(circuit, state; n_steps=n_steps, record_when=:marks)

# Extract entropy trajectory
entropies = state.observables[:entropy]
println("Final entropy: $(entropies[end])")

# See examples/mipt_example.ipynb for the full tutorial
```

**Physics**: The competition between entangling Haar gates and disentangling measurements creates a phase transition at critical measurement rate p_c ≈ 0.16. Below p_c, the system exhibits volume-law entanglement; above p_c, area-law entanglement emerges.

## CIPT Example: Control-Induced Phase Transition

```julia
using QuantumCircuitsMPS

# System parameters
L = 8                   # Number of qubits
p_ctrl = 0.5            # Control probability (critical point p_c ≈ 0.5)
n_steps = 2 * L^2       # Timesteps (staircase sweeps)

# Build circuit: each step, a coin flip applies Reset (moving left) or Haar (moving right)
left = StaircaseLeft(1)
right = StaircaseRight(1)

circuit = Circuit(L=L, bc=:periodic, p_ctrl=p_ctrl) do c
    apply_with_prob!(c; outcomes=[
        (probability=c.params[:p_ctrl], gate=Reset(), geometry=left),
        (probability=1-c.params[:p_ctrl], gate=HaarRandom(), geometry=right)
    ])
end

# Initialize state and track magnetization Mz = (1/L) Σᵢ ⟨Zᵢ⟩
state = SimulationState(L=L, bc=:periodic, maxdim=64,
    rng=RNGRegistry(gates_spacetime=42, born_measurement=1, gates_realization=2))
initialize!(state, ProductState(binary_int=0))
track!(state, :Mz => Magnetization(:Z))

# Run simulation
simulate!(circuit, state; n_steps=n_steps, record_when=:every_gate)

mz_vals = state.observables[:Mz]
println("Final Mz: $(mz_vals[end])")

# See examples/cipt_example.ipynb for the full tutorial
```

**Physics**: The competition between Reset gates (which project qubits to |0⟩) and Haar random unitaries (which entangle qubits) drives a phase transition at p_c ≈ 0.5. In the reset-dominated phase (p_ctrl > 0.5), the magnetization Mz → +1 as qubits are repeatedly reset to |0⟩. In the unitary-dominated phase (p_ctrl < 0.5), Mz → 0 as random unitaries scramble the state. The staircase geometries sweep in opposite directions, creating the spatial competition that drives the transition.

`Reset()` above is sugar: it's exactly `Measure(:Z; feedback=OnOutcome(1 => PauliX()))` (measure, then flip back to |0⟩ if the outcome was 1) — see [Feedback & Custom Gates](@ref) below for the general form, which lets you swap the flip for any gate, or for an arbitrary closure.

## AKLT Example: Forced Measurement Protocol

```julia
using QuantumCircuitsMPS

# System parameters
L = 12                    # Chain length
bc = :periodic            # Boundary conditions
p_nn = 1.0               # Pure NN projections (set to 0.0 for NNN)

# Create spin projection gate (projects out S=2 quintet sector)
P0, P1 = total_spin_projector(0), total_spin_projector(1)
proj_gate = SpinSectorProjection(P0 + P1)

# Build circuit: apply projections to all NN pairs
circuit = Circuit(L=L, bc=bc) do c
    apply_with_prob!(c; outcomes=[
        (probability=p_nn, gate=proj_gate, geometry=Bricklayer(:nn)),
        (probability=1-p_nn, gate=proj_gate, geometry=Bricklayer(:nnn))
    ])
end

# Initialize state and track observables
state = SimulationState(L=L, bc=bc, site_type="S=1", maxdim=128,
    rng=RNGRegistry(gates_spacetime=42, gates_realization=2, born_measurement=3))
initialize!(state, ProductState(spin_state="Z0"))

track!(state, :entropy => EntanglementEntropy(cut=L÷2, renyi_index=1, base=2))
track!(state, :string_order => StringOrder(1, L÷2+1, order=1))

# Run L layers of projections
simulate!(circuit, state; n_steps=L, record_when=:every_step)

# Results: NN AKLT converges to S ≈ 2.0, |SO| ≈ 0.444
println("Entropy: $(state.observables[:entropy][end])")
println("|String Order|: $(abs(state.observables[:string_order][end]))")

# See examples/AKLT_forcedmeas.ipynb for the full tutorial with NNN support
```

**Physics**: The AKLT (Affleck-Kennedy-Lieb-Tasaki) state is a paradigmatic example of symmetry-protected topological order. By projecting out the S=2 quintet sector from adjacent spin-1 pairs, the protocol converges to the AKLT ground state characterized by string order parameter |O| ≈ 4/9. See [Arbitrary Spin-S Support](@ref) for running the same protocol at higher spin.

## Feedback & Custom Gates

Measurement feedback, arbitrary unitaries, and correlated layers are all first-class:

```julia
using QuantumCircuitsMPS

# --- 1. Closure feedback: adaptive random-unitary response ---
L = 6
circuit = Circuit(L=L, bc=:open) do c
    apply!(c, HaarRandom(), Bricklayer(:odd))
    apply_with_prob!(c; outcomes=[
        (probability=1.0,
         gate=Measure(:Z; feedback=(state, sites, outcome) ->
             outcome == 1 && apply!(state, HaarRandom(1), SingleSite(sites[1]))),
         geometry=EachSite(2:L-1))
    ])
end

state = SimulationState(L=L, bc=:open, maxdim=32,
    rng=RNGRegistry(gates_spacetime=7, gates_realization=8, born_measurement=9, state_init=1),
    log_events=true)
initialize!(state, ProductState(binary_int=0))
simulate!(circuit, state; n_steps=3)
n_outcomes = length(QuantumCircuitsMPS.measurements(state))
println("Feedback circuit ran 3 steps, $(n_outcomes) measurement outcomes logged")

# --- 2. MatrixGate: any hand-supplied unitary as a gate ---
state2 = SimulationState(L=2, bc=:open, maxdim=16,
    rng=RNGRegistry(gates_spacetime=1, gates_realization=2, born_measurement=3))
initialize!(state2, ProductState(binary_int=0))
apply!(state2, MatrixGate([0.0 1.0; 1.0 0.0]), SingleSite(1))
println("MatrixGate(X) flipped site 1: P(site1=1) = $(born_probability(state2, 1, 1))")

# --- 3. ProductGate: ONE coin governs an entire correlated layer ---
pg_haar = ProductGate(HaarRandom(), Bricklayer(:even))
state3 = SimulationState(L=4, bc=:open, maxdim=16,
    rng=RNGRegistry(gates_spacetime=1, gates_realization=2, born_measurement=3))
initialize!(state3, ProductState(binary_int=0))
track!(state3, :entropy => EntanglementEntropy(; cut=2))
apply!(state3, pg_haar)  # geometry omitted — fills in Sites(union) automatically
record!(state3)
println("ProductGate layer applied: entropy = $(state3.observables[:entropy][end])")
```

## See Also

- [Custom Observables](@ref) — the `track!`/callable-struct contract for writing your own trackers, with worked examples
- [Design Philosophy](@ref) — the Unified Stochastic Rule and Broadcast-vs-Set geometry vocabulary used throughout these examples
- [API Reference](@ref) — full listing of every gate, geometry, and observable
