"""Higher-resolution CORRECTED aero sweep.

Denser CL/CD grid + CoP range EXTENDED to 0.675 so the interior CoP optimum
(~0.625; see docs/FUTURE.md) is sampled instead of pinned at the old 0.525 grid
edge. Corrected physics (legacy_compat=False) so the embedded scores match the
dashboard's corrected longitudinal-transfer load rendering (no /24 bug).

Run from the repo root:
    PYTHONPATH=. .venv/bin/python scripts/run_hires_sweep.py
"""
from __future__ import annotations

import os
import sys
import time

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from pylapsim.config import MEDIUM, SimConfig  # noqa: E402
from pylapsim.io_contract import write_meta_json, write_results_workbook  # noqa: E402
from pylapsim.sweep import finalize_results, run_sweep, sweep_combos  # noqa: E402

# committed grid was CL 5 @0.005, CD 7 @0.0025, CoP 5 @0.025 (0.425..0.525).
# Dial-up: extend CL THROUGH and PAST T26 (0.080) so T26 stops being the only
# point at its downforce level — now it can actually be compared/beaten. Extend
# CD below T26's 0.020 to find lower-drag setups at the same downforce.
CL = np.round(np.arange(0.035, 0.0901, 0.0025), 6)    # 23 pts (0.035..0.090, through T26 0.080)
CD = np.round(np.arange(0.010, 0.0301, 0.00125), 6)   # 17 pts (0.010..0.030, below T26 0.020)
COP = np.round(np.arange(0.425, 0.6751, 0.025), 6)    # 11 pts (0.425..0.675)

DEST = "Lap Sim March 2026/Test Results/python/T27_AeroSweep_hires_corrected.xlsx"


def main() -> int:
    combos = sweep_combos(CL, CD, COP)
    print(f"grid {len(CL)}x{len(CD)}x{len(COP)} = {len(CL) * len(CD) * len(COP)} "
          f"+ baseline -> {len(combos)} cases (CORRECTED physics)", flush=True)
    cfg = SimConfig(legacy_compat=False)
    t0 = time.time()
    df = run_sweep(base_cfg=cfg, combos=combos, fast_resolution=MEDIUM,
                   rerun_top_accurate=60,
                   progress=lambda m: print("  " + m, flush=True))
    out = finalize_results(df)
    os.makedirs(os.path.dirname(DEST), exist_ok=True)
    write_results_workbook(out, DEST)
    write_meta_json(os.path.splitext(DEST)[0] + ".meta.json", cfg)
    dt = time.time() - t0
    best = out.iloc[0]
    print(f"done in {dt:.0f}s -> {DEST}", flush=True)
    print(f"rows={len(out)}  best: CL {best.CL_target} CD {best.CD_target} "
          f"CoP {best.CoP_target} Total {best.Total_Points:.2f} ({best.RunMode})", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
