# The MATLAB sim, the Python port, and what changed

This is the in-depth technical record. It covers, in order: how the original MATLAB
lap sim works, the assumptions baked into it, what to investigate or fix in the MATLAB,
what the Python port (`pylapsim`) changed and why, what was kept bit-identical for
validation, how this branch differs from `origin/main`, and why MATLAB is a limiting
choice for *this particular* project.

The verified bug register lives in [../handover/FINDINGS.md](../handover/FINDINGS.md)
(items F1–F7, with exact line refs and corrected formulas); the measured impact of the
one physics fix is in [PHYSICS_DELTA.md](PHYSICS_DELTA.md); the parity numbers are in
[VALIDATION.md](VALIDATION.md). This document ties them together and adds the
"why MATLAB" argument the team asked for.

All coefficients here are **force coefficients in the sim's own units**: `DF = CL·V²`,
`drag = CD·V²` with V in ft/s and force in lbf. They are *not* CFD nondimensional
coefficients — air density and frontal area are folded in. Where a dimensional
conversion is needed, ρ = 0.002377 slug/ft³ (standard sea level).

---

## 1. How the MATLAB works

Repo root: the MATLAB lives under `Lap Sim March 2026/`. The active entry point is
`Aero/Lap_Sim_constantAero_T27V4.m` ("V4"); the batch driver is
`Aero/Run_T27_AeroSweep_MultithreadedExcel.m`. All `file:line` refs below are against
the files as they sit on disk at this branch's base.

### 1.1 The model

It is a **quasi-steady-state, point-mass lap simulator** built around a **g-g-V envelope**
(the code calls it the "GGV diagram"). It never integrates equations of motion forward
in time with a real chassis state. Instead it:

1. Pre-computes the vehicle's **maximum longitudinal acceleration, maximum braking, and
   maximum cornering capability as functions of speed** (and turn radius). These become
   cubic-spline lookups: `accel`, `grip`, `deccel` (functions of V) and `lateral`,
   `cornering` (functions of V and radius). See `Lap_Sim_constantAero_T27V4.m:384-385`,
   `:745-752`.
2. Lays a fixed **racing line** through cone "gates" digitized from the 2019 FSAE
   Michigan tracks, computes the **local radius of curvature** at every point
   (`curvature.m` → `circumcenter.m`), and finds the corner-limited max speed per point.
3. Runs a **forward–backward pass** (the "quasi-steady-state" / QSS velocity profiling):
   a forward acceleration pass, a backward braking pass, then combines them by taking the
   lower velocity at each point (`lap_information.m:295-322`). The combined trace gives the
   lap time.

Mid-corner, available longitudinal acceleration is reduced by a **friction-ellipse
coupling**: `ax = AX·(1 − (min(AY,ay)/AY)²)` (`lap_information.m:133`, `:264`). That is the
only place lateral and longitudinal demand are traded against each other in the lap
integration.

The cornering capability itself comes from a **quasi-static bicycle-model solve** at each
radius: find steering angle `delta` and body slip `beta` that balance lateral force and
yaw moment, sweeping speed up until no balanced solution exists. That defines the cornering
envelope.

### 1.2 What each `.m` file does

**Top-level / driver**
- `Aero/Lap_Sim_constantAero_T27V4.m` — the whole simulation, top to bottom (tire /
  powertrain / vehicle / aero setup → GGV generation → endurance lap → autocross lap →
  points scoring → suspension load cases). ~1150 lines, a **script** (not a function — it
  leaves variables in the workspace).
- `Aero/Run_T27_AeroSweep_MultithreadedExcel.m` — the batch runner. Builds a CL/CD/CoP grid
  (`ndgrid`, line 109), runs each case via `parfor` calling the core script, ranks by
  event, applies a **feasibility filter** (downforce/drag/LD windows at a reference speed,
  `addFeasibilityColumns`), reruns the top-N at high resolution, and writes a multi-sheet
  `.xlsx`.
- `Aero/resolveT27ResolutionPreset.m` — maps `High/Medium/Low/Custom` to grid step sizes.
- `setupLapSimPaths.m` — `addpath(genpath(...))` helper.

**GGV envelope helpers**
- `Aero/aeroMapfn.m` — downforce front/rear + the ride-height / suspension-deflection
  response, iterated to convergence. With constant aero, `fnCl/fnCd/fnCoP` are constant
  handles (`:241-243`), so the ride-height loop is effectively a passthrough.
- `Aero/evalLongitudinalTireLimit.m` — vectorized peak longitudinal tire-force lookup over
  a slip-ratio sweep, from the longitudinal CSAPS spline `full_send_x`. Filters
  `|F| > 1000 lbf` as bad extrapolation (line 14).
- `lat_solve.m` — the quasi-static lateral force/moment residuals `[Fy; Mz]` for a given
  `(delta, beta)` (bicycle model with LLTD load transfer, roll, a locked-diff yaw term, and
  a rear drag-ellipse penalty `rscale`).
- `lat_objective.m` — the `fmincon` objective: weighted sum of squared `Fy/Mz` residuals
  plus continuity penalties pulling `(delta,beta)` toward the previous solution so the
  solver doesn't jump roots.
- `cAlpha_nonlcon.m` — nonlinear constraint forcing local rear cornering stiffness below a
  fraction (`nCa`) of on-center stiffness — keeps the solver on the stable side of the Fy/α
  peak.
- `Tire Data/MF52_Fy_fcn.m` — Magic Formula 5.2 lateral force from coefficient vector `A`
  (loaded from `A2356run008_MF52_Fy_GV12.mat`) plus scaling globals.

**Lap integration**
- `lap_information.m` / `lap_information_sprint.m` — endurance / autocross forward–backward
  velocity profiling + telemetry. `_sprint` is the autocross variant (different start
  velocity, single forward pass; the second forward pass is commented out).
- `lap_time.m` / `lap_time_sprint.m` — slimmed lap-time-only versions used as the objective
  inside the (commented-out) racing-line optimizer.
- `track_curvature.m` / `track_curvature_sprint.m` — "car stays inside the cones"
  constraints for that line optimizer.
- `curvature.m`, `circumcenter.m`, `arclength.m` — geometry helpers.

**Powertrain**
- `Powertrain/Powertrainlapsim.m` — given speed (m/s), returns wheel tractive force (N) and
  current gear by walking the gear ratios and interpolating the dyno torque curve.
  **Operates in metric** while the rest of the sim is imperial (`:353-356` converts back).
- `Powertrain/calc_shiftpoints.m` — optimal shift RPMs by comparing power-at-wheel between
  adjacent gears.

**Inputs**
- `Sim Data/Endurance_Coordinates_1.xlsx`, `Autocross_Coordinates_2.xlsx` — cone gates, read
  from the `Scaled` sheet (gate #, outside x/y, inside x/y; `:760-766`).
- `Sim Data/endurance_racing_line.mat`, `autocross_racing_line.mat` — pre-optimized
  gate-fraction line positions (one scalar per gate, 0–1).
- `Tire Data/*.mat` — MF5.2 lateral coefficients + the CSAPS longitudinal spline.
- Constants hardcoded in Sections 1–5 (weight, weight distribution, CG, wheelbase, gear
  ratios, dyno curve, aero targets).

### 1.3 The event pipeline

All four scored FSAE dynamic events are computed in Section 17 (`:949-1064`):

- **Acceleration** — a separate little forward integration over a 247-ft straight
  (`:983-1058`) using the `accel` spline; scored against `Tmin_accel = 4.109` s.
- **Skidpad** — analytic: take the `cornering` spline speed at the skidpad radius,
  `time = 2πR/V` (`:961-967`); scored against `Tmin_skid = 4.865` s.
- **Autocross** — a full `lap_information_sprint` lap on the autocross gates; scored against
  `Tmin = 48.799` s.
- **Endurance** — a full `lap_information` lap on the endurance gates; scored against
  `Tmin = 115.249` s.
- `Total_Points = Accel + Skidpad + Autocross + Endurance` (`:1064`). **There is no
  Efficiency event** — see §3.

Section 18 (`:1098-1122`) also emits suspension **load cases** (worst-case wheel loads at
peak accel / brake / lateral) for downstream FEA.

---

## 2. Assumptions baked into the MATLAB

These are modeling choices, not bugs. They define what the sim *is* — and what it is not.
An owner needs to know them before quoting any number.

- **Aero is a pure V² force coefficient, not a CFD coefficient.** The code says so directly
  (`:215-219`); air density and frontal area are folded into the coefficient. Defaults
  `CL=0.040, CD=0.020, CoP=0.450` (`:224-226`).
- **Constant aero / ride height has no effect.** With constant handles, the ride-height
  convergence loop in `aeroMapfn.m` does nothing physical (`:234-235`).
- **CoP is the front downforce fraction.** `DFf = DF·CoP; DFr = DF·(1−CoP)`
  (`aeroMapfn.m:19-21`); `0.45 = 45% front` (`:221-222`).
- **Lateral load transfer is single-axle, LLTD-split, CG over the mean track:**
  `WT = A_y·cg·W/mean([twf twr])/32.2`, split `WTF = WT·LLTD`, `WTR = WT·(1−LLTD)`,
  `LLTD = 38%` front (`lat_solve.m:35-38`, mirrored at `:524-526`). One averaged track, not
  separate axles.
- **Roll is a linear gradient decoupled from spring rates** (`rg_f = rg_r = 0.5 deg/g`);
  it feeds only commented-out camber terms.
- **Camber is forced to zero everywhere.** Every kinematic camber expression is computed and
  then overwritten with `IA = 0` (`:344-345`, `:544-547`, `lat_solve.m:55-58`). All the
  Section-4 suspension-kinematics inputs (`:146-195`) are **dead** for the lateral solve.
- **Tire model is per-axle Fy, scaled, with no combined-slip ellipse at the tire.** Front
  uses a `cos(delta)` projection; the rear gets a drag-ellipse derate `rscale`. Global
  friction scales `sf_x = 0.45`, `sf_y = 0.50` are applied to all tire forces (`:86-87`) and
  are explicitly tuning knobs to be correlated to logged data.
- **Differential is a fixed-fraction locked-diff yaw moment** (`T_lock = 0.80`); commented
  "just ok, leave it open for most uses."
- **`A_Y` sign convention is assumed, not sourced.** "Positive A_Y loads the right side" is
  undocumented in the MATLAB; the port adopts it as a labeled assumption.
- **Acceleration is rear-tire-limited; braking uses all four tires.** Accel:
  `FX = abs(2·FXR)` (rear-drive, ignores fronts). Braking: `FX = abs(2·FXF + 2·FXR)`.
- **Scoring anchors are hardcoded 2019 Michigan times** and the formulas are the official
  FSAE points equations. **All scores are therefore relative rankings, not absolute 2026
  predictions** — quote deltas between candidates, not headline totals.
- **Fixed racing line.** The line is loaded pre-optimized; the `fmincon` line optimizer is
  commented out and the same line is reused for every aero case.
- **Vehicle mass is constant across all CL** (`W = 450 + 130` lbf) — a bigger wing package
  costs real pounds the model never sees.

---

## 3. What to investigate or fix in the MATLAB

The single fix that has been applied to V4 on disk is F1 (the load-transfer `/24`). The rest
below are open items — confirm them before trusting absolute numbers. Full evidence in
[../handover/FINDINGS.md](../handover/FINDINGS.md).

**F1 — Longitudinal load transfer `/24` (the headline bug; already fixed in V4 on disk —
verify any stale copies).** The committed code divided axle transfer by 24 and (in braking)
applied it twice, making longitudinal transfer ≈1/48 of physical on power and ≈1/24 on the
brakes — effectively **off**, which is why CG height never seemed to matter. The fix restores
`ΔW_axle = Ax·W·cg/l` (≈117 lbf/axle per g). V4 on disk now carries explanatory comments at
both fix sites (accel `:332-336`, brake `:682-686`). **Measured impact** (PHYSICS_DELTA):
**+34.3 pts mean** over the 176-case grid, accel time −8.7%, driven almost entirely by launch.
**Action:** confirm any circulating V1–V3 / shared copies carry the patched form, and re-run
the corrected V4 *in MATLAB* to close the loop (it is currently Python-validated only).

**F2 — Efficiency event is missing, so drag is nearly free.** `Total_Points` omits the
100-pt Efficiency event — the only event that punishes drag. Sweeping CD 0.015→0.030 costs
only ~9 pts while 60-mph drag doubles. **Any aero recommendation from this sim
systematically under-penalizes drag.** This is the single most consequential gap for the
stated purpose (choosing an aero target). The formula is implemented and cited in the port
(`pylapsim/scoring.py`, FSAE Rules 2026 §D.13.4) but stays null pending team BSFC inputs.

**F7 — the lateral envelope records failed solves.** In the cornering loop, the step-back
solve's results are written into `latResults` even when `exitflag < 1` (the code flags this
itself at `:488-491`). Failed-solve rows should be flagged so the downstream `csaps`/`fnxtr`
cornering fit can exclude them; as-is they can distort the spline.

**Tire FZ extrapolation guard is crude.** `evalLongitudinalTireLimit.m:14` just NaNs out
`|F| > 1000 lbf`; `lat_solve` has no FZ-range guard at all. After the F1 fix, rear-wheel load
reaches ~240 lbf and **exceeds the FX spline's fitted −250 lbf range once downforce is
added** — beyond that, forces are cubic CSAPS extrapolations. The `:697-699` "FZ
extrapolating beyond bounds" warning was disabled. **Investigate** whether high-DF points
are extrapolated tire data; TTC FX data over −250…−350 lbf would remove it.

**Unit boundary at the powertrain interface.** `Powertrainlapsim` is metric-only, called as
`Powertrainlapsim(max(7.5,V/3.28))` then converted `FX = output(1)*.2248` (N→lbf). The
`max(7.5,…)` / `max(…,10)` launch-speed floors ("7.5 reg, 10 launch") are magic numbers with
no derivation. Mixed unit systems across the file are a standing error risk.

**`a`/`b` reused and recomputed inside the cornering loop** (front-axle distance; also `A`,
the tire-coefficient matrix, differs only by case). A V2 bug clobbered `a` to 1 before
cornering; V4 renamed variables to fix it. **Verify** no remaining shadowing.

**Lateral clamp to `fnval(lateral,116)` is a hardcoded magic speed**
(`lap_information.m:323-324`). 116 ft/s ≈ 79 mph appears as a literal in several places; if
`top_speed`/VMAX differs, the clamp silently mis-scales lateral telemetry.

**Global state coupling.** `shift_points` and `gear` are globals written during GGV
generation and read during scoring; `gear` is reused as both a ratio vector and a scalar
index. The script is order-dependent and hard to test in isolation; `parfor` works only
because each worker re-runs the whole script in a fresh-ish workspace via `evalc('run(...)')`.

**Study-design issues (bias the answer, not code bugs).** The recommendation sits pinned at
the feasibility cap and CoP-grid edge with points still rising monotonically (F3/F6); the
feasibility window is acknowledged placeholder; vehicle mass is constant across all CL (F5).
See [FUTURE.md](FUTURE.md) for how these became the open-work list.

---

## 4. What the Python port changed and why

`pylapsim` is a numerically-faithful re-implementation of V4 plus its sweep driver. It is
validated bit-for-bit against committed MATLAB output (legacy mode) and adds an opt-in
physics correction, honest energy accounting, an airfoil layer, and a goal-seek/UQ layer.
The module map and data flow are in [../handover/DATA_CONTRACT.md](../handover/DATA_CONTRACT.md)
and the repo map in [../HANDOVER.md](../HANDOVER.md) §4. How to run it is in
[RUNNING.md](RUNNING.md) — not repeated here.

### A. The corrected F1 load transfer (opt-in via `--corrected`)

The port encodes **both** behaviors and switches on `cfg.legacy_compat`:

- **Accel** (`ggv.py:135-138`): legacy `WR + Ax·cg·(W/2)/l/24` vs corrected full-axle
  `WR + Ax·W·cg/l` (halved to per-wheel a few lines later).
- **Brake** (`ggv.py:183-186`): legacy `Ax·cg·WS/l/24·2.0` (the /24-applied-twice) vs
  corrected per-wheel `Ax·cg·WS/l` applied once.

`--legacy` (the default) reproduces V4-as-committed *including* the F1 bug — necessary
because the regression oracle was generated with the bug. `--corrected` runs the fixed
physics. Flipping legacy→corrected on the 176-case grid is **+34.3 pts mean** (Accel +22.5,
Endurance +10.9, Autocross +4.1, Skidpad −3.2), Spearman 0.9855.

**Deliberate amendment to the FINDINGS prediction** (measured, documented, not hidden): F1
predicted braking would *drop* after the fix. It does not — the committed FX spline is nearly
load-linear over its fitted −50…−250 lbf range, so front-biasing braking load costs nothing
in this tire model (deccel +1…3%). See PHYSICS_DELTA §2 and the amendment in FINDINGS.

### B. Solver substitutions (behaviorally equivalent, faster)

- **Cornering envelope:** V4's `fmincon` is replaced with a MINPACK hybrid root solve (fast
  path) falling back to bounded constrained SLSQP, replicating V4's exact accept/reject test
  (converged AND `|normalized residuals| ≤ 1e-2`, `ggv.py:36, 276-298`). Because V4 records
  lateral g from the stepped-back V regardless of the final solve, the envelope output
  depends only on the per-(R,V) accept/reject decision, which is preserved.
- **F7 kept faithfully:** the port records the stepped-back result "regardless" of the final
  step-back solve (matching V4's quirk) **plus** `lat_ok` diagnostics so failing rows can be
  flagged — strictly more information than the MATLAB, same numbers.

### C. What was kept bit-identical (so validation means something)

Everything not involving the autocross geometry reproduces the MATLAB chain to 1e-6 or
better in legacy mode:

- MF5.2 lateral model and the FX pp-form tensor spline with `fnval` nearest-piece
  extrapolation; the loader verifies coefficient layout via C1-continuity.
- `csaps` auto-`p` smoothing for the envelope fits; `Fnxtr2` reproduces `fnxtr(sp,2)`.
- Fixed-point `Ax += 0.01` envelope marching, vectorized but "lockstep with V4's serial
  walk; identical iterates per velocity."
- Quasi-steady forward/reverse passes, friction-ellipse de-rating, the quadratic time step,
  shift freezing, `VD`-based combination, the `lateral(116)` cap then curvature-y sign.
- Scoring formulas and 2019 anchors verbatim; the powertrain dyno table, PCHIP resample, and
  `calc_shiftpoints` edge cases.

### D. A data-provenance finding (not a behavior change)

The committed autocross **oracle** embeds a **2334.1 ft** path, but the committed
`Autocross_Coordinates_2.xlsx` + `autocross_racing_line.mat` produce a **2727.95 ft** path.
The port's geometry matches two independent committed MATLAB workspaces
(`distance_ax = 2727.9547…` ft) to **1e-10** — i.e. MATLAB on the committed inputs produces
the same geometry the port does. Per the "repo wins" rule the committed inputs are
authoritative; autocross runs the 2727.95 ft path and the two autocross Gate-A assertions are
encoded as strict `xfail`. Full proof in [VALIDATION.md](VALIDATION.md) §3. **Autocross
absolute times are the least-trusted numbers; rankings are unaffected** because the offset is
common to all targets.

### E. What the port adds beyond V4

- **Honest energy accounting** (`energy.py`): `DragEnergy = Σ CD·V²·dd` and
  `TractiveEnergy = Σ max(W·ax_g + CD·V², 0)·dd`. Assumption-free, for the (still un-scored)
  Efficiency event.
- **The Efficiency formula** (`scoring.py`), cited to FSAE Rules 2026 §D.13.4 — returns
  `None` until the team supplies BSFC + fuel density + competition anchors.
- **An airfoil layer** (`airfoils.py`): UIUC coordinates + XFOIL polars, the CL_target↔CL·A
  units bridge, and a wing suggester with cited rules-box limits. See
  [AIRFOIL_SELECTION_PLAN.md](AIRFOIL_SELECTION_PLAN.md).
- **Goal-seek / UQ** (`optimize.py`): NSGA-II multi-objective, Monte-Carlo + Sobol indices —
  every range labeled unsourced/assumed.
- **A test suite** (`tests/`) — the MATLAB-parity gate, tire continuity, contract, and
  airfoil tests. **44 passed, 1 skipped, 2 xfailed** (the autocross data issue).

---

## 5. How this branch differs from `origin/main`

The branch `pylapsim` branched from `origin/main` at commit `e5fd7e2` — the MATLAB-era
baseline (the MATLAB sim, its inputs, and the engineering reports, with no Python port and no
dashboard). Everything below is added on this branch:

- **`pylapsim/`** — the entire Python port and its CLI.
- **`tests/`, `pytest.ini`, `conftest.py`** — the parity + unit test suite.
- **`scripts/`** — sweep runners and the dashboard-data / track-geometry build scripts.
- **`dashboard-app/` + `handover/dashboard/`** — the web study UI and its prebuilt output.
- **`docs/` and `handover/`** — this technical record (validation, physics delta, findings,
  data contract, convergence, airfoil plan, and these handover docs).
- **`requirements.txt`** — pinned Python deps.
- **One edit inside the MATLAB tree:** the F1 fix applied to
  `Lap Sim March 2026/Aero/Lap_Sim_constantAero_T27V4.m` with explanatory comments at the two
  fix sites. The MATLAB physics is otherwise the `e5fd7e2` baseline.

To see the exact file-level delta from the baseline: `git diff e5fd7e2 --stat` (this compares
the working tree against the base, so it captures the change set whether or not the snapshot's
wrap-up work has been committed yet).

---

## 6. Why MATLAB is a limiting choice for *this* project

This is about *this* codebase's needs — a reproducible aero-target sweep feeding a web
dashboard and a handover doc — not a generic language preference. The MATLAB *physics* is a
reasonable QSS point-mass lap sim; the limits are reproducibility, testability, unit safety,
and deployability.

- **No dependency/reproducibility story.** The sim hard-depends on three separately-licensed
  toolboxes — **Optimization** (`fmincon`), **Curve Fitting** (`csaps`, `fnval`, `fnxtr`),
  and **Parallel Computing** (`parfor`) — with no manifest pinning versions. A teammate on a
  different release or toolbox set can get different `csaps`/`fmincon` behavior with no
  warning. The port pins exact versions in one `requirements.txt`.
- **Licensing blocks the deployment target.** The whole reason the port exists is to serve
  results to a browser. MATLAB Runtime/Compiler licensing makes "run the sim behind a web
  endpoint" expensive and awkward; the free Python/NumPy/SciPy stack wires into a web UI with
  no per-seat license.
- **Script-with-globals architecture resists testing.** V4 is a 1150-line script mutating
  ~20 globals and relying on workspace residue. There is no way to unit-test "compute the
  cornering envelope" without running the entire pipeline; the parallel runner only works by
  re-`run`-ning the whole script per case inside `evalc`. The known bugs above — F1's `/24`,
  recorded failed solves, the FZ extrapolation — are exactly the kind a function-level test
  harness catches. MATLAB's testing story here was effectively "eyeball the plots."
- **No types, no lint, silent unit mixing.** The file mixes lbf/N, ft/m, deg/rad, and
  g/(ft·s⁻²) with conversions scattered inline. The metric powertrain boundary and the
  `116 ft/s` magic clamp are the predictable result. Nothing complains about a dimensional
  mismatch — which is precisely why the `/24` bug survived multiple car generations.
- **Vectorization-vs-readability tension.** The performance-critical loops (the `Ax`
  convergence `while`, the per-radius `fmincon`) are iterative physics written as explicit
  scalar loops — so MATLAB's vectorization advantage doesn't apply while its weaknesses (slow
  scalar loops, JIT opacity) do. The team's answer was the Parallel Toolbox runner, which
  adds the licensing + reproducibility costs above just to claw back speed.
- **Binary, non-diffable inputs and outputs.** Track lines and tire models live in `.mat`;
  results in `.xlsx`. None of this version-controls meaningfully — a racing-line change is not
  reviewable in a diff — and the `.asv` editor-autosave files MATLAB leaves behind (cleared from
  this snapshot) should never be committed in the first place.
- **Tooling/web integration is the actual deliverable.** The repo already has the port, the
  pytest suite, and the dashboard. Keeping MATLAB as the source of truth means every result
  round-trips through a licensed desktop tool before it reaches the UI — which is why the port
  was validated to 0.000% against MATLAB and is now the integration target.

The honest read: MATLAB was likely chosen because it was the language the team knew and the
toolbox functions (`fmincon`, `csaps`) were close at hand — not because it fit a
version-controlled, testable, web-deployed decision tool. The port keeps the physics and
fixes the fit.
