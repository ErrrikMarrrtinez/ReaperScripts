-- @description Tempo detect item
-- @author mrtnz
-- @version 1.00
-- @about
--   Cut items and run script

reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)

local item = reaper.GetSelectedMediaItem(0, 0)
if not item then 
    reaper.ShowMessageBox("Please select an item.", "Error", 0)
    return 
end

function aha() 
    local function no_undo()
        reaper.defer(function() end)
    end

    local function GetPrevGrid(pos)
        reaper.Main_OnCommand(40755, 0)
        reaper.Main_OnCommand(40754, 0)
        local start_time, end_time = reaper.GetSet_ArrangeView2(0, false, false, false)
        reaper.GetSet_ArrangeView2(0, true, false, false, start_time, start_time + 0.1)
        if pos > 0 then
            local grid = pos
            local i = 0
            local posX = pos
            while grid >= pos do
                pos = pos - 0.0001
                if pos >= 0.0001 then
                    grid = reaper.SnapToGrid(0, pos)
                else
                    grid = 0
                end
                i = i + 1
                if i > 200000 then
                    reaper.Main_OnCommand(40756, 0)
                    reaper.GetSet_ArrangeView2(0, true, false, false, start_time, end_time)
                    return posX
                end
            end
            reaper.GetSet_ArrangeView2(0, true, false, false, start_time, end_time)
            reaper.Main_OnCommand(40756, 0)
            return grid
        end
        return 0
    end

    local countSelectedItems = reaper.CountSelectedMediaItems(0)
    if countSelectedItems == 0 then 
        no_undo()
        return 
    end

    for i = 1, countSelectedItems do
        local selectedItem = reaper.GetSelectedMediaItem(0, i - 1)
        local pos = reaper.GetMediaItemInfo_Value(selectedItem, 'D_POSITION')
        local prevGrid = GetPrevGrid(pos)
        reaper.SetMediaItemInfo_Value(selectedItem, 'D_POSITION', prevGrid)
    end

    reaper.PreventUIRefresh(-1)
    reaper.Undo_EndBlock('', -1)
    reaper.UpdateArrange()
end

local item_guid = reaper.BR_GetMediaItemGUID(item)
local original_track = reaper.GetMediaItemTrack(item)
local track_index = reaper.CountTracks(0) 
reaper.InsertTrackAtIndex(track_index, true)
local new_track = reaper.GetTrack(0, track_index) 
reaper.MoveMediaItemToTrack(item, new_track)

local item_length = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
reaper.GetSet_LoopTimeRange(true, false, 0, item_length, false)
reaper.Undo_BeginBlock2(nil)
reaper.Main_OnCommand(40338, 0)
local tempo = reaper.Master_GetTempo()
reaper.Undo_EndBlock2(nil, "Detect Tempo", -1)

item = reaper.BR_GetMediaItemByGUID(0, item_guid)
reaper.MoveMediaItemToTrack(item, original_track)
reaper.GetSet_LoopTimeRange(true, true, 0, 0, false)

for i = 0, reaper.CountTempoTimeSigMarkers(0) - 1 do 
    reaper.DeleteTempoTimeSigMarker(0, i) 
end

for i = 0, reaper.CountSelectedMediaItems(0) - 1 do 
    reaper.SetMediaItemSelected(reaper.GetSelectedMediaItem(0, i), false) 
end

reaper.SetEditCurPos(0, true, true)
reaper.Main_OnCommand(40617, 0)
reaper.PreventUIRefresh(-1)
reaper.DeleteTrack(new_track)
reaper.Undo_EndBlock("Tempo Detection", -1)

local rounded_tempo = math.ceil(tempo)
if rounded_tempo > 160 then 
    rounded_tempo = rounded_tempo / 2 
end

local user_input = reaper.ShowMessageBox(
      "Approximate tempo: "
      .. rounded_tempo 
      .. " BPM. Do you want to set this tempo for the project?",
      "Tempo Detection",
      1
      )
if user_input == 1 then 
    reaper.SetCurrentBPM(0, rounded_tempo, false) 
end


reaper.Undo_DoUndo2(nil)

reaper.Main_OnCommand(40617, 0)

reaper.Main_OnCommand(41173, 0)


function moveItems()
    function GetClosestBarStart(itemPosition)
      local prevBarStart = reaper.TimeMap_GetMeasureInfo(0, -1)
      local nextBarStart = prevBarStart
      local bar = 0
      
    
      repeat
        barStart = nextBarStart
        nextBarStart = reaper.TimeMap_GetMeasureInfo(0, bar)
        bar = bar + 1
      until nextBarStart > itemPosition
    
    
      if math.abs(itemPosition - barStart) < math.abs(nextBarStart - itemPosition) then
        return barStart
      else
        return nextBarStart
      end
    end
    
    local item = reaper.GetSelectedMediaItem(0, 0)
    
    if item then
      reaper.Undo_BeginBlock()
      reaper.PreventUIRefresh(1)
      
      local itemPosition = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
     
      local closestBarStart = GetClosestBarStart(itemPosition)
     
      reaper.SetMediaItemInfo_Value(item, "D_POSITION", closestBarStart)
      reaper.UpdateArrange()
      
      reaper.PreventUIRefresh(-1)
      reaper.Undo_EndBlock("Move item to closest bar start", -1)
    end
end

moveItems()