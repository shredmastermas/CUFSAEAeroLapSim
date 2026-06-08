WDF=[40:1:60];
filename = 'WDF_Cornering_Sweep.xlsx';

for i = 1:length(WDF)
    fprintf('Running WDF = %.1f%%\n', WDF(i));
    [Total_Points,Accel_Score,Skidpad_Score,Autocross_Score,Endurance_Score,AY_max,AX_max] = Lap_Sim(WDF(i))
    x_prev = [0.2521, 0.02]; %reset x_prev for each WDF
    V_guess = 8;                   % <-- also reset V_guess here
    
      % Pull the cornering table saved by Lap_Sim via global
  global latResults_out
    sheetName = sprintf('WDF = %d%%', WDF(i));
    writetable(latResults_out, filename, 'Sheet', sheetName);
    fprintf('  -> Written sheet: %s\n', sheetName);
end

disp('Done - check WDF_Cornering_Sweep.xlsx')