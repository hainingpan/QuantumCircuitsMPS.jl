# test/verify_ct_match.jl

using JSON

# Load reference data (from CT.jl - Task 10)
ref_file = "test/reference/ct_reference_L10.json"
ref_data = JSON.parsefile(ref_file)
ref_dw1 = ref_data["DW1"]
ref_dw2 = ref_data["DW2"]

# Load new implementation output (from Task 8)
new_file = "examples/output/ct_model_L10_sC42_sm123.json"
new_data = JSON.parsefile(new_file)
new_dw1 = new_data["DW1"]
new_dw2 = new_data["DW2"]

# Verify array lengths match
@assert length(ref_dw1) == length(new_dw1) "DW1 length mismatch"
@assert length(ref_dw2) == length(new_dw2) "DW2 length mismatch"

# Compute maximum absolute differences
max_diff_dw1 = maximum(abs.(new_dw1 .- ref_dw1))
max_diff_dw2 = maximum(abs.(new_dw2 .- ref_dw2))

# Print results
println("CT Physics Verification")
println("="^50)
println("Reference: $ref_file")
println("New:       $new_file")
println()
println("DW1 max abs diff: $max_diff_dw1")
println("DW2 max abs diff: $max_diff_dw2")
println()

# Assert tolerance
tolerance = 1e-4
if max_diff_dw1 < tolerance && max_diff_dw2 < tolerance
    println("✅ PASS: Physics match within tolerance (\$tolerance)")
    exit(0)
else
    println("❌ FAIL: Physics mismatch exceeds tolerance (\$tolerance)")
    exit(1)
end
