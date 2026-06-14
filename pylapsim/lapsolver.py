"""Quasi-steady lap solver: port of lap_information.m / lap_information_sprint.m.

Semantics preserved exactly (verified against the committed validation trace):
- per-segment corner cap min(VMAX, cornering(r)) with r clamped to [r_min, r_max]
- AX/AY capacities sampled once per segment at segment-entry speed
- friction-ellipse scaling AX*(1-(min(AY, ay)/AY)^2)
- quadratic time step (roots([0.5*g*ax, vel, -dd]), max root)
- shift logic: acceleration freezes while time_shifting <= shift_time
- endurance: fwd pass (v0=20) -> reverse pass from V0=v_f(end) -> fwd pass (v0=V0);
  autocross: single fwd pass (v0=30) -> reverse pass from V0 (no second fwd)
- combine: VD = v_f - v_r; VD < 0 -> forward sample, else reverse sample
- lateral capped at lateral(116), then signed by the curvature y-component
"""

from __future__ import annotations

import math
from dataclasses import dataclass

import numpy as np

from .config import GRAVITY
from .ggv import GGV
from .track import TrackData

INTERVAL = 5


@dataclass
class LapResult:
    lap_time: float
    time_elapsed: np.ndarray
    velocity: np.ndarray
    acceleration: np.ndarray  # longitudinal g (signed)
    lateral_accel: np.ndarray  # lateral g (signed by curvature)
    gear: np.ndarray
    distance: np.ndarray
    path_length: float
    x_ft: np.ndarray  # top-down sample position (track coordinates)
    y_ft: np.ndarray


def _gear_from_shift_points(shift_points: np.ndarray, vel: float) -> int:
    """MATLAB: gears = find((shift_points - vel) > 0); gear = gears(1)-1."""
    idx = np.nonzero(shift_points - vel > 0)[0]
    return int(idx[0])  # 0-based index == MATLAB gears(1)-1


def _quad_dt(ax: float, vel: float, dd: float) -> float:
    """max(roots([0.5*32.2*ax, vel, -dd])) with the MATLAB degenerate cases."""
    a = 0.5 * GRAVITY * ax
    if a == 0.0:
        return dd / max(vel, np.finfo(float).eps)
    disc = vel * vel + 4.0 * a * dd
    if disc < 0.0:
        # complex roots: MATLAB max() picks larger magnitude; both have the
        # same real part -b/2a. Does not occur on committed data.
        return -vel / (2.0 * a)
    sq = math.sqrt(disc)
    return max((-vel + sq) / (2.0 * a), (-vel - sq) / (2.0 * a))


def _forward_pass(track: TrackData, ggv: GGV, v0: float):
    sp = ggv.shift_points
    vmax_pt = ggv.top_speed
    nseg = len(track.seg_radius)
    n = nseg * INTERVAL
    ay_f = np.zeros(n)
    ax_f = np.zeros(n)
    dt_f = np.zeros(n)
    v_f = np.zeros(n)
    gear_log = np.zeros(n, dtype=int)

    r_clamped = np.clip(track.seg_radius, ggv.r_min, ggv.r_max)
    vmax_seg = np.minimum(vmax_pt, ggv.cornering(r_clamped))
    vmax_seg = np.where(vmax_seg < 0, vmax_pt, vmax_seg)

    vel = v0
    gear = _gear_from_shift_points(sp, vel)
    time_shifting = 0.0
    count = -1
    eps = np.finfo(float).eps
    for i in range(nseg):
        d = track.seg_dist[i]
        r = r_clamped[i]
        newgear = _gear_from_shift_points(sp, vel)
        shifting = newgear > gear
        vmax = vmax_seg[i]
        AX = float(ggv.accel(vel))
        AY = float(ggv.lateral(vel))
        dd = d / INTERVAL
        for _ in range(INTERVAL):
            count += 1
            gear_log[count] = gear
            ay = vel * vel / (r * GRAVITY)
            ay_f[count] = ay
            if shifting and vel < vmax:
                dt = dd / max(vel, eps)
                dt_f[count] = dt
                time_shifting += dt
                v_f[count] = vel
            elif vel < vmax:
                ax = AX * (1.0 - (min(AY, ay) / AY) ** 2)
                ax_f[count] = ax
                dt = _quad_dt(ax, vel, dd)
                dt_f[count] = dt
                dv = GRAVITY * ax * dt
                dv = min(dv, vmax - vel)
                vel = vel + dv
                v_f[count] = vel
                newgear = _gear_from_shift_points(sp, vel)
                if newgear > gear:
                    shifting = True
            else:
                vel = vmax
                dt_f[count] = dd / max(vel, eps)
                v_f[count] = vel
            if time_shifting > ggv.shift_time:
                shifting = False
                time_shifting = 0.0
                gear = newgear
        if not shifting:
            gear = newgear
    return v_f, ax_f, ay_f, dt_f, gear_log


def _reverse_pass(track: TrackData, ggv: GGV, v0: float):
    vmax_pt = ggv.top_speed
    nseg = len(track.seg_radius)
    n = nseg * INTERVAL
    ay_r = np.zeros(n)
    ax_r = np.zeros(n)
    dt_r = np.zeros(n)
    v_r = np.zeros(n)

    r_clamped = np.clip(track.seg_radius, ggv.r_min, ggv.r_max)
    vmax_seg = np.minimum(vmax_pt, ggv.cornering(r_clamped))
    vmax_seg = np.where(vmax_seg < 0, vmax_pt, vmax_seg)

    vel = v0
    count = n
    eps = np.finfo(float).eps
    for i in range(nseg - 1, -1, -1):
        d = track.seg_dist[i]
        r = r_clamped[i]
        vmax = vmax_seg[i]
        AX = float(ggv.deccel(vel))
        AY = float(ggv.lateral(vel))
        dd = d / INTERVAL
        for _ in range(INTERVAL):
            count -= 1
            ay = vel * vel / (r * GRAVITY)
            ay_r[count] = ay
            if vel < vmax:
                ax = AX * (1.0 - (min(AY, ay) / AY) ** 2)
                ax_r[count] = ax
                dt = _quad_dt(ax, vel, dd)
                dt_r[count] = dt
                dv = GRAVITY * ax * dt
                dv = min(dv, vmax - vel)
                vel = vel + dv
                v_r[count] = vel
            else:
                vel = vmax
                dt_r[count] = dd / max(vel, eps)
                v_r[count] = vel
    return v_r, ax_r, ay_r, dt_r


def solve_lap(track: TrackData, ggv: GGV, sprint: bool) -> LapResult:
    nseg = len(track.seg_radius)
    n = nseg * INTERVAL

    if sprint:
        v_f, ax_f, ay_f, dt_f, _ = _forward_pass(track, ggv, v0=30.0)
        v0 = v_f[-1]
        v_r, ax_r, ay_r, dt_r = _reverse_pass(track, ggv, v0=v0)
    else:
        v_f1, _, _, _, _ = _forward_pass(track, ggv, v0=20.0)
        v0 = v_f1[-1]
        v_r, ax_r, ay_r, dt_r = _reverse_pass(track, ggv, v0=v0)
        v_f, ax_f, ay_f, dt_f, _ = _forward_pass(track, ggv, v0=v0)

    # distance grid from the (any) forward pass segment lengths
    dd = np.repeat(track.seg_dist / INTERVAL, INTERVAL)
    distance = np.cumsum(dd)

    vd = v_f - v_r
    fwd = vd < 0
    velocity = np.where(fwd, v_f, v_r)
    dtime = np.where(fwd, dt_f, dt_r)
    acceleration = np.where(fwd, ax_f, -ax_r)
    lateral = np.where(fwd, ay_f, ay_r)
    time_elapsed = np.cumsum(dtime)

    cap = ggv.ay_cap_116
    lateral = np.where(lateral > cap, cap, lateral)
    seg_sign = np.sign(track.seg_ky)
    lateral = lateral * np.repeat(seg_sign, INTERVAL)

    gear_counter = np.empty(n, dtype=int)
    sp = ggv.shift_points
    # vectorized find((shift_points - V) > 0, 1) - 1
    gear_counter = np.searchsorted(sp, velocity, side="right")
    # searchsorted gives count of sp <= v; MATLAB wants first sp > v (0-based
    # index). sp values equal to v are not "> v": side="right" matches.

    # per-sample top-down position: linear within each segment, sample taken
    # at the end of its interval (consistent with the cumulative distance)
    seg_idx = np.arange(n) // INTERVAL
    frac = (np.arange(n) % INTERVAL + 1) / INTERVAL
    p1 = track.seg_p1[seg_idx]
    p2 = track.seg_p2[seg_idx]
    xy = p1 + frac[:, None] * (p2 - p1)

    return LapResult(
        lap_time=float(time_elapsed[-1]),
        time_elapsed=time_elapsed,
        velocity=velocity,
        acceleration=acceleration,
        lateral_accel=lateral,
        gear=gear_counter,
        distance=distance,
        path_length=track.path_length,
        x_ft=xy[:, 0],
        y_ft=xy[:, 1],
    )
