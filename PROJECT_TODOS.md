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

## Aero Map And Component Work

- [ ] Compare the static target model against the T26 aero map.
- [ ] Run the same scoring workflow with a real ride-height-dependent aero map.
- [ ] Compare effective downforce, drag, L/D, and CoP by speed.
- [ ] Keep the lap sim focused on total targets before splitting front wing, rear wing, and undertray targets.
- [ ] Use CFD to design component concepts that hit the chosen total targets.

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
