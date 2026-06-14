"""pylapsim — Python port of the CUFSAE T27 constant-aero MATLAB lap sim.

Validated against the committed MATLAB artifacts in `Lap Sim March 2026/Test
Results/` (see docs/VALIDATION.md). The `legacy_compat` config flag reproduces
the committed V4 physics including the FINDINGS F1 load-transfer bug, because
the validation oracle was generated with that bug; `legacy_compat=False` runs
the corrected physics.
"""

__version__ = "0.1.0"
