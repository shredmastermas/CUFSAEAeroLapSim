%% Run_T27_AeroSweep
% Batch runner for Lap_Sim_constantAero_T27V4.m
% Purpose: sweep CL, CD, and CoP targets to find better T27 aero goals.
%
% HOW TO USE:
% 1) Put this file in the same folder as Lap_Sim_constantAero_T27V4.m and all
%    lap sim dependency files (.mat tire data, track coordinate files, etc.).
% 2) Edit the three sweep vectors below.
% 3) Run this file. It will create ranked CSV and MAT result files.
%
% IMPORTANT:
% In this lap sim, CL and CD are used as force coefficients:
%   Downforce = CL * V^2
%   Drag      = CD * V^2
% with V in ft/s and force in lbf. These may not be the same as CFD
% nondimensional coefficients unless your aeroMapfn used the same scaling.

clear; clc;
T27_NO_CLEAR = true;
T27_WRITE_OUTPUTS = false;
T27_EXPORT_VALIDATION = false;
T27_PLOT_RESULTS = false;

%% 1) Edit these ranges for your T27 study
% Start coarse first. A huge sweep can take a long time because every row
% runs the full lap sim.
T27_CL_list  = 0.040:0.010:0.140;      % downforce coefficient used by lap sim
T27_CD_list  = 0.010:0.005:0.060;      % drag coefficient used by lap sim
T27_CoP_list = 0.375:0.025:0.575;      % front aero distribution, 0.45 = 45% front

% Optional: baseline row to compare against. Put your current car/aero here.
T27_baselineCL  = 0.080;
T27_baselineCD  = 0.020;
T27_baselineCoP = 0.450;
T27_targetCoP = 0.450;

% Output files
T27_outputCsv = 'T27_AeroSweep_ranked_results.csv';
T27_outputMat = 'T27_AeroSweep_results.mat';

%% 2) Build the sweep list
[CLg, CDg, CoPg] = ndgrid(T27_CL_list, T27_CD_list, T27_CoP_list);
T27_combos = [CLg(:), CDg(:), CoPg(:)];

% Force the baseline to be included as the first row for comparison.
T27_combos = [[T27_baselineCL, T27_baselineCD, T27_baselineCoP]; T27_combos];
T27_combos = unique(T27_combos, 'rows', 'stable');
T27_nCombos = size(T27_combos,1);

fprintf('\nStarting T27 aero sweep with %d total runs.\n', T27_nCombos);
fprintf('Coarse sweeps are recommended before fine sweeps.\n\n');

%% 3) Run every aero combination
T27_SWEEP_ACTIVE = true;
T27_resultsAll = table();
T27_baselineTotal = NaN;

for T27_i = 1:T27_nCombos
    CL_target  = T27_combos(T27_i,1);
    CD_target  = T27_combos(T27_i,2);
    CoP_target = T27_combos(T27_i,3);
    aeroTag = sprintf('CL_%0.3f_CD_%0.3f_CoP_%0.3f',CL_target,CD_target,CoP_target);
    sweepRunIndex = T27_i;
    sweepTotalRuns = T27_nCombos;

    try
        run('Lap_Sim_constantAero_T27V4.m');

        aeroTargetResults.RunNumber = T27_i;

        T27_resultsAll = [T27_resultsAll; aeroTargetResults]; %#ok<AGROW>

        % Save progress every run so you do not lose everything if one later
        % run fails or MATLAB is stopped.
        T27_baselineTotal = resolveBaselineTotal(T27_resultsAll, T27_baselineCL, T27_baselineCD, T27_baselineCoP);
        T27_progressResults = addPostMetrics(T27_resultsAll, T27_baselineTotal, T27_baselineCL, T27_baselineCD, T27_targetCoP);
        T27_rankedSoFar = sortrows(T27_progressResults, 'Total_Points', 'descend');
        writetable(T27_rankedSoFar, T27_outputCsv);
        save(T27_outputMat, 'T27_resultsAll', 'T27_rankedSoFar', 'T27_combos', ...
            'T27_CL_list', 'T27_CD_list', 'T27_CoP_list', 'T27_baselineTotal', 'T27_targetCoP');

    catch ME
        warning('Sweep run %d failed for CL=%0.4f, CD=%0.4f, CoP=%0.3f: %s', ...
            T27_i, CL_target, CD_target, CoP_target, ME.message);

        failedRow = table(string(aeroTag), CL_target, CD_target, CoP_target, string(ME.message), T27_i, ...
            'VariableNames', ["AeroTag","CL_target","CD_target","CoP_target","ErrorMessage","RunNumber"]);
        writetable(failedRow, 'T27_AeroSweep_failed_runs.csv', 'WriteMode', 'append');
    end
end

if isempty(T27_resultsAll)
    error('No successful sweep runs completed. Check T27_AeroSweep_failed_runs.csv and MATLAB errors.');
end

T27_baselineTotal = resolveBaselineTotal(T27_resultsAll, T27_baselineCL, T27_baselineCD, T27_baselineCoP);
T27_resultsAll = addPostMetrics(T27_resultsAll, T27_baselineTotal, T27_baselineCL, T27_baselineCD, T27_targetCoP);

%% 4) Rank and split the results into useful target buckets
T27_ranked = sortrows(T27_resultsAll, 'Total_Points', 'descend');
T27_bestTotal = T27_ranked(1:min(10,height(T27_ranked)),:);
T27_bestAutocross = sortrows(T27_resultsAll, 'Autocross_Score', 'descend');
T27_bestEndurance = sortrows(T27_resultsAll, 'Endurance_Score', 'descend');
T27_bestSkidpad = sortrows(T27_resultsAll, 'Skidpad_Score', 'descend');
T27_bestEfficiency = sortrows(T27_resultsAll, 'CL_over_CD', 'descend');
T27_bestBalanced = sortrows(T27_resultsAll, {'BalanceError','Total_Points'}, {'ascend','descend'});

writetable(T27_ranked, 'T27_AeroSweep_ranked_results.csv');
writetable(T27_bestTotal, 'T27_AeroSweep_top10_total.csv');
writetable(T27_bestAutocross(1:min(10,height(T27_bestAutocross)),:), 'T27_AeroSweep_top10_autocross.csv');
writetable(T27_bestEndurance(1:min(10,height(T27_bestEndurance)),:), 'T27_AeroSweep_top10_endurance.csv');
writetable(T27_bestSkidpad(1:min(10,height(T27_bestSkidpad)),:), 'T27_AeroSweep_top10_skidpad.csv');
writetable(T27_bestEfficiency(1:min(10,height(T27_bestEfficiency)),:), 'T27_AeroSweep_top10_efficiency.csv');
writetable(T27_bestBalanced(1:min(10,height(T27_bestBalanced)),:), 'T27_AeroSweep_top10_balanced.csv');
save(T27_outputMat);

fprintf('\nT27 aero sweep complete. Best total-points setup:\n');
disp(T27_bestTotal(1,:));
fprintf('\nPrimary output: %s\n', T27_outputCsv);

%% Local helper functions
function baselineTotal = resolveBaselineTotal(T, baselineCL, baselineCD, baselineCoP)
    tol = 1e-12;
    baselineMask = abs(T.CL_target - baselineCL) <= tol & ...
                   abs(T.CD_target - baselineCD) <= tol & ...
                   abs(T.CoP_target - baselineCoP) <= tol;
    if any(baselineMask)
        baselineTotal = T.Total_Points(find(baselineMask, 1, 'first'));
    else
        baselineTotal = T.Total_Points(1);
    end
end

function T = addPostMetrics(T, baselineTotal, baselineCL, baselineCD, targetCoP)
    T.CL_over_CD = T.CL_target ./ max(T.CD_target, eps);
    T.PointGain_vs_Baseline = T.Total_Points - baselineTotal;
    T.CD_Increase_vs_Baseline = T.CD_target - baselineCD;
    T.CL_Increase_vs_Baseline = T.CL_target - baselineCL;
    T.PointGain_per_CD = T.PointGain_vs_Baseline ./ max(T.CD_Increase_vs_Baseline, eps);
    T.BalanceError = abs(T.CoP_target - targetCoP);
    T.FrontAeroPercent = T.CoP_target * 100;
    T.RearAeroPercent = (1 - T.CoP_target) * 100;
end
