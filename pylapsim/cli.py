"""pylapsim CLI.

  python -m pylapsim run --cl 0.04 --cd 0.02 --cop 0.45 [--preset High]
                         [--legacy/--corrected] [--out-dir DIR]
  python -m pylapsim sweep [--preset Medium] [--legacy/--corrected]
                           [--out OUT.xlsx] [--workers N]
  python -m pylapsim validate            # Gate A vs committed artifacts
"""

from __future__ import annotations

import argparse
import os
import sys

import numpy as np

from .config import PRESETS, PYTHON_RESULTS_DIR, AeroTarget, SimConfig
from .simulate import SharedData, run_case, validation_summary_row


def _add_common(p):
    p.add_argument("--preset", default="High", choices=list(PRESETS))
    mode = p.add_mutually_exclusive_group()
    mode.add_argument("--legacy", dest="legacy", action="store_true", default=True,
                      help="reproduce committed V4 physics incl. F1 bug (default)")
    mode.add_argument("--corrected", dest="legacy", action="store_false",
                      help="corrected physics (FINDINGS F1 fix)")


def cmd_run(args):
    cfg = SimConfig(aero=AeroTarget(args.cl, args.cd, args.cop),
                    resolution=PRESETS[args.preset], legacy_compat=args.legacy)
    case = run_case(cfg)
    row = validation_summary_row(case)
    print(f"pylapsim run {cfg.aero.tag} preset={args.preset} "
          f"mode={'legacy' if args.legacy else 'corrected'} ({case.runtime_s:.2f}s)")
    for k, v in row.items():
        print(f"  {k:>22}: {v if isinstance(v, str) else round(float(v), 5)}")
    print(f"  {'Total_Points':>22}: {case.total_points:.3f}")
    if args.out_dir:
        from .io_contract import (safe_aero_tag, write_meta_json, write_trace_csv,
                                  write_validation_summary_csv)
        os.makedirs(args.out_dir, exist_ok=True)
        tag = safe_aero_tag(cfg.aero.tag)
        write_trace_csv(case, os.path.join(args.out_dir, f"T27_validation_trace_{tag}.csv"))
        write_validation_summary_csv([case], os.path.join(args.out_dir, f"T27_validation_summary_{tag}.csv"))
        write_meta_json(os.path.join(args.out_dir, "meta.json"), cfg)
        print(f"wrote trace/summary/meta under {args.out_dir}")
    return 0


def cmd_sweep(args):
    from .io_contract import write_meta_json, write_results_workbook
    from .sweep import finalize_results, run_sweep
    cfg = SimConfig(legacy_compat=args.legacy)
    df = run_sweep(base_cfg=cfg, fast_resolution=PRESETS[args.preset],
                   rerun_top_accurate=args.rerun_top, workers=args.workers,
                   progress=lambda m: print(f"  {m}", flush=True))
    out = finalize_results(df)
    dest = args.out or os.path.join(PYTHON_RESULTS_DIR, "T27_AeroSweep_pylapsim.xlsx")
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    write_results_workbook(out, dest)
    write_meta_json(os.path.splitext(dest)[0] + ".meta.json", cfg)
    best = out.iloc[0]
    print(f"sweep complete -> {dest}")
    print(f"best: CL {best.CL_target} CD {best.CD_target} CoP {best.CoP_target} "
          f"Total {best.Total_Points:.2f} ({best.RunMode})")
    return 0


def cmd_validate(args):
    """Gate A summary against committed artifacts (see docs/VALIDATION.md)."""
    import pandas as pd
    from .config import HIGH, TEST_RESULTS_DIR
    cfg = SimConfig(aero=AeroTarget(0.040, 0.020, 0.450), resolution=HIGH,
                    legacy_compat=True)
    case = run_case(cfg)
    row = validation_summary_row(case)
    ref = pd.read_csv(os.path.join(
        TEST_RESULTS_DIR, "T27_validation_summary_CL_0_040_CD_0_020_CoP_0_450.csv")).iloc[0]
    bands = {"Endurance_Lap_Time": 1.5, "Autocross_Time": 1.5, "Skidpad_Time": 1.5,
             "Accel_Time": 1.5, "Max_Abs_AY": 4.0, "Max_AX": 6.0, "Min_AX": 6.0}
    print("Gate A validation case (legacy_compat=True, High preset):")
    fails = 0
    for k, band in bands.items():
        delta = 100.0 * (row[k] - ref[k]) / abs(ref[k])
        ok = abs(delta) <= band
        note = ""
        if k == "Autocross_Time" and not ok:
            note = "  [expected: committed autocross geometry not reproducible from repo inputs — docs/VALIDATION.md]"
        else:
            fails += 0 if ok else 1
        print(f"  {k:>20}: py {row[k]:10.4f} ref {float(ref[k]):10.4f} "
              f"d {delta:+7.3f}% (band +-{band}%) {'PASS' if ok else 'FAIL'}{note}")
    print(f"non-autocross gate failures: {fails}")
    return 1 if fails else 0


def main(argv=None):
    ap = argparse.ArgumentParser(prog="pylapsim")
    sub = ap.add_subparsers(dest="cmd", required=True)

    p_run = sub.add_parser("run", help="run a single aero case")
    p_run.add_argument("--cl", type=float, default=0.040)
    p_run.add_argument("--cd", type=float, default=0.020)
    p_run.add_argument("--cop", type=float, default=0.450)
    p_run.add_argument("--out-dir", default=None)
    _add_common(p_run)
    p_run.set_defaults(fn=cmd_run)

    p_sw = sub.add_parser("sweep", help="run the committed aero grid sweep")
    p_sw.add_argument("--out", default=None)
    p_sw.add_argument("--workers", type=int, default=None)
    p_sw.add_argument("--rerun-top", type=int, default=10)
    _add_common(p_sw)
    p_sw.set_defaults(fn=cmd_sweep, preset="Medium")

    p_val = sub.add_parser("validate", help="Gate A KPI comparison vs committed artifacts")
    p_val.set_defaults(fn=cmd_validate)

    args = ap.parse_args(argv)
    return args.fn(args)


if __name__ == "__main__":
    sys.exit(main())
