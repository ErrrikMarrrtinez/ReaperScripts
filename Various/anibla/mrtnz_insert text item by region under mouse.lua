--@noindex
--NoIndex: true



local position = reaper.BR_PositionAtMouseCursor(true)
if position == -1 then position = reaper.GetCursorPosition() end

local track = reaper.GetTrackFromPoint(reaper.GetMousePosition())
if not track then return reaper.defer(function() end) end

local _, regionidx = reaper.GetLastMarkerAndCurRegion(0, position)
if regionidx == -1 then return reaper.defer(function() end) end

reaper.Undo_BeginBlock()
local _, _, rgnpos, rgnend, region_name = reaper.EnumProjectMarkers(regionidx)
reaper.PreventUIRefresh(1)

local function findTextItemInRegion(track)
    local item_count = reaper.GetTrackNumMediaItems(track)
    for i = 0, item_count-1 do
        local item = reaper.GetTrackMediaItem(track, i)
        local take = reaper.GetActiveTake(item)
        if take then
            local _, take_name = reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)
            if take_name == region_name then return item end
        end
    end
    return nil
end

local existing_item = nil
local current_track_idx = reaper.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER") - 1
existing_item = findTextItemInRegion(track)

local track_idx = current_track_idx - 1
while not existing_item and track_idx >= 0 do
    local track_above = reaper.GetTrack(0, track_idx)
    if track_above then
        existing_item = findTextItemInRegion(track_above)
        track_idx = track_idx - 1
    else break end
end

track_idx = current_track_idx + 1
while not existing_item do
    local track_below = reaper.GetTrack(0, track_idx)
    if track_below then
        existing_item = findTextItemInRegion(track_below)
        track_idx = track_idx + 1
    else break end
end

local final_item
if existing_item then
    reaper.MoveMediaItemToTrack(existing_item, track)
    reaper.SetMediaItemPosition(existing_item, rgnpos, false)
    reaper.SetMediaItemLength(existing_item, rgnend - rgnpos, false)
    final_item = existing_item
else
    final_item = reaper.AddMediaItemToTrack(track)
    reaper.SetMediaItemPosition(final_item, rgnpos, false)
    reaper.SetMediaItemLength(final_item, rgnend - rgnpos, false)
    local take = reaper.AddTakeToMediaItem(final_item)
    reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", region_name, true)
end

if final_item then
    reaper.GetSetMediaItemInfo_String(final_item, "P_NOTES", region_name, true)
    reaper.SetMediaItemInfo_Value(final_item, "I_NOTESL", 213)
    reaper.SetMediaItemInfo_Value(final_item, "I_NOTEST", 266)
    reaper.SetMediaItemInfo_Value(final_item, "I_NOTESR", 712)
    reaper.SetMediaItemInfo_Value(final_item, "I_NOTESB", 663)
    reaper.SetMediaItemInfo_Value(final_item, "C_NOTESCOLOR", 0)
end

reaper.PreventUIRefresh(-1)
reaper.UpdateArrange()
reaper.Undo_EndBlock("Move/Insert text item with region name and notes", -1)