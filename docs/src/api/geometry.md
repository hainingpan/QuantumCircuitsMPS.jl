```@meta
CurrentModule = QuantumCircuitsMPS
```

# Geometry

Site-selection vocabulary — broadcast ("distribution") vs. set ("region")
geometries; see [Design Philosophy](@ref) for the conceptual split.

!!! note "1D only"
    All geometries address sites on a one-dimensional chain (`1:L`).
    Higher-dimensional (2D+) circuit geometries are a planned future
    direction — see the project
    [ROADMAP](https://github.com/hainingpan/QuantumCircuitsMPS.jl/blob/main/ROADMAP.md).

```@docs
AbstractGeometry
SingleSite
AdjacentPair
Sites
AllSites
EachSite
Bricklayer
StaircaseLeft
StaircaseRight
Pointer
move!
elements
element_count
is_broadcast
```
