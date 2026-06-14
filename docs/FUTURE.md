# Where to take this next

Two halves: **suggestions** for making the project more consumable by other people (and
other teams), and the **prioritized open-work list** — the concrete things that block
trusting the aero conclusion. If you are taking ownership, read
[../HANDOVER.md](../HANDOVER.md) first, then this.

---

## Part A — Make it more consumable

### A1. Bring the MATLAB up to parity with the Python (or retire it)

Right now the Python port is the source of truth and the MATLAB is the historical reference
with one fix applied but **not re-run**. Pick a lane:

- **Parity path (keep MATLAB authoritative for the team's existing workflow):** re-run the
  corrected V4 in MATLAB to close the F1 validation loop (see open-work B3), then keep the two
  in lockstep with a thin parity harness — one constant-aero case + the sweep runner, asserting
  the MATLAB `.xlsx` matches the port's within the documented bands. Keep generated smoke files
  out of git.
- **Retire path (make Python the single source of truth):** treat the MATLAB as frozen
  reference, keep the tree free of editor autosave artifacts (`.asv`), and route all new physics
  work through `pylapsim` with its test suite. This is the lower-maintenance option and matches
  where the deliverables already live (the dashboard reads the port's output).

Either way, the value is removing the "which one is right?" ambiguity. The port already proves
they agree to 1e-6 everywhere except the autocross data issue — lock that in so it stays true.

### A2. A theming layer for the dashboard

The dashboard's look is currently hardwired into one component (palette `P`, type scale `FS`,
and the inlined CSS in `handover/dashboard/t27-aero-dashboard.jsx`). To make it reusable:

- **Extract the palette + type scale into a single theme object** (or a small CSS-variable
  block) so a school can re-skin without touching layout code. The two load-bearing brand
  values today are the accent (amber `#f56600`) and a violet for the racing line; everything
  else is neutral. Pull those into named tokens.
- **Keep the discipline, not just the colors.** The UI is deliberately data-first: real
  numbers and tables over decorative cards, monospaced figures, hierarchy by weight/color
  before size. A theme page should let someone change the *brand* without letting them break
  the *legibility* — document the contrast floor and the "numbers are monospaced" rule
  alongside the color tokens.
- **One toggle, not a framework.** A single light/dark or school-A/school-B switch that flips
  the theme object is enough; resist turning this into a design system.

### A3. A school-neutral version

The physics, the sweep, and the dashboard are not Clemson-specific — only the inputs and the
branding are. To make it a template other FSAE teams can pick up:

- **Parameterize the team identity** — name, colors, logo — through the theme object (A2) and
  a small config, so there are no hardcoded "T27 / CUFSAE" strings in the UI chrome.
- **Make the inputs the contract.** A team supplies their own tire `.mat`, track coordinates,
  racing line, vehicle constants (`pylapsim/config.py`), and 2019-equivalent score anchors;
  everything downstream is generic. Document the input set as the seam — most of it is already
  isolated in `config.py` and `Sim Data/`.
- **Ship a "your turn" checklist:** swap tire data → swap track coords → edit `config.py`
  constants → run the sweep → rebuild the dashboard. This is essentially [RUNNING.md](RUNNING.md)
  read as a template rather than a Clemson-specific guide.
- **Neutral defaults.** Where a value is Clemson-measured (tire scale factors `sf_x`/`sf_y`,
  the CoP grid, the feasibility framing), label it as an example, not a recommendation, so a
  borrowing team doesn't inherit a number that was only ever right for one car.

### A4. Smaller consumability wins

- **Resolve the cross-doc feasibility-framing inconsistency** (it appears three ways across the
  docs — see [VALIDATION.md](VALIDATION.md) and the findings). State one current position
  (no binary verdict; judge by L/D) and label the others historical.
- **Fold the one-shot process docs** that were scaffolding into the durable record so a new
  reader isn't misled by stale instructions (the handover doc set already supersedes them).
- **Add a `docs/validation_plan.md`** listing the logged channels a real track test needs
  (GPS/IMU/wheel-speed/steering/throttle/brake-pressure/RPM/gear/damper pots) so the next
  correlation effort has a target.

---

## Part B — Open work, prioritized

The first three items are what actually block trusting the aero conclusion. Everything scores
relative to fixed 2019 anchors, so **rankings between candidates are safe; absolute totals are
not** — keep that in mind when reading "+N pts."

### B1. Replace the placeholder feasibility window with real data — *highest value*

The "buildable" bound is a rectangular placeholder (`pylapsim/sweep.py` `FeasibilityWindow`:
DF 90–135 lbf, drag 40–65 lbf, L/D 2.0–2.4 at 35 mph, centered on last year's estimate). The
unconstrained sweep optimum is implausible (≈CL 0.160 / L/D 16) — a model-limit artifact, not
a goal. The honest decision variable today is **L/D**. A measured or CFD **CD_min(CL) polar**
replaces the placeholder and unlocks the real optimum, worth **~+17 pts**. This is the single
biggest blocker. (Note: the sweep *verdict* was relaxed to a DF≥90 floor in the 2026-06-13
decision, but `optimize.py` still uses the full six-bound window as hard constraints —
reconcile these when the real polar lands.)

### B2. Supply the Efficiency-event inputs — *drag is currently under-penalized*

The FSAE Efficiency formula is implemented and cited (`pylapsim/scoring.py`, Rules 2026
§D.13.4) but `Efficiency_Score` returns `None` until the team provides: **BSFC (g/kWh)**, fuel
density with provenance, and the competition efficiency anchors (`t_min`, `laps_tmin`,
`co2_min`, `laps_co2min`, `eff_factor_max/min`) — these are outcomes of a real competition and
cannot be invented. Until then `Total_Points` omits the only event that punishes drag, so every
aero recommendation systematically under-penalizes CD.

### B3. Re-run the F1 fix in MATLAB — *close the validation loop*

The load-transfer correction (worth +34.3 pts mean) is applied to V4 on disk and parity-checked
through the port, but has **not been run in the MATLAB runtime**. Run the corrected V4 in MATLAB
and confirm it reproduces the port's corrected-mode numbers, so the team's own tool agrees.

### B4. Resolve the autocross oracle provenance — *data integrity*

The committed inputs give a 2727.95 ft path; the committed oracle embeds 2334.1 ft. Either
regenerate the oracle in MATLAB from the committed inputs, **or** commit the coordinate file
(and/or regenerate `autocross_racing_line.mat`) that produced the 2334 ft path. Rankings are
unaffected; absolute autocross times are the least-trusted numbers until this is closed. The
parity tests are strict-xfail and will flip to passing automatically once the inputs reconcile.

### B5. Acquire tire data above −250 lbf FZ — *removes an extrapolation*

In corrected mode, rear-wheel loads exceed the FX spline's fitted −250 lbf range; beyond that
the committed CSAPS fit is cubic-extrapolated, guarded only by the `|F| > 1000 lbf` filter —
and that is exactly the high-CL region the corrected sweep favors. TTC FX data covering
−250…−350 lbf firms up the corrected accel/braking envelopes.

### B6. Supply a sourced wing-package mass

Vehicle mass is constant across all CL today (`W = 580 lbf`). The `m(CL) = m0 + k·(CL − cl_ref)`
coupling (`k ∈ {0, 250, 500} lbf/CL`) is an explicitly **unsourced** sensitivity bracket; the
optimum doesn't move across it (≈−0.14 pts/lbf), but a real wing-mass number is wanted before
quoting any mass-adjusted score.

### B7. Model-fidelity studies (now meaningful post-fix)

- **CG-height sensitivity study** — the transfer terms scale with cg/l, so this study finally
  has teeth. Sweep CG over a realistic range; plot total points and lateral capability vs CG
  height; confirm lower CG helps.
- **Braking-stability / forward-CoP review** — the corrected optimum sits at a forward CoP
  (~0.575–0.650), but the sim has **no braking-stability model**. Verify rear-axle margin under
  braking before adopting a forward CoP (see REPORT §4).
- **Real ride-height-dependent aero map** instead of constant aero — compare effective
  DF/drag/L/D/CoP by speed against the team's measured aero map.
- **Correlate the tire scale factors** `sf_x = 0.45` / `sf_y = 0.50` against logged
  accel/braking/skidpad data. This is the team's highest-value validation task — `sf_y`
  dominates absolute-score uncertainty (the Sobol indices didn't even converge at 768 runs).

### B8. Sweep-output / tooling polish

Add optional hard bounds (max CL, min CD, max L/D) to the sweep; generate the standard plot
set (points vs CL/CD/CoP/L-D; CL×CD colored by points; DF×drag at 35/60 mph); export top-10
feasible/overall presentation sheets; add a standard 25–60 mph force-conversion table to the
workbook. These are nice-to-haves once B1–B3 land.
