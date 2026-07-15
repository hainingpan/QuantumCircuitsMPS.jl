# Tests for the test-only ED/Pfaffian oracle (test/gaussian/oracle.jl).
# Run: julia --project=. -e 'include("test/gaussian/test_oracle.jl")'
using Test
using LinearAlgebra
using Random

include(joinpath(@__DIR__, "oracle.jl"))

@testset "ED/Pfaffian oracle" begin
    @testset "_pfaffian: pf(A)^2 = det(A)" begin
        rng = MersenneTwister(20260711)
        for n in (2, 4, 6), trial in 1:5

            B = randn(rng, n, n)
            A = B - transpose(B)   # random antisymmetric
            pf = _pfaffian(A)
            @test abs(pf^2 - det(A)) < 1e-10 * max(1.0, abs(det(A)))
        end
        # edge cases
        @test _pfaffian(zeros(0, 0)) == 1.0 + 0im
        @test _pfaffian(zeros(3, 3)) == 0.0 + 0im
        @test _pfaffian([0.0 1.0; -1.0 0.0]) ≈ 1.0
        # golden vs Python GTN._pfaffian (embedded literal)
        A4 = [0 2.0 -1 3; -2 0 4 -2; 1 -4 0 1.5; -3 2 -1.5 0]
        @test _pfaffian(A4) ≈ 13.0 + 0im atol = 1e-12
    end

    @testset "majorana_matrices algebra (L=2,3)" begin
        for L in (2, 3), order in (:msb, :lsb)

            γ = majorana_matrices(L; order = order)
            dim = 1 << L
            Id = Matrix{ComplexF64}(I, dim, dim)
            @test length(γ) == 2L
            for a in 1:2L
                @test γ[a] ≈ γ[a]'   # Hermitian
                for b in a:2L
                    anti = γ[a] * γ[b] + γ[b] * γ[a]
                    @test norm(anti - (a == b ? 2 : 0) * Id) < 1e-12
                end
            end
        end
    end

    @testset "vacuum reconstruction (L=2,3)" begin
        for L in (2, 3)
            Γ = oracle_vacuum_covariance(L)
            ρ = oracle_density_matrix(Γ)
            P = oracle_basis_projector(fill(false, L))
            @test maximum(abs.(ρ - P)) < 1e-12
            @test abs(tr(ρ) - 1) < 1e-12
            @test norm(ρ - ρ') < 1e-12
            @test minimum(real(eigvals(Hermitian(ρ)))) > -1e-12
        end
    end

    @testset "fully occupied reconstruction (L=2,3)" begin
        for L in (2, 3)
            Γ = oracle_occupation_covariance(fill(true, L))
            ρ = oracle_density_matrix(Γ)
            P = oracle_basis_projector(fill(true, L))
            @test maximum(abs.(ρ - P)) < 1e-12
            @test abs(tr(ρ) - 1) < 1e-12
        end
    end

    @testset "mixed occupation pattern + MSB ordering (L=3)" begin
        bits = [true, false, true]   # |101⟩: site1=MSB ⇒ index 0b101 = 5
        Γ = oracle_occupation_covariance(bits)
        ρ = oracle_density_matrix(Γ)
        @test abs(ρ[6, 6] - 1) < 1e-12   # 1-based index 6 = 0-based 5
        @test maximum(abs.(ρ - oracle_basis_projector(bits))) < 1e-12
        # LSB ordering: |101⟩ with site1=LSB ⇒ index 1 + 4 = 5 too (palindrome);
        # use asymmetric pattern instead
        bits2 = [true, false, false]  # msb ⇒ idx 4; lsb ⇒ idx 1
        Γ2 = oracle_occupation_covariance(bits2)
        @test abs(oracle_density_matrix(Γ2; order = :msb)[5, 5] - 1) < 1e-12
        @test abs(oracle_density_matrix(Γ2; order = :lsb)[2, 2] - 1) < 1e-12
    end

    @testset "golden cross-check vs Python GTN.density_matrix (rotated Γ, L=2)" begin
        # Γ' = R Γ_vac Rᵀ, R = Givens(θ=0.7) on Majoranas 2,3 (1-based)
        th = 0.7
        R = Matrix{Float64}(I, 4, 4)
        R[2, 2] = cos(th);
        R[2, 3] = -sin(th)
        R[3, 2] = sin(th);
        R[3, 3] = cos(th)
        Γ = R * oracle_vacuum_covariance(2) * transpose(R)
        ρ = oracle_density_matrix(Γ)
        # Python golden (density_matrix(G2, order="msb")):
        ρ_py = ComplexF64[0.8824210936422443 0 0 0.3221088436188455im;
                          0 0 0 0;
                          0 0 0 0;
                          -0.3221088436188455im 0 0 0.11757890635775575]
        @test maximum(abs.(ρ - ρ_py)) < 1e-12
        @test abs(tr(ρ) - 1) < 1e-12
        @test minimum(real(eigvals(Hermitian(ρ)))) > -1e-12
        @test norm(ρ * ρ - ρ) < 1e-10   # pure state
    end

    @testset "parity projector via majorana_matrices (L=2)" begin
        # collapse mode 1 of the rotated state back to unoccupied:
        # P_s = (I + s·im·γ̂₁γ̂₂)/2 with s such that Γ[1,2] → +1 ⇒ ⟨iγ₁γ₂⟩ = +1
        γ = majorana_matrices(2)
        th = 0.7
        R = Matrix{Float64}(I, 4, 4)
        R[2, 2] = cos(th);
        R[2, 3] = -sin(th)
        R[3, 2] = sin(th);
        R[3, 3] = cos(th)
        ρ = oracle_density_matrix(R * oracle_vacuum_covariance(2) * transpose(R))
        P = (Matrix{ComplexF64}(I, 4, 4) + im * γ[1] * γ[2]) / 2
        ρc = P * ρ * P'
        ρc ./= tr(ρc)
        # mode 1 unoccupied and mode 2 unoccupied (rotation preserved parity here):
        @test abs(real(tr(ρc * ((I + im * γ[1] * γ[2]) / 2))) - 1) < 1e-10
        @test abs(tr(ρc) - 1) < 1e-12
    end

    @testset "guards" begin
        @test_throws AssertionError oracle_density_matrix(oracle_vacuum_covariance(6))
        @test_throws ArgumentError oracle_density_matrix(zeros(3, 3))
        @test_throws ArgumentError majorana_matrices(6)
    end
end

println("test_oracle.jl: all tests finished")
