# === Geometry v0.1 API tests (Task 3) ===
# Canonical elements(), broadcast/set traits, EachSite, Sites, element_count,
# validate_support, and delegate behavior preservation.
#
# The hardcoded enumerations below were captured from the PRE-refactor
# get_compound_elements() output (commit on refactor/api-v0.1 before Task 3).
# They are the bit-for-bit API contract for element enumeration order.

using Test
using QuantumCircuitsMPS

@testset "Geometry v0.1" begin

    # ------------------------------------------------------------------
    # Enumeration order contract (hardcoded pre-refactor goldens)
    # ------------------------------------------------------------------
    @testset "elements: Bricklayer enumeration order (golden)" begin
        golden = Dict(
            (:odd, 8, :periodic) => [[1, 2], [3, 4], [5, 6], [7, 8]],
            (:odd, 9, :open) => [[1, 2], [3, 4], [5, 6], [7, 8]],
            (:odd, 12, :periodic) => [[1, 2], [3, 4], [5, 6], [7, 8], [9, 10], [11, 12]],
            (:odd, 4, :open) => [[1, 2], [3, 4]],
            (:odd, 6, :periodic) => [[1, 2], [3, 4], [5, 6]],
            (:even, 8, :periodic) => [[2, 3], [4, 5], [6, 7], [8, 1]],
            (:even, 9, :open) => [[2, 3], [4, 5], [6, 7], [8, 9]],
            (:even, 12, :periodic) => [[2, 3], [4, 5], [6, 7], [8, 9], [10, 11], [12, 1]],
            (:even, 4, :open) => [[2, 3]],
            (:even, 6, :periodic) => [[2, 3], [4, 5], [6, 1]],
            (:nn, 8, :periodic) =>
                [[1, 2], [3, 4], [5, 6], [7, 8], [2, 3], [4, 5], [6, 7], [8, 1]],
            (:nn, 9, :open) =>
                [[1, 2], [3, 4], [5, 6], [7, 8], [2, 3], [4, 5], [6, 7], [8, 9]],
            (:nn, 12, :periodic) => [[1, 2], [3, 4], [5, 6], [7, 8], [9, 10], [11, 12],
                [2, 3], [4, 5], [6, 7], [8, 9], [10, 11], [12, 1]],
            (:nn, 4, :open) => [[1, 2], [3, 4], [2, 3]],
            (:nn, 6, :periodic) => [[1, 2], [3, 4], [5, 6], [2, 3], [4, 5], [6, 1]],
            (:nnn, 8, :periodic) =>
                [[1, 3], [5, 7], [3, 5], [7, 1], [2, 4], [6, 8], [4, 6], [8, 2]],
            (:nnn, 9, :open) => [[1, 3], [5, 7], [3, 5], [7, 9], [2, 4], [6, 8], [4, 6]],
            (:nnn, 12, :periodic) => [[1, 3], [5, 7], [9, 11], [3, 5], [7, 9], [11, 1],
                [2, 4], [6, 8], [10, 12], [4, 6], [8, 10], [12, 2]],
            (:nnn, 4, :open) => [[1, 3], [2, 4]],
            (:nnn, 6, :periodic) => [[1, 3], [3, 5], [5, 1], [2, 4], [4, 6], [6, 2]],
            (:nnn_odd_1, 8, :periodic) => [[1, 3], [5, 7]],
            (:nnn_odd_1, 12, :periodic) => [[1, 3], [5, 7], [9, 11]],
            (:nnn_odd_2, 8, :periodic) => [[3, 5], [7, 1]],
            (:nnn_odd_2, 9, :open) => [[3, 5], [7, 9]],
            (:nnn_odd_2, 4, :open) => Vector{Int}[],
            (:nnn_even_1, 12, :periodic) => [[2, 4], [6, 8], [10, 12]],
            (:nnn_even_2, 8, :periodic) => [[4, 6], [8, 2]],
            (:nnn_even_2, 9, :open) => [[4, 6]],
            (:nnn_even_2, 4, :open) => Vector{Int}[]
        )
        for ((par, L, bc), expected) in golden
            @test QuantumCircuitsMPS.elements(Bricklayer(par), L, bc) == expected
        end
    end

    @testset "elements: AllSites canonical order" begin
        @test QuantumCircuitsMPS.elements(AllSites(), 8, :periodic) == [[i] for i in 1:8]
        @test QuantumCircuitsMPS.elements(AllSites(), 3, :open) == [[1], [2], [3]]
    end

    @testset "delegates preserve behavior (old == new)" begin
        for par in (:odd, :even, :nn, :nnn, :nnn_odd_1, :nnn_odd_2, :nnn_even_1, :nnn_even_2)
            for (L, bc) in ((8, :periodic), (9, :open), (12, :periodic))
                @test QuantumCircuitsMPS.get_compound_elements(Bricklayer(par), L, bc) ==
                      QuantumCircuitsMPS.elements(Bricklayer(par), L, bc)
            end
        end
        @test QuantumCircuitsMPS.get_compound_elements(AllSites(), 8, :periodic) ==
              QuantumCircuitsMPS.elements(AllSites(), 8, :periodic)
        # get_pairs (state-based) still returns tuples matching elements()
        state = (L = 8, bc = :periodic)
        @test QuantumCircuitsMPS.get_pairs(Bricklayer(:even), state) ==
              [(2, 3), (4, 5), (6, 7), (8, 1)]
    end

    # ------------------------------------------------------------------
    # Set geometries: single element
    # ------------------------------------------------------------------
    @testset "elements: set geometries" begin
        @test QuantumCircuitsMPS.elements(SingleSite(3), 8, :open) == [[3]]
        @test QuantumCircuitsMPS.elements(AdjacentPair(2), 8, :open) == [[2, 3]]
        @test QuantumCircuitsMPS.elements(AdjacentPair(8), 8, :periodic) == [[8, 1]]
        # Staircases: current-position resolution
        @test QuantumCircuitsMPS.elements(StaircaseRight(3), 8, :periodic) == [[3, 4]]
        @test QuantumCircuitsMPS.elements(StaircaseRight(8), 8, :periodic) == [[8, 1]]
        @test QuantumCircuitsMPS.elements(StaircaseLeft(5; range = 2), 8, :periodic) ==
              [[5, 7]]
        @test QuantumCircuitsMPS.elements(StaircaseLeft(7; range = 2), 8, :periodic) ==
              [[7, 1]]
        @test_throws ArgumentError QuantumCircuitsMPS.elements(StaircaseRight(8), 8, :open)
        # Pointer: current-position resolution
        @test QuantumCircuitsMPS.elements(Pointer(4), 8, :open) == [[4, 5]]
        @test QuantumCircuitsMPS.elements(Pointer(8), 8, :periodic) == [[8, 1]]
    end

    # ------------------------------------------------------------------
    # New geometry: EachSite (broadcast)
    # ------------------------------------------------------------------
    @testset "EachSite" begin
        @test QuantumCircuitsMPS.elements(EachSite(2:7), 8, :open) == [[i] for i in 2:7]
        @test QuantumCircuitsMPS.elements(EachSite([1, 4, 6]), 8, :periodic) ==
              [[1], [4], [6]]
        @test QuantumCircuitsMPS.element_count(EachSite(2:7), 8, :open) == 6
        # SRN bulk eligibility spelling
        L = 8
        @test QuantumCircuitsMPS.elements(EachSite(2:(L - 1)), L, :periodic) ==
              [[i] for i in 2:(L - 1)]
        # out-of-range sites error at elements() time
        @test_throws ArgumentError QuantumCircuitsMPS.elements(EachSite(2:9), 8, :open)
        @test_throws ArgumentError EachSite(Int[])
        @test_throws ArgumentError EachSite([0, 1])
    end

    # ------------------------------------------------------------------
    # New geometry: Sites (set)
    # ------------------------------------------------------------------
    @testset "Sites" begin
        @test QuantumCircuitsMPS.elements(Sites(1:4), 8, :open) == [[1, 2, 3, 4]]
        @test QuantumCircuitsMPS.elements(Sites([2, 5]), 8, :periodic) == [[2, 5]]
        @test QuantumCircuitsMPS.element_count(Sites(1:4), 8, :open) == 1
        @test_throws ArgumentError QuantumCircuitsMPS.elements(Sites(6:10), 8, :open)
        @test_throws ArgumentError Sites(Int[])
    end

    # ------------------------------------------------------------------
    # validate_support
    # ------------------------------------------------------------------
    @testset "validate_support" begin
        # HaarRandom support=2 vs Sites region of 3 → ArgumentError naming 2 and 3
        err = try
            QuantumCircuitsMPS.validate_support(HaarRandom(), Sites(1:3), 8, :open)
            nothing
        catch e
            e
        end
        @test err isa ArgumentError
        msg = sprint(showerror, err)
        @test occursin("2", msg)
        @test occursin("3", msg)
        # matching support passes (returns without throwing)
        @test QuantumCircuitsMPS.validate_support(HaarRandom(), Sites(3:4), 8, :open) ===
              nothing
        @test QuantumCircuitsMPS.validate_support(PauliX(), Sites([5]), 8, :open) ===
              nothing
        # non-Sites geometries: no-op (support resolution handled elsewhere)
        @test QuantumCircuitsMPS.validate_support(PauliX(), StaircaseLeft(1), 8, :periodic) ===
              nothing
    end

    # ------------------------------------------------------------------
    # element_count
    # ------------------------------------------------------------------
    @testset "element_count" begin
        @test QuantumCircuitsMPS.element_count(AllSites(), 8, :periodic) == 8
        @test QuantumCircuitsMPS.element_count(Bricklayer(:even), 8, :periodic) == 4
        @test QuantumCircuitsMPS.element_count(Bricklayer(:even), 9, :open) == 4
        @test QuantumCircuitsMPS.element_count(SingleSite(1), 8, :open) == 1
        @test QuantumCircuitsMPS.element_count(StaircaseLeft(1), 8, :periodic) == 1
        @test QuantumCircuitsMPS.element_count(Pointer(2), 8, :periodic) == 1
    end

    # ------------------------------------------------------------------
    # is_broadcast trait truth table
    # ------------------------------------------------------------------
    @testset "is_broadcast truth table" begin
        # broadcast ("distribution") geometries
        @test QuantumCircuitsMPS.is_broadcast(AllSites()) == true
        for par in (:odd, :even, :nn, :nnn, :nnn_odd_1, :nnn_odd_2, :nnn_even_1, :nnn_even_2)
            @test QuantumCircuitsMPS.is_broadcast(Bricklayer(par)) == true
        end
        @test QuantumCircuitsMPS.is_broadcast(EachSite(1:3)) == true
        # set ("region") geometries
        @test QuantumCircuitsMPS.is_broadcast(SingleSite(1)) == false
        @test QuantumCircuitsMPS.is_broadcast(AdjacentPair(1)) == false
        @test QuantumCircuitsMPS.is_broadcast(Sites(1:2)) == false
        @test QuantumCircuitsMPS.is_broadcast(StaircaseLeft(1)) == false
        @test QuantumCircuitsMPS.is_broadcast(StaircaseRight(1)) == false
        @test QuantumCircuitsMPS.is_broadcast(Pointer(1)) == false
    end

    # ------------------------------------------------------------------
    # Compatibility: new types work with existing plumbing
    # ------------------------------------------------------------------
    @testset "compat: is_compound_geometry + get_sites for new types" begin
        @test QuantumCircuitsMPS.is_compound_geometry(EachSite(1:3)) == true
        @test QuantumCircuitsMPS.is_compound_geometry(Sites(1:3)) == false
        @test QuantumCircuitsMPS.get_compound_elements(EachSite(2:4), 8, :open) ==
              [[2], [3], [4]]
        state = (L = 8, bc = :open)
        @test get_sites(Sites([1, 2, 5]), state) == [1, 2, 5]
    end
end
