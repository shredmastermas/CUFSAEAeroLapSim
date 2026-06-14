"""Manufacturable-envelope sweep — clamped to Mason's real build bounds.

Replaces the unconstrained sweep after the 2026-06-13 review:
  - parameterized by (CL, L/D, CoP); CD is DERIVED = CL / L/D, so every cell is
    inside the buildable lift-to-drag band (no more CD 0.01 / L/D 9 fantasy, no
    high-CL tire-extrapolation NaNs).
  - CL clamped to <= 0.055 (CL 0.08+ ⇒ ~1500 lbf, unmountable).
  - L/D swept 2.0–3.0 (buildable band 2.2–3.0; 2.0–2.2 kept only so the
    points-vs-L/D curve shows the shelf); 3.0 is the ceiling.
  - CoP rearward-leaning (forward ⇒ oversteer per Mason).
  - NO fabricated baseline prepended (the old BASELINE 0.080/0.020/0.450 "T26"
    was a seed number, not a real car). A real reference cell — CL 0.045 @ L/D 2.2,
    Mason's best-achieved ratio — is passed to finalize for the delta columns.

    PYTHONPATH=. .venv/bin/python scripts/run_clamped_sweep.py
"""
from __future__ import annotations

import os
import sys
import time

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from pylapsim.config import HIGH, AeroTarget, SimConfig  # noqa: E402
from pylapsim.io_contract import write_meta_json, write_results_workbook  # noqa: E402
from pylapsim.sweep import finalize_results, run_sweep  # noqa: E402

CL = np.round(np.arange(0.035, 0.05501, 0.0025), 6)   # 9  (0.035..0.055)
LD = np.round(np.arange(2.00, 3.0001, 0.05), 6)        # 21 (2.00..3.00)
COP = np.round(np.arange(0.40, 0.5501, 0.025), 6)      # 7  (0.40..0.55, rearward)

# Mason's best-achieved build (CL ~0.045, L/D ~2.19) — a REAL anchor for deltas.
REF = AeroTarget(0.045, round(0.045 / 2.2, 6), 0.45)

DEST = "Lap Sim March 2026/Test Results/python/T27_AeroSweep_manufacturable.xlsx"


def clamped_combos():
    seen, out = set(), []
    for cop in COP:
        for ld in LD:
            for cl in CL:
                cd = round(float(cl) / float(ld), 6)
                key = (round(float(cl), 6), cd, round(float(cop), 6))
                if key not in seen:
                    seen.add(key)
                    out.append(AeroTarget(float(cl), cd, float(cop)))
    return out


def main() -> int:
    combos = clamped_combos()
    print(f"clamped grid CL{len(CL)} x LD{len(LD)} x CoP{len(COP)} = {len(combos)} cells "
          f"(CD derived = CL/LD; L/D 2.0-3.0; no fake baseline)", flush=True)
    cfg = SimConfig(legacy_compat=False)
    t0 = time.time()
    df = run_sweep(base_cfg=cfg, combos=combos, fast_resolution=HIGH,
                   rerun_top_accurate=0,
                   progress=lambda m: print("  " + m, flush=True))
    out = finalize_results(df, baseline=REF)
    os.makedirs(os.path.dirname(DEST), exist_ok=True)
    write_results_workbook(out, DEST)
    write_meta_json(os.path.splitext(DEST)[0] + ".meta.json", cfg)
    dt = time.time() - t0
    solved = out.dropna(subset=["Total_Points"])
    best = solved.iloc[0]
    print(f"done in {dt:.0f}s -> {DEST}", flush=True)
    print(f"rows={len(out)} solved={len(solved)} | best CL {best.CL_target} "
          f"CD {best.CD_target} (L/D {best.CL_target / best.CD_target:.2f}) "
          f"CoP {best.CoP_target} Total {best.Total_Points:.2f}", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
