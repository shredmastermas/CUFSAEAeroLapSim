# pylapsim validation — Gate A results

Engine: `pylapsim` 0.1.0, `legacy_compat=True` (reproduces V4-as-committed
physics including FINDINGS F1, because the oracle was generated with the bug).
Oracle: committed artifacts in `Lap Sim March 2026/Test Results/` @ e5fd7e2.
Encoded as pytest: `tests/test_gate_a.py` (`--run-slow` adds the 176-case gate).

## 1. Validation case — CL 0.040 / CD 0.020 / CoP 0.450, High preset

vs `T27_validation_summary_CL_0_040_CD_0_020_CoP_0_450.csv`:

| KPI | MATLAB | pylapsim | Δ | band | verdict |
|---|---|---|---|---|---|
| Endurance_Lap_Time [s] | 131.39842 | 131.39842 | **+0.000%** | ±1.5% | PASS |
| Autocross_Time [s] | 59.04322 | 56.24957 | −4.732% | ±1.5% | **FAIL — data, not code (§3)** |
| Skidpad_Time [s] | 4.95640 | 4.95640 | **+0.000%** | ±1.5% | PASS |
| Accel_Time [s] | 4.96794 | 4.96794 | **+0.000%** | ±1.5% | PASS |
| Endurance_Max_Speed [ft/s] | 92.1235 | 92.1235 | +0.000% | (info) | PASS |
| Max_Abs_AY [g] | 2.13900 | 2.13900 | **+0.000%** | ±4% | PASS |
| Max_AX [g] | 0.55257 | 0.55257 | +0.000% | ±6% | PASS |
| Min_AX [g] | −1.04862 | −1.04862 | +0.000% | ±6% | PASS |

“+0.000%” is not rounding spin: agreement is at the 1e-6-or-better level —
the port reproduces the MATLAB chain numerically (csaps auto-p smoothing,
pp-form tensor tire spline, fmincon-equivalent cornering accept/reject,
fixed-point envelopes, quasi-steady passes, scoring).

Speed-vs-distance RMS vs the committed trace
(`docs/figs/gateA_speed_trace_overlay.png`):

| Event | RMS [% of mean event speed] | gate ≤4% |
|---|---|---|
| Endurance | **0.000%** (bit-for-bit overlay) | PASS |
| Autocross | 57.07% | FAIL — different geometry (§3) |

## 2. 176-case fast sweep vs `T27_AeroSweep_Multithreaded_Results.xlsx`

All 176 Fast combos matched by (CL, CD, CoP). Medium preset, `legacy_compat=True`.

| Gate | threshold | measured | verdict |
|---|---|---|---|
| Spearman rank corr, Total_Points | ≥ 0.98 | **0.9948** | PASS |
| mean ΔTotal | ±1.5 pts | +16.01 | FAIL — autocross geometry (§3) |
| max \|ΔTotal\| | ≤ 5 pts | 22.39 | FAIL — autocross geometry (§3) |
| mean Δ(Total − Autocross_Score) | ±1.5 pts | **−0.248** | PASS (port fidelity) |
| max \|Δ(Total − Autocross_Score)\| | ≤ 5 pts | **3.871** | PASS — inside the ±3.95 F4 noise band |

Per-event deltas (py − MATLAB), n=176:

| Event score | mean Δ | max \|Δ\| | Spearman |
|---|---|---|---|
| Accel | −0.000 | **0.000** | 1.00000 |
| Skidpad | −0.002 | 0.925 | 0.99495 |
| Endurance | −0.245 | 3.072 | 0.99578 |
| Autocross | +16.254 | 21.469 | 0.96721 |

AccurateRerun rows (High preset): 9 of 10 (CL, CD, CoP) keys overlap between
the two pipelines' top-10 selections; on those rows
Δ(Total − Autocross_Score) is mean −0.49 / max |2.13| pts and Accel matches
to 0.0000 — same picture at the accurate resolution.

Endurance/skidpad scatter at Medium preset comes from the cornering-envelope
continuation: accept/reject differences of a single 0.25 ft/s V-step between
fmincon and the hybrid root/SLSQP solve. At High preset (validation case) the
agreement is exact; the residual Fast-pass scatter sits inside MATLAB's own
measured fast-vs-accurate noise (±3.95 pts, FINDINGS F4).

## 3. The autocross discrepancy is a data-provenance issue, not a port bug

Claim: **the committed autocross oracle (workbook + validation trace) was
generated from an autocross geometry whose source data is not in the repo.**
Evidence, all reproducible from committed artifacts:

1. The committed validation trace's autocross path is **2334.11 ft** long.
   The committed inputs (`Sim Data/Autocross_Coordinates_2.xlsx` 'Scaled',
   48 gates + `autocross_racing_line.mat`, 48 positions) produce a
   **2727.95 ft** path through V4's documented construction.
2. Two independent committed MATLAB workspaces —
   `Test Results/latestpgResults.mat` and `latestLLTDResults.mat` — contain
   `distance_ax` with total **2727.9547458626157 ft**. pylapsim computes
   **2727.9547458625866 ft** from the committed inputs: agreement to 1e-10
   relative. MATLAB itself, run on the committed inputs, produced the same
   geometry the port produces. (Pinned by
   `tests/test_gate_a.py::test_autocross_geometry_matches_committed_inputs`.)
3. The trace's curvature-vs-distance profile does not correlate with the
   committed-input path under any tested hypothesis (corr 0.11; tested:
   forward/reversed direction, pure rescaling, 1−p and p=0.5 position
   transforms, 'Shifted'/'Raw Points' sheets, the stale
   `Sim Data/path_boundaries.mat`, t-range variants, windows of the
   endurance track).
4. The xlsx and racing-line .mat are byte-identical at both repo commits
   (1232b0d, e5fd7e2), so no committed revision explains it. V4's own
   Section-15 warning code (added for a position/gate count mismatch) shows
   the autocross inputs were in flux during development.
5. Everything that does not involve the autocross geometry matches at
   1e-6 or better (§1) — endurance shares every code path with autocross
   except the coordinate data.

Suspected cause: the sweep workbook and validation trace were generated on
the dev machine with an earlier/longer-gate-count `Autocross_Coordinates_2`
(V4's truncation warning hints at a 57-gate era) and the reorganized repo
committed a different revision of that file.

### Consequences adopted (brief: “the repo wins”)

- pylapsim treats the **committed inputs as authoritative** for all new
  results; the autocross event therefore runs the 2727.95 ft path.
- The two autocross-dependent Gate A assertions are encoded as **strict
  xfail** in pytest with this section as the reason. If the team restores the
  original coordinate file, they will flip to passing and the caveat must be
  removed.
- Ranking conclusions are safe: the geometry offset is common to all aero
  targets (Spearman 0.9948 across the full grid), and FINDINGS F2-F6 are
  about deltas between targets, not absolute times.
- **Team follow-up (added to PROJECT_TODOS):** regenerate the autocross
  oracle in MATLAB from the committed inputs, or commit the coordinate file
  that produced the 2334 ft path.

## 4. Performance

| Target (brief) | measured | verdict |
|---|---|---|
| 1 case (GGV + all events) ≤ ~1 s warm | 1.3 s (Medium) / 2.5 s (High), warm | slightly over at High; documented |
| 176-case grid ≤ ~3 min | **65 s** on 6 cores (incl. 10 accurate reruns) | PASS |

Runtime is dominated by the cornering-envelope continuation (hybrid MINPACK
root solve with SLSQP fallback, warm-started). Single-case ~1 s is met at the
fast preset; the High preset costs 2.5 s because it runs ~4× the cornering
solves. No further optimization attempted — sweep throughput is the binding
target and passes with 3× margin.

## 5. Figures

- `docs/figs/gateA_speed_trace_overlay.png` — speed vs distance, both events,
  pylapsim vs committed trace (data: the committed validation trace CSV +
  pylapsim run of the same case).
- `docs/figs/gateA_ggv_envelopes.png` — longitudinal/lateral/cornering
  envelopes for the validation case (data: pylapsim GGV from committed tire
  .mat files).
