# Running it — the simple guide

Two halves: the **simulator** (Python) makes the numbers; the **study UI** (a web page) shows them.
You can just *look at the existing results* with zero setup, or *run your own sweeps* and rebuild the page.

All commands run **from the repository root** unless a step says `cd` somewhere.

---

## TL;DR

| I want to… | Do this |
|---|---|
| **Just look at the study** (no installing anything) | Open `dashboard-app/dist-single/index.html` in any browser (double-click it). |
| Look at it as a normal local site (needs Node) | `cd dashboard-app && npm install && npm run build && npm run preview` → open <http://localhost:5280/> |
| Run my own aero sweep | `pip install -r requirements.txt`, then `python scripts/run_clamped_sweep.py` (see §2) |
| Put new sweep results into the page | `python scripts/build_dashboard_data.py`, then rebuild the UI (§3–§4) |
| Develop the UI with live reload | `cd dashboard-app && npm install && npm run dev` |

---

## 1. Just view the study (no setup)

The dashboard's data is baked in, so it needs no server or internet.

- **Easiest — open a file:** double-click **`dashboard-app/dist-single/index.html`**. It is one
  self-contained file (all code, styles, fonts, and data inlined). Every chart, the sweeps, and the
  track maps work straight from the file. *(Two minor things need the served version below: the header
  logo and the "About → downloads" buttons. Everything else works from the file.)*
- **As a local website (full features — needs Node):** the multi-file `dist/` is **not shipped** in the
  package (it's ~100 font/asset files the single-file above already inlines — kept lean and rebuildable).
  Build it, then serve:
  ```bash
  cd dashboard-app && npm install && npm run build && npm run preview
  # then open http://localhost:5280/
  ```
  (Opening a built `dist/index.html` directly via `file://` will *not* work — it loads JS modules and must
  be served over HTTP. That is why the single-file build above exists.)

---

## 2. Run a sweep (make new results)

A "sweep" runs the simulator across a grid of aero setups and writes one Excel workbook.

**One-time Python setup:**
```bash
python3 -m venv .venv
. .venv/bin/activate            # Windows: .venv\Scripts\activate
pip install -r requirements.txt
```
(Python 3.12 is what the project was built and tested on.)

**The production sweep** (the buildable-envelope grid the dashboard data is built from):
```bash
python scripts/run_clamped_sweep.py
```
Writes `Lap Sim March 2026/Test Results/python/T27_AeroSweep_manufacturable.xlsx`
(+ a `.meta.json` sidecar) and prints the best buildable setup.

**Other ways to sweep:**
```bash
# the built-in CLI sweep, to a path you choose:
python -m pylapsim sweep --preset Medium --corrected --out "my_sweep.xlsx"

# a denser grid for fine studies:
python scripts/run_hires_sweep.py
```
Key flags: `--preset Low|Medium|High` (solver fidelity), `--corrected` (the fixed physics — use this
for real analysis; the default `--legacy` reproduces the original MATLAB *with* its load-transfer bug,
which exists only so the port can be validated against the old results).

**A single setup + its lap trace** (the per-event time-series the dashboard's lap-playback replays):
```bash
python -m pylapsim run --cl 0.040 --cd 0.020 --cop 0.450 --corrected --out-dir trace_out
```
Writes `T27_validation_trace_<tag>.csv` (+ summary + meta) into `trace_out/`.

**Sanity checks:**
```bash
python -m pylapsim validate     # compare one case to the MATLAB reference, prints PASS/FAIL
pytest                          # run the test suite
```

> If `import pylapsim` fails, run the command with the repo root on the path:
> `PYTHONPATH=. python scripts/run_clamped_sweep.py`.

---

## 3. Put new results into the page

The dashboard reads its data from constants inlined near the top of
`handover/dashboard/t27-aero-dashboard.jsx`:

```
const META, SWEEP0, TRACE0, PAIRS   (lines 15–18)  ← sweep scores + lap trace
const TRACK0                        (line 19)      ← track maps (cone edges + racing line)
const AIRFOILS0                     (line 20)      ← airfoil reference data
```

**Re-inline a sweep + trace:**
```bash
python scripts/build_dashboard_data.py
```
It reads the production workbook and a trace CSV (paths are constants near the top of that script —
edit `XLSX` and `TRACE` there to point at different files) and rewrites the `META`/`SWEEP0`/`TRACE0`/`PAIRS`
lines in place. It prints how many cells it spliced and asserts if anything failed.

**Rebuild the track maps** (after changing the track inputs):
```bash
python scripts/build_track_geometry.py
```
It rebuilds `TRACK0` from the sim's own geometry and splices it into the dashboard source
(and writes `scripts/track0.json` as a record). The airfoil data (`AIRFOILS0`) is produced by
`scripts/fetch_airfoils.py` and pasted into line 20.

After regenerating any inlined data, **rebuild the UI** (next section) for it to show.

---

## 4. View / develop the UI from source

```bash
cd dashboard-app
npm install            # first time only

# pick one:
npm run dev            # live dev server with hot reload  → http://localhost:5273/
npm run build          # produce a fresh static dist/ from the current jsx + data
npm run preview        # serve the built dist/            → http://localhost:5280/
npm run build:single   # produce the single self-contained file → dist-single/index.html
```

- After a §3 data change: `npm run build` (and `npm run build:single` if you want a fresh standalone
  file), or just keep `npm run dev` running — it picks up edits automatically.
- The Vite config aliases `react`/`react-dom`/`xlsx`/`papaparse` to this app's `node_modules` and lets
  it serve the dashboard source from `../handover/dashboard` (outside the app root) — that is why the
  dashboard lives elsewhere but builds here.

---

## 5. The data pipeline at a glance

```
 INPUTS (committed)                         pylapsim                        dashboard
 ─────────────────                          ────────                        ─────────
 Endurance_Coordinates_1.xlsx ┐
 Autocross_Coordinates_2.xlsx ┤ run_clamped_sweep.py ─► T27_AeroSweep_manufacturable.xlsx ┐
 *_racing_line.mat            ┤ pylapsim run --out-dir ─► T27_validation_trace_*.csv       ┤
 Tire/vehicle data (pylapsim) ┘                                                            │
        │                                                                                  │
        │  build_track_geometry.py ─► TRACK0          build_dashboard_data.py ─► META/SWEEP0/TRACE0/PAIRS
        └───────────────────────────────┬───────────────────────────────────────┘
                                         ▼
                  handover/dashboard/t27-aero-dashboard.jsx  (data inlined)
                                         │  Vite
                          npm run build ─► dashboard-app/dist/  ──► browser
                          npm run build:single ─► dist-single/index.html (double-click)
```
