# test/features/pauli_string.jl
# ═══════════════════════════════════════════════════════════════════════════
# T24 FEATURE: PauliString expectation observable — all 3 backends
# ═══════════════════════════════════════════════════════════════════════════
#
# Analytic anchors (derived, not guessed):
#   Bell |Φ⁺⟩ = (|00⟩+|11⟩)/√2:
#     ⟨Z₁Z₂⟩ = ½[(+1)(+1) + (−1)(−1)] = +1;  ⟨X₁X₂⟩ = +1 (X⊗X swaps branches);
#     ⟨Y₁Y₂⟩ = −1;  ⟨Z₁⟩ = ½[+1 + (−1)] = 0
#   GHZ(4) |GHZ⟩ = (|0000⟩+|1111⟩)/√2:
#     Z⊗Z⊗Z⊗Z|0000⟩ = (+1)⁴|0000⟩, Z⊗Z⊗Z⊗Z|1111⟩ = (−1)⁴|1111⟩
#       ⇒ ⟨Z₁Z₂Z₃Z₄⟩ = ½(1+1) = +1
#     ⟨Z₁Z₂⟩ = ½[(+1)² + (−1)²] = +1;  ⟨Z₁⟩ = 0
#     X⊗X⊗X⊗X maps |0000⟩↔|1111⟩ ⇒ ⟨X₁X₂X₃X₄⟩ = ½(1+1) = +1
#
# Sign convention pinned against Magnetization: ⟨Zᵢ⟩ = +1 on |0⟩, −1 on |1⟩.

using Test
using QuantumCircuitsMPS

# Prefixed helpers (runtests.jl includes all test files into one shared scope)
function _ps_state(backend; L, bc = :open, kwargs...)
    bk = backend == :mps ? (maxdim = 64,) : (backend = backend,)
    state = SimulationState(; L = L, bc = bc, bk..., kwargs...,
        rng = RNGRegistry(gates_spacetime = 42, gates_realization = 7,
            born_measurement = 99))
    return state
end

_PS_BACKENDS = (:mps, :statevector, :clifford)
_ps_tol(backend) = backend == :mps ? 1e-10 : 1e-12

@testset "PauliString observable (T24)" begin
    @testset "constructor validation" begin
        @test PauliString(1 => :Z) isa PauliString
        @test PauliString(3 => :X, 1 => :Y).sites == [1, 3]    # canonical site order
        @test PauliString(3 => :X, 1 => :Y).paulis == [:Y, :X]
        @test_throws ArgumentError PauliString()                 # empty
        @test_throws ArgumentError PauliString(1 => :Q)          # bad pauli
        @test_throws ArgumentError PauliString(1 => :I)          # identity by omission only
        @test_throws ArgumentError PauliString(0 => :Z)          # non-positive site
        @test_throws ArgumentError PauliString(-2 => :X)
        @test_throws ArgumentError PauliString(1 => :Z, 1 => :X) # duplicate site
    end

    @testset "evaluation-time validation" begin
        for backend in _PS_BACKENDS
            state = _ps_state(backend; L = 4)
            initialize!(state, ProductState(binary_int = 0))
            @test_throws ArgumentError PauliString(99 => :Z)(state)  # out of range
        end
        # S=1 site type → clean qubit-only rejection (roadmap: spin-S strings)
        s1 = SimulationState(L = 4, bc = :open, site_type = "S=1", maxdim = 16,
            rng = RNGRegistry(gates_spacetime = 1, gates_realization = 2,
                born_measurement = 3))
        initialize!(s1, ProductState(spin_state = "Z0"))
        err = try
            PauliString(1 => :Z)(s1)
            nothing
        catch e
            e
        end
        @test err isa ArgumentError
        @test occursin("qubit-only", err.msg)
        @test occursin("roadmap", err.msg)
    end

    @testset "product states: ⟨Zᵢ⟩ = ±1, matches Magnetization convention" begin
        L = 4
        for backend in _PS_BACKENDS
            tol = _ps_tol(backend)
            # |0000⟩: every ⟨Zᵢ⟩ = +1; ⟨Z₁Z₂Z₃Z₄⟩ = +1; ⟨Xᵢ⟩ = 0
            s0 = _ps_state(backend; L = L)
            initialize!(s0, ProductState(binary_int = 0))
            for i in 1:L
                @test PauliString(i => :Z)(s0) ≈ 1.0 atol=tol
                @test PauliString(i => :X)(s0) ≈ 0.0 atol=tol
                @test PauliString(i => :Y)(s0) ≈ 0.0 atol=tol
            end
            @test PauliString((i => :Z for i in 1:L)...)(s0) ≈ 1.0 atol=tol

            # |1111⟩: every ⟨Zᵢ⟩ = −1; ⟨ZZZZ⟩ = (−1)⁴ = +1
            s1 = _ps_state(backend; L = L)
            initialize!(s1, ProductState(binary_int = 2^L - 1))
            for i in 1:L
                @test PauliString(i => :Z)(s1) ≈ -1.0 atol=tol
            end
            @test PauliString((i => :Z for i in 1:L)...)(s1) ≈ 1.0 atol=tol

            # Generic bit pattern: (1/L)Σᵢ⟨Zᵢ⟩ must equal Magnetization(:Z)
            # (convention-free cross-check of the per-site sign convention)
            sm = _ps_state(backend; L = L)
            initialize!(sm, ProductState(binary_int = 0b0110))
            avg_z = sum(PauliString(i => :Z)(sm) for i in 1:L) / L
            @test avg_z ≈ Magnetization(:Z)(sm) atol=tol
        end
    end

    @testset "Bell state: ⟨Z₁Z₂⟩=1, ⟨X₁X₂⟩=1, ⟨Y₁Y₂⟩=−1, ⟨Z₁⟩=0" begin
        for backend in _PS_BACKENDS
            tol = _ps_tol(backend)
            state = _ps_state(backend; L = 2)
            initialize!(state, ProductState(binary_int = 0))
            apply!(state, Hadamard(), SingleSite(1))
            apply!(state, CNOT(), Sites([1, 2]))
            @test PauliString(1 => :Z, 2 => :Z)(state) ≈ 1.0 atol=tol
            @test PauliString(1 => :X, 2 => :X)(state) ≈ 1.0 atol=tol
            @test PauliString(1 => :Y, 2 => :Y)(state) ≈ -1.0 atol=tol
            @test PauliString(1 => :Z)(state) ≈ 0.0 atol=tol
            @test PauliString(2 => :Z)(state) ≈ 0.0 atol=tol
        end
    end

    @testset "GHZ(4): derived analytic values" begin
        for backend in _PS_BACKENDS
            tol = _ps_tol(backend)
            state = _ps_state(backend; L = 4)
            initialize!(state, ProductState(binary_int = 0))
            apply!(state, Hadamard(), SingleSite(1))
            apply!(state, CNOT(), Sites([1, 2]))
            apply!(state, CNOT(), Sites([2, 3]))
            apply!(state, CNOT(), Sites([3, 4]))
            # ⟨ZZZZ⟩ = ½[(+1)⁴ + (−1)⁴] = +1 (derivation in file header)
            @test PauliString(1 => :Z, 2 => :Z, 3 => :Z, 4 => :Z)(state) ≈ 1.0 atol=tol
            @test PauliString(1 => :X, 2 => :X, 3 => :X, 4 => :X)(state) ≈ 1.0 atol=tol
            @test PauliString(1 => :Z, 2 => :Z)(state) ≈ 1.0 atol=tol
            @test PauliString(1 => :Z, 4 => :Z)(state) ≈ 1.0 atol=tol
            @test PauliString(1 => :Z)(state) ≈ 0.0 atol=tol
            # odd # of Z's on GHZ: ⟨Z₁Z₂Z₃⟩ = ½[(+1)³ + (−1)³] = 0
            @test PauliString(1 => :Z, 2 => :Z, 3 => :Z)(state) ≈ 0.0 atol=tol
        end
    end

    @testset "3-backend agreement on Clifford-reachable states (±1e-12)" begin
        L = 4
        strings = [
            PauliString(1 => :Z),
            PauliString(2 => :X),
            PauliString(3 => :Y),
            PauliString(1 => :Z, 3 => :Z),
            PauliString(1 => :X, 2 => :X),
            PauliString(2 => :Y, 3 => :Y),
            PauliString(1 => :X, 2 => :Y, 3 => :Z, 4 => :Z),
            PauliString(1 => :Z, 2 => :Z, 3 => :Z, 4 => :Z)
        ]
        vals = Dict{Symbol, Vector{Float64}}()
        for backend in _PS_BACKENDS
            state = _ps_state(backend; L = L)
            initialize!(state, ProductState(binary_int = 0))
            # Fixed (deterministic) Clifford circuit — identical state everywhere
            apply!(state, Hadamard(), SingleSite(1))
            apply!(state, PhaseGate(), SingleSite(1))
            apply!(state, CNOT(), Sites([1, 2]))
            apply!(state, Hadamard(), SingleSite(3))
            apply!(state, CZ(), Sites([2, 3]))
            apply!(state, CNOT(), Sites([3, 4]))
            apply!(state, PhaseGate(), SingleSite(4))
            apply!(state, Hadamard(), SingleSite(2))
            vals[backend] = [ps(state) for ps in strings]
        end
        @test vals[:statevector] ≈ vals[:clifford] atol=1e-12
        @test vals[:mps] ≈ vals[:statevector] atol=1e-12
    end

    @testset "MPS vs SV agreement on Haar states (±1e-10)" begin
        L = 6
        strings = [
            PauliString(1 => :Z),
            PauliString(3 => :X),
            PauliString(2 => :Z, 5 => :Z),
            PauliString(1 => :X, 4 => :Y),
            PauliString(1 => :Y, 2 => :Y, 3 => :Y),
            PauliString(2 => :X, 3 => :Z, 4 => :X, 6 => :Z)
        ]
        vals = Dict{Symbol, Vector{Float64}}()
        for backend in (:mps, :statevector)
            bk = backend == :mps ? (maxdim = 256,) : (backend = backend,)
            state = SimulationState(; L = L, bc = :open, bk...,
                rng = RNGRegistry(gates_spacetime = 11, gates_realization = 13,
                    born_measurement = 17))
            initialize!(state, ProductState(binary_int = 0))
            for _ in 1:3
                apply!(state, HaarRandom(), Bricklayer(:odd))
                apply!(state, HaarRandom(), Bricklayer(:even))
            end
            vals[backend] = [ps(state) for ps in strings]
        end
        @test vals[:mps] ≈ vals[:statevector] atol=1e-10
        # Haar-state expectations are generically non-trivial — guard against
        # a silently-identity implementation returning all zeros/ones
        @test any(v -> 1e-3 < abs(v) < 1 - 1e-3, vals[:statevector])
    end

    @testset "track!/record! integration in simulate!" begin
        for backend in _PS_BACKENDS
            circuit = if backend == :clifford
                Circuit(L = 4, bc = :open) do c
                    apply!(c, RandomClifford(2), Bricklayer(:odd))
                    apply!(c, RandomClifford(2), Bricklayer(:even))
                end
            else
                Circuit(L = 4, bc = :open) do c
                    apply!(c, HaarRandom(), Bricklayer(:odd))
                    apply!(c, HaarRandom(), Bricklayer(:even))
                end
            end
            state = _ps_state(backend; L = 4)
            initialize!(state, ProductState(binary_int = 0))
            track!(state, :zz => PauliString(1 => :Z, 2 => :Z))
            track!(state, :xyz => PauliString(1 => :X, 2 => :Y, 3 => :Z))
            simulate!(circuit, state; n_steps = 5, record_when = :every_step)
            for name in (:zz, :xyz)
                vals = state.observables[name]
                @test vals isa Vector{Float64}
                @test length(vals) == 5
                @test all(v -> -1 - 1e-9 <= v <= 1 + 1e-9, vals)
            end
        end
    end
end
