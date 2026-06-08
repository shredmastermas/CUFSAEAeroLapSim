function [c, ceq] = cAlpha_nonlcon(x, V, a, b, l, WDF, R, IA_staticf, IA_gainf, IA_staticr, IA_gainr, WF, WR, twf, twr, cg, W, LLTD, rg_f, rg_r, casterf, casterr, deltar, sf_y, A, grip, Cd, T_lock, KPIf, KPIr,fnCl,fnCoP,fnCd,RHfi,RHri,kRF,kRR,dxf,dxr,x_prev,nCa)

% Calculates local cornering stiffness to constrain against on-center
% cornering stiffness

delta = x(1);
beta  = x(2);


%% First, calculate slip angle, Fz, and IA
a = l*(1-WDF);
b = l*WDF;

dxf = 0;
dxr = 0;

% update downforce
[DFf,DFr,RHf,RHr,~,Cd,~,dxf,dxr] = aeroMapfn(fnCl,fnCoP,fnCd,RHfi,RHri,V,kRF,kRR,dxf,dxr);
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
% F_fin = -fnval(full_send_y,{-rad2deg(a_f) -wfin -rad2deg(IA_f_in)})*sf_y*cos(delta);
% F_fout = fnval(full_send_y,{rad2deg(a_f) -wfout -rad2deg(IA_f_out)})*sf_y*cos(delta);

% before you calculate the rears, you ned to see what the diff is
% doing
% calculate the drag from aero and the front tires
F_x = Cd*V^2 + (F_fin+F_fout)*sin(delta)/cos(delta);
% calculate the grip penalty assuming the rears must overcome that
% drag
longitudinalGrip = max(fnval(grip,V), eps);
rscale = max(0, 1-(F_x/W/longitudinalGrip)^2);

%% Now calculate local cornering stiffness

dAlpha = 0.05; % small pertubation in slip angle [deg]

ar1 = rad2deg(a_r)-dAlpha;
ar2 = rad2deg(a_r)+dAlpha;

Fy1 = MF52_Fy_fcn(A,[ar1,wrout,-rad2deg(IA_r_out)])*sf_y*rscale + MF52_Fy_fcn(A,[ar1,wrin,-rad2deg(IA_r_in)])*sf_y*rscale;
Fy2 = MF52_Fy_fcn(A,[ar2,wrout,-rad2deg(IA_r_out)])*sf_y*rscale + MF52_Fy_fcn(A,[ar2,wrin,-rad2deg(IA_r_in)])*sf_y*rscale;

C_ar = (Fy2-Fy1)./(2*dAlpha); % Local Cornering Stiffness [lb/deg]

%% Compare to on-center cornering stiffness:
ar1_0 = -dAlpha;
ar2_0 = dAlpha;

Fy1_0 = MF52_Fy_fcn(A,[ar1_0,wrout,-rad2deg(IA_r_out)])*sf_y*rscale + MF52_Fy_fcn(A,[ar1_0,wrin,-rad2deg(IA_r_in)])*sf_y*rscale;
Fy2_0 = MF52_Fy_fcn(A,[ar2_0,wrout,-rad2deg(IA_r_out)])*sf_y*rscale + MF52_Fy_fcn(A,[ar2_0,wrin,-rad2deg(IA_r_in)])*sf_y*rscale;

C_ar0 = (Fy2_0-Fy1_0)./(2*dAlpha); % On-center Cornering Stiffness [lb/deg]

c = C_ar - nCa*C_ar0;   % must be <= 0
ceq = [];
end
