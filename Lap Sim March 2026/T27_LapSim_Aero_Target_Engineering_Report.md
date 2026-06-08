# T27 Design Project Proposal

## Lap Simulation Based Aero Target Development

Lead Designer: TBD  
Division Lead: TBD  
Document Purpose: Engineering report and proposal support document  
Related Files:

- `Lap_Sim_constantAero_T27V4.m`
- `Run_T27_AeroSweep_MultithreadedExcel.m`
- `T27_AeroSweep_Multithreaded_Results.mat`
- `T27_AeroSweep_Multithreaded_Results.xlsx`
- `T27_LapSim_Presentation_Notes.md`

## Executive Summary

T27 currently needs a traceable reason for selecting aerodynamic goals such as center of pressure, downforce target, and drag target. Historically, these values can easily become inherited from previous cars or copied from past aero packages without a clear link to competition scoring. This lap simulation project creates that link, but the latest review showed an important issue: the unconstrained lap sim will choose aero values that are far beyond realistic CUFSAE capability.

The lap sim evaluates how different values of `CL`, `CD`, and front aero balance affect predicted dynamic event points. Instead of asking only "how much downforce can we make?", the sim asks "which aero target gives the best competition result after acceleration, skidpad, autocross, and endurance are all scored?" The answer must be filtered through physical feasibility limits. Without that filter, the sim optimizes toward extremely high downforce and extremely high lift-to-drag ratio.

The unconstrained mathematical winner from the previous sweep was approximately `CL=0.160`, `CD=0.010`, and `CoP=0.475` to `0.525`. At 35 mph, that predicts about 422 lbf of downforce and L/D of 16. This is not a realistic design target for our current aero capability. It should be treated as a model-limit result, not as an aero goal.

The updated engineering recommendation is to use the lap sim with feasibility caps based on expected CUFSAE aero capability. At about 15 m/s, which is approximately 35 mph, a reasonable expected total downforce range is 90 to 135 lbf, which is approximately 400 to 600 N. Drag should be slightly below half of downforce, roughly 40 to 65 lbf at that speed. The previous year's aero efficiency was about L/D = 2.2, so the sweep should not be allowed to select much higher efficiency unless there is CFD or test evidence to support it.

The current feasibility defaults are:

| Feasibility Limit | Current Value | Reason |
|---|---:|---|
| Reference speed | 35 mph | Close to the 15 m/s aero reference speed commonly used by the team. |
| Min total downforce at reference speed | 90 lbf | Lower end of expected realistic aero load. |
| Max total downforce at reference speed | 135 lbf | Upper end of expected realistic aero load. |
| Lift-to-drag target window | 2.0 to 2.4 | Centers the feasible sweep around last year's L/D about 2.2 and rejects unrealistic values such as L/D 16. |

A defensible nominal starting target is:

| Target | Feasible Starting Goal | Notes |
|---|---:|---|
| Lap-sim `CL_target` | about `0.045` | Gives about 119 lbf total downforce at 35 mph. |
| Lap-sim `CD_target` | about `0.020` | Gives about 53 lbf drag at 35 mph, slightly below half of downforce, with L/D near 2.25. |
| Front aero balance, `CoP_target` | about `0.475` front | Use as a starting balance target; preserve adjustability. |
| Front downforce share | about 47.5 percent | About 56 lbf front downforce at 35 mph for the nominal target. |
| Rear downforce share | about 52.5 percent | About 62 lbf rear downforce at 35 mph for the nominal target. |

Important: the `CL_target` and `CD_target` used in this lap sim are force coefficients in the sim's units:

```text
Downforce [lbf] = CL_target * V^2
Drag [lbf]      = CD_target * V^2
```

where `V` is speed in ft/s. These are not automatically CFD nondimensional coefficients. They must be converted or correlated before they become final CFD, wind tunnel, or track targets.

## Scope

### What The Design Project Tackles

This design project uses a MATLAB lap simulation to define initial T27 aerodynamic performance targets. The project focuses on:

- selecting a defensible front/rear aero balance target
- selecting a defensible total downforce target
- selecting a defensible total drag target
- comparing aero packages by predicted competition points
- understanding event-level tradeoffs, especially acceleration vs cornering vs endurance
- creating a validation path against real logged data

The lap sim is not intended to replace CFD, physical testing, or driver feedback. It is intended to give those efforts a target and a reason.

### What Limits The Project Has

The current lap sim is a target-setting tool, not a full high-fidelity vehicle dynamics model. Major limits include:

- Aero is modeled with constant `CL`, `CD`, and CoP.
- Aero does not currently vary with yaw, pitch, roll, ride height, steering angle, or proximity to the ground.
- The racing line is loaded from saved files and is not re-optimized for every aero case.
- Tire behavior depends on loaded tire models and global scale factors.
- The model is mostly quasi-static and does not fully capture transient driver control.
- Scoring is based on fixed reference times in the script.

These limits are acceptable for first-pass aero target development because the goal is to compare aero concepts consistently. They must be addressed before making final design claims.

### How The Design Affects The Rest Of The Car

The aero target directly affects:

- chassis mounting loads
- front wing and nose mounting structure
- rear wing mounting structure
- diffuser and undertray packaging
- suspension ride-height targets
- spring rates and platform control
- cooling inlet and outlet design
- powertrain performance due to drag
- driver confidence and vehicle balance
- tire loading and tire utilization

The sim is useful because it makes these interactions visible in points. For example, increasing downforce may improve skidpad, autocross, and endurance, but increasing drag can hurt acceleration and straight-line speed. A target must balance both.

### How This Design Is Affected By Other Designs

The aero goal depends on:

- available engine power and gearing
- vehicle mass
- CG height and weight distribution
- tire choice and tire scaling
- suspension stiffness and ride-height control
- front and rear track width
- packaging volume for aero surfaces
- cooling requirements
- rules-defined aero zones
- manufacturability and stiffness of aero mounts

If any of these change significantly, the aero sweep should be rerun.

### What Was Learned From The Previous Design

The main process issue from previous designs is that aero numbers can be carried forward without a clear engineering reason. A previous car may have used a certain CoP, CL, or CD because it was achievable, familiar, or inherited. That does not prove it is optimal for T27.

The lap sim changes the design process by making the reasoning explicit:

1. Choose candidate aero targets.
2. Run them through the same tire, powertrain, vehicle, track, and scoring model.
3. Rank them by total points and event performance.
4. Convert the best target region into component-level goals.
5. Validate with real data before freezing the design.

## Goals

### Team Goals

The team goal is to improve total dynamic competition performance. The aero target should not be optimized for only one event. It should improve the car's overall scoring potential.

Specific team-level goals:

- improve total dynamic event points
- improve autocross and endurance times without unacceptable acceleration loss
- provide clear design targets to aero, suspension, chassis, and powertrain
- reduce reliance on previous-year assumptions
- create a repeatable process that can be rerun as the car changes

### Divisional Goals

The aero division goal is to define performance targets that can guide design decisions for:

- front wing
- rear wing
- diffuser
- undertray
- bodywork
- cooling exits
- mounting structure

The simulation should provide:

- target total downforce
- target total drag
- target front/rear aero balance
- component-level downforce and drag budgets
- validation metrics for track testing

### Design Goals

The current recommended base aero goal should be separated into two categories:

1. Unconstrained lap-sim optimum: useful for showing what the model wants mathematically, but not realistic.
2. Feasible engineering target: useful for design, because it respects downforce and efficiency limits.

The unconstrained sweep result was:

| `CL` | `CD` | `CoP` | Total Points | 35 mph Downforce | 35 mph Drag | L/D | Status |
|---:|---:|---:|---:|---:|---:|---:|---|
| 0.160 | 0.010 | 0.475 | 552.45 | 422 lbf | 26 lbf | 16 | Infeasible with current capability assumptions. |

The feasible design target using the current CUFSAE-based caps is:

| Design Goal | Value | Notes |
|---|---:|---|
| Primary feasible lap-sim `CL_target` | `0.045` nominal, `0.034` to `0.051` range | Corresponds to about 90 to 135 lbf at 35 mph. |
| Primary feasible lap-sim `CD_target` | about `0.020`, expected range `0.016` to `0.023` | Corresponds to about 40 to 65 lbf drag at 35 mph. |
| Primary feasible lap-sim L/D | about `2.2` nominal, feasible window `2.0` to `2.4` | Based on previous-year efficiency near 2.2; prevents unrealistic efficiency from winning. |
| Primary feasible `CoP_target` | `0.475` front | About 47.5 percent front, 52.5 percent rear. |
| CoP validation range | `0.450` to `0.525` front | Keep physical adjustability until validated with real data. |

The recommended engineering position is:

- do not use `CL=0.160`, `CD=0.010` as a real design target unless CFD or test data proves that load and efficiency are achievable
- use `CL≈0.045`, `CD≈0.020`, `CoP≈0.475` as a realistic starting point under the current feasibility assumptions
- refine the 90-135 lbf downforce window, 40-65 lbf drag window, and L/D 2.0-2.4 feasibility window with measured CUFSAE data as soon as possible
- preserve aero adjustability so testing can move balance between roughly 45 percent and 52.5 percent front

## Aero Target Interpretation

### Lap-Sim Force Target Table

The current target is based on the lap-sim force equation:

```text
Downforce = CL_target * V^2
Drag      = CD_target * V^2
```

The table below compares the unconstrained mathematical winner against the feasible starting target. This is the key point for design review: the model can identify performance trends, but it must be filtered by physical aero capability.

| Case | CL | CD | CoP | 35 mph DF | 35 mph Drag | L/D | Interpretation |
|---|---:|---:|---:|---:|---:|---:|---|
| Unconstrained winner | 0.160 | 0.010 | 0.475 | 422 lbf | 26 lbf | 16 | Too much downforce and too efficient to treat as realistic. |
| Feasible nominal target | 0.045 | 0.020 | 0.475 | 119 lbf | 53 lbf | 2.25 | Plausible first target using CUFSAE expected aero capability and last year's efficiency. |

For the feasible nominal target `CL=0.045`, `CD=0.020`, `CoP=0.475`, the load targets are:

| Speed | Speed | Total Downforce | Front Downforce | Rear Downforce | Total Drag | L/D |
|---:|---:|---:|---:|---:|---:|---:|
| 35 mph | 51.3 ft/s | 119 lbf | 56 lbf | 62 lbf | 53 lbf | 2.25 |
| 45 mph | 66.0 ft/s | 196 lbf | 93 lbf | 103 lbf | 87 lbf | 2.25 |
| 60 mph | 88.0 ft/s | 348 lbf | 166 lbf | 183 lbf | 155 lbf | 2.25 |

These numbers should be treated as lap-sim force targets until the coefficient scaling is correlated. If CFD or wind tunnel outputs use nondimensional coefficients, the team must convert them into the sim's force model before direct comparison.

### Initial Component-Level Aero Budgets

The sim currently does not model individual aero components. It models total downforce, total drag, and front/rear aero balance. Therefore, the following component budgets are recommended starting allocations, not proven component optima.

At the feasible nominal target of `CL=0.045`, `CD=0.020`, and `CoP=0.475`, the 35 mph reference load is:

```text
Total downforce at 35 mph = about 119 lbf
Front aero target         = about 56 lbf
Rear aero target          = about 62 lbf
Total drag target         = about 53 lbf
Lift-to-drag target       = about 2.25
```

Across the expected 90-135 lbf (400-600 N) downforce window, the front/rear split at `CoP=0.475` is approximately:

```text
Front aero target range = about 43 to 64 lbf at 35 mph
Rear aero target range  = about 47 to 71 lbf at 35 mph
Total drag target range = about 40 to 65 lbf at 35 mph, slightly below half of downforce
```

Recommended component allocation at 35 mph:

| Component / Package | Downforce Goal | Drag Budget | Notes |
|---|---:|---:|---|
| Front wing / front aero package | 40 to 65 lbf | 10 to 25 lbf | Main tool for front balance. Must remain adjustable. |
| Rear wing | 30 to 50 lbf | 20 to 40 lbf | Likely largest drag contributor; should be efficient but realistic. |
| Diffuser / undertray | 10 to 25 lbf | 5 to 15 lbf | Valuable if it produces load efficiently and stays stable with ride height. |
| Bodywork / cooling aero | avoid lift, minimize drag | remaining drag budget | Cooling exits should avoid hurting rear wing and diffuser performance. |

Recommended component allocation as percent of total downforce:

| Component / Package | Percent of Total Downforce |
|---|---:|
| Front aero package | 41 to 54 percent |
| Rear wing | 28 to 41 percent |
| Diffuser / undertray | 13 to 22 percent |
| Other aero surfaces | as low or beneficial as practical |

The most important component-level design requirement is adjustability. The car should be able to shift aero balance during testing because the best feasible CoP is still an assumption until validated with real data.

## Validation And Verification Goals

### How The Design Will Be Validated

Validation should compare the sim against real car data. The goal is not only to match lap time, but to understand why the lap time matches or does not match.

Required comparison plots:

- speed vs distance
- longitudinal acceleration vs distance
- lateral acceleration vs distance
- gear vs distance
- time delta vs distance
- braking zone entry and exit speeds
- minimum speed in key corners
- maximum speed on straights
- skidpad steady-state lateral g

### Sensors Needed

Recommended sensors and logged channels:

| Channel | Purpose |
|---|---|
| GPS position and speed | Track alignment, speed trace, distance trace |
| IMU longitudinal acceleration | Accel and braking validation |
| IMU lateral acceleration | Cornering and skidpad validation |
| Wheel speed | Speed validation and wheel slip checks |
| Steering angle | Driver input and cornering comparison |
| Throttle position | Acceleration model validation |
| Brake pressure | Braking model validation |
| Engine RPM | Gear and powertrain model validation |
| Gear position | Shift timing and gear trace validation |
| Damper pots or ride-height sensors | Aero platform and ride-height sensitivity validation |

### Verification Of The Code

MATLAB R2026a verification completed:

- Fast baseline case ran successfully.
- Accurate baseline case ran successfully.
- Two-case `parfor` runner smoke test ran successfully with 2 workers.

The verified baseline case was:

| `CL` | `CD` | `CoP` | Total Points | Autocross Time | Endurance Lap Time |
|---:|---:|---:|---:|---:|---:|
| 0.080 | 0.020 | 0.450 | 417.35 | 56.903 s | 125.3 s |

The two-case parallel smoke test confirmed that the multithreaded runner can execute independent aero cases through MATLAB's Parallel Computing Toolbox.

## Criteria

Criteria are used to judge whether one aero target or component concept is better than another after all constraints are met.

| Criteria | Weight | Justification |
|---|---:|---|
| Total dynamic points | 30 percent | The purpose of the aero package is to improve competition performance, not isolated peak downforce. |
| Autocross and endurance time | 20 percent | These events benefit strongly from usable cornering performance and usually dominate aero value. |
| Drag efficiency | 15 percent | Drag hurts acceleration and straight-line speed, so downforce must be efficient. |
| Aero balance adjustability | 15 percent | The best CoP is sensitive and must be tunable during testing. |
| Structural feasibility | 10 percent | The car must survive loads and maintain aero platform stiffness. |
| Manufacturability and serviceability | 5 percent | The design must be buildable and repairable by the team. |
| Validation quality | 5 percent | A target is only useful if the team can measure whether it was achieved. |

## Constraints

### Major Rules

The final aero design must be checked against the current FSAE rules before release. Major rule areas likely to constrain the design include:

- maximum aero device size and location
- forward, rearward, and lateral bodywork/aero limits
- driver egress and visibility
- sharp edge and radius requirements
- structural attachment and safety requirements
- ground clearance requirements
- no unsafe movable aero unless specifically allowed

This report does not replace a rules check. It defines performance targets.

### Technical Constraints

The design must also satisfy:

- mounting stiffness and strength
- allowable chassis hardpoint loads
- ride-height and pitch sensitivity
- tire clearance through steering and suspension travel
- cooling airflow needs
- reasonable assembly time
- access for inspection and repair
- low enough drag to avoid losing acceleration and endurance performance

## Stakeholders

| Stakeholder | Interaction With Lap Sim / Aero Target |
|---|---|
| Aero | Uses CL, CD, CoP, downforce, and drag targets to design front wing, rear wing, diffuser, and bodywork. |
| Suspension | Must support aero platform, ride height, pitch, roll, and tire load targets. |
| Chassis | Must provide mounting structure for aero loads and keep stiffness adequate. |
| Powertrain | Drag affects acceleration and top speed; cooling design interacts with aero. |
| Vehicle Dynamics | Uses sim outputs to understand balance, tire use, and event performance. |
| Controls / Data | Needs logged data to validate speed, acceleration, gear, and position traces. |
| Drivers | Must confirm the predicted balance is usable and confidence-building. |
| Manufacturing | Must build components to the required stiffness, weight, and surface quality. |

Potential conflicts:

- More downforce may require heavier mounts.
- More front aero may improve cornering but hurt stability if not balanced.
- More rear wing may improve rear stability but increase drag.
- Diffuser performance may require ride-height control that suspension cannot provide.
- Cooling exits may reduce rear aero performance.

## Model Assumptions

### Track Layout Assumptions

- The endurance and autocross tracks are represented by coordinate files.
- The car follows a saved racing line through the gates.
- The racing line is treated as repeatable and driver-achievable.
- Track surface, bumps, camber, cone risk, and driver inconsistency are not directly modeled.
- The autocross coordinate file currently has 40 valid gates, while the saved autocross racing line has 48 positions. The sim trims to the valid 40 gates. This should be corrected by regenerating the autocross racing line.

### Constant Assumptions That Are Not Fully True In Reality

The following quantities are treated as constant or simplified even though they vary on the real car:

| Quantity | Sim Treatment | Real-World Behavior |
|---|---|---|
| `CL` | Constant target | Changes with speed, yaw, ride height, pitch, roll, steering, and aero interaction. |
| `CD` | Constant target | Changes with yaw, cooling flow, wheel wake, ride height, and aero setup. |
| CoP | Constant front percentage | Moves with speed, pitch, roll, yaw, and component stall. |
| Tire scale factors | Global constants | Change with temperature, pressure, wear, surface, and normal load. |
| Driver behavior | Idealized path following | Real drivers vary braking, turn-in, apex, throttle, and risk margin. |
| Track grip | Constant through event | Changes with surface, temperature, dust, water, and rubbering. |
| Vehicle mass | Fixed | Changes with fuel, driver, ballast, and hardware revisions. |
| Power delivery | Based on torque curve | Real delivery depends on transient engine behavior and drivetrain losses. |

These assumptions are acceptable for comparative target selection, but they should be reduced through validation.

### Tire And Vehicle Dynamics Assumptions

- Tire behavior is based on the loaded tire models.
- Longitudinal and lateral tire scale factors are calibration values.
- Load transfer is simplified.
- Pitch and aero ride-height effects are simplified.
- The GGV envelope is based on quasi-static limits.
- The lap integrator approximates combined acceleration and cornering.

### Aero Component Assumptions

- The sim does not know whether downforce came from the front wing, rear wing, diffuser, or bodywork.
- Component split must be chosen by aero design judgement and later checked with CFD or testing.
- The component budgets in this report are starting targets, not final proof of component performance.

## Benefits Of Using This Lap Sim

### 1. It Creates A Reason For Aero Targets

The biggest benefit is traceability. Instead of saying:

```text
We used this CoP because a previous car used it.
```

the team can say:

```text
We selected this target because the sweep showed that this region improved predicted total dynamic points while maintaining acceptable acceleration, autocross, and endurance performance.
```

### 2. It Compares Designs By Competition Result

An aero package with more downforce is not automatically better. If it creates too much drag or poor balance, it can score worse. The sim evaluates the total effect.

### 3. It Supports Early Design Decisions

Before final CFD or manufacturing, the team can use the sim to decide:

- how much downforce is worth pursuing
- how much drag is acceptable
- what front/rear balance is worth targeting
- how much adjustability is needed
- which event is driving the design

### 4. It Makes Parallel Trade Studies Practical

Each aero case is independent, so the Parallel Computing Toolbox can run multiple cases at once. This makes broad sweeps realistic on the M3 Max and still usable on a Windows PC with Parallel Computing Toolbox.

### 5. It Creates A Validation Path

The sim now generates telemetry-style outputs that can be compared to real data. This makes it possible to improve the model instead of simply trusting it.

## Risks And Mitigations

| Risk | Effect | Mitigation |
|---|---|---|
| Sim coefficients are not CFD coefficients | Wrong physical target if copied directly | Convert/correlate force coefficients before final aero release. |
| Constant aero over-simplifies behavior | Missed stall/yaw/ride-height sensitivity | Add aero maps after CFD or test data exists. |
| Unconstrained aero target is physically impossible | Unrealistic CL/CD recommendation | Use feasibility limits for downforce, drag, and L/D before selecting design goals. |
| CoP target overfit to one result | Bad real balance | Validate `0.450` to `0.525` with real data and adjustable aero. |
| Racing line mismatch | Incorrect autocross estimate | Regenerate autocross racing line from current coordinates. |
| Tire scaling uncalibrated | Wrong absolute lap times | Fit `sf_x` and `sf_y` to logged accel, braking, and skidpad data. |
| Mounts too flexible | Actual aero lower or unstable | Include stiffness targets and test deflection under load. |

## Recommended Next Steps

### Before Design Freeze

1. Regenerate `autocross_racing_line.mat` to match the current 40-gate autocross coordinate file.
2. Refine the 90-135 lbf downforce window, 40-65 lbf drag window, and L/D 2.0-2.4 feasibility window with measured or CFD-backed values.
3. Run a larger accurate rerun around the feasible region:
   - `CL = 0.040` to `0.080`
   - `CD = 0.015` to `0.030`, filtered to keep L/D near 2.2
   - `CoP = 0.450` to `0.525`
4. Create component CFD concepts that can hit the target load split.
5. Check if the physical aero package can be made adjustable from roughly 47.5 percent to 52.5 percent front aero balance.
6. Validate the baseline car against logged acceleration, skidpad, and autocross data.

### During Aero Design

1. Track component-level downforce and drag at 35, 45, and 60 mph equivalent conditions.
2. Convert CFD forces into the lap-sim force scale.
3. Update the lap sim with component-level or ride-height-dependent aero maps.
4. Rerun the sweep when mass, powertrain, suspension, or tire assumptions change.

### During Testing

1. Run baseline aero configuration.
2. Run front-balance adjustment tests.
3. Run rear-wing angle or element adjustment tests.
4. Compare speed, Ax, Ay, gear, and distance traces to sim.
5. Update tire scaling and aero targets based on measured data.

## Recommended Presentation Position

The recommended position for design review is:

```text
T27 should not inherit aero targets from previous cars without justification.
The lap sim provides a scoring-based reason for selecting aero goals.
The unconstrained sim result asks for far more downforce and efficiency than we believe is physically realistic, so it should not be used directly as a design target.
With the current CUFSAE-based feasibility limits, the defensible nominal starting target is about CL=0.045, CD=0.020, and CoP near 47.5 percent front, while preserving adjustability from roughly 45 percent to 52.5 percent front for validation. This keeps the target near 119 lbf downforce, 53 lbf drag, and L/D about 2.25 at 35 mph.
```

## Appendix A: Key Equations

```text
Total Downforce = CL_target * V^2
Total Drag      = CD_target * V^2
Front Downforce = Total Downforce * CoP_target
Rear Downforce  = Total Downforce * (1 - CoP_target)
```

where:

- `V` is speed in ft/s
- forces are in lbf
- `CoP_target` is front aero distribution

## Appendix B: Current Data-Based Target Summary

| Target Type | CL | CD | CoP | Reason |
|---|---:|---:|---:|---|
| Baseline/current estimate | 0.080 | 0.020 | 0.450 | Starting comparison point, but predicts about 211 lbf at 35 mph and may exceed realistic downforce. |
| Unconstrained mathematical winner | 0.160 | 0.010 | 0.475 to 0.525 | Highest points, but predicts about 422 lbf at 35 mph and L/D up to 16. Not realistic without proof. |
| Recommended feasible nominal target | 0.045 | 0.020 | 0.475 | About 119 lbf downforce, 53 lbf drag, and L/D 2.25 at 35 mph. |
| Feasible sweep range | 0.034 to 0.051 | about 0.016 to 0.030, filtered by L/D | 0.450 to 0.525 | Based on 90-135 lbf downforce, 40-65 lbf drag, and L/D around 2.2 at 35 mph. |

## Appendix C: Short Verbal Defense

This lap sim gives us an engineering reason for aero targets instead of copying previous-year values, but it also shows why feasibility limits matter. The unconstrained model wants CL and CD values that produce about 422 lbf at 35 mph with L/D near 16, which is not realistic for our current car. After applying CUFSAE-based feasibility limits, a more defensible starting point is about CL=0.045, CD=0.020, and CoP around 47.5 percent front. The exact caps should be replaced with measured or CFD-backed CUFSAE values, then validated with speed, acceleration, lateral g, gear, and distance data from the real car.

