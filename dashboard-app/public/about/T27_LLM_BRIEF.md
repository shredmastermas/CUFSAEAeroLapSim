# T27 Aero Target Study — LLM Briefing / Platform Prompt

> Paste this whole file to an LLM to bring it up to speed on the platform. It is a
> condensed, current snapshot; the repository docs cited at the end are ground truth.

## 1. What this is

A lap-simulation + dashboard system that recommends a Clemson FSAE (CUFSAE) **aero
target** — `(CL, CD, CoP)` — maximizing total points over Acceleration, Skidpad,
Autocross, Endurance (Efficiency is currently unscored). The deliverable is a total
downforce/drag/balance target for CFD + component design, not a wing design.

- **Engine:** `pylapsim` (Python) — a port of MATLAB `Lap_Sim_constantAero_T27V4.m`
  + sweep runner `Run_T27_AeroSweep_MultithreadedExcel.m`. Quasi-steady lap solver
  with a tensor-spline tire model, fixed-point GGV envelopes, and a points model.
- **Front-end:** a single-file React dashboard (`handover/dashboard/t27-aero-dashboard.jsx`)
  hosted by a Vite app (`dashboard-app/`). Data is embedded as JS consts
  (`META`, `SWEEP0`, `TRACE0`, `PAIRS`) and can also be live-loaded via the workbook/trace
  upload buttons.

## 2. Data pipeline (how to regenerate everything)

1. `scripts/run_hires_sweep.py` → runs a CORRECTED factorial sweep over a CL×CD×CoP
   grid (editable at the top of the file), writes
   `Lap Sim March 2026/Test Results/python/T27_AeroSweep_hires_corrected.xlsx`.
2. `pylapsim run --cl .. --cd .. --cop .. --corrected --preset High --out-dir DIR`
   → writes one lap-telemetry trace CSV (Endurance + Autocross channels).
3. `scripts/build_dashboard_data.py` → reads the workbook + trace, mirrors the
   dashboard's own parsers, and splices `META`/`SWEEP0`/`TRACE0`/`PAIRS` into the jsx.
4. `scripts/analyze_t26.py` → prints the T26 comparison (rank, beat-at-same-CL,
   realistic-L/D frontier).
- CLI: `python -m pylapsim {run|sweep|validate}`. **`--legacy` is the default and
  reproduces the F1 bug; always pass `--corrected` for real work.**

## 3. Validation status

- pylapsim vs MATLAB (committed artifacts, `docs/VALIDATION.md`): Endurance / Skidpad
  / Acceleration times and Max|AY|, Max/Min AX all match to **~1e-6**; endurance
  speed trace is bit-for-bit; sweep total-points Spearman **0.9948**.
- **Open hole — autocross geometry:** the committed sweep/trace embed a 2334.1 ft
  autocross path that cannot be reconstructed from the committed inputs
  (`Autocross_Coordinates_2.xlsx` + `autocross_racing_line.mat` give 2727.95 ft,
  confirmed to 1e-10 against committed `.mat` workspaces). The corrected re-run uses
  the committed coordinates (2728 ft) — self-consistent but differs from the legacy
  oracle. Autocross absolute values are the least-trusted numbers.
- The MATLAB F1 fix is **parity-checked via the Python port, not yet re-run in MATLAB**.

## 4. Assumption register (every non-measured input)

| Assumption | Value | Status |
|---|---|---|
| Feasibility | **none** — no feasible/infeasible verdict; judge targets by L/D | was a placeholder window (DF 90–135, drag 40–65, L/D 2.0–2.4), then a floor-only DF ≥ 90 lbf @35 mph; the grid starts at the floor so it filtered nothing → binary removed entirely 2026-06-13. Real bound is a measured CL–CD polar (not available). |
| Physics mode | corrected (F1 `/24` fix) | parity-checked vs MATLAB, not re-run in MATLAB |
| Tire scale `sf_x/sf_y` | 0.45 / 0.50 | V4 committed calibration, uncorrelated (F7); dominates UQ |
| Score anchors | 2019 Michigan: End 115.249 / Auto 48.799 / Skid 4.865 / Accel 4.109 s | historical; scores are relative rankings |
| `bsfc_g_per_kWh` | null → Efficiency_Score null | team input required; Efficiency event unscored |
| `rho` | 0.002377 slug/ft³ | standard sea-level air |
| `k_mass` (mass–CL coupling) | {0, 250, 500} lbf/CL scenario bracket | unsourced; optimum unmoved; baseline run uses 0 |
| A_Y sign convention | positive A_Y loads the right side | undocumented in MATLAB source; assumed |
| Vehicle constants | W 580 lbf, static front 47.4%, CG h 1.017 ft, wheelbase 5.042 ft, mean track 3.875 ft | from V4; not independently re-validated |
| FX tire range | fitted to FZ ≥ −250 lbf | corrected high-DF cases extrapolate (cubic) beyond it |

## 5. Known limitations / places for improvement (from `PROJECT_TODOS.md`)

- **Add a CFD/measured CL–CD polar as the buildability bound** — the binary feasibility
  verdict was removed (it was a placeholder); the unconstrained optimum is an implausibly
  efficient wing, and a real CD_min(CL) polar is the only honest way to bound it.
- **Resolve the autocross oracle provenance** (regenerate from committed inputs, or
  commit the coordinates that produced the 2334 ft path).
- **Run the MATLAB F1 fix in MATLAB** to close the validation loop.
- **Acquire/fit TTC FX tire data for FZ −250…−350 lbf** to remove the high-DF extrapolation.
- **Add a braking-stability model** — the corrected CoP optimum is forward (~0.575+);
  rear-axle margin under braking is not modeled.
- **Supply BSFC + efficiency anchors** to populate the Efficiency event (formula is
  implemented from FSAE Rules 2026 §D.13.4, currently null).
- **Real ride-height-dependent aero map** instead of constant-aero targets.
- **CG-height sensitivity study** (now meaningful post-F1-fix).

## 6. Sources

- **Repo:** github.com/shredmastermas/CUFSAEAeroLapSim
- **MATLAB sim:** `Lap Sim March 2026/` — `Lap_Sim_constantAero_T27V4.m`,
  `Run_T27_AeroSweep_MultithreadedExcel.m`.
- **Tire data:** `Tire Data/A2356run008_MF52_Fy_12.mat`, `_GV12.mat`,
  `Hoosier R20 18x6.0-10 10 Psi FX.mat`.
- **Track geometry:** `Sim Data/Endurance_Coordinates_1.xlsx`,
  `Autocross_Coordinates_2.xlsx`, `endurance_racing_line.mat`, `autocross_racing_line.mat`.
- **Rules:** FSAE Rules 2026 V1.0 (fsaeonline.com) — §D.13.4 (efficiency),
  §T.7.5–T.7.7 (aero envelope).
- **Airfoils (Phase 4 layer):** UIUC coordinates + airfoiltools XFOIL polars for
  S1223, E423, CH10, S1210, FX74-CL5-140 (Re 2e5/5e5), with MANIFEST + sha256.
- **In-repo docs (ground truth):** `HANDOVER.md` (start here), `README.md`, `PROJECT_TODOS.md`,
  `docs/RUNNING.md`, `docs/PORT_AND_MATLAB.md`, `docs/VALIDATION.md`, `docs/PHYSICS_DELTA.md`,
  `docs/FUTURE.md`, `handover/FINDINGS.md`, `handover/DATA_CONTRACT.md`.

## 7. Key learnings (read these before changing anything)

1. **The `/24` bug (F1)** silently disabled longitudinal load transfer; the corrected
   model is +34 pts mean and has real CG-height sensitivity. Always run `--corrected`.
2. **Feasibility was never a physics result** — first a placeholder window, then a
   floor the grid never dipped below. Both produced false "downforce X is infeasible"
   verdicts / an apparent points cap. The binary is now **removed**: judge buildability
   by L/D, since only a CFD CL–CD polar can say what's actually buildable.
3. **The CoP optimum is interior (~0.525)** — the top-scoring setups cluster at CoP
   0.50–0.55 (best total 519.8 at CoP 0.525); the grid had to be extended to see it.
4. **"You can't beat T26" was a grid-coverage artifact.** T26 is CL 0.080 but the old
   grid only sampled to CL 0.060, so nothing matched its downforce and it trivially
   "won." The dial-up grid (CL 0.035→0.090, CD 0.010→0.030, CoP 0.425→0.675; 4,301 fast
   cells) puts T26 mid-field: **~998 setups beat it**, and at its own downforce (CL 0.080)
   a lower-drag / better-balanced setup (CD 0.010, CoP 0.600) beats it by **+31 pts**.
   The real lever is **L/D efficiency**, not raw downforce.
5. **High-CL cells stop solving** (357 of 4,301, starting at CL 0.0775 and growing with
   CL): the corrected model pushes the rear axle past the fitted FX tire range and the
   solver fails. These render as dashed-empty cells; the very-high-CL "wins" are the
   least-trusted numbers.
6. **No synthetic data** is shown anywhere — every on-screen number is a sim output or a
   formula applied to one. Caveats above are honest model limits, not fabrications.
