# CUFSAE T27 Aero Lap Simulation

This repository contains the CUFSAE T27 aero lap simulation workflow used to study aerodynamic targets for a mock FSAE Michigan-style competition. The project now has three usable paths:

- `dashboard-app/`: the browser dashboard for reviewing sweep results and aero targets
- `pylapsim/`: the Python lap sim port used for fast sweeps, validation, and dashboard data generation
- `Lap Sim March 2026/`: the original MATLAB lap sim, input data, and engineering reports

The current workflow focuses on choosing defensible first-pass aero goals for total downforce, drag, and front/rear aero balance instead of copying previous-year `CL`, `CD`, and CoP values without a scoring reason.

## Quick Start: View The Dashboard

If you only want to explore the latest committed aero study, open the prebuilt single-file dashboard:

```bash
open dashboard-app/dist-single/index.html
```

On Windows, double-click this file instead:

```text
dashboard-app/dist-single/index.html
```

To run it as a local website with Vite:

```bash
cd dashboard-app
npm install
npm run dev
```

Then open the local URL that Vite prints, usually `http://localhost:5273/`. On Windows PowerShell, use `npm.cmd install` and `npm.cmd run dev` if script execution is disabled.

To build and preview the production site:

```bash
cd dashboard-app
npm install
npm run build
npm run preview
```

## Quick Start: Run The Python Lap Sim

Use Python when you want to run new sweeps, validate the port against the MATLAB reference data, or regenerate dashboard inputs. Python 3.12 is recommended.

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
python -m pylapsim validate
pytest
```

On Windows PowerShell:

```powershell
py -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
python -m pylapsim validate
pytest
```

Run the current buildable-envelope sweep:

```bash
python scripts/run_clamped_sweep.py
```

Run a single aero setup and export its lap trace:

```bash
python -m pylapsim run --cl 0.040 --cd 0.020 --cop 0.450 --corrected --out-dir trace_out
```

Run a grid sweep directly from the CLI:

```bash
python -m pylapsim sweep --preset Medium --corrected --out "my_sweep.xlsx"
```

The main Python outputs are written under:

```text
Lap Sim March 2026/Test Results/python/
```

After generating new sweep data, see `docs/RUNNING.md` for the dashboard data rebuild steps.

## Quick Start: Run The MATLAB Aero Sweep

The main MATLAB entry point is:

```text
Lap Sim March 2026/Aero/Run_T27_AeroSweep_MultithreadedExcel.m
```

That runner sweeps combinations of:

- `CL_target`: lap-sim downforce force coefficient
- `CD_target`: lap-sim drag force coefficient
- `CoP_target`: front aero balance, where `0.450` means 45 percent front and 55 percent rear

It then runs the lap sim, ranks the results, filters unrealistic aero targets, and writes a multi-sheet Excel workbook.

## Repository Layout

```text
CUFSAEAeroLapSim/
├── README.md
├── PROJECT_TODOS.md
├── pylapsim/                 # Python lap sim engine
├── dashboard-app/            # Vite/React dashboard host
├── docs/                     # running, validation, and technical notes
├── scripts/                  # sweep and dashboard-data helper scripts
├── tests/                    # pytest validation suite
├── data/airfoils/            # airfoil reference data
└── Lap Sim March 2026/
    ├── setupLapSimPaths.m
    ├── Aero/
    │   ├── Lap_Sim_constantAero_T27V4.m
    │   ├── Lap_Sim_fminconSp26.m
    │   ├── Run_T27_AeroSweep_MultithreadedExcel.m
    │   ├── aeroMapfn.m
    │   └── aero sweep/helper files
    ├── Powertrain/
    │   ├── Lap_Sim_powertrain.m
    │   ├── Powertrainlapsim.m
    │   └── calc_shiftpoints.m
    ├── Suspension/
    │   └── load-transfer and weight-distribution sweep files
    ├── Sim Data/
    │   ├── Autocross_Coordinates_2.xlsx
    │   ├── Endurance_Coordinates_1.xlsx
    │   └── track/racing-line/cache .mat files
    ├── Tire Data/
    │   └── TTC tire model data and tire utility files
    ├── Test Results/
    │   └── generated sweep, validation, and smoke-test outputs
    └── shared lap-time/path/solver utilities
```

The older lap sim files are kept for reference. Current constant-aero target work should usually use `Aero/Lap_Sim_constantAero_T27V4.m` through `Aero/Run_T27_AeroSweep_MultithreadedExcel.m`. Aero-map debugging and ride-height-sensitive aero work should use `Aero/Lap_Sim_fminconSp26.m`.

## MATLAB Requirements

Recommended environment:

- MATLAB R2026a or newer
- Optimization Toolbox, for `fmincon`
- Curve Fitting Toolbox or spline support used by the existing model, for `csaps` and spline objects
- Parallel Computing Toolbox, optional but strongly recommended for the multithreaded sweep

The workflow was built to run on macOS and Windows. The current development machine was a MacBook M3 Max, but the runner falls back to serial execution if a parallel pool is not available.

## Important Coefficient Definition

In this lap sim, `CL_target` and `CD_target` are force coefficients in the sim's internal force scale:

```text
Downforce [lbf] = CL_target * V^2
Drag [lbf]      = CD_target * V^2
Force [N]       = Force [lbf] * 4.448
```

where `V` is speed in ft/s.

These are not automatically nondimensional CFD coefficients. If CFD or wind-tunnel data is used, convert or correlate those forces into this same scale before comparing directly.

Example at 35 mph:

```text
35 mph = 51.333 ft/s
CL_target = 0.045
CD_target = 0.020

Downforce = 0.045 * 51.333^2 = about 119 lbf / 528 N
Drag      = 0.020 * 51.333^2 = about 53 lbf / 235 N
L/D       = 119 / 53 = about 2.25
```

## Current Feasible Aero Envelope

The runner includes feasibility filters so the workbook does not treat impossible aero as the design target.

Current defaults at the reference speed of 35 mph, about 15 m/s:

| Quantity | Default Limit |
|---|---:|
| Total downforce | 90 to 135 lbf |
| Total drag | 40 to 65 lbf |
| Lift-to-drag ratio | 2.0 to 2.4 |
| Target L/D center | 2.2 |

This reflects current CUFSAE expectations: roughly 400 to 600 N downforce at 15 m/s and drag slightly below half of downforce. The previous year's efficiency was about L/D = 2.2. The Python dashboard sweep now explores L/D 2.0 to 2.75, with values above 2.75 intentionally excluded until CFD or test data supports them.

## Quick Start: Run The Multithreaded Aero Sweep

1. Open MATLAB.
2. Change directory into the lap sim folder:

```matlab
cd('/Users/masonkelly/Documents/GitHub/CUFSAEAeroLapSim/Lap Sim March 2026')
setupLapSimPaths
```

On Windows, use the equivalent local path, for example:

```matlab
cd('C:\Users\YourName\Documents\GitHub\CUFSAEAeroLapSim\Lap Sim March 2026')
setupLapSimPaths
```

3. Run the multithreaded sweep:

```matlab
Run_T27_AeroSweep_MultithreadedExcel
```

4. Open the generated workbook:

```text
Lap Sim March 2026/Test Results/T27_AeroSweep_Multithreaded_Results.xlsx
```

The default runner uses the Parallel Computing Toolbox if available. If MATLAB cannot start a parallel pool, it falls back to serial execution.

## Quick Start: Run One Aero Case

For a single case, open MATLAB in the lap sim folder, add the reorganized folders to the path, and run:

```matlab
setupLapSimPaths
CL_target = 0.045;
CD_target = 0.020;
CoP_target = 0.475;
T27_PLOT_RESULTS = true;
run(fullfile('Aero','Lap_Sim_constantAero_T27V4.m'))
```

The main output is `aeroTargetResults` in the MATLAB workspace. It contains event scores, event times, total points, and the aero target that was used.

## Common Sweep Settings

Set these variables before running `Run_T27_AeroSweep_MultithreadedExcel.m` to customize the sweep.

### Change Worker Count

```matlab
T27_NUM_WORKERS = 6;
Run_T27_AeroSweep_MultithreadedExcel
```

Use a worker count near physical CPU cores, not necessarily maximum threads. Leave it empty to let MATLAB decide:

```matlab
T27_NUM_WORKERS = [];
```

### Disable Parallel Mode

```matlab
T27_USE_PARALLEL = false;
Run_T27_AeroSweep_MultithreadedExcel
```

This is useful for debugging or for machines without Parallel Computing Toolbox.

### Change The Aero Sweep Grid

```matlab
T27_CL_list  = 0.035:0.002:0.065;
T27_CD_list  = 0.015:0.0025:0.030;  % direct-CD MATLAB sweep only
T27_CoP_list = 0.400:0.025:0.500;
Run_T27_AeroSweep_MultithreadedExcel
```

### Change Feasibility Limits

```matlab
T27_feasibilityRefSpeedMph = 35;
T27_minFeasibleDownforceAtRef_lbf = 90;
T27_maxFeasibleDownforceAtRef_lbf = 135;
T27_minFeasibleDragAtRef_lbf = 40;
T27_maxFeasibleDragAtRef_lbf = 65;
T27_targetFeasibleLiftToDrag = 2.2;
T27_feasibleLiftToDragTolerance = 0.2;
Run_T27_AeroSweep_MultithreadedExcel
```

The resulting L/D window is:

```text
T27_minFeasibleLiftToDrag = 2.0
T27_maxFeasibleLiftToDrag = 2.4
```

### Choose Resolution Preset

Use named resolution presets instead of manually editing step sizes every run:

```matlab
T27_resolutionPreset = "Medium";  % "High", "Medium", "Low", or "Custom"
Run_T27_AeroSweep_MultithreadedExcel
```

Preset meanings:

| Preset | Use Case | Velocity Step | Radius Step | Lateral Search Step |
|---|---|---:|---:|---:|
| `High` | final/check run, original accurate grid | 1 ft/s | 5 ft | 0.10 ft/s |
| `Medium` | default aero sweep | 2 ft/s | 10 ft | 0.25 ft/s |
| `Low` | quick screening/debugging | 3 ft/s | 15 ft | 0.50 ft/s |
| `Custom` | use manually supplied values | user set | user set | user set |

To show an interactive MATLAB picker before the sweep starts:

```matlab
T27_SHOW_RESOLUTION_PICKER = true;
Run_T27_AeroSweep_MultithreadedExcel
```

For a custom resolution:

```matlab
T27_resolutionPreset = "Custom";
T27_FAST_MODE = true;
T27_velocityStep = 2;
T27_radiiStep = 10;
T27_lateralStep = 0.25;
Run_T27_AeroSweep_MultithreadedExcel
```

The runner can also do an accurate rerun of the best fast cases:

```matlab
T27_RERUN_TOP_ACCURATE = true;
T27_topN_accurate = 10;
Run_T27_AeroSweep_MultithreadedExcel
```

### Change Output File Names

```matlab
T27_outputXlsx = 'my_aero_sweep.xlsx';
T27_outputMat = 'my_aero_sweep.mat';
T27_failedCsv = 'my_failed_runs.csv';
Run_T27_AeroSweep_MultithreadedExcel
```

## Workbook Outputs

The multithreaded runner writes a workbook with sheets such as:

| Sheet | Purpose |
|---|---|
| `Best Summary` | High-level best results by scoring bucket. |
| `Best Overall` | Highest total-points result, regardless of feasibility. |
| `Best Overall Targets` | Downforce, drag, and split targets for the best overall result at selected speeds. |
| `Best Feasible` | Highest total-points result that passes downforce, drag, and L/D feasibility filters. |
| `Best Feasible Targets` | Downforce, drag, and front/rear split targets for the best feasible result. |
| `All Feasible Ranked` | All feasible rows sorted by total points. |
| `All Results Ranked` | All rows, including infeasible results, sorted by total points. |
| `All Fast Ranked` | Fast-sweep rows only. |
| `Top Fast Total` | Best fast rows by total points. |
| `Top Fast Autocross` | Best fast rows by autocross score. |
| `Top Fast Endurance` | Best fast rows by endurance score. |
| `Top Fast Skidpad` | Best fast rows by skidpad score. |
| `Top Fast CL CD` | Rows sorted by `CL_over_CD`. Use carefully; feasibility matters. |
| `Top Fast CoP` | Rows closest to the target aero balance. |
| `CL Sensitivity` | Summary of score sensitivity to `CL_target`. |
| `CD Sensitivity` | Summary of score sensitivity to `CD_target`. |
| `CoP Sensitivity` | Summary of score sensitivity to `CoP_target`. |
| `Accurate Rerun Ranked` | Optional accurate rerun of the top fast cases. |
| `Fast Failed Runs` | Any failed fast cases and error messages. |
| `Accurate Failed Runs` | Any failed accurate rerun cases and error messages. |

For design review, start with `Best Feasible` and `Best Feasible Targets`. The unconstrained `Best Overall` result is useful for understanding model direction, but it may be physically unrealistic.

## Current Recommended Starting Target

The current feasible nominal aero target is approximately:

| Target | Value |
|---|---:|
| `CL_target` | 0.045 |
| `CD_target` | 0.020 |
| `CoP_target` | 0.475 front |
| Total downforce at 35 mph | about 119 lbf |
| Total drag at 35 mph | about 53 lbf |
| L/D at 35 mph | about 2.25 |

This should be treated as a first-pass target for aero concept development, not as final proof. Replace the feasibility limits with measured or CFD-backed CUFSAE data as it becomes available.

## How The Lap Sim Works At A High Level

1. Loads tire, powertrain, vehicle, suspension, and track data.
2. Defines the constant aero target: `CL_target`, `CD_target`, and `CoP_target`.
3. Builds a GGV envelope:
   - maximum acceleration vs speed
   - maximum braking vs speed
   - maximum lateral acceleration vs speed
   - maximum corner speed vs turn radius
4. Runs acceleration, skidpad, autocross, and endurance calculations.
5. Converts event times into FSAE-style event scores.
6. Sums event scores into total dynamic points.
7. In sweep mode, repeats the process for many aero combinations.
8. Exports ranked results, sensitivity summaries, feasible targets, and validation-style traces.

## Ride Height Handling

The constant-aero version still passes ride height through the model because the original aero-map interface expected front and rear ride height. Static values are set in `Lap_Sim_constantAero_T27V4.m`:

```matlab
RHfi = 1.5;
RHri = 1.75;
```

`aeroMapfn.m` computes aero load and corresponding suspension compression. However, in the constant-aero workflow, `CL`, `CD`, and `CoP` are constant function handles:

```matlab
fnCl  = @(~,~) CL_target;
fnCd  = @(~,~) CD_target;
fnCoP = @(~,~) CoP_target;
```

That means ride height is computed and logged, but it does not change aero performance. The current model does not include ride-height sensitivity, diffuser stall, pitch sensitivity, yaw sensitivity, steering sensitivity, or aero balance migration with ride height.

## Sideslip Diagnostics And Guardrail

The sideslip/beta debugging work now belongs to the aero-map lap sim, `Aero/Lap_Sim_fminconSp26.m`, because that is the version where ride height changes can alter `CL`, `CD`, and CoP. The constant-aero V4 script keeps the resolution presets but does not reject lateral points based on beta saturation.

The aero-map solve uses chassis sideslip angle, `Beta`, as one of the `fmincon` variables. The current diagnostic guardrail records when the optimizer rides the configured beta limit:

- `T27_betaLimitDeg` sets the beta bound, default `10` deg.
- `T27_betaLimitToleranceDeg` sets the near-limit tolerance, default `0.25` deg.
- `T27_REJECT_SIDESLIP_LIMITED = true` treats beta-limit saturation as a failed lateral search point so the aero-map envelope stops before exploiting the bound.

`Lap_Sim_fminconSp26.m` now creates `latResults_out` with beta limit margin, solver exit flag, and normalized residuals. It also creates `aeroMapSideslipSummary` with max sideslip, beta-limit hit counts, rejected step count, and the first radius/speed where the limit is reached.

## Validation Workflow

The sim can create validation-style telemetry tables for comparison against real logged data. In a one-off run, enable validation export:

```matlab
T27_EXPORT_VALIDATION = true;
setupLapSimPaths
CL_target = 0.045;
CD_target = 0.020;
CoP_target = 0.475;
run(fullfile('Aero','Lap_Sim_constantAero_T27V4.m'))
```

This can write files like:

```text
T27_validation_trace_<aeroTag>.csv
T27_validation_summary_<aeroTag>.csv
```

Recommended logged channels for validation:

- speed
- time
- distance
- longitudinal acceleration
- lateral acceleration
- gear
- engine speed, if available
- throttle and brake, if available
- steering angle, if available

Suggested validation approach:

1. Compare acceleration time and speed trace first.
2. Compare skidpad lateral-g capability.
3. Compare autocross and endurance speed traces by distance.
4. Tune tire scale factors only when there is a clear data reason.
5. Replace aero feasibility assumptions with CFD or test-backed values.
6. Re-run the aero sweep after major tire, powertrain, mass, or aero updates.

## Major Assumptions And Limitations

The current lap sim is useful for target setting, but it is not a final high-fidelity vehicle dynamics model.

Key assumptions:

- Aero uses constant `CL`, `CD`, and CoP for each case.
- Aero does not vary with ride height, pitch, roll, yaw, steering, or wheel wake.
- Track layout comes from the included coordinate/racing-line files.
- Racing lines are not fully re-optimized for every aero case.
- Tire behavior depends on the loaded tire models and scale factors.
- Vehicle mass, powertrain, gearing, shift time, and suspension settings are fixed unless edited.
- The model is mostly quasi-static and does not fully capture driver control transients.
- Event scoring is based on the formulas and reference values in the script.

These assumptions are acceptable for comparing first-pass aero targets, but final design decisions should be backed by CFD, physical testing, and logged data correlation.

## Performance Notes

The current workflow was optimized for faster sweeps in several ways:

- `parfor` runs independent aero cases at the same time.
- Named resolution presets choose high, medium, low, or custom sweep resolution.
- Only the top fast cases need to be rerun accurately.
- Plotting and per-worker CSV output are disabled during sweeps.
- Constant aero uses cheap function handles instead of constant scattered interpolants.
- The longitudinal tire slip sweep is vectorized in `evalLongitudinalTireLimit.m`.
- Major result arrays are preallocated.

GPU acceleration is not currently used. This workload is dominated by optimization, spline interpolation, tire model calls, and lap integration. Those pieces are not automatically accelerated by GPU hardware in normal MATLAB usage.

## Troubleshooting

### MATLAB cannot find files

Make sure MATLAB's current folder is:

```text
Lap Sim March 2026
```

The scripts expect the tire, track, racing-line, and helper files to be in that folder.

### Parallel pool does not start

Run serial mode:

```matlab
T27_USE_PARALLEL = false;
Run_T27_AeroSweep_MultithreadedExcel
```

### The sweep is too slow

Try:

```matlab
T27_resolutionPreset = "Low";
T27_RERUN_TOP_ACCURATE = false;
Run_T27_AeroSweep_MultithreadedExcel
```

Then restore `Medium` or `High` for final results.

### Results look physically unrealistic

Check the feasibility columns in the workbook:

- `DF_Total_FeasRef_lbf`
- `Drag_Total_FeasRef_lbf`
- `LiftToDrag_FeasRef`
- `IsFeasibleAeroTarget`
- `FeasibilityNotes`

Use `Best Feasible`, not just `Best Overall`, when choosing design targets.

### The unconstrained winner has huge L/D

That is expected if the sweep allows unrealistically high downforce with unrealistically low drag. The feasibility gates exist specifically to prevent that result from becoming the design target.

## Git / Generated File Policy

The repository ignores local smoke-test outputs and temporary files such as:

- `.DS_Store`
- Office lock files
- `CODEX_T27_*.mat` / `CODEX_T27_*.xlsx`
- `Test Results/CODEX_T27_*.mat` / `Test Results/CODEX_T27_*.xlsx`
- generated validation CSV files
- one-off `aero_target_results.csv`
- one-off `logged_data.csv`
- local generated files under `Lap Sim March 2026/Test Results/`

Keep durable scripts, reports, and intentional result workbooks in version control. Keep local smoke-test output out of commits unless there is a specific reason to preserve it.

## Main Files To Read First

For users running the project:

1. `README.md`
2. `Lap Sim March 2026/Aero/Run_T27_AeroSweep_MultithreadedExcel.m`
3. `Lap Sim March 2026/T27_LapSim_Presentation_Notes.md`
4. `Lap Sim March 2026/T27_LapSim_Aero_Target_Engineering_Report.md`

For users changing the model:

1. `Lap Sim March 2026/Aero/Lap_Sim_constantAero_T27V4.m`
2. `Lap Sim March 2026/Aero/Lap_Sim_fminconSp26.m`
3. `Lap Sim March 2026/Aero/aeroMapfn.m`
4. `Lap Sim March 2026/lat_solve.m`
5. `Lap Sim March 2026/cAlpha_nonlcon.m`
6. `Lap Sim March 2026/Aero/evalLongitudinalTireLimit.m`

## Suggested Design Review Position

Use this lap sim as a scoring-based target-setting tool. The sim should answer:

```text
Which aero target gives the best competition result while staying inside realistic CUFSAE aero capability?
```

Do not use unconstrained `CL/CD` winners as final design goals unless CFD or testing proves they are achievable. The current defensible starting point is near `CL_target = 0.045`, `CD_target = 0.020`, and `CoP_target = 0.475`, then refine with real data.
