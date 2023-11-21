-- @description Move item to closet bar start
-- @author mrtnz
-- @version 1.00
-- @about
--   Move item to closet bar start


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