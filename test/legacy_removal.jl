# === Task 14: legacy API removal — migration stubs + export surface ===
# Contract under test: docs/api_surface_v0.1.md (KEEP + ADD + REMOVE tables).
# Removed entry points must NOT vanish silently (UndefVarError) — each remains
# defined in the module as an unexported stub throwing a migration error.

using Test
using QuantumCircuitsMPS

@testset "Legacy API removal (v0.1.0, Task 14)" begin
    @testset "EXPORTS: surface == manifest KEEP + ADD (docs/api_surface_v0.1.md)" begin
        # KEEP table (v0.4.0 surface: CT.jl-parity internal exports removed,
        # Measurement removed, born_probability kept as public)
        keep = [
            :SimulationState, :initialize!, :ProductState, :RandomMPS,
            :RNGRegistry, :get_rng,
            :AbstractGate, :PauliX, :PauliY, :PauliZ, :Projection, :HaarRandom,
            :Reset, :CZ,  # :Measurement removed in v0.4.0 (use Measure)
            :total_spin_projector, :verify_spin_projectors,
            :SpinSectorProjection, :SpinSectorMeasurement,
            :AbstractGeometry, :SingleSite, :AdjacentPair, :Bricklayer, :AllSites,
            :StaircaseLeft, :StaircaseRight, :Pointer, :move!,
            :AbstractObservable, :DomainWall, :BornProbability,
            :EntanglementEntropy, :StringOrder, :Magnetization,
            :track!, :record!, :list_observables,
            :apply!, :apply_with_prob!,
            :Circuit, :expand_circuit, :expand_circuit_grouped, :simulate!,
            :ExpandedOp, :RecordingContext, :every_n_gates, :every_n_steps,
            :print_circuit, :plot_circuit,
            # v0.4.0: the 11 CT.jl-parity internal exports (advance!, get_sites,
            # current_position, reset!, compute_site_staircase_right,
            # compute_site_staircase_left, compute_pair_staircase,
            # apply_op_internal!, compute_basis_mapping, physical_to_ram,
            # ram_to_physical) were UN-exported — use qualified
            # QuantumCircuitsMPS.<name>. born_probability was promoted to a
            # public Observables export (kept):
            :born_probability
        ]
        # ADD table (record!(::CircuitBuilder) is a method of record!, no new name)
        add = [
            :EachSite, :Sites, :Measure, :OnOutcome, :MatrixGate,
            :Rx, :Ry, :Rz, :Hadamard, :ProductGate,
            :events, :measurements, :expected_draws,
            :CNOT, :PhaseGate, :SWAP, :RandomClifford,  # Clifford backend gates (Task 11)
            :RandomStateVector,  # v0.4.0 (T13): SV random-init exported alongside RandomMPS
            :PauliString,  # v0.4.0 (T24): Pauli-string expectation observable (all 3 backends)
            :MutualInformation,  # v0.4.0 (T25): I(A:B) = S(A)+S(B)-S(A∪B) (all 3 backends)
            # v0.4.0 (T38): composed common observables (all 3 backends)
            :Correlator, :EntropyProfile, :TripartiteMutualInformation,
            :MagnetizationFluctuations
        ]
        # Geometry contract helpers documented in the KEEP table's
        # AbstractGeometry row ("Gains canonical elements(geo, L, bc),
        # element_count, is_broadcast trait") — exported by Task 3.
        geometry_contract = [:elements, :element_count, :is_broadcast]

        expected = Set(vcat(keep, add, geometry_contract))
        actual = Set(names(QuantumCircuitsMPS))
        delete!(actual, :QuantumCircuitsMPS)  # module name itself (Task 2 gotcha)

        extra = sort!(collect(setdiff(actual, expected)))
        missing_ = sort!(collect(setdiff(expected, actual)))
        @test isempty(extra) || error("Exports beyond manifest KEEP+ADD: $extra")
        @test isempty(missing_) ||
              error("Manifest KEEP+ADD symbols not exported: $missing_")
        @test length(actual) == 76

        # REMOVE-table symbols must not be exported
        removed = (:simulate, :simulate_circuits, :run_circuit!, :CircuitSimulation,
            :with_state, :current_state, :record_every, :record_at_circuits,
            :record_always, :get_state, :get_observables, :circuits_run)
        for name in removed
            @test !(name in actual)
        end
    end
end
