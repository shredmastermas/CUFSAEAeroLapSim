"""Output contract tests (DATA_CONTRACT §F): every emitted artifact must load
under the same expectations the dashboard's upload parsers apply."""

import os

import pandas as pd
import pytest

from pylapsim.config import SimConfig
from pylapsim.io_contract import (COMMITTED_COLUMNS, NEW_COLUMNS, SHEET_NAME,
                                  safe_aero_tag, validate_meta, validate_summary,
                                  validate_trace, validate_workbook,
                                  write_meta_json, write_results_workbook,
                                  write_trace_csv, write_validation_summary_csv)
from pylapsim.sweep import case_row, finalize_results


@pytest.fixture(scope="module")
def emitted(tmp_path_factory, validation_case):
    out = tmp_path_factory.mktemp("contract")
    rows = [case_row(validation_case, "Fast", 1),
            case_row(validation_case, "AccurateRerun", 2)]
    df = finalize_results(pd.DataFrame(rows))
    wb = os.path.join(out, "results.xlsx")
    tr = os.path.join(out, f"T27_validation_trace_{safe_aero_tag(validation_case.config.aero.tag)}.csv")
    sm = os.path.join(out, "summary.csv")
    mj = os.path.join(out, "meta.json")
    write_results_workbook(df, wb)
    write_trace_csv(validation_case, tr)
    write_validation_summary_csv([validation_case], sm)
    write_meta_json(mj, validation_case.config)
    return {"wb": wb, "tr": tr, "sm": sm, "mj": mj}


def test_workbook_contract(emitted):
    df = validate_workbook(emitted["wb"])
    assert list(df.columns)[: len(COMMITTED_COLUMNS)] == COMMITTED_COLUMNS
    for c in NEW_COLUMNS:
        assert c in df.columns


def test_trace_contract(emitted):
    df = validate_trace(emitted["tr"])
    assert set(df.Event.unique()) == {"Endurance", "Autocross"}
    assert (df.groupby("Event").size() == 14990).all()


def test_summary_contract(emitted):
    df = validate_summary(emitted["sm"])
    assert len(df) == 1


def test_meta_contract(emitted):
    meta = validate_meta(emitted["mj"])
    assert meta["engine"]["name"] == "pylapsim"
    assert meta["assumptions"][0]["name"] == "bsfc_g_per_kWh"
    assert meta["assumptions"][0]["value"] is None


def test_committed_workbook_passes_contract():
    """The committed MATLAB workbook must satisfy the same reader (sanity that
    the validator matches the team's real artifact, minus our new columns)."""
    from pylapsim.config import TEST_RESULTS_DIR
    path = os.path.join(TEST_RESULTS_DIR, "T27_AeroSweep_Multithreaded_Results.xlsx")
    df = validate_workbook(path)
    assert len(df) == 186


def test_safe_aero_tag():
    assert safe_aero_tag("CL_0.040_CD_0.020_CoP_0.450") == "CL_0_040_CD_0_020_CoP_0_450"
