"""Answer 'can we beat T26, and why couldn't we before?' from a sweep workbook.

    PYTHONPATH=. .venv/bin/python scripts/analyze_t26.py [workbook.xlsx]
"""
from __future__ import annotations

import sys

import numpy as np
import pandas as pd

XLSX = sys.argv[1] if len(sys.argv) > 1 else (
    "Lap Sim March 2026/Test Results/python/T27_AeroSweep_hires_corrected.xlsx")
EVENTS = [("Total_Points", "Total"), ("Endurance_Score", "Endurance"),
          ("Autocross_Score", "Autocross"), ("Skidpad_Score", "Skidpad"),
          ("Accel_Score", "Accel")]


def main():
    df = pd.read_excel(XLSX, sheet_name="All Results Ranked")
    fast = df[df.RunMode == "Fast"].copy()
    fast["LD"] = fast.CL_target / fast.CD_target
    print(f"workbook: {XLSX}")
    print(f"fast rows: {len(fast)} | CL {fast.CL_target.min()}-{fast.CL_target.max()} "
          f"CD {fast.CD_target.min()}-{fast.CD_target.max()} CoP {fast.CoP_target.min()}-{fast.CoP_target.max()}")

    t26m = (np.isclose(fast.CL_target, 0.08) & np.isclose(fast.CD_target, 0.02)
            & np.isclose(fast.CoP_target, 0.45))
    if not t26m.any():
        print("!! T26 (0.08/0.02/0.45) not in fast grid"); return
    t26 = fast[t26m].iloc[0]
    print(f"\nT26 (CL0.080/CD0.020/CoP0.450): Total {t26.Total_Points:.1f}  L/D {t26.LD:.1f}")

    print("\n=== T26 rank in the full field (lower = better) ===")
    for col, name in EVENTS:
        rank = int((fast[col] > t26[col]).sum()) + 1
        beats = int((fast[col] > t26[col]).sum())
        print(f"  {name:10s}: T26={t26[col]:7.2f}  rank #{rank} of {len(fast)}  ({beats} setups beat it)")

    print("\n=== Can we beat T26 AT ITS OWN downforce (CL 0.08)? ===")
    same_cl = fast[np.isclose(fast.CL_target, 0.08)].sort_values("Total_Points", ascending=False)
    b = same_cl.iloc[0]
    print(f"  best at CL0.08: CD{b.CD_target:.4f}/CoP{b.CoP_target:.3f} -> {b.Total_Points:.1f} "
          f"(L/D {b.LD:.1f}), beats T26 by {b.Total_Points - t26.Total_Points:+.1f} pts")
    print(f"  => same downforce, just less drag (CD {t26.CD_target:.3f}->{b.CD_target:.3f}) "
          f"+ better balance (CoP {t26.CoP_target:.3f}->{b.CoP_target:.3f})")

    print("\n=== Realistic-L/D frontier (what's actually buildable) ===")
    for ld_cap in (2.5, 3.0, 4.0, 6.0):
        sub = fast[fast.LD <= ld_cap]
        if len(sub):
            r = sub.sort_values("Total_Points", ascending=False).iloc[0]
            print(f"  L/D<= {ld_cap}: best CL{r.CL_target:.4f}/CD{r.CD_target:.4f}/CoP{r.CoP_target:.3f} "
                  f"-> {r.Total_Points:.1f} (L/D {r.LD:.1f}), vs T26 {r.Total_Points - t26.Total_Points:+.1f}")

    print("\n=== Absolute best (any L/D — note plausibility) ===")
    bo = fast.sort_values("Total_Points", ascending=False).iloc[0]
    print(f"  CL{bo.CL_target:.4f}/CD{bo.CD_target:.4f}/CoP{bo.CoP_target:.3f} -> {bo.Total_Points:.1f} "
          f"(L/D {bo.LD:.1f}), vs T26 {bo.Total_Points - t26.Total_Points:+.1f}")

    print("\n=== Marginal value of downforce (CoP 0.575, CD 0.020, vs CL) ===")
    sl = fast[np.isclose(fast.CoP_target, 0.575) & np.isclose(fast.CD_target, 0.020)].sort_values("CL_target")
    if len(sl) > 1:
        for _, r in sl.iterrows():
            print(f"  CL {r.CL_target:.4f}: {r.Total_Points:6.1f}  (L/D {r.LD:.1f})")


if __name__ == "__main__":
    main()
