%function Total_Points = Lap_Sim_powertrain(finalDrive)
close all
clear
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
%disp('2019 Michigan Endurance Points Analysis')
%disp('Loading Tire Model')

% First we load in the lateral tire force model, which is a CSAPS cubic
% spline interpolation fit to TTC data
% make sure these files are already in your directory
filename = 'Hoosier R20 16x7.5-10 12 Psi Final FY.mat';
load(filename)

% Next you load in the longitudinal tire model, which is a
% CSAPS spline fit to the TTC data
% find your pathname and filename for the tire you want to load in
filename = 'Hoosier_R25B_18.0x7.5-10_FX_12psi.mat';
load(filename)
tire_radius = 8.05/12; %ft
tyreRadius = tire_radius/3.28; % converts to meters

% finally, we have some scaling factors for longitudinal (x) and lateral
% (y) friction. You can use these to tune the lap sim to correlate better 
% to logged data 
sf_x = .6;
sf_y = .47;   
%% Section 2: Input Powertrain Model
% change whatever you want here, this is the 2018 powertrain package iirc
% just keep your units consistent please
%disp('Loading Engine Model')
% torque should be in N-m:
%engineTq = [41.57 42.98 44.43 45.65 46.44 47.09 47.52 48.58 49.57 50.41 51.43 51.48 51 49.311 48.94 48.66 49.62 49.60 47.89 47.91 48.09 48.57 49.07 49.31 49.58 49.56 49.84 50.10 50.00 50.00 50.75 51.25 52.01 52.44 52.59 52.73 53.34 53.72 52.11 52.25 51.66 50.5 50.34 50.50 50.50 50.55 50.63 50.17 50.80 49.73 49.35 49.11 48.65 48.28 48.28 47.99 47.68 47.43 47.07 46.67 45.49 45.37 44.67 43.8 43.0 42.3 42.00 41.96 41.70 40.43 39.83 38.60 38.46 37.56 36.34 35.35 33.75 33.54 32.63 31.63];
redline = 15000;
engineSpeed = [6000:100:redline]; % RPM
engineTq = [36.48501	38.59397	44.32983	46.28545	47.887875	49.829956	51.228146	51.03791	51.292057	51.900978	52.434673	52.499348	51.684544	50.131496	49.159187	48.94724	49.628212	50.57417	51.357998	51.728046	51.37902	50.64954	49.651802	48.46732	47.18437	44.13004	40.682053	36.252777];
engineRPM = [4000.0	5000.0	6000.0	7000.0	7500.0	8000.0	8500.0	9000.0	9500.0	9750.0	10000.0	10250.0	10500.0	10750.0	11000.0	11250.0	11500.0	11750.0	12000.0	12250.0	12500.0	12750.0	13000.0	13250.0	13500.0	14000.0	14500.0	15000.0];
engineTq = pchip(engineRPM, engineTq, engineSpeed);
primaryReduction = 76/36;
gear = [33/12, 32/16, 30/18, 26/18, 30/23, 29/24]; % transmission gear ratios
finalDrive = 30/12; % large sprocket/small sprocket
shiftpoints = calc_shiftpoints(finalDrive, gear, engineTq, redline, primaryReduction, tyreRadius, engineSpeed); % optimal shiftpoint for most gears [RPM]
drivetrainLosses = .80; % percent of torque that makes it to the rear wheels
shift_time = .075; % seconds
T_lock = 0; % differential locking torque (0 =  open, 1 = locked)

% Intermediary Calcs/Save your results into the workspace
gearTot = gear(end)*finalDrive*primaryReduction;
VMAX = floor(3.28*redline/(gearTot/tyreRadius*60/(2*pi)));
T_lock = T_lock/100;
powertrainpackage = {engineSpeed engineTq primaryReduction gear finalDrive shiftpoints drivetrainLosses};
%% Section 3: Vehicle Architecture
%disp('Loading Vehicle Characteristics')
% These are the basic vehicle architecture primary inputs:
LLTD = 55; % Front lateral load transfer distribution (%)
W = 650; % vehicle + driver weight (lbs)
WDF = 45; % front weight distribution (%)
cg = 12.2/12; % center of gravity height (ft)
l = 60.5/12; % wheelbase (ft)
twf = 46/12; % front track width (ft)
twr = 44/12; % rear track width (ft)

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
%disp('Loading Suspension Kinematics')
% this section is actually optional. So if you set everything to zero, you
% can essentially leave this portion out of the analysis. Useful if you are
% only trying to explore some higher level relationships

% Pitch and roll gradients define how much the car's gonna move around
rg_f = 1; % front roll gradient (deg/g)
rg_r = 1; % rear roll gradient (deg/g)
pg = .4; % pitch gradient (deg/g)
WRF = 160; % front and rear ride rates (lbs/in)
WRR = 160;

% then you can select your camber alignment
IA_staticf = -.5; % front static camber angle (deg)
IA_staticr = -.75; % rear static camber angle (deg)
IA_compensationf = 100*.3; % front camber compensation (%)
IA_compensationr = 100*.6; % rear camber compensation (%)

% lastly you can select your kingpin axis parameters
casterf = 3; % front caster angle (deg)
KPIf = 6; % front kingpin inclination angle (deg)
casterr = 20;
KPIr = 8;

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
IA_gainf = deg2rad(.5);
IA_gainr = deg2rad(1.7);
%% Section 5: Input Aero Parameters
%disp('Loading Aero Model')
%traditional Cl 
%Cl = C_l * 1.15 * .5 * 1.2754
%Cd = C_d * 1.15 * .5 * 1.2754
%metric -> imperial (ns/m2 -> lbss/ft2) * .02


Cl = .0704 * .75; % .0418
Cd = 1.8 * 1.15 * .5 * 1.2754 * .02 * .75; % .0184
CoP = 45; % front downforce distribution (%)

% Intermediary Calculations
CoP = CoP/100;
%% Section 6: Generate GGV Diagram
% this is where the m e a t of the lap sim takes place. The GGV diagram is
% built by finding a maximum cornering, braking, and acceleration capacity
% for any given speed

%disp('Generating g-g-V Diagram')

deltar = 0;
deltaf = 0;
velocity = 15:5:VMAX; % range of velocities at which sim will evaluate (ft/s)
radii = [15:10:155]; % range of turn radii at which sim will evaluate (ft)

% First we will evaluate our Acceleration Capacity
g = 1; % g is a gear indicator, and it will start at 1
spcount = 1; % spcount is keeping track of how many gearshifts there are
% shift_points tracks the actual shift point velocities
shift_points(1) = 0; 
%disp('     Acceleration Envelope')
tic
for  i = 1:1:length(velocity) % for each velocity
    gp = g; % Current gear = current gear (wow!)
    V = velocity(i); % find velocity
    DF = Cl*V^2; % calculate downforce (lbs)
    % calculate f/r suspension drop from downforce (in)
    dxf = DF*CoP/2/WRF; 
    dxr = DF*(1-CoP)/2/WRR;
    % from rh drop, find camber gain (deg)
    IA_0f = IA_staticf - dxf*IA_gainf;
    IA_0r = IA_staticr - dxr*IA_gainr;
    % find load on each tire (lbs)
    wf = (WF+DF*CoP)/2;
    wr = (WR+DF*(1-CoP))/2;
    
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
    % select a range of slip ratios (sl) [-]
    sl = [0:.01:.11];
    % evaluate the tractive force capacity from each tire for the range of
    % slip ratios
    for k = 1:length(sl)  
        fxf(k) = fnval([sl(k);-wf;rad2deg(-IA_f)],full_send_x)*sf_x;
        fxr(k) = fnval([sl(k);-wr;rad2deg(-IA_r)],full_send_x)*sf_x;
    end
    % find max force capacity from each tire:
    fxf(find(abs(fxf) > 1000)) = [];
    fxr(find(abs(fxr) > 1000)) = [];
    FXF = max(fxf);
    FXR = max(fxr);
    % Calculate total tire tractive force (lbs)
    FX = abs(2*FXR);
    % calculate total lateral acceleration capacity (g's)
    AX = FX/W;
    AX_diff = AX-Ax;
    while AX_diff>0
        %disp([Ax AX])
        Ax = Ax+.01;
        WS = W/2;
        pitch = -Ax*pg*pi/180;
        wf = (WF+DF*CoP)/2;
        wr = (WR+DF*(1-CoP))/2;
        wf = wf-Ax*cg*WS/l/24;
        wr = wr+Ax*cg*WS/l/24;
        IA_f = -l*12*sin(pitch)/2*IA_gainf + IA_0f;% - KPIf*(1-cos(deltaf)) + casterf*sin(deltaf);
        IA_r = l*12*sin(pitch)/2*IA_gainr + IA_0r;% - KPIr*(1-cos(deltar)) + casterf*sin(deltar);
        FZ_vals = [-250:1:-50];
        sl = [0:.01:.11];
        for k = 1:length(sl)
            fxf(k) = fnval([sl(k);-wf;rad2deg(-IA_f)],full_send_x)*sf_x;
            fxr(k) = fnval([sl(k);-wr;rad2deg(-IA_r)],full_send_x)*sf_x;
        end
        fxf(find(abs(fxf) > 1000)) = [];
        fxr(find(abs(fxr) > 1000)) = [];
        FXF = max(fxf);
        FXR = max(fxr);
        FX = abs(2*FXR);
        AX = FX/W;
        AX_diff = AX-Ax;
    end
    A_xr(i) = AX;
    output = Powertrainlapsim(max(10,V/3.28)); % 7.5 reg, 10 launch
    FX = output(1)*.2248;
    FX = FX-Cd*V^2;
    fx(i) = FX/W;
    AX(i) = min(FX/W,A_xr(i));
    output = Powertrainlapsim(V/3.28);
    g = output(2);
    gear(i) = g;
    if g>gp
        spcount = spcount+1;
        shift_points(spcount) = V;
    end
    A_Xr(i) = AX(i);
end
A_Xr(A_Xr < 0) = 0;
%toc
% from these results, you can create the first part of the GGV diagram
% input for the lap sim codes:
% accel is the maximum acceleration capacity as a function of velocity
% (power limited) and grip is the same but (tire limited)
accel = csaps(velocity,A_Xr);
grip = csaps(velocity,A_xr);

r_max = max(radii);
spcount = spcount+1;
shift_points(spcount) = V+1;
top_speed = V;
VMAX = top_speed;
tic
load("pickle.mat");
%% Section 7: Load Endurance Track Coordinates
%disp('Loading Endurance Track Coordinates')
[data text] = xlsread('Endurance_Coordinates_1.xlsx','Scaled');

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
%disp('Loading Endurance Racing Line')
xx = load('endurance_racing_line.mat');
xx = xx.endurance_racing_line;
%% Section 9: Optimize Endurance Racing Line
% The pre-loaded racing line should work for most applications; however,
% if you have the need to re-evaluate or generate a new optimized racing
% line, simply un-comment the code below:


% disp('Optimizing Endurance Racing Line')
% A = eye(length(xx));
% b = ones(length(xx),1);
% lb = zeros(1,length(xx));
% ub = ones(1,length(xx));
% options = optimoptions('fmincon',...
%     'Algorithm','sqp','Display','iter','ConstraintTolerance',1e-12);
% options = optimoptions(options,'MaxIter', 10000, 'MaxFunEvals', 1000000,'ConstraintTolerance',1e-12,'DiffMaxChange',.1);
% 
% x = fmincon(@lap_time,xx,[],[],[],[],lb,ub,@track_curvature,options);
% xx = x;
% x(end+1) = x(1);
% x(end+1) = x(2);
%% Section 10: Generate Final Endurance Trajectory
x = xx;
% Plot finished line
x(end+1) = x(1);
x(end+1) = x(2);
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
%disp('Plotting Vehicle Trajectory')
[laptime time_elapsed velocity acceleration lateral_accel gear_counter path_length weights distance] = lap_information(xx);
%% Section 12: Load Autocross Track Coordinates
%disp('Loading Autocross Track Coordinates')
[data text] = xlsread('Autocross_Coordinates_2.xlsx','Scaled');
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
clear path_boundaries
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
%disp('Loading Autocross Racng Line')
xx = load('autocross_racing_line.mat');
xx = xx.autocross_racing_line;
%% Section 14: Optimize Autocross Racing Line
% Same applies here, optimizing the line is optional but if you want,
% simply un-comment the lines of code below:
% 
% 
% disp('Optimizing Racing Line')
% A = eye(length(xx));
% b = ones(length(xx),1);
% lb = zeros(1,length(xx));
% ub = ones(1,length(xx));
% options = optimoptions('fmincon',...
%     'Algorithm','sqp','Display','iter','ConstraintTolerance',1e-12);
% options = optimoptions(options,'MaxIter', 10000, 'MaxFunEvals', 1000000,'ConstraintTolerance',1e-12,'DiffMaxChange',.1);
% 
% x = fmincon(@lap_time_sprint,xx,[],[],[],[],lb,ub,@track_curvature_sprint,options);
% xx_auto = x;
% % x(end+1) = x(1);
% % x(end+1) = x(2);
%% Section 15: Generate Final Autocross Trajectory
xx_auto = xx;
x = xx_auto;
%Plot finished line

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
x = linspace(1,t(end),1000);
ppv = pchip(t,path_points_ax');
vehicle_path = ppval(ppv,x);
vehicle_path_AX = vehicle_path;
Length = arclength(vehicle_path(1,:),vehicle_path(2,:));
%% Section 16: Simulate Autocross Lap
%disp('Plotting Vehicle Trajectory')
[laptime_ax time_elapsed_ax velocity_ax, acceleration_ax lateral_accel_ax gear_counter_ax path_length_ax weights_ax distance_ax] = lap_information_sprint(xx_auto);
%% Section 17: Calculate Dynamic Event Points
%disp('Calculating Points at Competition')
% calculate endurance score
Tmin = 115.249;
Tmax = Tmin*1.45;
Endurance_Score =250*((Tmax/(laptime+13))-1)/(Tmax/Tmin-1)+25;

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
    %disp(gear)
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
        if shifting == 1 & vel < vmax;
            % if you are shifting, then you are not accelerating, but
            % continue to travel forward at constant velocity
            dt_f(count) = dd/vel;
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
            dt_f(count) = dd/vel;
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
    if shifting == 1 || newgear == 1
        gear = gear;
    else
        gear = newgear;
    end
    t_accel_elapsed = t_accel_elapsed+dt_f(count);
    t_accel(i) = t_accel_elapsed;
end
accel_time = sum(dt_f(2:end))+.1;

% Acceleration Analysis
% start at speed 0, gear 1, etc
count = 0;
v = 0;
vel = v;
gears = find((shift_points-vel)>0);
gear = 1;
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
    %disp(gear)
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
        if shifting == 1 & vel < vmax;
            % if you are shifting, then you are not accelerating, but
            % continue to travel forward at constant velocity
            dt_f(count) = dd/vel;
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
            dt_f(count) = dd/vel;
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
    if shifting == 1 || newgear == 1
        gear = gear;
    else
        gear = newgear;
    end
    t_accel_elapsed = t_accel_elapsed+dt_f(count);
    t_accel(i) = t_accel_elapsed;
end
accel_time2 = sum(dt_f(2:end))+.1;

accel_time = min(accel_time, accel_time2);
% calculate accel score:
Tmin_accel = 4.109;
Tmax_accel = Tmin_accel*1.5;
Accel_Score = 95.5*((Tmax_accel/accel_time)-1)/((Tmax_accel/Tmin_accel)-1) + 4.5;

Total_Points = Accel_Score+Skidpad_Score+Autocross_Score+Endurance_Score;
disp(Total_Points)
disp(Accel_Score)
disp(Autocross_Score)
results = [time_elapsed' velocity'];
%xlswrite('logged_data.xlsx',results,'sim_data') 
%% Section 18: Generate Load Cases
%disp('Generating Load Cases')
% find all three worst case acceleration cases:
AX_min = min(acceleration);
AX_max = max(acceleration);
AY_max = max(lateral_accel);
% then find where they took place
VX_min = velocity(find(acceleration == AX_min));
VX_max = velocity(find(acceleration == AX_max));
VY_max = velocity(find(lateral_accel == AY_max));
VY_max = max(VY_max);
frontF = zeros(3,3);
rearF = zeros(3,3);
% then calculate loads based on those speeds and accelerations: 
% see documentation spreadsheet for translation
% frontF(3,:) = [WF/2 + Cl*VX_max^2*CoP/2 - WF*AX_max*cg/l/2 , WF/2 + Cl*VX_min^2*CoP/2 - WF*AX_min*cg/l/2, WF/2 + Cl*VY_max^2*CoP/2 + WF*AY_max*cg/tw/2];
% rearF(3,:) = [WR/2 + Cl*VX_max^2*(1-CoP)/2 + WR*AX_max*cg/l/2 , WR/2 + Cl*VX_min^2*(1-CoP)/2 + WR*AX_min*cg/l/2, WR/2 + Cl*VY_max^2*(1-CoP)/2 + WR*AY_max*cg/tw/2];
% frontF(2,:) = [0 0 (WF/2+WF*AY_max*cg/tw/2)*AY_max];
% rearF(2,:) = [0 0 (WR/2+WR*AY_max*cg/tw/2)*AY_max];
% frontF(1,:) = [0 -(WF/2 -WF*AX_min*cg/l/2)*AX_min 0];
% rearF(1,:) = [W*AX_max/2 -(WR/2 +WR*AX_min*cg/l/2)*AX_min 0];
%% Section 19: Plot Results