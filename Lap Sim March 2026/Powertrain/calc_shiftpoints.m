function shiftpoints = calc_shiftpoints(final_drive, gear_ratios, torque_curve, redline, primary_reduction, tire_radius, rpm)

actual_gear_reductions = gear_ratios.*final_drive.*primary_reduction;

torque_curve_by_gear = (ones([6 length(rpm)])' .* actual_gear_reductions)' .* torque_curve;
power_by_gear = (torque_curve_by_gear .* rpm) ./ 9550;

speed_by_gear_by_rpm = (rpm ./ actual_gear_reductions' * tire_radius / 60 * (2*pi));
shiftpoints = ones([1, length(actual_gear_reductions) - 1]);
for i = 1:1:(length(actual_gear_reductions)-1)
    for j = 1:1:length(rpm)
        logical = speed_by_gear_by_rpm(i, j) > speed_by_gear_by_rpm(i+1, :);
        new_power = power_by_gear(i+1, find(logical, 1, "last"));
        current_power = power_by_gear(i, j);

        if new_power > current_power
            break
        end
    end

    shiftpoints(i) = rpm(j);

end

end