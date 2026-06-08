function [y] = lat_solve_TbSht(x, V, a, b, l, WDF, R, CoP, Cl, WRF, WRR, IA_staticf, IA_gainf, IA_staticr, IA_gainr, WF, WR, twf, twr, cg, W, LLTD, rg_f, rg_r, casterf, casterr, deltar, sf_y, full_send_y, grip, Cd, T_lock, KPIf, KPIr)
%lat_solve Lateral quasi-static solve
%   Performs a quasi-static solution of the the lateral dynamics of the
%   vehicle. Vehicle props are given as anonymous function:
%   ( @(x) lat_solve(x, {vehicle props}...) )
%   returns y:
%       y(1): Fy residual
%       y(2): Mz residual
%   use fsolve to solve y(:) = 0
%
%   deltar (rear steer) is given as a (constant) vehicle prop. could be
%   redefined as a function mapped against some inputs to evaluate a rear
%   steer effect.

delta = x(1);
beta = x(2);
%delta=l/R;
%beta=0;

a = l*(1-WDF);
b = l*WDF;

% update downforce
DF = Cl*V^2;
% from downforce, update suspension travel (in):
dxf = DF*CoP/2/WRF;
dxr = DF*(1-CoP)/2/WRR;
% from suspension heave, update static camber (rad):
IA_0f = IA_staticf - dxf*IA_gainf;
IA_0r = IA_staticr - dxr*IA_gainr;
% update load on each axle (lbs)
wf = (WF+DF*CoP)/2;
wr = (WR+DF*(1-CoP))/2;

A_y = V^2/R;
% calculate lateral load transfer (lbs)
WT = A_y*cg*W/mean([twf twr])/32.2/12;
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
IA_f_in = -twf*sin(phif)*12/2*IA_gainf - IA_0f - KPIf*(1-cos(delta)) - casterf*sin(delta) +phif;
IA_f_out = -twf*sin(phif)*12/2*IA_gainf + IA_0f + KPIf*(1-cos(delta)) - casterf*sin(delta) + phif;
IA_r_in = -twr*sin(phir)*12/2*IA_gainr - IA_0r - KPIr*(1-cos(deltar)) - casterr*sin(deltar) +phir;
IA_r_out = -twr*sin(phir)*12/2*IA_gainr + IA_0r + KPIr*(1-cos(deltar)) - casterr*sin(deltar) + phir;

% calculate yaw rate
r = A_y/V;

% from yaw, sideslip and steer you can get slip angles
a_f = beta+a*r/V-delta;

a_r = beta-b*r/V;

% with slip angles, load and camber, calculate lateral force at
% the front
F_fin = -fnval(full_send_y,{-rad2deg(a_f) -wfin -rad2deg(IA_f_in)})*sf_y*cos(delta);
F_fout = fnval(full_send_y,{rad2deg(a_f) -wfout -rad2deg(IA_f_out)})*sf_y*cos(delta);

% before you calculate the rears, you ned to see what the diff is
% doing
% calculate the drag from aero and the front tires
F_x = Cd*V^2 + (F_fin+F_fout)*sin(delta)/cos(delta);
% calculate the grip penalty assuming the rears must overcome that
% drag
rscale = 1-(F_x/W/fnval(grip,V))^2;
% now calculate rear tire forces, with said penalty
F_rin = -fnval(full_send_y,{-rad2deg(a_r) -wrin -rad2deg(IA_r_in)})*sf_y*rscale;
F_rout = fnval(full_send_y,{rad2deg(a_r) -wrout -rad2deg(IA_r_out)})*sf_y*rscale;

% sum of forces and moments

F_y = (F_fin+F_fout+F_rin+F_rout) - ((W*A_y) / 32.2);
M_z_diff = F_x*T_lock*twr/2; % incl the differential contribution
M_z = (F_fin+F_fout)*a-(F_rin+F_rout)*b-M_z_diff;

%latG = A_y/32.2;
Fs = [F_fin,F_fout,F_rin,F_rout];
y(1) = F_y; y(2) = M_z;
end
