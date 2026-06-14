"""Powertrain port: V4 Section 2 + Powertrainlapsim.m + calc_shiftpoints.m.

All committed dyno-table numbers are copied verbatim from V4 (lines 98-100).
Units follow the MATLAB original: the engine model works in metric (m/s, N-m,
N); the lap sim converts at the call sites (ft/s / 3.28, N * 0.2248 -> lbf).
"""

from __future__ import annotations

import math

import numpy as np
from scipy.interpolate import PchipInterpolator

# V4 lines 98-100, verbatim
ENGINE_TQ_RAW = np.array([
    36.48501, 38.59397, 44.32983, 46.28545, 47.887875, 49.829956, 51.228146,
    51.03791, 51.292057, 51.900978, 52.434673, 52.499348, 51.684544,
    50.131496, 49.159187, 48.94724, 49.628212, 50.57417, 51.357998,
    51.728046, 51.37902, 50.64954, 49.651802, 48.46732, 47.18437, 44.13004,
    40.682053, 36.252777,
])
ENGINE_RPM_RAW = np.array([
    4000.0, 5000.0, 6000.0, 7000.0, 7500.0, 8000.0, 8500.0, 9000.0, 9500.0,
    9750.0, 10000.0, 10250.0, 10500.0, 10750.0, 11000.0, 11250.0, 11500.0,
    11750.0, 12000.0, 12250.0, 12500.0, 12750.0, 13000.0, 13250.0, 13500.0,
    14000.0, 14500.0, 15000.0,
])


def calc_shiftpoints(final_drive, gear_ratios, torque_curve, redline,
                     primary_reduction, tire_radius_m, rpm) -> np.ndarray:
    """Port of Powertrain/calc_shiftpoints.m (power-crossover shift RPM)."""
    gear_ratios = np.asarray(gear_ratios, dtype=float)
    rpm = np.asarray(rpm, dtype=float)
    torque_curve = np.asarray(torque_curve, dtype=float)
    red = gear_ratios * final_drive * primary_reduction
    torque_by_gear = red[:, None] * torque_curve[None, :]
    power_by_gear = torque_by_gear * rpm[None, :] / 9550.0
    speed = rpm[None, :] / red[:, None] * tire_radius_m / 60.0 * (2 * math.pi)
    n = len(red)
    shiftpoints = np.ones(n - 1)
    for i in range(n - 1):
        j_final = len(rpm) - 1
        for j in range(len(rpm)):
            mask = speed[i, j] > speed[i + 1, :]
            idxs = np.nonzero(mask)[0]
            if idxs.size == 0:
                # MATLAB find(...,1,'last') empty -> new_power empty -> the
                # `if new_power > current_power` comparison is false; continue
                j_final = j
                continue
            new_power = power_by_gear[i + 1, idxs[-1]]
            if new_power > power_by_gear[i, j]:
                j_final = j
                break
            j_final = j
        shiftpoints[i] = rpm[j_final]
    return shiftpoints


class Powertrain:
    """Engine + gearbox model with the V4 resampled torque table."""

    def __init__(self, vehicle):
        self.v = vehicle
        self.engine_speed = np.arange(6000.0, vehicle.redline + 1, 100.0)
        pch = PchipInterpolator(ENGINE_RPM_RAW, ENGINE_TQ_RAW)
        self.engine_tq = pch(self.engine_speed)
        self.tyre_radius_m = vehicle.tire_radius_ft / 3.28
        self.shiftpoints_rpm = calc_shiftpoints(
            vehicle.final_drive, vehicle.gear_ratios, self.engine_tq,
            vehicle.redline, vehicle.primary_reduction, self.tyre_radius_m,
            self.engine_speed,
        )
        gear_tot_top = vehicle.gear_ratios[-1] * vehicle.final_drive * vehicle.primary_reduction
        self.vmax_fts = math.floor(
            3.28 * vehicle.redline / (gear_tot_top / self.tyre_radius_m * 60.0 / (2 * math.pi))
        )
        self._reductions = np.array(
            [g * vehicle.final_drive * vehicle.primary_reduction for g in vehicle.gear_ratios]
        )

    def wheel_force_and_gear(self, v_ms: float) -> tuple[float, int]:
        """Port of Powertrainlapsim.m: (wheel force [N], 1-based gear)."""
        gear_sel = 0  # 0-based
        rpm = v_ms * self._reductions[gear_sel] / self.tyre_radius_m * 60.0 / (2 * math.pi)
        while gear_sel < len(self._reductions) - 1 and rpm > self.shiftpoints_rpm[gear_sel]:
            gear_sel += 1
            rpm = v_ms * self._reductions[gear_sel] / self.tyre_radius_m * 60.0 / (2 * math.pi)
        # interp1 ... 'linear','extrap'
        torque = float(np.interp(rpm, self.engine_speed, self.engine_tq))
        if rpm < self.engine_speed[0]:
            t0, t1 = self.engine_tq[0], self.engine_tq[1]
            s0, s1 = self.engine_speed[0], self.engine_speed[1]
            torque = t0 + (rpm - s0) * (t1 - t0) / (s1 - s0)
        elif rpm > self.engine_speed[-1]:
            t0, t1 = self.engine_tq[-2], self.engine_tq[-1]
            s0, s1 = self.engine_speed[-2], self.engine_speed[-1]
            torque = t1 + (rpm - s1) * (t1 - t0) / (s1 - s0)
        torque = torque * self._reductions[gear_sel] * self.v.drivetrain_losses
        return torque / self.tyre_radius_m, gear_sel + 1
