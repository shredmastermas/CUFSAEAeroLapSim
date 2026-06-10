function forceLimit = evalLongitudinalTireLimit(full_send_x, slipRatios, wheelLoad, camberRad, sf_x, limitMode)
%evalLongitudinalTireLimit Return peak longitudinal tire force for one tire.
%   Vectorizes the slip-ratio sweep that used to run as a small inner loop
%   inside the accel and brake envelope calculations.

slipRatios = slipRatios(:)';
queryPoints = [
    slipRatios
    -wheelLoad * ones(size(slipRatios))
    rad2deg(-camberRad) * ones(size(slipRatios))
];

forces = fnval(queryPoints, full_send_x) * sf_x;
forces(abs(forces) > 1000) = NaN;
validForces = forces(~isnan(forces));

if isempty(validForces)
    forceLimit = NaN;
elseif strcmpi(string(limitMode), "min")
    forceLimit = min(validForces);
else
    forceLimit = max(validForces);
end
end
