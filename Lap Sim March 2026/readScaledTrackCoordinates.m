function data = readScaledTrackCoordinates(filename)
%readScaledTrackCoordinates Read the numeric Scaled sheet from a track file.

if exist('readmatrix','file') ~= 0
    data = readmatrix(filename, 'Sheet', 'Scaled');
else
    data = xlsread(filename, 'Scaled'); %#ok<XLSRD>
end

data = data(~all(isnan(data),2), :);
end
