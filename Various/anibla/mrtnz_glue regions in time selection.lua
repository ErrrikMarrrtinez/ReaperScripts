--@noindex
--NoIndex: true



function MergeRegionsInTimeSelection()
    -- Get the time selection range
    local isLoopPoints = false
    local start_time, end_time = reaper.GetSet_LoopTimeRange2(0, false, isLoopPoints, 0, 0, false)
    
    -- Check if there's a time selection
    if end_time - start_time == 0 then
      reaper.ShowMessageBox("No time selection found. Please make a time selection first.", "Error", 0)
      return
    end

    local _, numMarkers, numRegions = reaper.CountProjectMarkers(0)
    if numRegions == 0 then 
      reaper.ShowMessageBox("No regions found in project.", "Error", 0)
      return 
    end
    
    reaper.Undo_BeginBlock()
    reaper.PreventUIRefresh(1)
    

    local regionsToMerge = {}
    local min_pos = math.huge
    local max_end = 0
    local merged_name = ""
    local separator = "; "
    local region_count = 0
    
    for i = 0, numMarkers + numRegions - 1 do
      local _, isRegion, pos, rgnEnd, name, regionIndex, color = reaper.EnumProjectMarkers3(0, i)
      if isRegion and pos >= start_time and rgnEnd <= end_time then
        table.insert(regionsToMerge, {
          index = regionIndex,
          pos = pos,
          endPos = rgnEnd,
          name = name,
          color = color
        })
        

        if pos < min_pos then min_pos = pos end
        if rgnEnd > max_end then max_end = rgnEnd end
        

        if region_count > 0 then
          merged_name = merged_name .. separator
        end
        merged_name = merged_name .. name
        
        region_count = region_count + 1
      end
    end
    

    if region_count == 0 then
      reaper.ShowMessageBox("No regions found within time selection.", "Info", 0)
      reaper.PreventUIRefresh(-1)
      reaper.Undo_EndBlock("Attempt to merge regions", -1)
      return
    elseif region_count == 1 then
      reaper.ShowMessageBox("Only one region found in time selection. Need at least two regions to merge.", "Info", 0)
      reaper.PreventUIRefresh(-1)
      reaper.Undo_EndBlock("Attempt to merge regions", -1)
      return
    end
    
    table.sort(regionsToMerge, function(a, b) return a.pos < b.pos end)
    
    local merged_color = regionsToMerge[1].color
    
    reaper.AddProjectMarker2(0, true, min_pos, max_end, merged_name, -1, merged_color)
    
    for i = #regionsToMerge, 1, -1 do
      reaper.DeleteProjectMarker(0, regionsToMerge[i].index, true)
    end
    
    reaper.UpdateTimeline()
    reaper.Undo_EndBlock("Merge regions within time selection", -1)
    reaper.PreventUIRefresh(-1)
    
    
  end
  
  MergeRegionsInTimeSelection()