"""Airfoil data layer + wing-configuration suggester (Phase 4).

Data (data/airfoils/, provenance in MANIFEST.json):
- Coordinates: UIUC Airfoil Coordinates Database (M. Selig), Selig format.
- Polars: airfoiltools.com XFOIL-computed polars (Ncrit=9), Re 2e5 / 5e5.
  These are computed (XFOIL) data published by airfoiltools.com — cited as
  such, never as wind-tunnel measurements.

Rules box: Formula SAE(R) Rules 2026, Version 1.0 (10 Sept 2025), retrieved
2026-06-12 from fsaeonline.com (DocumentID 278fd4d7-aa27-4e33-bc4a-
090148e662a0), Section T.7 (pp. 70-72):
- T.7.5  Length: <= 700 mm forward of the fronts of the front tires;
         <= 250 mm rearward of the rear of the rear tires.
- T.7.6  Width: forward of front axle, inboard of planes touching the
         OUTSIDE of the front tires at hub height; between axles, inboard of
         the line connecting tire outer surfaces; rearward of the rear axle,
         within the Rear Aerodynamic Zone (inside of the rear tires, T.7.3.3).
- T.7.7  Height: <= 1200 mm above ground in the Rear Aerodynamic Zone;
         <= 500 mm elsewhere; <= 250 mm forward+outboard of the front tires.

Units bridge (handover/FINDINGS.md): the sim's CL_target is a force
coefficient (DF = CL_target * V^2, V ft/s, lbf), so
CL*A [ft^2] = CL_target / (0.5 * rho), rho = 0.002377 slug/ft^3
(standard sea-level density; cited wherever these numbers appear).
"""

from __future__ import annotations

import json
import os
from dataclasses import dataclass

import numpy as np
import pandas as pd

AIRFOIL_DIR = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", "data", "airfoils"))

RHO_SLUG_FT3 = 0.002377  # standard sea-level air density
FT2_TO_M2 = 0.09290304
MPH_TO_FPS = 5280.0 / 3600.0

# FSAE Rules 2026 T.7 dimensional limits (mm), cited above
RULES_BOX = {
    "front_overhang_max_mm": 700.0,  # T.7.5(a)
    "rear_overhang_max_mm": 250.0,  # T.7.5(b)
    "height_rear_zone_max_mm": 1200.0,  # T.7.7.1(a)
    "height_elsewhere_max_mm": 500.0,  # T.7.7.1(b)
    "height_front_outboard_max_mm": 250.0,  # T.7.7.1(c)
    "citation": "FSAE Rules 2026 V1.0, T.7.5-T.7.7 (fsaeonline.com, retrieved 2026-06-12)",
}

AIRFOILS = {
    "S1223": {"coord": "s1223.dat", "polar": "xf-s1223-il-{re}.csv"},
    "E423": {"coord": "e423.dat", "polar": "xf-e423-il-{re}.csv"},
    "CH10": {"coord": "ch10sm.dat", "polar": "xf-ch10sm-il-{re}.csv"},
    "S1210": {"coord": "s1210.dat", "polar": "xf-s1210-il-{re}.csv"},
    "FX74-CL5-140": {"coord": "fx74cl5140.dat", "polar": "xf-fx74cl5140-il-{re}.csv"},
}
REYNOLDS = (200000, 500000)


def load_manifest() -> dict:
    with open(os.path.join(AIRFOIL_DIR, "MANIFEST.json")) as f:
        return json.load(f)


def load_coordinates(name: str) -> np.ndarray:
    """Selig-format .dat: title line, then x z pairs (upper TE -> LE -> lower TE)."""
    fn = AIRFOIL_DIR + "/" + AIRFOILS[name]["coord"]
    pts = []
    with open(fn) as f:
        lines = f.read().strip().splitlines()
    for line in lines[1:]:
        parts = line.split()
        if len(parts) >= 2:
            try:
                pts.append((float(parts[0]), float(parts[1])))
            except ValueError:
                continue
    arr = np.asarray(pts)
    if not (len(arr) > 20 and arr[:, 0].max() <= 1.01 and arr[:, 0].min() >= -0.01):
        raise ValueError(f"{fn}: does not look like normalized airfoil coordinates")
    return arr


def load_polar(name: str, re: int) -> pd.DataFrame:
    """airfoiltools.com CSV polar -> DataFrame with Alpha, Cl, Cd, Cdp, Cm columns."""
    fn = AIRFOIL_DIR + "/" + AIRFOILS[name]["polar"].format(re=re)
    with open(fn) as f:
        lines = f.read().splitlines()
    header_idx = next(i for i, ln in enumerate(lines) if ln.startswith("Alpha,"))
    df = pd.read_csv(fn, skiprows=header_idx)
    df = df.apply(pd.to_numeric, errors="coerce").dropna(subset=["Alpha", "Cl", "Cd"])
    return df


@dataclass
class PolarSummary:
    name: str
    re: int
    cl_max: float
    alpha_clmax_deg: float
    cd_at_clmax: float
    ld_max: float
    source_url: str


def polar_summary(name: str, re: int) -> PolarSummary:
    df = load_polar(name, re)
    i = int(df.Cl.idxmax())
    manifest = load_manifest()
    fn = AIRFOIL_DIR.split("/")[-1]
    url = manifest["files"][AIRFOILS[name]["polar"].format(re=re)]["url"]
    return PolarSummary(
        name=name, re=re,
        cl_max=float(df.Cl.max()),
        alpha_clmax_deg=float(df.Alpha.loc[i]),
        cd_at_clmax=float(df.Cd.loc[i]),
        ld_max=float((df.Cl / df.Cd).max()),
        source_url=url,
    )


def cla_from_cl_target(cl_target: float) -> tuple[float, float]:
    """(CL*A in ft^2, m^2) from a sim force coefficient. rho cited above."""
    cla_ft2 = cl_target / (0.5 * RHO_SLUG_FT3)
    return cla_ft2, cla_ft2 * FT2_TO_M2


def suggest_wings(cl_target: float, cd_target: float, cop_target: float,
                  ref_speed_mph: float = 35.0,
                  achieved_fractions=(0.7, 0.8, 0.9)) -> pd.DataFrame:
    """Map a sim aero target to per-wing CL*A demand and candidate airfoils.

    The front/rear split applies CoP_target directly (forces at the axles —
    the same approximation the lap sim makes). `achieved_fractions` expresses
    the achieved 3D wing CL as a fraction of the published 2D cl_max; it is an
    UNSOURCED sensitivity parameter, surfaced as a labeled column, because no
    cited 2D->3D knockdown for FSAE wing geometries is available in-repo.
    Every row carries the polar's source URL.
    """
    ref_fps = ref_speed_mph * MPH_TO_FPS
    cla_ft2, cla_m2 = cla_from_cl_target(cl_target)
    rows = []
    for wing, share in (("Front", cop_target), ("Rear", 1.0 - cop_target)):
        cla_wing_ft2 = cla_ft2 * share
        for name in AIRFOILS:
            for re in REYNOLDS:
                ps = polar_summary(name, re)
                for f in achieved_fractions:
                    area_ft2 = cla_wing_ft2 / (f * ps.cl_max)
                    rows.append({
                        "Wing": wing,
                        "DF_share": share,
                        "DF_at_ref_lbf": cl_target * ref_fps**2 * share,
                        "CLA_required_ft2": cla_wing_ft2,
                        "CLA_required_m2": cla_wing_ft2 * FT2_TO_M2,
                        "Airfoil": name,
                        "Re": re,
                        "cl_max_2D": ps.cl_max,
                        "alpha_at_clmax_deg": ps.alpha_clmax_deg,
                        "cd_at_clmax_2D": ps.cd_at_clmax,
                        "achieved_CL_fraction (unsourced sensitivity)": f,
                        "wing_area_required_ft2": area_ft2,
                        "wing_area_required_m2": area_ft2 * FT2_TO_M2,
                        "polar_source": ps.source_url,
                        "rules_box": RULES_BOX["citation"],
                        "rho_assumption": f"rho={RHO_SLUG_FT3} slug/ft^3 (std sea level)",
                    })
    return pd.DataFrame(rows)
