function lapSimRoot = setupLapSimPaths(lapSimRoot)
%setupLapSimPaths Add the reorganized 2026 lap sim folders to MATLAB path.

if nargin < 1 || isempty(lapSimRoot)
    lapSimRoot = fileparts(mfilename('fullpath'));
end

addpath(genpath(lapSimRoot));
fprintf('Lap sim path added: %s\n', lapSimRoot);
end
