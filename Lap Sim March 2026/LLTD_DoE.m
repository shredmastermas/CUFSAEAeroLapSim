x = input('!!! STOP !!! \nAre you sure you want to clear all results and rerun the sim? [Y/N]:\n','s');
if strcmpi(x,'n')
    error('User terminated run')
end
clear
clc
close all
totPts = [];
accPts = [];
skidPts = [];
autoXPts = [];
enduroPts = [];
AYmax = [];
AXmax = [];
AXmin = [];
dists = [];
AXs = [];
AYs = [];
Vels = [];
weights = [];
skidTime = [];
accWeight = [];
turnWeight = [];
brakeWeight = [];
Results = struct();
LLTDs = 30:5:70;
for i = 1:length(LLTDs)
    LLTD = LLTDs(i);
    [Total_Points,Accel_Score,Skidpad_Score,Autocross_Score,Endurance_Score,skidpad_time,AY_max,AX_max,AX_min,distance_ax,acceleration_ax,lateral_accel_ax,velocity_ax,weights_ax,vehicle_path_AX,time_elapsed_ax,brakeResults,accResults,latResults] = Lap_Sim_fminconSp26(LLTD);
    totPts = [totPts; Total_Points];
    accPts = [accPts; Accel_Score];
    skidPts = [skidPts; Skidpad_Score];
    autoXPts = [autoXPts; Autocross_Score];
    enduroPts = [enduroPts; Endurance_Score];
    skidTime = [skidTime; skidpad_time];
    AYmax = [AYmax; AY_max];
    AXmax = [AXmax; AX_max];
    AXmin = [AXmin; AX_min];
    dists = [dists;distance_ax];
    AXs = [AXs;acceleration_ax];
    AYs = [AYs;lateral_accel_ax];
    Vels = [Vels;velocity_ax];
    accWeight = [accWeight;weights_ax(1)];
    brakeWeight = [brakeWeight;weights_ax(2)];
    turnWeight = [turnWeight;weights_ax(3)];
    accResults = table2struct(accResults);
    brakeResults = table2struct(brakeResults);
    latResults = table2struct(latResults);
    Results(i).LLTD = LLTD;
    Results(i).totalPts = Total_Points;
    Results(i).skidPts = Skidpad_Score;
    Results(i).autoXPts = Autocross_Score;
    Results(i).enduroPts = Endurance_Score;
    Results(i).brakeResults = brakeResults;
    Results(i).accResults = accResults;
    Results(i).latResults = latResults;
    Results(i).Time = time_elapsed_ax;
    Results(i).Dists = distance_ax;
    Results(i).Velocities = velocity_ax;
    Results(i).AYs = lateral_accel_ax;
    Results(i).AXs = acceleration_ax;
    Results(i).Path = vehicle_path_AX;
    Results(i).weights = weights;
    results = table(LLTDs(1:i)',totPts,accPts,skidPts,autoXPts,enduroPts,skidTime,AYmax,AXmax,AXmin,accWeight,brakeWeight,turnWeight)
end

save("latestLLTDResults.mat");

%%
% Specify filepath for Aero Map Data
aeroMap = "Z:\FSAE 2026\Engineering\01 - Aerodynamics Division\08 - CFD Files\08-04 CFD Results\Aero Map\Aero Map Data.xlsx";

% Load data from excel file
%cl = readmatrix('C:\Users\ptgas\OneDrive - Clemson University\Documents\FSAE-Personal\Lap Sim\Lap Sim\Aero Map Data.xlsx','Range','V2:V28');
cl = readmatrix(aeroMap,'Range','V2:V28');
%cd = readmatric('C:\Users\ptgas\OneDrive - Clemson University\Documents\FSAE-Personal\Lap Sim\Lap Sim\Aero Map Data.xlsx','Range','W2:W28');
cd = readmatrix(aeroMap,'Range','W2:W28');
%cop = readmatrix('C:\Users\ptgas\OneDrive - Clemson University\Documents\FSAE-Personal\Lap Sim\Lap Sim\Aero Map Data.xlsx','Range','Q2:Q28');
cop = readmatrix(aeroMap,'Range','Q2:Q28');
RHF = readmatrix(aeroMap,'Range','C2:C28');
RHR = readmatrix(aeroMap,'Range','D2:D28');
ClCd = cl./cd;
data = {
1.00	1.00	-2.03
1.25	1.25	-2.14
1.50	1.50	-1.99
1.75	1.75	-2.09
2.00	2.00	-1.89
2.25	2.25	-1.87
1.00	1.25	-2.13
1.25	1.50	-2.16
1.25	1.75	-2.35
1.25	2.00	-2.33
1.35	2.00	-2.29
1.25	2.25	-2.09
1.50	1.75	-2.14
1.50	2.00	-2.20
1.50	2.25	-2.19
1.75	2.00	-2.00
1.75	2.25	-1.97
2.00	2.25	-1.95
1.50	1.25	-2.08
2.00	1.25	-1.86
2.25	1.50	-1.80
2.25	2.00	-1.89};

% x = RHF;
% y = RHR;
% z = ClCd;

x = vertcat(data{:,1});
y = vertcat(data{:,2});
z = vertcat(data{:,3});

N = 1000;
[X, Y] = meshgrid(linspace(min(x), max(x), N), linspace(min(y), max(y), N));
F = scatteredInterpolant(x, y, z,'natural','nearest');
Z = F(X, Y);

%% Post Process Results
close all
% Define a custom color order with 10 unique colors
customColors = [
    0, 0, 0.5;  % Color 1 (RGB)
    0, 0, 1;  % Color 2 (RGB)
    0, 0.5, 0.5;  % Color 3 (RGB)
    0, 1, 0.5;  % Color 4 (RGB)
    0, 1, 0;  % Color 5 (RGB)
    0.5, 1, 0;  % Color 6 (RGB)
    0.5, 0.5, 0;  % Color 7 (RGB)
    1, 0.5, 0;  % Color 8 (RGB)
    1, 0, 0;  % Color 9 (RGB)
    0.5, 0, 0   % Color 10 (RGB)
];

%LLTDs = 0.1:0.1:0.8;
% Plot AutoX pts vs pitch grad
figure('Name','Points Scored')
subplot(5,1,1)
plot(LLTDs,autoXPts,'-*')
ylabel('Points')
title('AutoX Points')
grid on
subplot(5,1,2)
plot(LLTDs,enduroPts,'-*')
ylabel('Points')
title('Enduro Points')
grid on
subplot(5,1,3)
plot(LLTDs,skidPts,'-*')
ylabel('Points')
title('Skid Points')
grid on
subplot(5,1,4)
plot(LLTDs,accPts,'-*')
ylabel('Points')
title('Acceleration Points')
grid on
subplot(5,1,5)
plot(LLTDs,totPts,'-*')
xlabel('LLTD [% Front]')
ylabel('Points')
title('Total Points')
grid on
% Path
Dists = sqrt(diff(vehicle_path_AX(1,:)).^2 + diff(vehicle_path_AX(2,:)).^2);
totDists = sum(Dists);
cumDists = [0,cumsum(Dists)]; % kekW
figure('Name','AutoX Map')
scatter(vehicle_path_AX(1,:),vehicle_path_AX(2,:),100,cumDists',"filled")
title('Autocross Track')
d = colorbar;
set(get(d,'title'),'string','Distance [ft]');

% Velocity
figure('Name','Velocity Trace')
set(gca, 'ColorOrder', customColors, 'NextPlot', 'replacechildren');
for i = 1:height(dists)
    plot(dists(i,:),Vels(i,:),'-x','MarkerSize',2)
    hold on
end
xlabel('Distance [ft]')
ylabel('Velocity [ft/s]')
title('Velocity Trace')
legend('LLTD=30','LLTD=35','LLTD=40','LLTD=45','LLTD=50','LLTD=55','LLTD=60','LLTD=65','LLTD=70','Location','best')
grid on;
hold off

figure('Name','Velocity Diff')
set(gca, 'ColorOrder', customColors, 'NextPlot', 'replacechildren');
for i = 1:height(dists)
    plot(dists(i,:),Vels(i,:)-Vels(end,:),'-*')
    hold on
end
xlabel('Distance [ft]')
ylabel('Velocity [ft/s]')
title('Velocity Diff')
legend('LLTD=30','LLTD=35','LLTD=40','LLTD=45','LLTD=50','LLTD=55','LLTD=60','LLTD=65','LLTD=70','Location','best')
grid on;
hold off


% Lateral Accel

figure('Name','Lat. Accel Capability')
set(gca, 'ColorOrder', customColors, 'NextPlot', 'replacechildren');
for i = 1:length(LLTDs)
    AYs = [Results(i).latResults.latG].';
    r = [Results(i).latResults.Radius].';
    plot(r,AYs,'-*')
    hold on
end
xlabel('Corner Radius [ft]')
ylabel('Lat. Accel [G]')
title('Lateral Accel Capability')
legend('LLTD=30','LLTD=35','LLTD=40','LLTD=45','LLTD=50','LLTD=55','LLTD=60','LLTD=65','LLTD=70','Location','best')
grid on;
hold off
xlim([15,155])

figure('Name','Cornering Velocity')
set(gca, 'ColorOrder', customColors, 'NextPlot', 'replacechildren');
for i = 1:length(LLTDs)
    Vs = [Results(i).latResults.speed].';
    plot(r,Vs,'-')
    hold on
end
xlabel('Corner Radius [ft]')
ylabel('Velocity [ft/s]')
title('Cornering Velocity')
legend('LLTD=30','LLTD=35','LLTD=40','LLTD=45','LLTD=50','LLTD=55','LLTD=60','LLTD=65','LLTD=70','Location','best')
grid on;
hold off
xlim([15,155])

figure('Name','US Angle')
set(gca, 'ColorOrder', customColors, 'NextPlot', 'replacechildren');
for i = 1:length(LLTDs)
    AYs = [Results(i).latResults.Radius].';
    UGs = [Results(i).latResults.USAngle].';
    plot(AYs,UGs,'-*')
    hold on
end
xlabel('Corner Radius [ft]')
ylabel('Understeer Angle [deg]')
title('Understeer Angle')
legend('LLTD=30','LLTD=35','LLTD=40','LLTD=45','LLTD=50','LLTD=55','LLTD=60','LLTD=65','LLTD=70','Location','best')
grid on;
hold off
%xlim([15,155])

figure('Name','Sideslip')
set(gca, 'ColorOrder', customColors, 'NextPlot', 'replacechildren');
for i = 1:length(LLTDs)
    Bs = [Results(i).latResults.Beta].';
    plot(r,Bs,'-*')
    hold on
end
xlabel('Corner Radius [ft]')
ylabel('Sideslip [deg]')
title('Sideslip')
legend('LLTD=30','LLTD=35','LLTD=40','LLTD=45','LLTD=50','LLTD=55','LLTD=60','LLTD=65','LLTD=70','Location','best')
yline(0, 'k');
grid on;
hold off
xlim([15,155])
ylim([-12,12])


figure('Name','AY vs. Steering')
set(gca, 'ColorOrder', customColors, 'NextPlot', 'replacechildren');
for i = 1:length(LLTDs)
    Steer = [Results(i).latResults.steering];
    Gs = [Results(i).latResults.latG].';
    plot(Steer,Gs,'-*')
    hold on
end
xlabel('Steering [deg]')
ylabel('Lateral Accel [G]')
title('AY v Steer')
legend('LLTD=30','LLTD=35','LLTD=40','LLTD=45','LLTD=50','LLTD=55','LLTD=60','LLTD=65','LLTD=70','Location','best')
yline(0, 'k');
%xlim([0,24])
%ylim([0,2.5])
grid on;
hold off

figure('Name','Steering')
set(gca, 'ColorOrder', customColors, 'NextPlot', 'replacechildren');
for i = 1:length(LLTDs)
    Steer = [Results(i).latResults.steering];
    Rs = [Results(i).latResults.Radius].';
    plot(Rs,Steer,'-*')
    hold on
end
ylabel('Steering [deg]')
xlabel('Corner Radius [ft]')
title('Steering vs. Radii')
legend('LLTD=30','LLTD=35','LLTD=40','LLTD=45','LLTD=50','LLTD=55','LLTD=60','LLTD=65','LLTD=70','Location','best')
%yline(0, 'k');
%xlim([0,24])
%ylim([0,2.5])
grid on;
hold off