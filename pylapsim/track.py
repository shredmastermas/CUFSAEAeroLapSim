"""Track loading and geometry: ports of readScaledTrackCoordinates.m, the gate
-> path-boundary construction (V4 Sections 7/12), curvature.m/circumcenter.m
and arclength.m (linear method, the V4 default).
"""

from __future__ import annotations

import os
from dataclasses import dataclass

import numpy as np
import pandas as pd
import scipy.io as sio
from scipy.interpolate import PchipInterpolator

from .config import SIM_DATA_DIR

ENDURANCE_XLSX = os.path.join(SIM_DATA_DIR, "Endurance_Coordinates_1.xlsx")
AUTOCROSS_XLSX = os.path.join(SIM_DATA_DIR, "Autocross_Coordinates_2.xlsx")
ENDURANCE_LINE_MAT = os.path.join(SIM_DATA_DIR, "endurance_racing_line.mat")
AUTOCROSS_LINE_MAT = os.path.join(SIM_DATA_DIR, "autocross_racing_line.mat")


def read_scaled_track_coordinates(filename: str) -> np.ndarray:
    """readScaledTrackCoordinates.m: numeric 'Scaled' sheet, all-NaN rows dropped."""
    df = pd.read_excel(filename, sheet_name="Scaled", header=None)
    data = df.apply(pd.to_numeric, errors="coerce").to_numpy(dtype=float)
    return data[~np.all(np.isnan(data), axis=1)]


def build_path_boundaries(data: np.ndarray, tw_ft: float) -> np.ndarray:
    """V4 Sections 7/12: per-gate [slope, intercept, x_lo, x_hi] after
    shrinking each gate by half a track width on both sides."""
    outside = data[:, 1:3]
    inside = data[:, 3:5]
    n = len(outside)
    pb = np.zeros((n, 4))
    for i in range(n):
        x1, y1 = inside[i]
        x2, y2 = outside[i]
        coeff = np.polyfit([x1, x2], [y1, y2], 1)
        gate_width = float(np.hypot(x2 - x1, y2 - y1))
        x_fs = tw_ft / (2.0 * gate_width)
        x_lo = min(x1, x2) + x_fs * abs(x2 - x1)
        x_hi = max(x1, x2) - x_fs * abs(x2 - x1)
        pb[i] = [coeff[0], coeff[1], x_lo, x_hi]
    return pb


def gate_positions_to_points(path_positions: np.ndarray, pb: np.ndarray) -> np.ndarray:
    """Place the car within each gate by linear interpolation (V4 Section 10)."""
    n = len(path_positions)
    pts = np.zeros((n, 2))
    for i in range(n):
        slope, intercept, b3, b4 = pb[i]
        x2 = max(b3, b4)
        x1 = min(b3, b4)
        x3 = x1 + path_positions[i] * (x2 - x1)
        pts[i] = [x3, slope * x3 + intercept]
    return pts


def circumradius_and_ky(X: np.ndarray):
    """curvature.m port: per-point circumcircle radius R and the y-component
    of the curvature vector k (V4 keeps KT(:,2)). First/last rows are NaN."""
    N = len(X)
    R = np.full(N, np.nan)
    ky = np.full(N, np.nan)
    A = np.column_stack([X[1:-1], np.zeros(N - 2)])
    B = np.column_stack([X[:-2], np.zeros(N - 2)])
    C = np.column_stack([X[2:], np.zeros(N - 2)])
    D = np.cross(B - A, C - A)
    b = np.linalg.norm(A - C, axis=1)
    c = np.linalg.norm(A - B, axis=1)
    E = np.cross(D, B - A)
    F = np.cross(D, C - A)
    normD2 = np.einsum("ij,ij->i", D, D)
    with np.errstate(invalid="ignore", divide="ignore"):
        G = (b[:, None] ** 2 * E - c[:, None] ** 2 * F) / normD2[:, None] / 2.0
        Rv = np.linalg.norm(G, axis=1)
        kv = G / Rv[:, None] ** 2
    R[1:-1] = Rv
    ky[1:-1] = kv[:, 1]
    return R, ky


def arclength_linear(x: np.ndarray, y: np.ndarray) -> float:
    return float(np.sum(np.hypot(np.diff(x), np.diff(y))))


@dataclass
class TrackData:
    """Sampled vehicle path + per-segment geometry for one event."""

    name: str
    seg_radius: np.ndarray  # clamped later by the solver
    seg_ky: np.ndarray  # curvature-vector y component (lateral sign source)
    seg_dist: np.ndarray  # segment lengths, ft
    path_length: float
    seg_p1: np.ndarray  # (n, 2) segment start coordinates, ft
    seg_p2: np.ndarray  # (n, 2) segment end coordinates, ft


def _sample_path(path_points: np.ndarray, sections: int = 3000) -> np.ndarray:
    n = len(path_points)
    t = np.arange(1.0, n + 1)
    pch = PchipInterpolator(t, path_points, axis=0)
    xq = np.linspace(1.0, float(n - 1), sections)
    return pch(xq)  # (sections, 2)


def _segments_from_path(path: np.ndarray):
    """lap_information.m:36-64. track_points prepends column len-2, keeps 1:end-1."""
    tp = np.vstack([path[len(path) - 3], path[:-1]])  # (sections, 2)
    RT, KT = circumradius_and_ky(tp)
    valid = ~np.isnan(RT)
    KT = KT[valid]
    RT = RT[valid]
    n = len(RT)
    # dist(i) = |tp(i+1) - tp(i+2)| in 1-based MATLAB -> tp[i+1]-tp[i+2] 0-based i
    p1 = tp[1 : n + 1]
    p2 = tp[2 : n + 2]
    dist = np.hypot(p1[:, 0] - p2[:, 0], p1[:, 1] - p2[:, 1])
    return RT, KT, dist, p1, p2


def load_endurance(tw_ft: float) -> TrackData:
    data = read_scaled_track_coordinates(ENDURANCE_XLSX)
    pb = build_path_boundaries(data, tw_ft)
    line = sio.loadmat(ENDURANCE_LINE_MAT)["endurance_racing_line"].ravel()
    # V4/lap_information append the first two positions to close the loop;
    # the coordinate file carries matching closure gates (152 = 150 + 2).
    pos = np.concatenate([line, line[:2]])
    if len(pb) < len(pos):
        raise ValueError(
            f"endurance boundaries ({len(pb)}) fewer than positions ({len(pos)})")
    pts = gate_positions_to_points(pos, pb[: len(pos)])
    path = _sample_path(pts)
    RT, KT, dist, p1, p2 = _segments_from_path(path)
    return TrackData("Endurance", RT, KT, dist,
                     arclength_linear(path[:, 0], path[:, 1]), p1, p2)


def load_autocross(tw_ft: float) -> TrackData:
    data = read_scaled_track_coordinates(AUTOCROSS_XLSX)
    pb = build_path_boundaries(data, tw_ft)
    line = sio.loadmat(AUTOCROSS_LINE_MAT)["autocross_racing_line"].ravel()
    n_gates = min(len(line), len(pb))
    pos = line[:n_gates]
    pts = gate_positions_to_points(pos, pb[:n_gates])
    # lap_information_sprint does NOT close the loop (sprint event)
    path = _sample_path(pts)
    RT, KT, dist, p1, p2 = _segments_from_path(path)
    return TrackData("Autocross", RT, KT, dist,
                     arclength_linear(path[:, 0], path[:, 1]), p1, p2)
