const _STATE_LOCK = ReentrantLock()
const _STATE_STACKS = Dict{UInt,Vector{SimulationState}}()

function _get_stack()
    tid = objectid(current_task())
    lock(_STATE_LOCK) do
        get!(() -> SimulationState[], _STATE_STACKS, tid)
    end
end

function with_state(f::Function, state::SimulationState)
    stack = _get_stack()
    push!(stack, state)
    try
        return f()
    finally
        pop!(stack)
    end
end

function current_state()
    stack = _get_stack()
    isempty(stack) && error("No active simulation context")
    return stack[end]
end

function forward(::AbstractCircuit)
    error("forward not implemented for circuit")
end

function simulate(
    circuit::AbstractCircuit;
    seed_circuit::Int=0,
    seed_meas::Int=0,
    x0::Union{Rational{Int},Rational{BigInt},Nothing}=nothing,
)
    state = SimulationState(L=circuit.L, seed_circuit=seed_circuit, seed_meas=seed_meas, x0=x0)
    with_state(state) do
        forward(circuit)
    end
    return state
end
