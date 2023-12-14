-- @noindex

local value = 0.035
local inertia_count = 0
local inertia_direction = -value
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






function getCommandState(commandId)
  local _, _, sectionId = reaper.get_action_context()
  return reaper.GetToggleCommandStateEx(sectionId, commandId)
end

function ensureCommandState(commandId, activateIfOff)
  local currentState = getCommandState(commandId)
  if (currentState == 0 and activateIfOff) or (currentState == 1 and not activateIfOff) then
    reaper.Main_OnCommand(commandId, 0)
  end
end

ensureCommandState(42459, false)