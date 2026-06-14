"""Gate A regression tests — MATLAB-parity validation gate.

Validation targets are the committed MATLAB artifacts. The autocross event is
asserted as a STRICT xfail: the committed autocross oracle was generated from
geometry whose source data is not in the repo (full evidence chain in
docs/VALIDATION.md §3), so the committed inputs cannot reproduce it. If the
xfail ever starts passing, the data inconsistency has been resolved and the
caveat must be removed.
"""

import os

import numpy as np
import pandas as pd
import pytest

from pylapsim.config import TEST_RESULTS_DIR
from pylapsim.simulate import validation_summary_row

REF_SUMMARY = os.path.join(
    TEST_RESULTS_DIR, "T27_validation_summary_CL_0_040_CD_0_020_CoP_0_450.csv")
REF_TRACE = os.path.join(
    TEST_RESULTS_DIR, "T27_validation_trace_CL_0_040_CD_0_020_CoP_0_450.csv")
REF_WORKBOOK = os.path.join(TEST_RESULTS_DIR, "T27_AeroSweep_Multithreaded_Results.xlsx")


@pytest.fixture(scope="module")
def ref():
    return pd.read_csv(REF_SUMMARY).iloc[0]


@pytest.fixture(scope="module")
def row(validation_case):
    return validation_summary_row(validation_case)


def _pct(a, b):
    return 100.0 * (a - b) / abs(b)


@pytest.mark.parametrize("kpi,band_pct", [
    ("Endurance_Lap_Time", 1.5),
    ("Skidpad_Time", 1.5),
    ("Accel_Time", 1.5),
    ("Endurance_Max_Speed", 1.5),
    ("Max_Abs_AY", 4.0),
    ("Max_AX", 6.0),
    ("Min_AX", 6.0),
])
def test_validation_kpis(row, ref, kpi, band_pct):
    assert abs(_pct(row[kpi], ref[kpi])) <= band_pct


@pytest.mark.xfail(strict=True,
                   reason="committed autocross oracle geometry is not "
                          "reproducible from committed inputs (VALIDATION.md §3)")
def test_validation_autocross_time(row, ref):
    assert abs(_pct(row["Autocross_Time"], ref["Autocross_Time"])) <= 1.5


def test_endurance_speed_trace_rms(validation_case):
    """Speed-vs-distance RMS error <= 4% of mean event speed (endurance)."""
    tr = pd.read_csv(REF_TRACE)
    e = tr[tr.Event == "Endurance"]
    lap = validation_case.endurance
    v_py = np.interp(e.Distance_ft, lap.distance, lap.velocity)
    rms = np.sqrt(np.mean((v_py - e.Speed_ft_s) ** 2))
    assert 100.0 * rms / e.Speed_ft_s.mean() <= 4.0


@pytest.mark.xfail(strict=True,
                   reason="committed autocross trace geometry differs (path "
                          "2334.1 ft vs 2728.0 ft from committed inputs)")
def test_autocross_speed_trace_rms(validation_case):
    tr = pd.read_csv(REF_TRACE)
    a = tr[tr.Event == "Autocross"]
    lap = validation_case.autocross
    v_py = np.interp(a.Distance_ft, lap.distance, lap.velocity)
    rms = np.sqrt(np.mean((v_py - a.Speed_ft_s) ** 2))
    assert 100.0 * rms / a.Speed_ft_s.mean() <= 4.0


def test_autocross_geometry_matches_committed_inputs(shared):
    """The autocross path computed from the COMMITTED inputs must match the
    geometry embedded in the committed latestpgResults.mat workspace (an
    independent MATLAB artifact) to high precision. This pins the port's
    autocross construction even though the sweep oracle used other data."""
    import scipy.io as sio
    m = sio.loadmat(os.path.join(TEST_RESULTS_DIR, "latestpgResults.mat"),
                    squeeze_me=True, variable_names=["distance_ax"])
    ref_total = float(np.ravel(m["distance_ax"])[-1])
    my_total = float(shared.autocross.seg_dist.sum())
    assert my_total == pytest.approx(ref_total, rel=1e-9)


@pytest.mark.slow
def test_sweep_gate(shared):
    """176-case fast sweep vs the committed workbook."""
    from scipy.stats import spearmanr

    from pylapsim.sweep import run_sweep
    df = run_sweep()
    ref = pd.read_excel(REF_WORKBOOK, sheet_name="All Results Ranked")
    key = ["CL_target", "CD_target", "CoP_target"]
    mine = df[df.RunMode == "Fast"].round({k: 6 for k in key})
    reff = ref[ref.RunMode == "Fast"].round({k: 6 for k in key})
    m = mine.merge(reff, on=key, suffixes=("_py", "_ml"))
    assert len(m) == 176

    rho = spearmanr(m.Total_Points_py, m.Total_Points_ml).statistic
    assert rho >= 0.98  # rank gate PASSES despite the autocross geometry issue

    # Port-fidelity deltas excluding the irreproducible autocross geometry:
    d = (m.Total_Points_py - m.Autocross_Score_py) \
        - (m.Total_Points_ml - m.Autocross_Score_ml)
    assert abs(d.mean()) <= 1.5
    assert d.abs().max() <= 5.0

    # Raw-total deltas: documented FAIL while the autocross data is absent.
    d_raw = m.Total_Points_py - m.Total_Points_ml
    assert d_raw.mean() > 1.5, "raw totals now match: remove the VALIDATION.md caveat"
