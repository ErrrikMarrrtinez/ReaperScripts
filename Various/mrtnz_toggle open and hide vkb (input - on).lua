-- @description Toggle open and hide VKB (input - on-off)
-- @author mrtnz
-- @version 1.03
-- @about
--   If you want to use a virtual keyboard (VKB) 
--   but you don't want to see it, then you can 
--   use this script that automatically opens the 
--   virtual keyboard and hides it outside the window, 
--   as well as in a "smart" way turns on the midi message, 
--   and sets rest/month on the selected track if it has a Forex tool. 
--   I'm going to make a second version of the script that will allow, on the contrary, 
--   to run only at the moment when the track with the AC tool is selected and if 
--   it has a course enabled, then it will run. 
-- @changelog
--    Changed the VKB window coordinates to and added 
--    two local variables in case the user fails to hide 
--    the window. Use or change move_x or (and) move_y 
--    to try to correctly hide this window.


local move_x = -1200
local move_y = -1200
local enableTrackChanges = true --auto apply rec and mon for selected track



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

ensureCommandState(40637, true)
ensureCommandState(40377, true)

local _, _, section_id, command_id = reaper.get_action_context()

function ToolbarButton(enable)
  reaper.SetToggleCommandState(section_id, command_id, enable)
  reaper.RefreshToolbar2(section_id, command_id)
end

function setVKBPositionAndSize(newX, newY, windowWidth, windowHeight)
  local vkbTitles = {"Virtual MIDI keyboard", "Виртуальная MIDI-клавиатура"}
  for _, title in ipairs(vkbTitles) do
    local vkb = reaper.JS_Window_Find(title, true)
    if vkb then
      reaper.JS_Window_SetPosition(vkb, newX, newY, windowWidth, windowHeight)
      return
    end
  end
  ensureCommandState(40377, true)
end

prev_selected_tracks = {}
function setTrackMonitoringAndRecording(enable)
  if not enableTrackChanges then return end

  -- Получаем только количество выбранных треков, чтобы сократить область поиска
  local selectedTrackCount = reaper.CountSelectedTracks(0)
  local selected_tracks = {}

  for i = 0, selectedTrackCount - 1 do
    local track = reaper.GetSelectedTrack(0, i)
    local trackNumber = reaper.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER")
    selected_tracks[trackNumber] = true
    
    -- Обработка только изменившихся треков
    if not prev_selected_tracks[trackNumber] then
      local fx = reaper.TrackFX_GetInstrument(track)
      if fx >= 0 then
        reaper.SetMediaTrackInfo_Value(track, "I_RECARM", 1)
        reaper.SetMediaTrackInfo_Value(track, "I_RECMON", 1)
      end
    end
  end

  -- Снимаем режимы с треков, которые больше не выбраны
  for trackNum, _ in pairs(prev_selected_tracks) do
    if not selected_tracks[trackNum] then
      local track = reaper.GetTrack(0, trackNum - 1)
      if track then
        reaper.SetMediaTrackInfo_Value(track, "I_RECARM", 0)
        reaper.SetMediaTrackInfo_Value(track, "I_RECMON", 0)
      end
    end
  end

  prev_selected_tracks = selected_tracks
end


function Exit()
  setTrackMonitoringAndRecording(false)
  setVKBPositionAndSize(400, 400, 380, 210)
  ensureCommandState(40637, false)
  ensureCommandState(40377, false)
  ToolbarButton(0)
end

function updateVKBPositionAndSize()
  if reaper.GetToggleCommandStateEx(section_id, command_id) == 1 then
    setVKBPositionAndSize(move_y, move_x, 110, 28)
  end
end

function Main()
  setTrackMonitoringAndRecording(true)
  updateVKBPositionAndSize()
  reaper.defer(Main)
end

if reaper.GetToggleCommandStateEx(section_id, command_id) == 0 then
  reaper.atexit(Exit)
  ToolbarButton(1)
  Main()
  reaper.UpdateArrange()
else
  ToolbarButton(0)
  Exit()
end