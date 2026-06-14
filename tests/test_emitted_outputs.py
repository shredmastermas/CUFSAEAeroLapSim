"""Contract validation of every artifact emitted under Test Results/python/.

DATA_CONTRACT §F: outputs do not ship unless these pass. Skips cleanly if the
outputs have not been generated in this checkout (they are produced by the
Phase 5/6 pipeline; regenerate via `python -m pylapsim sweep` + the
recommendation scripts).
"""

import glob
import os

import pytest

from pylapsim.config import PYTHON_RESULTS_DIR
from pylapsim.io_contract import (validate_meta, validate_summary,
                                  validate_trace, validate_workbook)

pytestmark = pytest.mark.skipif(
    not os.path.isdir(PYTHON_RESULTS_DIR),
    reason="Test Results/python/ outputs not generated in this checkout",
)


def _glob(pattern):
    return sorted(glob.glob(os.path.join(PYTHON_RESULTS_DIR, pattern)))


def test_workbooks_pass_contract():
    books = [p for p in _glob("T27_AeroSweep_pylapsim_*.xlsx")]
    assert books, "no emitted workbooks found"
    for p in books:
        df = validate_workbook(p)
        assert len(df) >= 176, f"{p}: expected at least the full grid"


def test_traces_pass_contract():
    traces = _glob("T27_validation_trace_*.csv") + _glob("traces/T27_validation_trace_*.csv")
    assert traces, "no emitted traces found"
    for p in traces:
        df = validate_trace(p)
        assert set(df.Event.unique()) == {"Endurance", "Autocross"}


def test_summaries_pass_contract():
    sums = _glob("T27_validation_summaries_*.csv")
    assert sums, "no emitted summaries found"
    for p in sums:
        validate_summary(p)


def test_meta_files_pass_contract():
    metas = _glob("*.meta.json")
    assert metas, "no emitted meta.json found"
    for p in metas:
        meta = validate_meta(p)
        assert meta["engine"]["name"] == "pylapsim"
