"""FSAE dynamic-event scoring: V4 Section 17 verbatim (2019 Michigan anchors,
team-hardcoded) plus the Phase 3 parameterized Efficiency formula.

Efficiency: the FSAE points formula requires fuel-burn data. Fuel mass is
derived from tractive energy via BSFC, which is a REQUIRED team input with no
default (handover hard rule: no invented numbers). With bsfc_g_per_kwh=None
the Efficiency_Score stays None. Formula citation is a TODO pending retrieval
of the current FSAE Rules document (assumptions: handover/FINDINGS.md, docs/PORT_AND_MATLAB.md §2).
"""

from __future__ import annotations

from dataclasses import dataclass

from .config import ScoreAnchors


@dataclass
class EventScores:
    endurance: float
    autocross: float
    skidpad: float
    accel: float

    @property
    def total(self) -> float:
        return self.endurance + self.autocross + self.skidpad + self.accel


def score_events(endurance_lap_s: float, autocross_s: float, skidpad_s: float,
                 accel_s: float, anchors: ScoreAnchors = ScoreAnchors()) -> EventScores:
    a = anchors
    tmax_e = a.endurance_tmin * a.endurance_tmax_factor
    endurance = 250.0 * ((tmax_e / endurance_lap_s) - 1.0) / (tmax_e / a.endurance_tmin - 1.0) + 25.0

    tmax_a = a.autocross_tmin * a.autocross_tmax_factor
    autocross = 118.5 * ((tmax_a / autocross_s) - 1.0) / (tmax_a / a.autocross_tmin - 1.0) + 6.5

    tmax_s = a.skidpad_tmin * a.skidpad_tmax_factor
    skidpad = 71.5 * ((tmax_s / skidpad_s) ** 2 - 1.0) / ((tmax_s / a.skidpad_tmin) ** 2 - 1.0) + 3.5

    tmax_x = a.accel_tmin * a.accel_tmax_factor
    accel = 95.5 * ((tmax_x / accel_s) - 1.0) / ((tmax_x / a.accel_tmin) - 1.0) + 4.5

    return EventScores(endurance, autocross, skidpad, accel)


# --- Phase 3: FSAE Efficiency score (rules-cited) --------------------------
# Source: Formula SAE(R) Rules 2026, Version 1.0 (10 Sept 2025), retrieved
# 2026-06-12 from fsaeonline.com (DocumentID 278fd4d7-aa27-4e33-bc4a-
# 090148e662a0), Section D.13 "Efficiency Event", pp. 143-145:
#   D.13.4.1  Gasoline/Petrol converts at 2.31 kg CO2 per liter.
#   D.13.4.4  Efficiency Factor =
#               (Tmin/LapTotal_Tmin)/(Tyours/Lap_yours)
#             x (CO2min/LapTotal_CO2min)/(CO2your/Lap_yours)
#   D.13.4.5  EfficiencyFactor_min uses CO2_your equivalent to 60.06 kg
#             CO2/100 km (gasoline 26 l/100 km) and Tyour = 1.45 x Tmin.
#   D.13.4.6  Efficiency Score = 100 x (EffFactor_your - EffFactor_min)
#                                     / (EffFactor_max - EffFactor_min)
#   D.13.3.1  Eligibility: average laptime <= 1.45 x fastest team's.
#
# Tmin, CO2min and EffFactor_max are OUTCOMES of a real competition (they
# depend on the other teams), so they are required anchor inputs here — the
# sim never invents them. Fuel mass derives from TractiveEnergy via BSFC,
# a required team input (no default).

FT_LBF_TO_J = 1.3558179483314004  # NIST: 1 ft·lbf in J
GASOLINE_KG_CO2_PER_LITER = 2.31  # FSAE Rules 2026 D.13.4.1(a)


def fuel_mass_kg(tractive_energy_kj: float, bsfc_g_per_kwh: float | None,
                 drivetrain_efficiency: float = 1.0) -> float | None:
    """Fuel mass from tractive energy via BSFC. Returns None if unconfigured.

    BSFC converts brake (crank) energy to fuel mass. Tractive energy is at the
    wheels; pass drivetrain_efficiency=0.80 (the V4 committed loss factor) to
    convert wheel energy back to crank energy.
    """
    if bsfc_g_per_kwh is None:
        return None
    crank_kwh = (tractive_energy_kj / drivetrain_efficiency) / 3600.0
    return crank_kwh * bsfc_g_per_kwh / 1000.0


def efficiency_factor(t_endurance_s: float, laps_yours: float, co2_kg: float,
                      anchors: dict) -> float:
    """FSAE Rules 2026 D.13.4.4 (see citation block above)."""
    t_term = (anchors["t_min_s"] / anchors["laps_tmin"]) / (t_endurance_s / laps_yours)
    co2_term = (anchors["co2_min_kg"] / anchors["laps_co2min"]) / (co2_kg / laps_yours)
    return t_term * co2_term


def efficiency_score(fuel_kg: float | None, t_endurance_s: float,
                     anchors: dict | None = None,
                     fuel_density_kg_per_l: float | None = None,
                     laps_yours: float = 1.0) -> float | None:
    """FSAE Rules 2026 D.13.4.6. Returns None unless every required input is
    configured (BSFC-derived fuel mass, fuel density with provenance, and the
    competition anchor set t_min_s/laps_tmin/co2_min_kg/laps_co2min/
    eff_factor_max/eff_factor_min). No defaults are invented."""
    if fuel_kg is None or not anchors or fuel_density_kg_per_l is None:
        return None
    co2_kg = (fuel_kg / fuel_density_kg_per_l) * GASOLINE_KG_CO2_PER_LITER
    eff = efficiency_factor(t_endurance_s, laps_yours, co2_kg, anchors)
    return 100.0 * (eff - anchors["eff_factor_min"]) / (
        anchors["eff_factor_max"] - anchors["eff_factor_min"])
