"""Configuration objects for pylapsim.

Every constant here traces to `Lap Sim March 2026/Aero/Lap_Sim_constantAero_T27V4.m`
(commit e5fd7e2) unless noted. Values are NOT to be edited casually: Gate A
regression tests compare against MATLAB outputs generated with exactly these.
"""

from __future__ import annotations

import os
from dataclasses import dataclass, field, asdict

# Repo-relative data locations (paths contain spaces by team convention).
LAPSIM_ROOT = os.path.normpath(
    os.path.join(os.path.dirname(__file__), "..", "Lap Sim March 2026")
)
TIRE_DIR = os.path.join(LAPSIM_ROOT, "Tire Data")
SIM_DATA_DIR = os.path.join(LAPSIM_ROOT, "Sim Data")
TEST_RESULTS_DIR = os.path.join(LAPSIM_ROOT, "Test Results")
PYTHON_RESULTS_DIR = os.path.join(TEST_RESULTS_DIR, "python")

GRAVITY = 32.2  # ft/s^2, as used throughout V4


@dataclass(frozen=True)
class AeroTarget:
    """Force-coefficient targets: DF = cl*V^2, drag = cd*V^2 (V ft/s, lbf)."""

    cl: float = 0.040
    cd: float = 0.020
    cop: float = 0.450  # front downforce fraction

    @property
    def tag(self) -> str:
        return f"CL_{self.cl:0.3f}_CD_{self.cd:0.3f}_CoP_{self.cop:0.3f}"


@dataclass(frozen=True)
class Resolution:
    """Sweep resolution presets (resolveT27ResolutionPreset.m)."""

    name: str
    velocity_step: float  # ft/s, accel/brake envelope grid
    radii_step: float  # ft, cornering envelope grid
    lateral_step: float  # ft/s, cornering V-continuation step


HIGH = Resolution("High", 1.0, 5.0, 0.10)  # AccurateRerun preset
MEDIUM = Resolution("Medium", 2.0, 10.0, 0.25)  # Fast sweep preset
LOW = Resolution("Low", 3.0, 15.0, 0.50)

PRESETS = {"High": HIGH, "Medium": MEDIUM, "Low": LOW}


@dataclass(frozen=True)
class VehicleConfig:
    """V4 Sections 1-4 vehicle architecture (committed values)."""

    weight_lbf: float = 450.0 + 130.0  # vehicle + driver (W)
    wdf: float = 0.474  # front weight fraction
    cg_ft: float = 12.2 / 12.0  # CG height
    wheelbase_ft: float = 60.5 / 12.0  # l
    lltd: float = 0.38  # front lateral load transfer distribution
    twf_ft: float = 47.0 / 12.0  # front track
    twr_ft: float = 46.0 / 12.0  # rear track
    rg_f: float = 0.5  # roll gradients (deg/g)
    rg_r: float = 0.5
    pg: float = 0.5  # pitch gradient (deg/g)
    sf_x: float = 0.45  # longitudinal tire scaling (V4 calibration)
    sf_y: float = 0.50  # lateral tire scaling
    t_lock: float = 0.80  # diff locking fraction (T_lock/100)
    n_ca: float = 0.1  # on-center cornering stiffness constraint coefficient
    tire_radius_ft: float = 8.05 / 12.0

    # Powertrain (V4 Section 2)
    redline: float = 15000.0
    primary_reduction: float = 76.0 / 36.0
    gear_ratios: tuple = (33 / 12, 32 / 16, 30 / 18, 26 / 18, 30 / 23, 29 / 24)
    final_drive: float = 32.0 / 12.0
    drivetrain_losses: float = 0.80
    shift_time_s: float = 0.075

    @property
    def wf_lbf(self) -> float:
        return self.weight_lbf * self.wdf

    @property
    def wr_lbf(self) -> float:
        return self.weight_lbf * (1.0 - self.wdf)

    @property
    def a_ft(self) -> float:  # front axle to CG
        return self.wheelbase_ft * (1.0 - self.wdf)

    @property
    def b_ft(self) -> float:  # rear axle to CG
        return self.wheelbase_ft * self.wdf

    @property
    def tw_ft(self) -> float:  # 'tw' alias used for gates/skidpad (= twf)
        return self.twf_ft


# 2019 Michigan score anchors, V4 Section 17 verbatim (hardcoded by the team).
@dataclass(frozen=True)
class ScoreAnchors:
    endurance_tmin: float = 115.249
    endurance_tmax_factor: float = 1.45
    autocross_tmin: float = 48.799
    autocross_tmax_factor: float = 1.45
    skidpad_tmin: float = 4.865
    skidpad_tmax_factor: float = 1.45
    accel_tmin: float = 4.109
    accel_tmax_factor: float = 1.5


@dataclass
class SimConfig:
    """Full run configuration."""

    aero: AeroTarget = field(default_factory=AeroTarget)
    vehicle: VehicleConfig = field(default_factory=VehicleConfig)
    resolution: Resolution = field(default_factory=lambda: HIGH)
    anchors: ScoreAnchors = field(default_factory=ScoreAnchors)
    # True reproduces V4-as-committed physics including the F1 /24 bug and the
    # braking double-application, because the regression oracle was generated
    # with the bug. False = corrected physics (handover/FINDINGS.md F1).
    legacy_compat: bool = True
    # Phase 3 scenario knobs (assumptions in docs/PORT_AND_MATLAB.md §2)
    mass_scenario: str = "baseline"  # label only
    extra_mass_lbf: float = 0.0  # added to weight before solving
    bsfc_g_per_kwh: float | None = None  # required for Efficiency_Score; no default

    def resolved_vehicle(self) -> VehicleConfig:
        if self.extra_mass_lbf == 0.0:
            return self.vehicle
        d = asdict(self.vehicle)
        d["weight_lbf"] = self.vehicle.weight_lbf + self.extra_mass_lbf
        d["gear_ratios"] = tuple(d["gear_ratios"])
        return VehicleConfig(**d)

    def snapshot(self) -> dict:
        return {
            "aero": asdict(self.aero),
            "vehicle": asdict(self.resolved_vehicle()),
            "resolution": asdict(self.resolution),
            "anchors": asdict(self.anchors),
            "legacy_compat": self.legacy_compat,
            "mass_scenario": self.mass_scenario,
            "extra_mass_lbf": self.extra_mass_lbf,
            "bsfc_g_per_kwh": self.bsfc_g_per_kwh,
        }
