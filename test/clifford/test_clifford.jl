# test/clifford/test_clifford.jl
# Comprehensive unit tests for the Clifford (stabilizer-tableau) backend.
# Covers: initialization, all 9 gate types, gate validation/rejection,
# measurement/reset/feedback, all 3 observables (EntanglementEntropy,
# Magnetization, BornProbability), constructor validation, and full circuit
# integration.

using Test
using QuantumCircuitsMPS

const QCM = QuantumCircuitsMPS

# ── Helpers ─────────────────────────────────────────────────────────────────

"""Fresh Clifford |0...0⟩ state."""
function _cliff_state(L::Int; bc = :open,
        seeds = (gates_spacetime = 11, gates_realization = 22, born_measurement = 33))
    state = SimulationState(L = L, bc = bc, backend = :clifford,
        rng = RNGRegistry(; seeds...))
    initialize!(state, ProductState(binary_int = 0))
    return state
end

"""Fresh Clifford state initialised to `binary_int`."""
function _cliff_state_bin(L::Int, bin::Int; bc = :open,
        seeds = (gates_spacetime = 11, gates_realization = 22, born_measurement = 33))
    state = SimulationState(L = L, bc = bc, backend = :clifford,
        rng = RNGRegistry(; seeds...))
    initialize!(state, ProductState(binary_int = bin))
    return state
end

@testset "Clifford Backend" begin

    # ═══════════════════════════════════════════════════════════════════════
    # 1. Initialization
    # ═══════════════════════════════════════════════════════════════════════
    @testset "Initialization" begin
        @testset "ProductState(binary_int=0) → all |0⟩  (L=$L)" for L in [2, 4, 8]
            s = _cliff_state(L)
            for site in 1:L
                @test born_probability(s, site, 0) ≈ 1.0
                @test born_probability(s, site, 1) ≈ 0.0
            end
        end

        @testset "ProductState(binary_int) MSB convention (L=4)" begin
            # binary_int=5 → "0101" → sites 2,4 are |1⟩
            s = _cliff_state_bin(4, 5)
            @test born_probability(s, 1, 0) ≈ 1.0   # '0'
            @test born_probability(s, 2, 1) ≈ 1.0   # '1'
            @test born_probability(s, 3, 0) ≈ 1.0   # '0'
            @test born_probability(s, 4, 1) ≈ 1.0   # '1'

            # binary_int=8 → "1000" → site 1 is |1⟩, rest |0⟩
            s = _cliff_state_bin(4, 8)
            @test born_probability(s, 1, 1) ≈ 1.0
            for site in 2:4
                @test born_probability(s, site, 0) ≈ 1.0
            end

            # binary_int=15 → "1111" → all |1⟩
            s = _cliff_state_bin(4, 15)
            for site in 1:4
                @test born_probability(s, site, 1) ≈ 1.0
            end

            # binary_int=10 → "1010" → sites 1,3 are |1⟩
            s = _cliff_state_bin(4, 10)
            @test born_probability(s, 1, 1) ≈ 1.0
            @test born_probability(s, 2, 0) ≈ 1.0
            @test born_probability(s, 3, 1) ≈ 1.0
            @test born_probability(s, 4, 0) ≈ 1.0
        end

        @testset "ProductState(bitstring=...)" begin
            state = SimulationState(L = 4, bc = :open, backend = :clifford,
                rng = RNGRegistry(gates_spacetime = 1, gates_realization = 2, born_measurement = 3))
            initialize!(state, ProductState(bitstring = "1100"))
            @test born_probability(state, 1, 1) ≈ 1.0
            @test born_probability(state, 2, 1) ≈ 1.0
            @test born_probability(state, 3, 0) ≈ 1.0
            @test born_probability(state, 4, 0) ≈ 1.0
        end

        @testset "ProductState(spin_state=...) throws" begin
            state = SimulationState(L = 2, bc = :open, backend = :clifford,
                rng = RNGRegistry(gates_spacetime = 1, gates_realization = 2, born_measurement = 3))
            @test_throws ArgumentError initialize!(state, ProductState(spin_state = "Up"))
        end
    end

    # ═══════════════════════════════════════════════════════════════════════
    # 2. Gate Application (each of the 9 Clifford-compatible gates)
    # ═══════════════════════════════════════════════════════════════════════
    @testset "Gate Application" begin
        @testset "PauliX  (L=$L)" for L in [2, 4, 8]
            # X|0⟩ = |1⟩ on site 1
            s = _cliff_state(L)
            apply!(s, PauliX(), SingleSite(1))
            @test born_probability(s, 1, 1) ≈ 1.0
            @test born_probability(s, 1, 0) ≈ 0.0
            # other sites untouched
            for site in 2:L
                @test born_probability(s, site, 0) ≈ 1.0
            end
            # X again → back to |0⟩ (involution)
            apply!(s, PauliX(), SingleSite(1))
            @test born_probability(s, 1, 0) ≈ 1.0
        end

        @testset "PauliY" begin
            # Y|0⟩ = i|1⟩ → P(1)=1
            s = _cliff_state(2)
            apply!(s, PauliY(), SingleSite(1))
            @test born_probability(s, 1, 1) ≈ 1.0
            # Y again → back to |0⟩ (Y²=I up to global phase)
            apply!(s, PauliY(), SingleSite(1))
            @test born_probability(s, 1, 0) ≈ 1.0
        end

        @testset "PauliZ" begin
            # Z|0⟩ = |0⟩ (eigenstate)
            s = _cliff_state(2)
            apply!(s, PauliZ(), SingleSite(1))
            @test born_probability(s, 1, 0) ≈ 1.0
            # Z|1⟩ = -|1⟩ (phase only, still |1⟩ in measurement)
            s2 = _cliff_state_bin(2, 2)   # |10⟩
            apply!(s2, PauliZ(), SingleSite(1))
            @test born_probability(s2, 1, 1) ≈ 1.0
        end

        @testset "Hadamard  (L=$L)" for L in [2, 4]
            # H|0⟩ = |+⟩ → P(0)=P(1)=0.5
            s = _cliff_state(L)
            apply!(s, Hadamard(), SingleSite(1))
            @test born_probability(s, 1, 0) ≈ 0.5
            @test born_probability(s, 1, 1) ≈ 0.5
            # other sites untouched
            for site in 2:L
                @test born_probability(s, site, 0) ≈ 1.0
            end
            # H again → back to |0⟩
            apply!(s, Hadamard(), SingleSite(1))
            @test born_probability(s, 1, 0) ≈ 1.0
        end

        @testset "PhaseGate (S gate)" begin
            # H;S;S;H on |0⟩ → |1⟩  (S²=Z, HZH=X, X|0⟩=|1⟩)
            s = _cliff_state(2)
            apply!(s, Hadamard(), SingleSite(1))
            apply!(s, PhaseGate(), SingleSite(1))
            apply!(s, PhaseGate(), SingleSite(1))
            apply!(s, Hadamard(), SingleSite(1))
            @test born_probability(s, 1, 1) ≈ 1.0
            @test born_probability(s, 1, 0) ≈ 0.0

            # S on |0⟩ → |0⟩ (computational basis eigenstate)
            s2 = _cliff_state(2)
            apply!(s2, PhaseGate(), SingleSite(1))
            @test born_probability(s2, 1, 0) ≈ 1.0
        end

        @testset "CZ  (L=$L)" for L in [2, 4]
            # CZ|11⟩ = -|11⟩ (phase only → same measurement outcome)
            s = _cliff_state_bin(L, (1 << (L-1)) + (1 << (L-2)))  # sites 1,2 = |1⟩
            apply!(s, CZ(), AdjacentPair(1))
            @test born_probability(s, 1, 1) ≈ 1.0
            @test born_probability(s, 2, 1) ≈ 1.0

            # CZ|10⟩ = |10⟩ (no phase change when control XOR target = 0)
            s2 = _cliff_state_bin(L, 1 << (L-1))  # site 1 = |1⟩
            apply!(s2, CZ(), AdjacentPair(1))
            @test born_probability(s2, 1, 1) ≈ 1.0
            @test born_probability(s2, 2, 0) ≈ 1.0
        end

        @testset "CNOT  (L=$L)" for L in [2, 4]
            # CNOT|10⟩ = |11⟩ (control=1 ⇒ target flipped)
            s = _cliff_state_bin(L, 1 << (L-1))  # site 1 = |1⟩
            apply!(s, CNOT(), AdjacentPair(1))
            @test born_probability(s, 1, 1) ≈ 1.0
            @test born_probability(s, 2, 1) ≈ 1.0

            # CNOT|00⟩ = |00⟩ (control=0 ⇒ target unchanged)
            s2 = _cliff_state(L)
            apply!(s2, CNOT(), AdjacentPair(1))
            @test born_probability(s2, 1, 0) ≈ 1.0
            @test born_probability(s2, 2, 0) ≈ 1.0
        end

        @testset "SWAP  (L=$L)" for L in [2, 4]
            # SWAP|10⟩ = |01⟩
            s = _cliff_state_bin(L, 1 << (L-1))  # site 1 = |1⟩
            apply!(s, SWAP(), AdjacentPair(1))
            @test born_probability(s, 1, 0) ≈ 1.0
            @test born_probability(s, 2, 1) ≈ 1.0
        end
    end

    # ═══════════════════════════════════════════════════════════════════════
    # 3. RandomClifford
    # ═══════════════════════════════════════════════════════════════════════
    @testset "RandomClifford" begin
        @testset "applies without error (n=$n)" for n in [1, 2]
            s = _cliff_state(4; seeds = (
                gates_spacetime = 1, gates_realization = 42, born_measurement = 3))
            if n == 1
                apply!(s, RandomClifford(1), SingleSite(1))
            else
                apply!(s, RandomClifford(2), AdjacentPair(1))
            end
            # Probabilities still sum to 1 (state is valid)
            @test born_probability(s, 1, 0) + born_probability(s, 1, 1) ≈ 1.0
        end

        @testset "seed reproducibility" begin
            # Same seed → same born_probability distribution
            function run_random_clifford(seed)
                s = _cliff_state(4;
                    seeds = (gates_spacetime = 1, gates_realization = seed,
                        born_measurement = 3))
                apply!(s, RandomClifford(2), AdjacentPair(1))
                apply!(s, RandomClifford(2), AdjacentPair(3))
                return [born_probability(s, site, 0) for site in 1:4]
            end

            probs1 = run_random_clifford(42)
            probs2 = run_random_clifford(42)
            @test probs1 ≈ probs2 atol=0

            # Different seed → (almost certainly) different distribution
            probs3 = run_random_clifford(99)
            @test probs1 != probs3
        end
    end

    # ═══════════════════════════════════════════════════════════════════════
    # 4. Gate Validation (non-Clifford gates throw)
    # ═══════════════════════════════════════════════════════════════════════
    @testset "Gate Validation" begin
        s = _cliff_state(4)

        @testset "HaarRandom() throws" begin
            @test_throws ArgumentError apply!(s, HaarRandom(), AdjacentPair(1))
        end

        @testset "Rx(0.5) throws" begin
            @test_throws ArgumentError apply!(s, Rx(0.5), SingleSite(1))
        end

        @testset "Ry(0.5) throws" begin
            @test_throws ArgumentError apply!(s, Ry(0.5), SingleSite(1))
        end

        @testset "Rz(0.5) throws" begin
            @test_throws ArgumentError apply!(s, Rz(0.5), SingleSite(1))
        end

        @testset "MatrixGate throws" begin
            @test_throws ArgumentError apply!(s, MatrixGate([1.0 0.0; 0.0 1.0]), SingleSite(1))
        end

        @testset "Projection(0) throws" begin
            @test_throws ArgumentError apply!(s, Projection(0), SingleSite(1))
        end

        @testset "SpinSectorProjection throws" begin
            # SpinSectorProjection needs a projector matrix; use identity as dummy
            proj = SpinSectorProjection(Float64[1 0 0 0 0 0 0 0 0;
                                                0 1 0 0 0 0 0 0 0;
                                                0 0 1 0 0 0 0 0 0;
                                                0 0 0 1 0 0 0 0 0;
                                                0 0 0 0 1 0 0 0 0;
                                                0 0 0 0 0 1 0 0 0;
                                                0 0 0 0 0 0 1 0 0;
                                                0 0 0 0 0 0 0 1 0;
                                                0 0 0 0 0 0 0 0 1])
            @test_throws ArgumentError apply!(s, proj, AdjacentPair(1))
        end

        @testset "Error message is informative" begin
            try
                apply!(s, HaarRandom(), AdjacentPair(1))
            catch e
                @test e isa ArgumentError
                msg = e.msg
                @test occursin("Clifford backend only supports Clifford gates", msg)
                @test occursin("HaarRandom", msg)
                @test occursin("backend=:mps", msg)
            end
        end
    end

    # ═══════════════════════════════════════════════════════════════════════
    # 5. Measurement
    # ═══════════════════════════════════════════════════════════════════════
    @testset "Measurement" begin
        @testset "deterministic outcome on |0⟩" begin
            # Measure |0⟩ → always outcome 0
            for seed in 1:50
                s = _cliff_state(2;
                    seeds = (gates_spacetime = 1, gates_realization = 2,
                        born_measurement = seed))
                apply!(s, Measure(:Z), SingleSite(1))
                @test born_probability(s, 1, 0) ≈ 1.0
            end
        end

        @testset "deterministic outcome on |1⟩" begin
            # PauliX|0⟩ = |1⟩, Measure → always outcome 1
            for seed in 1:50
                s = _cliff_state(2;
                    seeds = (gates_spacetime = 1, gates_realization = 2,
                        born_measurement = seed))
                apply!(s, PauliX(), SingleSite(1))
                apply!(s, Measure(:Z), SingleSite(1))
                @test born_probability(s, 1, 1) ≈ 1.0
            end
        end

        @testset "50/50 on |+⟩ (Hadamard)" begin
            n_trials = 200
            n_zeros = 0
            for seed in 1:n_trials
                s = _cliff_state(2;
                    seeds = (gates_spacetime = 1, gates_realization = 2,
                        born_measurement = seed))
                apply!(s, Hadamard(), SingleSite(1))
                apply!(s, Measure(:Z), SingleSite(1))
                if born_probability(s, 1, 0) ≈ 1.0
                    n_zeros += 1
                end
            end
            freq = n_zeros / n_trials
            # Generous tolerance: binomial(200, 0.5) → expect ~0.5 ± ~0.035 (1σ)
            @test 0.35 < freq < 0.65
        end
    end

    # ═══════════════════════════════════════════════════════════════════════
    # 6. Reset
    # ═══════════════════════════════════════════════════════════════════════
    @testset "Reset" begin
        @testset "Reset on |1⟩ → |0⟩ deterministically" begin
            for seed in 1:50
                s = _cliff_state(2;
                    seeds = (gates_spacetime = 1, gates_realization = 2,
                        born_measurement = seed))
                apply!(s, PauliX(), SingleSite(1))
                # Now site 1 = |1⟩
                @test born_probability(s, 1, 1) ≈ 1.0
                apply!(s, Reset(), SingleSite(1))
                # After Reset: site 1 = |0⟩
                @test born_probability(s, 1, 0) ≈ 1.0
            end
        end

        @testset "Reset on |0⟩ stays |0⟩" begin
            s = _cliff_state(2)
            apply!(s, Reset(), SingleSite(1))
            @test born_probability(s, 1, 0) ≈ 1.0
        end
    end

    # ═══════════════════════════════════════════════════════════════════════
    # 7. Feedback (OnOutcome dispatch mechanism)
    # ═══════════════════════════════════════════════════════════════════════
    @testset "Feedback" begin
        @testset "OnOutcome(1 => PauliX()) on deterministic |1⟩" begin
            # Prepare |1⟩, measure, feedback should fire PauliX → back to |0⟩
            # This is exactly what Reset() does, but via the general feedback API
            for seed in 1:20
                s = _cliff_state(2;
                    seeds = (gates_spacetime = 1, gates_realization = 2,
                        born_measurement = seed))
                apply!(s, PauliX(), SingleSite(1))
                @test born_probability(s, 1, 1) ≈ 1.0
                # Measure with OnOutcome feedback
                apply!(s, Measure(:Z; feedback = OnOutcome(1 => PauliX())), SingleSite(1))
                # Outcome was 1 → PauliX fired → now |0⟩
                @test born_probability(s, 1, 0) ≈ 1.0
            end
        end

        @testset "OnOutcome does NOT fire on non-matching outcome" begin
            # Prepare |0⟩, measure → outcome 0, OnOutcome(1 => PauliX()) should NOT fire
            s = _cliff_state(2)
            apply!(s, Measure(:Z; feedback = OnOutcome(1 => PauliX())), SingleSite(1))
            # Outcome was 0, feedback skipped → still |0⟩
            @test born_probability(s, 1, 0) ≈ 1.0
        end

        @testset "Closure feedback" begin
            s = _cliff_state(2; seeds = (
                gates_spacetime = 1, gates_realization = 2, born_measurement = 1))
            apply!(s, PauliX(), SingleSite(1))
            # Closure: on any outcome, apply PauliX (flip) to measured site
            apply!(s,
                Measure(:Z;
                    feedback = (state, sites, outcome) -> apply!(state, PauliX(), SingleSite(sites[1]))),
                SingleSite(1))
            # Was |1⟩, measured as 1, closure applies X → |0⟩
            @test born_probability(s, 1, 0) ≈ 1.0
        end
    end

    # ═══════════════════════════════════════════════════════════════════════
    # 8. EntanglementEntropy
    # ═══════════════════════════════════════════════════════════════════════
    @testset "EntanglementEntropy" begin
        @testset "product state → 0.0  (L=$L)" for L in [2, 4, 8]
            s = _cliff_state(L)
            ee = EntanglementEntropy(cut = L÷2)
            @test ee(s) ≈ 0.0 atol=1e-12
        end

        @testset "Bell state → 1.0  (L=$L)" for L in [2, 4]
            # H on site 1 + CNOT on (1,2) → Bell pair (sites 1-2 entangled)
            s = _cliff_state(L)
            apply!(s, Hadamard(), SingleSite(1))
            apply!(s, CNOT(), AdjacentPair(1))
            ee = EntanglementEntropy(cut = 1)
            @test ee(s) ≈ 1.0 atol=1e-12
        end

        @testset "Bell state with base=exp(1) → ln(2)" begin
            s = _cliff_state(2)
            apply!(s, Hadamard(), SingleSite(1))
            apply!(s, CNOT(), AdjacentPair(1))
            ee = EntanglementEntropy(cut = 1, base = exp(1))
            @test ee(s) ≈ log(2) atol=1e-12
        end

        @testset "GHZ state → 1.0 for any nontrivial cut (L=4)" begin
            # H on site 1, CNOT chain: (1,2), (2,3), (3,4) → GHZ
            s = _cliff_state(4)
            apply!(s, Hadamard(), SingleSite(1))
            for i in 1:3
                apply!(s, CNOT(), AdjacentPair(i))
            end
            for cut in 1:3
                ee = EntanglementEntropy(cut = cut)
                @test ee(s) ≈ 1.0 atol=1e-12
            end
        end

        @testset "GHZ state (L=8) → 1.0 for any nontrivial cut" begin
            s = _cliff_state(8)
            apply!(s, Hadamard(), SingleSite(1))
            for i in 1:7
                apply!(s, CNOT(), AdjacentPair(i))
            end
            for cut in [1, 2, 4, 7]
                ee = EntanglementEntropy(cut = cut)
                @test ee(s) ≈ 1.0 atol=1e-12
            end
        end

        @testset "Renyi-index invariance for stabilizer states" begin
            # GHZ L=4, cut=2 — all Renyi indices give same value
            s = _cliff_state(4)
            apply!(s, Hadamard(), SingleSite(1))
            for i in 1:3
                apply!(s, CNOT(), AdjacentPair(i))
            end
            for n in [1, 2, 3, 5]
                ee = EntanglementEntropy(cut = 2, renyi_index = n)
                @test ee(s) ≈ 1.0 atol=1e-12
            end
        end
    end

    # ═══════════════════════════════════════════════════════════════════════
    # 9. Magnetization
    # ═══════════════════════════════════════════════════════════════════════
    @testset "Magnetization" begin
        @testset "|0...0⟩ → Mz=1.0  (L=$L)" for L in [2, 4, 8]
            s = _cliff_state(L)
            mz = Magnetization(:Z)
            @test mz(s) ≈ 1.0 atol=1e-12
        end

        @testset "|1...1⟩ → Mz=-1.0  (L=$L)" for L in [2, 4, 8]
            s = _cliff_state_bin(L, (1 << L) - 1)  # all ones
            mz = Magnetization(:Z)
            @test mz(s) ≈ -1.0 atol=1e-12
        end

        @testset "alternating bits → Mz=0.0 (L=4)" begin
            # binary_int=10 → "1010" → sites 1,3=|1⟩, sites 2,4=|0⟩
            s = _cliff_state_bin(4, 10)
            mz = Magnetization(:Z)
            @test mz(s) ≈ 0.0 atol=1e-12
        end

        @testset "alternating bits → Mz=0.0 (L=8)" begin
            # binary_int=170 → "10101010"
            s = _cliff_state_bin(8, 170)
            mz = Magnetization(:Z)
            @test mz(s) ≈ 0.0 atol=1e-12
        end

        @testset "Magnetization(:X) throws on Clifford" begin
            s = _cliff_state(2)
            @test_throws ArgumentError Magnetization(:X)(s)
        end
    end

    # ═══════════════════════════════════════════════════════════════════════
    # 10. BornProbability
    # ═══════════════════════════════════════════════════════════════════════
    @testset "BornProbability" begin
        @testset "product state  (L=$L)" for L in [2, 4, 8]
            s = _cliff_state(L)
            @test born_probability(s, 1, 0) ≈ 1.0
            @test born_probability(s, 1, 1) ≈ 0.0
        end

        @testset "Hadamard superposition" begin
            s = _cliff_state(4)
            apply!(s, Hadamard(), SingleSite(2))
            @test born_probability(s, 2, 0) ≈ 0.5
            @test born_probability(s, 2, 1) ≈ 0.5
            # Other sites untouched
            @test born_probability(s, 1, 0) ≈ 1.0
            @test born_probability(s, 3, 0) ≈ 1.0
        end

        @testset "non-destructive (repeated calls)" begin
            s = _cliff_state(2)
            apply!(s, Hadamard(), SingleSite(1))
            for _ in 1:5
                @test born_probability(s, 1, 0) ≈ 0.5
                @test born_probability(s, 1, 1) ≈ 0.5
            end
        end

        @testset "BornProbability observable in track!" begin
            s = _cliff_state(4)
            track!(s, :bp => BornProbability(1, 0))
            record!(s)
            @test s.observables[:bp][end] ≈ 1.0
            apply!(s, Hadamard(), SingleSite(1))
            record!(s)
            @test s.observables[:bp][end] ≈ 0.5
        end
    end

    # ═══════════════════════════════════════════════════════════════════════
    # 11. Constructor Validation
    # ═══════════════════════════════════════════════════════════════════════
    @testset "Constructor Validation" begin
        @testset "site_type=\"S=1\" throws" begin
            @test_throws ArgumentError SimulationState(
                L = 4, bc = :open, backend = :clifford, site_type = "S=1",
                rng = RNGRegistry(gates_spacetime = 1, gates_realization = 2, born_measurement = 3))
        end

        @testset "explicit local_dim=3 throws" begin
            @test_throws ArgumentError SimulationState(
                L = 4, bc = :open, backend = :clifford, site_type = "Qudit", local_dim = 3,
                rng = RNGRegistry(gates_spacetime = 1, gates_realization = 2, born_measurement = 3))
        end

        @testset "error message is informative" begin
            try
                SimulationState(L = 4, bc = :open, backend = :clifford, site_type = "S=1",
                    rng = RNGRegistry(gates_spacetime = 1, gates_realization = 2, born_measurement = 3))
            catch e
                @test e isa ArgumentError
                msg = e.msg
                @test occursin("Clifford backend only supports qubits", msg)
                @test occursin("local_dim=2", msg)
            end
        end
    end

    # ═══════════════════════════════════════════════════════════════════════
    # 12. Circuit Integration
    # ═══════════════════════════════════════════════════════════════════════
    @testset "Circuit Integration" begin
        @testset "full Clifford circuit (L=4)" begin
            L = 4
            n_steps = 5

            circuit = Circuit(L = L, bc = :open) do c
                # Layer of single-qubit Cliffords
                apply!(c, Hadamard(), SingleSite(1))
                apply!(c, PhaseGate(), SingleSite(2))
                apply!(c, PauliX(), SingleSite(3))
                # Two-qubit Clifford gates
                apply!(c, CNOT(), AdjacentPair(1))
                apply!(c, CZ(), AdjacentPair(2))
                apply!(c, SWAP(), AdjacentPair(3))
                # Stochastic measurement
                apply_with_prob!(c; outcomes = [
                    (probability = 0.3, gate = Measure(:Z), geometry = AllSites())
                ])
                record!(c, :entropy, :mz)
            end

            state = SimulationState(L = L, bc = :open, backend = :clifford,
                rng = RNGRegistry(gates_spacetime = 42, gates_realization = 7, born_measurement = 99))
            initialize!(state, ProductState(binary_int = 0))
            track!(state, :entropy => EntanglementEntropy(cut = L÷2))
            track!(state, :mz => Magnetization(:Z))

            simulate!(circuit, state; n_steps = n_steps, record_when = :marks)

            # Check observable arrays have expected length
            @test length(state.observables[:entropy]) == n_steps
            @test length(state.observables[:mz]) == n_steps

            # Entropy stays within valid bounds [0, min(cut, L-cut)]
            max_entropy = min(L÷2, L - L÷2)
            for ee_val in state.observables[:entropy]
                @test 0.0 <= ee_val <= max_entropy + 1e-10
            end

            # Magnetization stays within [-1, 1]
            for mz_val in state.observables[:mz]
                @test -1.0 - 1e-10 <= mz_val <= 1.0 + 1e-10
            end
        end

        @testset "RandomClifford bricklayer circuit (L=8)" begin
            L = 8
            n_steps = 3

            circuit = Circuit(L = L, bc = :open) do c
                apply!(c, RandomClifford(), Bricklayer(:odd))
                apply!(c, RandomClifford(), Bricklayer(:even))
                apply_with_prob!(c; outcomes = [
                    (probability = 0.2, gate = Measure(:Z), geometry = AllSites())
                ])
                record!(c, :entropy)
            end

            state = SimulationState(L = L, bc = :open, backend = :clifford,
                rng = RNGRegistry(gates_spacetime = 42, gates_realization = 7, born_measurement = 99))
            initialize!(state, ProductState(binary_int = 0))
            track!(state, :entropy => EntanglementEntropy(cut = L÷2))

            simulate!(circuit, state; n_steps = n_steps, record_when = :marks)

            @test length(state.observables[:entropy]) == n_steps
            max_entropy = min(L÷2, L - L÷2)
            for ee_val in state.observables[:entropy]
                @test 0.0 <= ee_val <= max_entropy + 1e-10
            end
        end

        @testset "Reset circuit (L=4)" begin
            L = 4
            circuit = Circuit(L = L, bc = :open) do c
                apply!(c, Hadamard(), SingleSite(1))
                apply!(c, CNOT(), AdjacentPair(1))
                apply!(c, Reset(), SingleSite(1))
                apply!(c, Reset(), SingleSite(2))
                record!(c, :mz)
            end

            state = SimulationState(L = L, bc = :open, backend = :clifford,
                rng = RNGRegistry(gates_spacetime = 1, gates_realization = 2, born_measurement = 42))
            initialize!(state, ProductState(binary_int = 0))
            track!(state, :mz => Magnetization(:Z))

            simulate!(circuit, state; n_steps = 1, record_when = :marks)

            # After Reset on sites 1 and 2, both should be |0⟩ → Mz = 1.0
            @test state.observables[:mz][end] ≈ 1.0 atol=1e-12
        end
    end
end  # top-level @testset
