"""Top-level single-case orchestrator (the V4 script flow)."""

from __future__ import annotations

import time
from dataclasses import dataclass, field

import numpy as np

from .config import SimConfig, VehicleConfig
from .energy import drag_energy_kj, tractive_energy_kj
from .events import accel_event_time, skidpad_time
from .ggv import GGV, build_ggv
from .lapsolver import LapResult, solve_lap
from .powertrain import Powertrain
from .scoring import EventScores, score_events
from .tires import MF52Fy, PPFormTensor, load_fx_spline, load_lateral_model
from .track import TrackData, load_autocross, load_endurance


@dataclass
class SharedData:
    """Process-wide caches that do not depend on the aero target."""

    mf: MF52Fy
    fx: PPFormTensor
    endurance: TrackData
    autocross: TrackData

    @classmethod
    def load(cls, veh: VehicleConfig | None = None) -> "SharedData":
        veh = veh or VehicleConfig()
        return cls(
            mf=load_lateral_model(),
            fx=load_fx_spline(),
            endurance=load_endurance(veh.tw_ft),
            autocross=load_autocross(veh.tw_ft),
        )


@dataclass
class CaseResult:
    config: SimConfig
    scores: EventScores
    endurance_lap_time: float
    autocross_time: float
    skidpad_time: float
    accel_time: float
    endurance: LapResult
    autocross: LapResult
    ggv: GGV
    drag_energy_endurance_kj: float
    drag_energy_autocross_kj: float
    tractive_energy_endurance_kj: float
    tractive_energy_autocross_kj: float
    runtime_s: float = 0.0

    @property
    def total_points(self) -> float:
        return self.scores.total


def run_case(cfg: SimConfig, shared: SharedData | None = None) -> CaseResult:
    t0 = time.perf_counter()
    veh = cfg.resolved_vehicle()
    if shared is None:
        shared = SharedData.load(veh)
    pt = Powertrain(veh)
    ggv = build_ggv(cfg, shared.mf, shared.fx, pt)

    end_lap = solve_lap(shared.endurance, ggv, sprint=False)
    ax_lap = solve_lap(shared.autocross, ggv, sprint=True)
    t_skid = skidpad_time(ggv, veh)
    t_accel = accel_event_time(ggv)

    scores = score_events(end_lap.lap_time, ax_lap.lap_time, t_skid, t_accel,
                          cfg.anchors)
    return CaseResult(
        config=cfg,
        scores=scores,
        endurance_lap_time=end_lap.lap_time,
        autocross_time=ax_lap.lap_time,
        skidpad_time=t_skid,
        accel_time=t_accel,
        endurance=end_lap,
        autocross=ax_lap,
        ggv=ggv,
        drag_energy_endurance_kj=drag_energy_kj(end_lap, cfg.aero.cd),
        drag_energy_autocross_kj=drag_energy_kj(ax_lap, cfg.aero.cd),
        tractive_energy_endurance_kj=tractive_energy_kj(end_lap, cfg.aero.cd, veh.weight_lbf),
        tractive_energy_autocross_kj=tractive_energy_kj(ax_lap, cfg.aero.cd, veh.weight_lbf),
        runtime_s=time.perf_counter() - t0,
    )


def validation_summary_row(case: CaseResult) -> dict:
    """DATA_CONTRACT §C row."""
    cfg = case.config
    return {
        "AeroTag": cfg.aero.tag,
        "CL_target": cfg.aero.cl,
        "CD_target": cfg.aero.cd,
        "CoP_target": cfg.aero.cop,
        "Endurance_Lap_Time": case.endurance_lap_time,
        "Autocross_Time": case.autocross_time,
        "Skidpad_Time": case.skidpad_time,
        "Accel_Time": case.accel_time,
        "Endurance_Max_Speed": float(np.max(case.endurance.velocity)),
        "Autocross_Max_Speed": float(np.max(case.autocross.velocity)),
        "Max_AX": float(np.max(case.endurance.acceleration)),
        "Min_AX": float(np.min(case.endurance.acceleration)),
        "Max_Abs_AY": float(np.max(np.abs(case.endurance.lateral_accel))),
    }
