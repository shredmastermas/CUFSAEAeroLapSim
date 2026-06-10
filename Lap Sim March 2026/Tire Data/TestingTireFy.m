clear
clc
close all

filename = 'Hoosier_LCO_16.0x7.5-10_FY_10psi';
load(filename)
IA = 0;
delta = deg2rad(10);
results = [];
sf_y = 0.5;



for sa = -12:12
    for fz = 0:300
        fy = fnval(full_send_y,{sa -fz -IA})*sf_y*cos(delta);
        results = [results; sa,fz,fy];
    end
end

figure
plot3(results(:,1),results(:,2),results(:,3),'.')

hold on

filename = 'Hoosier R20 16x7.5-10 12 Psi Final FY';
load(filename)
results = [];



for sa = -12:12
    for fz = 0:300
        fy = fnval(full_send_y,{sa -fz -IA})*sf_y*cos(delta);
        results = [results; sa,fz,fy];
    end
end

plot3(results(:,1),results(:,2),results(:,3),'.')
hold off
xlabel('Slip Angle [deg]')
ylabel('Normal Load (Fz) [lb]')
zlabel('Lateral Force (Fy) [lb]')
legend({'LC0','R20'},'FontSize',16)
%zlim([-1000,1000])

