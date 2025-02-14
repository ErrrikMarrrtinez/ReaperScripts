--@noindex
--NoIndex: true

local position = reaper.BR_PositionAtMouseCursor(true)
if position == -1 then position = reaper.GetCursorPosition() end

local track = reaper.GetTrackFromPoint(reaper.GetMousePosition())
if not track then return reaper.defer(function() end) end

local _, regionidx = reaper.GetLastMarkerAndCurRegion(0, position)
if regionidx == -1 then return reaper.defer(function() end) end

local _, _, rgnpos, rgnend, region_name = reaper.EnumProjectMarkers(regionidx)
if position < rgnpos or position > rgnend then return reaper.defer(function() end) end
if not region_name then region_name = "" end

reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)

local function findAndDeleteTextItemAtCursor(track)
    local item_count = reaper.GetTrackNumMediaItems(track)
    for i = item_count-1, 0, -1 do
        local item = reaper.GetTrackMediaItem(track, i)
        local item_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
        local item_len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
        local item_end = item_pos + item_len
        
        if position >= item_pos and position <= item_end then
            local _, item_notes = reaper.GetSetMediaItemInfo_String(item, "P_NOTES", "", false)
            if item_notes == region_name then
                local take = reaper.GetActiveTake(item)
                if take then
                    local is_midi = reaper.TakeIsMIDI(take)
                    if not is_midi then
                        reaper.DeleteTrackMediaItem(track, item)
                        return true
                    end
                end
            end
        end
    end
    return false
end

findAndDeleteTextItemAtCursor(track)

local final_item = reaper.AddMediaItemToTrack(track)
reaper.SetMediaItemPosition(final_item, rgnpos, false)
reaper.SetMediaItemLength(final_item, rgnend - rgnpos, false)
local take = reaper.AddTakeToMediaItem(final_item)
reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", region_name, true)

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
