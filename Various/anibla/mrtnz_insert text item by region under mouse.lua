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

-- Улучшенная функция для поиска текстового айтема в конкретном регионе
local function findTextItemInRegion(track, region_name, region_start, region_end)
    local item_count = reaper.GetTrackNumMediaItems(track)
    for i = 0, item_count-1 do
        local item = reaper.GetTrackMediaItem(track, i)
        local take = reaper.GetActiveTake(item)
        if take then
            local _, take_name = reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)
            
            -- Проверяем не только имя, но и положение айтема относительно региона
            local item_start = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
            local item_end = item_start + reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
            
            -- Проверка перекрытия айтема и региона
            local overlap = (item_start < region_end) and (item_end > region_start)
            
            if take_name == region_name and overlap then
                return item
            end
        end
    end
    return nil
end

-- Пытаемся найти существующий айтем в текущем регионе
local existing_item = nil
local current_track_idx = reaper.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER") - 1
existing_item = findTextItemInRegion(track, region_name, rgnpos, rgnend)

-- Если не нашли в текущем треке, ищем в треках выше
local track_idx = current_track_idx - 1
while not existing_item and track_idx >= 0 do
    local track_above = reaper.GetTrack(0, track_idx)
    if track_above then
        existing_item = findTextItemInRegion(track_above, region_name, rgnpos, rgnend)
        track_idx = track_idx - 1
    else break end
end

-- Если все еще не нашли, ищем в треках ниже
track_idx = current_track_idx + 1
while not existing_item do
    local track_below = reaper.GetTrack(0, track_idx)
    if track_below then
        existing_item = findTextItemInRegion(track_below, region_name, rgnpos, rgnend)
        track_idx = track_idx + 1
    else break end
end

-- Проверяем, есть ли текстовый айтем с таким же именем в ТЕКУЩЕМ регионе
local function findTextItemInCurrentRegionOnly(region_name, region_start, region_end)
    local track_count = reaper.CountTracks(0)
    for t = 0, track_count-1 do
        local current_track = reaper.GetTrack(0, t)
        local item_count = reaper.GetTrackNumMediaItems(current_track)
        
        for i = 0, item_count-1 do
            local item = reaper.GetTrackMediaItem(current_track, i)
            local take = reaper.GetActiveTake(item)
            if take then
                local _, take_name = reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)
                
                -- Проверяем положение
                local item_start = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
                local item_end = item_start + reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
                
                -- Проверяем перекрытие именно с текущим регионом
                local overlap = (item_start < region_end) and (item_end > region_start)
                
                if take_name == region_name and overlap then
                    return item
                end
            end
        end
    end
    return nil
end

-- Ищем айтем только в текущем регионе
local item_in_current_region = findTextItemInCurrentRegionOnly(region_name, rgnpos, rgnend)

local final_item
if item_in_current_region then
    -- Если нашли айтем в текущем регионе, перемещаем его на выбранный трек
    reaper.MoveMediaItemToTrack(item_in_current_region, track)
    reaper.SetMediaItemPosition(item_in_current_region, rgnpos, false)
    reaper.SetMediaItemLength(item_in_current_region, rgnend - rgnpos, false)
    final_item = item_in_current_region
elseif existing_item then
    -- Если нашли где-то еще, но не в текущем регионе, создаем новый
    final_item = reaper.AddMediaItemToTrack(track)
    reaper.SetMediaItemPosition(final_item, rgnpos, false)
    reaper.SetMediaItemLength(final_item, rgnend - rgnpos, false)
    local take = reaper.AddTakeToMediaItem(final_item)
    reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", region_name, true)
else
    -- Если нигде не нашли, создаем новый
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