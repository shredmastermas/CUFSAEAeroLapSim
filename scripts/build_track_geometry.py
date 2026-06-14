"""Regenerate the dashboard's TRACK0 from the sim's OWN track geometry.

Uses pylapsim.track exactly as the simulator does: reconstruct the racing line
from the gate-position .mat + gate boundaries, then PCHIP-smooth (shape-preserving,
NO overshoot — the lumpy CubicSpline ribbon was the bug). Also emit PCHIP-smoothed
outer/inner cone edges for the road surface. Writes track0.json + a verify PNG.
"""
import json
import os
import sys

import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
JSX = os.path.join(ROOT, "handover/dashboard/t27-aero-dashboard.jsx")

sys.path.insert(0, ".")
from pylapsim.track import (  # noqa: E402
    read_scaled_track_coordinates, build_path_boundaries,
    gate_positions_to_points, _sample_path,
    ENDURANCE_XLSX, AUTOCROSS_XLSX, ENDURANCE_LINE_MAT, AUTOCROSS_LINE_MAT,
)
import scipy.io as sio  # noqa: E402
from scipy.interpolate import PchipInterpolator  # noqa: E402

TW = 47.0 / 12.0  # front track, ft (the gate-shrink width the sim uses)


def pchip_resample(P, n, closed):
    """Arc-length PCHIP resample of a polyline to n points (no overshoot)."""
    P = np.asarray(P, float)
    if closed:
        P = np.vstack([P, P[0]])
    d = np.r_[0.0, np.cumsum(np.hypot(np.diff(P[:, 0]), np.diff(P[:, 1])))]
    if d[-1] == 0:
        return P[:n]
    u = d / d[-1]
    # drop duplicate parameter values (PCHIP needs strictly increasing x)
    keep = np.r_[True, np.diff(u) > 1e-9]
    u, P = u[keep], P[keep]
    fx, fy = PchipInterpolator(u, P[:, 0]), PchipInterpolator(u, P[:, 1])
    uq = np.linspace(0, 1, n)
    return np.column_stack([fx(uq), fy(uq)])


def build(name, xlsx, mat, key, closed):
    data = read_scaled_track_coordinates(xlsx)
    pb = build_path_boundaries(data, TW)
    line = sio.loadmat(mat)[key].ravel()
    if closed:                       # endurance: V4 appends first 2 gates to close
        pos = np.concatenate([line, line[:2]])
    else:
        pos = line[: min(len(line), len(pb))]
    pts = gate_positions_to_points(pos, pb[: len(pos)])
    racing = _sample_path(pts)       # 3000-pt PCHIP driven line (the sim's own)

    outer = data[:, 1:3]
    inner = data[:, 3:5]
    # smooth, evenly-sampled road edges + racing line for the minimap
    outer_s = pchip_resample(outer, 220, closed)
    inner_s = pchip_resample(inner, 220, closed)
    racing_s = pchip_resample(racing, 260, closed)

    rnd = lambda A: [[round(float(x), 1), round(float(y), 1)] for x, y in A]
    return {
        "year": 2019, "closed": closed,
        "outer": rnd(outer_s), "inner": rnd(inner_s), "line": rnd(racing_s),
    }, dict(outer=outer, inner=inner, racing=racing)


def main():
    out = {}
    raw = {}
    out["endurance"], raw["endurance"] = build(
        "endurance", ENDURANCE_XLSX, ENDURANCE_LINE_MAT, "endurance_racing_line", True)
    out["autocross"], raw["autocross"] = build(
        "autocross", AUTOCROSS_XLSX, AUTOCROSS_LINE_MAT, "autocross_racing_line", False)

    json_path = os.path.join(ROOT, "scripts/track0.json")
    with open(json_path, "w") as f:
        json.dump(out, f, separators=(",", ":"))
    print("wrote scripts/track0.json")
    for k, v in out.items():
        print(f"  {k}: closed={v['closed']} outer={len(v['outer'])} inner={len(v['inner'])} line={len(v['line'])}")

    # Splice TRACK0 into the dashboard source (mirrors build_dashboard_data.py).
    blob = "const TRACK0 = " + json.dumps(out, separators=(",", ":")) + ";\n"
    with open(JSX) as f:
        lines = f.readlines()
    spliced = False
    for i, ln in enumerate(lines):
        if ln.startswith("const TRACK0 = "):
            lines[i] = blob
            spliced = True
            break
    assert spliced, "could not find `const TRACK0 = ` line to splice in the jsx"
    with open(JSX, "w") as f:
        f.writelines(lines)
    print("spliced TRACK0 into handover/dashboard/t27-aero-dashboard.jsx")

    # verify PNG
    try:
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
        fig, ax = plt.subplots(1, 2, figsize=(16, 6))
        for i, k in enumerate(["endurance", "autocross"]):
            o = np.array(out[k]["outer"]); inn = np.array(out[k]["inner"]); ln = np.array(out[k]["line"])
            ax[i].fill(np.r_[o[:, 0], inn[::-1, 0]], np.r_[o[:, 1], inn[::-1, 1]], color="#d4d4d4", zorder=1)
            ax[i].plot(o[:, 0], o[:, 1], color="#9a9a9a", lw=0.8)
            ax[i].plot(inn[:, 0], inn[:, 1], color="#9a9a9a", lw=0.8)
            ax[i].plot(ln[:, 0], ln[:, 1], color="#522d80", lw=1.6, zorder=3)
            ax[i].set_aspect("equal"); ax[i].set_title(f"{k} (closed={out[k]['closed']})")
        plt.tight_layout()
        plt.savefig("scripts/track_verify.png", dpi=80)
        print("wrote scripts/track_verify.png")
    except Exception as e:
        print("plot skipped:", e)


if __name__ == "__main__":
    main()
