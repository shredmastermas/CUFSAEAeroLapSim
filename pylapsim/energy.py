"""Phase 3 energy accounting (assumption-free, from solved speed profiles).

DragEnergy     = sum(CD * V^2 * dd)            [ft*lbf -> kJ]
TractiveEnergy = sum(max(F_tractive, 0) * dd)  [ft*lbf -> kJ]

F_tractive is the longitudinal force the wheels must produce:
m*ax + drag = W/g * (ax_g * g) + CD*V^2 = W*ax_g + CD*V^2 (lbf), floored at 0.
"""

from __future__ import annotations

import numpy as np

from .lapsolver import LapResult

FT_LBF_TO_KJ = 1.3558179483314004e-3


def drag_energy_kj(lap: LapResult, cd: float) -> float:
    dd = np.diff(lap.distance, prepend=0.0)
    return float(np.sum(cd * lap.velocity**2 * dd) * FT_LBF_TO_KJ)


def tractive_energy_kj(lap: LapResult, cd: float, weight_lbf: float) -> float:
    dd = np.diff(lap.distance, prepend=0.0)
    f_tractive = weight_lbf * lap.acceleration + cd * lap.velocity**2
    return float(np.sum(np.maximum(f_tractive, 0.0) * dd) * FT_LBF_TO_KJ)
