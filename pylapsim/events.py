"""Skidpad + acceleration event: port of V4 Section 17 (event sims only;
score formulas live in scoring.py).
"""

from __future__ import annotations

import numpy as np

from .config import GRAVITY, VehicleConfig
from .ggv import GGV
from .lapsolver import _gear_from_shift_points, _quad_dt


def skidpad_time(ggv: GGV, veh: VehicleConfig) -> float:
    """V4: path_radius = 25 + tw/2 + .5; speed from the cornering spline."""
    path_radius = 25.0 + veh.tw_ft / 2.0 + 0.5
    speed = float(ggv.cornering(path_radius))
    return path_radius * 2.0 * np.pi / speed


def accel_event_time(ggv: GGV) -> float:
    """V4's 'little quickie accel sim': 247 x 1 ft segments, gear starts at 2,
    accel_time = sum(dt(2:end)) + 0.1."""
    sp = ggv.shift_points
    vmax = ggv.top_speed
    vel = 0.0
    gear = 2
    time_shifting = 0.0
    dts = []
    eps = np.finfo(float).eps
    for _ in range(247):
        newgear = _gear_from_shift_points(sp, vel)
        shifting = newgear > gear
        AX = float(ggv.accel(vel))
        dd = 1.0
        if shifting and vel < vmax:
            dt = dd / max(vel, eps)
            time_shifting += dt
            dts.append(dt)
        elif vel < vmax:
            dt = _quad_dt(AX, vel, dd)
            dts.append(dt)
            dv = GRAVITY * AX * dt
            dv = min(dv, vmax - vel)
            vel = vel + dv
            newgear = _gear_from_shift_points(sp, vel)
            if newgear > gear:
                shifting = True
        else:
            vel = vmax
            dts.append(dd / max(vel, eps))
        if time_shifting > ggv.shift_time:
            shifting = False
            time_shifting = 0.0
            if newgear != 1:
                gear = newgear
        if not (shifting or newgear == 1):
            gear = newgear
    return float(np.sum(dts[1:]) + 0.1)
