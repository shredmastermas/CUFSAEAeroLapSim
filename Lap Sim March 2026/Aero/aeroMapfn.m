function [DFf,DFr,RHf,RHr,Cl,Cd,CoP,dxf,dxr] = aeroMapfn(fnCl,fnCoP,fnCd,RHfi,RHri,V,WRF,WRR,dxf,dxr)
%aeroMapfn Calculate aero loads and ride-height response.
%   fnCl/fnCoP/fnCd can be scatteredInterpolants or simple function handles.

RHf = RHfi - dxf;
RHr = RHri - dxr;
tol = 1e-3;
maxIter = 25;

for iter = 1:maxIter
    RHfPrev = RHf;
    RHrPrev = RHr;

    Cl = abs(fnCl(RHf,RHr));
    CoP = fnCoP(RHf,RHr);
    Cd = fnCd(RHf,RHr);

    DF = Cl * V^2;
    DFf = DF * CoP;
    DFr = DF * (1 - CoP);

    dxf = DFf / WRF;
    dxr = DFr / WRR;
    RHf = RHfi - dxf;
    RHr = RHri - dxr;

    if abs(RHf - RHfPrev) < tol && abs(RHr - RHrPrev) < tol
        return
    end
end
end
