import numpy as np
import pytest

from pylapsim.airfoils import (AIRFOILS, REYNOLDS, cla_from_cl_target,
                               load_coordinates, load_manifest, load_polar,
                               polar_summary, suggest_wings)


def test_manifest_covers_all_files():
    man = load_manifest()
    for name, spec in AIRFOILS.items():
        assert spec["coord"] in man["files"]
        for re in REYNOLDS:
            assert spec["polar"].format(re=re) in man["files"]
    for entry in man["files"].values():
        assert entry["url"].startswith("http")
        assert len(entry["sha256"]) == 64


@pytest.mark.parametrize("name", list(AIRFOILS))
def test_coordinates_parse(name):
    xy = load_coordinates(name)
    assert len(xy) > 30
    # normalized chord, closed-ish profile
    assert xy[:, 0].min() >= -0.01 and xy[:, 0].max() <= 1.01
    assert np.abs(xy[:, 1]).max() < 0.5


@pytest.mark.parametrize("name", list(AIRFOILS))
@pytest.mark.parametrize("re", REYNOLDS)
def test_polars_parse(name, re):
    df = load_polar(name, re)
    assert {"Alpha", "Cl", "Cd"} <= set(df.columns)
    assert len(df) > 20
    assert (df.Cd > 0).all()
    # these are documented high-lift sections: published 2D cl_max > 1.5
    assert df.Cl.max() > 1.5


def test_units_bridge_matches_findings_examples():
    """FINDINGS 'Physical-units bridge' examples (rho = 0.002377 slug/ft^3)."""
    ft2, m2 = cla_from_cl_target(0.080)
    assert ft2 == pytest.approx(67.3, abs=0.1)
    assert m2 == pytest.approx(6.25, abs=0.01)
    ft2, m2 = cla_from_cl_target(0.0512)
    assert m2 == pytest.approx(4.00, abs=0.01)


def test_suggester_rows_carry_citations():
    df = suggest_wings(0.050, 0.0225, 0.525)
    assert len(df) == 2 * len(AIRFOILS) * len(REYNOLDS) * 3
    assert (df.polar_source.str.startswith("http")).all()
    assert df.rules_box.str.contains("T.7").all()
    front = df[df.Wing == "Front"]
    assert front.DF_share.iloc[0] == pytest.approx(0.525)
    # more achieved CL -> less area
    sub = front[(front.Airfoil == "S1223") & (front.Re == 200000)]
    areas = sub.sort_values("achieved_CL_fraction (unsourced sensitivity)").wing_area_required_ft2
    assert areas.is_monotonic_decreasing


def test_polar_summary_sane():
    ps = polar_summary("S1223", 200000)
    assert 1.8 < ps.cl_max < 2.6  # S1223 is a ~2.2 cl_max section in XFOIL
    assert 0 < ps.alpha_clmax_deg < 20
