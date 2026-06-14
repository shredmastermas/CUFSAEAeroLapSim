"""GGV envelope generation: port of V4 Sections 5-6 + lat_solve/lat_objective/
cAlpha_nonlcon.

Legacy/corrected physics switch (handover/FINDINGS.md F1):
- legacy accel loop:  axle transfer base `WF - Ax*cg*(W/2)/l/24` (~1/48 physical)
- legacy brake loop:  per-wheel `+ Ax*cg*(W/2)/l/24` applied twice (~1/24 physical)
- corrected accel:    full-axle `WF - Ax*W*cg/l`, halved to per-wheel with DF
- corrected brake:    per-wheel `+ Ax*cg*(W/2)/l` applied once

Cornering solve: V4 uses fmincon on a weighted residual objective with an
on-center cornering-stiffness inequality. The envelope output depends only on
the accept/reject decision per (R, V) — V4 records lateral g from V (and the
stepped-back V on failure) regardless of the final solve, so we use a fast
Newton root solve and fall back to SLSQP (constrained, bounded) only when the
root is out of bounds, violates the constraint, or fails to converge.
Acceptance replicates V4: solver converged AND |normalized residuals| <= 1e-2.
"""

from __future__ import annotations

import math
from dataclasses import dataclass

import numpy as np
from csaps import CubicSmoothingSpline
from scipy.optimize import minimize, root

from .config import GRAVITY, AeroTarget, Resolution, SimConfig, VehicleConfig
from .powertrain import Powertrain
from .tires import MF52Fy, PPFormTensor

SLIP_ACCEL = np.arange(0.0, 0.1101, 0.01)  # V4: 0:.01:.11
SLIP_BRAKE = np.arange(-0.15, 0.0001, 0.01)  # V4: -.15:.01:0
DELTA_BOUNDS = (math.radians(-20.0), math.radians(25.0))
BETA_BOUNDS = (math.radians(-10.0), math.radians(10.0))
RES_TOL = 1e-2  # V4 'tol'


class FastPP:
    """Fast scalar/vector evaluation of a scipy PPoly (cubic), with MATLAB
    fnval-style nearest-piece extrapolation (PPoly extrapolate=True matches)."""

    def __init__(self, pp):
        self.x = pp.x
        self.c = pp.c  # (k, n_pieces)
        self.k = pp.c.shape[0]

    def __call__(self, v):
        x = self.x
        scalar = np.isscalar(v)
        vv = np.asarray(v, dtype=float)
        idx = np.clip(np.searchsorted(x, vv, side="right") - 1, 0, len(x) - 2)
        s = vv - x[idx]
        out = self.c[0, idx]
        for m in range(1, self.k):
            out = out * s + self.c[m, idx]
        return float(out) if scalar else out


class Fnxtr2:
    """MATLAB fnxtr(sp, 2): linear (order-2) extension outside the basic
    interval, value+slope continuous at the ends."""

    def __init__(self, pp):
        self.inner = FastPP(pp)
        self.a = float(pp.x[0])
        self.b = float(pp.x[-1])
        self.fa = float(pp(self.a))
        self.fb = float(pp(self.b))
        d = pp.derivative()
        self.da = float(d(self.a))
        self.db = float(d(self.b))

    def __call__(self, v):
        scalar = np.isscalar(v)
        x = np.asarray(v, dtype=float)
        out = self.inner(np.clip(x, self.a, self.b))
        out = np.where(x < self.a, self.fa + self.da * (x - self.a), out)
        out = np.where(x > self.b, self.fb + self.db * (x - self.b), out)
        return float(out) if scalar else out


def _csaps(x, y, smooth=None):
    return CubicSmoothingSpline(np.asarray(x, float), np.asarray(y, float), smooth=smooth).spline


def _tire_limit_rows(fx: PPFormTensor, slips: np.ndarray, loads: np.ndarray,
                     sf_x: float, mode: str) -> np.ndarray:
    """Vectorized evalLongitudinalTireLimit over an array of wheel loads
    (camber 0 throughout V4's envelopes)."""
    forces = fx.eval(slips[None, :], -loads[:, None], 0.0) * sf_x
    forces = np.where(np.abs(forces) > 1000.0, np.nan, forces)
    with np.errstate(all="ignore"):
        out = np.nanmin(forces, axis=1) if mode == "min" else np.nanmax(forces, axis=1)
    return out


@dataclass
class GGV:
    accel: FastPP  # Ax capacity vs V (power+grip limited), g
    grip: FastPP  # Ax tire-limited capacity vs V, g
    deccel: FastPP  # braking capacity vs V, g
    lateral: FastPP  # lateral g vs V
    cornering: Fnxtr2  # max V vs radius
    shift_points: np.ndarray  # ft/s, [0, v_shift..., VMAX+1]
    shift_time: float  # s
    top_speed: float  # ft/s (= VMAX)
    r_min: float
    r_max: float
    lat_radii: np.ndarray  # diagnostics: recorded envelope (radius, V, ok)
    lat_speeds: np.ndarray
    lat_ok: np.ndarray
    ay_cap_116: float  # fnval(lateral, 116) cap used by the lap solver


def _accel_envelope(cfg: SimConfig, veh: VehicleConfig, pt: Powertrain,
                    fx: PPFormTensor, velocity: np.ndarray):
    W, WF, WR = veh.weight_lbf, veh.wf_lbf, veh.wr_lbf
    cg, l = veh.cg_ft, veh.wheelbase_ft
    aero = cfg.aero
    n = len(velocity)
    DF = aero.cl * velocity**2
    DFf = DF * aero.cop
    DFr = DF * (1 - aero.cop)

    # Fixed-point marching, vectorized across velocities (lockstep with V4's
    # serial `Ax += 0.01` walk; identical iterates per velocity).
    Ax = np.zeros(n)
    wr0 = (WR + DFr) / 2.0
    FXR = _tire_limit_rows(fx, SLIP_ACCEL, wr0, veh.sf_x, "max")
    ax_limit = np.abs(2.0 * FXR) / W
    active = (ax_limit - Ax) > 0
    while np.any(active):
        Ax[active] += 0.01
        if cfg.legacy_compat:
            wr_axle = WR + Ax[active] * cg * (W / 2.0) / l / 24.0
        else:
            wr_axle = WR + Ax[active] * W * cg / l
        wr = (wr_axle + DFr[active]) / 2.0
        FXR = _tire_limit_rows(fx, SLIP_ACCEL, wr, veh.sf_x, "max")
        ax_limit[active] = np.abs(2.0 * FXR) / W
        # inactive entries keep Ax and ax_limit fixed, so they stay inactive
        active = (ax_limit - Ax) > 0
    a_xr = ax_limit.copy()  # tire-limited (grip)

    a_Xr = np.empty(n)
    gear_sel = np.empty(n, dtype=int)
    g = 1
    shift_points = [0.0]
    for i, V in enumerate(velocity):
        gp = g
        fxN, _ = pt.wheel_force_and_gear(max(7.5, V / 3.28))
        FXp = fxN * 0.2248 - aero.cd * V**2
        a_Xr[i] = min(FXp / W, a_xr[i])
        _, g = pt.wheel_force_and_gear(V / 3.28)
        gear_sel[i] = g
        if g > gp:
            shift_points.append(float(V))
    a_Xr = np.where(a_Xr < 0, 0.0, a_Xr)
    return a_xr, a_Xr, shift_points


def _brake_envelope(cfg: SimConfig, veh: VehicleConfig, fx: PPFormTensor,
                    velocity: np.ndarray):
    W, WF, WR = veh.weight_lbf, veh.wf_lbf, veh.wr_lbf
    cg, l = veh.cg_ft, veh.wheelbase_ft
    WS = W / 2.0
    aero = cfg.aero
    n = len(velocity)
    DF = aero.cl * velocity**2
    DFf = DF * aero.cop
    DFr = DF * (1 - aero.cop)

    Ax = np.ones(n)
    wf = (WF + DFf) / 2.0 + Ax * cg * WS / l  # seed: per-wheel-correct (V4:654)
    wr = (WR + DFr) / 2.0 - Ax * cg * WS / l
    FXF = _tire_limit_rows(fx, SLIP_BRAKE, wf, veh.sf_x, "min")
    FXR = _tire_limit_rows(fx, SLIP_BRAKE, wr, veh.sf_x, "min")
    ax_limit = np.abs(2 * FXF + 2 * FXR) / W
    active = (ax_limit - Ax) > 0
    while np.any(active):
        Ax[active] += 0.01
        if cfg.legacy_compat:
            transfer = Ax[active] * cg * WS / l / 24.0 * 2.0  # /24 applied twice
        else:
            transfer = Ax[active] * cg * WS / l
        wf = (WF + DFf[active]) / 2.0 + transfer
        wr = (WR + DFr[active]) / 2.0 - transfer
        FXF = _tire_limit_rows(fx, SLIP_BRAKE, wf, veh.sf_x, "min")
        FXR = _tire_limit_rows(fx, SLIP_BRAKE, wr, veh.sf_x, "min")
        ax_limit[active] = np.abs(2 * FXF + 2 * FXR) / W
        active = (ax_limit - Ax) > 0
    return ax_limit


class _LatProblem:
    """Shared state for one (R, V) cornering solve (lat_solve.m equations)."""

    def __init__(self, veh: VehicleConfig, aero: AeroTarget, mf: MF52Fy, grip: FastPP):
        self.veh = veh
        self.aero = aero
        self.mf = mf
        self.grip = grip
        v = veh
        self.a = v.wheelbase_ft * (1 - v.wdf)
        self.b = v.wheelbase_ft * v.wdf
        self.mz_scale = (v.weight_lbf * v.wdf) * self.a
        self.tw_mean = 0.5 * (v.twf_ft + v.twr_ft)

    def set_speed(self, V: float, R: float):
        self.V = V
        self.R = R
        v, aero = self.veh, self.aero
        DF = aero.cl * V * V
        self.wf = (v.wf_lbf + DF * aero.cop) / 2.0
        self.wr = (v.wr_lbf + DF * (1 - aero.cop)) / 2.0
        self.A_y = V * V / R
        WT = self.A_y * v.cg_ft * v.weight_lbf / self.tw_mean / GRAVITY
        self.wfin = self.wf - WT * v.lltd
        self.wfout = self.wf + WT * v.lltd
        self.wrin = self.wr - WT * (1 - v.lltd)
        self.wrout = self.wr + WT * (1 - v.lltd)
        self.drag = aero.cd * V * V
        self.grip_v = max(float(self.grip(V)), np.finfo(float).eps)

    def residuals(self, x):
        """Returns (res1, res2) normalized as V4 does, plus internals."""
        delta, beta = float(x[0]), float(x[1])
        v = self.veh
        r = self.A_y / self.V
        a_f = beta + self.a * r / self.V - delta
        a_r = beta - self.b * r / self.V
        afd = math.degrees(a_f)
        ard = math.degrees(a_r)
        mfv = self.mf(np.array([-afd, afd]), np.array([self.wfin, self.wfout]), 0.0)
        cosd = math.cos(delta)
        F_fin = -float(mfv[0]) * v.sf_y * cosd
        F_fout = float(mfv[1]) * v.sf_y * cosd
        F_x = self.drag + (F_fin + F_fout) * math.sin(delta) / cosd
        rscale = max(0.0, 1.0 - (F_x / v.weight_lbf / self.grip_v) ** 2)
        mrv = self.mf(np.array([-ard, ard]), np.array([self.wrin, self.wrout]), 0.0)
        F_rin = -float(mrv[0]) * v.sf_y * rscale
        F_rout = float(mrv[1]) * v.sf_y * rscale
        F_y = F_fin + F_fout + F_rin + F_rout - v.weight_lbf * self.A_y / GRAVITY
        M_z = (F_fin + F_fout) * self.a - (F_rin + F_rout) * self.b \
            - F_x * v.t_lock * v.twr_ft / 2.0
        res1 = F_y / v.weight_lbf
        res2 = M_z / self.mz_scale
        return res1, res2, ard, rscale

    def constraint(self, x):
        """cAlpha_nonlcon: C_ar - nCa*C_ar0 (must be <= 0)."""
        _, _, ard, rscale = self.residuals(x)
        v = self.veh
        dA = 0.05
        alphas = np.array([ard - dA, ard - dA, ard + dA, ard + dA, -dA, -dA, dA, dA])
        loads = np.array([self.wrout, self.wrin, self.wrout, self.wrin] * 2)
        fy = self.mf(alphas, loads, 0.0) * v.sf_y * rscale
        c_ar = ((fy[2] + fy[3]) - (fy[0] + fy[1])) / (2 * dA)
        c_ar0 = ((fy[6] + fy[7]) - (fy[4] + fy[5])) / (2 * dA)
        return c_ar - v.n_ca * c_ar0


def _solve_lateral(prob: _LatProblem, x_prev: np.ndarray) -> tuple[np.ndarray, bool]:
    """One (R, V) solve. Returns (x, accepted) with V4 acceptance semantics."""

    def res_vec(x):
        r1, r2, _, _ = prob.residuals(x)
        return np.array([r1, r2])

    lb = np.array([DELTA_BOUNDS[0], BETA_BOUNDS[0]])
    ub = np.array([DELTA_BOUNDS[1], BETA_BOUNDS[1]])

    # Fast path: Newton/hybrid root of the residual system.
    sol = root(res_vec, x_prev, method="hybr", options={"xtol": 1e-10})
    if sol.success:
        x = sol.x
        r = res_vec(x)
        if (np.all(x >= lb - 1e-12) and np.all(x <= ub + 1e-12)
                and np.all(np.abs(r) <= RES_TOL)
                and prob.constraint(x) <= 0.0):
            return x, True

    # Faithful path: bounded, constrained minimization like fmincon.
    def obj(x):
        r1, r2, _, _ = prob.residuals(x)
        return (r1 * r1 + r2 * r2
                + 0.1 * (x[0] - x_prev[0]) ** 2
                + 0.05 * (x[1] - x_prev[1]) ** 2)

    cons = [{"type": "ineq", "fun": lambda x: -prob.constraint(x)}]
    res = minimize(obj, np.clip(x_prev, lb, ub), method="SLSQP",
                   bounds=list(zip(lb, ub)), constraints=cons,
                   options={"maxiter": 60, "ftol": 1e-10})
    x = res.x
    r = res_vec(x)
    ok = bool(res.success) and bool(np.all(np.abs(r) <= RES_TOL))
    return x, ok


def _cornering_envelope(cfg: SimConfig, veh: VehicleConfig, mf: MF52Fy,
                        grip: FastPP, radii: np.ndarray, step: float):
    prob = _LatProblem(veh, cfg.aero, mf, grip)
    n = len(radii)
    speeds = np.full(n, np.nan)
    latg = np.full(n, np.nan)
    ok_flags = np.zeros(n, dtype=bool)
    v_guess = 1.0
    x_prev = np.array([0.0, 0.0])
    l = veh.wheelbase_ft
    for t, R in enumerate(radii):
        V = v_guess
        x_prev = np.array([math.atan(l / R), x_prev[1]])
        while True:
            prob.set_speed(V, R)
            x, ok = _solve_lateral(prob, x_prev)
            if ok and V < 250.0:  # hard cap guards a runaway continuation
                x_prev = x
                V += step
                continue
            # step back, final solve, record regardless (FINDINGS F7)
            V -= step
            prob.set_speed(V, R)
            x, ok2 = _solve_lateral(prob, x_prev)
            AY = V * V / R
            speeds[t] = V
            latg[t] = AY / GRAVITY
            ok_flags[t] = ok2
            break
        v_guess = V
    return speeds, latg, ok_flags


def build_ggv(cfg: SimConfig, mf: MF52Fy, fx: PPFormTensor,
              pt: Powertrain | None = None) -> GGV:
    veh = cfg.resolved_vehicle()
    if pt is None:
        pt = Powertrain(veh)
    res = cfg.resolution
    vmax = float(pt.vmax_fts)
    velocity = np.arange(0.0, vmax + 1e-9, res.velocity_step)
    if velocity[-1] != vmax:
        velocity = np.append(velocity, vmax)
    radii = np.arange(15.0, 155.0 + 1e-9, res.radii_step)

    a_xr, a_Xr, shift_points = _accel_envelope(cfg, veh, pt, fx, velocity)
    accel_pp = _csaps(velocity, a_Xr)
    grip_pp = _csaps(velocity, a_xr)
    grip_fast = FastPP(grip_pp)

    lat_speeds, lat_g, lat_ok = _cornering_envelope(
        cfg, veh, mf, grip_fast, radii, res.lateral_step)

    brake_ax = _brake_envelope(cfg, veh, fx, velocity)

    # V4:697-716 envelope cleanup before spline fits
    velocity_y = np.sqrt(np.maximum(lat_g * GRAVITY * radii, 0.0))
    valid = np.isfinite(velocity_y) & np.isfinite(lat_g) & (velocity_y > 0) & (lat_g > 0)
    if valid.sum() < 3:
        raise RuntimeError("Cornering envelope did not produce enough valid points.")
    vy = velocity_y[valid]
    lg = lat_g[valid]
    order = np.argsort(vy, kind="stable")
    vy, lg = vy[order], lg[order]
    keep = np.concatenate([[True], np.diff(vy) != 0])
    vy, lg = vy[keep], lg[keep]
    radii_fit = vy**2 / lg / GRAVITY
    order = np.argsort(radii_fit, kind="stable")
    radii_fit_s = radii_fit[order]
    vy_byr = vy[order]
    keep = np.concatenate([[True], np.diff(radii_fit_s) != 0])
    radii_fit_s, vy_byr = radii_fit_s[keep], vy_byr[keep]

    deccel_pp = _csaps(velocity, brake_ax)
    lateral_pp = _csaps(vy, lg)
    cornering = Fnxtr2(_csaps(radii_fit_s, vy_byr, smooth=0.99999))

    shift_points = list(shift_points)
    shift_points.append(float(velocity[-1]) + 1.0)  # V4:731-732
    top_speed = float(velocity[-1])

    tw = veh.tw_ft
    r_min = 4.5 * 3.28 - tw / 2.0
    r_max = float(np.max(radii_fit_s))

    lateral_fast = FastPP(lateral_pp)
    return GGV(
        accel=FastPP(accel_pp),
        grip=grip_fast,
        deccel=FastPP(deccel_pp),
        lateral=lateral_fast,
        cornering=cornering,
        shift_points=np.asarray(shift_points, dtype=float),
        shift_time=veh.shift_time_s,
        top_speed=top_speed,
        r_min=r_min,
        r_max=r_max,
        lat_radii=radii,
        lat_speeds=lat_speeds,
        lat_ok=lat_ok,
        ay_cap_116=float(lateral_fast(116.0)),
    )
