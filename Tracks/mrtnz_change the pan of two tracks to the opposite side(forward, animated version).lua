-- @description Change the pan of two tracks to the opposite side(animated).
-- @author mrtnz
-- @version 1.0
-- @provides
--   [main=main] mrtnz_change the pan of two tracks to the opposite side(backward, animated version).lua
-- @about
--      If you want something new, you can change synchronously the pan parameter
--      of the two selected tracks with a tricky animation that reaper does not have.
--      Visually beautiful? - Yes. Practical? - Not really, but it works :D


local value = 0.039
local inertia_count = 0
local inertia_direction = value
local val_1 = 25

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
  if reaper.CountSelectedTracks(0) >= 2 then
    changePan(inertia_direction)
    inertia_count = val_1
    reaper.defer(inertiaPan)
  end
end

function inertiaPan()
  if inertia_count > 0 then
    changePan(inertia_direction * (inertia_count / val_1))
    inertia_count = inertia_count - 1
    reaper.defer(inertiaPan)
  else
    reaper.defer(function() end)
  end
end

reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)
run()
reaper.PreventUIRefresh(-1)
reaper.Undo_EndBlock("Pan changed!", -1)
reaper.UpdateArrange()
