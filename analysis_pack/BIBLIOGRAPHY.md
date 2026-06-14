# Bibliography — citations and links only

No source contents are reproduced in this repo; retrieve from the links.

## Rules

1. *Formula SAE® Rules 2026, Version 1.0* (10 Sept 2025). SAE International.
   Retrieved 2026-06-12 from fsaeonline.com:
   https://www.fsaeonline.com/cdsweb/gen/DownloadDocument.aspx?DocumentID=278fd4d7-aa27-4e33-bc4a-090148e662a0
   - §D.13 Efficiency Event (pp. 143–145): conversion factors D.13.4.1,
     Efficiency Factor D.13.4.4, anchors D.13.4.5, score D.13.4.6.
   - §T.7 Bodywork and Aerodynamic Devices (pp. 70–72): T.7.5 length,
     T.7.6 width, T.7.7 height limits.

## Airfoil data

2. UIUC Airfoil Coordinates Database, M. Selig, UIUC Applied Aerodynamics
   Group: https://m-selig.ae.illinois.edu/ads/coord_database.html
   Files used (exact URLs + sha256 in `data/airfoils/MANIFEST.json`):
   s1223.dat, e423.dat, ch10sm.dat, s1210.dat, fx74cl5140.dat.
3. airfoiltools.com XFOIL-computed polars (Ncrit = 9, Mach 0), Re 2×10⁵ and
   5×10⁵ per section, e.g.
   http://airfoiltools.com/polar/csv?polar=xf-s1223-il-200000
   (all 10 polar URLs in `data/airfoils/MANIFEST.json`). Computed data —
   cited as XFOIL predictions, not wind-tunnel measurements.

## Physical constants

4. Standard sea-level air density ρ = 0.002377 slug/ft³ (U.S. Standard
   Atmosphere, 1976 — sea-level value as commonly tabulated).
5. 1 ft·lbf = 1.3558179483314004 J (NIST SP 811 conversion factor).

## Team/committed data (in-repo, commit e5fd7e2)

6. CUFSAEAeroLapSim committed artifacts: TTC-derived tire model .mat files
   (A2356run008 MF5.2 lateral fit; Hoosier R20 18x6.0-10 FX CSAPS fit),
   track coordinate workbooks, racing-line .mat files, sweep workbook,
   validation trace/summary, latestpgResults.mat / latestLLTDResults.mat
   workspaces. (TTC raw data is consortium-licensed; only the team's fitted
   models live in the repo and are used here.)

## Software

7. pymoo (NSGA-II), SALib (Sobol/Saltelli), SciPy, NumPy, pandas, csaps
   (MATLAB-compatible cubic smoothing splines), matplotlib, openpyxl, pytest —
   versions pinned in the emitted meta.json config snapshots.
