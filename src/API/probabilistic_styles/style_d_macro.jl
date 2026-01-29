#=
Style D: DSL Macro
==================

Philosophy: DSL that reads like natural language physics descriptions

Pros:
- Reads like natural language: "with probability p, apply gate to geometry"
- Cleanest syntax for expressing probabilistic branching
- Supports N-way branching within the DSL block

Cons:
- Macros are harder to debug (less helpful error messages)
- Less IDE support (autocomplete, type hints)
- Macro hygiene can be surprising if not understood

When to Use:
Choose this if you want code that reads like physics prose and don't mind macro limitations

See also: examples/ct_model_styles.jl for side-by-side comparison
=#

# This file is meant to be included in the QuantumCircuitsMPS module context
# where AbstractGate, AbstractGeometry, and SimulationState are already defined.
# It should NOT be loaded standalone.

"""
    @stochastic state rng begin
        prob1 => apply!(gate1, geo1)
        prob2 => apply!(gate2, geo2)
        ...
    end

DSL-style probabilistic branching that reads like natural language.

CRITICAL: Per Contract 4.4, this macro generates code that ALWAYS draws ONE random 
number from the specified RNG stream BEFORE checking probabilities. This ensures 
deterministic RNG advancement regardless of which branch is taken.

Arguments:
- state: SimulationState expression
- rng: Symbol identifying the RNG stream (e.g., :ctrl)
- block: Block of `probability => apply!(gate, geo)` statements

Example (binary):
    @stochastic state :ctrl begin
        p_ctrl => apply!(Reset(), left)
        (1-p_ctrl) => apply!(HaarRandom(), right)
    end

Example (3-way):
    @stochastic state :ctrl begin
        0.25 => apply!(PauliX(), site)
        0.25 => apply!(PauliY(), site)
        0.50 => apply!(Identity(), site)
    end

NOTE: The macro captures 'apply!' calls and transforms them into 
conditional execution based on the drawn random number.
"""
macro stochastic(state_expr, rng_expr, block)
    # Validate block is a begin...end
    if !isa(block, Expr) || block.head != :block
        error("@stochastic requires a begin...end block as third argument")
    end
    
    # Parse the block to extract probability => action pairs
    pairs = Tuple{Any, Any, Any}[]  # (prob, gate, geo)
    for line in block.args
        # Skip LineNumberNode entries
        if isa(line, LineNumberNode)
            continue
        end
        
        # Match: prob => apply!(gate, geo)
        if isa(line, Expr) && line.head == :call && line.args[1] == :(=>)
            prob = line.args[2]
            action_call = line.args[3]
            
            # Validate action is apply!(gate, geo)
            if isa(action_call, Expr) && action_call.head == :call && action_call.args[1] == :apply!
                if length(action_call.args) != 3
                    error("@stochastic: apply! must have exactly 2 arguments (gate, geo), got $(length(action_call.args) - 1)")
                end
                gate = action_call.args[2]
                geo = action_call.args[3]
                push!(pairs, (prob, gate, geo))
            else
                error("@stochastic: Expected apply!(gate, geo), got $(action_call)")
            end
        else
            error("@stochastic: Expected 'prob => apply!(gate, geo)', got $(line)")
        end
    end
    
    if isempty(pairs)
        error("@stochastic: No probability => apply! pairs found in block")
    end
    
    # Generate unique symbols for hygiene
    state_sym = gensym("state")
    rng_sym = gensym("rng")
    actual_rng_sym = gensym("actual_rng")
    r_sym = gensym("r")
    cumulative_sym = gensym("cumulative")
    done_label = gensym("done")
    
    # Build the conditional branches
    branch_exprs = map(pairs) do (prob, gate, geo)
        quote
            $cumulative_sym += $(esc(prob))
            if $r_sym < $cumulative_sym
                apply!($state_sym, $(esc(gate)), $(esc(geo)))
                @goto $done_label
            end
        end
    end
    
    # Generate the complete runtime code
    result = quote
        let $state_sym = $(esc(state_expr)), $rng_sym = $(esc(rng_expr))
            $actual_rng_sym = get_rng($state_sym.rng_registry, $rng_sym)
            # CRITICAL: Draw random number BEFORE checking probabilities
            $r_sym = rand($actual_rng_sym)
            $cumulative_sym = 0.0
            
            $(branch_exprs...)
            
            # Edge case: r exactly equals 1.0 (extremely rare) - execute last branch
            # This is already handled by the loop but we need the label
            @label $done_label
            nothing
        end
    end
    
    return result
end
