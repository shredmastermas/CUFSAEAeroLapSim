import numpy as np
import pytest

from pylapsim.tires import (PPFormTensor, eval_longitudinal_tire_limit,
                            load_fx_spline, load_lateral_model)


@pytest.fixture(scope="module")
def fx():
    return load_fx_spline()


@pytest.fixture(scope="module")
def mf():
    return load_lateral_model()


def test_fx_layout_continuity(fx):
    # exact-break polynomial agreement: a wrong coefficient layout is O(1) off
    assert fx.max_continuity_jump() < 1e-10


def test_fx_smooth_bounded_over_sim_ranges(fx):
    """Brief requirement: smooth/bounded over slip 0..0.11 and -0.15..0,
    FZ -250..-50 lbf, IA ~ 0."""
    slips = np.linspace(-0.15, 0.11, 105)
    loads = np.linspace(50.0, 250.0, 41)
    vals = fx.eval(slips[None, :], -loads[:, None], 0.0)
    assert np.isfinite(vals).all()
    assert np.abs(vals).max() < 2500  # raw (unscaled) force stays physical
    # smoothness: second differences bounded along slip
    d2 = np.diff(vals, n=2, axis=1)
    assert np.abs(d2).max() < 50.0


def test_fx_sign_convention(fx):
    drive = fx.eval(0.08, -150.0, 0.0)
    brake = fx.eval(-0.08, -150.0, 0.0)
    assert drive > 100.0
    assert brake < -100.0


def test_eval_longitudinal_tire_limit_filters(fx):
    sl = np.arange(0.0, 0.1101, 0.01)
    lim = eval_longitudinal_tire_limit(fx, sl, 150.0, 0.0, 0.45, "max")
    assert 100.0 < lim < 250.0
    # min mode returns the most negative braking force
    slb = np.arange(-0.15, 0.0001, 0.01)
    limb = eval_longitudinal_tire_limit(fx, slb, 150.0, 0.0, 0.45, "min")
    assert -250.0 < limb < -100.0


def test_mf52_shape_and_sign(mf):
    alphas = np.linspace(0.0, 12.0, 40)
    fy = mf(alphas, 150.0, 0.0)
    # SAE sign: positive slip angle -> negative lateral force
    assert fy[5:].max() < 0
    peak_alpha = alphas[np.argmin(fy)]
    assert 6.0 < peak_alpha < 11.0  # race tire peak slip angle range
    # load sensitivity: more load -> more force but lower mu
    f1 = -float(mf(8.0, 100.0, 0.0))
    f2 = -float(mf(8.0, 200.0, 0.0))
    assert f2 > f1
    assert f2 / 200.0 < f1 / 100.0


def test_mf52_matches_loaded_scales(mf):
    assert mf.FZ0 == pytest.approx(-146.545, abs=0.01)
    assert mf.LFZO == 1.0 and mf.LMUY == 1.0
