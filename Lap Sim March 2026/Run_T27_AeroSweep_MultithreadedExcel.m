%% Run_T27_AeroSweep_MultithreadedExcel
% Multithreaded batch runner for Lap_Sim_constantAero_T27V4.m
% This uses MATLAB's Parallel Computing Toolbox to run independent aero
% cases at the same time with parfor, then exports a multi-sheet Excel file.
%
% HOW TO USE:
% 1) Put this file in the same folder as Lap_Sim_constantAero_T27V4.m and all
%    lap sim dependency files.
% 2) Run this file in MATLAB:
%       Run_T27_AeroSweep_MultithreadedExcel
% 3) Open T27_AeroSweep_Multithreaded_Results.xlsx.
%
% IMPORTANT GPU NOTE:
% This lap sim is mostly fmincon, spline interpolation, tire-model calls,
% and track/lap integration. That workload is not automatically GPU-fast.
% The best speedup is CPU parallelism because each CL/CD/CoP case is an
% independent simulation. GPU support would require rewriting inner math
% using gpuArray-compatible functions, and fmincon itself will not run on
% the GPU in the normal way.

if ~exist('T27_KEEP_WORKSPACE','var') || ~T27_KEEP_WORKSPACE
    clear; clc;
end

%% 1) User settings
if ~exist('T27_FAST_MODE','var') || isempty(T27_FAST_MODE); T27_FAST_MODE = true; end
if ~exist('T27_PLOT_RESULTS','var') || isempty(T27_PLOT_RESULTS); T27_PLOT_RESULTS = false; end
if ~exist('T27_EXPORT_VALIDATION','var') || isempty(T27_EXPORT_VALIDATION); T27_EXPORT_VALIDATION = false; end

% Set true to use parpool/parfor. If unavailable, the script falls back to serial.
if ~exist('T27_USE_PARALLEL','var') || isempty(T27_USE_PARALLEL); T27_USE_PARALLEL = true; end

% Leave false unless someone rewrites the tire/optimization internals for gpuArray.
if ~exist('T27_USE_GPU','var') || isempty(T27_USE_GPU); T27_USE_GPU = false; end

% Choose worker count. [] lets MATLAB decide. Start with physical cores, not max threads.
% Example: T27_NUM_WORKERS = 6;
if ~exist('T27_NUM_WORKERS','var'); T27_NUM_WORKERS = []; end

% Fast mode resolution. Larger values = faster but less accurate.
if ~exist('T27_velocityStep','var') || isempty(T27_velocityStep); T27_velocityStep = 2; end    % original = 1 ft/s
if ~exist('T27_radiiStep','var') || isempty(T27_radiiStep); T27_radiiStep = 10; end            % original = 5 ft
if ~exist('T27_lateralStep','var') || isempty(T27_lateralStep); T27_lateralStep = 0.25; end    % original = 0.10 ft/s cornering search step
if ~exist('T27_targetSpeedsMph','var') || isempty(T27_targetSpeedsMph); T27_targetSpeedsMph = [35 45 60]; end

% Feasibility caps keep the workbook from treating impossible aero as a design target.
% Current defaults reflect expected CUFSAE aero capability at about 15 m/s / 35 mph.
if ~exist('T27_feasibilityRefSpeedMph','var') || isempty(T27_feasibilityRefSpeedMph); T27_feasibilityRefSpeedMph = 35; end
if ~exist('T27_minFeasibleDownforceAtRef_lbf','var') || isempty(T27_minFeasibleDownforceAtRef_lbf); T27_minFeasibleDownforceAtRef_lbf = 90; end
if ~exist('T27_maxFeasibleDownforceAtRef_lbf','var') || isempty(T27_maxFeasibleDownforceAtRef_lbf); T27_maxFeasibleDownforceAtRef_lbf = 135; end
if ~exist('T27_targetFeasibleLiftToDrag','var') || isempty(T27_targetFeasibleLiftToDrag); T27_targetFeasibleLiftToDrag = 2.2; end
if ~exist('T27_feasibleLiftToDragTolerance','var') || isempty(T27_feasibleLiftToDragTolerance); T27_feasibleLiftToDragTolerance = 0.2; end
if ~exist('T27_minFeasibleLiftToDrag','var') || isempty(T27_minFeasibleLiftToDrag); T27_minFeasibleLiftToDrag = T27_targetFeasibleLiftToDrag - T27_feasibleLiftToDragTolerance; end
if ~exist('T27_maxFeasibleLiftToDrag','var') || isempty(T27_maxFeasibleLiftToDrag); T27_maxFeasibleLiftToDrag = T27_targetFeasibleLiftToDrag + T27_feasibleLiftToDragTolerance; end
if ~exist('T27_minFeasibleDragAtRef_lbf','var') || isempty(T27_minFeasibleDragAtRef_lbf); T27_minFeasibleDragAtRef_lbf = 40; end
if ~exist('T27_maxFeasibleDragAtRef_lbf','var') || isempty(T27_maxFeasibleDragAtRef_lbf); T27_maxFeasibleDragAtRef_lbf = 65; end

% Coarse aero grid. Add/remove values here. Defaults focus on the realistic
% 90-135 lbf downforce and roughly L/D 2.2 target range at 35 mph.
if ~exist('T27_CL_list','var') || isempty(T27_CL_list); T27_CL_list = 0.035:0.005:0.055; end
if ~exist('T27_CD_list','var') || isempty(T27_CD_list); T27_CD_list = 0.015:0.0025:0.030; end
if ~exist('T27_CoP_list','var') || isempty(T27_CoP_list); T27_CoP_list = 0.425:0.025:0.525; end

% Baseline/current car estimate for point-gain comparisons.
if ~exist('T27_baselineCL','var') || isempty(T27_baselineCL); T27_baselineCL = 0.080; end
if ~exist('T27_baselineCD','var') || isempty(T27_baselineCD); T27_baselineCD = 0.020; end
if ~exist('T27_baselineCoP','var') || isempty(T27_baselineCoP); T27_baselineCoP = 0.450; end

% Desired aero balance target for ranking.
if ~exist('T27_targetCoP','var') || isempty(T27_targetCoP); T27_targetCoP = 0.450; end

% Optional accurate rerun of the best fast cases. Accurate reruns can also be parallel.
if ~exist('T27_RERUN_TOP_ACCURATE','var') || isempty(T27_RERUN_TOP_ACCURATE); T27_RERUN_TOP_ACCURATE = true; end
if ~exist('T27_topN_accurate','var') || isempty(T27_topN_accurate); T27_topN_accurate = 10; end

% Output files.
if ~exist('T27_outputXlsx','var') || isempty(T27_outputXlsx); T27_outputXlsx = 'T27_AeroSweep_Multithreaded_Results.xlsx'; end
if ~exist('T27_outputMat','var') || isempty(T27_outputMat); T27_outputMat = 'T27_AeroSweep_Multithreaded_Results.mat'; end
if ~exist('T27_failedCsv','var') || isempty(T27_failedCsv); T27_failedCsv = 'T27_AeroSweep_Multithreaded_failed_runs.csv'; end

if isfile(T27_outputXlsx); delete(T27_outputXlsx); end
if isfile(T27_failedCsv); delete(T27_failedCsv); end

thisFolder = fileparts(mfilename('fullpath'));
if isempty(thisFolder); thisFolder = pwd; end
coreFile = fullfile(thisFolder, 'Lap_Sim_constantAero_T27V4.m');
if ~isfile(coreFile)
    error('Could not find Lap_Sim_constantAero_T27V4.m in: %s', thisFolder);
end
addpath(thisFolder);

%% 2) Build sweep combinations
[CLg, CDg, CoPg] = ndgrid(T27_CL_list, T27_CD_list, T27_CoP_list);
T27_combos = [CLg(:), CDg(:), CoPg(:)];
T27_combos = [[T27_baselineCL, T27_baselineCD, T27_baselineCoP]; T27_combos];
T27_combos = unique(T27_combos, 'rows', 'stable');
T27_nCombos = size(T27_combos, 1);

fprintf('\nT27 parallel aero sweep starting: %d combinations.\n', T27_nCombos);
fprintf('Fast mode: %d | velocity step %g ft/s | radius step %g ft | lateral step %g ft/s\n', ...
    T27_FAST_MODE, T27_velocityStep, T27_radiiStep, T27_lateralStep);

%% 3) Start parallel pool if available
T27_PARALLEL_ACTIVE = false;
if T27_USE_PARALLEL
    try
        pool = gcp('nocreate');
        if isempty(pool)
            if isempty(T27_NUM_WORKERS)
                pool = parpool;
            else
                pool = parpool(T27_NUM_WORKERS);
            end
        end
        T27_PARALLEL_ACTIVE = true;
        fprintf('Parallel pool active with %d workers.\n', pool.NumWorkers);
    catch ME
        warning('Could not start parpool. Falling back to serial. Reason: %s', ME.message);
        T27_PARALLEL_ACTIVE = false;
    end
end

if T27_USE_GPU
    try
        gpuInfo = gpuDevice;
        fprintf('GPU detected: %s. Note: this script does not offload fmincon/tire solver to GPU.\n', gpuInfo.Name);
    catch ME
        warning('GPU requested, but no usable GPU was found: %s', ME.message);
    end
end

%% 4) Run fast sweep
fastRows = cell(T27_nCombos, 1);
fastErrors = cell(T27_nCombos, 1);

if T27_PARALLEL_ACTIVE
    parfor T27_i = 1:T27_nCombos
        [fastRows{T27_i}, fastErrors{T27_i}] = runOneAeroCase(coreFile, thisFolder, ...
            T27_combos(T27_i, :), T27_i, T27_nCombos, "Fast", true, false, ...
            T27_velocityStep, T27_radiiStep, T27_lateralStep, T27_USE_GPU);
    end
else
    for T27_i = 1:T27_nCombos
        [fastRows{T27_i}, fastErrors{T27_i}] = runOneAeroCase(coreFile, thisFolder, ...
            T27_combos(T27_i, :), T27_i, T27_nCombos, "Fast", true, false, ...
            T27_velocityStep, T27_radiiStep, T27_lateralStep, T27_USE_GPU);
        fprintf('Completed fast run %d/%d.\n', T27_i, T27_nCombos);
    end
end

T27_resultsAll = vertcatNonEmpty(fastRows);
T27_failedRuns = vertcatNonEmpty(fastErrors);

if isempty(T27_resultsAll)
    if ~isempty(T27_failedRuns); writetable(T27_failedRuns, T27_failedCsv); end
    error('No successful fast runs completed. Check failed run CSV and MATLAB errors.');
end

T27_baselineTotal = resolveBaselineTotal(T27_resultsAll, T27_baselineCL, T27_baselineCD, T27_baselineCoP);
T27_resultsAll = addPostMetrics(T27_resultsAll, T27_baselineTotal, T27_baselineCL, T27_baselineCD, T27_targetCoP);
T27_resultsAll = addAeroForceColumns(T27_resultsAll, T27_targetSpeedsMph);
T27_resultsAll = addFeasibilityColumns(T27_resultsAll, T27_feasibilityRefSpeedMph, ...
    T27_minFeasibleDownforceAtRef_lbf, T27_maxFeasibleDownforceAtRef_lbf, ...
    T27_minFeasibleLiftToDrag, T27_maxFeasibleLiftToDrag, ...
    T27_minFeasibleDragAtRef_lbf, T27_maxFeasibleDragAtRef_lbf);

%% 5) Build fast ranked tables
T27_rankedTotal        = sortrows(T27_resultsAll, 'Total_Points', 'descend');
T27_rankedAutocross    = sortrows(T27_resultsAll, 'Autocross_Score', 'descend');
T27_rankedEndurance    = sortrows(T27_resultsAll, 'Endurance_Score', 'descend');
T27_rankedSkidpad      = sortrows(T27_resultsAll, 'Skidpad_Score', 'descend');
T27_rankedAccel        = sortrows(T27_resultsAll, 'Accel_Score', 'descend');
T27_rankedEfficiency   = sortrows(T27_resultsAll, {'CL_over_CD','Total_Points'}, {'descend','descend'});
T27_rankedBalanced     = sortrows(T27_resultsAll, {'BalanceError','Total_Points'}, {'ascend','descend'});
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

T27_CL_sensitivity  = groupsummary(T27_resultsAll, 'CL_target',  {'mean','max'}, {'Total_Points','Autocross_Score','Endurance_Score','Skidpad_Score','Accel_Score'});
T27_CD_sensitivity  = groupsummary(T27_resultsAll, 'CD_target',  {'mean','max'}, {'Total_Points','Autocross_Score','Endurance_Score','Skidpad_Score','Accel_Score'});
T27_CoP_sensitivity = groupsummary(T27_resultsAll, 'CoP_target', {'mean','max'}, {'Total_Points','Autocross_Score','Endurance_Score','Skidpad_Score','Accel_Score'});

%% 6) Optional accurate rerun of top fast cases
T27_accurateResults = table();
T27_accurateFailedRuns = table();
T27_accurateRanked = table();

if T27_RERUN_TOP_ACCURATE
    T27_topN_accurate = min(T27_topN_accurate, height(T27_rankedTotal));
    T27_accurateCombos = [T27_rankedTotal.CL_target(1:T27_topN_accurate), ...
                          T27_rankedTotal.CD_target(1:T27_topN_accurate), ...
                          T27_rankedTotal.CoP_target(1:T27_topN_accurate)];

    fprintf('\nAccurate rerun starting for top %d fast setups.\n', T27_topN_accurate);
    accurateRows = cell(T27_topN_accurate, 1);
    accurateErrors = cell(T27_topN_accurate, 1);

    if T27_PARALLEL_ACTIVE
        parfor T27_j = 1:T27_topN_accurate
            [accurateRows{T27_j}, accurateErrors{T27_j}] = runOneAeroCase(coreFile, thisFolder, ...
                T27_accurateCombos(T27_j, :), T27_j, T27_topN_accurate, "AccurateRerun", false, false, ...
                1, 5, 0.10, T27_USE_GPU);
        end
    else
        for T27_j = 1:T27_topN_accurate
            [accurateRows{T27_j}, accurateErrors{T27_j}] = runOneAeroCase(coreFile, thisFolder, ...
                T27_accurateCombos(T27_j, :), T27_j, T27_topN_accurate, "AccurateRerun", false, false, ...
                1, 5, 0.10, T27_USE_GPU);
            fprintf('Completed accurate rerun %d/%d.\n', T27_j, T27_topN_accurate);
        end
    end

    T27_accurateResults = vertcatNonEmpty(accurateRows);
    T27_accurateFailedRuns = vertcatNonEmpty(accurateErrors);
    if ~isempty(T27_accurateResults)
        T27_accurateResults = addPostMetrics(T27_accurateResults, T27_baselineTotal, T27_baselineCL, T27_baselineCD, T27_targetCoP);
        T27_accurateResults = addAeroForceColumns(T27_accurateResults, T27_targetSpeedsMph);
        T27_accurateResults = addFeasibilityColumns(T27_accurateResults, T27_feasibilityRefSpeedMph, ...
            T27_minFeasibleDownforceAtRef_lbf, T27_maxFeasibleDownforceAtRef_lbf, ...
            T27_minFeasibleLiftToDrag, T27_maxFeasibleLiftToDrag, ...
            T27_minFeasibleDragAtRef_lbf, T27_maxFeasibleDragAtRef_lbf);
        T27_accurateRanked = sortrows(T27_accurateResults, 'Total_Points', 'descend');
    end
end

%% 7) Build combined best-overall target tables
T27_allResults = T27_resultsAll;
if ~isempty(T27_accurateResults)
    T27_allResults = [T27_allResults; T27_accurateResults];
end
T27_allRanked = sortrows(T27_allResults, 'Total_Points', 'descend');
T27_bestOverall = T27_allRanked(1,:);
T27_bestOverallTargets = buildAeroTargetTable(T27_bestOverall, T27_targetSpeedsMph);
T27_bestOverallSummaryRow = addBucketName(T27_bestOverall, "Best Overall Total Points");
T27_bestOverallSummaryRow = movevars(T27_bestOverallSummaryRow, 'Bucket', 'Before', 1);

T27_feasibleResults = T27_allResults(T27_allResults.IsFeasibleAeroTarget,:);
T27_feasibleRanked = sortrows(T27_feasibleResults, 'Total_Points', 'descend');
T27_bestFeasible = table();
T27_bestFeasibleTargets = table();
if ~isempty(T27_feasibleRanked)
    T27_bestFeasible = T27_feasibleRanked(1,:);
    T27_bestFeasibleTargets = buildAeroTargetTable(T27_bestFeasible, T27_targetSpeedsMph);
    T27_bestFeasibleSummaryRow = addBucketName(T27_bestFeasible, "Best Feasible Total Points");
    T27_bestFeasibleSummaryRow = movevars(T27_bestFeasibleSummaryRow, 'Bucket', 'Before', 1);
    T27_bestSummary = [T27_bestOverallSummaryRow; T27_bestFeasibleSummaryRow; T27_bestSummary];
else
    T27_bestSummary = [T27_bestOverallSummaryRow; T27_bestSummary];
end

%% 8) Export Excel workbook
writetable(T27_bestSummary,                 T27_outputXlsx, 'Sheet', 'Best Summary');
writetable(T27_bestOverall,                 T27_outputXlsx, 'Sheet', 'Best Overall');
writetable(T27_bestOverallTargets,          T27_outputXlsx, 'Sheet', 'Best Overall Targets');
if ~isempty(T27_bestFeasible)
    writetable(T27_bestFeasible,            T27_outputXlsx, 'Sheet', 'Best Feasible');
    writetable(T27_bestFeasibleTargets,     T27_outputXlsx, 'Sheet', 'Best Feasible Targets');
    writetable(T27_feasibleRanked,          T27_outputXlsx, 'Sheet', 'All Feasible Ranked');
end
writetable(T27_allRanked,                   T27_outputXlsx, 'Sheet', 'All Results Ranked');
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
    writetable(T27_failedRuns,               T27_failedCsv);
end
if ~isempty(T27_accurateFailedRuns)
    writetable(T27_accurateFailedRuns,       T27_outputXlsx, 'Sheet', 'Accurate Failed Runs');
end

save(T27_outputMat);

fprintf('\nMultithreaded aero sweep complete.\n');
fprintf('Best overall setup across all result modes:\n');
disp(T27_bestOverall);
if ~isempty(T27_bestFeasible)
    fprintf('Best feasible setup using %g mph, DF %g-%g lbf, drag %g-%g lbf, L/D %g-%g:\n', ...
        T27_feasibilityRefSpeedMph, T27_minFeasibleDownforceAtRef_lbf, ...
        T27_maxFeasibleDownforceAtRef_lbf, T27_minFeasibleDragAtRef_lbf, ...
        T27_maxFeasibleDragAtRef_lbf, T27_minFeasibleLiftToDrag, T27_maxFeasibleLiftToDrag);
    disp(T27_bestFeasible);
else
    fprintf('No feasible setup met the configured downforce/drag limits. Check feasibility settings.\n');
end
fprintf('Best fast setup:\n');
disp(T27_rankedTotal(1,:));
if ~isempty(T27_accurateRanked)
    fprintf('\nBest accurate rerun setup:\n');
    disp(T27_accurateRanked(1,:));
end
fprintf('\nOpen this Excel workbook: %s\n', T27_outputXlsx);

%% Local helper functions
function [row, errRow] = runOneAeroCase(coreFile, runFolder, combo, runIndex, totalRuns, runMode, fastMode, plotResults, velocityStep, radiiStep, lateralStep, useGpu)
    row = table();
    errRow = table();
    oldFolder = pwd;
    try
        cd(runFolder);
        addpath(runFolder);

        T27_SWEEP_ACTIVE = true; %#ok<NASGU>
        T27_NO_CLEAR = true; %#ok<NASGU>
        T27_PARALLEL_ACTIVE = true; %#ok<NASGU>
        T27_WRITE_OUTPUTS = false; %#ok<NASGU>
        T27_EXPORT_VALIDATION = false; %#ok<NASGU>
        T27_FAST_MODE = fastMode; %#ok<NASGU>
        T27_PLOT_RESULTS = plotResults; %#ok<NASGU>
        T27_velocityStep = velocityStep; %#ok<NASGU>
        T27_radiiStep = radiiStep; %#ok<NASGU>
        T27_lateralStep = lateralStep; %#ok<NASGU>
        T27_USE_GPU = useGpu; %#ok<NASGU>
        T27_WORKER_ID = runIndex; %#ok<NASGU>

        CL_target  = combo(1); %#ok<NASGU>
        CD_target  = combo(2); %#ok<NASGU>
        CoP_target = combo(3); %#ok<NASGU>
        aeroTag = sprintf('%s_CL_%0.3f_CD_%0.3f_CoP_%0.3f', runMode, combo(1), combo(2), combo(3)); %#ok<NASGU>
        sweepRunIndex = runIndex; %#ok<NASGU>
        sweepTotalRuns = totalRuns; %#ok<NASGU>

        % Capture command window spam from the lap sim so parallel output stays readable.
        evalc('run(coreFile);');

        row = aeroTargetResults;
        row.RunNumber = runIndex;
        row.RunMode = string(runMode);
    catch ME
        errRow = table(runIndex, string(runMode), combo(1), combo(2), combo(3), string(ME.message), ...
            'VariableNames', ["RunNumber","RunMode","CL_target","CD_target","CoP_target","ErrorMessage"]);
    end
    try
        cd(oldFolder);
    catch
    end
end

function T = vertcatNonEmpty(cellsIn)
    nonEmpty = cellsIn(~cellfun(@isempty, cellsIn));
    if isempty(nonEmpty)
        T = table();
    else
        T = vertcat(nonEmpty{:});
    end
end

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

function T = addAeroForceColumns(T, targetSpeedsMph)
    for k = 1:numel(targetSpeedsMph)
        speedMph = targetSpeedsMph(k);
        speedFps = speedMph * 5280 / 3600;
        speedLabel = strrep(sprintf('%g', speedMph), '.', 'p');

        totalDownforce = T.CL_target .* speedFps.^2;
        totalDrag = T.CD_target .* speedFps.^2;

        T.(sprintf('Speed_%smph_ft_s', speedLabel)) = repmat(speedFps, height(T), 1);
        T.(sprintf('DF_Total_%smph_lbf', speedLabel)) = totalDownforce;
        T.(sprintf('DF_Front_%smph_lbf', speedLabel)) = totalDownforce .* T.CoP_target;
        T.(sprintf('DF_Rear_%smph_lbf', speedLabel)) = totalDownforce .* (1 - T.CoP_target);
        T.(sprintf('Drag_Total_%smph_lbf', speedLabel)) = totalDrag;
        T.(sprintf('LiftToDrag_%smph', speedLabel)) = totalDownforce ./ max(totalDrag, eps);
    end
end

function T = addFeasibilityColumns(T, refSpeedMph, minDownforceRefLbf, maxDownforceRefLbf, minLiftToDrag, maxLiftToDrag, minDragRefLbf, maxDragRefLbf)
    refSpeedFps = refSpeedMph * 5280 / 3600;
    nRows = height(T);

    T.FeasibilityRefSpeed_mph = repmat(refSpeedMph, nRows, 1);
    T.FeasibilityRefSpeed_ft_s = repmat(refSpeedFps, nRows, 1);
    T.DF_Total_FeasRef_lbf = T.CL_target .* refSpeedFps.^2;
    T.Drag_Total_FeasRef_lbf = T.CD_target .* refSpeedFps.^2;
    T.LiftToDrag_FeasRef = T.DF_Total_FeasRef_lbf ./ max(T.Drag_Total_FeasRef_lbf, eps);

    if isempty(minDownforceRefLbf)
        dfMin = -inf;
        T.MinFeasibleDownforceAtRef_lbf = nan(nRows,1);
    else
        dfMin = minDownforceRefLbf;
        T.MinFeasibleDownforceAtRef_lbf = repmat(minDownforceRefLbf, nRows, 1);
    end

    if isempty(maxDownforceRefLbf)
        dfMax = inf;
        T.MaxFeasibleDownforceAtRef_lbf = nan(nRows,1);
    else
        dfMax = maxDownforceRefLbf;
        T.MaxFeasibleDownforceAtRef_lbf = repmat(maxDownforceRefLbf, nRows, 1);
    end

    if isempty(minLiftToDrag)
        ldMin = -inf;
        T.MinFeasibleLiftToDrag = nan(nRows,1);
    else
        ldMin = minLiftToDrag;
        T.MinFeasibleLiftToDrag = repmat(minLiftToDrag, nRows, 1);
    end

    if isempty(maxLiftToDrag)
        ldMax = inf;
        T.MaxFeasibleLiftToDrag = nan(nRows,1);
    else
        ldMax = maxLiftToDrag;
        T.MaxFeasibleLiftToDrag = repmat(maxLiftToDrag, nRows, 1);
    end

    if isempty(minDragRefLbf)
        dragFloor = -inf;
        T.MinFeasibleDragAtRef_lbf = nan(nRows,1);
    else
        dragFloor = minDragRefLbf;
        T.MinFeasibleDragAtRef_lbf = repmat(minDragRefLbf, nRows, 1);
    end

    if isempty(maxDragRefLbf)
        dragCeiling = inf;
        T.MaxFeasibleDragAtRef_lbf = nan(nRows,1);
    else
        dragCeiling = maxDragRefLbf;
        T.MaxFeasibleDragAtRef_lbf = repmat(maxDragRefLbf, nRows, 1);
    end

    belowDf = T.DF_Total_FeasRef_lbf < dfMin;
    exceedsDf = T.DF_Total_FeasRef_lbf > dfMax;
    belowLd = T.LiftToDrag_FeasRef < ldMin;
    exceedsLd = T.LiftToDrag_FeasRef > ldMax;
    belowDrag = T.Drag_Total_FeasRef_lbf < dragFloor;
    exceedsDrag = T.Drag_Total_FeasRef_lbf > dragCeiling;
    T.IsFeasibleAeroTarget = ~(belowDf | exceedsDf | belowLd | exceedsLd | belowDrag | exceedsDrag);

    notes = strings(nRows,1);
    notes(belowDf) = notes(belowDf) + "DF below target window; ";
    notes(exceedsDf) = notes(exceedsDf) + "DF exceeds cap; ";
    notes(belowLd) = notes(belowLd) + "L/D below target window; ";
    notes(exceedsLd) = notes(exceedsLd) + "L/D exceeds target window; ";
    notes(belowDrag) = notes(belowDrag) + "drag below target window; ";
    notes(exceedsDrag) = notes(exceedsDrag) + "drag exceeds target window; ";
    notes(notes == "") = "OK";
    T.FeasibilityNotes = notes;
end

function targetTable = buildAeroTargetTable(row, targetSpeedsMph)
    speedsMph = targetSpeedsMph(:);
    speedsFps = speedsMph * 5280 / 3600;
    nSpeeds = numel(speedsMph);

    aeroTag = repmat(string(row.AeroTag(1)), nSpeeds, 1);
    runMode = repmat(string(row.RunMode(1)), nSpeeds, 1);
    totalPoints = repmat(row.Total_Points(1), nSpeeds, 1);
    clTarget = repmat(row.CL_target(1), nSpeeds, 1);
    cdTarget = repmat(row.CD_target(1), nSpeeds, 1);
    copTarget = repmat(row.CoP_target(1), nSpeeds, 1);

    totalDownforce = clTarget .* speedsFps.^2;
    frontDownforce = totalDownforce .* copTarget;
    rearDownforce = totalDownforce .* (1 - copTarget);
    totalDrag = cdTarget .* speedsFps.^2;
    liftToDrag = totalDownforce ./ max(totalDrag, eps);
    frontAeroPercent = copTarget * 100;
    rearAeroPercent = (1 - copTarget) * 100;

    targetTable = table(aeroTag, runMode, totalPoints, speedsMph, speedsFps, ...
        clTarget, cdTarget, copTarget, frontAeroPercent, rearAeroPercent, ...
        totalDownforce, frontDownforce, rearDownforce, totalDrag, liftToDrag, ...
        'VariableNames', ["AeroTag","RunMode","Total_Points","Speed_mph","Speed_ft_s", ...
        "CL_target","CD_target","CoP_target","FrontAeroPercent","RearAeroPercent", ...
        "TotalDownforce_lbf","FrontDownforce_lbf","RearDownforce_lbf","TotalDrag_lbf","LiftToDrag"]);
end

function out = addBucketName(row, bucketName)
    out = row;
    out.Bucket = string(bucketName);
end
