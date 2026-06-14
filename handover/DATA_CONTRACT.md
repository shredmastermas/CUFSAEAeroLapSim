# Dashboard data contract

Consumer: `dashboard/t27-aero-dashboard.jsx` (React; parses workbooks with SheetJS and traces
with PapaParse — read its `onSweepFile` / `onTraceFile` functions for the authoritative parsing
rules). Every results artifact the new pipeline emits MUST remain loadable by it unmodified.
Rule of thumb: **preserve existing column names exactly; append new columns; never rename.**

---

## A. Results workbook (.xlsx)

- Sheet name: **`All Results Ranked`** (the dashboard falls back to the first sheet, but keep
  the name for the team's existing habits).
- Columns the dashboard requires (exact names):

```
CL_target, CD_target, CoP_target,
Total_Points, Accel_Score, Skidpad_Score, Autocross_Score, Endurance_Score,
Accel_Time, Skidpad_Time, Autocross_Time, Endurance_Lap_Time,
CL_over_CD, RunMode, IsFeasibleAeroTarget
```

- `RunMode` ∈ {`Fast`, `AccurateRerun`}. `IsFeasibleAeroTarget` boolean (TRUE/FALSE or 1/0).
- Full committed 54-column schema (preserve all of these):

```
AeroTag, CL_target, CD_target, CoP_target,
Accel_Score, Skidpad_Score, Autocross_Score, Endurance_Score, Total_Points,
Skidpad_Time, Accel_Time, Autocross_Time, Endurance_Lap_Time,
CL_over_CD, RunNumber, RunMode,
PointGain_vs_Baseline, CD_Increase_vs_Baseline, CL_Increase_vs_Baseline, PointGain_per_CD,
BalanceError, FrontAeroPercent, RearAeroPercent,
Speed_35mph_ft_s, DF_Total_35mph_lbf, DF_Front_35mph_lbf, DF_Rear_35mph_lbf,
Drag_Total_35mph_lbf, LiftToDrag_35mph,
Speed_45mph_ft_s, DF_Total_45mph_lbf, DF_Front_45mph_lbf, DF_Rear_45mph_lbf,
Drag_Total_45mph_lbf, LiftToDrag_45mph,
Speed_60mph_ft_s, DF_Total_60mph_lbf, DF_Front_60mph_lbf, DF_Rear_60mph_lbf,
Drag_Total_60mph_lbf, LiftToDrag_60mph,
FeasibilityRefSpeed_mph, FeasibilityRefSpeed_ft_s, DF_Total_FeasRef_lbf, Drag_Total_FeasRef_lbf,
LiftToDrag_FeasRef, MinFeasibleDownforceAtRef_lbf, MaxFeasibleDownforceAtRef_lbf,
MinFeasibleLiftToDrag, MaxFeasibleLiftToDrag, MinFeasibleDragAtRef_lbf, MaxFeasibleDragAtRef_lbf,
IsFeasibleAeroTarget, FeasibilityNotes
```

- Committed feasibility window values (current placeholders): ref 35 mph; DF 90–135 lbf;
  drag 40–65 lbf; L/D 2.0–2.4.
- **New columns to append** (Phase 3+; names are the contract):

```
DragEnergy_Endurance_kJ, DragEnergy_Autocross_kJ,
TractiveEnergy_Endurance_kJ, TractiveEnergy_Autocross_kJ,
Efficiency_Score (nullable — only when BSFC configured),
Mass_lbf, MassScenario, BSFC_g_per_kWh (nullable),
EngineMode (legacy | corrected)
```

---

## B. Telemetry trace (.csv)

Exact header (order preserved):

```
Event, Time_s, Distance_ft, Speed_ft_s, Longitudinal_G, Lateral_G, Gear
```

- `Event` values: `Endurance`, `Autocross`. One file may contain both events back-to-back.
- Committed example: 14,990 rows per event
  (`T27_validation_trace_CL_0_040_CD_0_020_CoP_0_450.csv`).
- MATLAB-side generator: `Aero/buildValidationTelemetry.m`, written by V4 around lines
  1088–1089. The Python engine must emit identical schema for the top-N candidate cases
  (filename pattern `T27_validation_trace_<AeroTag>.csv` is the team's convention).

---

## C. Validation summary (.csv) — the KPI gate file

Columns:

```
AeroTag, CL_target, CD_target, CoP_target,
Endurance_Lap_Time, Autocross_Time, Skidpad_Time, Accel_Time,
Endurance_Max_Speed, Autocross_Max_Speed, Max_AX, Min_AX, Max_Abs_AY
```

Committed reference values (CL 0.040 / CD 0.020 / CoP 0.450) — these are the Phase 2 Gate A
targets:

| KPI | value | unit |
|---|---|---|
| Endurance_Lap_Time | 131.398 | s |
| Autocross_Time | 59.043 | s |
| Skidpad_Time | 4.9564 | s |
| Accel_Time | 4.96794 | s |
| Endurance_Max_Speed | 92.124 | ft/s |
| Autocross_Max_Speed | 76.558 | ft/s |
| Max_AX | +0.5526 | g |
| Min_AX | −1.0486 | g |
| Max_Abs_AY | 2.1390 | g |

---

## D. Vehicle constants the dashboard hardcodes

Keep the sim consistent with these, or update both sides together:
W = 580 lbf · static front fraction 0.474 · CG height 12.2/12 ft · wheelbase 60.5/12 ft ·
LLTD 0.38 · mean track (47+46)/2/12 ft. Force convention DF = CL·V², drag = CD·V²
(V in ft/s, lbf). The dashboard computes corner loads with the **physically correct**
longitudinal transfer A_X·W·h/L (see FINDINGS F1).

---

## E. meta.json (new — emit alongside every results bundle, Phase 6)

```json
{
  "git_sha": "...", "generated_at": "ISO8601",
  "engine": { "name": "pylapsim", "version": "...", "legacy_compat": false },
  "config": { "...full resolved config snapshot..." },
  "sources": ["tire .mat files used", "track files", "racing line files"],
  "assumptions": [ { "name": "bsfc_g_per_kWh", "value": null, "source": "team input required" } ]
}
```

---

## F. Contract test (required)

A pytest that loads every emitted workbook/trace/summary and asserts: sheet name, required
columns present with exact names, RunMode and Event value sets, boolean parse of
IsFeasibleAeroTarget, numeric parse of all score/time columns — i.e., the same expectations the
dashboard's upload parsers apply. Outputs do not ship unless this test passes.
