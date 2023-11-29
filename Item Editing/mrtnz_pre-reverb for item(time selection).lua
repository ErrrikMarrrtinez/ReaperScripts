-- @description Pre-reverb, reverse reverb for item(time selection) 
-- @author mrtnz
-- @version 1.0
-- @about
--  ...

reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)

local last_fx_name = reaper.GetExtState("LastFXName", "FXName")
if last_fx_name == "" then last_fx_name = "FX name" end


local start_time, end_time = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
if start_time == end_time then
  reaper.ShowMessageBox("No time selection", "Error", 0)
  reaper.Undo_EndBlock("No time selection", -1)
  reaper.PreventUIRefresh(-1)
  return
end

local item = reaper.GetSelectedMediaItem(0, 0)
if not item then 
  reaper.Undo_EndBlock("No item selected", -1)
  reaper.PreventUIRefresh(-1)
  return 
end

local retval, fx = reaper.GetUserInputs("Enter FX Name", 1, "FX Name:", last_fx_name)
if not retval or fx == "" then
  reaper.Undo_EndBlock("Operation Cancelled", -1)
  reaper.PreventUIRefresh(-1)
  return
end

reaper.SetExtState("LastFXName", "FXName", fx, true)

local track = reaper.GetMediaItem_Track(item)
local track_idx = reaper.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER") - 1
local mode = reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH") < 1 and 1 or 2
local newTrack

if mode == 1 then
  reaper.InsertTrackAtIndex(track_idx, false)
  newTrack = reaper.GetTrack(0, track_idx)
elseif mode == 2 then
  while reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH") < 1 and track_idx > 0 do
    track_idx = track_idx - 1
    track = reaper.GetTrack(0, track_idx)
  end
  reaper.InsertTrackAtIndex(track_idx, false)
  newTrack = reaper.GetTrack(0, track_idx)
end

local item_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
local _, item_chunk = reaper.GetItemStateChunk(item, '')
local new_item = reaper.AddMediaItemToTrack(newTrack)
reaper.SetMediaItemInfo_Value(new_item, "D_POSITION", item_pos)
reaper.SetItemStateChunk(new_item, item_chunk)

reaper.SetMediaItemSelected(item, false)
reaper.SetMediaItemSelected(new_item, true)
reaper.TrackList_AdjustWindows(false)
reaper.UpdateArrange()

reaper.Main_OnCommand(40297, 0)  -- Unselect all tracks
reaper.SetMediaTrackInfo_Value(newTrack, "I_SELECTED", 1)  -- Select the new track only
reaper.Main_OnCommand(41051, 0)

local start_time, end_time = reaper.GetSet_LoopTimeRange2(0, false, false, 0, 0, false)
reaper.SetMediaItemPosition(new_item, start_time, false)
local take = reaper.GetActiveTake(new_item)

if not reaper.TakeFX_AddByName(take, fx, 1) then
  reaper.Undo_EndBlock("FX not found", -1)
  reaper.PreventUIRefresh(-1)
  return
end

reaper.Main_OnCommand(42009, 0) 
reaper.Main_OnCommand(41051, 0) 
local new_item = reaper.GetSelectedMediaItem(0, 0) 

if new_item then
  local take = reaper.GetActiveTake(new_item)
  if take then
    local name = ""
    retval, name = reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)
    local new_name = string.gsub(name, "-glued.*", "[reversed]")
    reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", new_name, true)
  end
end
reaper.Main_OnCommand(40635, 0) 
reaper.Undo_EndBlock("Pre-verb item", -1)
reaper.PreventUIRefresh(-1)
