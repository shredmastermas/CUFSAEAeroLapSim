%% Run_T27_AeroSweep_FastExcel
% Faster batch runner for Lap_Sim_constantAero_T27V4.m
% It runs a coarse aero sweep in FAST MODE, exports a viewable Excel file,
% and can optionally rerun the best fast cases in accurate mode.
%
% HOW TO USE:
% 1) Put this file in the same folder as Lap_Sim_constantAero_T27V4.m and all
%    lap sim dependency files.
% 2) Run this file in MATLAB.
% 3) Open T27_AeroSweep_Fast_Results.xlsx.
%
% IMPORTANT:
% Fast mode reduces GGV resolution, turns plots off, and is for target
% screening. Use the accurate rerun section for final numbers.

clear; clc;

%% 1) User settings
% Set this to true for the broad first-pass sweep.
T27_FAST_MODE = true;
T27_PLOT_RESULTS = false;
T27_NO_CLEAR = true;
T27_WRITE_OUTPUTS = false;
T27_EXPORT_VALIDATION = false;

% Fast mode resolution. Larger numbers = faster but less accurate.
T27_velocityStep = 2;    % original = 1 ft/s
T27_radiiStep    = 10;   % original = 5 ft
T27_lateralStep  = 0.25; % original = 0.10 ft/s cornering search step

% Coarse aero grid. Add/remove values here.
T27_CL_list  = 0.040:0.020:0.160;
T27_CD_list  = 0.010:0.010:0.070;
T27_CoP_list = 0.375:0.050:0.575;

% Baseline/current car estimate for point-gain comparisons.
T27_baselineCL  = 0.080;
T27_baselineCD  = 0.020;
T27_baselineCoP = 0.450;

% Desired aero balance target for ranking.
T27_targetCoP = 0.450;

% Optional accurate rerun of the best fast cases.
% Keep this small because accurate mode is slow.
T27_RERUN_TOP_ACCURATE = true;
T27_topN_accurate = 10;

% Output files.
T27_outputXlsx = 'T27_AeroSweep_Fast_Results.xlsx';
T27_progressCsv = 'T27_AeroSweep_Fast_progress_ranked.csv';
T27_outputMat = 'T27_AeroSweep_Fast_Results.mat';
T27_failedCsv = 'T27_AeroSweep_Fast_failed_runs.csv';

if isfile(T27_outputXlsx); delete(T27_outputXlsx); end
if isfile(T27_progressCsv); delete(T27_progressCsv); end
if isfile(T27_failedCsv); delete(T27_failedCsv); end

%% 2) Build sweep combinations
[CLg, CDg, CoPg] = ndgrid(T27_CL_list, T27_CD_list, T27_CoP_list);
T27_combos = [CLg(:), CDg(:), CoPg(:)];
T27_combos = [[T27_baselineCL, T27_baselineCD, T27_baselineCoP]; T27_combos];
T27_combos = unique(T27_combos, 'rows', 'stable');
T27_nCombos = size(T27_combos,1);

fprintf('\nFAST T27 aero sweep starting: %d combinations.\n', T27_nCombos);
fprintf('Resolution: velocity step %g ft/s, radius step %g ft, lateral step %g ft/s.\n', ...
    T27_velocityStep, T27_radiiStep, T27_lateralStep);
fprintf('Plots off: %d\n\n', ~T27_PLOT_RESULTS);

%% 3) Run fast sweep
T27_SWEEP_ACTIVE = true;
T27_resultsAll = table();
T27_failedRuns = table();
T27_baselineTotal = NaN;

for T27_i = 1:T27_nCombos
    CL_target  = T27_combos(T27_i,1);
    CD_target  = T27_combos(T27_i,2);
    CoP_target = T27_combos(T27_i,3);
    aeroTag = sprintf('FAST_CL_%0.3f_CD_%0.3f_CoP_%0.3f', CL_target, CD_target, CoP_target);
    sweepRunIndex = T27_i;
    sweepTotalRuns = T27_nCombos;

    try
        run('Lap_Sim_constantAero_T27V4.m');

        aeroTargetResults.RunNumber = T27_i;
        aeroTargetResults.RunMode = "Fast";

        T27_resultsAll = [T27_resultsAll; aeroTargetResults]; %#ok<AGROW>
        T27_baselineTotal = resolveBaselineTotal(T27_resultsAll, T27_baselineCL, T27_baselineCD, T27_baselineCoP);
        T27_progressResults = addPostMetrics(T27_resultsAll, T27_baselineTotal, T27_baselineCL, T27_baselineCD, T27_targetCoP);
        T27_rankedSoFar = sortrows(T27_progressResults, 'Total_Points', 'descend');
        writetable(T27_rankedSoFar, T27_progressCsv);
        save(T27_outputMat, 'T27_resultsAll', 'T27_failedRuns', 'T27_rankedSoFar', ...
            'T27_combos', 'T27_baselineTotal', 'T27_FAST_MODE', 'T27_velocityStep', ...
            'T27_radiiStep', 'T27_lateralStep', 'T27_targetCoP');

    catch ME
        warning('FAST run %d failed for CL=%0.4f, CD=%0.4f, CoP=%0.3f: %s', ...
            T27_i, CL_target, CD_target, CoP_target, ME.message);
        failedRow = table(T27_i, string(aeroTag), CL_target, CD_target, CoP_target, string(ME.message), ...
            'VariableNames', ["RunNumber","AeroTag","CL_target","CD_target","CoP_target","ErrorMessage"]);
        T27_failedRuns = [T27_failedRuns; failedRow]; %#ok<AGROW>
        writetable(T27_failedRuns, T27_failedCsv);
    end
end

if isempty(T27_resultsAll)
    error('No successful fast runs completed. Check failed run CSV and MATLAB errors.');
end

T27_baselineTotal = resolveBaselineTotal(T27_resultsAll, T27_baselineCL, T27_baselineCD, T27_baselineCoP);
T27_resultsAll = addPostMetrics(T27_resultsAll, T27_baselineTotal, T27_baselineCL, T27_baselineCD, T27_targetCoP);

%% 4) Build fast ranked tables
T27_rankedTotal = sortrows(T27_resultsAll, 'Total_Points', 'descend');
T27_rankedAutocross = sortrows(T27_resultsAll, 'Autocross_Score', 'descend');
T27_rankedEndurance = sortrows(T27_resultsAll, 'Endurance_Score', 'descend');
T27_rankedSkidpad = sortrows(T27_resultsAll, 'Skidpad_Score', 'descend');
T27_rankedAccel = sortrows(T27_resultsAll, 'Accel_Score', 'descend');
T27_rankedEfficiency = sortrows(T27_resultsAll, {'CL_over_CD','Total_Points'}, {'descend','descend'});
T27_rankedBalanced = sortrows(T27_resultsAll, {'BalanceError','Total_Points'}, {'ascend','descend'});
T27_rankedPointPerDrag = sortrows(T27_resultsAll, {'PointGain_per_CD','Total_Points'}, {'descend','descend'});

N = min(25, height(T27_resultsAll));
T27_bestSummary = [
    addBucketName(T27_rankedTotal(1,:), "Best Fast Total Points")
    addBucketName(T27_rankedAutocross(1,:), "Best Fast Autocross")
    addBucketName(T27_rankedEndurance(1,:), "Best Fast Endurance")
    addBucketName(T27_rankedSkidpad(1,:), "Best Fast Skidpad")
    addBucketName(T27_rankedAccel(1,:), "Best Fast Acceleration")
    addBucketName(T27_rankedEfficiency(1,:), "Best Fast CL/CD")
    addBucketName(T27_rankedBalanced(1,:), "Closest Fast CoP Balance")
    addBucketName(T27_rankedPointPerDrag(1,:), "Best Fast Points per CD")
];
T27_bestSummary = movevars(T27_bestSummary, 'Bucket', 'Before', 1);

T27_CL_sensitivity = groupsummary(T27_resultsAll, 'CL_target', {'mean','max'}, {'Total_Points','Autocross_Score','Endurance_Score','Skidpad_Score','Accel_Score'});
T27_CD_sensitivity = groupsummary(T27_resultsAll, 'CD_target', {'mean','max'}, {'Total_Points','Autocross_Score','Endurance_Score','Skidpad_Score','Accel_Score'});
T27_CoP_sensitivity = groupsummary(T27_resultsAll, 'CoP_target', {'mean','max'}, {'Total_Points','Autocross_Score','Endurance_Score','Skidpad_Score','Accel_Score'});

%% 5) Optional accurate rerun of top fast cases
T27_accurateResults = table();
T27_accurateFailedRuns = table();

if T27_RERUN_TOP_ACCURATE
    T27_topN_accurate = min(T27_topN_accurate, height(T27_rankedTotal));
    T27_accurateCombos = [T27_rankedTotal.CL_target(1:T27_topN_accurate), ...
                          T27_rankedTotal.CD_target(1:T27_topN_accurate), ...
                          T27_rankedTotal.CoP_target(1:T27_topN_accurate)];

    fprintf('\nAccurate rerun starting for top %d fast setups.\n', T27_topN_accurate);

    % Switch back to original accurate GGV resolution.
    T27_FAST_MODE = false;
    T27_PLOT_RESULTS = false;
    T27_velocityStep = 1;
    T27_radiiStep = 5;
    T27_lateralStep = 0.10;

    for T27_j = 1:T27_topN_accurate
        CL_target  = T27_accurateCombos(T27_j,1);
        CD_target  = T27_accurateCombos(T27_j,2);
        CoP_target = T27_accurateCombos(T27_j,3);
        aeroTag = sprintf('ACCURATE_CL_%0.3f_CD_%0.3f_CoP_%0.3f', CL_target, CD_target, CoP_target);
        sweepRunIndex = T27_j;
        sweepTotalRuns = T27_topN_accurate;

        try
            run('Lap_Sim_constantAero_T27V4.m');
            aeroTargetResults.RunNumber = T27_j;
            aeroTargetResults.RunMode = "AccurateRerun";
            T27_accurateResults = [T27_accurateResults; aeroTargetResults]; %#ok<AGROW>
        catch ME
            warning('ACCURATE rerun %d failed for CL=%0.4f, CD=%0.4f, CoP=%0.3f: %s', ...
                T27_j, CL_target, CD_target, CoP_target, ME.message);
            failedRow = table(T27_j, string(aeroTag), CL_target, CD_target, CoP_target, string(ME.message), ...
                'VariableNames', ["RunNumber","AeroTag","CL_target","CD_target","CoP_target","ErrorMessage"]);
            T27_accurateFailedRuns = [T27_accurateFailedRuns; failedRow]; %#ok<AGROW>
        end
    end
end

if ~isempty(T27_accurateResults)
    T27_accurateResults = addPostMetrics(T27_accurateResults, T27_baselineTotal, T27_baselineCL, T27_baselineCD, T27_targetCoP);
    T27_accurateRanked = sortrows(T27_accurateResults, 'Total_Points', 'descend');
else
    T27_accurateRanked = table();
end

%% 6) Export Excel workbook
writetable(T27_bestSummary,                 T27_outputXlsx, 'Sheet', 'Best Summary');
writetable(T27_rankedTotal,                 T27_outputXlsx, 'Sheet', 'All Fast Ranked');
writetable(T27_rankedTotal(1:N,:),          T27_outputXlsx, 'Sheet', 'Top Fast Total');
writetable(T27_rankedAutocross(1:N,:),      T27_outputXlsx, 'Sheet', 'Top Fast Autocross');
writetable(T27_rankedEndurance(1:N,:),      T27_outputXlsx, 'Sheet', 'Top Fast Endurance');
writetable(T27_rankedSkidpad(1:N,:),        T27_outputXlsx, 'Sheet', 'Top Fast Skidpad');
writetable(T27_rankedEfficiency(1:N,:),     T27_outputXlsx, 'Sheet', 'Top Fast CL CD');
writetable(T27_rankedBalanced(1:N,:),       T27_outputXlsx, 'Sheet', 'Top Fast CoP');
writetable(T27_rankedPointPerDrag(1:N,:),   T27_outputXlsx, 'Sheet', 'Top Fast Points per CD');
writetable(T27_CL_sensitivity,              T27_outputXlsx, 'Sheet', 'CL Sensitivity');
writetable(T27_CD_sensitivity,              T27_outputXlsx, 'Sheet', 'CD Sensitivity');
writetable(T27_CoP_sensitivity,             T27_outputXlsx, 'Sheet', 'CoP Sensitivity');

if ~isempty(T27_accurateRanked)
    writetable(T27_accurateRanked,           T27_outputXlsx, 'Sheet', 'Accurate Rerun Ranked');
end
if ~isempty(T27_failedRuns)
    writetable(T27_failedRuns,               T27_outputXlsx, 'Sheet', 'Fast Failed Runs');
end
if ~isempty(T27_accurateFailedRuns)
    writetable(T27_accurateFailedRuns,       T27_outputXlsx, 'Sheet', 'Accurate Failed Runs');
end

save(T27_outputMat);

fprintf('\nFast aero sweep complete.\n');
fprintf('Best fast setup:\n');
disp(T27_rankedTotal(1,:));
if ~isempty(T27_accurateRanked)
    fprintf('\nBest accurate rerun setup:\n');
    disp(T27_accurateRanked(1,:));
end
fprintf('\nOpen this Excel workbook: %s\n', T27_outputXlsx);

%% Local helper
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

function out = addBucketName(row, bucketName)
    out = row;
    out.Bucket = string(bucketName);
end
