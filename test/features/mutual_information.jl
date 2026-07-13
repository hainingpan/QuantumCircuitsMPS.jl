# === T25: MutualInformation observable — analytic cross-checks ===
#
# I(A:B) = S(A) + S(B) - S(A∪B), contiguous disjoint regions, all 3 backends.
#
# Analytic anchors (derived, see .sisyphus/notepads/v04-findings.md T25 entry):
#   - Product state: every RDM is a pure product projector ⇒ I = 0.
#   - Bell on (1,2), A={1}, B={2}: S(A)=S(B)=log2; A∪B={1,2} is PURE
#     (unentangled from the rest) ⇒ S(A∪B)=0 ⇒ I = 2·log2. (General rule:
#     pure global state with B = complement(A) ⇒ I = 2S(A).)
#   - GHZ(4) = (|0000⟩+|1111⟩)/√2, A={1}, B={4}:
#       ρ_A = ρ_B = ½(|0⟩⟨0|+|1⟩⟨1⟩)          ⇒ S(A) = S(B) = log2
#       ρ_{14} = ½(|00⟩⟨00|+|11⟩⟨11|)          ⇒ S(A∪B) = log2
#         (cross terms vanish: the traced middle sites ⟨00|11⟩ = 0)
#       ⇒ I = log2 + log2 − log2 = log2.
#   - Stabilizer states have flat entanglement spectra ⇒ every renyi_index
#     gives the same I on Bell/GHZ states (checked with renyi_index=2).
#
# BC note: all scenarios use bc=:open per T6's PBC-cut-semantics finding /
# T11's established practice (MutualInformation itself is defined on physical
# sites and is PBC-safe by construction, but open BC keeps cross-backend
# comparisons free of the folded-MPS confound).

using Test
using QuantumCircuitsMPS

function _mi_state(backend::Symbol, L::Int; maxdim = 64)
    state = SimulationState(L = L, bc = :open, backend = backend,
        maxdim = maxdim,
        rng = RNGRegistry(gates_spacetime = 11, gates_realization = 12,
            born_measurement = 13))
    initialize!(state, ProductState(binary_int = 0))
    return state
end

# Deterministic entangling Clifford circuit (identical unitaries on every
# backend — no RNG stream involved), used for cross-backend agreement.
function _mi_scrambled_state(backend::Symbol, L::Int)
    state = _mi_state(backend, L)
    for i in 1:L
        apply!(state, Hadamard(), SingleSite(i))
    end
    for pass in 1:2
        for i in 1:(L - 1)
            apply!(state, CNOT(), Sites([i, i + 1]))
        end
        apply!(state, PhaseGate(), SingleSite(1 + (pass % L)))
        apply!(state, CZ(), Sites([1, 2]))
    end
    return state
end

@testset "FEATURE MutualInformation (T25)" begin
    @testset "(a) product state: I = 0 on all backends" begin
        for backend in (:mps, :statevector, :clifford)
            state = _mi_state(backend, 6)
            apply!(state, PauliX(), SingleSite(2))  # |010000⟩ — still product
            @test abs(MutualInformation(1:2, 4:5)(state)) < 1e-12
            @test abs(MutualInformation(1, 6)(state)) < 1e-12
        end
    end

    @testset "(b) Bell endpoints A={1}, B={2}: I = 2log2" begin
        for backend in (:mps, :statevector, :clifford)
            state = _mi_state(backend, 4)
            apply!(state, Hadamard(), SingleSite(1))
            apply!(state, CNOT(), Sites([1, 2]))     # Bell on (1,2), |00⟩ on (3,4)
            tol = backend === :mps ? 1e-8 : 1e-12
            I = MutualInformation([1], [2])(state)
            @test isapprox(I, 2 * log(2); atol = tol)
            # base=2 → bits; pure-global-state rule I = 2S(A) with B = complement
            @test isapprox(MutualInformation(1, 2; base = 2)(state), 2.0; atol = tol)
            # Bell has a flat spectrum ⇒ Rényi-2 combination gives the same value
            @test isapprox(MutualInformation(1, 2; renyi_index = 2)(state),
                2 * log(2); atol = tol)
            # Far, unentangled pair: I = 0
            @test abs(MutualInformation(3, 4)(state)) < (backend === :mps ? 1e-10 : 1e-12)
        end
    end

    @testset "(c) GHZ(4) A={1}, B={4}: I = log2 (derived)" begin
        for backend in (:mps, :statevector, :clifford)
            state = _mi_state(backend, 4)
            apply!(state, Hadamard(), SingleSite(1))
            apply!(state, CNOT(), Sites([1, 2]))
            apply!(state, CNOT(), Sites([2, 3]))
            apply!(state, CNOT(), Sites([3, 4]))     # GHZ(4)
            tol = backend === :mps ? 1e-8 : 1e-12
            @test isapprox(MutualInformation(1, 4)(state), log(2); atol = tol)
            # flat GHZ spectrum ⇒ Rényi-2 identical
            @test isapprox(MutualInformation(1, 4; renyi_index = 2)(state),
                log(2); atol = tol)
            # two-site blocks: A={1,2}, B={3,4} are complements of a pure state
            # with S(A) = log2 ⇒ I = 2log2
            @test isapprox(MutualInformation(1:2, 3:4)(state), 2 * log(2); atol = tol)
        end
    end

    @testset "(d) cross-backend agreement on a scrambled Clifford state" begin
        L = 6
        mps_s = _mi_scrambled_state(:mps, L)
        sv_s = _mi_scrambled_state(:statevector, L)
        cl_s = _mi_scrambled_state(:clifford, L)
        for (A, B) in ((1:1, 6:6), (1:2, 4:5), (2:3, 5:6), (1:1, 3:4))
            for renyi in (1, 2)
                mi = MutualInformation(A, B; renyi_index = renyi)
                I_sv = mi(sv_s)
                @test isapprox(mi(mps_s), I_sv; atol = 1e-8)      # MPS vs SV
                @test isapprox(mi(cl_s), I_sv; atol = 1e-12)      # Clifford vs SV
            end
        end
    end

    @testset "(e) validation: overlap / non-contiguity / bounds / size guard" begin
        # overlapping regions → ArgumentError mentioning "disjoint"
        err = try
            MutualInformation(1:3, 3:5)
            nothing
        catch e
            e
        end
        @test err isa ArgumentError
        @test occursin("disjoint", err.msg)
        @test_throws ArgumentError MutualInformation(2, 2)

        # non-contiguous individual region: constructible (the Gaussian
        # backend supports arbitrary subsets) but REJECTED at evaluation
        # time on the MPS/state-vector/Clifford backends
        mi_nc = MutualInformation([1, 3], [5])
        @test mi_nc isa MutualInformation
        for backend in (:mps, :statevector, :clifford)
            nc_err = try
                mi_nc(_mi_state(backend, 6))
                nothing
            catch e
                e
            end
            @test nc_err isa ArgumentError
            @test occursin("CONTIGUOUS", nc_err.msg)
        end
        @test_throws ArgumentError MutualInformation([1], [3, 5])(_mi_state(:mps, 6))
        # empty / non-positive
        @test_throws ArgumentError MutualInformation(Int[], [2])
        @test_throws ArgumentError MutualInformation(0:1, 3:4)
        # bad keywords
        @test_throws ArgumentError MutualInformation(1, 3; renyi_index = 0)
        @test_throws ArgumentError MutualInformation(1, 3; base = -1)
        # adjacent-but-disjoint is fine
        @test MutualInformation(1:2, 3:4) isa MutualInformation

        # out-of-range region at evaluation time
        state = _mi_state(:statevector, 4)
        @test_throws ArgumentError MutualInformation(1, 6)(state)

        # MPS size guard: d^(|A|+|B|) > 256 → informative ArgumentError
        big = _mi_state(:mps, 12)
        guard_err = try
            MutualInformation(1:5, 7:11)(big)   # |A|+|B| = 10 qubits
            nothing
        catch e
            e
        end
        @test guard_err isa ArgumentError
        @test occursin("d^(|A|+|B|)", guard_err.msg)
        @test occursin("statevector", guard_err.msg)
        # same regions fine on the SV backend (no guard needed at L=12)
        sv12 = _mi_state(:statevector, 12)
        @test abs(MutualInformation(1:5, 7:11)(sv12)) < 1e-12  # product state
    end

    @testset "track!/record! integration" begin
        state = _mi_state(:mps, 4)
        apply!(state, Hadamard(), SingleSite(1))
        apply!(state, CNOT(), Sites([1, 2]))
        track!(state, :I12 => MutualInformation(1, 2))
        record!(state)
        @test isapprox(state.observables[:I12][end], 2 * log(2); atol = 1e-8)
        @test "MutualInformation" in list_observables()
    end
end
