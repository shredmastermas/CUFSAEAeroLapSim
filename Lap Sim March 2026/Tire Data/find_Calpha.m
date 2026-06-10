function [c,ceq] = find_Calpha(A,X)

% Solves 

% Calpha: Local Cornering Stiffness [lb/deg]

% X = [alpha [deg], Fz [lb], IA [deg]]

dAlpha = 0.01; % small pertubation in slip angle [deg]

X1 = X;
X2 = X;


% First, find local cornering stiffness
X1(:,1) = X1(:,1) - dAlpha;
X2(:,1) = X2(:,1) + dAlpha;

Fy1 = MF52_Fy_fcn(A,X1);
Fy2 = MF52_Fy_fcn(A,X2);

Calpha = (Fy2-Fy1)./(2*dAlpha); % Cornering Stiffness [lb/deg]