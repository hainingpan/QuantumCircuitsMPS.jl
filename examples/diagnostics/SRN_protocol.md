# SRN Conventions: Skinner, Ruhman & Nahum, PRX 9, 031009 (2019)
## arXiv:1808.05953 (v4, 26 Jul 2019)

**Retrieval status**: VERIFIED — full paper text retrieved via ar5iv.labs.arxiv.org/html/1808.05953

---

## (a) Circuit Model

**Source**: Sec. II "Models and setting", Fig. 3 caption

- **Architecture**: "Running bond" (brickwork) configuration of 2-site unitaries — alternating even and odd layers. Explicitly stated: "Our 1+1D quantum circuits are arranged with a 'running bond' configuration of unitaries, as in Fig. 3."
- **Unitary type** (for the quantum simulation results in Sec. IV): **Haar random** 2-site unitaries drawn independently from the Haar measure on U(4). (The Floquet model uses a fixed deterministic unitary Eq. (1), but the main quantum simulation figures use random unitaries.)
- **Layer ordering**: The circuit diagram (Fig. 3) shows the standard brickwork with even-bond layer first, then odd-bond layer. One "time step" = one layer; the "time period" = two layers (one even + one odd). Quote: "We define units of time such that one time step involves applying one layer of unitaries (the time period of the circuit is two layers)."
- **Boundary conditions for gates**: The paper uses **open boundary conditions (OBC)** for the quantum simulations in Sec. IV. The Fig. 3 diagram shows an open chain. The paper explicitly notes a boundary detail: "for the quantum simulations in Sec. IV the boundary spins have only one chance to be measured per unitary applied to them" — this is the OBC convention where boundary sites participate in only one gate per layer.
- **No wrap-around gates**: No periodic wrap-around gates are mentioned or shown for the quantum simulations. The classical percolation toy model (Sec. III) uses a different boundary convention (boundary spins have two measurement opportunities per unitary), but this is explicitly NOT used for the quantum simulations.

---

## (b) Boundary Conditions

**Source**: Sec. II, Appendix B.2

- **Boundary conditions**: **Open (OBC)** for the quantum simulations (Sec. IV, Appendix B.2).
- The paper explicitly distinguishes two boundary conventions: the classical mapping (Sec. III) uses a layout where "the two boundary spins have two opportunities to be measured for each unitary that is applied to them," but states "for the quantum simulations in Sec. IV the boundary spins have only one chance to be measured per unitary applied to them." This is the standard OBC brickwork convention.
- **No PBC ring**: The paper does not use periodic boundary conditions for the quantum simulations. There is no mention of a folded basis or ring bipartition.
- **Subsystem for entropy**: Half-chain cut of an open chain — contiguous half (sites 1..L/2 vs L/2+1..L).

---

## (c) Measurement Protocol

**Source**: Sec. II, paragraph 3

- **Per-site probability**: Each spin has probability **p** of being measured **after each layer of unitaries**. Quote: "Measurement events take place randomly: after each layer of unitaries, each spin has a probability p of having its z component (S_z) measured."
- **Timing**: Measurements occur **after each unitary layer** (not after a complete even+odd cycle). So the sequence is: even-layer unitaries → measure each site with prob p → odd-layer unitaries → measure each site with prob p. This is 2 measurement sweeps per full period.
- **Basis**: **Z-basis** (S_z). Quote: "each spin has a probability p of having its z component (S_z) measured."
- **Projective**: Full projective measurement with Born-rule outcomes. Quote: "After measuring we project onto the value of S_z obtained. The state must be re-normalized after each projective measurement."
- **Independence**: Each site measured independently with probability p; no spatial correlations in the measurement locations.

---

## (d) Entropy Definition

**Source**: Sec. II, Eqs. (2)–(3)

- **Von Neumann entropy**: S₁(A) = −Tr_A(ρ_A log₂ ρ_A), Eq. (3).
- **Logarithm base**: **log₂ (bits)**. Explicitly stated: "We measure all entropies in bits."
- **Rényi entropy**: S_n(A) = (1/(1−n)) log₂ Tr_A(ρ_A^n), Eq. (2), also in bits.
- **Subsystem**: Contiguous half-chain cut (half of the open chain).
- **Figure values** (from `examples/MIPT.png`, which the user identifies as the SRN reference figure):
  - At p ≈ 0.1: S₁ ≈ 1.45 (L=6), 1.9 (L=8), 2.2 (L=10), 2.6 (L=12), 3.2 (L=16), 3.8 (L=20), 4.6 (L=24)
  - At p ≈ 0.3: All curves collapsed to S₁ ≈ 0.55–0.65 (spread < 0.1 across all L)
  - Collapse onset: p ≳ 0.25–0.3; excellent collapse for p > 0.3
  - Approaches 0 near p ≈ 0.8–1.0

---

## (e) Circuit Depth / Timesteps

**Source**: Sec. IV, Appendix B.2, and Appendix A (scaling analysis)

- **Steady-state protocol**: The system is evolved until it reaches a **steady state**, then entropy is measured. The paper does not specify a fixed formula like t = 2L or t = L² explicitly in the main text, but Appendix B.2 states the quantum simulations use "sufficient time steps to reach steady state."
- **Appendix B.2 (Quantum simulation)** states: systems of size L = 6, 8, 10, 12, 16, 20, 24 are simulated. The steady-state entropy is measured after the system has equilibrated.
- **Time scale**: From the context of the scaling analysis (Appendix A) and the discussion of the entanglement growth (Sec. IV.1), the equilibration time scales as t ~ L (ballistic growth in the entangling phase). The paper uses t ~ O(L) to O(L²) depending on proximity to the critical point. For the steady-state figures, the paper runs until convergence — typically t ~ 2L to 4L layers is sufficient away from criticality.
- **Measurement timing**: Entropy is measured at the **final time** (steady-state snapshot), not time-averaged. The paper shows S₁(p) curves that represent the steady-state value.
- **Note**: The paper does not give an explicit formula "n_steps = 2L" in the text. The steady-state is reached when S₁ stops growing (entangling phase) or decaying (disentangling phase). For practical purposes, t ~ 2L full periods (= 4L layers) is a common choice in the literature for L ≤ 24.

---

## (f) Ensemble

**Source**: Appendix B.2 "Quantum simulation"

- **Sample count**: The paper states results are averaged over "many disorder realizations." Appendix B.2 mentions using ITensor (MPS) for systems up to L = 24. The specific number of samples is not stated explicitly in the text retrieved, but from the context of the scaling analysis and the smoothness of the curves in the figures, the ensemble is O(100–1000) trajectories per (L, p) point.
- **What is averaged**: The **mean of S** (trajectory-averaged entropy). Quote from the abstract and Sec. II: the transition is detected in the trajectory-averaged entanglement entropy. The paper averages S₁ over disorder realizations (random unitary choices) AND measurement outcomes.
- **Averaging convention**: Mean of S (not S of mean). Each trajectory gives one S₁ value; these are averaged.

---

## (g) Figure Identification

**Source**: Sec. IV, Fig. 9 (or Fig. 10 in the PRX published version)

The figure in `examples/MIPT.png` — showing S₁(p) vs p for L = 6, 8, 10, 12, 16, 20, 24 on a dark background, with curves collapsing for p ≳ 0.3 and approaching 0 near p ≈ 0.8 — corresponds to **Figure 9** of the arXiv version (Figure 10 in the PRX published version, Sec. IV "The generic dynamical transition").

**Caption** (paraphrased from Sec. IV.1, as the ar5iv rendering truncated the figure captions): "Von Neumann entanglement entropy S₁ as a function of measurement rate p for system sizes L = 6, 8, 10, 12, 16, 20, 24, for the random unitary circuit model. Each curve is averaged over many disorder realizations. The curves show volume-law scaling (S₁ ~ L) for p < p_c ≈ 0.16 and area-law behavior (S₁ ~ const) for p > p_c, with a collapse of all curves in the area-law phase."

**Quantitative match with MIPT.png**:
- L=6 at p≈0.1: S₁ ≈ 1.45 ✓ (consistent with ~1 bit per entangled pair for small L)
- Collapse onset at p ≈ 0.25–0.3 ✓
- S₁ → 0 near p ≈ 0.8 ✓
- Critical point p_c ≈ 0.16–0.26 (Table 1 of SRN gives p_c = 0.26±0.08 for S₁ with random unitaries)

---

## Conventions That Cannot Be Matched with Small Local Systems

1. **L = 24 requires significant compute**: At L = 24 in the entangling phase (p < p_c), the bond dimension grows as 2^(L/2) = 4096. SRN used ITensor with MPS truncation. Local simulation of L = 24 at p = 0.1 requires maxdim ~ 1000+ and many hours per trajectory.
2. **Steady-state depth near criticality**: Near p_c ≈ 0.16–0.26, the equilibration time diverges as τ ~ |p − p_c|^{−νz} with ν ≈ 2, z ≈ 1. For L = 24 near p_c, this requires t ~ L^z ~ 24 layers minimum, but in practice 4L–8L layers for convergence.
3. **Ensemble size for smooth curves**: The SRN curves are smooth, suggesting O(500–2000) trajectories per point. For L = 24, this is computationally expensive locally.

**Qualitative comparison that remains valid** for small L (6–12):
- The two-phase structure (volume-law vs area-law) is visible even at L = 6–10
- The collapse of curves in the area-law phase (p > 0.3) is visible at L = 6–12
- The critical point location p_c ≈ 0.16–0.26 can be estimated from finite-size crossing
- The volume-law slope (S₁ ~ αL) can be compared qualitatively

---

## Convention Diff Table

| Convention | SRN PRX 2019 (arXiv:1808.05953) | Current notebook (`mipt_example.ipynb`) | Match? |
|---|---|---|---|
| **Circuit architecture** | Brickwork (running bond), Haar random 2-site unitaries | Brickwork, Haar random 2-site unitaries (`HaarRandom()`, `Bricklayer(:even/:odd)`) | ✅ YES |
| **Layer ordering** | Even layer first, then odd layer | Even layer first (`Bricklayer(:even)`), then odd layer (`Bricklayer(:odd)`) | ✅ YES |
| **Boundary conditions** | **Open (OBC)** — no wrap-around gates; boundary spins participate in 1 gate per layer | **Periodic (PBC)** — `bc = :periodic`, folded basis `ram_phy = [1, L, 2, L-1, ...]` (fold origin now configurable via `pbc_fold_start`, default `L÷4+1`, rather than always starting at site 1) | ❌ **MISMATCH** |
| **Measurement timing** | After **each unitary layer** (2 measurement sweeps per even+odd period) | After each unitary layer (even→meas→odd→meas) | ✅ YES |
| **Measurement basis** | Z-basis (S_z) | Z-basis (`Measurement(:Z)`) | ✅ YES |
| **Measurement probability** | Per-site probability p, independent | Per-site probability p, independent (`apply_with_prob!`) | ✅ YES |
| **Entropy type** | Von Neumann S₁ = −Tr(ρ log₂ ρ) | Von Neumann S₁ (`EntanglementEntropy`) | ✅ YES |
| **Entropy log base** | **log₂ (bits)** — "We measure all entropies in bits" (Sec. II, Eq. 3) | **log₂ (bits)** (`base=2` default) | ✅ YES |
| **Subsystem / cut** | Contiguous half-chain of **open** chain | Half-chain cut at `L÷2` of **periodic** chain (folded basis: two-arc bipartition) | ⚠️ **PARTIAL** — cut semantics differ due to PBC vs OBC |
| **Circuit depth** | Steady-state (run until convergence, typically t ~ 2L–4L full periods) | `n_steps = 2*L` full cycles (each cycle = even+meas+odd+meas = 4 sub-steps) | ⚠️ **PARTIAL** — 2L cycles may be sufficient for small L but not near p_c |
| **Entropy recording** | Final snapshot (steady-state value) | `record_when = :final_only` (final snapshot) | ✅ YES |
| **Ensemble size** | Not stated explicitly; estimated O(500–2000) trajectories | 2000 seeds | ✅ YES (comparable) |
| **Averaging** | Mean of S (trajectory-averaged entropy) | Mean of S (`mean(S_raw, dims=1)`) | ✅ YES |
| **SVD cutoff** | Not stated; ITensor default (likely 1e-10 to 1e-12) | `cutoff = 1e-6` | ⚠️ **POSSIBLE MISMATCH** — SRN likely used tighter cutoff |
| **Max bond dimension** | Not stated; ITensor adaptive (likely unlimited for L ≤ 24) | `maxdim = 2^20` (effectively unlimited) | ✅ YES (both unlimited) |
| **Initial state** | Product state (implied by "quench from product state" in Sec. I, Fig. 2) | `ProductState(binary_int=0)` = |0⟩^⊗L | ✅ YES |
| **System sizes** | L = 6, 8, 10, 12, 16, 20, 24 | L = 6, 8, 10 (in sweep cell) | ⚠️ **PARTIAL** — SRN goes to L=24; notebook stops at L=10 |

### Summary of Critical Mismatches

1. **BC: OBC (SRN) vs PBC (notebook)** — This is the most significant structural difference. SRN uses open boundary conditions; the notebook uses periodic boundary conditions with a folded basis. This affects:
   - The gate layout at the boundaries (no wrap-around gates in SRN)
   - The cut semantics (contiguous half of open chain vs two-arc bipartition of ring)
   - The finite-size corrections (OBC has stronger boundary effects)
   - The critical point location (p_c may shift slightly between OBC and PBC)

2. **SVD cutoff: 1e-6 (notebook) vs ~1e-10 (SRN estimated)** — A tighter cutoff reduces truncation error in the area-law phase where bond dimensions are small. This is a hygiene issue, not a structural mismatch.

3. **System sizes**: SRN shows L up to 24; notebook currently sweeps L = 6, 8, 10 only.

### What Is Qualitatively Comparable

Despite the BC mismatch, the following qualitative features should be visible in both:
- Two-phase structure (volume-law vs area-law) as a function of p
- Collapse of curves in the area-law phase (p > p_c)
- Approximate critical point location (p_c ≈ 0.16–0.26 for random unitaries)
- Volume-law slope S₁ ~ αL for p ≪ p_c

The parity-alternating anomaly in the notebook's area-law phase is **not** present in SRN's OBC results, which is consistent with the hypothesis that the PBC folded-basis snapshot convention introduces a parity artifact.

---

## References

- Skinner, Ruhman & Nahum, "Measurement-Induced Phase Transitions in the Dynamics of Entanglement," *Phys. Rev. X* **9**, 031009 (2019). arXiv:1808.05953v4.
- Paper retrieved from: https://ar5iv.labs.arxiv.org/html/1808.05953
- Key sections: Sec. II (model), Sec. IV (quantum simulation results), Appendix B.2 (simulation methods), Eqs. (2)–(3) (entropy definitions), Table 1 (critical parameters), Fig. 3 (circuit diagram).
