# T27 dashboard host

A minimal Vite host for the committed consumer UI
(`handover/dashboard/t27-aero-dashboard.jsx`) — the dashboard the data
contract targets. No dashboard code is duplicated here; this app only mounts
it.

Design: "pit-wall run sheet" — warm engineering-paper theme with a drafting
grid, Barlow Condensed display type + IBM Plex Mono data type, one racing-red
signal color. Fonts and Tailwind are compiled into the bundle (no CDNs), so
it renders identically on isolated networks. Visual smoke check:
`node screenshot.mjs` (writes ./screenshots/, needs `npx playwright install
chromium` once).

## Run

```bash
cd dashboard-app
npm install   # first time only
npm run dev   # -> http://localhost:5273/
```

## What to load

The page opens seeded with the **committed MATLAB results** (the 186-case
sweep + the CL 0.040 validation trace baked into the jsx). To view the new
pylapsim results, use the two buttons at the top:

- **load workbook .xlsx** →
  `Lap Sim March 2026/Test Results/python/T27_AeroSweep_pylapsim_corrected.xlsx`
  (or `..._legacy.xlsx` for the apples-to-apples bug-mode comparison)
- **load trace .csv** →
  `Lap Sim March 2026/Test Results/python/T27_validation_trace_CL_0_050_CD_0_022_CoP_0_600.csv`
  (the recommended target; more traces under `python/traces/`, regenerable via
  `python -m pylapsim run --cl ... --cd ... --cop ... --corrected --out-dir ...`)

## Reading the tabs

A dismissible **START HERE** strip (load → explore → replay → compare) and
per-tab **WHAT / DATA SOURCE / TAKEAWAY** briefs are built into the UI; the
`? GUIDE` button in the nav brings the strip back.

- **Sweep explorer** — points landscape over CL/CD/CoP; ◆ best feasible,
  ★ best overall; with the corrected workbook loaded you should see the best
  feasible row at CL 0.050 / CD 0.0225 with CoP up at 0.600–0.625 (the old
  CoP 0.525 edge answer is beaten by ~5–7 pts).
- **Balance & CoP** — front/rear downforce splits at speed; in lap playback a
  **track minimap** shows the car's top-down position (exact X_ft/Y_ft from
  pylapsim traces; legacy traces fall back to a dead-reckoned shape labeled
  as such).
- **Sensitivity & noise** — fast-vs-accurate noise dots: the ±3.95 pt band;
  any ranking gap inside it is a tie.
- **Run stats** — mean / median / mode (binned) / range + histograms of every
  event time and total points across the loaded workbook's runs, with
  Fast / AccurateRerun / All scope chips.
