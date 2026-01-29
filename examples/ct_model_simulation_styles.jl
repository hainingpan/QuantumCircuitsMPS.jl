# CT Model - Simulation API Styles Comparison
# ============================================
# This file shows the EXACT SAME CT Model physics implemented in 3 simulation styles.
# All 3 styles produce IDENTICAL results when given the same seed.
# Run this file and choose your preferred syntax!
#
# The 3 styles are:
#   1: Imperative (explicit loop) - Maximum control, user manages loop
#   2: Callback (simulate_circuits) - Structure provided, on_circuit! callback
#   3: Iterator (CircuitSimulation) - Lazy evaluation, composable with Iterators
#
# Key concept: 1 circuit = L steps (one full sweep across system)
# So n_circuits = 2*L gives same total steps as steps = 2*L^2

using Pkg; Pkg.activate(dirname(@__DIR__))
using QuantumCircuitsMPS

# ============= COMMON PARAMETERS =============
const L = 10
const p_ctrl = 0.5
const seed_C = 42
const seed_m = 123
const N_CIRCUITS = 2 * L  # 20 circuits × 10 steps = 200 total steps
const RECORD_EVERY = 2    # Record every 2 circuits

# ============= STYLE 1: IMPERATIVE =============
function run_style1_imperative()
    left = StaircaseLeft(L)
    right = StaircaseRight(1)
    rng = RNGRegistry(Val(:ct_compat), circuit=seed_C, measurement=seed_m)
    
    state = SimulationState(L=L, bc=:periodic, rng=rng)
    initialize!(state, ProductState(x0 = 1//2^L))
    
    # i1_fn captured at registration - called automatically during record!
    get_i1() = (current_position(left) % L) + 1
    track!(state, :DW1 => DomainWall(order=1, i1_fn=get_i1))
    
    # Circuit step with renamed API
    circuit_step!(s) = apply_with_prob!(s; rng=:ctrl, outcomes=[
        (probability=p_ctrl, gate=Reset(), geometry=left),
        (probability=1-p_ctrl, gate=HaarRandom(), geometry=right)
    ])
    
    # Initial recording - no i1 needed!
    record!(state)
    
    # Plain loop - no run_circuit! wrapper
    for circuit in 1:N_CIRCUITS
        for _ in 1:L
            circuit_step!(state)
        end
        if circuit % RECORD_EVERY == 0
            record!(state)
        end
    end
    
    return state.observables[:DW1]
end

# ============= STYLE 2: CALLBACK =============
function run_style2_callback()
    left = StaircaseLeft(L)
    right = StaircaseRight(1)
    rng = RNGRegistry(Val(:ct_compat), circuit=seed_C, measurement=seed_m)
    
    circuit_step!(s) = apply_with_prob!(s; rng=:ctrl, outcomes=[
        (probability=p_ctrl, gate=Reset(), geometry=left),
        (probability=1-p_ctrl, gate=HaarRandom(), geometry=right)
    ])
    
    results = simulate_circuits(
        L = L,
        bc = :periodic,
        init = ProductState(x0 = 1//2^L),
        circuit_step! = circuit_step!,
        circuits = N_CIRCUITS,
        observables = [:DW1 => DomainWall(order=1)],
        rng = rng,
        on_circuit! = record_every(RECORD_EVERY),
        i1_fn = () -> (current_position(left) % L) + 1
        # NOTE: No reset_geometry! - staircases continue accumulating
    )
    
    return results[:DW1]
end

# ============= STYLE 3: ITERATOR =============
function run_style3_iterator()
    left = StaircaseLeft(L)
    right = StaircaseRight(1)
    rng = RNGRegistry(Val(:ct_compat), circuit=seed_C, measurement=seed_m)
    
    circuit_step!(s) = apply_with_prob!(s; rng=:ctrl, outcomes=[
        (probability=p_ctrl, gate=Reset(), geometry=left),
        (probability=1-p_ctrl, gate=HaarRandom(), geometry=right)
    ])
    
    get_i1() = (current_position(left) % L) + 1
    sim = CircuitSimulation(
        L = L,
        bc = :periodic,
        init = ProductState(x0 = 1//2^L),
        circuit_step! = circuit_step!,
        observables = [:DW1 => DomainWall(order=1, i1_fn=get_i1)],
        rng = rng
        # NOTE: No reset_geometry! - staircases continue accumulating
    )
    
    # Initial recording
    record!(sim.state)
    
    # Iterate with take() to limit circuits
    for (n, state) in enumerate(Iterators.take(sim, N_CIRCUITS))
        if n % RECORD_EVERY == 0
            record!(state)
        end
    end
    
    return get_observables(sim)[:DW1]
end

# ============= RUN AND COMPARE =============

println("=" ^ 70)
println("CT Model - Simulation API Styles Comparison")
println("=" ^ 70)
println()
println("Parameters:")
println("  L = $L")
println("  p_ctrl = $p_ctrl")
println("  seed_C = $seed_C, seed_m = $seed_m")
println("  N_CIRCUITS = $N_CIRCUITS (= 2*L)")
println("  RECORD_EVERY = $RECORD_EVERY circuits")
println()
println("Running simulations...")
println()

# Run all 3 styles
dw1_style1 = run_style1_imperative()
dw1_style2 = run_style2_callback()
dw1_style3 = run_style3_iterator()

# Verify exact equality
@assert dw1_style1 == dw1_style2 == dw1_style3 "Physics mismatch! Styles produced different results."

# Print results
println("✓ All 3 styles produce IDENTICAL results!")
println()
println("Results (first 5 DW1 values):")
println("  ", dw1_style1[1:5])
println()
println("Number of recordings: ", length(dw1_style1))
println("  Expected: ", 1 + div(N_CIRCUITS, RECORD_EVERY), " (initial + every $RECORD_EVERY circuits)")
println()
println("=" ^ 70)
println("Summary:")
println("=" ^ 70)
println()
println("Style 1 (Imperative):  User controls loop with explicit for _ in 1:L")
println("Style 2 (Callback):    Structure provided, record_every($RECORD_EVERY) callback")
println("Style 3 (Iterator):    Lazy evaluation with Iterators.take(sim, $N_CIRCUITS)")
println()
println("All styles verified to produce identical physics. Choose your preferred syntax!")
println()
