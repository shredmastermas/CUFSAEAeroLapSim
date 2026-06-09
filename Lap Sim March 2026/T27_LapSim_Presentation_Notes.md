# T27 Constant-Aero Lap Sim: Change Log, Explanation, and Defense Notes

## Executive Summary

This lap sim estimates T27 dynamic-event performance at a mock FSAE Michigan-style competition while sweeping aero targets for:

- `CL_target`: downforce coefficient used by this sim
- `CD_target`: drag coefficient used by this sim
- `CoP_target`: front aero balance, where `0.450` means 45 percent front and 55 percent rear

The original workflow was a single-threaded, manually edited MATLAB script. The refactor keeps the existing vehicle, tire, powertrain, track, and scoring logic, but makes it easier to run many aero cases, safer to use in parallel workers, faster in several hot loops, and more useful for validating against real logged data.

The key result is that the sim can now be run either as a normal one-off script or through sweep runners, including a `parfor` multithreaded runner for the Parallel Computing Toolbox. MATLAB R2026a was used to verify:

- A fast baseline run completed successfully.
- An accurate baseline run completed successfully.
- A two-case `parfor` smoke test completed successfully with 2 workers.

Baseline verification result for `CL=0.080`, `CD=0.020`, `CoP=0.450`:

| Metric | Value |
|---|---:|
| Total Points | 417.35 |
| Accel Score | 56.814 |
| Skidpad Score | 79.553 |
| Autocross Score | 70.619 |
| Endurance Score | 210.36 |
| Accel Time | 4.8383 s |
| Skidpad Time | 4.7858 s |
| Autocross Time | 56.903 s |
| Endurance Lap Time | 125.3 s |

Important feasibility correction:

The unconstrained sweep can select aero values that are not physically realistic. For example, `CL=0.160` and `CD=0.010` predicts about 422 lbf of downforce at 35 mph with L/D near 16. Based on current CUFSAE expectations, a realistic 15 m/s / 35 mph window is about 90 to 135 lbf downforce, which is approximately 400 to 600 N. Drag should be slightly below half of downforce, about 40 to 65 lbf, and last year's efficiency was about L/D = 2.2. The runner now enforces those feasibility filters directly: downforce 90-135 lbf, drag 40-65 lbf, and L/D 2.0-2.4 at 35 mph. The workbook reports both the unconstrained best result and the best feasible result. A reasonable nominal starting target is about `CL=0.045`, `CD=0.020`, and `CoP=0.475`, which gives about 119 lbf downforce, 53 lbf drag, and L/D about 2.25 at 35 mph.

## What Changed

### 1. The Main Script Is Now Runner-Friendly

File: `Lap_Sim_constantAero_T27V4.m`

The top of the script now supports injected settings from batch runners:

- `T27_NO_CLEAR`
- `T27_SWEEP_ACTIVE`
- `T27_PARALLEL_ACTIVE`
- `T27_FAST_MODE`
- `T27_PLOT_RESULTS`
- `T27_velocityStep`
- `T27_radiiStep`
- `T27_lateralStep`
- `T27_WRITE_OUTPUTS`
- `T27_EXPORT_VALIDATION`

Why this matters:

- A normal one-off run still works.
- A runner can set `CL_target`, `CD_target`, and `CoP_target` before calling the script.
- Parallel workers do not erase their injected variables with `clear`.
- Parallel workers do not all try to write the same CSV files at the same time.

This was one of the most important structural changes because MATLAB scripts share the caller workspace. Without guarding `clear`, each sweep case would lose its assigned aero target.

### 2. Constant Aero Is Now Direct and Cheap

The sim now uses constant function handles:

```matlab
fnCl  = @(~,~) CL_target;
fnCd  = @(~,~) CD_target;
fnCoP = @(~,~) CoP_target;
```

The old aero-map style interface is still supported through `aeroMapfn`, but constant aero does not pay scattered-interpolant overhead. This matters because `aeroMapfn` is called many times inside acceleration, braking, and lateral-envelope calculations.

The sim uses:

```text
Downforce = CL_target * V^2
Drag      = CD_target * V^2
```

where `V` is vehicle speed in ft/s and force is lbf.

Important defense point: these `CL` and `CD` values are the force coefficients used by this lap sim. They are not automatically CFD nondimensional coefficients unless the CFD data is converted into the same units and scaling.

### 3. The Longitudinal Tire Slip Sweep Was Vectorized

New file: `evalLongitudinalTireLimit.m`

The old acceleration and braking loops repeatedly evaluated tire force one slip-ratio point at a time. The refactor evaluates the whole slip-ratio vector in one call:

- Acceleration uses `0:0.01:0.11`
- Braking uses `-0.15:0.01:0`

This removes a small inner loop from the acceleration and braking envelopes. It also centralizes the tire-force filtering rule:

- Tire forces with magnitude greater than 1000 lbf are treated as invalid and removed.

Why this matters:

- Less duplicated code.
- Easier to audit tire-force limit behavior.
- Faster repeated envelope generation.

### 4. GGV Generation Is More Structured

The sim still builds a g-g-V map before lap integration:

- Maximum acceleration vs speed
- Maximum braking vs speed
- Maximum lateral acceleration vs speed
- Maximum corner speed vs radius

Changes made:

- Velocity grid starts at 0 ft/s and includes `VMAX`.
- Fast mode can coarsen velocity, radius, and lateral search resolution.
- Lateral and longitudinal result arrays are preallocated.
- Spline fitting now checks for enough valid and unique lateral-envelope points.
- Plotting is controlled by `T27_PLOT_RESULTS`, so sweeps do not open figures.

This makes the sim more stable when running hundreds of cases.

### 5. `aeroMapfn` Was Simplified

File: `aeroMapfn.m`

The function now focuses only on what the sim actually needs:

- compute ride heights from downforce and suspension stiffness
- compute front and rear downforce from total downforce and CoP
- iterate ride height until it converges

The old table logging and repeated dynamic table growth were removed.

Why this matters:

- This function is called in hot loops.
- Dynamic table growth inside a hot loop is expensive.
- A compact function is easier to defend and verify.

### 6. Powertrain Interpolation Was Cleaned Up

File: `Powertrainlapsim.m`

The RPM/torque lookup now uses interpolation instead of a manual while-loop style search. Gear selection also guards against indexing past the gear vector.

Why this matters:

- Less fragile around gear boundaries.
- Easier to read.
- More MATLAB-native.

### 7. Track Coordinate Loading Was Centralized

New file: `readScaledTrackCoordinates.m`

Track coordinate files are now read through one helper:

- Uses `readmatrix` when available.
- Falls back to `xlsread` if needed.
- Removes fully blank rows.

Why this matters:

- Endurance and autocross use the same loading behavior.
- More portable across MATLAB versions.
- Easier to debug coordinate-file issues.

### 8. Validation Telemetry Was Added

New file: `buildValidationTelemetry.m`

The sim now creates telemetry-style output tables with:

- Event name
- Time
- Distance
- Speed
- Longitudinal acceleration
- Lateral acceleration
- Gear

This is the start of an IRL validation workflow. The intent is to compare simulation channels against logged GPS, IMU, wheel speed, and CAN data by time or distance.

When `T27_EXPORT_VALIDATION = true`, the script writes:

- `T27_validation_trace_<tag>.csv`
- `T27_validation_summary_<tag>.csv`

Sweep workers default this off so many parallel runs do not fight over output files.

### 9. Sweep Runners Were Updated to Use V4

The runner files now call `Lap_Sim_constantAero_T27V4.m`:

- `Run_T27_AeroSweep.m`
- `Run_T27_AeroSweep_FastExcel.m`
- `Run_T27_AeroSweep_MultithreadedExcel.m`

The multithreaded runner uses `parfor` through a local helper function called `runOneAeroCase`. Each worker gets its own:

- `CL_target`
- `CD_target`
- `CoP_target`
- `aeroTag`
- fast/accurate mode settings

The worker captures command-window output with `evalc`, which prevents parallel output from becoming unreadable.

The multithreaded runner exports a multi-sheet Excel workbook with:

- best summary
- ranked fast results
- top results by event
- CL/CD/CoP sensitivity summaries
- optional accurate reruns
- failed-run tables

### 10. Baseline Comparison Is More Robust

The runners now compute baseline point gain using the exact baseline row if it succeeded. If the baseline run failed, they fall back to the first successful row instead of crashing.

Added post metrics include:

- `CL_over_CD`
- `PointGain_vs_Baseline`
- `CD_Increase_vs_Baseline`
- `CL_Increase_vs_Baseline`
- `PointGain_per_CD`
- `BalanceError`
- `FrontAeroPercent`
- `RearAeroPercent`

Defense point: `PointGain_per_CD` should be interpreted carefully if `CD_Increase_vs_Baseline` is zero or near zero. For final decisions, rank by total points and event times first, then use efficiency metrics as supporting evidence.

### 11. Autocross Racing-Line Mismatch Is Handled

MATLAB found that:

- `Autocross_Coordinates_2.xlsx` has 40 valid gates.
- `autocross_racing_line.mat` has 48 racing-line positions.

The sim now trims the loaded autocross racing line to the number of available gates and warns during one-off runs.

Why this matters:

- Before the fix, the sim indexed past the coordinate boundary array and crashed.
- The sim can now run, but the file mismatch should still be fixed for final validation.

Defense point: this is not hiding the issue. The sim now reports it clearly and uses the valid coordinate range. The better long-term fix is regenerating the autocross racing line from the current coordinate file.

### 12. Optional Sprint Optimization Helpers Were Fixed

Files:

- `lap_time_sprint.m`
- `track_curvature_sprint.m`

These files had function declarations that did not match their filenames. That is risky in MATLAB and confusing during optional autocross optimization. They now declare the sprint-specific function names and use the active autocross boundary data.

## How the Sim Works

### Step 1: Load Tire Models

The sim loads:

- a lateral Magic Formula 5.2 tire model
- a longitudinal tire-force spline model

The lateral model predicts lateral force from slip angle, vertical load, and camber. The longitudinal model predicts drive/brake force from slip ratio, vertical load, and camber.

The sim also applies tire scaling factors:

```matlab
sf_x = 0.45;
sf_y = 0.5;
```

These are calibration knobs. They reduce the theoretical tire capability to better represent the car, track surface, tire temperature, driver, and model uncertainty.

### Step 2: Load Powertrain and Vehicle Parameters

The sim defines:

- engine torque curve
- gear ratios
- final drive
- shift time
- vehicle mass
- static front/rear weight distribution
- wheelbase
- CG height
- track width
- suspension stiffness and ride height
- camber gain
- pitch behavior

The powertrain model converts engine torque into available wheel force at a given speed and selected gear.

### Step 3: Define Aero Target

For this version, aero is intentionally simplified to constant target values:

```matlab
CL_target  = 0.080;
CD_target  = 0.020;
CoP_target = 0.450;
```

At each speed:

```text
Total downforce = CL_target * V^2
Drag force      = CD_target * V^2
Front DF        = Total downforce * CoP_target
Rear DF         = Total downforce * (1 - CoP_target)
```

This makes it easy to ask aero-goal questions:

- How much downforce is worth the drag?
- What balance gives the best total score?
- Does more front aero help skidpad but hurt stability?
- Which event is most sensitive to drag?

### Step 4: Build the GGV Envelope

The GGV envelope is the performance map the lap integrator uses.

Acceleration envelope:

- For each speed, compute downforce and wheel loads.
- Estimate load transfer and pitch.
- Find rear tire drive-force limit.
- Compare tire limit against powertrain wheel force.
- Store the lower of power-limited and grip-limited acceleration.

Braking envelope:

- For each speed, compute downforce and wheel loads.
- Estimate forward load transfer and pitch.
- Find braking force available from all four tires.
- Store braking acceleration capability.

Cornering envelope:

- For each radius, solve for the maximum steady-state lateral acceleration.
- Uses tire model, aero load, load transfer, slip angles, and yaw equilibrium.
- Stores lateral g and cornering speed.

The final products are spline functions:

- `accel`
- `deccel`
- `lateral`
- `cornering`

These are used during the lap simulation.

### Step 5: Load Tracks and Racing Lines

The sim loads endurance and autocross gate coordinates from Excel files. Each gate has an inside and outside boundary. The racing line is stored as a normalized position between the inside and outside gate.

For each gate:

```text
position = 0   means one side of the gate
position = 1   means the other side of the gate
position = 0.5 means center of the gate
```

The sim converts the racing-line vector into x-y path points, fits a smooth path, and computes curvature.

### Step 6: Integrate Lap Time

The lap integrator walks along the path in small distance segments.

For each segment:

- Determine path curvature.
- Compute radius.
- Use `cornering` spline to find max speed for that radius.
- Use `accel` or `deccel` spline to determine how speed changes.
- Reduce longitudinal acceleration when lateral acceleration demand is high.
- Add shift delay when gear changes occur.
- Store speed, acceleration, lateral acceleration, gear, time, and distance.

This produces:

- event lap time
- velocity trace
- longitudinal acceleration trace
- lateral acceleration trace
- gear trace
- distance trace

### Step 7: Score the Competition

The sim converts event times into FSAE-style dynamic points:

- Acceleration
- Skidpad
- Autocross
- Endurance

Total dynamic score is:

```text
Total_Points = Accel_Score + Skidpad_Score + Autocross_Score + Endurance_Score
```

This is useful because aero design should optimize competition performance, not just one isolated metric.

## How Parallel Sweeping Works

The recommended sweep file is:

```matlab
Run_T27_AeroSweep_MultithreadedExcel
```

It builds all combinations of:

```matlab
T27_CL_list
T27_CD_list
T27_CoP_list
```

Then it runs each case independently. This is ideal for parallel computing because each aero combination does not depend on the others.

Why parallelism helps:

- The sim itself is mostly serial math, tire calls, splines, and optimization.
- GPU offload is not straightforward because `fmincon`, splines, and the tire-model workflow are not automatically GPU-accelerated.
- But each aero case is independent, so CPU workers can run separate cases at the same time.

Recommended workflow:

1. Run a coarse fast sweep.
2. Look at total points and event sensitivity.
3. Rerun the best cases in accurate mode.
4. Validate top candidates against logged data before treating them as design targets.

## Major Assumptions

### Aero Assumptions

- Aero coefficients are constant with speed, yaw, pitch, roll, steer angle, and ride height.
- CoP is constant front/rear distribution.
- Aero force scales with `V^2`.
- `CL_target` and `CD_target` are sim-force coefficients, not automatically CFD nondimensional coefficients.
- Drag is modeled as a direct force loss from available tractive force.

### Tire Assumptions

- Tire behavior comes from the loaded TTC-derived models.
- Global scaling factors `sf_x` and `sf_y` represent track condition, temperature, driver, setup, and model uncertainty.
- Tire temperature, pressure change, wear, and transient relaxation effects are not modeled directly.
- Combined longitudinal/lateral use is approximated in the lap integrator by reducing available longitudinal acceleration as lateral demand rises.

### Vehicle Dynamics Assumptions

- Load transfer and pitch are quasi-static.
- Roll, yaw transients, damping, compliance, and driver control dynamics are simplified.
- The lateral envelope is steady-state.
- Wheel loads are based on static distribution, downforce, and simplified load-transfer equations.
- Powertrain torque delivery is based on the engine curve and gearing, not detailed engine/transient behavior.

### Track and Driver Assumptions

- The racing line is precomputed or loaded from a file.
- The driver follows the racing line exactly.
- The sim does not include traffic, cone penalties, driver inconsistency, or risk margin.
- The autocross racing-line file currently has more positions than the coordinate file has gates, so the sim trims to the valid gate count.

### Scoring Assumptions

- Event scoring uses fixed minimum/reference times in the script.
- These reference values are useful for comparison studies, but should be updated if the mock competition rules or reference times change.

## Good Points to Emphasize in a Presentation

- The sim optimizes for competition score, not just downforce.
- The aero sweep directly answers design-goal questions for `CL`, `CD`, and balance.
- Parallel sweeps are valid because each aero case is independent.
- Fast mode supports broad screening; accurate mode supports final comparison.
- The same vehicle model, tire model, powertrain model, and track definitions are reused across all aero cases.
- Validation telemetry now exists, which makes the sim easier to correlate to real data.
- The refactor did not throw away the original modeling approach. It made the existing approach cleaner, faster, and more repeatable.
- MATLAB runtime verification found and fixed real issues, which improves confidence in the code path.

## Known Limitations and How to Defend Them

### Constant Aero Is a Simplification

Defense:

This version is meant to find target-level aero goals before committing to detailed aero maps. Constant `CL`, `CD`, and `CoP` make the design trade study clean and easy to interpret. A later version can replace the constants with ride-height, yaw, pitch, or speed-dependent maps once CFD or wind-tunnel data is ready.

### Racing Line Is Not Re-Optimized for Every Aero Package

Defense:

Using one racing line isolates the effect of aero changes. If every aero package also got a new optimized line, the comparison would mix aero performance with optimizer behavior. For final candidates, re-optimizing the racing line is a good next step.

### Tire Scaling Factors Are Calibration Knobs

Defense:

The raw tire model does not perfectly represent the car on the actual surface. Scaling factors are common in lap simulation and should be calibrated using logged acceleration, braking, and skidpad/autocross data.

### The Model Is Quasi-Static

Defense:

For aero target selection, a quasi-static lap sim is appropriate because it captures first-order performance tradeoffs quickly. Higher-fidelity transient simulation would take longer and require more parameters that may not be known accurately yet.

### Parallelism Speeds the Sweep, Not One Single Lap

Defense:

The lap sim itself is still mostly serial. The speedup comes from running many independent aero cases at once. That is the correct use of the Parallel Computing Toolbox for this problem.

## IRL Validation Plan

### Data to Collect

Useful channels:

- GPS speed
- GPS position or distance
- IMU longitudinal acceleration
- IMU lateral acceleration
- wheel speed
- steering angle
- throttle
- brake pressure
- gear or engine RPM
- damper pots or ride-height sensors if available

### How to Compare

Compare by distance first, not only by time. Distance-based comparison makes it easier to align corners and braking zones even if one run is faster.

Recommended overlays:

- speed vs distance
- longitudinal acceleration vs distance
- lateral acceleration vs distance
- gear vs distance
- time delta vs distance
- max speed on straights
- min speed in key corners
- braking start/end points
- peak lateral g in skidpad or constant-radius sections

### What to Tune First

1. Vehicle mass and weight distribution
2. Tire scaling factors `sf_x` and `sf_y`
3. Powertrain torque or drivetrain loss assumptions
4. Aero coefficients and aero balance
5. Shift time and shift strategy
6. Racing line and track coordinate accuracy

### Validation Targets

Good first validation goals:

- Acceleration time within about 3 to 5 percent
- Skidpad lateral g within about 5 percent
- Straight-line speed trace shape close to logged data
- Braking decel envelope close to logged data
- Autocross/endurance lap time within a reasonable tolerance after line and driver assumptions are considered

## Possible Next Steps

### High Priority

- Regenerate `autocross_racing_line.mat` so it matches the 40-gate autocross coordinate file.
- Run a larger fast parallel sweep on the M3 Max.
- Rerun the top 10 to 20 aero candidates in accurate mode.
- Export validation traces for the baseline setup and compare to logged data.
- Calibrate `sf_x` and `sf_y` using real acceleration, braking, and skidpad data.

### Medium Priority

- Convert the main lap sim from a script into a function with explicit input/output structs.
- Remove more global variables over time.
- Add an automated smoke-test script that runs one baseline and one small sweep.
- Add a structured config file for vehicle, tire, aero, track, and sweep settings.
- Add plots for CL/CD/CoP sensitivity and event tradeoffs.

### Higher-Fidelity Future Work

- Add ride-height-dependent aero maps.
- Add yaw-dependent aero maps.
- Add speed-dependent cooling or drag terms if needed.
- Re-optimize racing line for final aero candidates.
- Add tire temperature or pressure correction if data is available.
- Add uncertainty bands for tire scaling, mass, aero coefficients, and driver variation.

## Recommended Presentation Structure

1. Problem: we need aero goals that improve total dynamic score, not just downforce.
2. Method: use the lap sim to sweep `CL`, `CD`, and front aero balance.
3. Refactor: made the sim repeatable, parallel, and validation-ready.
4. Model flow: tire/powertrain/vehicle inputs -> GGV envelope -> track integration -> event scoring.
5. Results from verification: baseline and parallel smoke test ran successfully in MATLAB R2026a.
6. Assumptions: constant aero, quasi-static dynamics, tire scaling, fixed racing line.
7. Validation plan: compare speed, accel, lateral g, gear, and distance traces against logged data.
8. Next steps: regenerate autocross racing line, run large sweep, accurate reruns, validate with IRL data.

## Short Defense Script

The goal of this version is not to claim perfect absolute lap times. The goal is to make a consistent, repeatable aero trade study that tells us which combinations of downforce, drag, and aero balance are worth pursuing. The sim uses our existing tire, vehicle, powertrain, and track models, then evaluates each aero case through the same GGV envelope and scoring pipeline. Because every aero case is independent, the sweep is parallelized with MATLAB's Parallel Computing Toolbox. I also added validation outputs so we can compare simulated speed, acceleration, lateral g, gear, and distance traces directly against real logged data. The model still has simplifications, especially constant aero and quasi-static dynamics, but those assumptions are appropriate for early aero target selection and can be improved once we have more measured aero and track data.

