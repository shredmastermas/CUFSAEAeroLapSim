# T27 Aero Target Study — Project Overview

A decision tool for Clemson Formula SAE (CUFSAE) to choose an **aero target** — a
lift coefficient (CL), drag coefficient (CD), and center-of-pressure split (CoP) —
that maximizes total competition points across the four dynamic events
(Acceleration, Skidpad, Autocross, Endurance).

It is **not** a wing design tool. It answers "what total downforce / drag / balance
should we aim for?" so that CFD and component design have a sourced target.

## What's under the hood

- **The simulator (`pylapsim`)** is a Python port of the team's MATLAB lap sim
  (`Lap_Sim_constantAero_T27V4.m`). It reproduces the MATLAB results to ~1e-6 on
  Endurance / Skidpad / Acceleration times and lateral/longitudinal g — i.e. it is
  numerically the same model, just faster and scriptable.
- **Corrected physics.** The original MATLAB had a bug (`F1`): longitudinal load
  transfer was divided by ~24, which all but disabled it (the car was
  insensitive to CG height). This dashboard runs the **corrected** physics, so the
  scores and the on-screen corner-load picture agree. Corrected scoring is about
  +34 points higher on average than the buggy version.
- **The sweep.** The sim runs a factorial grid over (CL, CD, CoP), scoring every
  combination. Each cell in the heat-map is one simulated car. A "fast" pass scores
  the whole grid; the top setups get an "accurate" re-run at higher solver fidelity.

## Reading the dashboard

- **Sweep Explorer** — a CL × CD heat-map at a chosen CoP slice. Darker/oranger =
  more points. Click a cell (or a data-table row) to select it as your target. The
  leaderboards rank the top setups per event.
- **Balance & CoP** — how the front/rear load split migrates with speed, plus a
  lap replay that shows where on track the car is and how balance shifts.
- **Sensitivity & Noise** — one-variable-at-a-time curves (points vs CL, vs CoP,
  vs CD) and the fast-vs-accurate resolution-noise band.
- **Run Stats** — distribution of every event time and total across the whole sweep.

The **T26** marker is last year's car (CL 0.080). It is included as a point in the
grid so you can compare directly: at the same downforce, a lower-drag, better-
balanced setup beats it — T26 left points on the table in drag and balance.

## Feasibility — there is no verdict (judge by L/D)

The dashboard does **not** label any target feasible or infeasible. Whether a given
(CL, CD) is buildable is a CFD/wind-tunnel question, and any cutoff drawn without
that data would just be a made-up number. (An earlier build had a feasibility
*window*, then a minimum-downforce *floor* — but the sweep grid starts right at the
floor, so nothing ever failed it. A filter that filters nothing is theater, so it
was removed.)

More downforce always scores higher, so the honest decision variable is **L/D**
(lift-to-drag), shown on every cell's scorecard:

- **Low L/D (≤ ~3):** draggy but easily built.
- **High L/D (≥ ~6):** scores great, but implies a very efficient wing that needs
  CFD to confirm it's even possible.

Judge targets by their lift-to-drag, not points alone. The real buildable bound is
a measured CL–CD polar (a CFD deliverable the team doesn't have yet).

## Honest caveats

- **Autocross geometry** — the committed MATLAB oracle used a 2334 ft path that
  cannot be reproduced from the committed coordinate files (which give 2728 ft).
  This dashboard's autocross derives from the committed coordinates (2728 ft), so
  it is self-consistent but differs from the legacy oracle.
- **Tire model** — corrected high-downforce cases push rear loads past the fitted
  tire-data range; values beyond are extrapolated. This matters most in exactly the
  high-CL region the sweep favors.
- **Scoring anchors** are 2019 Michigan results, so scores are *relative rankings*,
  not absolute 2026 predictions.
- **Efficiency event** is not scored (no team BSFC supplied), so drag is somewhat
  under-penalized.

See `T27_LLM_BRIEF.md` for the full assumption register, sources, and improvement
list. Repository: github.com/shredmastermas/CUFSAEAeroLapSim.
