# CUFSAEAeroLapSim — Handover

**Read this first.** It orients you (human or LLM) to the whole repository, points to the
deeper docs in the right order, tells you how to run everything, and lists the open work.
If you are taking ownership, also read **[§8 Before you make this your own](#8-before-you-make-this-your-own)**.

---

## 1. What this is

A decision tool for the Clemson FSAE (CUFSAE) **T27 aero target study**: pick the front/rear
downforce and drag (the `CL` / `CD` / `CoP` aero coefficients) that maximize FSAE competition
points. It has two halves joined by one data file:

- **`pylapsim/`** — a Python lap-time simulator. A numerically faithful re-implementation of the
  team's MATLAB lap sim (`Lap Sim March 2026/Aero/Lap_Sim_constantAero_T27V4.m`). You run *sweeps*
  (many aero setups at once) and get an Excel workbook of scores per setup.
- **`dashboard-app/`** — a small web "study UI" that turns a sweep workbook + a lap trace into an
  interactive explorer (heat-map of points, balance/CoP instrument, track maps, sensitivity charts,
  a real-world wing sizer). Its data is **baked into the source** — no server or database at view time.

The Python sim is validated to **0.000%** against the MATLAB reference on every event except one
(autocross, which is a known data-provenance issue, not a code bug — see §3).

## 2. The 30-second mental model

```
 track coords + tire/vehicle data ──► pylapsim ──► sweep workbook (.xlsx) + lap trace (.csv)
                                                          │
                                          build scripts inline the data into
                                          handover/dashboard/t27-aero-dashboard.jsx
                                                          │
                                          dashboard-app (Vite) builds it into a static site
                                                          │
                                                    browser: the study UI
```

The simulator decides *what the numbers are*; the dashboard makes them *consumable*. They are
decoupled — you can regenerate either side independently.

## 3. Current state (what's done, what's trusted)

- **Physics port:** complete and validated. `pylapsim` reproduces the MATLAB chain bit-for-bit
  (1e-6 or better on every KPI) in `legacy` mode, and adds an opt-in `--corrected` mode that fixes a
  load-transfer bug (see §5 / [docs/PORT_AND_MATLAB.md](docs/PORT_AND_MATLAB.md)). Test suite:
  **44 passed, 1 skipped, 2 xfailed** (`pytest`). The 2 xfails are the autocross-geometry data issue.
- **Validation numbers:** [docs/VALIDATION.md](docs/VALIDATION.md) — Gate-A KPI table + the autocross
  provenance proof. Rankings across a 176-case grid agree at Spearman **0.9948**.
- **Dashboard:** complete and current. Heat-map explorer, balance & CoP instrument (with 3D CG/CoP
  height views), real-2019-track maps (drawn from the sim's own cone edges + racing line), sensitivity
  charts, run statistics, and a real-world wing sizer (single-element table + a multi-element designer).
  Every number on screen traces to the sweep/trace/track/airfoil data; the one labeled illustration is
  the CoP *vertical* height (the sim is a point mass with no vertical CoP).
- **What is NOT final** (open work, §7): the *feasibility envelope* is still a placeholder window
  (needs CFD or measured data), the *Efficiency event* is implemented but un-scored (needs a team BSFC
  number), and the *MATLAB F1 fix* is parity-checked via Python but not yet re-run in MATLAB itself.

## 4. Repository map

```
HANDOVER.md                ← you are here
README.md                  ← original project README (MATLAB-era workflow + layout)
requirements.txt           ← Python deps for the simulator + build scripts

pylapsim/                  ← the Python lap sim (the engine). See docs/PORT_AND_MATLAB.md §1.
  cli.py / __main__.py       python -m pylapsim run|sweep|validate
  config.py                  all constants as dataclasses, traced to MATLAB line numbers
  ggv.py tires.py track.py   physics: g-g-V envelope, tire models, track geometry
  lapsolver.py events.py     quasi-steady lap solve, skidpad/accel events
  scoring.py energy.py       FSAE points + energy accounting
  sweep.py optimize.py       aero-grid sweep + goal-seek/UQ
  airfoils.py io_contract.py airfoil layer + dashboard data contract
tests/                     ← pytest suite (MATLAB parity gates, tire/contract/airfoil tests)

scripts/                   ← run sweeps + rebuild the dashboard's inlined data (see docs/RUNNING.md)
  run_clamped_sweep.py       the production buildable-envelope sweep
  run_hires_sweep.py         a denser grid
  build_dashboard_data.py    splice a workbook+trace into the dashboard source
  build_track_geometry.py    rebuild the track maps (TRACK0) from the sim's geometry
  fetch_airfoils.py          airfoil reference data
  convergence_study.py       grid-resolution settling study

dashboard-app/             ← the web study UI host (Vite). See docs/RUNNING.md §4.
  dist-single/index.html     ← single self-contained file, SHIPPED — just open it in a browser
  vite.config.js             dev/preview server config
  vite.config.single.js      the standalone single-file build
  (dist/ — the multi-file served build — is produced by `npm run build`; not shipped, to stay lean)
handover/dashboard/t27-aero-dashboard.jsx   ← the dashboard itself (data inlined at the top)

Lap Sim March 2026/        ← the ORIGINAL MATLAB sim + its input data + the engineering reports
  Aero/Lap_Sim_constantAero_T27V4.m   the reference simulator ("V4")
  Sim Data/                  track cone coordinates + racing-line .mat files
  Tire Data/                 MF5.2 lateral + FX longitudinal tire models (.mat)
  Test Results/              MATLAB + Python sweep workbooks and validation traces

docs/                      ← the technical record (read order in §6)
analysis_pack/             ← a self-contained results/bibliography bundle
```

## 5. The one change you most need to understand: the load-transfer fix

The committed MATLAB had longitudinal weight transfer effectively switched off by a stray `/24`
divisor (and, in braking, applied twice). Net modeled transfer was ~1/48 of physical on power and
~1/24 on the brakes — which is why CG height never seemed to matter. The fix restores the textbook
`ΔW_axle = Aₓ·W·cg/l` (≈117 lbf/axle per g). Flipping it on (`--corrected`) is worth **+34.3 points
mean** across the grid (mostly acceleration), while rankings largely survive (Spearman 0.9855). Full
evidence: [docs/PHYSICS_DELTA.md](docs/PHYSICS_DELTA.md) and [handover/FINDINGS.md](handover/FINDINGS.md) (item F1).
The fix is applied in the V4 `.m` on disk **and** in the port, but has only been validated through the
port — re-running it in MATLAB itself is open work (§7).

## 6. Read these next (in order)

1. **[docs/RUNNING.md](docs/RUNNING.md)** — dead-simple operating guide: run a sweep, rebuild the
   dashboard data, view the UI (from "double-click a file" up to the full dev loop).
2. **[docs/PORT_AND_MATLAB.md](docs/PORT_AND_MATLAB.md)** — how the MATLAB works, what the Python port
   changed and why, what to investigate/fix in the MATLAB, and why MATLAB is a limiting choice here.
3. **[docs/VALIDATION.md](docs/VALIDATION.md)** — the MATLAB-parity proof (KPI tables, autocross provenance).
4. **[handover/FINDINGS.md](handover/FINDINGS.md)** — the verified bug register (F1–F7) with exact line refs.
5. **[docs/FUTURE.md](docs/FUTURE.md)** — suggestions for making this more consumable (MATLAB parity,
   a theming layer, a school-neutral version) plus the prioritized open-work list.
6. **[PROJECT_TODOS.md](PROJECT_TODOS.md)** — the live team checklist.

Other durable technical docs: [docs/PHYSICS_DELTA.md](docs/PHYSICS_DELTA.md) (corrected-vs-legacy
impact), [docs/CONVERGENCE_STUDY.md](docs/CONVERGENCE_STUDY.md) (grid is settled),
[handover/DATA_CONTRACT.md](handover/DATA_CONTRACT.md) (workbook schema the dashboard consumes),
[docs/AIRFOIL_SELECTION_PLAN.md](docs/AIRFOIL_SELECTION_PLAN.md) (the multi-element wing roadmap).

## 7. Open work (prioritized)

1. **Replace the placeholder feasibility window with real data.** The sweep's "buildable" bound is a
   rectangular placeholder (`pylapsim/sweep.py` `FeasibilityWindow`); the honest decision variable today
   is L/D. A measured/CFD `CD_min(CL)` polar unlocks the unconstrained optimum (~+17 pts).
2. **Supply the Efficiency-event inputs.** The FSAE Efficiency formula is implemented and cited
   (`pylapsim/scoring.py`, Rules 2026 §D.13.4) but returns `None` until the team provides BSFC, fuel
   density, and the competition efficiency anchors. Until then, **drag is under-penalized**.
3. **Re-run the F1 fix in MATLAB** to close the validation loop (it is currently Python-validated only).
4. **Resolve the autocross oracle provenance** — the committed inputs give a 2727.95 ft path; the
   committed oracle embeds 2334.1 ft. Regenerate the oracle from the committed inputs, or commit the
   coordinate file that produced 2334 ft. (Rankings are unaffected; absolute autocross times are not trusted.)
5. **Tire data above −250 lbf FZ** and a **sourced wing-package mass** — see [docs/FUTURE.md](docs/FUTURE.md).

## 8. Before you make this your own

This package is a working snapshot, and its working tree is **intentionally uncommitted**. On top
of 16 committed porting commits on the `pylapsim` branch, the wrap-up work sits as uncommitted
changes — most of the handover docs, the build scripts, and `requirements.txt` are *untracked* new
files, with a handful of files modified or removed. So `git diff e5fd7e2 HEAD` will **not** show the
full picture: run `git status` to see the uncommitted set and **`git diff e5fd7e2`** (working tree vs
the baseline) for the complete change set. Commit it under your team's identity as your first step
when you adopt the repo.

The **git history is included on purpose** — it carries the real development context (the phased
port, the validation gates, the dashboard iterations) and is worth reading to understand how the code
reached its current state. **Before you publish or push it under your own name, rewrite the
authorship/metadata to your team.** Practically:

```bash
# 1) Strip the co-author trailers from every commit message.
#    (Preferred: git-filter-repo — `pip install git-filter-repo`.)
git filter-repo --message-callback '
  return b"\n".join(l for l in message.split(b"\n")
                    if not l.startswith(b"Co-Authored-By:"))'

# Fallback if you cannot install git-filter-repo:
git filter-branch -f --msg-filter 'grep -v "^Co-Authored-By:"' -- --all

# 2) (Optional) re-point author/committer name+email to your team identity:
git filter-repo --name-callback 'return b"CUFSAE"' \
                --email-callback 'return b"aero@cufsae.example"'

# 3) Prefer a clean slate instead? Squash everything to a single fresh commit:
#    git checkout --orphan fresh && git add -A && git commit -m "T27 aero lap sim" && \
#    git branch -D pylapsim main && git branch -m pylapsim
```

The working tree itself is already free of external tooling references. The branch `pylapsim` holds all
of the porting + dashboard work; it branched from `origin/main` at commit `e5fd7e2`
(the MATLAB-era baseline). When you adopt it, decide whether to merge `pylapsim` into your `main` or
keep it as the new trunk.

## 9. House rules baked into the code (so you keep them)

- **No fabricated numbers.** Every value shown or scored traces to committed data, the documented
  formulas, or a *labeled* assumption. Assumptions are never silent (grep the dashboard for "assumption"
  / "illustration"; grep the sim for "placeholder" / "unsourced").
- **The repo wins.** Where a committed oracle disagrees with committed inputs, the inputs are
  authoritative and the discrepancy is documented (the autocross case).
- **Rankings before absolutes.** Scores anchor to fixed 2019 times, so they are relative comparisons,
  not absolute 2026 predictions. Quote deltas between candidates, not headline point totals.
