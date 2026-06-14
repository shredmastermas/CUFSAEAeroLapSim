# T27 Aero Lap Sim Project TODOs

This is the working checklist for the CUFSAE T27 aero lap sim. The goal is to keep the project moving in small, testable chunks while protecting the credibility of the results.

## Current Sprint

- [x] Add a comprehensive root `README.md` for setup and normal use.
- [x] Make `main` the default GitHub branch and merge the aero lap sim updates.
- [x] Add named resolution presets so users do not manually edit step sizes every run.
- [x] Add sideslip-limit diagnostics to the aero-map lap sim output.
- [x] Treat beta-limit saturation as a failed aero-map lateral search point instead of letting the model exploit the bound.
- [ ] Run a full medium-resolution aero sweep after MATLAB validation.
- [ ] Review the updated `Best Feasible` result against the 35 mph downforce/drag/L/D limits.

## Model Trust And Debugging

- [x] Root-cause CG-height insensitivity: longitudinal load transfer was effectively
      disabled by a spurious `/24` (and a double application in braking) in
      `Lap_Sim_constantAero_T27V4.m` — fixed on branch `pylapsim`; see
      `handover/FINDINGS.md` F1. CG height now has real longitudinal sensitivity.
      (MATLAB fix is parity-checked via the Python port, not yet run in MATLAB.)
- [ ] Create a CG height sensitivity study.
- [ ] Sweep CG height over a realistic range.
- [ ] Plot total points vs CG height.
- [ ] Plot lateral acceleration capability vs corner radius.
- [ ] Plot chassis sideslip angle vs corner radius.
- [ ] Mark where sideslip reaches the configured beta limit.
- [ ] Check whether lower CG height improves lateral acceleration as expected.
- [ ] Save raw sensitivity data and plots in a dedicated debug results folder.

## Sideslip Diagnostics

- [x] Track maximum chassis sideslip angle for each run.
- [x] Flag whether the configured beta limit was reached.
- [x] Count how many lateral envelope points hit the beta limit.
- [x] Record the first radius where beta-limit saturation occurs.
- [x] Record the first speed where beta-limit saturation occurs.
- [x] Add sideslip warning columns to the aero-map `latResults_out` table.
- [ ] Plot sideslip diagnostics automatically from sweep output.
- [ ] Decide whether the default beta limit should stay at 10 deg or move lower after validation.

## Aero Sweep Outputs

- [x] Include `CL_target`, `CD_target`, `CoP_target`, and `CL_over_CD`.
- [x] Include total points and event-specific points.
- [x] Include downforce, drag, L/D, and front/rear split at key speeds.
- [x] Include feasibility flags and rejection notes.
- [ ] Decide whether sideslip diagnostics should be propagated into constant-aero sweep workbooks.
- [ ] Include front and rear static ride-height assumptions in the sweep table.
- [ ] Add a standard 25 to 60 mph force-conversion table for every selected target.

## Physical Feasibility Filters

- [x] Add configurable downforce limits at the reference speed.
- [x] Add configurable drag limits at the reference speed.
- [x] Add configurable L/D limits centered on last year's estimate.
- [x] Keep infeasible rows in the workbook with notes instead of deleting them.
- [ ] Replace the placeholder feasibility window with CFD or measured CUFSAE data.
- [ ] Add optional hard bounds for maximum `CL_target`, minimum `CD_target`, and maximum L/D.

## Plotting And Review Tools

- [ ] Generate total points vs `CL_target`.
- [ ] Generate total points vs `CD_target`.
- [ ] Generate total points vs `CoP_target`.
- [ ] Generate total points vs L/D.
- [ ] Generate CL vs CD colored by total points.
- [ ] Generate CoP vs total points colored by L/D.
- [ ] Generate 35 mph downforce vs drag colored by total points.
- [ ] Generate 60 mph downforce vs drag colored by total points.
- [ ] Export top 10 feasible and top 10 overall tables as presentation-ready sheets.

## Aero Target Follow-ups (pylapsim, 2026-06-12)

- [ ] Vehicle-dynamics review of forward CoP: the corrected-physics optimum sits at
      CoP 0.575–0.650, but the lap sim has **no braking-stability model** — verify
      rear-axle margin under braking before adopting (HANDOVER.md §7 / docs/PHYSICS_DELTA.md).
- [ ] Supply BSFC (g/kWh) + fuel density + competition efficiency anchors so
      Efficiency_Score can be populated (formula already implemented from
      FSAE Rules 2026 §D.13.4 — pylapsim/scoring.py).
- [ ] Supply a sourced wing-package mass estimate to replace the unsourced
      k_mass scenario bracket (docs/PHYSICS_DELTA.md).
- [ ] Replace the placeholder feasibility window with CFD/measured data — the
      unconstrained optimum is worth ~+17 pts and is blocked only by the window.

## Aero Map And Component Work

- [ ] Compare the static target model against the T26 aero map.
- [ ] Run the same scoring workflow with a real ride-height-dependent aero map.
- [ ] Compare effective downforce, drag, L/D, and CoP by speed.
- [ ] Keep the lap sim focused on total targets before splitting front wing, rear wing, and undertray targets.
- [ ] Use CFD to design component concepts that hit the chosen total targets.

## Data Integrity

- [ ] FX tire model range: corrected-physics rear-wheel loads exceed the CSAPS fit's
      FZ range (−250 lbf) under combined transfer + downforce; values beyond are cubic
      extrapolations. Acquire/fit TTC FX data covering −250 to −350 lbf
      (see docs/PHYSICS_DELTA.md "Model-limit caveat").

- [ ] **Autocross oracle mismatch (found by the pylapsim port, 2026-06-12):** the
      committed sweep workbook + validation trace embed a 2334.1 ft autocross path,
      but the committed `Autocross_Coordinates_2.xlsx` + `autocross_racing_line.mat`
      produce a 2727.95 ft path (confirmed by MATLAB's own committed
      `latestpgResults.mat` / `latestLLTDResults.mat` workspaces to 1e-10).
      Either regenerate the oracle in MATLAB from the committed inputs, or commit
      the coordinate file that produced the 2334 ft path. Full evidence:
      `docs/VALIDATION.md` §3.

## Validation Planning

- [ ] Create `docs/validation_plan.md`.
- [ ] Define required logged channels for acceleration, braking, skidpad, autocross, and endurance validation.
- [ ] Include ride-height or linear-potentiometer validation plans.
- [ ] Include steady-state longitudinal braking tests.
- [ ] Use braking data to correlate tire/grip scale factors.
- [ ] Compare measured speed, Ax, Ay, gear, and distance traces against `validationTelemetry`.

## Code Quality And Workflow

- [ ] Add a small MATLAB smoke-test script for one feasible constant-aero case.
- [ ] Add a small MATLAB smoke-test script for the sweep runner.
- [ ] Add a small MATLAB check for `Aero/Lap_Sim_fminconSp26.m` using a locally available aero map file.
- [ ] Keep generated smoke files out of Git.
- [ ] Keep `README.md` updated as the workflow changes.
- [ ] Commit changes in small chunks with clear messages.
