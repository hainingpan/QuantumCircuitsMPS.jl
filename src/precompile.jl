# === Precompile workload (PrecompileTools) ===
#
# Everything inside `@compile_workload` runs once, at package-precompile time,
# and every method that gets compiled while it runs is saved into the package
# image. Without this, each fresh Julia session pays the JIT cost of the
# specialized gate/observable/`simulate!` methods on the first trajectory
# (tens of seconds for the MPS backend). With it, that cost is paid once per
# install/update instead.
#
# What is covered: one tiny trajectory per backend (L = 4–8, a few steps),
# built from the gates, geometries, observables, and recording modes of the
# four worked examples in `examples/` (Clifford MIPT, state-vector CIPT, MPS
# AKLT forced measurement, Gaussian DIII Majorana chain), plus the remaining
# public gates and observables, the feedback and event-log mechanisms, and
# the circuit expansion / ASCII printing helpers. Nothing here changes
# runtime behavior: the workload only drives the public API with fixed seeds,
# its results are discarded, and its RNG streams are local to the workload.
#
# Keep the sizes tiny — precompile time scales with how much code runs here,
# not with how much it compiles. Avoid anything that prints or warns: output
# during precompilation is surfaced to the user by Pkg.
#
# To skip this workload while developing (it adds a few minutes to each
# precompile of the package itself), set the PrecompileTools preference in a
# `LocalPreferences.toml` next to the root `Project.toml`:
#
#     [QuantumCircuitsMPS]
#     precompile_workload = false
#
# See CONTRIBUTING.md ("Skipping the precompile workload while developing").

@setup_workload begin
    @compile_workload begin
        # Fresh registry per state: every stream is seeded, so no backend ever
        # hits an unseeded (guarded) stream during the workload.
        rng(seed) = RNGRegistry(gates_spacetime = seed, born_measurement = seed,
            gates_realization = seed, state_init = seed)

        # --- Clifford backend: MIPT (examples/mipt_example.jl) ------------
        let L = 8
            c = Circuit(L = L, bc = :periodic, p = 0.2) do c
                apply!(c, RandomClifford(), Bricklayer(:even))
                apply_with_prob!(c;
                    outcomes = [(probability = c.params[:p], gate = Measure(:Z),
                        geometry = AllSites())])
                apply!(c, RandomClifford(), Bricklayer(:odd))
                apply_with_prob!(c;
                    outcomes = [(probability = c.params[:p], gate = Measure(:Z),
                        geometry = AllSites())])
            end
            st = SimulationState(L = L, bc = :periodic, backend = :clifford, rng = rng(1))
            initialize!(st, ProductState(binary_int = 0))
            track!(st, :S => EntanglementEntropy(cut = L ÷ 2))
            track!(st, :I => MutualInformation(1:1, 5:5; base = 2))
            simulate!(c, st; n_steps = 2, record_when = :final_only)
        end

        # --- State-vector backend: CIPT (examples/cipt_example.jl) --------
        let L = 4
            c = Circuit(L = L, bc = :periodic) do c
                apply_with_prob!(c;
                    outcomes = [
                        (probability = 0.5, gate = Reset(), geometry = StaircaseLeft(1)),
                        (probability = 0.5, gate = HaarRandom(),
                            geometry = StaircaseRight(1))])
            end
            for engine in (:builtin, :optimized)
                st = SimulationState(L = L, bc = :periodic, backend = :statevector,
                    engine = engine, rng = rng(1))
                initialize!(st, ProductState(binary_int = 0))
                track!(st, :Mz => Magnetization(:Z))
                track!(st, :I3 => TripartiteMutualInformation(1:1, 2:2, 3:3; base = 2))
                simulate!(c, st; n_steps = 4, record_when = :final_only)
            end
        end

        # --- MPS backend, spin-1: AKLT forced measurement -----------------
        # (examples/AKLT_forcedmeas.jl)
        let L = 8
            P = SpinSectorProjection(total_spin_projector(0) + total_spin_projector(1))
            c = Circuit(L = L, bc = :periodic) do c
                apply_with_prob!(c;
                    outcomes = [
                        (probability = 0.5, gate = P, geometry = StaircaseRight(1)),
                        (probability = 0.5, gate = P,
                            geometry = StaircaseRight(1; range = 2))])
            end
            st = SimulationState(L = L, bc = :periodic, site_type = "S=1", maxdim = 8,
                rng = rng(1))
            initialize!(st, ProductState(spin_state = "Z0"))
            track!(st, :nn => StringOrder(1, 5, order = 1))
            track!(st, :nnn => StringOrder(1, 5, order = 2))
            simulate!(c, st; n_steps = 4, record_when = every_n_steps(2))
        end

        # --- MPS backend, qubits: Haar + measurement (README example) -----
        let L = 4
            c = Circuit(L = L, bc = :periodic, p = 0.3) do c
                apply!(c, HaarRandom(), Bricklayer(:even))
                apply_with_prob!(c;
                    outcomes = [(probability = c.params[:p], gate = Measure(:Z),
                        geometry = AllSites())])
                record!(c, :S)
                apply!(c, HaarRandom(), Bricklayer(:odd))
                apply_with_prob!(c;
                    outcomes = [(probability = c.params[:p], gate = Measure(:Z),
                        geometry = AllSites())])
                record!(c, :S)
            end
            st = SimulationState(L = L, bc = :periodic, maxdim = 8, rng = rng(1))
            initialize!(st, ProductState(binary_int = 0))
            track!(st, :S => EntanglementEntropy(cut = L ÷ 2))
            simulate!(c, st; n_steps = 2, record_when = :marks)
        end

        # --- Gaussian backend: DIII Majorana chain ------------------------
        # (examples/gaussian_example.jl)
        let L = 8
            c = Circuit(L = L, bc = :periodic) do c
                apply_with_prob!(c;
                    outcomes = [
                        (probability = 0.5, gate = BondParity(),
                            geometry = Bricklayer(:odd)),
                        (probability = 0.5, gate = GaussianHaar(),
                            geometry = Bricklayer(:odd))])
                apply_with_prob!(c;
                    outcomes = [
                        (probability = 0.5, gate = BondParity(),
                            geometry = Bricklayer(:even)),
                        (probability = 0.5, gate = GaussianHaar(),
                            geometry = Bricklayer(:even))])
            end
            st = SimulationState(L = L, bc = :periodic, backend = :gaussian,
                site_type = "Majorana", rng = rng(1))
            initialize!(st, RandomGaussianState())
            track!(st, :S => EntanglementEntropy(cut = 2:5))
            track!(st, :I => MutualInformation(1:2, 5:6; base = 2))
            simulate!(c, st; n_steps = 2, record_when = :final_only)
        end

        # ==== Remaining public API, one small pass per backend ============

        # --- MPS + state vector, qubits, bc = :open -----------------------
        # Named gates, MatrixGate, Projection/Reset, feedback (OnOutcome and
        # callback forms), ProductGate, eager apply_with_prob!, the event
        # log, every observable the two backends share, eager record!, the
        # remaining `record_when` modes, and circuit expansion/printing.
        let L = 4
            X = [0 1; 1 0]
            feedback_cb = (s, sites, o) -> (o == 1 &&
                                            apply!(s, PauliX(), SingleSite(sites[1])))
            c = Circuit(L = L, bc = :open, p = 0.5) do c
                apply!(c, Hadamard(), AllSites())
                apply!(c, CNOT(), Bricklayer(:odd))
                apply!(c, CZ(), Bricklayer(:even))
                apply!(c, SWAP(), AdjacentPair(1))
                apply!(c, Rx(0.3), SingleSite(1))
                apply!(c, Ry(0.3), SingleSite(2))
                apply!(c, Rz(0.3), SingleSite(3))
                apply!(c, PhaseGate(), SingleSite(4))
                apply!(c, PauliY(), EachSite(2:3))
                apply!(c, PauliZ(), SingleSite(1))
                apply!(c, MatrixGate(X), SingleSite(2))
                apply!(c, MatrixGate(kron(X, X)), Sites(3:4))
                apply!(c, RandomClifford(), AdjacentPair(2))
                apply!(c, ProductGate(HaarRandom(), Bricklayer(:odd)))
                apply_with_prob!(c;
                    outcomes = [(probability = c.params[:p],
                        gate = Measure(:Z; feedback = OnOutcome(1 => PauliX())),
                        geometry = AllSites())])
                apply_with_prob!(c;
                    outcomes = [(probability = 0.5,
                        gate = Measure(:Z; feedback = feedback_cb), geometry = SingleSite(1))])
                apply!(c, Reset(), StaircaseRight(1))
                record!(c, :S)
            end
            buf = IOBuffer()
            print_circuit(c; n_steps = 2, gates_spacetime = 1, io = buf)
            print_circuit(buf, c; unicode = false)
            expand_circuit(c; n_steps = 2, seed = 1)
            expand_circuit_grouped(c; n_steps = 2, seed = 1)
            for (backend, engine) in ((:mps, :builtin), (:statevector, :builtin),
                (:statevector, :optimized))
                st = SimulationState(L = L, bc = :open, backend = backend, engine = engine,
                    maxdim = 8, log_events = true, rng = rng(2))
                backend == :mps && initialize!(st, RandomMPS(bond_dim = 2))
                backend == :statevector && initialize!(st, RandomStateVector())
                initialize!(st, ProductState(bitstring = "0101"))
                # Postselection on a certain outcome: never rejected.
                apply!(st, Projection(1), SingleSite(2))
                apply!(st, CNOT(), [1, 2])
                apply_with_prob!(st;
                    outcomes = [(
                        probability = 0.5, gate = Measure(:Z), geometry = AllSites())])
                track!(st, :S => EntanglementEntropy(cut = 2))
                # Region form of the entropy: state vector only (MPS rejects it).
                backend == :statevector &&
                    track!(st, :Sreg => EntanglementEntropy(cut = 1:2))
                track!(st, :Mz => Magnetization(:Z))
                track!(st, :p => BornProbability(1, 0))
                track!(st, :I => MutualInformation(1:1, 3:3; base = 2))
                track!(st, :I3 => TripartiteMutualInformation(1:1, 2:2, 3:3))
                track!(st, :prof => EntropyProfile())
                track!(st, :ZX => PauliString(1 => :Z, 2 => :X))
                track!(st, :C => Correlator(1 => :Z, 3 => :Z))
                track!(st, :dM => MagnetizationFluctuations(1:2; axis = :Z))
                track!(st, :DW => DomainWall(order = 1, i1_fn = () -> 1))
                track!(st, :p0 => s -> born_probability(s, 1, 0))
                backend == :mps && track!(st, :Mx => Magnetization(:X))
                record!(st)
                list_observables()
                simulate!(c, st; n_steps = 2, record_when = :marks)
                events(st)
                measurements(st)
            end
            c2 = Circuit(L = L, bc = :open) do c
                apply!(c, HaarRandom(), Bricklayer(:odd))
                apply!(c, Measure(:Z), AllSites())
            end
            for record_when in (:every_step, :every_gate, every_n_gates(2), every_n_steps(1))
                st = SimulationState(L = L, bc = :open, maxdim = 8, rng = rng(3))
                initialize!(st, ProductState(binary_int = 0))
                track!(st, :S => EntanglementEntropy(cut = 2))
                simulate!(c2, st; n_steps = 2, record_when = record_when)
            end
        end

        # --- MPS + state vector, spin-1: SpinSectorMeasurement, StringOrder
        let L = 6
            P = SpinSectorProjection(total_spin_projector(0) + total_spin_projector(1))
            c = Circuit(L = L, bc = :open) do c
                apply!(c, P, Bricklayer(:odd))
                apply!(c, Measure(:Z), SingleSite(1))
            end
            for backend in (:mps, :statevector)
                st = SimulationState(
                    L = L, bc = :open, backend = backend, site_type = "S=1",
                    maxdim = 8, rng = rng(4))
                initialize!(st, ProductState(spin_state = "Z0"))
                track!(st, :nn => StringOrder(1, 5, order = 1))
                track!(st, :nnn => StringOrder(1, 5, order = 2))
                simulate!(c, st; n_steps = 1, record_when = :final_only)
                # Born-sampled sector measurement (MPS only). The post-selecting
                # form follows a fresh P, so its sectors have probability one.
                if backend == :mps
                    apply!(st, SpinSectorMeasurement(), AdjacentPair(3))
                    apply!(st, P, AdjacentPair(1))
                    apply!(st, SpinSectorMeasurement([0, 1]), AdjacentPair(1))
                end
            end
        end

        # --- Clifford, bc = :open ----------------------------------------
        let L = 6
            c = Circuit(L = L, bc = :open) do c
                apply!(c, Hadamard(), AllSites())
                apply!(c, PhaseGate(), SingleSite(1))
                apply!(c, CNOT(), Bricklayer(:odd))
                apply!(c, CZ(), Bricklayer(:even))
                apply!(c, SWAP(), AdjacentPair(1))
                apply!(c, PauliX(), SingleSite(1))
                apply!(c, PauliY(), SingleSite(2))
                apply!(c, PauliZ(), SingleSite(3))
                apply!(c, ProductGate(RandomClifford(), Bricklayer(:odd)))
                apply_with_prob!(c;
                    outcomes = [(probability = 0.5,
                        gate = Measure(:Z; feedback = OnOutcome(1 => PauliX())),
                        geometry = AllSites())])
                apply!(c, Reset(), SingleSite(2))
            end
            st = SimulationState(L = L, bc = :open, backend = :clifford, log_events = true,
                rng = rng(5))
            initialize!(st, ProductState(binary_int = 0))
            apply!(st, Hadamard(), SingleSite(1))
            apply!(st, CNOT(), AdjacentPair(1))
            apply_with_prob!(st;
                outcomes = [(probability = 0.5, gate = Measure(:Z), geometry = AllSites())])
            track!(st, :S => EntanglementEntropy(cut = 3))
            track!(st, :Sreg => EntanglementEntropy(cut = 2:3))
            track!(st, :Mz => Magnetization(:Z))
            track!(st, :p => BornProbability(1, 0))
            track!(st, :I => MutualInformation(1:2, 4:5; base = 2))
            track!(st, :I3 => TripartiteMutualInformation(1:2, 3:4, 5:6; base = 2))
            track!(st, :prof => EntropyProfile())
            track!(st, :ZZ => PauliString(1 => :Z, 2 => :Z))
            track!(st, :C => Correlator(1 => :Z, 3 => :Z))
            track!(st, :dM => MagnetizationFluctuations(1:3; axis = :Z))
            record!(st)
            simulate!(c, st; n_steps = 2, record_when = :every_step)
            events(st)
            measurements(st)
        end

        # --- Gaussian, qubit granularity, bc = :open ---------------------
        let L = 6
            c = Circuit(L = L, bc = :open) do c
                apply!(c, ProductGate(GaussianHaar(), Bricklayer(:odd)))
                apply!(c, BondParity(), Bricklayer(:even))
                apply_with_prob!(c;
                    outcomes = [(
                        probability = 0.5, gate = Measure(:Z), geometry = AllSites())])
            end
            st = SimulationState(L = L, bc = :open, backend = :gaussian, log_events = true,
                rng = rng(6))
            initialize!(st, ProductState(binary_int = 0))
            apply!(st, GaussianHaar(), AdjacentPair(1))
            apply!(st, Measure(:Z), SingleSite(1))
            track!(st, :S => EntanglementEntropy(cut = 3))
            track!(st, :Mz => Magnetization(:Z))
            track!(st, :p => BornProbability(1, 0))
            track!(st, :I => MutualInformation(1:2, 4:5; base = 2))
            track!(st, :I3 => TripartiteMutualInformation(1:2, 3:4, 5:6; base = 2))
            track!(st, :prof => EntropyProfile())
            record!(st)
            simulate!(c, st; n_steps = 2, record_when = :every_step)
            events(st)
            measurements(st)
        end
    end
end
