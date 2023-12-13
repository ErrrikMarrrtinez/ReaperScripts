-- @description Change pan for paired selected tracks (mousewheel ctx)
-- @author mrtnz
-- @version 1.1
-- @about
--  ...

local value = 0.2 --step

function clampPanValue(pan_val)
  return math.max(-1, math.min(1, pan_val))
end

function changePan(valueChange)
  local track_1 = reaper.GetSelectedTrack(0, 0)
  local track_2 = reaper.GetSelectedTrack(0, 1)
  if track_1 and track_2 then
    local pan_val_1 = reaper.GetMediaTrackInfo_Value(track_1, "D_PAN")
    local pan_val_2 = reaper.GetMediaTrackInfo_Value(track_2, "D_PAN")
    reaper.SetMediaTrackInfo_Value(track_1, "D_PAN", clampPanValue(pan_val_1 + valueChange))
    reaper.SetMediaTrackInfo_Value(track_2, "D_PAN", clampPanValue(pan_val_2 - valueChange))
  else
    reaper.ShowMessageBox("Please select two tracks.", "Error", 0)
  end
end

function run()
  is_new, name, sec, cmd, rel, res, val = reaper.get_action_context()
  if reaper.CountSelectedTracks(0) >= 2 then
    changePan(val > 0 and value or -value)
  end
end

reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)
run()
reaper.PreventUIRefresh(-1)
reaper.Undo_EndBlock("Pan changed!", -1)
reaper.UpdateArrange()
