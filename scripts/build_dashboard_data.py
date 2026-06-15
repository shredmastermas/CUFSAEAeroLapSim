"""Regenerate the dashboard's embedded data blobs and splice them into the jsx.

Rebuilds META / SWEEP0 / TRACE0 / PAIRS from a sweep workbook + a lap-replay
trace CSV, mirroring the dashboard's own onSweepFile / PapaParse readers
(handover/dashboard/t27-aero-dashboard.jsx) so the embedded default matches what
a runtime upload of the same files would produce.

    PYTHONPATH=. .venv/bin/python scripts/build_dashboard_data.py
"""
from __future__ import annotations

import json
import os
import subprocess

import numpy as np
import pandas as pd

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
XLSX = os.path.join(ROOT, "Lap Sim March 2026/Test Results/python/"
                          "T27_AeroSweep_manufacturable.xlsx")
TRACE = os.path.join(ROOT, "Lap Sim March 2026/Test Results/"
                           "T27_validation_trace_CL_0_040_CD_0_020_CoP_0_450.csv")
JSX = os.path.join(ROOT, "handover/dashboard/t27-aero-dashboard.jsx")

WORKBOOK_NAME = "T27_AeroSweep_manufacturable.xlsx"
TRACE_NAME = "T27_validation_trace_CL_0_040_CD_0_020_CoP_0_450.csv"
TRACE_RUN = {"cl": 0.04, "cd": 0.02, "cop": 0.45}
DF_FLOOR = 90.0   # minimum-downforce sanity floor @35 mph (lbf); no upper cap
KEEP = 1250       # downsampled trace points kept per event


def rd(x, n):
    return round(float(x), n)


def isT26(s):  # the current car as a grid cell — excluded from "best" picks
    return abs(s["cl"] - 0.08) < 1e-9 and abs(s["cd"] - 0.02) < 1e-9 and abs(s["cop"] - 0.45) < 1e-9


def build_sweep(df):
    rows = []
    for _, x in df.iterrows():
        if pd.isna(x.Total_Points):
            continue  # unsolved cell (high-DF tire extrapolation) — mirror the
            # upload parser, which drops rows with total == null, so the embedded
            # default matches a runtime upload and the heat-map renders it empty.
        rows.append({
            "cl": rd(x.CL_target, 4), "cd": rd(x.CD_target, 4), "cop": rd(x.CoP_target, 3),
            "total": rd(x.Total_Points, 2), "accel": rd(x.Accel_Score, 2),
            "skid": rd(x.Skidpad_Score, 2), "auto": rd(x.Autocross_Score, 2),
            "endur": rd(x.Endurance_Score, 2),
            "t_accel": rd(x.Accel_Time, 3), "t_skid": rd(x.Skidpad_Time, 3),
            "t_auto": rd(x.Autocross_Time, 3), "t_endur": rd(x.Endurance_Lap_Time, 3),
            "ld": rd(x.CL_over_CD, 3),
            "df": rd(x.DF_Total_FeasRef_lbf, 1),  # total downforce @35 mph (lbf)
            "mode": "A" if x.RunMode == "AccurateRerun" else "F",
            "feas": bool(x.DF_Total_FeasRef_lbf >= DF_FLOOR),
        })
    return rows


def build_pairs(df):
    fast = {(rd(x.CL_target, 4), rd(x.CD_target, 4), rd(x.CoP_target, 3)): x.Total_Points
            for _, x in df[df.RunMode == "Fast"].iterrows()}
    pairs = []
    for _, x in df[df.RunMode == "AccurateRerun"].iterrows():
        k = (rd(x.CL_target, 4), rd(x.CD_target, 4), rd(x.CoP_target, 3))
        if k in fast:
            pairs.append({"cl": k[0], "cd": k[1], "cop": k[2],
                          "f": rd(fast[k], 2), "a": rd(x.Total_Points, 2)})
    return pairs


def build_trace(path):
    d = pd.read_csv(path)
    out = {}
    for ev_csv, ev_key in (("Autocross", "autocross"), ("Endurance", "endurance")):
        g = d[d.Event == ev_csv].reset_index(drop=True)
        n = len(g)
        idx = np.unique(np.linspace(0, n - 1, min(KEEP, n)).round().astype(int))
        s = g.iloc[idx]
        ax = s.Longitudinal_G.to_numpy()
        ay = s.Lateral_G.to_numpy()
        out[ev_key] = {
            "src": int(n), "kept": int(len(s)),
            "t": [rd(v, 2) for v in s.Time_s], "d": [rd(v, 1) for v in s.Distance_ft],
            "v": [rd(v, 2) for v in s.Speed_ft_s],
            "ax": [rd(v, 3) for v in ax], "ay": [rd(v, 3) for v in ay],
            "g": [rd(float(np.hypot(a, b)), 3) for a, b in zip(ax, ay)],
        }
    return out


def git_sha():
    try:
        return subprocess.run(["git", "rev-parse", "--short", "HEAD"], cwd=ROOT,
                              capture_output=True, text=True, check=True).stdout.strip()
    except Exception:
        return "uncommitted"


def main():
    df = pd.read_excel(XLSX, sheet_name="All Results Ranked")
    consts = {
        "META": {"workbook": WORKBOOK_NAME, "sha": git_sha(), "trace": TRACE_NAME,
                 "traceRun": TRACE_RUN, "feas": {"refMph": 35.0, "dfMin": DF_FLOOR},
                 # manufacturable envelope (Mason 2026-06-13, revised bounds): realistic L/D band +
                 # a REAL reference cell (best-achieved ~CL0.045/L2.2) — no fake T26.
                 "ld": {"band": [2.0, 2.75], "excludedAbove": 2.75},
                 "refMph": 35.0, "topMph": 60.0, "maxLoadMph": 90.0,
                 "ref": {"cl": 0.045, "cd": round(0.045 / 2.2, 6), "cop": 0.45}},
        "SWEEP0": build_sweep(df),
        "TRACE0": build_trace(TRACE),
        "PAIRS": build_pairs(df),
    }
    with open(JSX) as f:
        lines = f.readlines()
    spliced = set()
    for i, ln in enumerate(lines):
        for name, val in consts.items():
            if ln.startswith(f"const {name} = "):
                lines[i] = f"const {name} = {json.dumps(val, separators=(',', ':'))};\n"
                spliced.add(name)
    with open(JSX, "w") as f:
        f.writelines(lines)
    missing = set(consts) - spliced
    assert not missing, f"could not splice: {missing}"
    sweep = consts["SWEEP0"]
    dropped = len(df[df.RunMode != "AccurateRerun"]) - sum(s["mode"] == "F" for s in sweep) \
        if "RunMode" in df else 0
    best = max((s for s in sweep if not isT26(s)), key=lambda s: s["total"])
    best_buildable = max((s for s in sweep if not isT26(s) and s["ld"] <= 2.75),
                         key=lambda s: s["total"], default=None)
    print(f"spliced META / SWEEP0({len(sweep)}) / TRACE0 / PAIRS({len(consts['PAIRS'])})")
    print(f"dropped unsolved (NaN-total) fast cells: {dropped}")
    print(f"feasible(floor {DF_FLOOR}): {sum(s['feas'] for s in sweep)}/{len(sweep)}")
    print(f"best simulated row inside active envelope: {best}")
    if best_buildable:
        print(f"best buildable (L/D<=2.75): {best_buildable}")


if __name__ == "__main__":
    main()
