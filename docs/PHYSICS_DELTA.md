# Corrected-physics impact memo (FINDINGS F1 fix)

What changes in the team's answer when longitudinal load transfer actually
works. Both runs: pylapsim on the committed 176-case grid (Medium fast
preset, k_mass = 0), identical inputs, only `legacy_compat` flipped.
Data: `pylapsim sweep` runs of 2026-06-12; figure
`docs/figs/physics_delta_scatter.png`.

## Headline

| Metric | legacy (bug) → corrected |
|---|---|
| Total points, mean shift over 176 cases | **+34.3 pts** (range +28.1 … +43.0) |
| Spearman rank corr. legacy vs corrected | 0.9855 — rankings largely survive |
| Best grid target (CL ≤ 0.055) | CL 0.055 / CD 0.0175 / CoP 0.525 → **CL 0.055 / CD 0.0150 / CoP 0.525** |
| Validation-case accel time | 4.968 → 4.534 s (**−8.7%**) |
| Validation-case endurance lap | 131.57 → 129.41 s (−1.6%) |
| Validation-case skidpad | 4.975 → 5.010 s (+0.7%) |

Per-event mean shift (corrected − legacy, 176 cases):

| Event | mean Δ | range |
|---|---|---|
| Accel | **+22.5 pts** | +21.5 … +23.6 |
| Endurance | +10.9 pts | +7.7 … +15.9 |
| Autocross | +4.1 pts | +2.2 … +7.5 |
| Skidpad | −3.2 pts | −5.5 … −1.5 |

## Mechanisms (measured, not assumed)

1. **Launch transforms.** With real transfer the rear axle gains
   ~117 lbf/g; the grip-limited envelope converges much higher
   (grip(43 ft/s): 0.59 → 0.74 g; grip(80): 0.76 → 0.96 g). Max forward AX
   in endurance rises +0.55 → +0.69 g. This is the dominant points shift
   (Accel is scored on a 1.5× Tmax window — steep).
2. **Braking is nearly unchanged** (deccel +1…3%), *contrary to the
   FINDINGS F1 expectation* that tire load sensitivity would cut braking.
   Measured cause: the committed FX spline is almost load-linear in the
   −50…−250 lbf fitted range (peak braking force ≈ −47.5/−149.4/−256.8 lbf
   at 50/150/250 lbf load, sf_x applied) — slightly *super*-linear at the
   top end — so front-biasing the load costs nothing in this tire model.
   FINDINGS F1's directional claim is amended accordingly.
3. **Skidpad slips slightly.** Higher longitudinal grip relaxes the
   drag-ellipse penalty (`rscale`) on the rear axle in the cornering solve;
   the rear's relative lateral capacity rises, the yaw balance shifts
   toward push, and the quasi-static (delta, beta) root is lost at slightly
   lower V on tight radii. Skidpad speed 34.81 → 34.47 ft/s.
4. **CG height now does something.** The transfer terms scale with
   `cg/l`; the PROJECT_TODOS CG-sensitivity study is now meaningful.

## Model-limit caveat

At corrected transfer levels the rear-wheel load reaches ~240 lbf/wheel at
1.5 g (no aero) and exceeds the FX spline's fitted FZ range (−250 lbf max)
once downforce is added at speed. Values beyond −250 lbf are cubic
extrapolations of the committed CSAPS fit, filtered only by the existing
|F| > 1000 lbf guard. Tire data covering −250…−350 lbf would firm up the
corrected accel/braking envelopes (added to PROJECT_TODOS).

## Mass-coupling sensitivity (F5; scenario bracket, unsourced)

`m(CL) = 580 + k_mass·(CL − 0.040)` lbf, k_mass ∈ {0, 250, 500} lbf per
unit CL_target (= {0, +2.5, +5.0} lbf per +0.010 CL step). The k values are
an **unsourced scenario bracket** — sensitivity only, not a claim.

- Measured mass cost at fixed aero: **−0.14 pts/lbf median** (−0.23 mean)
  across the grid (corrected physics).
- Across the bracket the optimum does not move: CL 0.055 / CD 0.0150 /
  CoP 0.525 wins at k = 0, 250 and 500 (447.4 / 446.9 / 446.0 pts) — at
  ≤ 5 lbf per 0.010 CL, added wing mass does not overturn the CL appetite
  within the committed grid. A real team-supplied wing-mass number is still
  wanted before quoting any mass-adjusted score.

## Takeaways for the aero target

- The F1 fix does not overturn FINDINGS F3/F6: points still rise toward the
  CL cap and the CoP grid edge; the optimum is still the feasibility window
  itself. CoP > 0.525 exploration happens in Phase 5.
- It *does* re-weight events: with launch fixed, Accel contributes ~22 more
  points everywhere — flat across targets, so aero rankings shift little
  (ρ = 0.986), but absolute scores and trade-off slopes (e.g. pts per lbf
  drag) change. Efficiency-relevant numbers in Phase 3+ use corrected
  physics only.
