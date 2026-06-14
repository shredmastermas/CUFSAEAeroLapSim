"""Runtime vs quality vs size — a convergence study for the corrected sweep.

Answers "how much resolution is enough?" by sweeping two knobs and watching
whether the ANSWER (best target + rankings) actually moves:

  Part 1 — GRID DENSITY ladder at fixed High fidelity (nested grids, so coarse
           points are a subset of fine ones → exact shared-point comparison).
  Part 2 — SOLVER FIDELITY ladder (Low / Medium / High) at a fixed grid.

For each run we record wall-clock runtime, grid size (cells), the best target it
finds, and — as the "quality" axis — how far its totals/rankings sit from the
finest run, measured on a fixed probe set of points present in every grid.

Streams results to docs/CONVERGENCE_STUDY.{csv,md} as each run completes, so a
kill leaves usable partial output.

    PYTHONPATH=. .venv/bin/python scripts/convergence_study.py
"""
from __future__ import annotations

import os
import sys
import time

import numpy as np
import pandas as pd

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from pylapsim.config import HIGH, LOW, MEDIUM, SimConfig  # noqa: E402
from pylapsim.sweep import run_sweep, sweep_combos  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CSV = os.path.join(ROOT, "docs/CONVERGENCE_STUDY.csv")
MD = os.path.join(ROOT, "docs/CONVERGENCE_STUDY.md")

# Fixed ranges chosen inside the region that reliably solves (CL capped at 0.075
# — above that the rear axle extrapolates past the tire data and cells NaN out,
# which would pollute the convergence metrics). Endpoints fixed so the density
# levels are NESTED (each coarse point is also a fine point).
CL0, CL1 = 0.035, 0.075
CD0, CD1 = 0.010, 0.030
CP0, CP1 = 0.450, 0.650


def grid(ncl, ncd, ncp):
    return (np.round(np.linspace(CL0, CL1, ncl), 6),
            np.round(np.linspace(CD0, CD1, ncd), 6),
            np.round(np.linspace(CP0, CP1, ncp), 6))


# nested density ladder: each axis count is (prev-1)*2+1 so points stay shared
DENSITY = {
    "L0 coarse": grid(5, 5, 5),     # 125
    "L1 medium": grid(9, 9, 9),     # 729
    "L2 fine":   grid(17, 17, 17),  # 4913  (~ current production density)
}
# the coarsest grid's points are present in every level -> exact probe set
PROBE = [(float(a), float(b), float(c))
         for a in DENSITY["L0 coarse"][0]
         for b in DENSITY["L0 coarse"][1]
         for c in DENSITY["L0 coarse"][2]]

CFG = SimConfig(legacy_compat=False)
RESULTS = []   # one dict per run
PROBES = {}    # run label -> {(cl,cd,cop): total}


def key(cl, cd, cop):
    return (round(float(cl), 6), round(float(cd), 6), round(float(cop), 6))


def run(label, cls, cds, cps, res):
    combos = sweep_combos(cls, cds, cps)
    n = len(cls) * len(cds) * len(cps)
    print(f"\n=== {label} | {len(cls)}x{len(cds)}x{len(cps)} = {n} cells | {res.name} ===", flush=True)
    t0 = time.time()
    df = run_sweep(base_cfg=CFG, combos=combos, fast_resolution=res,
                   rerun_top_accurate=0,
                   progress=lambda m: print("  " + m, flush=True))
    dt = time.time() - t0
    f = df[df.RunMode == "Fast"].copy()
    solved = f.dropna(subset=["Total_Points"])
    nan = len(f) - len(solved)
    best = solved.loc[solved.Total_Points.idxmax()]
    pmap = {key(r.CL_target, r.CD_target, r.CoP_target): r.Total_Points
            for _, r in solved.iterrows()}
    PROBES[label] = {k: pmap.get(k, np.nan) for k in (key(*p) for p in PROBE)}
    rec = {
        "label": label, "fidelity": res.name, "cells": n, "solved": len(solved),
        "nan": nan, "runtime_s": round(dt, 1), "s_per_cell": round(dt / n, 4),
        "best_cl": round(float(best.CL_target), 5), "best_cd": round(float(best.CD_target), 5),
        "best_cop": round(float(best.CoP_target), 4), "best_total": round(float(best.Total_Points), 2),
        "best_ld": round(float(best.CL_target / best.CD_target), 2),
    }
    RESULTS.append(rec)
    print(f"  -> {dt:.0f}s ({rec['s_per_cell']}s/cell) best "
          f"CL{rec['best_cl']}/CD{rec['best_cd']}/CoP{rec['best_cop']} "
          f"= {rec['best_total']} (L/D {rec['best_ld']}), {nan} NaN", flush=True)
    flush_csv()
    return rec


def flush_csv():
    pd.DataFrame(RESULTS).to_csv(CSV, index=False)


def spearman(a, b):
    a, b = np.asarray(a, float), np.asarray(b, float)
    m = ~(np.isnan(a) | np.isnan(b))
    if m.sum() < 3:
        return float("nan")
    ra = pd.Series(a[m]).rank().to_numpy()
    rb = pd.Series(b[m]).rank().to_numpy()
    return float(np.corrcoef(ra, rb)[0, 1])


def convergence(ref_label):
    """vs the finest run: mean|Δ| and Spearman on the shared probe set."""
    ref = PROBES[ref_label]
    keys = list(ref.keys())
    rv = np.array([ref[k] for k in keys], float)
    rows = []
    for r in RESULTS:
        pv = np.array([PROBES[r["label"]].get(k, np.nan) for k in keys], float)
        d = np.abs(pv - rv)
        rows.append({
            "label": r["label"], "fidelity": r["fidelity"], "cells": r["cells"],
            "runtime_s": r["runtime_s"], "best_total": r["best_total"],
            "best_cop": r["best_cop"], "best_ld": r["best_ld"],
            "vs_finest_meanAbsD": round(float(np.nanmean(d)), 3),
            "vs_finest_maxAbsD": round(float(np.nanmax(d)), 3),
            "vs_finest_spearman": round(spearman(pv, rv), 5),
        })
    return rows


def write_md():
    # Part 1: density levels (all High) vs the finest density run.
    dens = [r for r in convergence("L2 fine")
            if r["label"] in DENSITY]
    # Part 2: fidelity at the fixed L1 grid vs that grid's High run.
    fide = [r for r in convergence("L1 medium")
            if r["label"] in ("L1 medium", "F@Medium", "F@Low")]
    # order the fidelity table High -> Medium -> Low
    order = {"L1 medium": 0, "F@Medium": 1, "F@Low": 2}
    fide.sort(key=lambda r: order[r["label"]])
    rename = {"L1 medium": "High", "F@Medium": "Medium", "F@Low": "Low"}
    for r in fide:
        r["fid_label"] = rename[r["label"]]
    lines = ["# Convergence study — runtime vs quality vs size", "",
             f"Corrected physics. Ranges CL [{CL0}, {CL1}], CD [{CD0}, {CD1}], "
             f"CoP [{CP0}, {CP1}]. Quality = agreement with the finest run on a "
             f"{len(PROBE)}-point shared probe set (mean/max |Δtotal|, Spearman of "
             "rankings). Lower |Δ| and Spearman→1 mean 'finer would not change the answer.'",
             "", "## Part 1 — grid density (fidelity = High)", "",
             "| level | cells | runtime s | s/cell | best total | best CoP | best L/D | mean|Δ| vs finest | max|Δ| | Spearman |",
             "|---|---|---|---|---|---|---|---|---|---|"]
    for r in dens:
        lines.append(f"| {r['label']} | {r['cells']} | {r['runtime_s']} | "
                     f"{round(r['runtime_s']/r['cells'],4)} | {r['best_total']} | "
                     f"{r['best_cop']} | {r['best_ld']} | {r['vs_finest_meanAbsD']} | "
                     f"{r['vs_finest_maxAbsD']} | {r['vs_finest_spearman']} |")
    lines += ["", f"## Part 2 — solver fidelity (grid fixed at L1 = {DENSITY['L1 medium'][0].size}"
              f"x{DENSITY['L1 medium'][1].size}x{DENSITY['L1 medium'][2].size})", "",
              "| fidelity | cells | runtime s | s/cell | best total | mean|Δ| vs High | max|Δ| | Spearman |",
              "|---|---|---|---|---|---|---|---|"]
    for r in fide:
        lines.append(f"| {r['fid_label']} | {r['cells']} | {r['runtime_s']} | "
                     f"{round(r['runtime_s']/r['cells'],4)} | {r['best_total']} | "
                     f"{r['vs_finest_meanAbsD']} | {r['vs_finest_maxAbsD']} | {r['vs_finest_spearman']} |")
    with open(MD, "w") as f:
        f.write("\n".join(lines) + "\n")
    print("\n" + "\n".join(lines), flush=True)


def main():
    os.makedirs(os.path.dirname(CSV), exist_ok=True)
    grand0 = time.time()
    # Part 1 — density ladder at High
    for label, (cls, cds, cps) in DENSITY.items():
        run(label, cls, cds, cps, HIGH)
    # Part 2 — fidelity ladder at a fixed mid grid (L1); the L1-High run above
    # is reused as the High reference in write_md (compared on the probe set).
    cls, cds, cps = DENSITY["L1 medium"]
    for res in (MEDIUM, LOW):
        run(f"F@{res.name}", cls, cds, cps, res)
    write_md()
    print(f"\nTOTAL STUDY {time.time()-grand0:.0f}s -> {MD}", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
