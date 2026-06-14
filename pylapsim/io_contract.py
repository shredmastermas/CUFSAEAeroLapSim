"""Dashboard data contract I/O (handover/DATA_CONTRACT.md).

Emitters write artifacts the existing dashboard loads unmodified; validators
encode the same expectations its upload parsers apply (§F) and are exercised
by tests/test_contract.py against every emitted file.
"""

from __future__ import annotations

import json
import re
import subprocess
from datetime import datetime, timezone

import numpy as np
import pandas as pd

from . import __version__
from .config import SimConfig
from .simulate import CaseResult, validation_summary_row

SHEET_NAME = "All Results Ranked"

# §A committed 54-column schema, exact names and order
COMMITTED_COLUMNS = [
    "AeroTag", "CL_target", "CD_target", "CoP_target",
    "Accel_Score", "Skidpad_Score", "Autocross_Score", "Endurance_Score", "Total_Points",
    "Skidpad_Time", "Accel_Time", "Autocross_Time", "Endurance_Lap_Time",
    "CL_over_CD", "RunNumber", "RunMode",
    "PointGain_vs_Baseline", "CD_Increase_vs_Baseline", "CL_Increase_vs_Baseline", "PointGain_per_CD",
    "BalanceError", "FrontAeroPercent", "RearAeroPercent",
    "Speed_35mph_ft_s", "DF_Total_35mph_lbf", "DF_Front_35mph_lbf", "DF_Rear_35mph_lbf",
    "Drag_Total_35mph_lbf", "LiftToDrag_35mph",
    "Speed_45mph_ft_s", "DF_Total_45mph_lbf", "DF_Front_45mph_lbf", "DF_Rear_45mph_lbf",
    "Drag_Total_45mph_lbf", "LiftToDrag_45mph",
    "Speed_60mph_ft_s", "DF_Total_60mph_lbf", "DF_Front_60mph_lbf", "DF_Rear_60mph_lbf",
    "Drag_Total_60mph_lbf", "LiftToDrag_60mph",
    "FeasibilityRefSpeed_mph", "FeasibilityRefSpeed_ft_s", "DF_Total_FeasRef_lbf", "Drag_Total_FeasRef_lbf",
    "LiftToDrag_FeasRef", "MinFeasibleDownforceAtRef_lbf", "MaxFeasibleDownforceAtRef_lbf",
    "MinFeasibleLiftToDrag", "MaxFeasibleLiftToDrag", "MinFeasibleDragAtRef_lbf", "MaxFeasibleDragAtRef_lbf",
    "IsFeasibleAeroTarget", "FeasibilityNotes",
]

# §A new columns appended by the Python pipeline (names are the contract)
NEW_COLUMNS = [
    "DragEnergy_Endurance_kJ", "DragEnergy_Autocross_kJ",
    "TractiveEnergy_Endurance_kJ", "TractiveEnergy_Autocross_kJ",
    "Efficiency_Score", "Mass_lbf", "MassScenario", "BSFC_g_per_kWh", "EngineMode",
]

REQUIRED_DASHBOARD_COLUMNS = [
    "CL_target", "CD_target", "CoP_target",
    "Total_Points", "Accel_Score", "Skidpad_Score", "Autocross_Score", "Endurance_Score",
    "Accel_Time", "Skidpad_Time", "Autocross_Time", "Endurance_Lap_Time",
    "CL_over_CD", "RunMode", "IsFeasibleAeroTarget",
]

TRACE_COLUMNS = ["Event", "Time_s", "Distance_ft", "Speed_ft_s",
                 "Longitudinal_G", "Lateral_G", "Gear"]
# Appended after the canonical §B header (append-never-rename, like §A);
# the dashboard's PapaParse reader accesses fields by name and tolerates them.
TRACE_EXTRA_COLUMNS = ["X_ft", "Y_ft"]
TRACE_EVENTS = {"Endurance", "Autocross"}

SUMMARY_COLUMNS = [
    "AeroTag", "CL_target", "CD_target", "CoP_target",
    "Endurance_Lap_Time", "Autocross_Time", "Skidpad_Time", "Accel_Time",
    "Endurance_Max_Speed", "Autocross_Max_Speed", "Max_AX", "Min_AX", "Max_Abs_AY",
]

RUN_MODES = {"Fast", "AccurateRerun"}


def safe_aero_tag(tag: str) -> str:
    """V4: regexprep(aeroTag, '[^A-Za-z0-9_-]', '_')."""
    return re.sub(r"[^A-Za-z0-9_-]", "_", str(tag))


def order_results_columns(df: pd.DataFrame) -> pd.DataFrame:
    cols = [c for c in COMMITTED_COLUMNS if c in df.columns]
    cols += [c for c in NEW_COLUMNS if c in df.columns]
    cols += [c for c in df.columns if c not in cols]
    return df[cols]


def write_results_workbook(df: pd.DataFrame, path: str, extra_sheets: dict | None = None):
    """Workbook with the contract sheet first; optional extra ranked sheets."""
    out = order_results_columns(df.sort_values("Total_Points", ascending=False))
    with pd.ExcelWriter(path, engine="openpyxl") as xw:
        out.to_excel(xw, sheet_name=SHEET_NAME, index=False)
        for name, sheet_df in (extra_sheets or {}).items():
            sheet_df.to_excel(xw, sheet_name=name[:31], index=False)


def trace_frame(case: CaseResult) -> pd.DataFrame:
    rows = []
    for ev, lap in (("Endurance", case.endurance), ("Autocross", case.autocross)):
        rows.append(pd.DataFrame({
            "Event": ev,
            "Time_s": lap.time_elapsed,
            "Distance_ft": lap.distance,
            "Speed_ft_s": lap.velocity,
            "Longitudinal_G": lap.acceleration,
            "Lateral_G": lap.lateral_accel,
            "Gear": lap.gear,
            "X_ft": lap.x_ft,
            "Y_ft": lap.y_ft,
        }))
    return pd.concat(rows, ignore_index=True)[TRACE_COLUMNS + TRACE_EXTRA_COLUMNS]


def write_trace_csv(case: CaseResult, path: str):
    trace_frame(case).to_csv(path, index=False)


def write_validation_summary_csv(cases: list[CaseResult], path: str):
    df = pd.DataFrame([validation_summary_row(c) for c in cases])[SUMMARY_COLUMNS]
    df.to_csv(path, index=False)


def _git_sha() -> str:
    try:
        return subprocess.run(["git", "rev-parse", "HEAD"], capture_output=True,
                              text=True, check=True).stdout.strip()
    except Exception:
        return "unknown"


def meta_json(cfg: SimConfig, assumptions: list[dict] | None = None) -> dict:
    return {
        "git_sha": _git_sha(),
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "engine": {"name": "pylapsim", "version": __version__,
                   "legacy_compat": cfg.legacy_compat},
        "config": cfg.snapshot(),
        "sources": [
            "Tire Data/A2356run008_MF52_Fy_12.mat",
            "Tire Data/A2356run008_MF52_Fy_GV12.mat",
            "Tire Data/Hoosier R20 18x6.0-10 10 Psi FX.mat",
            "Sim Data/Endurance_Coordinates_1.xlsx",
            "Sim Data/Autocross_Coordinates_2.xlsx",
            "Sim Data/endurance_racing_line.mat",
            "Sim Data/autocross_racing_line.mat",
        ],
        "assumptions": assumptions or [
            {"name": "bsfc_g_per_kWh", "value": cfg.bsfc_g_per_kwh,
             "source": "team input required"},
        ],
    }


def write_meta_json(path: str, cfg: SimConfig, assumptions: list[dict] | None = None):
    with open(path, "w") as f:
        json.dump(meta_json(cfg, assumptions), f, indent=2)


# --------------------------- validators (§F) ---------------------------

def validate_workbook(path: str) -> pd.DataFrame:
    """Same expectations as the dashboard's onSweepFile parser."""
    xl = pd.ExcelFile(path)
    assert SHEET_NAME in xl.sheet_names, f"missing sheet {SHEET_NAME!r}"
    df = pd.read_excel(xl, sheet_name=SHEET_NAME)
    missing = [c for c in REQUIRED_DASHBOARD_COLUMNS if c not in df.columns]
    assert not missing, f"missing required columns: {missing}"
    missing54 = [c for c in COMMITTED_COLUMNS if c not in df.columns]
    assert not missing54, f"missing committed schema columns: {missing54}"
    assert set(df.RunMode.unique()) <= RUN_MODES, f"bad RunMode values: {set(df.RunMode)}"
    feas = df.IsFeasibleAeroTarget
    ok_bool = feas.isin([True, False, 1, 0, "TRUE", "FALSE"]).all()
    assert ok_bool, "IsFeasibleAeroTarget not boolean-parseable"
    numeric_cols = ["CL_target", "CD_target", "CoP_target", "Total_Points",
                    "Accel_Score", "Skidpad_Score", "Autocross_Score", "Endurance_Score",
                    "Accel_Time", "Skidpad_Time", "Autocross_Time", "Endurance_Lap_Time",
                    "CL_over_CD"]
    for c in numeric_cols:
        vals = pd.to_numeric(df[c], errors="coerce")
        assert vals.notna().all(), f"column {c} has non-numeric entries"
        assert np.isfinite(vals).all(), f"column {c} has non-finite entries"
    return df


def validate_trace(path: str) -> pd.DataFrame:
    df = pd.read_csv(path)
    head = list(df.columns)[: len(TRACE_COLUMNS)]
    assert head == TRACE_COLUMNS, f"trace canonical header mismatch: {head}"
    extras = list(df.columns)[len(TRACE_COLUMNS):]
    assert all(e in TRACE_EXTRA_COLUMNS for e in extras), f"unknown trace columns: {extras}"
    assert set(df.Event.unique()) <= TRACE_EVENTS, f"bad Event values: {set(df.Event)}"
    for c in list(df.columns)[1:]:
        vals = pd.to_numeric(df[c], errors="coerce")
        assert vals.notna().all(), f"trace column {c} has non-numeric entries"
    for ev, g in df.groupby("Event"):
        assert (np.diff(g.Time_s) >= 0).all(), f"{ev} Time_s not monotonic"
    return df


def validate_summary(path: str) -> pd.DataFrame:
    df = pd.read_csv(path)
    assert list(df.columns) == SUMMARY_COLUMNS, f"summary header mismatch: {list(df.columns)}"
    for c in SUMMARY_COLUMNS[1:]:
        vals = pd.to_numeric(df[c], errors="coerce")
        assert vals.notna().all(), f"summary column {c} has non-numeric entries"
    return df


def validate_meta(path: str) -> dict:
    with open(path) as f:
        meta = json.load(f)
    for k in ("git_sha", "generated_at", "engine", "config", "sources", "assumptions"):
        assert k in meta, f"meta.json missing {k!r}"
    assert "legacy_compat" in meta["engine"]
    return meta
