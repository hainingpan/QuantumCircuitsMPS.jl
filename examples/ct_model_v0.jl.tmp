# CT Model Example - v2 API
# Reproduces CT.jl's run_CT_MPS_C_m_T.jl random_control! algorithm
# For verification against reference implementation

# Module loading (Contract 6)
# Use joinpath with @__DIR__ to get correct path from examples/
const PROJECT_ROOT = dirname(@__DIR__)
include(joinpath(PROJECT_ROOT, "src/v2/QuantumCircuitsMPSv2.jl"))
using .QuantumCircuitsMPSv2
using ITensors, ITensorMPS
using JSON

# ============================================================================
# Helper Functions
# ============================================================================

"""
    reset!(state, site::Int, outcome::Int)

Perform CT.jl Reset operation: Projection to observed outcome, then X if outcome was 1.
This resets the qubit to |0⟩ state after measurement.

CT.jl R! algorithm (lines 232-245):
1. P! - Apply projection with observed outcome
2. If outcome == 1, apply X to flip back to |0⟩
"""
function reset!(state, site::Int, outcome::Int)
    # Apply Projection with the observed outcome
    apply!(state, Projection(outcome), SingleSite(site))
    
    # If outcome was 1, apply X to reset to |0⟩
    if outcome == 1
        apply!(state, PauliX(), SingleSite(site))
    end
    
    return nothing
end

"""
    random_control_step!(state, i::Int, p_ctrl::Float64, p_proj::Float64) -> Int

CT.jl random_control! algorithm (lines 363-414).
Returns the new pointer position.

CRITICAL RNG SEQUENCE (must match exactly for verification):
1. rand(ct.rng_C) < p_ctrl  -- Control vs Bernoulli decision
2. If Control: rand(ct.rng_m) -- Born outcome
3. If Bernoulli: HaarRandom uses rng_C (via :haar which is aliased to :ctrl in ct_compat mode)
4. If Bernoulli AND p_proj > 0: rand(ct.rng_C) for projection decision
"""
function random_control_step!(state, i::Int, p_ctrl::Float64, p_proj::Float64)
    L = state.L
    rng = state.rng_registry
    
    # 1. Control vs Bernoulli decision
    if rand(get_rng(rng, :ctrl)) < p_ctrl
        # === CONTROL BRANCH (CT.jl lines 366-391) ===
        
        # 2. Born probability at site i
        p_0 = born_probability(state, i, 0)
        
        # 3. Sample outcome using :born stream
        outcome = rand(get_rng(rng, :born)) < p_0 ? 0 : 1
        
        # 4. Apply Reset (Projection + conditional X)
        reset!(state, i, outcome)
        
        # 5. Move pointer LEFT: i = mod((i-1) - 1, L) + 1
        i = mod((i - 1) - 1, L) + 1
    else
        # === BERNOULLI BRANCH (CT.jl lines 392-397) ===
        
        # 2. Apply HaarRandom to (i, i+1) with PBC wrap
        # Note: HaarRandom uses :haar stream which is aliased to :ctrl in ct_compat mode
        apply!(state, HaarRandom(), AdjacentPair(i))
        
        # 3. Move pointer RIGHT: i = mod(i, L) + 1
        i = mod(i, L) + 1
        
        # 4. PROJECTION (CT.jl lines 399-410) - ONLY if p_proj > 0
        # Check positions (i-1) and i for projection
        if p_proj > 0
            for pos in [i - 1, i]
                # Wrap position for PBC
                wrapped_pos = mod(pos - 1, L) + 1
                
                # RNG draw for projection decision (uses :proj which is aliased to :ctrl)
                if rand(get_rng(rng, :proj)) < p_proj
                    p_0 = born_probability(state, wrapped_pos, 0)
                    outcome = rand(get_rng(rng, :born)) < p_0 ? 0 : 1
                    apply!(state, Projection(outcome), SingleSite(wrapped_pos))
                end
            end
        end
    end
    
    return i
end

# ============================================================================
# Main Simulation Function
# ============================================================================

"""
    run_dw_t(L, p_ctrl, p_proj, seed_C, seed_m) -> Dict

Run CT model simulation and return domain wall time series.
Reproduces CT.jl's run_dw_t function (lines 26-57).

Parameters:
- L: System size
- p_ctrl: Probability of control (vs Bernoulli)
- p_proj: Probability of projection after Bernoulli (0 for verification)
- seed_C: Seed for circuit RNG (ctrl/haar/proj streams)
- seed_m: Seed for measurement RNG (born stream)

Returns Dict with keys:
- "L", "p_ctrl", "p_proj", "seed_C", "seed_m": Parameters
- "DW1": First-order domain wall time series
- "DW2": Second-order domain wall time series
"""
function run_dw_t(L::Int, p_ctrl::Float64, p_proj::Float64, seed_C::Int, seed_m::Int)
    # Setup with ct_compat mode (aliases :ctrl, :proj, :haar to same RNG)
    rng = RNGRegistry(Val(:ct_compat), circuit=seed_C, measurement=seed_m)
    state = SimulationState(L=L, bc=:periodic, rng=rng)
    
    # Initialize: x0 = 1/2^L means only site L has "1", rest "0"
    # CT.jl line 27: x0=1//2^L
    initialize!(state, ProductState(x0=1//2^L))
    
    # Initial pointer at last site (CT.jl line 33)
    i = L
    
    # Total time steps: 2*L^2 (CT.jl line 34)
    tf = 2 * L^2
    
    # Preallocate DW arrays (CT.jl line 35)
    dw_list = zeros(tf + 1, 2)
    
    # Initial DW at i1=1 (CT.jl line 36: CT.dw(ct,1))
    dw_list[1, :] = [DomainWall(order=1)(state, 1), DomainWall(order=2)(state, 1)]
    
    # Main loop (CT.jl lines 42-44)
    for idx in 1:tf
        i = random_control_step!(state, i, p_ctrl, p_proj)
        
        # DW sampling site is AHEAD of pointer (CT.jl line 44)
        # i1 = (i % L) + 1
        i1 = (i % L) + 1
        
        dw_list[idx + 1, :] = [DomainWall(order=1)(state, i1), DomainWall(order=2)(state, i1)]
    end
    
    return Dict(
        "L" => L,
        "p_ctrl" => p_ctrl,
        "p_proj" => p_proj,
        "seed_C" => seed_C,
        "seed_m" => seed_m,
        "DW1" => dw_list[:, 1],
        "DW2" => dw_list[:, 2]
    )
end

# ============================================================================
# Main Execution
# ============================================================================

if abspath(PROGRAM_FILE) == @__FILE__
    # Test parameters for verification (matches CT.jl reference)
    L = 10
    p_ctrl = 0.5
    p_proj = 0.0  # CRITICAL: Must be 0.0 for verification
    seed_C = 42
    seed_m = 123
    
    println("Running CT model: L=$L, p_ctrl=$p_ctrl, p_proj=$p_proj, seed_C=$seed_C, seed_m=$seed_m")
    println("Total steps: $(2 * L^2)")
    
    @time results = run_dw_t(L, p_ctrl, p_proj, seed_C, seed_m)
    
    # Save to JSON
    output_dir = joinpath(PROJECT_ROOT, "examples/output")
    mkpath(output_dir)
    output_file = joinpath(output_dir, "ct_model_L$(L)_sC$(seed_C)_sm$(seed_m).json")
    open(output_file, "w") do f
        JSON.print(f, results, 4)  # Pretty-print with indent=4
    end
    
    println("\nResults saved to: $output_file")
    println("DW1 length: ", length(results["DW1"]))
    println("DW2 length: ", length(results["DW2"]))
    println("\nFirst 5 DW1 values: ", results["DW1"][1:5])
    println("Last 5 DW1 values: ", results["DW1"][end-4:end])
end
