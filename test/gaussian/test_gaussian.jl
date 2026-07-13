# test/gaussian/test_gaussian.jl
# Master include for the Gaussian (free-fermion covariance-matrix) backend
# test suite. Mirrors test/clifford/test_clifford.jl's role: one entry point
# organizing every per-feature test file into named @testset's.
#
# Run standalone:
#   julia --project=. -e 'include("test/gaussian/test_gaussian.jl")'
#
# NOTE: oracle.jl is a HELPER file (top-level function definitions, no
# @testset) — it is included here once as a dependency. Several files below
# re-include it (some guarded, some not); re-inclusion just overwrites the
# same top-level methods, which is harmless.

using Test
using QuantumCircuitsMPS

# ED/Pfaffian test oracle (T5) — dependency, NOT a testset.
include(joinpath(@__DIR__, "oracle.jl"))

@testset "Gaussian Backend" begin
    @testset "Construction" begin
        include(joinpath(@__DIR__, "test_construction.jl"))
    end
    @testset "Numerical Kernel" begin
        include(joinpath(@__DIR__, "test_kernel.jl"))
    end
    @testset "Gate Types" begin
        include(joinpath(@__DIR__, "test_gates.jl"))
    end
    @testset "RandomGaussianState Spec" begin
        include(joinpath(@__DIR__, "test_random_init_spec.jl"))
    end
    @testset "ED/Pfaffian Oracle" begin
        include(joinpath(@__DIR__, "test_oracle.jl"))
    end
    @testset "Initialization" begin
        include(joinpath(@__DIR__, "test_initialization.jl"))
    end
    @testset "Gate Application" begin
        include(joinpath(@__DIR__, "test_apply.jl"))
    end
    @testset "Measurement" begin
        include(joinpath(@__DIR__, "test_measurement.jl"))
    end
    @testset "Observables (EE + Magnetization)" begin
        include(joinpath(@__DIR__, "test_observables.jl"))
    end
    @testset "Observable Rejections" begin
        include(joinpath(@__DIR__, "test_rejections.jl"))
    end
    @testset "BondParity Measurement" begin
        include(joinpath(@__DIR__, "test_bond_parity.jl"))
    end
    @testset "Mutual Information (MI + TMI)" begin
        include(joinpath(@__DIR__, "test_mutual_information.jl"))
    end
    @testset "Majorana Chain Granularity" begin
        include(joinpath(@__DIR__, "test_majorana_chain.jl"))
    end
    @testset "Python Golden Values" begin
        include(joinpath(@__DIR__, "golden_values.jl"))
    end
end  # top-level @testset
