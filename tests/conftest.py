import os
import sys

import pytest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from pylapsim.config import HIGH, AeroTarget, SimConfig  # noqa: E402
from pylapsim.simulate import SharedData, run_case  # noqa: E402


def pytest_addoption(parser):
    parser.addoption("--run-slow", action="store_true", default=False,
                     help="run the slow 176-case sweep regression gate")


def pytest_collection_modifyitems(config, items):
    if config.getoption("--run-slow"):
        return
    skip = pytest.mark.skip(reason="slow: pass --run-slow to run the full sweep gate")
    for item in items:
        if "slow" in item.keywords:
            item.add_marker(skip)


@pytest.fixture(scope="session")
def shared():
    return SharedData.load()


@pytest.fixture(scope="session")
def validation_case(shared):
    """The Gate A case: CL 0.040 / CD 0.020 / CoP 0.450, High preset, legacy."""
    cfg = SimConfig(aero=AeroTarget(0.040, 0.020, 0.450), resolution=HIGH,
                    legacy_compat=True)
    return run_case(cfg, shared)
