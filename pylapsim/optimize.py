"""Phase 5: constrained goal-seeking + uncertainty quantification.

Optimization: multi-objective (maximize Total_Points, minimize
DragEnergy_Endurance) over (CL, CD, CoP) subject to the team's feasibility
window (explicit placeholder config — PROJECT_TODOS). pymoo NSGA-II with
parallel case evaluation; scipy differential_evolution scalarized fallback.

UQ: Monte Carlo over {sf_x, sf_y, mass} using common random numbers across
candidates so P(A beats B) is a paired comparison; Sobol first-order/total
indices via SALib. BSFC is excluded: Efficiency_Score is unconfigured by
team decision (2026-06-12), so it cannot contribute variance.

All ranking language downstream must apply the F4 fast-noise tie band
(±3.95 pts): gaps inside the band are ties.
"""

from __future__ import annotations

import os
from concurrent.futures import ProcessPoolExecutor
from dataclasses import replace

import numpy as np
import pandas as pd

from .config import MEDIUM, AeroTarget, SimConfig, VehicleConfig
from .simulate import SharedData, run_case
from .sweep import MPH_TO_FPS, FeasibilityWindow

F4_NOISE_BAND = 3.95  # pts, measured fast-vs-accurate max |delta| (FINDINGS F4)

_SHARED: SharedData | None = None


def _init_worker():
    global _SHARED
    _SHARED = SharedData.load()


def _eval_case(cfg: SimConfig) -> dict:
    global _SHARED
    if _SHARED is None:
        _SHARED = SharedData.load()
    case = run_case(cfg, _SHARED)
    return {
        "CL_target": cfg.aero.cl, "CD_target": cfg.aero.cd, "CoP_target": cfg.aero.cop,
        "Total_Points": case.total_points,
        "Accel_Score": case.scores.accel, "Skidpad_Score": case.scores.skidpad,
        "Autocross_Score": case.scores.autocross, "Endurance_Score": case.scores.endurance,
        "DragEnergy_Endurance_kJ": case.drag_energy_endurance_kj,
        "DragEnergy_Autocross_kJ": case.drag_energy_autocross_kj,
        "TractiveEnergy_Endurance_kJ": case.tractive_energy_endurance_kj,
        "sf_x": cfg.resolved_vehicle().sf_x, "sf_y": cfg.resolved_vehicle().sf_y,
        "Mass_lbf": cfg.resolved_vehicle().weight_lbf,
    }


def feasibility_violations(cl: float, cd: float, win: FeasibilityWindow) -> np.ndarray:
    """<=0 feasible, per constraint, at the window's reference speed."""
    fps = win.ref_speed_mph * MPH_TO_FPS
    df = cl * fps**2
    drag = cd * fps**2
    ld = df / max(drag, 1e-12)
    return np.array([
        win.df_min_lbf - df, df - win.df_max_lbf,
        win.drag_min_lbf - drag, drag - win.drag_max_lbf,
        win.ld_min - ld, ld - win.ld_max,
    ])


def run_nsga2(bounds_cl=(0.030, 0.060), bounds_cd=(0.014, 0.031),
              bounds_cop=(0.425, 0.650), pop_size=24, n_gen=15,
              win: FeasibilityWindow | None = None, workers: int | None = None,
              legacy_compat: bool = False, seed: int = 7,
              progress=None):
    """NSGA-II: max Total, min DragEnergy_Endurance, feasibility window as
    inequality constraints. Returns (result_df_of_all_evals, pareto_df)."""
    from pymoo.algorithms.moo.nsga2 import NSGA2
    from pymoo.core.problem import Problem
    from pymoo.optimize import minimize as pymoo_minimize

    win = win or FeasibilityWindow()
    workers = workers or max(1, (os.cpu_count() or 2) - 2)
    pool = ProcessPoolExecutor(max_workers=workers, initializer=_init_worker)
    all_rows: list[dict] = []

    class AeroProblem(Problem):
        def __init__(self):
            super().__init__(n_var=3, n_obj=2, n_ieq_constr=6,
                             xl=np.array([bounds_cl[0], bounds_cd[0], bounds_cop[0]]),
                             xu=np.array([bounds_cl[1], bounds_cd[1], bounds_cop[1]]))

        def _evaluate(self, X, out, *args, **kwargs):
            cfgs = [SimConfig(aero=AeroTarget(*x), resolution=MEDIUM,
                              legacy_compat=legacy_compat) for x in X]
            rows = list(pool.map(_eval_case, cfgs))
            all_rows.extend(rows)
            F = np.array([[-r["Total_Points"], r["DragEnergy_Endurance_kJ"]] for r in rows])
            G = np.array([feasibility_violations(x[0], x[1], win) for x in X])
            out["F"] = F
            out["G"] = G
            if progress:
                progress(f"evaluated {len(all_rows)} cases")

    res = pymoo_minimize(AeroProblem(), NSGA2(pop_size=pop_size), ("n_gen", n_gen),
                         seed=seed, verbose=False)
    pool.shutdown()
    evals = pd.DataFrame(all_rows)
    X = np.atleast_2d(res.X)
    F = np.atleast_2d(res.F)
    pareto = pd.DataFrame({
        "CL_target": X[:, 0], "CD_target": X[:, 1], "CoP_target": X[:, 2],
        "Total_Points": -F[:, 0], "DragEnergy_Endurance_kJ": F[:, 1],
    }).sort_values("Total_Points", ascending=False).reset_index(drop=True)
    return evals, pareto


def run_de_fallback(win: FeasibilityWindow | None = None, legacy_compat: bool = False,
                    weight_drag: float = 0.0, seed: int = 7, maxiter: int = 12):
    """Scalarized differential evolution fallback (Total − w·DragEnergy)."""
    from scipy.optimize import NonlinearConstraint, differential_evolution

    win = win or FeasibilityWindow()
    shared = SharedData.load()

    def neg_obj(x):
        cfg = SimConfig(aero=AeroTarget(*x), resolution=MEDIUM, legacy_compat=legacy_compat)
        case = run_case(cfg, shared)
        return -(case.total_points - weight_drag * case.drag_energy_endurance_kj)

    nlc = NonlinearConstraint(
        lambda x: feasibility_violations(x[0], x[1], win), -np.inf, 0.0)
    res = differential_evolution(neg_obj, [(0.030, 0.060), (0.014, 0.031), (0.425, 0.650)],
                                 constraints=(nlc,), seed=seed, maxiter=maxiter,
                                 popsize=8, polish=False)
    return res


# ------------------------------- UQ ---------------------------------------

# Perturbation ranges: sf_x/sf_y are uncorrelated calibration factors (F7);
# ±10% relative is an ASSUMED uncertainty band (unsourced — labeled in all
# outputs). Mass ±15 lbf covers driver/fuel variation (unsourced, labeled).
UQ_RANGES = {
    "sf_x": (0.45 * 0.9, 0.45 * 1.1),
    "sf_y": (0.50 * 0.9, 0.50 * 1.1),
    "mass_delta_lbf": (-15.0, 15.0),
}
UQ_LABEL = "uncertainty ranges assumed (unsourced): sf_x/sf_y ±10% rel, mass ±15 lbf"


def _uq_cfg(aero: AeroTarget, sf_x: float, sf_y: float, dm: float,
            legacy_compat: bool = False) -> SimConfig:
    veh = VehicleConfig(sf_x=sf_x, sf_y=sf_y)
    return SimConfig(aero=aero, vehicle=veh, resolution=MEDIUM,
                     legacy_compat=legacy_compat, extra_mass_lbf=dm,
                     mass_scenario=f"UQ dm={dm:+.1f}")


def monte_carlo(candidates: dict[str, AeroTarget], n_draws: int = 40,
                seed: int = 11, workers: int | None = None,
                legacy_compat: bool = False, progress=None) -> pd.DataFrame:
    """Common-random-number MC: every candidate sees the SAME parameter draws,
    so candidate comparisons are paired."""
    rng = np.random.default_rng(seed)
    draws = np.column_stack([
        rng.uniform(*UQ_RANGES["sf_x"], n_draws),
        rng.uniform(*UQ_RANGES["sf_y"], n_draws),
        rng.uniform(*UQ_RANGES["mass_delta_lbf"], n_draws),
    ])
    workers = workers or max(1, (os.cpu_count() or 2) - 2)
    jobs, meta = [], []
    for name, aero in candidates.items():
        for i, (sx, sy, dm) in enumerate(draws):
            jobs.append(_uq_cfg(aero, sx, sy, dm, legacy_compat))
            meta.append({"candidate": name, "draw": i,
                         "sf_x": sx, "sf_y": sy, "mass_delta_lbf": dm})
    rows = []
    with ProcessPoolExecutor(max_workers=workers, initializer=_init_worker) as ex:
        for m, r in zip(meta, ex.map(_eval_case, jobs, chunksize=2)):
            rows.append({**m, "Total_Points": r["Total_Points"],
                         "DragEnergy_Endurance_kJ": r["DragEnergy_Endurance_kJ"]})
            if progress and len(rows) % 50 == 0:
                progress(f"MC {len(rows)}/{len(jobs)}")
    return pd.DataFrame(rows)


def p_beats(mc: pd.DataFrame, a: str, b: str) -> float:
    """P(candidate a beats b) over paired draws."""
    pa = mc[mc.candidate == a].set_index("draw").Total_Points
    pb = mc[mc.candidate == b].set_index("draw").Total_Points
    return float((pa - pb > 0).mean())


def sobol_indices(aero: AeroTarget, n_base: int = 64, workers: int | None = None,
                  legacy_compat: bool = False, seed: int = 13, progress=None):
    """Sobol first-order/total indices of Total_Points wrt (sf_x, sf_y, mass).
    Saltelli sampling: N*(2D+2) = n_base*8 model runs."""
    from SALib.analyze import sobol as sobol_analyze
    from SALib.sample import sobol as sobol_sample

    problem = {
        "num_vars": 3,
        "names": ["sf_x", "sf_y", "mass_delta_lbf"],
        "bounds": [list(UQ_RANGES["sf_x"]), list(UQ_RANGES["sf_y"]),
                   list(UQ_RANGES["mass_delta_lbf"])],
    }
    X = sobol_sample.sample(problem, n_base, calc_second_order=True, seed=seed)
    workers = workers or max(1, (os.cpu_count() or 2) - 2)
    jobs = [_uq_cfg(aero, sx, sy, dm, legacy_compat) for sx, sy, dm in X]
    Y = np.empty(len(jobs))
    with ProcessPoolExecutor(max_workers=workers, initializer=_init_worker) as ex:
        for i, r in enumerate(ex.map(_eval_case, jobs, chunksize=4)):
            Y[i] = r["Total_Points"]
            if progress and (i + 1) % 100 == 0:
                progress(f"sobol {i + 1}/{len(jobs)}")
    si = sobol_analyze.analyze(problem, Y, calc_second_order=True, seed=seed)
    return si, X, Y
