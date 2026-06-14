"""Aero sweep runner: port of Run_T27_AeroSweep_MultithreadedExcel.m
(grid + baseline, fast pass, accurate rerun of top N, post/force/feasibility
columns) with multiprocessing across cases.
"""

from __future__ import annotations

import os
from concurrent.futures import ProcessPoolExecutor
from dataclasses import dataclass, field, replace

import numpy as np
import pandas as pd

from .config import HIGH, MEDIUM, AeroTarget, Resolution, SimConfig
from .simulate import CaseResult, SharedData, run_case

MPH_TO_FPS = 5280.0 / 3600.0

# Committed runner defaults (Run_T27_AeroSweep_MultithreadedExcel.m §1)
CL_LIST = np.arange(0.035, 0.0551, 0.005)
CD_LIST = np.arange(0.015, 0.0301, 0.0025)
COP_LIST = np.arange(0.425, 0.5251, 0.025)
BASELINE = AeroTarget(0.080, 0.020, 0.450)
TARGET_SPEEDS_MPH = (35.0, 45.0, 60.0)
TARGET_COP = 0.450


@dataclass(frozen=True)
class FeasibilityWindow:
    """Team placeholder window (PROJECT_TODOS flags it as placeholder)."""

    ref_speed_mph: float = 35.0
    df_min_lbf: float = 90.0
    df_max_lbf: float = 135.0
    ld_min: float = 2.0
    ld_max: float = 2.4
    drag_min_lbf: float = 40.0
    drag_max_lbf: float = 65.0


def sweep_combos(cl_list=CL_LIST, cd_list=CD_LIST, cop_list=COP_LIST,
                 baseline: AeroTarget = BASELINE) -> list[AeroTarget]:
    """ndgrid order with the baseline prepended, unique 'stable' (runner §2).
    MATLAB ndgrid varies the FIRST axis fastest."""
    combos = [baseline]
    seen = {(round(baseline.cl, 10), round(baseline.cd, 10), round(baseline.cop, 10))}
    for cop in cop_list:
        for cd in cd_list:
            for cl in cl_list:
                key = (round(cl, 10), round(cd, 10), round(cop, 10))
                if key not in seen:
                    seen.add(key)
                    combos.append(AeroTarget(float(cl), float(cd), float(cop)))
    return combos


_SHARED: SharedData | None = None


def _init_worker():
    global _SHARED
    _SHARED = SharedData.load()


def _run_one(args) -> dict:
    cfg, run_mode, run_number = args
    global _SHARED
    if _SHARED is None:
        _SHARED = SharedData.load()
    case = run_case(cfg, _SHARED)
    return case_row(case, run_mode, run_number)


def case_row(case: CaseResult, run_mode: str, run_number: int) -> dict:
    """One results-table row (V4 Section 17 logging + runner row fields)."""
    cfg = case.config
    aero = cfg.aero
    return {
        "AeroTag": f"{run_mode}_{aero.tag}",
        "CL_target": aero.cl,
        "CD_target": aero.cd,
        "CoP_target": aero.cop,
        "Accel_Score": case.scores.accel,
        "Skidpad_Score": case.scores.skidpad,
        "Autocross_Score": case.scores.autocross,
        "Endurance_Score": case.scores.endurance,
        "Total_Points": case.total_points,
        "Skidpad_Time": case.skidpad_time,
        "Accel_Time": case.accel_time,
        "Autocross_Time": case.autocross_time,
        "Endurance_Lap_Time": case.endurance_lap_time,
        "RunNumber": run_number,
        "RunMode": run_mode,
        # Phase 3 appended columns (DATA_CONTRACT §A "new columns")
        "DragEnergy_Endurance_kJ": case.drag_energy_endurance_kj,
        "DragEnergy_Autocross_kJ": case.drag_energy_autocross_kj,
        "TractiveEnergy_Endurance_kJ": case.tractive_energy_endurance_kj,
        "TractiveEnergy_Autocross_kJ": case.tractive_energy_autocross_kj,
        "Efficiency_Score": None if cfg.bsfc_g_per_kwh is None else np.nan,
        "Mass_lbf": cfg.resolved_vehicle().weight_lbf,
        "MassScenario": cfg.mass_scenario,
        "BSFC_g_per_kWh": cfg.bsfc_g_per_kwh,
        "EngineMode": "legacy" if cfg.legacy_compat else "corrected",
    }


def add_post_metrics(df: pd.DataFrame, baseline: AeroTarget = BASELINE,
                     target_cop: float = TARGET_COP) -> pd.DataFrame:
    """Runner addPostMetrics (baseline row resolved the same way)."""
    tol = 1e-12
    mask = (((df.CL_target - baseline.cl).abs() <= tol)
            & ((df.CD_target - baseline.cd).abs() <= tol)
            & ((df.CoP_target - baseline.cop).abs() <= tol))
    base_total = df.loc[mask, "Total_Points"].iloc[0] if mask.any() else df.Total_Points.iloc[0]
    eps = np.finfo(float).eps
    df = df.copy()
    df["CL_over_CD"] = df.CL_target / np.maximum(df.CD_target, eps)
    df["PointGain_vs_Baseline"] = df.Total_Points - base_total
    df["CD_Increase_vs_Baseline"] = df.CD_target - baseline.cd
    df["CL_Increase_vs_Baseline"] = df.CL_target - baseline.cl
    df["PointGain_per_CD"] = df.PointGain_vs_Baseline / np.maximum(df.CD_Increase_vs_Baseline, eps)
    df["BalanceError"] = (df.CoP_target - target_cop).abs()
    df["FrontAeroPercent"] = df.CoP_target * 100.0
    df["RearAeroPercent"] = (1.0 - df.CoP_target) * 100.0
    return df


def add_aero_force_columns(df: pd.DataFrame,
                           speeds_mph=TARGET_SPEEDS_MPH) -> pd.DataFrame:
    df = df.copy()
    eps = np.finfo(float).eps
    for mph in speeds_mph:
        fps = mph * MPH_TO_FPS
        label = str(int(mph)) if float(mph).is_integer() else str(mph).replace(".", "p")
        dft = df.CL_target * fps**2
        drg = df.CD_target * fps**2
        df[f"Speed_{label}mph_ft_s"] = fps
        df[f"DF_Total_{label}mph_lbf"] = dft
        df[f"DF_Front_{label}mph_lbf"] = dft * df.CoP_target
        df[f"DF_Rear_{label}mph_lbf"] = dft * (1 - df.CoP_target)
        df[f"Drag_Total_{label}mph_lbf"] = drg
        df[f"LiftToDrag_{label}mph"] = dft / np.maximum(drg, eps)
    return df


def add_feasibility_columns(df: pd.DataFrame,
                            win: FeasibilityWindow = FeasibilityWindow()) -> pd.DataFrame:
    df = df.copy()
    eps = np.finfo(float).eps
    fps = win.ref_speed_mph * MPH_TO_FPS
    df["FeasibilityRefSpeed_mph"] = win.ref_speed_mph
    df["FeasibilityRefSpeed_ft_s"] = fps
    df["DF_Total_FeasRef_lbf"] = df.CL_target * fps**2
    df["Drag_Total_FeasRef_lbf"] = df.CD_target * fps**2
    df["LiftToDrag_FeasRef"] = df.DF_Total_FeasRef_lbf / np.maximum(df.Drag_Total_FeasRef_lbf, eps)
    df["MinFeasibleDownforceAtRef_lbf"] = win.df_min_lbf
    df["MaxFeasibleDownforceAtRef_lbf"] = win.df_max_lbf
    df["MinFeasibleLiftToDrag"] = win.ld_min
    df["MaxFeasibleLiftToDrag"] = win.ld_max
    df["MinFeasibleDragAtRef_lbf"] = win.drag_min_lbf
    df["MaxFeasibleDragAtRef_lbf"] = win.drag_max_lbf
    # Floor-only feasibility (team decision 2026-06-13). The upper caps
    # (DF/drag/L/D max) were a placeholder window and are dropped: more
    # downforce scores higher, and whether a target is buildable is a
    # CFD/test question, not a feasibility verdict. The only retained gate is
    # a minimum-downforce sanity floor (df_min). The Max* reference columns
    # above are kept for schema compatibility but no longer gate the verdict.
    below_df = df.DF_Total_FeasRef_lbf < win.df_min_lbf
    df["IsFeasibleAeroTarget"] = ~below_df
    notes = pd.Series([""] * len(df), index=df.index)
    notes[below_df] += "DF below minimum-downforce floor; "
    notes[notes == ""] = "OK"
    df["FeasibilityNotes"] = notes
    return df


def finalize_results(df: pd.DataFrame, baseline: AeroTarget = BASELINE,
                     win: FeasibilityWindow = FeasibilityWindow()) -> pd.DataFrame:
    df = add_post_metrics(df, baseline)
    df = add_aero_force_columns(df)
    df = add_feasibility_columns(df, win)
    return df.sort_values("Total_Points", ascending=False).reset_index(drop=True)


def run_sweep(base_cfg: SimConfig | None = None,
              combos: list[AeroTarget] | None = None,
              fast_resolution: Resolution = MEDIUM,
              rerun_top_accurate: int = 10,
              workers: int | None = None,
              k_mass_lbf_per_cl: float = 0.0,
              cl_ref: float = 0.040,
              mass_scenario: str | None = None,
              progress=None) -> pd.DataFrame:
    """Fast sweep + accurate rerun, returns the raw (pre-finalize) rows.

    Mass coupling (FINDINGS F5): m(CL) = m0 + k_mass*(CL - cl_ref). k_mass is
    a SCENARIO parameter — when unsourced, callers must label the scenario
    accordingly (assumptions in docs/PORT_AND_MATLAB.md §2)."""
    base_cfg = base_cfg or SimConfig()
    combos = combos or sweep_combos()
    workers = workers or max(1, (os.cpu_count() or 2) - 2)
    scenario = mass_scenario or (
        "baseline" if k_mass_lbf_per_cl == 0.0
        else f"k_mass={k_mass_lbf_per_cl:g} lbf/CL (scenario bracket, unsourced)")

    def _cfg_for(a: AeroTarget) -> SimConfig:
        return replace(base_cfg, aero=a,
                       extra_mass_lbf=k_mass_lbf_per_cl * (a.cl - cl_ref),
                       mass_scenario=scenario)

    jobs = [(replace(_cfg_for(a), resolution=fast_resolution), "Fast", i + 1)
            for i, a in enumerate(combos)]
    rows = []
    with ProcessPoolExecutor(max_workers=workers, initializer=_init_worker) as ex:
        for i, row in enumerate(ex.map(_run_one, jobs, chunksize=2)):
            rows.append(row)
            if progress and (i + 1) % 25 == 0:
                progress(f"fast {i + 1}/{len(jobs)}")
    fast_df = pd.DataFrame(rows)

    if rerun_top_accurate > 0:
        top = fast_df.sort_values("Total_Points", ascending=False).head(rerun_top_accurate)
        jobs = [(replace(_cfg_for(AeroTarget(r.CL_target, r.CD_target, r.CoP_target)),
                         resolution=HIGH),
                 "AccurateRerun", j + 1)
                for j, r in enumerate(top.itertuples())]
        with ProcessPoolExecutor(max_workers=workers, initializer=_init_worker) as ex:
            for row in ex.map(_run_one, jobs):
                rows.append(row)
            if progress:
                progress(f"accurate rerun {len(jobs)} done")
    return pd.DataFrame(rows)
