# Verified findings — CUFSAEAeroLapSim @ e5fd7e2 (2026-06-10)

Produced by static code review plus analysis of the committed sweep workbook and validation
artifacts. Line numbers are against e5fd7e2 — **re-verify against HEAD before patching**; if the
repo has moved, the repo wins and this file should be amended.

All sweep statistics below were computed from
`Lap Sim March 2026/Test Results/T27_AeroSweep_Multithreaded_Results.xlsx`,
sheet "All Results Ranked": 186 rows = 176 `Fast` + 10 `AccurateRerun`; 30 Fast rows feasible.

---

## F1 — Longitudinal load transfer effectively disabled (`/24`)  [BUG — fix in Phase 1]

File: `Lap Sim March 2026/Aero/Lap_Sim_constantAero_T27V4.m`

**Lines 333–334** (acceleration envelope, inside the Ax convergence loop). `wf`/`wr` here are
full-axle loads; downforce is added and the result halved to per-wheel a few lines later
(`wf = (wf+DFf)/2`):

```matlab
wf = WF-Ax*cg*WS/l/24;
wr = WR+Ax*cg*WS/l/24;
```

**Lines 676–679** (braking envelope, inside loop) — `/24` AND the term applied **twice**:

```matlab
wf = ((WF+DFf)/2)+(Ax*cg*WS/l/24);
wr = ((WR+DFr)/2)-(Ax*cg*WS/l/24);
wf = wf+Ax*cg*WS/l/24;
wr = wr-Ax*cg*WS/l/24;
```

**Line 654** (braking pre-loop seed) uses `wf = wf+Ax*cg*WS/l;` — per-wheel-correct form,
inconsistent with the loop it seeds.

**Physics.** Axle transfer is ΔW_axle = Ax·W·cg/l (Ax in g). With W=580 lbf, cg=12.2/12 ft,
l=60.5/12 ft: physical transfer at 1 g ≈ **117 lbf/axle**. As coded (WS=W/2, /24, halving),
the modeled effect is ≈1/48 of physical on the accel path and ≈1/24 (double-applied) in braking
— i.e. **longitudinal weight transfer is essentially OFF** in both envelopes.

**Corrected expressions** (single application, consistent with surrounding structure):

- Accel loop (replace 333–334; value is full-axle, halved later, so use full transfer):
  ```matlab
  wf = WF - Ax*W*cg/l;
  wr = WR + Ax*W*cg/l;
  ```
- Braking loop (replace 676–679 with one per-wheel application; with WS=W/2,
  `Ax*cg*WS/l` ≡ per-wheel ΔW = Ax·W·cg/(2l)):
  ```matlab
  wf = (WF+DFf)/2 + Ax*cg*WS/l;
  wr = (WR+DFr)/2 - Ax*cg*WS/l;
  ```

**Expected direction of change after fix:** braking capacity drops somewhat (tire load
sensitivity penalizes the now-modeled front-biased loading); grip-limited launch improves
slightly (rear axle gains load); CG height finally has real longitudinal sensitivity — this is
the likely root cause behind the PROJECT_TODOS item questioning CG-height behavior.

> **AMENDED 2026-06-12 (measured, pylapsim corrected mode — docs/PHYSICS_DELTA.md):**
> launch improves far more than "slightly" (accel event −8.7%, ≈ +22.5 pts everywhere);
> braking is essentially unchanged because the committed FX spline is ~load-linear over
> its fitted −50…−250 lbf range, so front-biased loading costs nothing in this tire model;
> skidpad drops slightly (−3.2 pts mean) via the relaxed rear drag-ellipse penalty shifting
> yaw balance. CG-height sensitivity claim confirmed.

---

## F2 — Efficiency event missing → drag is nearly free  [MODEL GAP]

The sim scores 575 of 675 dynamic points (Endurance 275, Autocross 125, Skidpad 75, Accel 100).
The absent **Efficiency 100** is the only score that punishes drag.

Evidence (Fast rows, n=176): Pearson r with Total_Points — **CL +0.892, CoP +0.345, CD −0.253**.
Sweeping CD 0.0150→0.0300 at CL 0.050 / CoP 0.475 costs only **376.85 → 367.71 = 9.1 pts** while
60 mph drag doubles from 116.2 → 232.3 lbf (≈0.079 pts per lbf @ 60 mph). With efficiency
modeled, drag's true cost is materially higher.

---

## F3 — Recommendation pinned at constraint and grid edges  [STUDY-DESIGN GAP]

Best feasible (Fast): **CL 0.050 / CD 0.0225 / CoP 0.525 → 380.03 pts**, sitting at
**131.8 of the 135 lbf** DF@35 mph cap and at the **CoP grid edge** with points still rising
monotonically (CL 0.050, CD 0.0225):

| CoP_target | 0.425 | 0.450 | 0.475 | 0.500 | 0.525 |
|---|---|---|---|---|---|
| Total_Points | 363.96 | 369.33 | 372.94 | 376.20 | 380.03 |

Best overall is the off-grid baseline CL 0.080 / CD 0.020 / CoP 0.450 → **418.29** (its
AccurateRerun: 417.35). The current "answer" is therefore the feasibility window itself —
PROJECT_TODOS already flags that window as placeholder. The CoP range must be extended upward
until the optimum turns interior or a stated physical limit binds.

---

## F4 — Fast-pass resolution noise: ±3.95 pts

The 10 Fast-vs-AccurateRerun pairs give ΔTotal (fast − accurate):

```
[0.94, −0.66, 0.13, −1.01, −0.70, −0.11, 0.50, −0.51, −0.70, −3.95]   mean −0.61, max |Δ| 3.95
```

Any fast-pass ranking gap below ~4 pts is a tie, not a ranking. Note CD's entire effect (F2)
is only ~2× this band.

---

## F5 — Mass not coupled to the aero package  [MODEL GAP]

W = 580 lbf for every CL_target. A bigger wing package costs real pounds and real points.
Treat added-package mass as a **scenario parameter** (team-supplied or cited bracket), never a
guessed constant.

---

## F6 — Diminishing returns in CL (real, from committed data)

At CD 0.020 / CoP 0.475, CL 0.035→0.055:

| CL_target | 0.035 | 0.040 | 0.045 | 0.050 | 0.055 |
|---|---|---|---|---|---|
| Total_Points | 348.15 | 356.44 | 368.24 | 374.23 | 376.93 |

Step gains +8.3 / +11.8 / +6.0 / +2.7 — flattening right around the feasibility cap
(135 lbf @35 mph ⇒ CL ≤ 0.0512).

---

## F7 — Minor / hygiene (address opportunistically)

- `sf_x = 0.45`, `sf_y = 0.50` tire scaling is conservative; treat as calibration parameters
  (the team's validation plan in PROJECT_TODOS covers this).
- Racing line is fixed across aero cases (README acknowledges); fine for relative comparisons;
  consider line re-optimization for finalist candidates only.
- 2019 Tmin score anchors hardcoded in Section 17.
- Lateral envelope records results even when the step-back fmincon solve fails
  (exitflag < 1) — rows should be flagged.
- `gear` global reuse, mixed unit conversions, legacy `xlswrite` I/O — all resolved naturally
  by the Python port.

---

## Fixed-in-V4 — do NOT chase (stale copies of these files circulate)

- `a` (front-axle-to-CG distance) clobbered to 1 by the ride-rate calc before the first
  cornering radius (V2 bug; V4 renamed the variable).
- Hardcoded CL/CD/CoP after a top-of-file `clear` made the old `Run_T27_AeroSweep.m` sweep a
  no-op (V2 chain).
- Missing `CL_over_CD` / `BalanceError` columns crashed the old runner's ranking.

**Current chain = `Lap_Sim_constantAero_T27V4.m` + `Run_T27_AeroSweep_MultithreadedExcel.m`.**
Earlier sim versions V1–V3 and `untitled2.m` were removed from the working tree in cleanup (they
remain in git history). Other legacy/scratch files (`Run_T27_AeroSweep.m`, `*_FastExcel.m`,
`Lap_Sim.m`, `tank.m`, `Troubleshooting.m`) remain — leave them alone.

---

## Physical-units bridge (use in all reports)

The sim's coefficients are force coefficients: DF = CL_target·V², drag = CD_target·V²
(V in ft/s, force in lbf). Conversion to dimensional CL·A with ρ = 0.002377 slug/ft³
(standard sea level):

```
CL·A [ft²] = CL_target / (0.5·ρ) = CL_target / 0.0011885      CL·A [m²] = ft² × 0.092903
```

Examples: baseline 0.080 → 67.3 ft² → **6.25 m²** (top of anything published for FSAE);
feasibility cap 0.0512 → **4.00 m²**; best-feasible CD 0.0225 → CD·A **1.76 m²**, L/D 2.22.
Cite the density assumption whenever these appear.
