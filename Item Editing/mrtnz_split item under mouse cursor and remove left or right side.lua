-- @description Split and cut item under mouse cursor and remove left or right side.lua
-- @author mrtnz
-- @version 1.0
-- @about
--   The script allows splitting the item under the cursor, removing the smaller part, while preserving the larger one.

local window, segment, details = reaper.BR_GetMouseCursorContext()
local item = reaper.BR_GetMouseCursorContext_Item()
reaper.Undo_BeginBlock(0)
if item then
  local cursor_pos = reaper.BR_GetMouseCursorContext_Position()
  local _, grid_division = reaper.GetSetProjectGrid(0, false)
  local split_pos = reaper.SnapToGrid(0, cursor_pos)
  local item_start, item_end = reaper.GetMediaItemInfo_Value(item, "D_POSITION"), reaper.GetMediaItemInfo_Value(item, "D_LENGTH") + reaper.GetMediaItemInfo_Value(item, "D_POSITION")
  local new_item = reaper.SplitMediaItem(item, split_pos)
  if new_item then
    local left_item_length = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
    local right_item_length = reaper.GetMediaItemInfo_Value(new_item, "D_LENGTH")
    if math.abs(left_item_length - right_item_length) > 0.0001 then
      if math.abs(split_pos - item_start) < math.abs(split_pos - item_end) then
        reaper.DeleteTrackMediaItem(reaper.GetMediaItem_Track(item), item)
      else
        reaper.DeleteTrackMediaItem(reaper.GetMediaItem_Track(new_item), new_item)
      end
    end
    reaper.UpdateArrange()
  end
end
reaper.Undo_BeginBlock(1)
