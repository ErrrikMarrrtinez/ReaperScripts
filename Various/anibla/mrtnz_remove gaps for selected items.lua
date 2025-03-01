--@noindex
--NoIndex: true


local f = dofile(debug.getinfo(1, "S").source:match([[^@?(.*[\/])[^\/]-$]]) .. 'mrtnz_utils.lua')

local RemoveGapsBetweenItems = f.RemoveGaps

function Main()
  reaper.Undo_BeginBlock()
  
  local itemCount = reaper.CountSelectedMediaItems(0)
  local selectedItems = {}
  
  for i = 0, itemCount - 1 do
    local item = reaper.GetSelectedMediaItem(0, i)
    table.insert(selectedItems, item)
  end
  
  local success = RemoveGapsBetweenItems(selectedItems)
  
  if success then
    reaper.UpdateArrange()
    reaper.Undo_EndBlock("Remove Gaps Between Items", -1)
    reaper.ShowConsoleMsg("Промежутки между " .. itemCount .. " выделенными айтемами были удалены!\n")
  else
    reaper.Undo_EndBlock("", -1)
  end
end

Main()