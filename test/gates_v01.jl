# === Tests for v0.1 gates: HaarRandom(n), MatrixGate, Rx/Ry/Rz/Hadamard ===
#
# Conventions under test (API contract):
# - MatrixGate matrices use standard Kronecker ordering: U = kron(A, B) acts
#   with A on the FIRST site of the region; U[out, in] = ⟨out|U|in⟩.
# - Rotation convention: Rx(θ) = exp(-iθX/2), Ry(θ) = exp(-iθY/2),
#   Rz(θ) = exp(-iθZ/2).
# - HaarRandom(2) must be bit-identical (matrices AND RNG consumption) to the
#   historical two-site implementation (golden Case D depends on it).

using Test
using QuantumCircuitsMPS
using LinearAlgebra
using Random: MersenneTwister
using ITensors: siteinds, ITensor, prime, Index
import ITensorMPS

const QCM = QuantumCircuitsMPS
using QuantumCircuitsMPS: GateApplied  # internal since Task 14 (not in manifest)

# Helper: fresh |0...0⟩ qubit state
function _fresh_state(L::Int; seeds=(gates_spacetime=11, gates_realization=22, born_measurement=33))
    state = SimulationState(L=L, bc=:periodic, maxdim=64,
        rng=RNGRegistry(; seeds...))
    initialize!(state, ProductState(binary_int=0))
    return state
end

# Helper: reconstruct the N×N matrix stored in a MatrixGate-convention ITensor
# (primed = out with LAST site fastest). op built as
# ITensor(T, s_n', ..., s_1', s_n, ..., s_1).
function _matrixgate_op_to_matrix(op, sites, d)
    n = length(sites)
    ord = vcat([prime(s) for s in reverse(sites)], collect(reverse(sites)))
    A = Array(op, ord...)
    N = d^n
    return reshape(A, N, N)
end

@testset "gates_v01" begin

    # =====================================================================
    @testset "HaarRandom construction and support" begin
        @test QCM.support(HaarRandom()) == 2       # default unchanged
        @test HaarRandom().n == 2
        @test QCM.support(HaarRandom(1)) == 1
        @test QCM.support(HaarRandom(3)) == 3
        @test_throws ArgumentError HaarRandom(0)
        @test_throws ArgumentError HaarRandom(-1)
    end

    @testset "HaarRandom(2) bit-identical to legacy algorithm" begin
        seed = 20260703
        sites2 = siteinds("Qubit", 2)
        reg = RNGRegistry(gates_spacetime=1, gates_realization=seed, born_measurement=2)
        op = QCM.build_operator(HaarRandom(), sites2, 2; rng=reg)

        # Twin: verbatim reproduction of the pre-refactor algorithm
        rng_twin = MersenneTwister(seed)
        z = randn(rng_twin, 4, 4) + randn(rng_twin, 4, 4) * im
        Q, R = qr(z)
        Q = Matrix(Q)
        r_diag = diag(R)
        Lambda = Diagonal(r_diag ./ abs.(r_diag))
        U_ref = Q * Lambda
        U4_ref = reshape(U_ref, 2, 2, 2, 2)
        op_ref = ITensor(U4_ref, sites2[1], sites2[2], sites2[1]', sites2[2]')

        ord = (sites2[1], sites2[2], sites2[1]', sites2[2]')
        @test Array(op, ord...) == Array(op_ref, ord...)  # bitwise identical

        # RNG consumption identical: next draw from stream matches twin
        @test rand(get_rng(reg, :gates_realization)) == rand(rng_twin)
    end

    @testset "HaarRandom(n) unitarity, n = 1, 2, 3" begin
        for n in 1:3
            reg = RNGRegistry(gates_spacetime=1, gates_realization=100 + n, born_measurement=2)
            sitesn = siteinds("Qubit", n)
            N = 2^n
            op = if n == 1
                QCM.build_operator(HaarRandom(1), sitesn[1], 2; rng=reg)
            else
                QCM.build_operator(HaarRandom(n), sitesn, 2; rng=reg)
            end
            ord = if n == 1
                (sitesn[1], prime(sitesn[1]))
            else
                (sitesn..., prime.(sitesn)...)
            end
            M = reshape(Array(op, ord...), N, N)
            @test norm(M' * M - I) < 1e-12
        end
    end

    @testset "HaarRandom(n) support-mismatch errors" begin
        sites2 = siteinds("Qubit", 2)
        reg = RNGRegistry(gates_spacetime=1, gates_realization=5, born_measurement=2)
        @test_throws ArgumentError QCM.build_operator(HaarRandom(3), sites2, 2; rng=reg)
        @test_throws ArgumentError QCM.build_operator(HaarRandom(2), sites2[1], 2; rng=reg)
    end

    @testset "HaarRandom apply! end-to-end (norm preserved)" begin
        # n = 1 through the single-site engine path (SingleSite geometry)
        state = _fresh_state(4)
        apply!(state, HaarRandom(1), SingleSite(2))
        @test abs(ITensorMPS.norm(state.mps) - 1) < 1e-10

        # n = 3 through the Sites geometry path
        state = _fresh_state(4)
        apply!(state, HaarRandom(3), Sites(1:3))
        @test abs(ITensorMPS.norm(state.mps) - 1) < 1e-10
    end

    # =====================================================================
    @testset "MatrixGate construction / size inference" begin
        # qubit sizes: 2^n
        @test QCM.support(MatrixGate(Matrix{Float64}(I, 2, 2))) == 1
        @test MatrixGate(Matrix{Float64}(I, 2, 2)).d == 2
        @test QCM.support(MatrixGate(Matrix{Float64}(I, 4, 4))) == 2
        @test QCM.support(MatrixGate(Matrix{Float64}(I, 8, 8))) == 3
        # spin-1 sizes: 3^n with n >= 2
        g9 = MatrixGate(Matrix{Float64}(I, 9, 9))
        @test QCM.support(g9) == 2
        @test g9.d == 3
        @test QCM.support(MatrixGate(Matrix{Float64}(I, 27, 27))) == 3
        # rejected sizes
        @test_throws ArgumentError MatrixGate(rand(3, 3))   # single-site spin-1: not in v0.1
        @test_throws ArgumentError MatrixGate(rand(5, 5))
        @test_throws ArgumentError MatrixGate(rand(6, 6))
        @test_throws ArgumentError MatrixGate(rand(12, 12))
        @test_throws ArgumentError MatrixGate(rand(1, 1))
        @test_throws ArgumentError MatrixGate(rand(4, 2))   # non-square
    end

    @testset "MatrixGate kron convention: X ⊗ I flips FIRST site" begin
        X = [0.0 1.0; 1.0 0.0]
        I2 = Matrix{Float64}(I, 2, 2)
        state = _fresh_state(2)
        apply!(state, MatrixGate(kron(X, I2)), Sites(1:2))
        @test born_probability(state, 1, 1) ≈ 1.0 atol=1e-12
        @test born_probability(state, 2, 0) ≈ 1.0 atol=1e-12

        # and I ⊗ X flips the SECOND site
        state = _fresh_state(2)
        apply!(state, MatrixGate(kron(I2, X)), Sites(1:2))
        @test born_probability(state, 1, 0) ≈ 1.0 atol=1e-12
        @test born_probability(state, 2, 1) ≈ 1.0 atol=1e-12
    end

    @testset "MatrixGate random-unitary marginals match U columns" begin
        # ψ = U|00⟩ → P(site1 = b1) = Σ_{b2} |U[2 b1 + b2 + 1, 1]|²
        rng = MersenneTwister(7)
        z = randn(rng, 4, 4) + randn(rng, 4, 4) * im
        Q, R = qr(z)
        U = Matrix(Q) * Diagonal(diag(R) ./ abs.(diag(R)))
        state = _fresh_state(2)
        apply!(state, MatrixGate(U), Sites(1:2))
        col = U[:, 1]
        @test born_probability(state, 1, 0) ≈ abs2(col[1]) + abs2(col[2]) atol=1e-12
        @test born_probability(state, 1, 1) ≈ abs2(col[3]) + abs2(col[4]) atol=1e-12
        @test born_probability(state, 2, 0) ≈ abs2(col[1]) + abs2(col[3]) atol=1e-12
        @test born_probability(state, 2, 1) ≈ abs2(col[2]) + abs2(col[4]) atol=1e-12
        @test abs(ITensorMPS.norm(state.mps) - 1) < 1e-10
    end

    @testset "MatrixGate amplitude/phase conventions (no transpose/conjugate)" begin
        # Single-site: (-i X)|0⟩ = -i|1⟩ → ⟨10|ψ⟩ = -i (L=2, act on site 1)
        state = _fresh_state(2)
        ref = deepcopy(state)
        apply!(ref, PauliX(), SingleSite(1))          # ref = |10⟩
        apply!(state, MatrixGate([0 -im; -im 0]), SingleSite(1))
        amp = ITensorMPS.inner(ref.mps, state.mps)
        @test amp ≈ -im atol=1e-12

        # Two-site reshape path: S ⊗ I after H on site 1:
        # ψ = (S⊗I)(H⊗I)|00⟩ = (|00⟩ + i|10⟩)/√2 → ⟨10|ψ⟩ = i/√2
        S = [1.0+0im 0; 0 im]
        I2 = Matrix{ComplexF64}(I, 2, 2)
        state = _fresh_state(2)
        ref = deepcopy(state)
        apply!(ref, PauliX(), SingleSite(1))          # ref = |10⟩
        apply!(state, Hadamard(), SingleSite(1))
        apply!(state, MatrixGate(kron(S, I2)), Sites(1:2))
        amp = ITensorMPS.inner(ref.mps, state.mps)
        @test amp ≈ im / sqrt(2) atol=1e-12
    end

    @testset "MatrixGate local-dimension mismatch errors" begin
        g = MatrixGate(Matrix{Float64}(I, 4, 4))     # qubit gate
        s1_sites = siteinds("S=1", 2)
        @test_throws ArgumentError QCM.build_operator(g, s1_sites, 3)
        g9 = MatrixGate(Matrix{Float64}(I, 9, 9))    # spin-1 gate
        q_sites = siteinds("Qubit", 2)
        @test_throws ArgumentError QCM.build_operator(g9, q_sites, 2)
    end

    @testset "MatrixGate d=3 (spin-1) roundtrip" begin
        rng = MersenneTwister(13)
        z = randn(rng, 9, 9) + randn(rng, 9, 9) * im
        Q, R = qr(z)
        U9 = Matrix(Q) * Diagonal(diag(R) ./ abs.(diag(R)))
        g = MatrixGate(U9)
        s1_sites = siteinds("S=1", 2)
        op = QCM.build_operator(g, s1_sites, 3)
        M = _matrixgate_op_to_matrix(op, s1_sites, 3)
        @test M ≈ U9 atol=1e-14
        @test norm(M' * M - I) < 1e-12
    end

    @testset "MatrixGate support mismatch via Sites errors" begin
        g = MatrixGate(Matrix{Float64}(I, 4, 4))     # 2-site gate
        state = _fresh_state(4)
        @test_throws ArgumentError apply!(state, g, Sites(1:3))
    end

    # =====================================================================
    @testset "Named parametrized gates: exact matrices" begin
        θ = 1.234
        @test QCM.gate_matrix(Rx(θ)) == ComplexF64[cos(θ/2) -im*sin(θ/2); -im*sin(θ/2) cos(θ/2)]
        @test QCM.gate_matrix(Ry(θ)) == ComplexF64[cos(θ/2) -sin(θ/2); sin(θ/2) cos(θ/2)]
        @test QCM.gate_matrix(Rz(θ)) == ComplexF64[exp(-im*θ/2) 0; 0 exp(im*θ/2)]

        # Acceptance criterion: Rx(π) exact
        @test QCM.gate_matrix(Rx(π)) == [cos(π/2) -im*sin(π/2); -im*sin(π/2) cos(π/2)]

        # Hadamard² = I
        H = QCM.gate_matrix(Hadamard())
        @test H ≈ ComplexF64[1 1; 1 -1] ./ sqrt(2) atol=1e-15
        @test norm(H * H - I) < 1e-12
    end

    @testset "Named gates unitarity" begin
        for θ in (0.0, 0.3, π/2, float(π), 2.7, 2π)
            for g in (Rx(θ), Ry(θ), Rz(θ))
                M = QCM.gate_matrix(g)
                @test norm(M' * M - I) < 1e-12
            end
        end
        H = QCM.gate_matrix(Hadamard())
        @test norm(H' * H - I) < 1e-12
        for g in (Rx(0.7), Ry(0.7), Rz(0.7), Hadamard())
            @test QCM.support(g) == 1
        end
    end

    @testset "Named gates apply! semantics" begin
        θ = 0.83
        # Rx(θ)|0⟩ = cos(θ/2)|0⟩ - i sin(θ/2)|1⟩
        state = _fresh_state(2)
        ref = deepcopy(state)
        apply!(ref, PauliX(), SingleSite(1))
        apply!(state, Rx(θ), SingleSite(1))
        @test born_probability(state, 1, 0) ≈ cos(θ/2)^2 atol=1e-12
        amp = ITensorMPS.inner(ref.mps, state.mps)
        @test amp ≈ -im * sin(θ/2) atol=1e-12   # catches conjugate/transpose bugs

        # Ry(θ)|0⟩ = cos(θ/2)|0⟩ + sin(θ/2)|1⟩ (real amplitude)
        state = _fresh_state(2)
        ref = deepcopy(state)
        apply!(ref, PauliX(), SingleSite(1))
        apply!(state, Ry(θ), SingleSite(1))
        amp = ITensorMPS.inner(ref.mps, state.mps)
        @test amp ≈ sin(θ/2) atol=1e-12

        # Rz is diagonal: leaves |0⟩ populations alone
        state = _fresh_state(2)
        apply!(state, Rz(θ), SingleSite(1))
        @test born_probability(state, 1, 0) ≈ 1.0 atol=1e-12

        # Hadamard: |0⟩ → |+⟩; twice → |0⟩
        state = _fresh_state(2)
        apply!(state, Hadamard(), SingleSite(1))
        @test born_probability(state, 1, 0) ≈ 0.5 atol=1e-12
        apply!(state, Hadamard(), SingleSite(1))
        @test born_probability(state, 1, 0) ≈ 1.0 atol=1e-12

        # Qubit-only guard
        s1 = siteinds("S=1", 1)
        @test_throws ArgumentError QCM.build_operator(Rx(0.5), s1[1], 3)
    end

    # =====================================================================
    @testset "gate_label for new gates" begin
        @test QCM.gate_label(HaarRandom()) == "Haar"
        @test QCM.gate_label(HaarRandom(1)) == "Haar"
        @test QCM.gate_label(MatrixGate(Matrix{Float64}(I, 4, 4))) == "U"
        @test QCM.gate_label(Rx(0.1)) == "Rx"
        @test QCM.gate_label(Ry(0.1)) == "Ry"
        @test QCM.gate_label(Rz(0.1)) == "Rz"
        @test QCM.gate_label(Hadamard()) == "H"
    end

    @testset "exports" begin
        exported = names(QuantumCircuitsMPS)
        for sym in (:MatrixGate, :Rx, :Ry, :Rz, :Hadamard, :HaarRandom, :ProductGate)
            @test sym in exported
        end
    end

    # =====================================================================
    # ProductGate (Task 11): product layer as ONE gate (K = 1 in outcomes)
    # =====================================================================
    @testset "ProductGate (v0.1)" begin

        @testset "construction validation" begin
            pg = ProductGate(HaarRandom(), Bricklayer(:even))
            @test pg.inner isa HaarRandom
            @test pg.region_geometry isa Bricklayer
            # broadcast geometries accepted
            @test ProductGate(Measurement(:Z), AllSites()) isa ProductGate
            @test ProductGate(PauliX(), EachSite(2:5)) isa ProductGate
            # set geometries rejected
            @test_throws ArgumentError ProductGate(CZ(), Sites(1:4))
            @test_throws ArgumentError ProductGate(PauliX(), SingleSite(1))
            @test_throws ArgumentError ProductGate(CZ(), StaircaseRight(1))
            @test_throws ArgumentError ProductGate(CZ(), AdjacentPair(1))
            # nesting rejected
            inner_pg = ProductGate(CZ(), Bricklayer(:odd))
            @test_throws ArgumentError ProductGate(inner_pg, Bricklayer(:even))
            # no fixed support (L/bc-dependent)
            @test_throws ArgumentError QCM.support(pg)
        end

        @testset "gate_label" begin
            @test QCM.gate_label(ProductGate(HaarRandom(), Bricklayer(:even))) == "∏Haar"
            @test QCM.gate_label(ProductGate(CZ(), Bricklayer(:odd))) == "∏CZ"
        end

        @testset "canonical region" begin
            @test QCM._product_region(ProductGate(CZ(), Bricklayer(:even)), 8, :periodic) == collect(1:8)
            @test QCM._product_region(ProductGate(CZ(), Bricklayer(:even)), 8, :open) == collect(2:7)
            @test QCM._product_region(ProductGate(PauliX(), EachSite(2:5)), 8, :periodic) == collect(2:5)
        end

        @testset "eager apply! == element-wise inner application (RNG per element)" begin
            L = 8
            # state1: whole layer as ONE ProductGate
            state1 = _fresh_state(L)
            apply!(state1, ProductGate(HaarRandom(), Bricklayer(:even)))
            # state2: manual element-wise application with the SAME seeds
            state2 = _fresh_state(L)
            for elem in elements(Bricklayer(:even), L, :periodic)
                apply!(state2, HaarRandom(), elem)
            end
            @test abs(ITensorMPS.inner(state1.mps, state2.mps)) ≈ 1.0 atol=1e-12
            # MPS stays normalized; entanglement was generated
            @test ITensorMPS.norm(state1.mps) ≈ 1.0 atol=1e-10
            @test ITensorMPS.maxlinkdim(state1.mps) > 1
            # identical :gates_realization consumption (4 fresh Haars each)
            @test rand(get_rng(state1.rng_registry, :gates_realization)) ==
                  rand(get_rng(state2.rng_registry, :gates_realization))
        end

        @testset "region spelling: Sites(union) accepted, others error" begin
            L = 8
            pg = ProductGate(HaarRandom(), Bricklayer(:even))
            # explicit Sites(union) == omitted-geometry form
            sA = _fresh_state(L)
            apply!(sA, pg)
            sB = _fresh_state(L)
            apply!(sB, pg, Sites(1:L))
            @test abs(ITensorMPS.inner(sA.mps, sB.mps)) ≈ 1.0 atol=1e-12
            # wrong Sites region
            sC = _fresh_state(L)
            @test_throws ArgumentError apply!(sC, pg, Sites([1, 2]))
            # passing the broadcast geometry itself is the documented error case
            @test_throws ArgumentError apply!(sC, pg, Bricklayer(:even))
            @test_throws ArgumentError apply!(sC, pg, AllSites())
            # inner support mismatch (CZ needs 2 sites, AllSites elements have 1)
            @test_throws ArgumentError apply!(sC, ProductGate(CZ(), AllSites()))
        end

        @testset "builder forms (build-time validation)" begin
            L = 8
            pg = ProductGate(CZ(), Bricklayer(:odd))
            # omitted geometry records Sites(union)
            c = Circuit(L=L, bc=:periodic) do c
                apply!(c, pg)
            end
            @test length(c.operations) == 1
            @test c.operations[1].type == :deterministic
            @test c.operations[1].geometry isa Sites
            @test sort(c.operations[1].geometry.sites) == collect(1:L)
            # explicit Sites(union) accepted
            c2 = Circuit(L=L, bc=:periodic) do c
                apply!(c, pg, Sites(1:L))
            end
            @test c2.operations[1].geometry isa Sites
            # wrong region / wrong geometry error at BUILD time
            @test_throws ArgumentError Circuit(L=L, bc=:periodic) do c
                apply!(c, pg, Sites(1:4))
            end
            @test_throws ArgumentError Circuit(L=L, bc=:periodic) do c
                apply!(c, pg, Bricklayer(:odd))
            end
        end

        @testset "deterministic circuit: L/2 inner applications in canonical order" begin
            L = 8
            c = Circuit(L=L, bc=:periodic) do c
                apply!(c, ProductGate(CZ(), Bricklayer(:odd)))
            end
            state = SimulationState(L=L, bc=:periodic, maxdim=64,
                rng=RNGRegistry(gates_spacetime=1, gates_realization=2, born_measurement=3),
                log_events=true)
            initialize!(state, ProductState(binary_int=0))
            simulate!(c, state; n_steps=1)
            evs = [e for e in QCM.events(state) if e isa GateApplied]
            cz = [e for e in evs if e.gate_label == "CZ"]
            @test length(cz) == L ÷ 2
            @test [e.sites for e in cz] == elements(Bricklayer(:odd), L, :periodic)
            @test [e.element_idx for e in cz] == collect(1:L÷2)
            @test all(e.step == 1 for e in cz)
            # engine wrapper event carries the product label + union region
            wrap = [e for e in evs if e.gate_label == "∏CZ"]
            @test length(wrap) == 1
            @test sort(wrap[1].sites) == collect(1:L)
        end

        @testset "correlated layer choice: K=1, never mixed within a step" begin
            L = 8
            n_steps = 20
            c = Circuit(L=L, bc=:periodic) do c
                apply_with_prob!(c; outcomes=[
                    (probability=0.5, gate=ProductGate(HaarRandom(), Bricklayer(:even)),
                     geometry=Sites(1:L)),
                    (probability=0.5, gate=ProductGate(CZ(), Bricklayer(:even)),
                     geometry=Sites(1:L)),
                ])
            end
            # the whole product is ONE element (K = 1): one coin per step
            @test expected_draws(c, n_steps) == n_steps
            seed = 42
            state = SimulationState(L=L, bc=:periodic, maxdim=64,
                rng=RNGRegistry(gates_spacetime=seed, gates_realization=2, born_measurement=3),
                log_events=true)
            initialize!(state, ProductState(binary_int=0))
            simulate!(c, state; n_steps=n_steps)
            evs = [e for e in QCM.events(state) if e isa GateApplied]
            saw_haar_step = false
            saw_cz_step = false
            for s in 1:n_steps
                labels = Set(e.gate_label for e in evs if e.step == s)
                # per step: ALL-Haar or ALL-CZ, never mixed
                @test labels == Set(["Haar", "∏Haar"]) || labels == Set(["CZ", "∏CZ"])
                inner_evs = [e for e in evs if e.step == s && e.gate_label in ("Haar", "CZ")]
                @test length(inner_evs) == L ÷ 2   # full layer each step (Σp = 1)
                saw_haar_step |= ("Haar" in labels)
                saw_cz_step |= ("CZ" in labels)
            end
            # with seed=42 both branches occur within 20 steps
            @test saw_haar_step && saw_cz_step
            # fixed-draw contract: exactly n_steps coins from :gates_spacetime
            twin = MersenneTwister(seed)
            for _ in 1:n_steps
                rand(twin)
            end
            @test rand(get_rng(state.rng_registry, :gates_spacetime)) == rand(twin)
        end

        @testset "measurement inner gate (Born sampling per element)" begin
            L = 4
            state = SimulationState(L=L, bc=:periodic, maxdim=64,
                rng=RNGRegistry(gates_spacetime=1, gates_realization=2, born_measurement=3),
                log_events=true)
            initialize!(state, ProductState(binary_int=0))
            apply!(state, Hadamard(), SingleSite(1))
            pg = ProductGate(Measurement(:Z), AllSites())
            @test QCM.is_measurement(pg)   # trait delegates to inner
            apply!(state, pg)
            @test length(QCM.measurements(state)) == L   # one Born sample per site
            @test ITensorMPS.norm(state.mps) ≈ 1.0 atol=1e-10
        end

        @testset "compute_sites for Sites (engine set-outcome path)" begin
            @test QCM.compute_sites(Sites([2, 3]), 1, 8, :periodic) == [2, 3]
            @test QCM.compute_sites(Sites(1:4), 7, 8, :open) == collect(1:4)   # step-independent
            @test_throws ArgumentError QCM.compute_sites(Sites([9]), 1, 8, :periodic)
        end
    end

end
