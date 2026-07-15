# === Gaussian backend: Majorana chain site granularity (T15) ===
# Standalone: julia --project=. -e 'include("test/gaussian/test_majorana_chain.jl")'
# NOT wired into runtests.jl (T13's job).
#
# site_type="Majorana": each site IS one Majorana mode (majoranas_per_site=1,
# Γ is L×L) vs the default fermionic-mode granularity (2 Majoranas per site,
# Γ is 2L×2L). Same covariance-matrix machinery, same gate types — only the
# site→Majorana index mapping (site_majoranas) changes.

using Test
using QuantumCircuitsMPS
using LinearAlgebra
using Random: MersenneTwister
const QC = QuantumCircuitsMPS

function _rng(k)
    RNGRegistry(gates_spacetime = k, gates_realization = k + 10,
        born_measurement = k + 20, state_init = k + 30)
end

function _majorana_state(L; bc = :open, seed = 1, binary_int = 0)
    state = SimulationState(L = L, bc = bc, backend = :gaussian,
        site_type = "Majorana", rng = _rng(seed))
    initialize!(state, ProductState(binary_int = binary_int))
    return state
end

@testset "Majorana chain: construction + initialization" begin
    # even L accepted; majoranas_per_site set from site_type
    for L in (2, 4, 16)
        s = SimulationState(L = L, bc = :open, backend = :gaussian,
            site_type = "Majorana", rng = _rng(1))
        @test s.backend isa GaussianBackend
        @test s.backend.majoranas_per_site == 1
    end
    # fermionic default unchanged
    sferm = SimulationState(L = 4, bc = :open, backend = :gaussian, rng = _rng(1))
    @test sferm.backend.majoranas_per_site == 2

    # odd L rejected with informative ArgumentError
    err = try
        SimulationState(L = 5, bc = :open, backend = :gaussian, site_type = "Majorana")
        nothing
    catch e
        e
    end
    @test err isa ArgumentError
    @test occursin("even", err.msg)
    @test occursin("Majorana", err.msg)

    # ProductState vacuum: Γ is L×L, dimerized ⊕[[0,1],[-1,0]]
    L = 8
    s = _majorana_state(L)
    Γ = s.backend.corr
    @test size(Γ) == (L, L)
    @test size(s.backend.scratch) == (L, L)
    for k in 1:(L ÷ 2)
        @test Γ[2k - 1, 2k] == 1.0
        @test Γ[2k, 2k - 1] == -1.0
    end
    @test maximum(abs.(Γ * Γ + I)) == 0.0
    # bit pattern has length L÷2: bit k flips the sign of pair (2k-1, 2k)
    s2 = SimulationState(L = 4, bc = :open, backend = :gaussian,
        site_type = "Majorana", rng = _rng(2))
    initialize!(s2, ProductState(bitstring = "10"))
    Γ2 = s2.backend.corr
    @test Γ2[1, 2] == -1.0   # bit 1 → flipped pair
    @test Γ2[3, 4] == 1.0    # bit 0 → vacuum sign

    # RandomGaussianState: Γ is L×L, pure, antisymmetric, seed-reproducible
    sA = SimulationState(L = 6, bc = :open, backend = :gaussian,
        site_type = "Majorana", rng = _rng(7))
    initialize!(sA, RandomGaussianState())
    ΓA = sA.backend.corr
    @test size(ΓA) == (6, 6)
    @test maximum(abs.(ΓA + transpose(ΓA))) == 0.0
    @test maximum(abs.(ΓA * ΓA + I)) < 1e-12
    sB = SimulationState(L = 6, bc = :open, backend = :gaussian,
        site_type = "Majorana", rng = _rng(7))
    initialize!(sB, RandomGaussianState())
    @test sB.backend.corr == ΓA  # bitwise
end

@testset "site_majoranas helper: both granularities" begin
    sM = _majorana_state(4)
    sF = SimulationState(L = 4, bc = :open, backend = :gaussian, rng = _rng(1))
    @test QC.site_majoranas(sM, 3) == (3,)
    @test QC.site_majoranas(sF, 3) == (5, 6)
end

@testset "fermion↔Majorana equivalence: BondParity ≡ Measure(:Z) (KEY index-mapping test)" begin
    # A Majorana chain of 2L sites with BondParity on Bricklayer(:odd) bonds
    # (1,2),(3,4),...,(2L-1,2L) measures exactly the intra-mode parities
    # iγ_{2k-1}γ_{2k} — i.e. the occupations of a fermionic chain of L sites
    # measured by Measure(:Z) on AllSites. Same :state_init seed → identical
    # initial Γ (both are 2L×2L with the same Haar-SO(2L) draw); same
    # :born_measurement seed → identical outcome sequence → identical final Γ.
    L = 6  # fermionic sites; Majorana chain has 2L = 12 sites
    seed = 11

    sM = SimulationState(L = 2L, bc = :open, backend = :gaussian,
        site_type = "Majorana", rng = _rng(seed))
    initialize!(sM, RandomGaussianState())
    sF = SimulationState(L = L, bc = :open, backend = :gaussian, rng = _rng(seed))
    initialize!(sF, RandomGaussianState())
    @test sM.backend.corr == sF.backend.corr  # identical 2L×2L initial Γ (bitwise)

    apply!(sM, BondParity(), Bricklayer(:odd))   # bonds (1,2),(3,4),...,(2L-1,2L)
    apply!(sF, Measure(:Z), AllSites())          # sites 1..L, same order
    @test sM.backend.corr == sF.backend.corr     # bitwise-identical collapse
    @test maximum(abs.(sM.backend.corr * sM.backend.corr + I)) < 1e-12
end

@testset "fermion↔Majorana equivalence: GaussianHaar SO(2) index mapping" begin
    # GaussianHaar on Majorana-chain sites (3,4) must equal the SAME SO(2)
    # rotation conjugated manually at Majorana indices [3,4] — and therefore
    # also equal the identical manual conjugation of the fermionic-chain Γ
    # (same matrix), pinning the site→Majorana index mapping.
    seed = 21
    sM = SimulationState(L = 8, bc = :open, backend = :gaussian,
        site_type = "Majorana", rng = _rng(seed))
    initialize!(sM, RandomGaussianState())
    Γ0 = copy(sM.backend.corr)

    apply!(sM, GaussianHaar(), AdjacentPair(3))  # Majorana sites (3,4)

    # replicate the :gates_realization stream (MersenneTwister(seed+10), first
    # draw) and conjugate manually — SO(2), i.e. n = 2 Majorana legs
    O = QC.haar_orthogonal(MersenneTwister(seed + 10), 2)
    @test size(O) == (2, 2)
    @test abs(det(O) - 1) < 1e-12
    Γexp = copy(Γ0)
    ix = [3, 4]
    Γexp[ix, :] .= O * Γexp[ix, :]
    Γexp[:, ix] .= Γexp[:, ix] * O'
    Γexp .= (Γexp .- transpose(Γexp)) ./ 2
    @test sM.backend.corr == Γexp  # bitwise (same float ops)

    # fermionic chain sharing the same initial Γ: the same manual conjugation
    # at the same Majorana indices gives the same state — the Majorana-chain
    # gate on sites (3,4) IS the rotation on Majoranas (3,4) of mode space
    # (fermionic mode 2's second Majorana + nothing else would NOT match; the
    # mapping is site k ↔ Majorana k, verified bitwise above).
    sF = SimulationState(L = 4, bc = :open, backend = :gaussian, rng = _rng(seed))
    initialize!(sF, RandomGaussianState())
    @test sF.backend.corr == Γ0
end

@testset "purity + antisymmetry: 100 mixed ops, L=16 Majorana sites, PBC; seed repro" begin
    L = 16
    function run(seed)
        s = SimulationState(L = L, bc = :periodic, backend = :gaussian,
            site_type = "Majorana", rng = _rng(seed))
        initialize!(s, ProductState(binary_int = 0))
        for t in 1:25
            apply!(s, GaussianHaar(), Bricklayer(:odd))
            apply!(s, BondParity(), Bricklayer(:even))
            apply!(s, GaussianHaar(), Bricklayer(:even))
            apply!(s, BondParity(), Bricklayer(:odd))
        end
        return s.backend.corr
    end
    Γ = run(3)
    @test size(Γ) == (L, L)
    @test maximum(abs.(Γ + transpose(Γ))) == 0.0
    @test maximum(abs.(Γ * Γ + I)) < 1e-10
    @test Γ == run(3)          # bitwise seed reproducibility
    @test Γ != run(4)          # different seed differs
end

@testset "PBC wrap bond (L,1) on Majorana chain → Majorana indices [L,1]" begin
    L = 8
    s = SimulationState(L = L, bc = :periodic, backend = :gaussian,
        site_type = "Majorana", rng = _rng(5))
    initialize!(s, RandomGaussianState())
    apply!(s, BondParity(), AdjacentPair(L))  # wrap bond (L,1)
    Γ = s.backend.corr
    @test abs(abs(Γ[L, 1]) - 1.0) < 1e-12     # parity iγ_Lγ_1 now definite
    @test maximum(abs.(Γ * Γ + I)) < 1e-10
end

@testset "rejections on Majorana chain: Measure(:Z), Reset, PauliX, Magnetization, born_probability" begin
    s = _majorana_state(8)
    @test_throws ArgumentError apply!(s, Measure(:Z), SingleSite(2))
    @test_throws ArgumentError apply!(s, Reset(), SingleSite(2))
    @test_throws ArgumentError apply!(s, PauliX(), SingleSite(2))
    @test_throws ArgumentError Magnetization(:Z)(s)
    @test_throws ArgumentError born_probability(s, 2, 0)
    # messages are informative
    for (f, needle) in ((() -> apply!(s, Measure(:Z), SingleSite(2)), "BondParity"),
        (() -> apply!(s, PauliX(), SingleSite(2)), "single-Majorana"),
        (() -> Magnetization(:Z)(s), "Majorana"),
        (() -> born_probability(s, 2, 0), "BondParity"))
        err = try
            ;
            f();
            nothing;
        catch e
            ;
            e;
        end
        @test err isa ArgumentError
        @test occursin(needle, err.msg)
    end
    # state untouched by the rejected operations (vacuum preserved)
    @test s.backend.corr == QC.occupation_covariance(fill(false, 4))
end

@testset "observables on Majorana chain: EE / MI route through site_majoranas" begin
    L = 8
    s = _majorana_state(L)
    # dimerized vacuum: cutting BETWEEN dimers (even cut) → S = 0;
    # cutting a dimer in half (odd cut) → half a fermion → S = log(2)/2 nats.
    @test abs(EntanglementEntropy(cut = 2, base = ℯ)(s)) < 1e-12
    @test abs(EntanglementEntropy(cut = 4, base = ℯ)(s)) < 1e-12
    @test abs(EntanglementEntropy(cut = 1, base = ℯ)(s) - log(2) / 2) < 1e-12
    @test abs(EntanglementEntropy(cut = 3, base = ℯ)(s) - log(2) / 2) < 1e-12
    # MI between the two halves of one dimer = log 2 (nats, default base=ℯ)
    @test abs(MutualInformation([1], [2])(s) - log(2)) < 1e-12
    # MI between different dimers = 0
    @test abs(MutualInformation([1, 2], [5, 6])(s)) < 1e-12
    # wrapped/non-contiguous subsets still work (identity index mapping)
    @test MutualInformation([7, 8, 1, 2], [3, 4, 5, 6])(s) isa Float64
    # TMI composes for free
    @test abs(TripartiteMutualInformation(1:2, 3:4, 5:6)(s)) < 1e-12
end

@testset "Python golden: SO(2) rotation ↔ kraus((0, cos φ, sin φ)) convention" begin
    # GOLDEN (embedded literal), generated by ~/GTN/GTN.py:
    #   g = GTN.GTN(L=2, history=False, seed=0, op=False, random_init=False)
    #   Ups = g.kraus((0, cos(0.7), sin(0.7)))          # class-DIII unitary branch
    #   P_contraction_2(g.C_m, Ups, ix=[1,2], ix_bar=[0,3])   # 0-based legs
    # → output covariance matrix (float64, printed to 17 significant digits):
    golden = [0.0 0.7648421872844885 0.644217687237691 0.0;
              -0.7648421872844885 0.0 0.0 -0.644217687237691;
              -0.644217687237691 0.0 0.0 0.7648421872844885;
              0.0 0.644217687237691 -0.7648421872844885 0.0]
    # EMPIRICALLY DERIVED convention (do not assume): the contraction of
    # kraus((0, cos φ, sin φ)) on Majorana pair (a, b) equals the direct
    # SO(2) conjugation Γ ← RΓRᵀ with R = [[cos φ, −sin φ], [sin φ, cos φ]]
    # on rows/columns (a, b). (Python solve: R = Γ'[ix, ix̄]·pinv(Γ[ix, ix̄]),
    # exact rotation, det = 1, residual 0.0.)
    φ = 0.7
    R = [cos(φ) -sin(φ); sin(φ) cos(φ)]
    Γ = QC.vacuum_covariance(2)             # 4×4 L=2 vacuum, same as Python C_m
    ix = [2, 3]                             # 1-based == Python [1,2] 0-based
    Γ[ix, :] .= R * Γ[ix, :]
    Γ[:, ix] .= Γ[:, ix] * R'
    @test maximum(abs.(Γ - golden)) < 1e-12

    # Ensemble agreement: QR-Haar on SO(2) is provably uniform in angle —
    # SO(2) ≅ U(1) and Haar measure on U(1) is the uniform angle measure;
    # haar_orthogonal implements exact Haar via the QR + R-diag sign fix
    # (Mezzadri 2007), so the extracted rotation angle is U[0, 2π).
    # Statistical check (KS-style): N draws, ECDF vs uniform.
    rng = MersenneTwister(1234)
    N = 20000
    θs = sort([begin
                   O = QC.haar_orthogonal(rng, 2)
                   mod(atan(O[2, 1], O[1, 1]), 2π)
               end for _ in 1:N])
    ks = maximum(abs.(θs ./ (2π) .- (1:N) ./ N))
    @test ks < 0.02   # KS critical value at α=0.01 is 1.63/√N ≈ 0.0115
end

println("test_majorana_chain.jl: all testsets finished")
