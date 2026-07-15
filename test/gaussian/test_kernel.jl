# test/gaussian/test_kernel.jl
# Unit tests for the Gaussian numerical kernel (src/Gaussian/kernel.jl).
# Golden values generated from ~/GTN/GTN.py (P_contraction_2, kraus, get_C_f)
# with ~/.pyenv/versions/miniforge3-25.1.1-2/bin/python.
#
# NOTE: not yet wired into test/runtests.jl — run directly:
#   julia --project=. -e 'include("test/gaussian/test_kernel.jl")'

using Test
using LinearAlgebra
using Random
using QuantumCircuitsMPS
const QCM = QuantumCircuitsMPS

@testset "Gaussian kernel" begin
    @testset "haar_orthogonal: orthogonal, det=+1" begin
        for n in [2, 4, 8, 16], seed in [0, 1, 42, 12345]

            Q = QCM.haar_orthogonal(MersenneTwister(seed), n)
            @test maximum(abs.(Q' * Q - I)) < 1e-12
            @test abs(det(Q) - 1.0) < 1e-12
        end
    end

    @testset "vacuum_covariance: antisymmetric, pure" begin
        for L in [1, 2, 4, 7]
            Γ = QCM.vacuum_covariance(L)
            @test size(Γ) == (2L, 2L)
            @test maximum(abs.(Γ + Γ')) == 0.0
            @test maximum(abs.(Γ * Γ + I)) < 1e-14
        end
    end

    @testset "occupation_covariance: verified sign convention" begin
        # Verified vs Python get_C_f: bit=false -> [[0,1],[-1,0]] (⟨c†c⟩=0),
        # bit=true -> [[0,-1],[1,0]] (⟨c†c⟩=1)
        Γ = QCM.occupation_covariance([false, true, false])
        @test Γ[1, 2] == 1.0 && Γ[2, 1] == -1.0
        @test Γ[3, 4] == -1.0 && Γ[4, 3] == 1.0
        @test Γ[5, 6] == 1.0
        @test maximum(abs.(Γ * Γ + I)) < 1e-14
        @test QCM.occupation_covariance(fill(false, 4)) == QCM.vacuum_covariance(4)
        # ⟨cᵢ†cᵢ⟩ = (1 - Γ[2i-1,2i])/2 (from get_C_f definition)
        @test [(1 - Γ[2i - 1, 2i]) / 2 for i in 1:3] == [0.0, 1.0, 0.0]
    end

    @testset "majorana_indices" begin
        @test QCM.majorana_indices(1) == (1, 2)
        @test QCM.majorana_indices(5) == (9, 10)
    end

    @testset "gaussian_contraction! with unitary kraus preserves purity" begin
        for (i, j) in [(1, 2), (2, 3), (5, 6)],
            n in [(0.6, 0.8, 0.0), (0.0, 0.0, 1.0), (1 / sqrt(3), 1 / sqrt(3), 1 / sqrt(3))]

            Γ = QCM.vacuum_covariance(4)
            Υ = QCM._kraus(n)
            QCM.gaussian_contraction!(Γ, Υ, [i, j])
            @test maximum(abs.(Γ + Γ')) < 1e-12
            @test maximum(abs.(Γ * Γ + I)) < 1e-12
        end
    end

    @testset "gaussian_contraction! with scratch buffer matches" begin
        Γ1 = QCM.vacuum_covariance(4)
        Γ2 = QCM.vacuum_covariance(4)
        Υ = QCM._kraus((0.6, 0.8, 0.0))
        QCM.gaussian_contraction!(Γ1, Υ, [2, 3])
        QCM.gaussian_contraction!(Γ2, Υ, [2, 3]; scratch = zeros(8, 8))
        @test Γ1 == Γ2
    end

    @testset "golden cross-check vs Python P_contraction_2" begin
        # Python: GTN(L=4).C_m (vacuum), kraus([0.6,0.8,0.0]), ix=[1,2] 0-based
        # -> Julia ix=[2,3] 1-based. Golden Γ printed at %.17g from Python.
        Γ = QCM.vacuum_covariance(4)
        Υ = QCM._kraus((0.6, 0.8, 0.0))
        QCM.gaussian_contraction!(Γ, Υ, [2, 3])
        Γ_python = [0.0 0.8 0.0 -0.6 0 0 0 0;
                    -0.8 0.0 -0.6 0.0 0 0 0 0;
                    0.0 0.6 0.0 0.8 0 0 0 0;
                    0.6 0.0 -0.8 0.0 0 0 0 0;
                    0 0 0 0 0.0 1.0 0 0;
                    0 0 0 0 -1.0 0.0 0 0;
                    0 0 0 0 0 0 0.0 1.0;
                    0 0 0 0 0 0 -1.0 0.0]
        @test maximum(abs.(Γ - Γ_python)) < 1e-12
    end

    @testset "purify! restores pure state" begin
        rng = MersenneTwister(7)
        Γ = QCM.vacuum_covariance(4)
        noise = 1e-6 .* randn(rng, 8, 8)
        Γ .+= (noise .- noise') ./ 2
        @test norm(Γ * Γ + I) > 1e-7
        QCM.purify!(Γ)
        @test norm(Γ * Γ + I) < 1e-10
        @test maximum(abs.(Γ + Γ')) < 1e-14
    end

    @testset "parity_projection_upsilon gives valid pure states" begin
        # Cross-mode pair (Majoranas 2,3): both outcomes have prob 1/2 on vacuum
        for s in (+1, -1)
            Γ = QCM.vacuum_covariance(2)
            QCM.gaussian_contraction!(Γ, QCM.parity_projection_upsilon(s), [2, 3])
            @test maximum(abs.(Γ + Γ')) < 1e-12
            @test maximum(abs.(Γ * Γ + I)) < 1e-12
            @test Γ[2, 3] ≈ -s  # verified convention: post-state Γ[i,j] = -s
        end
        # Intra-mode pair: vacuum IS the s=-1 outcome (Γ[1,2]=+1)
        Γ = QCM.vacuum_covariance(2)
        QCM.gaussian_contraction!(Γ, QCM.parity_projection_upsilon(-1), [1, 2])
        @test Γ[1, 2] ≈ 1.0
        @test maximum(abs.(Γ * Γ + I)) < 1e-12
        @test_throws ArgumentError QCM.parity_projection_upsilon(0)
    end

    @testset "singular contraction throws ArgumentError" begin
        # Vacuum pair (Γ[1,2]=+1) projected onto opposite parity s=+1:
        # Γ_RR·Υ_LL + I = 0 exactly -> probability-zero outcome
        Γ = QCM.vacuum_covariance(2)
        err = try
            QCM.gaussian_contraction!(Γ, QCM.parity_projection_upsilon(+1), [1, 2])
            nothing
        catch e
            e
        end
        @test err isa ArgumentError
        @test occursin("vanishing state", err.msg)
    end
end
