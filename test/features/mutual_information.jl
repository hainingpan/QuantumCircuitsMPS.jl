# === MutualInformation observable — analytic cross-checks ===
#
# I(A:B) = S(A) + S(B) - S(A∪B), contiguous disjoint regions, all 3 backends.
#
# Analytic anchors (derived):
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
# BC note: all scenarios use bc=:open per the PBC-cut-semantics finding /
# established practice (MutualInformation itself is defined on physical
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

@testset "FEATURE MutualInformation" begin
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

# ======================================================================
# Real-valued `renyi_index` on MutualInformation: normalize-then-validate
# contract + Rényi passthrough into `_mi_entropy_from_probs`.
# ======================================================================
@testset "MutualInformation renyi_index: real-valued contract" begin
    # Same rejection set as EntanglementEntropy / EntropyProfile: `true` is a
    # `Real` whose Float64 normalization is 1.0 (would silently mean von
    # Neumann), and the two BigFloats are finite reals > 0 that normalize to
    # `Inf` / `0.0` — hence the contract is on the NORMALIZED value.
    for bad in (0, 0.0, -1, -0.5, Inf, NaN, true, false,
        BigFloat("1e400"), BigFloat("1e-400"))
        @test_throws ArgumentError MutualInformation(1, 2; renyi_index = bad)
    end

    mi = MutualInformation(1, 2; renyi_index = 1.5)
    @test mi.renyi_index == 1.5
    @test mi.renyi_index isa Float64
    @test MutualInformation(1, 2; renyi_index = 0.5).renyi_index == 0.5
    # Int input is normalized, not stored as an Int
    mi2 = MutualInformation(1, 2; renyi_index = 2)
    @test mi2.renyi_index == 2
    @test mi2.renyi_index isa Float64
    @test MutualInformation(1, 2;
        renyi_index = floatmax(Float64)).renyi_index == floatmax(Float64)
end

@testset "MutualInformation Rényi passthrough (Bell pair)" begin
    # Bell pair, A = {1}, B = {2}: both single-site spectra are flat {1/2,1/2}
    # and the joint spectrum is pure, so I_n = 2·log(2) for EVERY index. This
    # exercises `_mi_entropy_from_probs`'s scaled log-domain form (n = 0.5,
    # 1.5, floatmax) AND its widened von Neumann shunt (n = 1 ± 1e-8).
    for backend in (:mps, :statevector)
        st = backend === :mps ?
             SimulationState(L = 2, bc = :open, maxdim = 64,
            rng = RNGRegistry(gates_spacetime = 5, gates_realization = 6,
                born_measurement = 7)) :
             SimulationState(L = 2, bc = :open, backend = backend,
            rng = RNGRegistry(gates_spacetime = 5, gates_realization = 6,
                born_measurement = 7))
        initialize!(st, ProductState(binary_int = 0))
        apply!(st, Hadamard(), SingleSite(1))
        apply!(st, CNOT(), Sites([1, 2]))
        for n in (0.5, 1.5, floatmax(Float64), 1.0 - 1e-8, 1.0 + 1e-8)
            I = MutualInformation(1, 2; renyi_index = n)(st)
            @test isfinite(I)
            @test isapprox(I, 2 * log(2); atol = 1e-10)
        end
        # The shunt values must be EXACTLY the von Neumann value
        I1 = MutualInformation(1, 2; renyi_index = 1)(st)
        for n in (prevfloat(1.0), nextfloat(1.0), 1.0 - 1e-8, 1.0 + 1e-8)
            @test MutualInformation(1, 2; renyi_index = n)(st) == I1
        end
    end
end
