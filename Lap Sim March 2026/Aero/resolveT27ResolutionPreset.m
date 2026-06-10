function [fastMode, velocityStep, radiiStep, lateralStep, presetLabel] = resolveT27ResolutionPreset(presetLabel, fastMode, velocityStep, radiiStep, lateralStep, showPicker)
%resolveT27ResolutionPreset Resolve named lap-sim resolution presets.
%   Presets keep sweep setup repeatable while Custom preserves manually supplied
%   step sizes. Set showPicker true to show an interactive selector in MATLAB.

    if nargin < 1 || isempty(presetLabel); presetLabel = "Custom"; end
    if nargin < 2 || isempty(fastMode); fastMode = true; end
    if nargin < 3 || isempty(velocityStep); velocityStep = 2; end
    if nargin < 4 || isempty(radiiStep); radiiStep = 10; end
    if nargin < 5 || isempty(lateralStep); lateralStep = 0.25; end
    if nargin < 6 || isempty(showPicker); showPicker = false; end

    presetOptions = ["High", "Medium", "Low", "Custom"];
    presetLabel = string(presetLabel);

    if showPicker
        canShowPicker = usejava('desktop') && feature('ShowFigureWindows');
        if canShowPicker
            initialValue = find(strcmpi(presetOptions, presetLabel), 1, 'first');
            if isempty(initialValue); initialValue = 2; end
            [selection, ok] = listdlg('PromptString', 'Select lap sim resolution:', ...
                'SelectionMode', 'single', ...
                'ListString', cellstr(presetOptions), ...
                'InitialValue', initialValue, ...
                'ListSize', [220 95]);
            if ok
                presetLabel = presetOptions(selection);
            end
        else
            warning('Resolution picker requested, but MATLAB desktop UI is unavailable. Using preset %s.', presetLabel);
        end
    end

    switch lower(strtrim(presetLabel))
        case "high"
            presetLabel = "High";
            fastMode = false;
            velocityStep = 1;
            radiiStep = 5;
            lateralStep = 0.10;
        case "medium"
            presetLabel = "Medium";
            fastMode = true;
            velocityStep = 2;
            radiiStep = 10;
            lateralStep = 0.25;
        case "low"
            presetLabel = "Low";
            fastMode = true;
            velocityStep = 3;
            radiiStep = 15;
            lateralStep = 0.50;
        case "custom"
            presetLabel = "Custom";
            fastMode = logical(fastMode);
        otherwise
            error('Unknown T27 resolution preset: %s. Use High, Medium, Low, or Custom.', presetLabel);
    end
end
