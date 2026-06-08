function [c,ceq] = track_curvature_sprint(path_positions, track_width)

global path_boundaries_ax
tw = track_width;
r_min = 14.75*2/tw;
path_boundaries = path_boundaries_ax;
if isempty(path_boundaries)
    error('path_boundaries_ax is empty. Load autocross track coordinates before calling track_curvature_sprint.');
end
nPathGates = min(numel(path_positions), size(path_boundaries,1));
if nPathGates < 3
    error('Autocross path needs at least 3 valid gate positions.');
end
path_positions = path_positions(1:nPathGates);
t = 1:1:length(path_positions);
path_points = zeros(length(path_positions),2);

for i = 1:1:length(path_positions)
    coeff = path_boundaries(i,1:2);
    x2 = max(path_boundaries(i,3:4));
    x1 = min(path_boundaries(i,3:4));
    position = path_positions(i);
    x3 = x1+position*(x2-x1);
    y3 = polyval(coeff,x3);
    path_points(i,:) = [x3 y3];
%     if i >= 3
%         [L,R,K] = curvature([path_points(i-2:i,1) path_points(i-2:i,2)]);
%         R = R(2);
%         while  R < r_min
%             
end
% x = linspace(1,t(end-1),length(path_points)*5);
% ppv = interp1([1:length(path_points)],path_points,x,'makima');
% vehicle_path = ppv;
% [L,R1,K] = curvature(vehicle_path);
% %R1 = R1(~isnan(R1));
% for i = 1:length(path_points)
%     for j = 1:5
%         ind =5*i-5+j;
%         radii(j) = R1(ind);
%     end
%     R(i) = min(radii);
% end
        

[L,R,K] = curvature(path_points);
R = R(~isnan(R));
R = -R+.75*r_min;
c = R;     % Compute nonlinear inequalities at x.
ceq = zeros(length(R),1);   % Compute nonlinear equalities at x.
