"""Tire models, ported exactly from the MATLAB chain.

Lateral: `Tire Data/MF52_Fy_fcn.m` (Pacejka MF5.2) with coefficients from
`A2356run008_MF52_Fy_12.mat` and scaling globals from `A2356run008_MF52_Fy_GV12.mat`.

Longitudinal: `Hoosier R20 18x6.0-10 10 Psi FX.mat` holds a MATLAB CSAPS
tensor-product spline in **pp-form** (slip x FZ x camber). We evaluate it with
a direct port of MATLAB `fnval`/`ppual` semantics, including nearest-piece
polynomial extrapolation outside the break range. The coefficient memory
layout is verified at load time by checking C1 continuity across interior
breaks (a wrong layout produces discontinuities; see tests/test_tires.py).
"""

from __future__ import annotations

import os

import numpy as np
import scipy.io as sio

from .config import TIRE_DIR

MF52_LAT_MAT = os.path.join(TIRE_DIR, "A2356run008_MF52_Fy_12.mat")
MF52_SCALE_MAT = os.path.join(TIRE_DIR, "A2356run008_MF52_Fy_GV12.mat")
FX_SPLINE_MAT = os.path.join(TIRE_DIR, "Hoosier R20 18x6.0-10 10 Psi FX.mat")


class MF52Fy:
    """Vectorized port of MF52_Fy_fcn.m. Inputs: alpha [deg], Fz [lbf], gamma [deg]."""

    def __init__(self, coeffs: np.ndarray, fz0: float, scales: dict):
        a = np.asarray(coeffs, dtype=float).ravel()
        if a.size != 18:
            raise ValueError(f"expected 18 MF52 coefficients, got {a.size}")
        self.A = a
        self.FZ0 = float(fz0)
        # All committed scaling factors are 1; kept explicit for fidelity.
        self.LFZO = float(scales.get("LFZO", 1))
        self.LCY = float(scales.get("LCY", 1))
        self.LMUY = float(scales.get("LMUY", 1))
        self.LEY = float(scales.get("LEY", 1))
        self.LKY = float(scales.get("LKY", 1))
        self.LHY = float(scales.get("LHY", 1))
        self.LVY = float(scales.get("LVY", 1))
        self.LGAY = float(scales.get("LGAY", 1))

    def __call__(self, alpha_deg, fz_lbf, gamma_deg):
        A = self.A
        ALPHA = np.deg2rad(np.asarray(alpha_deg, dtype=float))
        Fz = np.abs(np.asarray(fz_lbf, dtype=float))
        GAMMA = np.deg2rad(np.asarray(gamma_deg, dtype=float))

        GAMMAy = GAMMA * self.LGAY
        Fz0PR = self.FZ0 * self.LFZO
        DFz = (Fz - Fz0PR) / Fz0PR

        PCy1, PDy1, PDy2, PDy3 = A[0], A[1], A[2], A[3]
        PEy1, PEy2, PEy3, PEy4 = A[4], A[5], A[6], A[7]
        PKy1, PKy2, PKy3 = A[8], A[9], A[10]
        PHy1, PHy2, PHy3 = A[11], A[12], A[13]
        PVy1, PVy2, PVy3, PVy4 = A[14], A[15], A[16], A[17]

        SHy = (PHy1 + PHy2 * DFz) * self.LHY + PHy3 * GAMMAy
        ALPHAy = ALPHA + SHy
        Cy = PCy1 * self.LCY
        MUy = (PDy1 + PDy2 * DFz) * (1.0 - PDy3 * GAMMAy**2) * self.LMUY
        Dy = MUy * Fz
        KY = (
            PKy1
            * self.FZ0
            * np.sin(2.0 * np.arctan(Fz / (PKy2 * self.FZ0 * self.LFZO)))
            * (1.0 - PKy3 * np.abs(GAMMAy))
            * self.LFZO
            * self.LKY
        )
        By = KY / (Cy * Dy)
        Ey = (PEy1 + PEy2 * DFz) * (1.0 - (PEy3 + PEy4 * GAMMAy) * np.sign(ALPHAy)) * self.LEY
        SVy = Fz * ((PVy1 + PVy2 * DFz) * self.LVY + (PVy3 + PVy4 * DFz) * GAMMAy) * self.LMUY
        Fy0 = Dy * np.sin(Cy * np.arctan(By * ALPHAy - Ey * (By * ALPHAy - np.arctan(By * ALPHAy)))) + SVy
        return Fy0


class PPFormTensor:
    """MATLAB tensor-product pp-form spline evaluator (3-variate, scalar-valued).

    Mirrors fnval/ppual: per dimension, locate the piece by the breaks
    (points outside the break range use the first/last piece, i.e. polynomial
    extrapolation with the nearest piece), shift to the piece-local
    coordinate, and run nested Horner over the coefficient cube (MATLAB pp
    coefficients are stored highest power first).

    `layout` selects how each (l_j*k_j) coefficient axis is unpacked:
    "kl" -> (k_j, l_j) [power-major], "lk" -> (l_j, k_j) [piece-major].
    The loader picks the layout that yields a continuous spline.
    """

    def __init__(self, breaks, coefs, order, layout: str = "kl"):
        self.breaks = [np.asarray(b, dtype=float).ravel() for b in breaks]
        self.order = [int(k) for k in np.ravel(order)]
        self.pieces = [len(b) - 1 for b in self.breaks]
        self.layout = layout
        k1, k2, k3 = self.order
        l1, l2, l3 = self.pieces
        c = np.asarray(coefs, dtype=float)
        if c.shape != (l1 * k1, l2 * k2, l3 * k3):
            raise ValueError(f"coef shape {c.shape} != expected {(l1*k1, l2*k2, l3*k3)}")
        if layout == "kl":
            c6 = c.reshape(k1, l1, k2, l2, k3, l3)
            self._c = np.ascontiguousarray(c6.transpose(1, 3, 5, 0, 2, 4))
        elif layout == "lk":
            c6 = c.reshape(l1, k1, l2, k2, l3, k3)
            self._c = np.ascontiguousarray(c6.transpose(0, 2, 4, 1, 3, 5))
        else:
            raise ValueError(layout)
        # final shape: (l1, l2, l3, k1, k2, k3)

    def _locate(self, dim: int, x: np.ndarray):
        b = self.breaks[dim]
        # MATLAB ppual: piece i such that b(i) <= x < b(i+1); outside -> end pieces
        idx = np.searchsorted(b[1:-1], x, side="right")
        return idx, x - b[idx]

    def eval(self, slip, fz, camber):
        q = np.broadcast_arrays(
            np.asarray(slip, dtype=float),
            np.asarray(fz, dtype=float),
            np.asarray(camber, dtype=float),
        )
        shape = q[0].shape
        x1, x2, x3 = (np.atleast_1d(a).ravel() for a in q)
        i1, s1 = self._locate(0, x1)
        i2, s2 = self._locate(1, x2)
        i3, s3 = self._locate(2, x3)
        cube = self._c[i1, i2, i3]  # (n, k1, k2, k3)
        k1, k2, k3 = self.order
        v = cube[:, :, :, 0]
        for m in range(1, k3):
            v = v * s3[:, None, None] + cube[:, :, :, m]
        v2 = v[:, :, 0]
        for m in range(1, k2):
            v2 = v2 * s2[:, None] + v[:, :, m]
        v1 = v2[:, 0]
        for m in range(1, k1):
            v1 = v1 * s1 + v2[:, m]
        return v1.reshape(shape) if shape else float(v1[0])

    def _eval_forced(self, x, pieces_idx):
        """Evaluate one point with explicit piece indices (continuity check)."""
        s = [float(x[d]) - self.breaks[d][pieces_idx[d]] for d in range(3)]
        cube = self._c[pieces_idx[0], pieces_idx[1], pieces_idx[2]]  # (k1,k2,k3)
        k1, k2, k3 = self.order
        v = cube[:, :, 0]
        for m in range(1, k3):
            v = v * s[2] + cube[:, :, m]
        v2 = v[:, 0]
        for m in range(1, k2):
            v2 = v2 * s[1] + v[:, m]
        v1 = v2[0]
        for m in range(1, k1):
            v1 = v1 * s[0] + v2[m]
        return float(v1)

    def max_continuity_jump(self) -> float:
        """Largest relative mismatch between adjacent piece polynomials, both
        evaluated exactly at their shared interior break (layout check; a
        wrong coefficient layout produces O(1) mismatches)."""
        worst = 0.0
        mid_idx = [max(0, p // 2) for p in self.pieces]
        for dim in range(3):
            for j in range(1, self.pieces[dim]):
                br = self.breaks[dim][j]
                pt = [self.breaks[d][mid_idx[d]] for d in range(3)]
                pt[dim] = br
                idx_r = list(mid_idx)
                idx_r[dim] = j
                idx_l = list(mid_idx)
                idx_l[dim] = j - 1
                right = self._eval_forced(pt, idx_r)
                left = self._eval_forced(pt, idx_l)
                scale = max(1.0, abs(left), abs(right))
                worst = max(worst, abs(right - left) / scale)
        return worst


def eval_longitudinal_tire_limit(fx_spline: PPFormTensor, slip_ratios: np.ndarray,
                                 wheel_load_lbf: float, camber_rad: float,
                                 sf_x: float, mode: str) -> float:
    """Port of Aero/evalLongitudinalTireLimit.m (peak force for one tire)."""
    slips = np.asarray(slip_ratios, dtype=float)
    forces = fx_spline.eval(slips, -wheel_load_lbf, np.rad2deg(-camber_rad)) * sf_x
    forces = np.where(np.abs(forces) > 1000.0, np.nan, forces)
    valid = forces[~np.isnan(forces)]
    if valid.size == 0:
        return float("nan")
    return float(valid.min() if mode == "min" else valid.max())


def load_lateral_model() -> MF52Fy:
    lat = sio.loadmat(MF52_LAT_MAT)
    sc = sio.loadmat(MF52_SCALE_MAT)
    scales = {k: float(np.ravel(v)[0]) for k, v in sc.items()
              if not k.startswith("__") and np.size(v) == 1}
    return MF52Fy(lat["A"], scales.pop("FZ0"), scales)


def load_fx_spline() -> PPFormTensor:
    m = sio.loadmat(FX_SPLINE_MAT, squeeze_me=True, struct_as_record=False)
    fs = m["full_send_x"]
    if str(fs.form) != "pp":
        raise ValueError(f"expected pp-form spline, got {fs.form!r}")
    breaks = [np.asarray(b, dtype=float).ravel() for b in fs.breaks]
    coefs = np.asarray(fs.coefs, dtype=float)
    order = np.ravel(fs.order)
    candidates = {lay: PPFormTensor(breaks, coefs, order, lay) for lay in ("kl", "lk")}
    jumps = {lay: sp.max_continuity_jump() for lay, sp in candidates.items()}
    best = min(jumps, key=jumps.get)
    if jumps[best] > 1e-6:
        raise ValueError(f"no continuous pp layout found (jumps: {jumps})")
    return candidates[best]
