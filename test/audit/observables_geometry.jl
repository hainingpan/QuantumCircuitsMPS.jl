# === AUDIT: Observables (Magnetization, StringOrder, DomainWall) + Geometry semantics ===
#
# Task 9 of the v0.4.0 physics audit. Analytic cross-checks reviewed against:
#   src/Observables/{magnetization,string_order,domain_wall}.jl (MPS)
#   src/StateVector/{magnetization,string_order,domain_wall}.jl  (SV)
#   src/Clifford/magnetization.jl                                (Clifford)
#   src/Geometry/{elements,static,compute_sites,staircase}.jl
#
# What was verified (and by which testset):
# (a) "Magnetization sign convention" — Mz(|0…0⟩)=+1, Mz(|1…1⟩)=−1, Mz(|+⟩^L)=0
#     ±1e-12, agreeing across MPS/SV/Clifford. Sign convention: |0⟩ ↔ ⟨Z⟩=+1.
# (b) "AKLT string order" — quantitative |O¹|≈4/9 on the NN AKLT state (L=12
#     PBC, README recipe) on BOTH the MPS and SV backends; |O²|≈(4/9)² on the
#     NNN AKLT state (Bricklayer(:nnn) projections → two decoupled chains) on
#     both backends; order=2 constructor requires j ≥ i+4.
#     NOTE: on the *NN* AKLT state, |O²| ≈ 0.008 (NOT (4/9)²) — the O²
#     formula is specific to the NNN construction, exactly as the README's
#     StringOrder table says.
# (c) "DomainWall analytic counts" — domain-wall product states give exact
#     integer-weighted counts, cyclic wrap from i1 correct, superposition case
#     gives the Born-weighted average; MPS vs SV agree.
# (d) "Geometry enumeration" — Bricklayer L=12 PBC enumeration equals the
#     README parity table VERBATIM for all 8 parities; EachSite-vs-Sites
#     broadcast/set semantics; odd-L (L=5) PBC behavior pinned (see below).
# (e) "Axis rejection" — SV/Clifford Magnetization cleanly reject :X/:Y with
#     ArgumentError (no silent mis-computation).
#
# FINDINGS captured here as @test_broken / pinned behavior:
# - Clifford StringOrder/DomainWall CRASH with a raw field access error
#   ("type CliffordBackend has no field mps" / "... no field sites") because
#   they fall through to the MPS-typed generic methods
#   (src/Observables/string_order.jl, src/Observables/domain_wall.jl).
#   Pinned as @test_broken expecting the eventual clean ArgumentError — T14
#   fixes the rejection and flips these to @test.
# - Magnetization(:Z) on an S=1 MPS state is BROKEN today:
#   expect(mps, "Z") → ArgumentError, the "Z" op string is not defined for
#   ITensor "S=1" sites (src/Observables/magnetization.jl:24). @test_broken;
#   T39 (arbitrary spin-S) owns the fix.
# - SpinSectorProjection is NOT applicable on the SV backend (MethodError:
#   no gate_matrix(::SpinSectorProjection)); the SV AKLT construction below
#   works around it via MatrixGate(P₀+P₁) + manual renormalization. Pinned.
#
# odd-L PBC Bricklayer behavior (PINNED, silently partial — recorded in
# .sisyphus/notepads/v04-findings.md for T27):
#   L=5 PBC :odd  → (1,2),(3,4)              [site 5 unpaired — no wrap pair]
#   L=5 PBC :even → (2,3),(4,5),(5,1)        [site 5 appears TWICE]
#   L=5 PBC :nn   → 5 pairs (odd ∪ even)     [site coverage uneven]
#   NNN sublayers produce stride-4 partial covers; no error is raised.

using Test
using QuantumCircuitsMPS
using LinearAlgebra

# --- shared helpers -----------------------------------------------------

_rng() = RNGRegistry(gates_spacetime = 42, gates_realization = 2, born_measurement = 3)

function _qubit_state(backend::Symbol; L::Int = 6, bc::Symbol = :open)
    state = SimulationState(L = L, bc = bc, backend = backend, maxdim = 32, rng = _rng())
    initialize!(state, ProductState(binary_int = 0))
    return state
end

# Build the NN or NNN AKLT state (L=12 PBC, README recipe: repeated P₀+P₁
# projections). MPS uses SpinSectorProjection natively; SV uses
# MatrixGate(P₀+P₁) + manual renormalization (see FINDINGS above).
function _aklt_state(backend::Symbol, parity::Symbol; L::Int = 12, n_layers::Int = L)
    P01 = total_spin_projector(0) + total_spin_projector(1)
    state = if backend == :mps
        SimulationState(L = L, bc = :periodic, site_type = "S=1", maxdim = 128,
            rng = _rng())
    else
        SimulationState(L = L, bc = :periodic, backend = :statevector,
            site_type = "S=1", rng = _rng())
    end
    initialize!(state, ProductState(spin_state = "Z0"))
    if backend == :mps
        proj = SpinSectorProjection(P01)
        for _ in 1:n_layers
            apply!(state, proj, Bricklayer(parity))
        end
    else
        mg = MatrixGate(P01)
        for _ in 1:n_layers
            for pair in QuantumCircuitsMPS.elements(Bricklayer(parity), L, :periodic)
                apply!(state, mg, Sites(pair))
                normalize!(state.backend.ψ)
            end
        end
    end
    return state
end

@testset "audit: observables + geometry" begin

    # ------------------------------------------------------------------
    # (a) Magnetization sign convention, cross-backend agreement
    # ------------------------------------------------------------------
    @testset "Magnetization sign convention (|0⟩ → ⟨Z⟩ = +1)" begin
        L = 6
        for backend in (:mps, :statevector, :clifford)
            @testset "$backend" begin
                # |0…0⟩ → Mz = +1
                s0 = _qubit_state(backend; L = L)
                @test Magnetization(:Z)(s0) ≈ 1.0 atol=1e-12

                # |1…1⟩ → Mz = −1
                s1 = _qubit_state(backend; L = L)
                apply!(s1, PauliX(), AllSites())
                @test Magnetization(:Z)(s1) ≈ -1.0 atol=1e-12

                # |+⟩^L → Mz = 0
                sp = _qubit_state(backend; L = L)
                apply!(sp, Hadamard(), AllSites())
                @test Magnetization(:Z)(sp) ≈ 0.0 atol=1e-12
            end
        end

        # Mixed product state |110000⟩ → Mz = (L − 2·n_ones)/L = 2/6, all backends
        for backend in (:mps, :statevector, :clifford)
            sm = SimulationState(L = 6, bc = :open, backend = backend, maxdim = 32,
                rng = _rng())
            initialize!(sm, ProductState(bitstring = "110000"))
            @test Magnetization(:Z)(sm) ≈ (6 - 2 * 2) / 6 atol=1e-12
        end

        # MPS-only axis sanity: Mx(|+⟩^L) = 1
        sx = _qubit_state(:mps; L = 4)
        apply!(sx, Hadamard(), AllSites())
        @test Magnetization(:X)(sx) ≈ 1.0 atol=1e-12
        @test Magnetization(:Y)(sx) ≈ 0.0 atol=1e-12
    end

    @testset "FINDING: Magnetization(:Z) broken on S=1 MPS" begin
        # expect(mps, "Z") — the "Z" op string is undefined for ITensor
        # "S=1" sites, so this throws ArgumentError TODAY. T39 will make it
        # return (1/L)Σ⟨Sz⟩-style value; flip to @test then.
        s1 = SimulationState(L = 4, bc = :open, site_type = "S=1", maxdim = 32,
            rng = _rng())
        initialize!(s1, ProductState(spin_state = "Z0"))
        @test_broken Magnetization(:Z)(s1) isa Float64
    end

    # ------------------------------------------------------------------
    # (b) AKLT string order — quantitative, MPS + SV
    # ------------------------------------------------------------------
    @testset "AKLT string order |O¹| ≈ 4/9 (L=12 PBC, MPS + SV)" begin
        L = 12
        so_by_backend = Dict{Symbol, Float64}()
        for backend in (:mps, :statevector)
            state = _aklt_state(backend, :nn; L = L, n_layers = L)
            so1 = StringOrder(1, L ÷ 2 + 1)(state)
            so_by_backend[backend] = so1
            @test abs(abs(so1) - 4 / 9) < 0.01
        end
        # Backends agree with each other far more tightly than with 4/9
        @test so_by_backend[:mps] ≈ so_by_backend[:statevector] atol=1e-8
    end

    @testset "NNN AKLT string order |O²| ≈ (4/9)² (L=12 PBC, MPS + SV)" begin
        # O² (paired endpoints) is the order parameter of the NNN AKLT state
        # (two decoupled chains) — per the README StringOrder table. On the
        # NN AKLT state |O²| ≈ 0.008, NOT (4/9)² (verified during audit).
        L = 12
        for backend in (:mps, :statevector)
            state = _aklt_state(backend, :nnn; L = L, n_layers = 2L)
            so2 = StringOrder(1, L ÷ 2 + 1, order = 2)(state)
            @test abs(abs(so2) - (4 / 9)^2) < 0.02
        end
    end

    @testset "StringOrder constructor constraints" begin
        # order=2 requires j ≥ i+4 (non-overlapping endpoint pairs)
        @test_throws ArgumentError StringOrder(1, 4, order = 2)
        @test StringOrder(1, 5, order = 2) isa StringOrder
        # generic validation
        @test_throws ArgumentError StringOrder(3, 2)           # j must be > i
        @test_throws ArgumentError StringOrder(1, 5, order = 3) # order ∈ (1,2)
        # out-of-bounds sites rejected at call time
        s = _qubit_state(:statevector; L = 4)
        @test_throws ArgumentError StringOrder(1, 9)(s)
    end

    @testset "FINDING: SpinSectorProjection unsupported on SV backend" begin
        # No gate_matrix(::SpinSectorProjection) method exists — the SV gate
        # path throws MethodError. Pinned; the AKLT-on-SV construction above
        # works around it via MatrixGate. (Candidate for T17/T39.)
        sv = SimulationState(L = 4, bc = :open, backend = :statevector,
            site_type = "S=1", rng = _rng())
        initialize!(sv, ProductState(spin_state = "Z0"))
        P01 = total_spin_projector(0) + total_spin_projector(1)
        @test_throws MethodError apply!(sv, SpinSectorProjection(P01), Sites([1, 2]))
    end

    # ------------------------------------------------------------------
    # (c) DomainWall analytic counts + PBC wrap
    # ------------------------------------------------------------------
    @testset "DomainWall analytic counts (MPS + SV)" begin
        L = 6
        for backend in (:mps, :statevector)
            @testset "$backend" begin
                # |000000⟩: no "1" anywhere → every projector product is 0 → DW = 0
                s0 = _qubit_state(backend; L = L)
                @test DomainWall(order = 1)(s0, 1) ≈ 0.0 atol=1e-12
                @test DomainWall(order = 2)(s0, 1) ≈ 0.0 atol=1e-12

                # |100000⟩ scanning from i1=1: first "1" at j=1, weight (L−1+1)^order
                s1 = SimulationState(L = L, bc = :open, backend = backend,
                    maxdim = 32, rng = _rng())
                initialize!(s1, ProductState(bitstring = "100000"))
                @test DomainWall(order = 1)(s1, 1) ≈ Float64(L) atol=1e-12
                @test DomainWall(order = 2)(s1, 1) ≈ Float64(L^2) atol=1e-12

                # same state scanning from i1=2: cyclic wrap puts site 1 at
                # scan position j=L → weight (L−L+1)^order = 1 (both orders)
                @test DomainWall(order = 1)(s1, 2) ≈ 1.0 atol=1e-12
                @test DomainWall(order = 2)(s1, 2) ≈ 1.0 atol=1e-12

                # |000001⟩ from i1=1: first "1" at j=L → weight 1
                s2 = SimulationState(L = L, bc = :open, backend = backend,
                    maxdim = 32, rng = _rng())
                initialize!(s2, ProductState(bitstring = "000001"))
                @test DomainWall(order = 1)(s2, 1) ≈ 1.0 atol=1e-12

                # Superposition: (|0⟩+|1⟩)/√2 on site 1, rest |0⟩, i1=1:
                # P(first "1" at j=1) = 1/2, P(no "1") = 1/2 → DW = L/2
                sp = _qubit_state(backend; L = L)
                apply!(sp, Hadamard(), SingleSite(1))
                @test DomainWall(order = 1)(sp, 1) ≈ L / 2 atol=1e-12
            end
        end

        # The cyclic scan is a property of the observable (not of state.bc):
        # a :periodic state gives identical values
        sp_pbc = SimulationState(L = L, bc = :periodic, backend = :statevector,
            rng = _rng())
        initialize!(sp_pbc, ProductState(bitstring = "100000"))
        @test DomainWall(order = 1)(sp_pbc, 2) ≈ 1.0 atol=1e-12

        # i1 dispatch validation: neither i1_fn nor i1 → ArgumentError
        s = _qubit_state(:statevector; L = 4)
        @test_throws ArgumentError DomainWall(order = 1)(s)
        # i1_fn variant matches explicit i1
        @test DomainWall(order = 1, i1_fn = () -> 1)(s) ≈ DomainWall(order = 1)(s, 1)
        # constructor: order ≥ 1
        @test_throws ArgumentError DomainWall(order = 0)
    end

    # ------------------------------------------------------------------
    # FINDING: StringOrder / DomainWall on Clifford crash (raw field error)
    # ------------------------------------------------------------------
    @testset "FINDING: Clifford StringOrder/DomainWall crash" begin
        cs = _qubit_state(:clifford; L = 4)

        # CURRENT behavior (pinned): both fall through to the MPS-typed
        # generic and crash on `state.backend.mps` / `state.backend.sites`
        # (FieldError on Julia ≥ 1.12). They DO throw — never a silent
        # wrong answer:
        @test_throws Exception StringOrder(1, 3)(cs)
        @test_throws Exception DomainWall(order = 1)(cs, 1)

        # EXPECTED behavior after T14: a clean, informative ArgumentError.
        # T14 flips these two to plain @test.
        @test_broken (try
            StringOrder(1, 3)(cs)
            false
        catch e
            e isa ArgumentError
        end)
        @test_broken (try
            DomainWall(order = 1)(cs, 1)
            false
        catch e
            e isa ArgumentError
        end)
    end

    # ------------------------------------------------------------------
    # (d) Geometry enumeration semantics
    # ------------------------------------------------------------------
    @testset "Bricklayer enumeration ≡ README table (L=12 PBC, verbatim)" begin
        L, bc = 12, :periodic
        readme_table = Dict(
            :odd => [[1, 2], [3, 4], [5, 6], [7, 8], [9, 10], [11, 12]],
            :even => [[2, 3], [4, 5], [6, 7], [8, 9], [10, 11], [12, 1]],
            :nn => [[1, 2], [3, 4], [5, 6], [7, 8], [9, 10], [11, 12],
                [2, 3], [4, 5], [6, 7], [8, 9], [10, 11], [12, 1]],
            :nnn_odd_1 => [[1, 3], [5, 7], [9, 11]],
            :nnn_odd_2 => [[3, 5], [7, 9], [11, 1]],
            :nnn_even_1 => [[2, 4], [6, 8], [10, 12]],
            :nnn_even_2 => [[4, 6], [8, 10], [12, 2]],
            :nnn => [[1, 3], [5, 7], [9, 11], [3, 5], [7, 9], [11, 1],
                [2, 4], [6, 8], [10, 12], [4, 6], [8, 10], [12, 2]]
        )
        for (parity, expected) in readme_table
            @test QuantumCircuitsMPS.elements(Bricklayer(parity), L, bc) == expected
        end
        # :nn covers all 12 NN bonds exactly once; :nnn all 12 NNN bonds
        nn = QuantumCircuitsMPS.elements(Bricklayer(:nn), L, bc)
        @test length(nn) == 12 && allunique(Set.(nn))
        nnn = QuantumCircuitsMPS.elements(Bricklayer(:nnn), L, bc)
        @test length(nnn) == 12 && allunique(Set.(nnn))
    end

    @testset "EachSite (broadcast) vs Sites (set) semantics" begin
        L = 8
        # EachSite(2:L-1): K = L-2 independent single-site elements
        es = QuantumCircuitsMPS.elements(EachSite(2:(L - 1)), L, :open)
        @test es == [[i] for i in 2:(L - 1)]
        @test length(es) == L - 2
        # Sites(2:L-1): ONE region element of size L-2
        st = QuantumCircuitsMPS.elements(Sites(2:(L - 1)), L, :open)
        @test st == [collect(2:(L - 1))]
        @test length(st) == 1
        # traits
        @test QuantumCircuitsMPS.is_broadcast(EachSite(2:(L - 1)))
        @test !QuantumCircuitsMPS.is_broadcast(Sites(2:(L - 1)))
        @test QuantumCircuitsMPS.is_broadcast(Bricklayer(:odd))
        @test QuantumCircuitsMPS.is_broadcast(AllSites())
        @test !QuantumCircuitsMPS.is_broadcast(SingleSite(1))
        @test !QuantumCircuitsMPS.is_broadcast(AdjacentPair(1))
        # element_count mirrors elements()
        @test QuantumCircuitsMPS.element_count(EachSite(2:(L - 1)), L, :open) == L - 2
        @test QuantumCircuitsMPS.element_count(Sites(2:(L - 1)), L, :open) == 1
    end

    @testset "odd-L PBC Bricklayer behavior (PINNED)" begin
        # Odd L cannot be tiled by disjoint NN pairs. CURRENT behavior is
        # silently partial/uneven coverage — NO error is raised. Pinned
        # verbatim so any future change is a deliberate, visible decision
        # (T27 owns the coverage-policy question; see notepad).
        L, bc = 5, :periodic
        @test QuantumCircuitsMPS.elements(Bricklayer(:odd), L, bc) ==
              [[1, 2], [3, 4]]                       # site 5 unpaired, no wrap
        @test QuantumCircuitsMPS.elements(Bricklayer(:even), L, bc) ==
              [[2, 3], [4, 5], [5, 1]]               # site 5 in TWO pairs
        @test QuantumCircuitsMPS.elements(Bricklayer(:nn), L, bc) ==
              [[1, 2], [3, 4], [2, 3], [4, 5], [5, 1]]
        @test QuantumCircuitsMPS.elements(Bricklayer(:nnn), L, bc) ==
              [[1, 3], [3, 5], [4, 1], [2, 4], [5, 2]]
        @test QuantumCircuitsMPS.elements(Bricklayer(:nnn_odd_1), L, bc) == [[1, 3]]
        @test QuantumCircuitsMPS.elements(Bricklayer(:nnn_odd_2), L, bc) ==
              [[3, 5], [4, 1]]
        @test QuantumCircuitsMPS.elements(Bricklayer(:nnn_even_1), L, bc) == [[2, 4]]
        @test QuantumCircuitsMPS.elements(Bricklayer(:nnn_even_2), L, bc) == [[5, 2]]
        # odd-L OBC for contrast (no wrap pairs at all)
        @test QuantumCircuitsMPS.elements(Bricklayer(:odd), L, :open) ==
              [[1, 2], [3, 4]]
        @test QuantumCircuitsMPS.elements(Bricklayer(:even), L, :open) ==
              [[2, 3], [4, 5]]
    end

    # ------------------------------------------------------------------
    # (e) SV/Clifford Magnetization rejects non-Z axes cleanly
    # ------------------------------------------------------------------
    @testset "Magnetization axis rejection (SV + Clifford)" begin
        for backend in (:statevector, :clifford)
            s = _qubit_state(backend; L = 3)
            @test_throws ArgumentError Magnetization(:X)(s)
            @test_throws ArgumentError Magnetization(:Y)(s)
            # :Z still works on the same state object
            @test Magnetization(:Z)(s) ≈ 1.0 atol=1e-12
        end
        # struct-level validation (backend-independent)
        @test_throws ArgumentError Magnetization(:W)
    end
end
