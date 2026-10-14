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

    @testset "antisymmetrize! is bit-identical to the broadcast" begin
        rng = MersenneTwister(11)
        for N in (2, 7, 16), trial in 1:5

            A = randn(rng, N, N)
            # Plant exact zeros of both signs, including equal-sign pairs
            # (the case where `v, -v` and the broadcast disagree on signed
            # zeros) and a nonzero diagonal.
            A[1, 2] = 0.0
            A[2, 1] = 0.0
            A[1, N] = -0.0
            A[N, 1] = 0.0
            A[N, N - 1] = -0.0
            A[N - 1, N] = -0.0
            ref = (A .- transpose(A)) ./ 2
            B = copy(A)
            @test QCM.antisymmetrize!(B) === B
            @test isequal(B, ref)                       # isequal: -0.0 ≠ 0.0
            @test isequal(QCM.antisymmetrize!(copy(B)), B)   # idempotent
        end
        @test_throws DimensionMismatch QCM.antisymmetrize!(zeros(3, 4))
    end

    @testset "antisymmetrize!(Γ, rows) equals the full pass after a row/column update" begin
        rng = MersenneTwister(13)
        for N in (4, 12, 30), trial in 1:5

            O = QCM.haar_orthogonal(rng, N)
            Γ = O * QCM.vacuum_covariance(N ÷ 2) * transpose(O)
            QCM.antisymmetrize!(Γ)                      # exactly antisymmetric start
            ix = randperm(rng, N)[1:(trial % 2 == 0 ? 2 : 4)]
            R = QCM.haar_orthogonal(rng, length(ix))
            Γ[ix, :] .= R * Γ[ix, :]
            Γ[:, ix] .= Γ[:, ix] * R'
            full = QCM.antisymmetrize!(copy(Γ))
            part = QCM.antisymmetrize!(copy(Γ), ix)
            @test isequal(part, full)                   # bit-for-bit, signed zeros included
            @test isequal(QCM.antisymmetrize!(copy(part), ix), part)   # idempotent
        end
        @test_throws DimensionMismatch QCM.antisymmetrize!(zeros(3, 4), [1])
    end

    @testset "conjugate_rows_cols! equals the slice form" begin
        rng = MersenneTwister(17)
        for N in (2, 4, 6, 8, 12, 40), m in (2, 4), trial in 1:3
            m <= N || continue
            O = QCM.haar_orthogonal(rng, N)
            Γ0 = O * QCM.vacuum_covariance(N ÷ 2) * transpose(O)
            ix = randperm(rng, N)[1:m]
            R = QCM.haar_orthogonal(rng, m)
            ref = copy(Γ0)
            ref[ix, :] .= R * ref[ix, :]
            ref[:, ix] .= ref[:, ix] * R'
            Γ = copy(Γ0)
            scratch = fill(NaN, N, N)             # staging only; contents must not matter
            @test QCM.conjugate_rows_cols!(Γ, R, ix, scratch) === Γ
            @test isequal(Γ, ref)                 # bit-for-bit (N < 2m exercises the fallback)
            # untouched block is untouched
            rest = [k for k in 1:N if !(k in ix)]
            @test isequal(Γ[rest, rest], Γ0[rest, rest])
        end
        @test_throws DimensionMismatch QCM.conjugate_rows_cols!(
            zeros(4, 4), zeros(3, 3), [
                1, 2], zeros(4, 4))
    end

    @testset "_purity_drift matches max|diag(Γ²)+1|" begin
        rng = MersenneTwister(5)
        @test QCM._purity_drift(QCM.vacuum_covariance(3)) == 0.0
        for N in (4, 10, 32)
            # pure random state: drift at roundoff level
            O = QCM.haar_orthogonal(rng, N)
            Γ = O * QCM.vacuum_covariance(N ÷ 2) * transpose(O)
            QCM.antisymmetrize!(Γ)
            @test QCM._purity_drift(Γ) ≈ maximum(abs.(diag(Γ * Γ) .+ 1)) atol = 1e-14
            @test QCM._purity_drift(Γ) < 1e-13
            # mixed / drifted state: an O(1) and an O(1e-6) drift
            @test QCM._purity_drift(zeros(N, N)) == 1.0
            noise = 1e-6 .* randn(rng, N, N)
            Γ .+= (noise .- noise') ./ 2
            @test QCM._purity_drift(Γ) ≈ maximum(abs.(diag(Γ * Γ) .+ 1)) atol = 1e-14
            @test 1e-7 < QCM._purity_drift(Γ) < 1e-4
        end
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

    @testset "parity_projection! == gaussian_contraction! with the parity projector" begin
        rng = MersenneTwister(2024)
        # Random pure Gaussian states (exactly antisymmetric, Γ² = -I), random
        # Majorana pairs in both orientations, both outcomes: the closed form
        # must agree with the general Schur-complement kernel to roundoff.
        for N in (4, 8, 20, 64), trial in 1:6

            O = QCM.haar_orthogonal(rng, N)
            Γ0 = O * QCM.vacuum_covariance(N ÷ 2) * transpose(O)
            QCM.antisymmetrize!(Γ0)
            a, b = randperm(rng, N)[1:2]
            for s in (+1, -1)
                g = Γ0[a, b]
                abs(1 - s * g) > 0.05 || continue   # keep the test away from ill-conditioned outcomes
                Γ_ref = copy(Γ0)
                QCM.gaussian_contraction!(Γ_ref, QCM.parity_projection_upsilon(s), [a, b])
                Γ_fast = copy(Γ0)
                @test QCM.parity_projection!(Γ_fast, a, b, s) === Γ_fast
                @test maximum(abs.(Γ_fast .- Γ_ref)) < 1e-13
                # exact (not just roundoff-level) antisymmetry, pure, correct sector
                @test Γ_fast == -transpose(Γ_fast)
                @test maximum(abs.(Γ_fast * Γ_fast + I)) < 1e-12
                @test Γ_fast[a, b] == -s && Γ_fast[b, a] == s
                @test all(iszero, Γ_fast[a, [k for k in 1:N if k != b]])
                @test all(iszero, Γ_fast[[k for k in 1:N if k != a], b])
            end
        end
    end

    @testset "parity_projection! on product states and golden conventions" begin
        # Cross-mode pair (2,3) on the vacuum: both outcomes have probability 1/2
        for s in (+1, -1)
            Γ = QCM.vacuum_covariance(2)
            QCM.parity_projection!(Γ, 2, 3, s)
            @test Γ == -transpose(Γ)
            @test maximum(abs.(Γ * Γ + I)) < 1e-12
            @test Γ[2, 3] == -s
            # The leftover Majoranas (1,4) pair up with the SAME parity: the
            # vacuum has total parity (iγ₁γ₂)(iγ₃γ₄) = +1 = (iγ₁γ₄)(iγ₂γ₃),
            # so iγ₁γ₄ = iγ₂γ₃ = -s.
            @test Γ[1, 4] == -s
        end
        # Intra-mode pair: vacuum IS the s = -1 outcome (probability 1) and is
        # left untouched
        Γ = QCM.vacuum_covariance(2)
        QCM.parity_projection!(Γ, 1, 2, -1)
        @test Γ == QCM.vacuum_covariance(2)
        # Vacuum pair projected onto the opposite parity: probability-zero outcome
        err = try
            QCM.parity_projection!(QCM.vacuum_covariance(2), 1, 2, +1)
            nothing
        catch e
            e
        end
        @test err isa ArgumentError
        @test occursin("vanishing state", err.msg)
        @test_throws ArgumentError QCM.parity_projection!(QCM.vacuum_covariance(2), 1, 2, 0)
        @test_throws ArgumentError QCM.parity_projection!(QCM.vacuum_covariance(2), 1, 1, 1)
        @test_throws ArgumentError QCM.parity_projection!(QCM.vacuum_covariance(2), 0, 1, 1)
    end

    @testset "parity_projection! re-purifies a drifted state when asked" begin
        rng = MersenneTwister(99)
        O = QCM.haar_orthogonal(rng, 12)
        Γ = O * QCM.vacuum_covariance(6) * transpose(O)
        QCM.antisymmetrize!(Γ)
        noise = 1e-7 .* randn(rng, 12, 12)
        Γ .+= (noise .- noise') ./ 2
        @test QCM._purity_drift(Γ) > 1e-10
        s = Γ[3, 8] > 0 ? -1 : +1          # the likelier outcome (well-conditioned)
        Γ_loose = copy(Γ)
        QCM.parity_projection!(Γ_loose, 3, 8, s; purify_tol = 1.0)   # never purifies
        @test QCM._purity_drift(Γ_loose) > 1e-10
        Γ_tight = copy(Γ)
        QCM.parity_projection!(Γ_tight, 3, 8, s; purify_tol = 1e-10)   # purifies
        @test QCM._purity_drift(Γ_tight) < 1e-12
        @test maximum(abs.(Γ_tight + Γ_tight')) == 0.0
        @test Γ_tight[3, 8] ≈ -s atol = 1e-6
    end
end
