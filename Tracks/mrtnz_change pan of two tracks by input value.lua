-- @noindex

function clampPanValue(pan_val)
    return math.max(-1, math.min(1, pan_val))
  end
  
  function setPan(valueChange)
    local track_1 = reaper.GetSelectedTrack(0, 0)
    local track_2 = reaper.GetSelectedTrack(0, 1)
    if track_1 and track_2 then
      reaper.SetMediaTrackInfo_Value(track_1, "D_PAN", clampPanValue(valueChange))
      reaper.SetMediaTrackInfo_Value(track_2, "D_PAN", clampPanValue(-valueChange))
    else
      reaper.ShowMessageBox("Please select two tracks.", "Error", 0)
    end
  end
  
  function run()
    local retval, retvals_csv = reaper.GetUserInputs("Enter pan value", 1, "Pan Value:", "")
    if retval then
      local value = tonumber(retvals_csv) / 100
      if value and reaper.CountSelectedTracks(0) >= 2 then
        setPan(value)
      end
    end
  end
  
  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)
  run()
  reaper.PreventUIRefresh(-1)
  reaper.Undo_EndBlock("Pan changed!", -1)
  reaper.UpdateArrange()
  