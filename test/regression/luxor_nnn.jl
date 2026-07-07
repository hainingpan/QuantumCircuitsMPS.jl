# === Regression: Luxor extension NNN / non-adjacent gate rendering (v0.4 T15) ===
# Non-adjacent two-site gates (e.g. Bricklayer(:nnn)) must render as labeled
# boxes at BOTH endpoint qubits connected the SHORT way around:
#   - non-wrap pairs (e.g. (1,3)): solid connector between the inner box edges,
#     spanning exactly the skipped wire — never a floating label over other
#     gates packed into the same layer;
#   - PBC wrap pairs (e.g. (7,1) at L=8): dashed stubs from the endpoint boxes
#     out to the boundary edges — never a line spanning the middle of the
#     lattice (the old broken rendering drew (7,1) as a 6-qubit-wide dashed
#     line through the (3,5)/(4,6) gates with its label colliding at center).
# Structural assertions parse the SVG path data directly (style mirrors
# test/circuit_test.jl "SVG Multi-Qubit Spanning Box").
#
# Layout constants (must match ext/QuantumCircuitsMPSLuxorExt.jl):
#   MARGIN=50, QUBIT_SPACING=40, GATE_WIDTH=30, ROW_HEIGHT=60
#   → qubit q wire at global x = 50 + 40q; box half-width = 15.

using Test
using QuantumCircuitsMPS

# Extract all 2-point line segments as (x1, y1, x2, y2, dashed) tuples
function _svg_segments(svg::String)
    segs = NTuple{5, Float64}[]
    for el in eachmatch(r"<path[^>]*/>", svg)
        m = match(r"d=\"M ([0-9.]+) ([0-9.]+) L ([0-9.]+) ([0-9.]+) \"", el.match)
        m === nothing && continue
        dashed = contains(el.match, "stroke-dasharray")
        push!(segs,
            (parse(Float64, m[1]), parse(Float64, m[2]),
                parse(Float64, m[3]), parse(Float64, m[4]), Float64(dashed)))
    end
    return segs
end

# Horizontal (gate-connector) segments only; wires are vertical
_horizontal(segs) = [s for s in segs if s[2] == s[4] && s[1] != s[3]]

_qx(q) = 50.0 + 40.0 * q   # global x of qubit q's wire

@testset "Luxor NNN / non-adjacent rendering (regression)" begin
    luxor_ok = try
        Base.require(Main, :Luxor)
        true
    catch e
        if e isa ArgumentError && contains(string(e), "Package Luxor not found")
            false
        else
            rethrow(e)
        end
    end

    if !luxor_ok
        @test_skip "Luxor not available - skipping NNN SVG regression tests"
    else
        @testset "Bricklayer(:nnn) L=8 PBC: full structural check" begin
            circuit = Circuit(L = 8, bc = :periodic) do c
                apply!(c, HaarRandom(), Bricklayer(:nnn))
            end
            svg_path = tempname() * ".svg"
            plot_circuit(circuit; gates_spacetime = 0, filename = svg_path)
            svg = read(svg_path, String)
            rm(svg_path)

            @test contains(svg, "<svg")
            horiz = _horizontal(_svg_segments(svg))

            # Every connector spans exactly ONE skipped wire (or a boundary
            # stub): width ≤ 50 px. The broken rendering drew 210-px lines
            # across the lattice for the wrap pairs (7,1) and (8,2).
            @test !isempty(horiz)
            @test all(abs(s[3] - s[1]) <= 50.0 for s in horiz)

            # Non-wrap NNN pair (1,3): solid connector from q1 box right edge
            # to q3 box left edge (crossing skipped wire q2)
            @test any(s -> s[1] == _qx(1) + 15 && s[3] == _qx(3) - 15 &&
                          s[5] == 0.0, horiz)
            # (2,4), (5,7), (6,8) likewise (layer 1); (3,5), (4,6) (layer 2)
            for (i, j) in ((2, 4), (5, 7), (6, 8), (3, 5), (4, 6))
                @test any(s -> s[1] == _qx(i) + 15 && s[3] == _qx(j) - 15 &&
                              s[5] == 0.0, horiz)
            end

            # Wrap pair (7,1): DASHED stub from q7 box right edge to the right
            # boundary extent (q8 wire + 15). Left stub suppressed (q1 box
            # already touches the left boundary extent).
            @test any(s -> s[1] == _qx(7) + 15 && s[3] == _qx(8) + 15 &&
                          s[5] == 1.0, horiz)
            # Wrap pair (8,2): DASHED stub from the left boundary extent
            # (q1 wire - 15) to q2 box left edge
            @test any(s -> s[1] == _qx(1) - 15 && s[3] == _qx(2) - 15 &&
                          s[5] == 1.0, horiz)
            # Exactly these two dashed segments — nothing dashed spans the bulk
            dashed = [s for s in horiz if s[5] == 1.0]
            @test length(dashed) == 2

            # Endpoint boxes exist at BOTH sites of a non-adjacent pair:
            # box at qubit q is a closed rect x ∈ [qx-15, qx+15]. And no single
            # spanning box (width 110 = 2*40+30) exists — NNN gates must not
            # render like adjacent spanning boxes over the skipped wire.
            for q in 1:8
                @test contains(svg, "M $(round(Int, _qx(q) - 15)) ")
            end
            box_widths = [abs(parse(Float64, m[3]) - parse(Float64, m[1]))
                          for m in eachmatch(
                r"M ([0-9.]+) ([0-9.]+) L \1 [0-9.]+ L ([0-9.]+) [0-9.]+ L \3 \2 Z",
                svg)]
            @test !isempty(box_widths)
            @test all(w -> w <= 30.0 + 6, box_widths)  # gate boxes + label bgs only
        end

        @testset "wrap-pair-only case: Bricklayer(:nnn_odd_2) L=8 PBC" begin
            # pairs (3,5) and the PBC-wrapping (7,1)
            circuit = Circuit(L = 8, bc = :periodic) do c
                apply!(c, HaarRandom(), Bricklayer(:nnn_odd_2))
            end
            svg_path = tempname() * ".svg"
            plot_circuit(circuit; gates_spacetime = 0, filename = svg_path)
            svg = read(svg_path, String)
            rm(svg_path)

            horiz = _horizontal(_svg_segments(svg))
            # (3,5): solid inner-edge connector
            @test any(s -> s[1] == _qx(3) + 15 && s[3] == _qx(5) - 15 &&
                          s[5] == 0.0, horiz)
            # (7,1): dashed boundary stub, and NO segment through the bulk
            @test any(s -> s[1] == _qx(7) + 15 && s[3] == _qx(8) + 15 &&
                          s[5] == 1.0, horiz)
            @test all(abs(s[3] - s[1]) <= 50.0 for s in horiz)
        end

        @testset "open BC long-range gate is NOT treated as a wrap" begin
            # Sites([1,7]) at L=8 open BC: genuine long-range gate → solid
            # connector between the endpoints, no dashed boundary stubs
            circuit = Circuit(L = 8, bc = :open) do c
                apply!(c, HaarRandom(), Sites([1, 7]))
            end
            svg_path = tempname() * ".svg"
            plot_circuit(circuit; gates_spacetime = 0, filename = svg_path)
            svg = read(svg_path, String)
            rm(svg_path)

            horiz = _horizontal(_svg_segments(svg))
            @test any(s -> s[1] == _qx(1) + 15 && s[3] == _qx(7) - 15 &&
                          s[5] == 0.0, horiz)
            @test all(s -> s[5] == 0.0, horiz)
        end

        @testset "adjacent rendering unchanged (regression guard)" begin
            # Bricklayer(:even) L=4 PBC includes the wrap-adjacent pair (4,1):
            # adjacent gates keep their single-spanning-box / half-box style
            circuit = Circuit(L = 4, bc = :periodic) do c
                apply!(c, HaarRandom(), Bricklayer(:even))
            end
            svg_path = tempname() * ".svg"
            plot_circuit(circuit; gates_spacetime = 0, filename = svg_path)
            svg = read(svg_path, String)
            rm(svg_path)

            @test contains(svg, "<svg")
            # (2,3) renders as ONE spanning box of width 40+30=70
            box_widths = [abs(parse(Float64, m[3]) - parse(Float64, m[1]))
                          for m in eachmatch(
                r"M ([0-9.]+) ([0-9.]+) L \1 [0-9.]+ L ([0-9.]+) [0-9.]+ L \3 \2 Z",
                svg)]
            @test any(w -> w == 70.0, box_widths)
            # adjacent gates draw no connector lines — the only horizontal
            # segments are the wrap pair's half-box edges (width == GATE_WIDTH)
            @test all(abs(s[3] - s[1]) == 30.0 for s in _horizontal(_svg_segments(svg)))
        end
    end
end
