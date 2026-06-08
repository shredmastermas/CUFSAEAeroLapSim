function telemetry = buildValidationTelemetry(eventName, timeElapsed, distance, velocity, acceleration, lateralAccel, gearCounter)
%buildValidationTelemetry Pack simulated trace channels for data correlation.
%   The output is intentionally narrow: these are the channels most useful
%   for comparing the sim to GPS/IMU/CAN logs by distance or by time.

n = min([numel(timeElapsed), numel(distance), numel(velocity), numel(acceleration), numel(lateralAccel), numel(gearCounter)]);
event = repmat(string(eventName), n, 1);
timeElapsed = timeElapsed(:);
distance = distance(:);
velocity = velocity(:);
acceleration = acceleration(:);
lateralAccel = lateralAccel(:);
gearCounter = gearCounter(:);

telemetry = table(event, ...
    timeElapsed(1:n), distance(1:n), velocity(1:n), acceleration(1:n), lateralAccel(1:n), gearCounter(1:n), ...
    'VariableNames', ["Event","Time_s","Distance_ft","Speed_ft_s","Longitudinal_G","Lateral_G","Gear"]);
end
