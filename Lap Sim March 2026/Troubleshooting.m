clear
clc

WDF = 50;
%function [Total_Points,Accel_Score,Skidpad_Score,Autocross_Score,Endurance_Score,AY_max,AX_max] = Lap_Sim(WDF)

% The purpose of this code is to evaluate the points-scoring capacity of a
% virtual vehicle around the 2019 FSAE Michigan Dynamic Event Tracks

%% Section 0: Name all symbolic variables
% Don't touch this. This is just naming a bunch of variables and making
% them global so that all the other functions can access them
global r_max accel grip deccel lateral cornering gear shift_points...
    top_speed r_min path_boundaries tire_radius shift_time...
    powertrainpackage track_width path_boundaries_ax
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

filename = 'Hoosier_LCO_16.0x7.5-10_FY_10psi';
%filename = 'Hoosier R20 16x7.5-10 12 Psi Final FY';
load(filename)

% Next you load in the longitudinal tire model, which is a
% CSAPS spline fit to the TTC data
% find your pathname and filename for the tire you want to load in

filename = 'Hoosier_LCO_18.0x6.0-10_FX_10psi';
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

% sf_x = .55;
% sf_y = .47;   

sf_x = 0.55;
sf_y = 0.50;
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
T_lock = 0; % differential locking torque (0 =  open, 1 = locked)

% Intermediary Calcs/Save your results into the workspace
gearTot = gear(end)*finalDrive*primaryReduction;
VMAX = floor(3.28*redline/(gearTot/tyreRadius*60/(2*pi)));
T_lock = T_lock/100;
powertrainpackage = {engineSpeed engineTq primaryReduction gear finalDrive shiftpoints drivetrainLosses};
%% Section 3: Vehicle Architecture
disp('Loading Vehicle Characteristics')
% These are the basic vehicle architecture primary inputs:
LLTD = 53; % Front lateral load transfer distribution (%)
W = 610; % vehicle + driver weight (lbs)
%WDF = 55; % front weight distribution (%) 45
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
WRF = 268; % front and rear ride rates (lbs/in)
WRR = 191.88; 

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
%% Section 5: Input Aero Parameters
disp('Loading Aero Model')
% obviously the biggest room for improvement is having an aero map. enough
% said

%traditional Cl 
%Cl = C_l * 1.15 * .5 * 1.2754
%Cd = C_d * 1.15 * .5 * 1.2754
%metric -> imperial (ns/m2 -> lbss/ft2) * .02

Cl = 0.048; % 1
Cd = 0.0216; % .625
CoP = 43; % front downforce distribution (%)

% Intermediary Calculations
CoP = CoP/100;
%% Section 6: Generate GGV Diagram
% this is where the m e a t of the lap sim takes place. The GGV diagram is
% built by finding a maximum cornering, braking, and acceleration capacity
% for any given speed

disp('Generating g-g-V Diagram')

deltar = 0;
deltaf = 0;
velocity = 15:5:VMAX; % range of velocities at which sim will evaluate (ft/s)
radii = [20:10:160]; % range of turn radii at which sim will evaluate (ft)

% % First we will evaluate our Acceleration Capacity
g = 1; % g is a gear indicator, and it will start at 1
spcount = 1; % spcount is keeping track of how many gearshifts there are
% shift_points tracks the actual shift point velocities
shift_points(1) = 0; 
% disp('     Acceleration Envelope')
% tic
% for  i = 1:1:length(velocity) % for each velocity
%     gp = g; % Current gear = current gear (wow!)
%     V = velocity(i); % find velocity
%     DF = Cl*V^2; % calculate downforce (lbs)
%     % calculate f/r suspension drop from downforce (in)
%     dxf = DF*CoP/2/WRF; 
%     dxr = DF*(1-CoP)/2/WRR;
%     % from rh drop, find camber gain (deg)
%     IA_0f = IA_staticf - dxf*IA_gainf;
%     IA_0r = IA_staticr - dxr*IA_gainr;
%     % find load on each tire (lbs)
%     wf = (WF+DF*CoP)/2;
%     wr = (WR+DF*(1-CoP))/2;
% 
%     % now we actually sweep through with acceleration
%     Ax = 0; % starting guess of zero g's
%     WS = W/2; % weight of one half-car
%     pitch = -Ax*pg*pi/180; % pitch angle (rad)
%     % recalculate wheel loads due to load transfer (lbs)
%     wf = wf-Ax*cg*WS/l; 
%     wr = wr+Ax*cg*WS/l;
%     % recalculate camber angles due to pitch
%     IA_f = -l*12*sin(pitch)/2*IA_gainf + IA_0f;
%     IA_r = l*12*sin(pitch)/2*IA_gainr + IA_0r;
%     % IA_f = 0;
%     % IA_r = 0;
%     % select a range of slip ratios (sl) [-]
%     sl = [0:.01:.11];
%     % evaluate the tractive force capacity from each tire for the range of
%     % slip ratios
%     fxf = zeros(1, length(sl));
%     fxr = fxf;
%     for k = 1:length(sl)  
%         fxf(k) = fnval([sl(k);-wf;rad2deg(-IA_f)],full_send_x)*sf_x;
%         fxr(k) = fnval([sl(k);-wr;rad2deg(-IA_r)],full_send_x)*sf_x;
%     end
%     % find max force capacity from each tire:
%     fxf(find(abs(fxf) > 1000)) = [];
%     fxr(find(abs(fxr) > 1000)) = [];
%     FXF = max(fxf);
%     FXR = max(fxr);
%     % Calculate total tire tractive force (lbs)
%     FX = abs(2*FXR);
%     % calculate total lateral acceleration capacity (g's)
%     AX = FX/W;
%     AX_diff = AX-Ax;
%     while AX_diff>0
%         %disp([Ax AX])
%         Ax = Ax+.01;
%         WS = W/2;
%         pitch = -Ax*pg*pi/180;
%         wf = (WF+DF*CoP)/2;
%         wr = (WR+DF*(1-CoP))/2;
%         wf = wf-Ax*cg*WS/l/24;
%         wr = wr+Ax*cg*WS/l/24;
%         IA_f = -l*12*sin(pitch)/2*IA_gainf + IA_0f;% - KPIf*(1-cos(deltaf)) + casterf*sin(deltaf);
%         IA_r = l*12*sin(pitch)/2*IA_gainr + IA_0r;% - KPIr*(1-cos(deltar)) + casterf*sin(deltar);
%         IA_f = 0;
%         IA_r = 0;
%         FZ_vals = [-250:1:-50];
%         sl = [0:.01:.11];
%         for k = 1:length(sl)
%             fxf(k) = fnval([sl(k);-wf;rad2deg(-IA_f)],full_send_x)*sf_x;
%             fxr(k) = fnval([sl(k);-wr;rad2deg(-IA_r)],full_send_x)*sf_x;
%         end
%         fxf(find(abs(fxf) > 1000)) = [];
%         fxr(find(abs(fxr) > 1000)) = [];
%         FXF = max(fxf);
%         FXR = max(fxr);
%         FX = abs(2*FXR);
%         AX = FX/W;
%         AX_diff = AX-Ax;
%     end
%     A_xr(i) = AX;
%     output = Powertrainlapsim(max(7.5,V/3.28)); % 7.5 reg, 10 launch
%     FX = output(1)*.2248;
%     FX = FX-Cd*V^2;
%     fx(i) = FX/W;
%     AX(i) = min(FX/W,A_xr(i));
%     output = Powertrainlapsim(V/3.28);
%     g = output(2);
%     gear(i) = g;
%     if g>gp
%         spcount = spcount+1;
%         shift_points(spcount) = V;
%     end
%     A_Xr(i) = AX(i);
% end
% A_Xr(A_Xr < 0) = 0;
% toc
% from these results, you can create the first part of the GGV diagram
% input for the lap sim codes:
% accel is the maximum acceleration capacity as a function of velocity
% (power limited) and grip is the same but (tire limited)
% accel = csaps(velocity,A_Xr);
% grip = csaps(velocity,A_xr);

% Next we explore the cornering envelope. First we define AYP, which is the
% starting guess for lateral acceleration capacity at a given speed
V_guess = 8;
tol = 1e-5;
step = 0.1;
options = optimoptions('fsolve', 'Display', 'none');
disp('     Cornering Envelope')
% for cornering performance, it makes more sense to evaluate a set of
% cornering radii, instead of speeds
tic



for turn = 1:1:length(radii)
    R = radii(turn);
    V = V_guess;
    cond = 0;
    fini = 0;
    while cond == 0
        % x(1) = delta
        % x(2) = beta
        % can improve this by switching to fmincon and constraining the
        % tyres by ratio to on-center slip stiffness. would be faster and
        % more stable. Should also add extra constraints to vehicle
        % stability based on model linearisation (eigenvalues!)
        %fun = @(x) lat_solve(x, V, a, b, l, WDF, R, CoP, Cl, WRF, WRR, IA_staticf, IA_gainf, IA_staticr, IA_gainr, WF, WR, twf, twr, cg, W, LLTD, rg_f, rg_r, casterf, casterr, deltar, sf_y, full_send_y, grip, Cd, T_lock, KPIf, KPIr);
        fun = @(x) lat_solve_TbSht(x, V, a, b, l, WDF, R, CoP, Cl, WRF, WRR, IA_staticf, IA_gainf, IA_staticr, IA_gainr, WF, WR, twf, twr, cg, W, LLTD, rg_f, rg_r, casterf, casterr, deltar, sf_y, full_send_y, grip, Cd, T_lock, KPIf, KPIr);
        [x, fval, exitflag] = fsolve(fun, [0, 0], options);
        % lower and upper bounds on inputs
        % [delta, beta]
        % set these to something reasonable (these are probably too lax)
        lb = deg2rad([-15, -12]);
        ub = deg2rad([15, 12]);
        % if residuals exceeds tolerance, cond to -1
        for h=1:2 
            if(abs(fval(h)) > tol)
                fprintf('\nResiduals out of tolerance - %f > %f',fval(h),tol)
                cond = -1;
            end
        end
        % if lat_solve fails, cond to -1
        if exitflag < 1 
            fprintf('\nexitflag = %f',exitflag)
            cond = -1;
        end
        % if x is out of bounds, set cond to -1
        if sum(x<lb) 
            fprintf('\ndelta and/or beta exceeded lower bound')
            cond = -1;
        elseif sum(x>ub)
            fprintf('\ndelta and/or beta exceeded upper bound')
            cond = -1;
        end
        % Increase V and continue solving (restart loop)
        if cond == 0 
            V = V + step;
            fini = 1;
        % if cond = -1, perform final solve and exit the loop
        else 
            V = V - step;
            %fun = @(x) lat_solve(x, V, a, b, l, WDF, R, CoP, Cl, WRF, WRR, IA_staticf, IA_gainf, IA_staticr, IA_gainr, WF, WR, twf, twr, cg, W, LLTD, rg_f, rg_r, casterf, casterr, deltar, sf_y, full_send_y, grip, Cd, T_lock, KPIf, KPIr);
            fun = @(x) lat_solve_TbSht(x, V, a, b, l, WDF, R, CoP, Cl, WRF, WRR, IA_staticf, IA_gainf, IA_staticr, IA_gainr, WF, WR, twf, twr, cg, W, LLTD, rg_f, rg_r, casterf, casterr, deltar, sf_y, full_send_y, grip, Cd, T_lock, KPIf, KPIr);
            [x] = fsolve(fun, [0, 0], options); 
            delta = x(1); beta = x(2);
            AY = V^2 / R;
            r = AY/V;
            a_f = beta+a*r/V-delta;
            a_r = -beta+b*r/V;
            B = rad2deg(beta);
            af = rad2deg(a_f);
            ar = rad2deg(a_r);
            steer = rad2deg(delta);
            UG = rad2deg(delta-l/R)*32.2/AY;
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
            latResults = table(Rs',steering',speed',lateralg',Ugradient',betas',afs',ars','VariableNames',["Radius","steering","speed","latG","USG","Beta","af","ar"])
        end
    end
    % initial guess for next turning radius
    % can do this more intelligently???
    V_guess = V;
end

toc
% Lateral Acceleration

% % Braking Performance
% velocity = 15:5:VMAX;
% disp('     Braking Envelope')
% % the braking sim works exactly the same as acceleration, except now all 4
% % tires are contributing to the total braking capacity
% tic
% for  i = 1:1:length(velocity)
%     V = velocity(i);
%     DF = Cl*V^2;
%     dxf = DF*CoP/2/WRF;
%     dxr = DF*(1-CoP)/2/WRR;
%     IA_0f = IA_staticf - dxf*IA_gainf;
%     IA_0r = IA_staticr - dxr*IA_gainr;
%     wf = (WF+DF*CoP)/2;
%     wr = (WR+DF*(1-CoP))/2;
%     Ax = 1;
%     WS = W/2;
%     pitch = Ax*pg*pi/180;
%     wf = wf+Ax*cg*WS/l/24;
%     wr = wr-Ax*cg*WS/l/24;
%     IA_f = -l*12*sin(pitch)/2*IA_gainf + IA_0f;% - KPIf*(1-cos(deltaf)) + casterf*sin(deltaf);
%     IA_r = l*12*sin(pitch)/2*IA_gainr + IA_0r;% - KPIr*(1-cos(deltar)) + casterf*sin(deltar);
%     IA_f = 0;
%     IA_r = 0;
%     FZ_vals = [-250:1:-50];
%     sl = [-.15:.01:0];
%     for k = 1:length(sl)
%         fxf(k) = fnval([sl(k);-wf;rad2deg(-IA_f)],full_send_x)*sf_x;
%         fxr(k) = fnval([sl(k);-wr;rad2deg(-IA_r)],full_send_x)*sf_x;
%     end
%     fxf(find(abs(fxf) > 1000)) = [];
%     fxr(find(abs(fxr) > 1000)) = [];
%     FXF = min(fxf);
%     FXR = min(fxr);
%     FX = abs(2*FXF+2*FXR);
%     AX = FX/W;
%     AX_diff = AX-Ax;
%     while AX_diff>0
%         %disp([Ax AX])
%         Ax = Ax+.01;
%         WS = W/2;
%         pitch = Ax*pg*pi/180;
%         wf = (WF+DF*CoP)/2;
%         wr = (WR+DF*(1-CoP))/2;
%         wf = wf+Ax*cg*WS/l/24;
%         wr = wr-Ax*cg*WS/l/24;
%         IA_f = -l*12*sin(pitch)/2*IA_gainf + IA_0f;% - KPIf*(1-cos(deltaf)) + casterf*sin(deltaf);
%         IA_r = l*12*sin(pitch)/2*IA_gainr + IA_0r;% - KPIr*(1-cos(deltar)) + casterf*sin(deltar);
%         IA_f = 0;
%         IA_r = 0;
%         FZ_vals = [-250:1:-50];
%         sl = [-.15:.01:0];
%         for k = 1:length(sl)
%             fxf(k) = fnval([sl(k);-wf;rad2deg(-IA_f)],full_send_x)*sf_x;
%             fxr(k) = fnval([sl(k);-wr;rad2deg(-IA_r)],full_send_x)*sf_x;
%         end
%         fxf(find(abs(fxf) > 1000)) = [];
%         fxr(find(abs(fxr) > 1000)) = [];
%         FXF = min(fxf);
%         FXR = min(fxr);
%         FX = abs(2*FXF+2*FXR);
%         AX = FX/W;
%         AX_diff = AX-Ax;
%     end
%     A_X(i) = AX;
% end
% toc
% velocity_y = lateralg.*32.2.*radii;
% velocity_y = sqrt(velocity_y);
% 
% r_max = max(radii);
% spcount = spcount+1;
% shift_points(spcount) = V+1;
% top_speed = V;
% VMAX = top_speed;
% tic
% % make the rest of your functions for the GGV diagram
% % braking as a function of speed
% deccel = csaps(velocity,A_X);
% velocity = 15:5:VMAX;
% % lateral g's as a function of velocity
% lateral = csaps(velocity_y,lateralg);
% radii = velocity_y.^2./lateralg/32.2;
% % max velocity as a function of instantaneous turn radius
% % cornering = csaps(radii,velocity_y);
% cornering = fnxtr(csaps(radii, velocity_y, 0.99999), 2);
% 
% save("pickle.mat", "cornering", "lateral", "deccel")