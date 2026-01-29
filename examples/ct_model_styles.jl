# CT Model - API Style Comparison
# ================================
# This file shows the EXACT SAME CT Model physics implemented in 4 different styles.
# All 4 styles produce IDENTICAL results when given the same seed.
# Run this file and choose your preferred syntax!
#
# The 4 styles are:
#   A: Action-Based (apply_stochastic!) - Gate+geometry unified in Action type
#   B: Categorical (apply_categorical!) - Simple tuple-based syntax
#   C: Named Parameters (apply_branch!) - Fully self-documenting
#   D: Macro DSL (@stochastic) - Reads like natural language

using Pkg; Pkg.activate(dirname(@__DIR__))
using QuantumCircuitsMPS

#= ============================================
   COMMON PARAMETERS (IDENTICAL FOR ALL STYLES)
   ============================================ =#

const L = 10
const p_ctrl = 0.5
const seed_C = 42
const seed_m = 123
const STEPS = 2 * L^2  # 200 steps

#= ============================================
   STYLE A: Action-Based (apply_stochastic!)
   ============================================
   
   Key Feature: Gate + Geometry combined into Action type
   
   Pros:
   - Action unifies what physicists think about as a single concept
   - Clear probability => action association
   
   Cons:
   - Requires Action() wrapper
   
   Usage:
     apply_stochastic!(state,
         p1 => Action(gate1, geo1),
         p2 => Action(gate2, geo2),
         ...
     )
=#

function run_style_a()
    left = StaircaseLeft(L)
    right = StaircaseRight(L)
    
    # Define actions (gate + geometry combined)
    reset_left = Action(Reset(), left)
    haar_right = Action(HaarRandom(), right)
    
    # Circuit step: "With prob p_ctrl, reset+left; else Haar+right"
    function circuit_step!(state, t)
        apply_stochastic!(state,
            p_ctrl => reset_left,
            (1-p_ctrl) => haar_right
        )
    end
    
    # i1 for DomainWall depends on current pointer position
    get_i1(state, t) = (current_position(left) % L) + 1
    
    # Run simulation
    results = simulate(
        L = L,
        bc = :periodic,
        init = ProductState(x0 = 1//2^L),
        rng = RNGRegistry(Val(:ct_compat), circuit=seed_C, measurement=seed_m),
        steps = STEPS,
        circuit! = circuit_step!,
        observables = [:DW1 => DomainWall(order=1), :DW2 => DomainWall(order=2)],
        i1_fn = get_i1
    )
    
    return results
end


#= ============================================
   STYLE B: Categorical/Tuple-Based (apply_categorical!)
   ============================================
   
   Key Feature: Simple Vector of (probability, gate, geometry) tuples
   
   Pros:
   - Simple, minimal syntax
   - No new types needed
   
   Cons:
   - Position-based within tuple (prob, gate, geo) order to memorize
   
   Usage:
     apply_categorical!(state, [
         (p1, gate1, geo1),
         (p2, gate2, geo2),
         ...
     ])
=#

function run_style_b()
    left = StaircaseLeft(L)
    right = StaircaseRight(L)
    
    # Circuit step using tuple syntax
    function circuit_step!(state, t)
        apply_categorical!(state, [
            (p_ctrl, Reset(), left),
            (1-p_ctrl, HaarRandom(), right)
        ])
    end
    
    get_i1(state, t) = (current_position(left) % L) + 1
    
    results = simulate(
        L = L,
        bc = :periodic,
        init = ProductState(x0 = 1//2^L),
        rng = RNGRegistry(Val(:ct_compat), circuit=seed_C, measurement=seed_m),
        steps = STEPS,
        circuit! = circuit_step!,
        observables = [:DW1 => DomainWall(order=1), :DW2 => DomainWall(order=2)],
        i1_fn = get_i1
    )
    
    return results
end


#= ============================================
   STYLE C: Fully Named Parameters (apply_branch!)
   ============================================
   
   Key Feature: Completely self-documenting with named parameters
   
   Pros:
   - Completely self-documenting
   - No memorization of argument order needed
   
   Cons:
   - More verbose, especially for simple cases
   - More typing required
   
   Usage:
     apply_branch!(state;
         rng = :ctrl,
         outcomes = [
             (probability=p1, gate=gate1, geometry=geo1),
             (probability=p2, gate=gate2, geometry=geo2),
             ...
         ]
     )
=#

function run_style_c()
    left = StaircaseLeft(L)
    right = StaircaseRight(L)
    
    # Circuit step using fully named parameters
    function circuit_step!(state, t)
        apply_branch!(state;
            rng = :ctrl,
            outcomes = [
                (probability=p_ctrl, gate=Reset(), geometry=left),
                (probability=1-p_ctrl, gate=HaarRandom(), geometry=right)
            ]
        )
    end
    
    get_i1(state, t) = (current_position(left) % L) + 1
    
    results = simulate(
        L = L,
        bc = :periodic,
        init = ProductState(x0 = 1//2^L),
        rng = RNGRegistry(Val(:ct_compat), circuit=seed_C, measurement=seed_m),
        steps = STEPS,
        circuit! = circuit_step!,
        observables = [:DW1 => DomainWall(order=1), :DW2 => DomainWall(order=2)],
        i1_fn = get_i1
    )
    
    return results
end


#= ============================================
   STYLE D: Macro/DSL (@stochastic)
   ============================================
   
   Key Feature: Reads like natural language
   
   Pros:
   - Reads like natural language
   - Cleanest syntax for expressing probabilistic branching
   
   Cons:
   - Macros are harder to debug
   - Less IDE support (autocomplete, type hints)
   
   Usage:
     @stochastic state :ctrl begin
         p1 => apply!(gate1, geo1)
         p2 => apply!(gate2, geo2)
         ...
     end
=#

function run_style_d()
    left = StaircaseLeft(L)
    right = StaircaseRight(L)
    
    # Circuit step using macro DSL
    function circuit_step!(state, t)
        @stochastic state :ctrl begin
            p_ctrl => apply!(Reset(), left)
            (1-p_ctrl) => apply!(HaarRandom(), right)
        end
    end
    
    get_i1(state, t) = (current_position(left) % L) + 1
    
    results = simulate(
        L = L,
        bc = :periodic,
        init = ProductState(x0 = 1//2^L),
        rng = RNGRegistry(Val(:ct_compat), circuit=seed_C, measurement=seed_m),
        steps = STEPS,
        circuit! = circuit_step!,
        observables = [:DW1 => DomainWall(order=1), :DW2 => DomainWall(order=2)],
        i1_fn = get_i1
    )
    
    return results
end


#= ============================================
   PHYSICS VERIFICATION
   ============================================
   
   All 4 styles use the same seed and parameters.
   They MUST produce identical DW values.
   This verifies that all styles correctly implement Contract 4.4
   (draw ONE random number BEFORE checking probabilities).
=#

if abspath(PROGRAM_FILE) == @__FILE__
    println("=" ^ 60)
    println("CT Model - API Style Comparison")
    println("=" ^ 60)
    println()
    println("Parameters: L=$L, p_ctrl=$p_ctrl, seed_C=$seed_C, seed_m=$seed_m, steps=$STEPS")
    println()
    
    println("Running Style A (apply_stochastic!)...")
    dw_a = run_style_a()
    
    println("Running Style B (apply_categorical!)...")
    dw_b = run_style_b()
    
    println("Running Style C (apply_branch!)...")
    dw_c = run_style_c()
    
    println("Running Style D (@stochastic)...")
    dw_d = run_style_d()
    
    println()
    println("=" ^ 60)
    println("PHYSICS VERIFICATION")
    println("=" ^ 60)
    println()
    println("Style A DW1[1:5]: ", dw_a[:DW1][1:5])
    println("Style B DW1[1:5]: ", dw_b[:DW1][1:5])
    println("Style C DW1[1:5]: ", dw_c[:DW1][1:5])
    println("Style D DW1[1:5]: ", dw_d[:DW1][1:5])
    
    # Check all match
    all_match = (dw_a[:DW1] == dw_b[:DW1] == dw_c[:DW1] == dw_d[:DW1]) &&
                (dw_a[:DW2] == dw_b[:DW2] == dw_c[:DW2] == dw_d[:DW2])
    
    println()
    println("All styles produce identical physics: ", all_match ? "✓ PASS" : "✗ FAIL")
    
    if !all_match
        println()
        println("MISMATCH DETAILS:")
        println("  DW1 match: A==B=$(dw_a[:DW1]==dw_b[:DW1]), B==C=$(dw_b[:DW1]==dw_c[:DW1]), C==D=$(dw_c[:DW1]==dw_d[:DW1])")
        println("  DW2 match: A==B=$(dw_a[:DW2]==dw_b[:DW2]), B==C=$(dw_b[:DW2]==dw_c[:DW2]), C==D=$(dw_c[:DW2]==dw_d[:DW2])")
    end
    
    #= ============================================
       STYLE COMPARISON TABLE
       ============================================ =#
    
    println("""
    
╔═══════════════════════════════════════════════════════════════════════════════╗
║                           API STYLE COMPARISON                                ║
╠═══════════╦═══════════════════════╦════════════════════════════════════════════╣
║ Style     ║ Pros                  ║ Cons                                       ║
╠═══════════╬═══════════════════════╬════════════════════════════════════════════╣
║ A: Action ║ • Gate+geometry       ║ • Requires Action() wrapper                ║
║           ║   unified             ║                                            ║
║           ║ • Clear probability   ║                                            ║
║           ║   association         ║                                            ║
╠═══════════╬═══════════════════════╬════════════════════════════════════════════╣
║ B: Tuple  ║ • Simple syntax       ║ • Position-based within tuple              ║
║           ║ • No new types        ║ • (prob, gate, geo) order to memorize      ║
╠═══════════╬═══════════════════════╬════════════════════════════════════════════╣
║ C: Named  ║ • Completely self-    ║ • Verbose for simple cases                 ║
║           ║   documenting         ║ • More typing                              ║
║           ║ • No memorization     ║                                            ║
╠═══════════╬═══════════════════════╬════════════════════════════════════════════╣
║ D: Macro  ║ • Reads like natural  ║ • Macros harder to debug                   ║
║           ║   language            ║ • Less IDE support                         ║
║           ║ • Cleanest syntax     ║                                            ║
╚═══════════╩═══════════════════════╩════════════════════════════════════════════╝

Please run this file and choose your preferred style!
    """)
end
