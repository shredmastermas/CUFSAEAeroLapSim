function [J] = lat_objective(x, V, a, b, l, WDF, R, IA_staticf, IA_gainf, IA_staticr, IA_gainr, WF, WR, twf, twr, cg, W, LLTD, rg_f, rg_r, casterf, casterr, deltar, sf_y, A, grip, Cd, T_lock, KPIf, KPIr,fnCl,fnCoP,fnCd,RHfi,RHri,kRF,kRR,dxf,dxr,x_prev)

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

%% First, calculate residuals per usual:

y = lat_solve(x, V, a, b, l, WDF, R, IA_staticf, IA_gainf, IA_staticr, IA_gainr, WF, WR, twf, twr, cg, W, LLTD, rg_f, rg_r, casterf, casterr, deltar, sf_y, A, grip, Cd, T_lock, KPIf, KPIr,fnCl,fnCoP,fnCd,RHfi,RHri,kRF,kRR,dxf,dxr);

%% Define weighted objective function

% weights:
Fy_Scale = W; % Lateral Force Normalization (set as vehicle weight)
Mz_Scale = (W*WDF)*(l*(1-WDF)); % Yaw Moment Normalization (set as yaw moment imposed by front axle mass)
wDelta = 0.1;
wBeta = 0.05;

% Objective Function:
J = (y(1)/Fy_Scale)^2 + (y(2)/Mz_Scale)^2 + wDelta*(x(1)-x_prev(1))^2 + wBeta*(x(2)-x_prev(2))^2;
end