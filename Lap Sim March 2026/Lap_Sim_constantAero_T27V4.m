% function [Total_Points,Accel_Score,Skidpad_Score,Autocross_Score,Endurance_Score,skidpad_time,AY_max,AX_max,AX_min,distance_ax,acceleration_ax,lateral_accel_ax,velocity_ax,weights_ax,vehicle_path_AX,time_elapsed_ax,brakeResults,accResults,latResults] = Lap_Sim_fminconSp26(pg)
if ~exist('T27_NO_CLEAR','var') || ~T27_NO_CLEAR
    clear
end
% The purpose of this code is to evaluate the points-scoring capacity of a
% virtual vehicle around the 2019 FSAE Michigan Dynamic Event Tracks

%% Section 0: Name all symbolic variables
% Don't touch this. This is just naming a bunch of variables and making
% them global so that all the other functions can access them
global r_max accel grip deccel lateral cornering gear shift_points...
    top_speed r_min path_boundaries tire_radius shift_time...
    powertrainpackage track_width path_boundaries_ax

% Batch/sweep runners set these before calling this script. These defaults
% keep the file usable as a normal one-off MATLAB script.
if ~exist('T27_SWEEP_ACTIVE','var'); T27_SWEEP_ACTIVE = false; end
if ~exist('T27_PARALLEL_ACTIVE','var'); T27_PARALLEL_ACTIVE = false; end
if ~exist('T27_FAST_MODE','var'); T27_FAST_MODE = false; end
if ~exist('T27_PLOT_RESULTS','var'); T27_PLOT_RESULTS = true; end
if ~exist('T27_velocityStep','var') || isempty(T27_velocityStep); T27_velocityStep = 1; end
if ~exist('T27_radiiStep','var') || isempty(T27_radiiStep); T27_radiiStep = 5; end
if ~exist('T27_lateralStep','var') || isempty(T27_lateralStep); T27_lateralStep = 0.10; end
if ~exist('T27_WRITE_OUTPUTS','var'); T27_WRITE_OUTPUTS = ~T27_PARALLEL_ACTIVE; end
if ~exist('T27_EXPORT_VALIDATION','var'); T27_EXPORT_VALIDATION = T27_WRITE_OUTPUTS; end
%% Section 1: Input Tire Model
% this section is required, everything should be pre-loaded so no need to
% touch any of this, unless you want to change the tire being evaluated.
% The only things you might want to change are the scaling factors at the
% bottom of the section
disp('2019 Michigan Endurance Points Analysis')
disp('Loading Tire Model')

% First we load in the lateral tire force model, which is a CSAPS cubic
% spline interpolation fit to TTC data
% make sure these files are already in your directory

% filename = 'Hoosier_LCO_16.0x7.5-10_FY_10psi';
% filename = 'Hoosier R20 16x7.5-10 10 Psi FY.mat';
% load(filename)

% First we load in the lateral tire force model, which is a Pacejka model
% created by derek:
global FZ0 LFZO LCX LMUX LEX LKX  LHX LVX LCY LMUY LEY LKY LHY LVY ...
    LGAY LTR LRES LGAZ LXAL LYKA LVYKA LS LSGKP  LSGAL LGYR KY
load('A2356run008_MF52_Fy_12.mat')
% then load in coefficients for Magic Formula 5.2 Tire Model:
load('A2356run008_MF52_Fy_GV12.mat')

% Next you load in the longitudinal tire model, which is a
% CSAPS spline fit to the TTC data
% find your pathname and filename for the tire you want to load in

% filename = 'Hoosier_LCO_18.0x6.0-10_FX_10psi';
filename = 'Hoosier R20 18x6.0-10 10 Psi FX.mat';
load(filename)
tire_radius = 8.05/12; %ft
tyreRadius = tire_radius/3.28; % converts to meters

% finally, we have some scaling factors for longitudinal (x) and lateral
% (y) friction. You can use these to tune the lap sim to correlate better
% to logged data.
% Alternatively, fitting constraints to tyre utilisation may better
% represent the problem. Consider constraining the instantaneous cornering
% stiffness (Fy/alpha curve) against the "on center" cornering stiffness
% i.e. cornering stiffness at 0 slip. This makes the solver more stable
% as it doesn't change sign of cornering stiffness past peak FY


sf_x = 0.45;
sf_y = 0.5;
%% Section 2: Input Powertrain Model
% Provide vectors of engine torque against rpm (engineTQ and engineRPM)
% and the RPMs to interpolate against (engineSpeed). This should be strict
% interpolation, i.e:

% min(engineRPM) <= min(engineSpeed) < max(engineSpeed) <= max(engineRPM)
disp('Loading Engine Model')

% torque should be in N-m:
redline = 15000;
engineSpeed = [6000:100:redline]; % RPM
engineTq = [36.48501	38.59397	44.32983	46.28545	47.887875	49.829956	51.228146	51.03791	51.292057	51.900978	52.434673	52.499348	51.684544	50.131496	49.159187	48.94724	49.628212	50.57417	51.357998	51.728046	51.37902	50.64954	49.651802	48.46732	47.18437	44.13004	40.682053	36.252777];
engineRPM = [4000.0	5000.0	6000.0	7000.0	7500.0	8000.0	8500.0	9000.0	9500.0	9750.0	10000.0	10250.0	10500.0	10750.0	11000.0	11250.0	11500.0	11750.0	12000.0	12250.0	12500.0	12750.0	13000.0	13250.0	13500.0	14000.0	14500.0	15000.0];
engineTq = pchip(engineRPM, engineTq, engineSpeed);
% gearing. This is self explanatory
primaryReduction = 76/36;
gear = [33/12, 32/16, 30/18, 26/18, 30/23, 29/24]; % transmission gear ratios
finalDrive = 32/12; % large sprocket/small sprocket

% this is a script to calculate the optimal shift points by gear
% there's been many threads on how you do this on slack.

shiftpoints = calc_shiftpoints(finalDrive, gear, engineTq, redline, primaryReduction, tyreRadius, engineSpeed);

% keep these current
drivetrainLosses = .80; % percent of torque that makes it to the rear wheels
shift_time = .075; % seconds

% the diff model is just ok. leave it open for most uses imo. big place for
% future development
T_lock = 80; % differential locking torque (0 =  open, 100 = locked)

% Intermediary Calcs/Save your results into the workspace
gearTot = gear(end)*finalDrive*primaryReduction;
VMAX = floor(3.28*redline/(gearTot/tyreRadius*60/(2*pi)));
T_lock = T_lock/100;
powertrainpackage = {engineSpeed engineTq primaryReduction gear finalDrive shiftpoints drivetrainLosses};
%% Section 3: Vehicle Architecture
disp('Loading Vehicle Characteristics')
% These are the basic vehicle architecture primary inputs:
LLTD = 38; % Front lateral load transfer distribution (%)
W = 450+130; % vehicle + driver weight (lbs)
WDF = 47.4; % front weight distribution (%)
cg = 12.2/12; % center of gravity height (ft)
l = 60.5/12; % wheelbase (ft)
track_width = 46.5;
twf = 47/12; % front track width (ft)
twr = 46/12; % rear track width (ft)

% some intermediary calcs you don't have to touch
LLTD = LLTD/100;
WDF = WDF/100;
m = W/32.2; % mass (lbm)
WF = W*WDF; % front weight
WR = W*(1-WDF); % rear weight
a = l*(1-WDF); % front axle to cg
b = l*WDF; % rear axle to cg
tw = twf;
%% Section 4: Input Suspension Kinematics
disp('Loading Suspension Kinematics')
% this section is actually optional. So if you set everything to zero, you
% can essentially leave this portion out of the analysis. Useful if you are
% only trying to explore some higher level relationships
% Room for improvement is hooking up any of the various kinematic tools to
% calculate these as functions of wheel displacements. would need to
% propogate through the model, but e.g. f_IA = @(dx_fl, steer_fl ...) func
% could be used and passed to the GGV solver

% Pitch and roll gradients define how much the car's gonna move around
rg_f = 0.5; % front roll gradient (deg/g)
rg_r = 0.5; % rear roll gradient (deg/g)
pg = 0.5; % pitch gradient (deg/g)

% Anti Geometries
antiDive = 0.1; % Anti-dive [-]
antiLift = 0; % Anti-Lift [-]
antiSquat = 0.35; % Anti-squat [-]
antiRise = 0.1; % Anti-rise [-]
% WRF = 268; % front and rear ride rates [lbs/in]
% WRR = 191.88;

% then you can select your camber alignment
IA_staticf = 0; % front static camber angle (deg)
IA_staticr = 0; % rear static camber angle (deg)

% these are your linear camber gains against vertical displacement
IA_compensationf = 0; % front camber compensation (%)
IA_compensationr = 0; % rear camber compensation (%)

% lastly you can select your kingpin axis parameters
casterf = -3; % front caster angle (deg)
KPIf = 6; % front kingpin inclination angle (deg)
casterr = 17;
KPIr = 10;

% intermediary calcs, plz ignore
IA_staticf = deg2rad(IA_staticf); % front static camber angle (deg)
IA_staticr = deg2rad(IA_staticr); % rear static camber angle (deg)
IA_compensationf = IA_compensationf/100; % front camber compensation (%)
IA_compensationr = IA_compensationr/100; % rear camber compensation (%)
casterf = deg2rad(casterf);
KPIf = deg2rad(KPIf);
casterr = deg2rad(casterr);
KPIr = deg2rad(KPIr);
IA_roll_inducedf = asin(2/twf/12);
IA_roll_inducedr = asin(2/twr/12);
IA_gainf = deg2rad(0);
IA_gainr = deg2rad(0);

% Calculates ride rate to meet set pg
rideRateAccelG = 1;
theta = rideRateAccelG*pg;
dx = l*tand(theta);
LLT = (cg/l)*W*rideRateAccelG;
kr = LLT/dx;
kRF = kr;
kRR = kr;
%% Section 5: Input Aero Parameters
disp('Loading Constant Aero Targets')

% -------------------------------------------------------------------------
% T27 AERO TARGET STUDY INPUTS
% -------------------------------------------------------------------------
% Use this section instead of the ride-height aero map when you want to test
% simple CL, CD, and CoP targets. Run the lap sim once, change the numbers
% below, and run again. Higher Total_Points = better competition result.
%
% NOTE: This lap sim uses CL and CD as force coefficients in the form:
%       Downforce = CL_target * V^2
%       Drag      = CD_target * V^2
% where V is in ft/s and force is in lbf. These are NOT necessarily CFD
% nondimensional coefficients unless your old aeroMapfn used the same units.
%
% CoP_target is front aero distribution as a decimal:
%       0.45 = 45% of downforce on front axle, 55% rear
% -------------------------------------------------------------------------
if ~exist('CL_target','var') || isempty(CL_target); CL_target = 0.040; end   % lbf/(ft/s)^2, increase for more downforce
if ~exist('CD_target','var') || isempty(CD_target); CD_target = 0.020; end   % lbf/(ft/s)^2, increase for more drag
if ~exist('CoP_target','var') || isempty(CoP_target); CoP_target = 0.450; end % front aero distribution, 0 to 1

% Optional label so logged results are easier to compare between runs
if ~exist('aeroTag','var') || isempty(aeroTag)
    aeroTag = sprintf('CL_%0.3f_CD_%0.3f_CoP_%0.3f',CL_target,CD_target,CoP_target);
end

% Set static ride heights. These are kept only so the rest of the existing
% functions still receive the same inputs. With constant aero, RH does not
% change the aero numbers.
RHfi = 1.5;   % front static ride height [in]
RHri = 1.75;  % rear static ride height [in]

% Constant function handles avoid the scatteredInterpolant overhead in the
% tight fmincon loops while keeping aeroMapfn's call signature unchanged.
fnCl  = @(~,~) CL_target;
fnCd  = @(~,~) CD_target;
fnCoP = @(~,~) CoP_target;

%% Section 6: Generate GGV Diagram
% this is where the m e a t of the lap sim takes place. The GGV diagram is
% built by finding a maximum cornering, braking, and acceleration capacity
% for any given speed

disp('Generating g-g-V Diagram')

deltar = 0;
deltaf = 0;
if T27_FAST_MODE
    velocityStep = T27_velocityStep;
    radiiStep = T27_radiiStep;
    lateralSearchStep = T27_lateralStep;
else
    velocityStep = 1;
    radiiStep = 5;
    lateralSearchStep = 0.10;
end
velocity = 0:velocityStep:VMAX; % range of velocities at which sim will evaluate (ft/s)
if velocity(end) ~= VMAX
    velocity = [velocity VMAX];
end
radii = 15:radiiStep:155; % range of turn radii at which sim will evaluate (ft)

% First we will evaluate our Acceleration Capacity
g = 1; % g is a gear indicator, and it will start at 1
spcount = 1; % spcount is keeping track of how many gearshifts there are
% shift_points tracks the actual shift point velocities
shift_points(1) = 0;
nVel = numel(velocity);
slAccel = 0:.01:.11;
A_xr = zeros(1,nVel);
A_Xr = zeros(1,nVel);
fx = zeros(1,nVel);
gearSelection = zeros(1,nVel);
RH = zeros(nVel,2);
DFs = zeros(nVel,2);
pitches = zeros(nVel,1);
CoPs = zeros(nVel,1);
Cls = zeros(nVel,1);
Cds = zeros(nVel,1);
Vs = zeros(nVel,1);
disp('     Acceleration Envelope')
tic
for  i = 1:1:length(velocity) % for each velocity
    gp = g; % Current gear = current gear (wow!)
    V = velocity(i); % find velocity
    dxf = 0;
    dxr = 0;
    % Calculate downforce and susp disp
    [DFf,DFr,RHf,RHr,Cl,Cd,CoP,dxf,dxr] = aeroMapfn(fnCl,fnCoP,fnCd,RHfi,RHri,V,kRF,kRR,dxf,dxr);
    % from rh drop, find camber gain (deg)
    IA_0f = IA_staticf - dxf*IA_gainf;
    IA_0r = IA_staticr - dxr*IA_gainr;
    % find load on each tire (lbs)
    wf = (WF+DFf)/2;
    wr = (WR+DFr)/2;

    % now we actually sweep through with acceleration
    Ax = 0; % starting guess of zero g's
    WS = W/2; % weight of one half-car
    pitch = -Ax*pg*pi/180; % pitch angle (rad)
    % recalculate wheel loads due to load transfer (lbs)
    wf = wf-Ax*cg*WS/l;
    wr = wr+Ax*cg*WS/l;
    % recalculate camber angles due to pitch
    IA_f = -l*12*sin(pitch)/2*IA_gainf + IA_0f;
    IA_r = l*12*sin(pitch)/2*IA_gainr + IA_0r;
    % IA_f = 0;
    % IA_r = 0;
    % evaluate the tractive force capacity from each tire for the range of
    % slip ratios
    FXF = evalLongitudinalTireLimit(full_send_x, slAccel, wf, IA_f, sf_x, "max");
    FXR = evalLongitudinalTireLimit(full_send_x, slAccel, wr, IA_r, sf_x, "max");
    % find max force capacity from each tire:
    % Calculate total tire tractive force (lbs)
    FX = abs(2*FXR);
    % calculate total lateral acceleration capacity (g's)
    AxLimit = FX/W;
    AX_diff = AxLimit-Ax;
    while AX_diff>0
        %disp([Ax AxLimit])
        Ax = Ax+.01;
        WS = W/2;
        pitch = -Ax*pg*pi/180;
        dx = ((l*12)/2)*tan(pitch); % assumes pitch center is perfectly centered on car and no pitch center migration
        % dxf = dxf0+dx;
        % dxr = dxr0-dx;
        wf = WF-Ax*cg*WS/l/24;
        wr = WR+Ax*cg*WS/l/24;
        dxf = dx-(dx*antiLift);
        dxr = -dx+(dx*antiSquat);
        [DFf,DFr,RHf,RHr,Cl,Cd,CoP,dxf,dxr] = aeroMapfn(fnCl,fnCoP,fnCd,RHfi,RHri,V,kRF,kRR,dxf,dxr);
        wf = (wf+DFf)/2;
        wr = (wr+DFr)/2;
        IA_f = -l*12*sin(pitch)/2*IA_gainf + IA_0f;% - KPIf*(1-cos(deltaf)) + casterf*sin(deltaf);
        IA_r = l*12*sin(pitch)/2*IA_gainr + IA_0r;% - KPIr*(1-cos(deltar)) + casterf*sin(deltar);
        IA_f = 0;
        IA_r = 0;
        FXF = evalLongitudinalTireLimit(full_send_x, slAccel, wf, IA_f, sf_x, "max");
        FXR = evalLongitudinalTireLimit(full_send_x, slAccel, wr, IA_r, sf_x, "max");
        FX = abs(2*FXR);
        AxLimit = FX/W;
        AX_diff = AxLimit-Ax;
    end
    A_xr(i) = AxLimit;
    output = Powertrainlapsim(max(7.5,V/3.28)); % 7.5 reg, 10 launch
    FX = output(1)*.2248;
    FX = FX-Cd*V^2;
    fx(i) = FX/W;
    A_Xr(i) = min(FX/W,A_xr(i));
    output = Powertrainlapsim(V/3.28);
    g = output(2);
    gearSelection(i) = g;
    if g>gp
        spcount = spcount+1;
        shift_points(spcount) = V;
    end
    RH(i,:) = [RHf,RHr]; DFs(i,:) = [DFf,DFr]; pitches(i) = pitch/(pi/180); Vs(i) = V; CoPs(i) = CoP; Cls(i) = Cl; Cds(i) = Cd;
end
A_Xr(A_Xr < 0) = 0;
toc

% Log Accel Results:
AXr = A_Xr';
VEL = velocity';
fx = fx';
%Cls = Cls';
%DFs = DFs';
%FZFs = FZFs';
%FZRs = FZRs';
accResults = table(VEL,AXr,fx,RH,DFs,pitches,CoPs,Cls,Cds);

% from these results, you can create the first part of the GGV diagram
% input for the lap sim codes:
% accel is the maximum acceleration capacity as a function of velocity
% (power limited) and grip is the same but (tire limited)
accel = csaps(velocity,A_Xr);
grip = csaps(velocity,A_xr);

%% Lateral Acceleration

nRadii = numel(radii);
Rs = nan(1,nRadii);
steering = nan(1,nRadii);
speed = nan(1,nRadii);
lateralg = nan(1,nRadii);
USangle = nan(1,nRadii);
Ugradient = nan(1,nRadii);
betas = nan(1,nRadii);
afs = nan(1,nRadii);
ars = nan(1,nRadii);
Car = nan(1,nRadii);
Car0 = nan(1,nRadii);
CoPs = nan(1,nRadii);
Cls = nan(1,nRadii);
Cds = nan(1,nRadii);

% Next we explore the cornering envelope. First we define AYP, which is the
% starting guess for lateral acceleration capacity at a given speed
V_guess = 1;
tol = 1e-2;
step = lateralSearchStep;
res= [];
nCa = 0.1; % On-center Cornering Stiffness Constraint Coefficient [-]
options = optimoptions('fmincon', 'Display', 'none');
disp('     Cornering Envelope')


% for cornering performance, it makes more sense to evaluate a set of
% cornering radii, instead of speeds
x_prev = [0, 0];    %initial guess for f solve
tic
for turn = 1:1:length(radii)
    R = radii(turn);
    V = V_guess;
    cond = 0;
    fini = 0;
    x_prev = [atan(l/R), x_prev(2)];    %initial guess for f solve

    while cond == 0
        % x(1) = delta - Steering Angle [rad]
        % x(2) = beta - CG (Chassis) Slip Angle [rad]

        % lower and upper bounds on inputs
        % [delta, belta]
        % set these to something reasonable
        lb = [deg2rad(-20), deg2rad(-10)];
        ub = [deg2rad(25), deg2rad(10)];

        % This version of lat_solve utilizes fmincon to find the *best* solution to
        % the system by treating the system as a constrained nonlinear
        % multivariable function, and minimizing the objective, J, given by the
        % weighted objective function. You can think of the objective as the
        % total magnitude of all residuals combined.
        %
        % This is superior to the original implementation of lat_solve with fsolve
        % in that you can enforce constraints to encourage continuity (no jumping
        % between roots)
        %
        % In classic CUFSAE fashion, much of this was learned and developed with
        % the help of ChatGPT with limited sleep, so this may not be the most
        % robust.
        %
        % - Geter, '24-26 Sus Lead
        nonlcon = @(x) cAlpha_nonlcon(x, V, a, b, l, WDF, R, IA_staticf, IA_gainf, IA_staticr, IA_gainr, WF, WR, twf, twr, cg, W, LLTD, rg_f, rg_r, casterf, casterr, deltar, sf_y, A, grip, Cd, T_lock, KPIf, KPIr,fnCl,fnCoP,fnCd,RHfi,RHri,kRF,kRR,dxf,dxr,x_prev,nCa);
        obj = @(x) lat_objective(x, V, a, b, l, WDF, R, IA_staticf, IA_gainf, IA_staticr, IA_gainr, WF, WR, twf, twr, cg, W, LLTD, rg_f, rg_r, casterf, casterr, deltar, sf_y, A, grip, Cd, T_lock, KPIf, KPIr,fnCl,fnCoP,fnCd,RHfi,RHri,kRF,kRR,dxf,dxr,x_prev);
        [x, Jval, exitflag] = fmincon(obj, x_prev, [], [], [], [], lb, ub, nonlcon, options);
        fval = lat_solve(x, V, a, b, l, WDF, R, IA_staticf, IA_gainf, IA_staticr, IA_gainr, WF, WR, twf, twr, cg, W, LLTD, rg_f, rg_r, casterf, casterr, deltar, sf_y, A, grip, Cd, T_lock, KPIf, KPIr,fnCl,fnCoP,fnCd,RHfi,RHri,kRF,kRR,dxf,dxr);
        res(1) = fval(1)/W;
        res(2) = fval(2)/((W*WDF)*(l*(1-WDF)));
        % if lat_solve fails, exit loop
        if exitflag < 1 || any(abs(res) > tol)
            cond = -1;
            % Retry with a neutral initial guess instead of the warm-start
            % x_retry = [atan(l/R), 0];
            % [x2, jval2, exitflag2] = fmincon(obj, x_retry, [], [], [], [], lb, ub, [], options);
            % fval2 = lat_solve(x2, V, a, b, l, WDF, R, IA_staticf, IA_gainf, IA_staticr, IA_gainr, WF, WR, twf, twr, cg, W, LLTD, rg_f, rg_r, casterf, casterr, deltar, sf_y, A, grip, Cd, T_lock, KPIf, KPIr,fnCl,fnCoP,fnCd,RHfi,RHri,kRF,kRR,dxf,dxr);
            %
            % if exitflag2 >= 1 && all(abs(fval2) <= tol)
            %     x = x2;
            %     cond = 0;  % accept the retry solution
            %     x_prev = x;
            %     fval = fval2;
            % else
            %     cond = -1;
            % end
        end

        % Increase V and continue solving (restart loop)
        if cond == 0
            x_prev = x;   %save good solution before stepping V
            V = V + step;
            fini = 1;
            % if cond = -1, perform final solve and exit the loop
        else
            V = V - step;
            nonlcon = @(x) cAlpha_nonlcon(x, V, a, b, l, WDF, R, IA_staticf, IA_gainf, IA_staticr, IA_gainr, WF, WR, twf, twr, cg, W, LLTD, rg_f, rg_r, casterf, casterr, deltar, sf_y, A, grip, Cd, T_lock, KPIf, KPIr,fnCl,fnCoP,fnCd,RHfi,RHri,kRF,kRR,dxf,dxr,x_prev,nCa);
            obj = @(x) lat_objective(x, V, a, b, l, WDF, R, IA_staticf, IA_gainf, IA_staticr, IA_gainr, WF, WR, twf, twr, cg, W, LLTD, rg_f, rg_r, casterf, casterr, deltar, sf_y, A, grip, Cd, T_lock, KPIf, KPIr,fnCl,fnCoP,fnCd,RHfi,RHri,kRF,kRR,dxf,dxr,x_prev);
            [x, Jval, exitflag] = fmincon(obj, x_prev, [], [], [], [], lb, ub, nonlcon, options);
            fval = lat_solve(x, V, a, b, l, WDF, R, IA_staticf, IA_gainf, IA_staticr, IA_gainr, WF, WR, twf, twr, cg, W, LLTD, rg_f, rg_r, casterf, casterr, deltar, sf_y, A, grip, Cd, T_lock, KPIf, KPIr,fnCl,fnCoP,fnCd,RHfi,RHri,kRF,kRR,dxf,dxr);
            % fprintf('\nFy Residual: %0.6f', res(1))
            % fprintf('\nMz Residual: %0.6f', res(2))


            % INTERMEDIATE CALCS FOR RECORDING RESULTS. PLEASE IGNORE!!!!
            delta = x(1); beta = x(2);
            AY = V^2 / R;
            r = AY/V;
            a_f = beta+a*r/V-delta;
            a_r = beta-b*r/V;
            B = rad2deg(beta);
            af = rad2deg(a_f);
            ar = rad2deg(a_r);

            % First, calculate slip angle, Fz, and IA
            a = l*(1-WDF);
            b = l*WDF;

            dxf = 0;
            dxr = 0;

            % update downforce
            [DFf,DFr,RHf,RHr,Cl,Cd,CoP,dxf,dxr] = aeroMapfn(fnCl,fnCoP,fnCd,RHfi,RHri,V,kRF,kRR,dxf,dxr);
            % from suspension heave, update static camber (rad):
            IA_0f = IA_staticf - dxf*IA_gainf;
            IA_0r = IA_staticr - dxr*IA_gainr;
            % update load on each axle (lbs)
            wf = (WF+DFf)/2;
            wr = (WR+DFr)/2;

            A_y = V^2/R;
            % calculate lateral load transfer (lbs)
            WT = A_y*cg*W/mean([twf twr])/32.2;
            % split f/r using LLTD
            WTF = WT*LLTD;
            WTR = WT*(1-LLTD);
            % calculate f/r roll (rad)
            phif = A_y*rg_f*pi/180/32.2;
            phir = A_y*rg_r*pi/180/32.2;
            % update individual wheel loads
            wfin = wf-WTF;
            wfout = wf+WTF;
            wrin = wr-WTR;
            wrout = wr+WTR;


            % update individual wheel camber (from roll, then from steer
            % effects)
            % IA_f_in = -twf*sin(phif)*12/2*IA_gainf - IA_0f - KPIf*(1-cos(delta)) - casterf*sin(delta) +phif;
            % IA_f_out = -twf*sin(phif)*12/2*IA_gainf + IA_0f + KPIf*(1-cos(delta)) - casterf*sin(delta) + phif;
            % IA_r_in = -twr*sin(phir)*12/2*IA_gainr - IA_0r - KPIr*(1-cos(deltar)) - casterr*sin(deltar) +phir;
            % IA_r_out = -twr*sin(phir)*12/2*IA_gainr + IA_0r + KPIr*(1-cos(deltar)) - casterr*sin(deltar) + phir;
            IA_f_in = 0;
            IA_f_out = 0;
            IA_r_in = 0;
            IA_r_out = 0;
            % calculate yaw rate
            r = A_y/V;
            % from yaw, sideslip and steer you can get slip angles
            a_f = beta+a*r/V-delta;
            a_r = beta-b*r/V;
            % with slip angles, load and camber, calculate lateral force at
            % the front
            F_fin = -MF52_Fy_fcn(A,[-rad2deg(a_f) wfin -rad2deg(IA_f_in)])*sf_y*cos(delta);
            F_fout = MF52_Fy_fcn(A,[rad2deg(a_f) wfout -rad2deg(IA_f_out)])*sf_y*cos(delta);

            % before you calculate the rears, you ned to see what the diff is
            % doing
            % calculate the drag from aero and the front tires
            F_x = Cd*V^2 + (F_fin+F_fout)*sin(delta)/cos(delta);
            % calculate the grip penalty assuming the rears must overcome that
            % drag
            longitudinalGrip = max(fnval(grip,V), eps);
            rscale = max(0, 1-(F_x/W/longitudinalGrip)^2);
            
            
            dAlpha = 0.05; % small pertubation in slip angle [deg]

            ar1 = rad2deg(a_r)-dAlpha;
            ar2 = rad2deg(a_r)+dAlpha;

            Fy1 = MF52_Fy_fcn(A,[ar1,wrout,-rad2deg(IA_r_out)])*sf_y*rscale + MF52_Fy_fcn(A,[ar1,wrin,-rad2deg(IA_r_in)])*sf_y*rscale;
            Fy2 = MF52_Fy_fcn(A,[ar2,wrout,-rad2deg(IA_r_out)])*sf_y*rscale + MF52_Fy_fcn(A,[ar2,wrin,-rad2deg(IA_r_in)])*sf_y*rscale;

            C_ar = (Fy2-Fy1)./(2*dAlpha); % Local Cornering Stiffness [lb/deg]

            %Compare to on-center cornering stiffness:
            ar1_0 = -dAlpha;
            ar2_0 = dAlpha;

            Fy1_0 = MF52_Fy_fcn(A,[ar1_0,wrout,-rad2deg(IA_r_out)])*sf_y*rscale + MF52_Fy_fcn(A,[ar1_0,wrin,-rad2deg(IA_r_in)])*sf_y*rscale;
            Fy2_0 = MF52_Fy_fcn(A,[ar2_0,wrout,-rad2deg(IA_r_out)])*sf_y*rscale + MF52_Fy_fcn(A,[ar2_0,wrin,-rad2deg(IA_r_in)])*sf_y*rscale;

            C_ar0 = (Fy2_0-Fy1_0)./(2*dAlpha); % On-center Cornering Stiffness [lb/deg]
            c = C_ar - nCa*C_ar0;   % must be <= 0

            % steer = rad2deg(delta);
            steer = rad2deg(delta);
            UG = rad2deg(delta-l/R)*32.2/AY;
            USa = rad2deg(delta-l/R);
            USangle(turn) = USa;
            Ugradient(turn) = UG;
            %F_lat = fnval([rad2deg(a_f);-wf;0],full_send_y)*.45*cos(delta);
            %F_drag = fnval([rad2deg(a_f);-wf;0],full_send_y)*.45*sin(delta);
            skid = 2*pi*R/V;
            steering(turn) = steer;
            speed(turn) = V;
            lateralg(turn) = AY/32.2;
            Rs(turn) = R;
            trn(turn) = turn;
            afs(turn) = af;  
            ars(turn) = ar;
            betas(turn) = B;
            Car(turn) = C_ar;
            Car0(turn) = C_ar0;
            CoPs(turn) = CoP;
            Cls(turn) = Cl;
            Cds(turn) = Cd;
        end
    end
    % initial guess for next turning radius
    % can do this more intelligently???
    V_guess = V;
end
latResults = table(Rs',steering',speed',lateralg',USangle',betas',afs',ars',Car',Car0',CoPs',Cls',Cds','VariableNames',["Radius","steering","speed","latG","US Angle","Beta","af","ar","C_ar","C_ar0","CoPs","Cls","Cds"]);
toc
% figure;
% plot(Rs,lateralg)
% xlabel('Corner Radii [ft]')
% ylabel('Lateral Acceleration [G]')
% grid on
global latResults_out
latResults_out = latResults;
if T27_PLOT_RESULTS
    figure;
    plot(Rs,steering)
    xlabel('Radii [ft]')
    ylabel('Steering angle [deg]')
end
%% Braking Performance
slBrake = -.15:.01:0;
A_X = zeros(1,nVel);
RH = zeros(nVel,2);
DFs = zeros(nVel,2);
pitches = zeros(nVel,1);
CoPs = zeros(nVel,1);
Cls = zeros(nVel,1);
Cds = zeros(nVel,1);
Vs = zeros(nVel,1);

% velocity = 15:5:VMAX;
disp('     Braking Envelope')
% the braking sim works exactly the same as acceleration, except now all 4
% tires are contributing to the total braking capacity
tic
for  i = 1:1:length(velocity)
    V = velocity(i);
    dxf = 0;
    dxr = 0;
    % Calculate downforce and susp disp
    [DFf,DFr,RHf,RHr,Cl,Cd,CoP,dxf,dxr] = aeroMapfn(fnCl,fnCoP,fnCd,RHfi,RHri,V,kRF,kRR,dxf,dxr);
    IA_0f = IA_staticf - dxf*IA_gainf;
    IA_0r = IA_staticr - dxr*IA_gainr;
    wf = (WF+DFf)/2;
    wr = (WR+DFr)/2;
    Ax = 1;
    WS = W/2;
    pitch = Ax*pg*pi/180;
    wf = wf+Ax*cg*WS/l;
    wr = wr-Ax*cg*WS/l;
    IA_f = -l*12*sin(pitch)/2*IA_gainf + IA_0f;% - KPIf*(1-cos(deltaf)) + casterf*sin(deltaf);
    IA_r = l*12*sin(pitch)/2*IA_gainr + IA_0r;% - KPIr*(1-cos(deltar)) + casterf*sin(deltar);
    IA_f = 0;
    IA_r = 0;
    FXF = evalLongitudinalTireLimit(full_send_x, slBrake, wf, IA_f, sf_x, "min");
    FXR = evalLongitudinalTireLimit(full_send_x, slBrake, wr, IA_r, sf_x, "min");
    FX = abs(2*FXF+2*FXR);
    AxLimit = FX/W;
    AX_diff = AxLimit-Ax;
    while AX_diff>0
        %disp([Ax AxLimit])
        Ax = Ax+.01;
        WS = W/2;
        pitch = Ax*pg*pi/180;
        dx = ((l*12)/2)*tan(pitch);
        % dxf = dxf0+dx;
        % dxr = dxr0-dx;
        dxf = dx-(dx*antiDive);
        dxr = -dx+(dx*antiRise);
        [DFf,DFr,RHf,RHr,Cl,Cd,CoP,dxf,dxr] = aeroMapfn(fnCl,fnCoP,fnCd,RHfi,RHri,V,kRF,kRR,dxf,dxr);
        wf = ((WF+DFf)/2)+(Ax*cg*WS/l/24);
        wr = ((WR+DFr)/2)-(Ax*cg*WS/l/24);
        wf = wf+Ax*cg*WS/l/24;
        wr = wr-Ax*cg*WS/l/24;
        IA_f = -l*12*sin(pitch)/2*IA_gainf + IA_0f;% - KPIf*(1-cos(deltaf)) + casterf*sin(deltaf);
        IA_r = l*12*sin(pitch)/2*IA_gainr + IA_0r;% - KPIr*(1-cos(deltar)) + casterf*sin(deltar);
        IA_f = 0;
        IA_r = 0;
        FXF = evalLongitudinalTireLimit(full_send_x, slBrake, wf, IA_f, sf_x, "min");
        FXR = evalLongitudinalTireLimit(full_send_x, slBrake, wr, IA_r, sf_x, "min");
        FX = abs(2*FXF+2*FXR);
        AxLimit = FX/W;
        AX_diff = AxLimit-Ax;
    end
    % if abs(wf) > 250 || abs(wr) > 250
    %     warning('FZ extrapolating beyond bounds of CSAPS spline \n wf = %0.0f \n wr = %0.0f ',wf,wr)
    % end
    RH(i,:) = [RHf,RHr]; DFs(i,:) = [DFf,DFr]; pitches(i) = pitch/(pi/180); Vs(i) = V; CoPs(i) = CoP; Cls(i) = Cl; Cds(i) = Cd;
    A_X(i) = AxLimit;
end
toc
velocity_y = lateralg.*32.2.*radii;
velocity_y = sqrt(velocity_y);
validLateral = isfinite(velocity_y) & isfinite(lateralg) & isfinite(radii) & velocity_y > 0 & lateralg > 0;
if nnz(validLateral) < 3
    error('Cornering envelope did not produce enough valid points for spline fitting.');
end
velocity_y_fit = velocity_y(validLateral);
lateralg_fit = lateralg(validLateral);
[velocity_y_fit, velOrder] = sort(velocity_y_fit);
lateralg_fit = lateralg_fit(velOrder);
[velocity_y_fit, uniqueVelIdx] = unique(velocity_y_fit, 'stable');
lateralg_fit = lateralg_fit(uniqueVelIdx);
radii_fit = velocity_y_fit.^2./lateralg_fit/32.2;
[radii_fit, radiusOrder] = sort(radii_fit);
corneringVelocity_fit = velocity_y_fit(radiusOrder);
[radii_fit, uniqueRadiusIdx] = unique(radii_fit, 'stable');
corneringVelocity_fit = corneringVelocity_fit(uniqueRadiusIdx);
if numel(velocity_y_fit) < 3 || numel(radii_fit) < 3
    error('Cornering envelope collapsed to too few unique points for spline fitting.');
end

%Log Results:
A_Xt = A_X';
VEL = velocity';
% fx = fx';
%Cls = Cls';
%DFs = DFs';
%CoPs = CoPs
%pitches = pitches
%FZFs = FZFs';
%FZRs = FZRs';
brakeResults = table(VEL,A_Xt,RH,DFs,pitches,CoPs,Cls,Cds);

r_max = max(radii);
spcount = spcount+1;
shift_points(spcount) = V+1;
top_speed = V;
VMAX = top_speed;
tic
% make the rest of your functions for the GGV diagram
% braking as a function of speed
deccel = csaps(velocity,A_X);
% lateral g's as a function of velocity
lateral = csaps(velocity_y_fit,lateralg_fit);
radii = radii_fit;
r_max = max(radii);
% max velocity as a function of instantaneous turn radius
% cornering = csaps(radii,velocity_y);
cornering = fnxtr(csaps(radii, corneringVelocity_fit, 0.99999), 2);

%% Section 7: Load Endurance Track Coordinates
disp('Loading Endurance Track Coordinates')
data = readScaledTrackCoordinates('Endurance_Coordinates_1.xlsx');

% the coordinates are now contained within 'data'. This is a 5 column
% matrix that contains a set of defined 'gates' that the car must mavigate
% through
% Column 1: Gate #
% Column 2: Outside boundary, x coordinate
% Column 3: Outside boundary, y coordinate
% Column 4: Inside boundary, x coordinate
% Column 5: Inside boundary, y coordinate

% sort the data into "inside" and "outside" cones
outside = data(:,2:3);
inside = data(:,4:5);
t = [1:length(outside)];
% define the minimum turn radius of the car
r_min = 4.5*3.28;
r_min = r_min-tw/2;
pp_out = spline(t,outside');
pp_in = spline(t,inside');
path_boundaries = zeros(length(outside),4);

for i = 1:1:length(outside)
    % isolate individual gates
    gate_in = inside(i,:);
    gate_out = outside(i,:);
    % create the line that connects the two cones together
    x1 = gate_in(1);
    x2 = gate_out(1);
    y1 = gate_in(2);
    y2 = gate_out(2);
    % polynomial expression for the line:
    coeff = polyfit([x1, x2], [y1, y2], 1);
    % adjust the width of the gate for the width of the car:
    gate_width = sqrt((x2-x1)^2+(y2-y1)^2);
    path_width = gate_width-tw;
    x_fs = tw/(2*gate_width);
    % update the gate boundaries based on said new width
    x_bound = [min(x1,x2)+x_fs*abs(x2-x1),max(x1,x2)-x_fs*abs(x2-x1)];
    path_boundaries(i,:) = [coeff x_bound];
end
%% Seciton 8: Load Endurance Racing Line
disp('Loading Endurance Racing Line')
xx = load('endurance_racing_line.mat');
xx = xx.endurance_racing_line;
%% Section 9: Optimize Endurance Racing Line
% The pre-loaded racing line should work for most applications; however,
% if you have the need to re-evaluate or generate a new optimized racing
% line, simply un-comment the code below:
% 
% 
% disp('Optimizing Endurance Racing Line')
% A = eye(length(xx));
% b = ones(length(xx),1);
% lb = zeros(1,length(xx));
% ub = ones(1,length(xx));
% options = optimoptions('fmincon',...
% 'Algorithm','sqp','Display','iter','ConstraintTolerance',1e-12);
% options = optimoptions(options,'MaxIter', 10000, 'MaxFunEvals', 1000000,'ConstraintTolerance',1e-12,'DiffMaxChange',.1);
% %
% lap_time_wrapped = @(path_positions) lap_time(path_positions, r_min, r_max, cornering, accel, deccel, lateral, shift_points, shift_time, top_speed);
% track_curvature_wrapped = @(path_positions) track_curvature(path_positions, track_width);
% %
% x = fmincon(lap_time_wrapped,xx,[],[],[],[],lb,ub,track_curvature_wrapped,options);
% xx = x;
% x(end+1) = x(1);
% x(end+1) = x(2);
% 
% endurance_racing_line = xx;
% save("endurance_racing_line.mat","endurance_racing_line");
%% Section 10: Generate Final Endurance Trajectory
x = xx;
% Plot finished line
x(end+1) = x(1);
x(end+1) = x(2);
path_points = zeros(length(x),2);
for i = 1:1:length(x)
    % for each gate, find the position defined between the cones
    coeff = path_boundaries(i,1:2);
    x2 = max(path_boundaries(i,3:4));
    x1 = min(path_boundaries(i,3:4));
    position = x(i);
    % place the car within via linear interpolation
    x3 = x1+position*(x2-x1);
    y3 = polyval(coeff,x3);
    %plot(x3,y3,'og')
    % the actual car's trajectory defined in x-y coordinates:
    path_points(i,:) = [x3 y3];
end

x = linspace(1,t(end-1),1000);
ppv = pchip(t,path_points');
vehicle_path = ppval(ppv,x);
vehicle_path_EN = vehicle_path;
Length = arclength(vehicle_path(1,:),vehicle_path(2,:));
%% Section 11: Simulate Endurance Lap
disp('Plotting Vehicle Trajectory')
[laptime time_elapsed velocity acceleration lateral_accel gear_counter path_length weights distance] = lap_information(xx);
%% Section 12: Load Autocross Track Coordinates
disp('Loading Autocross Track Coordinates')
data = readScaledTrackCoordinates('Autocross_Coordinates_2.xlsx');
outside = data(:,2:3);
inside = data(:,4:5);
t = [1:length(outside)];
r_min = 4.5*3.28;
r_min = r_min-tw/2;
pp_out = spline(t,outside');
pp_in = spline(t,inside');

%plot(outside(:,1),outside(:,2),'ok')
%hold on
%plot(inside(:,1),inside(:,2),'ok')
path_boundaries_ax = zeros(length(outside),4);
for i = 1:1:length(outside)
    gate_in = inside(i,:);
    gate_out = outside(i,:);
    %plot([gate_in(1) gate_out(1)],[gate_in(2) gate_out(2)],'-k')
    x1 = gate_in(1);
    x2 = gate_out(1);
    y1 = gate_in(2);
    y2 = gate_out(2);
    coeff = polyfit([x1, x2], [y1, y2], 1);
    gate_width = sqrt((x2-x1)^2+(y2-y1)^2);
    path_width = gate_width-tw;
    x_fs = tw/(2*gate_width);
    x_bound = [min(x1,x2)+x_fs*abs(x2-x1),max(x1,x2)-x_fs*abs(x2-x1)];
    path_boundaries_ax(i,:) = [coeff x_bound];
    %text(round(x1),round(y1),num2str(i))
end


%save('path_boundaries.mat','path_boundaries');
%% Section 13: Load Autocross Racing Line
disp('Loading Autocross Racing Line')
xx = load('autocross_racing_line.mat');
xx = xx.autocross_racing_line;
%% Section 14: Optimize Autocross Racing Line
% Same applies here, optimizing the line is optional but if you want,
% simply un-comment the lines of code below:

% 
% disp('Optimizing Racing Line')
% A = eye(length(xx));
% b = ones(length(xx),1);
% lb = zeros(1,length(xx));
% ub = ones(1,length(xx));
% options = optimoptions('fmincon',...
% 'Algorithm','sqp','Display','iter','ConstraintTolerance',1e-12);
% options = optimoptions(options,'MaxIter', 10000, 'MaxFunEvals', 1000000,'ConstraintTolerance',1e-12,'DiffMaxChange',.1);
% 
% lap_time_sprint_wrapped = @(path_positions) lap_time_sprint(path_positions, r_min, r_max, cornering, accel, deccel, lateral, shift_points, shift_time, top_speed);
% track_curvature_sprint_wrapped = @(path_positions) track_curvature_sprint(path_positions, track_width);
% x = fmincon(lap_time_sprint_wrapped,xx,[],[],[],[],lb,ub,track_curvature_sprint_wrapped,options);
% xx_auto = x;
% x(end+1) = x(1);
% x(end+1) = x(2);
% autocross_racing_line = xx_auto;
% save("autocross_racing_line.mat","autocross_racing_line");
%% Section 15: Generate Final Autocross Trajectory
xx_auto = xx;
nAutocrossGates = size(path_boundaries_ax,1);
if numel(xx_auto) ~= nAutocrossGates
    nUsableAutocrossGates = min(numel(xx_auto), nAutocrossGates);
    if ~T27_SWEEP_ACTIVE
        warning('Autocross racing line has %d positions but the coordinate file has %d gates. Using the first %d positions.', ...
            numel(xx_auto), nAutocrossGates, nUsableAutocrossGates);
    end
    xx_auto = xx_auto(1:nUsableAutocrossGates);
end
x = xx_auto;

%Plot finished line

path_points_ax = zeros(length(x),2);
for i = 1:1:length(x)
    coeff = path_boundaries_ax(i,1:2);
    x2 = max(path_boundaries_ax(i,3:4));
    x1 = min(path_boundaries_ax(i,3:4));
    position = x(i);
    x3 = x1+position*(x2-x1);
    y3 = polyval(coeff,x3);
    %plot(x3,y3,'og')
    path_points_ax(i,:) = [x3 y3];
end
t_ax = 1:1:length(path_points_ax);
x = linspace(1,t_ax(end),1000);
ppv = pchip(t_ax,path_points_ax');
vehicle_path = ppval(ppv,x);
vehicle_path_AX = vehicle_path;
Length = arclength(vehicle_path(1,:),vehicle_path(2,:));
%% Section 16: Simulate Autocross Lap
disp('Plotting Vehicle Trajectory')
[laptime_ax time_elapsed_ax velocity_ax, acceleration_ax lateral_accel_ax gear_counter_ax path_length_ax weights_ax distance_ax] = lap_information_sprint(xx_auto);
%% Section 17: Calculate Dynamic Event Points
disp('Calculating Points at Competition')
% calculate endurance score
Tmin = 115.249;
Tmax = Tmin*1.45;
Endurance_Score =250*((Tmax/(laptime))-1)/(Tmax/Tmin-1)+25;

% Calculate autocross score
Tmin = 48.799;
Tmax = Tmin*1.45;
Autocross_Score =118.5*((Tmax/(laptime_ax))-1)/(Tmax/Tmin-1)+6.5;

% Skidpad Analysis
% define skidpad turn radius (ft)
path_radius = 25+tw/2+.5;
% determine speed possible to take:
speed = fnval(cornering,path_radius);
% calculate skidpad time
skidpad_time = path_radius*2*pi/speed;
% calculate score based on 2019 times
Tmin_skid = 4.865;
Tmax_skid = Tmin_skid*1.45;
Skidpad_Score = 71.5*((Tmax_skid/skidpad_time)^2-1)/((Tmax_skid/Tmin_skid)^2-1) + 3.5;

% Acceleration Analysis
% start at speed 0, gear 1, etc
count = 0;
v = 0;
vel = v;
gears = find((shift_points-vel)>0);
gear = 2;
newgear = gear;
time_shifting = 0;
interval = 1;
% accel track is 247 feet, so I am defining 247 segments of 1 foot:
segment = 1:1:247;
t_accel_elapsed = 0;
clear dt_f v_f
% little quickie accel sim:
for i = 1:1:length(segment)
    d = 1;

    %gear = newgear;
    % find what gear you are in
    gears = find((shift_points-vel)>0);
    newgear = gears(1)-1;

    % compare to previous iteration, to detect an upshift
    if newgear > gear
        shifting = 1;
    else
        shifting = 0;
    end

    vmax = VMAX;
    % determine instantaneous acceleration capacity
    AX = fnval(accel,vel);
    dd = d/interval;
    for j = 1:1:interval
        count = count+1;
        vehicle_gear(count) = gear;
        if shifting == 1 && vel < vmax
            % if you are shifting, then you are not accelerating, but
            % continue to travel forward at constant velocity
            dt_f(count) = dd/max(vel, eps);
            time_shifting = time_shifting+dt_f(count);
            ax_f(count) = 0;
            v_f(count) = vel;
            dv_f(count) = 0;
            vel = vel;
        elseif vel < vmax
            % if you are not shifting, and top speed has not been achieved
            % then you keep accelerating at maximum capacity possible
            ax_f(count) = AX;
            tt = roots([0.5*32.2*ax_f(count) vel -dd]);
            dt_f(count) = max(tt);
            dv = 32.2*ax_f(count)*dt_f(count);
            dvmax = vmax-vel;
            dv_f(count) = min(dv,dvmax);
            v_f(count) = vel+dv_f(count);
            vel = v_f(count);
            gears = find((shift_points-vel)>0);
            newgear = gears(1)-1;
            if newgear > gear
                shifting = 1;
            end
        else
            % if you are not shifting but you are at top speed, then just
            % hold top speed
            vel = vmax;
            dt_f(count) = dd/max(vel, eps);
            ax_f(count) = 0;
            v_f(count) = vel;
            dv_f(count) = 0;
        end
        if time_shifting > shift_time
            shifting = 0;
            time_shifting = 0;
            if newgear ~= 1
                gear = newgear;
            end
        end
    end
    if ~(shifting == 1 || newgear == 1)
        gear = newgear;
    end
    t_accel_elapsed = t_accel_elapsed+dt_f(count);
    t_accel(i) = t_accel_elapsed;
end
accel_time = sum(dt_f(2:end))+.1;
% calculate accel score:
Tmin_accel = 4.109;
Tmax_accel = Tmin_accel*1.5;
Accel_Score = 95.5*((Tmax_accel/accel_time)-1)/((Tmax_accel/Tmin_accel)-1) + 4.5;

Total_Points = Accel_Score+Skidpad_Score+Autocross_Score+Endurance_Score;

% Log the aero target used for this run so different runs are easy to compare
aeroTargetResults = table(string(aeroTag),CL_target,CD_target,CoP_target, ...
    Accel_Score,Skidpad_Score,Autocross_Score,Endurance_Score,Total_Points, ...
    skidpad_time,accel_time,laptime_ax,laptime, ...
    'VariableNames',["AeroTag","CL_target","CD_target","CoP_target", ...
    "Accel_Score","Skidpad_Score","Autocross_Score","Endurance_Score","Total_Points", ...
    "Skidpad_Time","Accel_Time","Autocross_Time","Endurance_Lap_Time"]);
aeroTargetResults.CL_over_CD = CL_target ./ max(CD_target, eps);
disp(aeroTargetResults)

enduranceTelemetry = buildValidationTelemetry("Endurance", time_elapsed, distance, velocity, acceleration, lateral_accel, gear_counter);
autocrossTelemetry = buildValidationTelemetry("Autocross", time_elapsed_ax, distance_ax, velocity_ax, acceleration_ax, lateral_accel_ax, gear_counter_ax);
validationTelemetry = [enduranceTelemetry; autocrossTelemetry];
validationSummary = table(string(aeroTag), CL_target, CD_target, CoP_target, ...
    laptime, laptime_ax, skidpad_time, accel_time, ...
    max(velocity), max(velocity_ax), max(acceleration), min(acceleration), max(abs(lateral_accel)), ...
    'VariableNames', ["AeroTag","CL_target","CD_target","CoP_target", ...
    "Endurance_Lap_Time","Autocross_Time","Skidpad_Time","Accel_Time", ...
    "Endurance_Max_Speed","Autocross_Max_Speed","Max_AX","Min_AX","Max_Abs_AY"]);

if T27_WRITE_OUTPUTS
    writetable(aeroTargetResults,'aero_target_results.csv','WriteMode','append');
end
if T27_EXPORT_VALIDATION
    safeAeroTag = regexprep(char(string(aeroTag)), '[^A-Za-z0-9_-]', '_');
    writetable(validationTelemetry, sprintf('T27_validation_trace_%s.csv', safeAeroTag));
    writetable(validationSummary, sprintf('T27_validation_summary_%s.csv', safeAeroTag));
end
%% Section 18: Generate Load Cases
disp('Generating Load Cases')
% find all three worst case acceleration cases:
AX_min = min(acceleration);
AX_max = max(acceleration);
AY_max = max(lateral_accel);
% then find where they took place
VX_min = velocity(acceleration == AX_min);
VX_max = velocity(acceleration == AX_max);
VY_max = velocity(lateral_accel == AY_max);
VX_min = min(VX_min);
VX_max = max(VX_max);
VY_max = max(VY_max);
frontF = zeros(3,3);
rearF = zeros(3,3);
Cl_load = CL_target;
CoP_load = CoP_target;
% then calculate loads based on those speeds and accelerations:
% see documentation spreadsheet for translation
frontF(3,:) = [WF/2 + Cl_load*VX_max^2*CoP_load/2 - WF*AX_max*cg/l/2 , WF/2 + Cl_load*VX_min.^2*CoP_load/2 - WF*AX_min*cg/l/2, WF/2 + Cl_load*VY_max^2*CoP_load/2 + WF*AY_max*cg/tw/2];
rearF(3,:) = [WR/2 + Cl_load*VX_max^2*(1-CoP_load)/2 + WR*AX_max*cg/l/2 , WR/2 + Cl_load*VX_min^2*(1-CoP_load)/2 + WR*AX_min*cg/l/2, WR/2 + Cl_load*VY_max^2*(1-CoP_load)/2 + WR*AY_max*cg/tw/2];
frontF(2,:) = [0 0 (WF/2+WF*AY_max*cg/tw/2)*AY_max];
rearF(2,:) = [0 0 (WR/2+WR*AY_max*cg/tw/2)*AY_max];
frontF(1,:) = [0 -(WF/2 -WF*AX_min*cg/l/2)*AX_min 0];
rearF(1,:) = [W*AX_max/2 -(WR/2 +WR*AX_min*cg/l/2)*AX_min 0];
%% Section 19: Plot Results
% disp('Plotting Results')
% % This is just to make some pretty pictures, feel free to comment this out
% figure
% plot(distance,velocity,'k')
% title('Endurance Simulation Velocity Trace')
% xlabel('Distance Travelled (d) [ft]')
% ylabel('Velocity (V) [ft/s]')
% figure
% plot(distance,acceleration,distance,lateral_accel)
% title('Endurance Simulation Acceleration Traces')
% xlabel('Distance Travelled (d) [ft]')
% ylabel('Acceleration [g]')
% legend('Longitudinal','Lateral')
% figure
% plot(distance_ax,velocity_ax,'k')
% title('Autocross Simulation Velocity Trace')
% xlabel('Distance Travelled (d) [ft]')
% ylabel('Velocity (V) [ft/s]')
% figure
% plot(distance_ax,acceleration_ax,distance_ax,lateral_accel_ax)
% title('Autocross Simulation Acceleration Traces')
% xlabel('Distance Travelled (d) [ft]')
% ylabel('Acceleration [g]')
% legend('Longitudinal','Lateral')
% disp('Analysis Complete')
% disp(Total_Points)
% toc
