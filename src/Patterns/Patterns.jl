module Patterns

using ..Core: AbstractPattern, current_state
using ..Gates: apply!

export Bricklayer,
       StaircaseStep,
       pairs,
       bricklayer!,
       staircase_step!

struct Bricklayer <: AbstractPattern
    offset::Int
end

struct StaircaseStep <: AbstractPattern end

function pairs(pat::Bricklayer, L::Int)
    result = Tuple{Int,Int}[]
    start = 1 + pat.offset
    for i in start:2:(L - 1)
        push!(result, (i, i + 1))
    end
    if pat.offset == 1 && L > 1
        push!(result, (L, 1))
    end
    return result
end

function bricklayer!(gate; offset::Int=0)
    state = current_state()
    for (i, j) in pairs(Bricklayer(offset), state.L)
        apply!(gate, i, j)
    end
    return
end

function staircase_step!(gate)
    state = current_state()
    i = state.current_site
    j = mod(i, state.L) + 1
    apply!(gate, i, j)
    state.current_site = j
    return
end

end
