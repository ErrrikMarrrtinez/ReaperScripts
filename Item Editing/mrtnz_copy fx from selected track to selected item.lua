-- @description Copy fx from selected track to selected item
-- @author mrtnz
-- @version 1.00
-- @about
--   copy fx from selected track to selected item

-- Get selected item and track
local item = reaper.GetSelectedMediaItem(0, 0)
local track = reaper.GetSelectedTrack(0, 0)

-- Exit if no item or track is selected
if not item or not track then
  reaper.ShowConsoleMsg("No item or track selected.\n")
  return
end

-- Get FX chunk from track
local ret, trackChunk = reaper.GetTrackStateChunk(track, "", false)
local fxChunk = trackChunk:match("<FXCHAIN\n(.-\n)>\n>")
if not fxChunk then
  reaper.ShowConsoleMsg("No FX on track.\n")
  return
end

-- Get item chunk
local ret, itemChunk = reaper.GetItemStateChunk(item, "", false)

-- Check if TAKEFX exists, if not insert
if not itemChunk:find("<TAKEFX") then
  local sourceEnd = itemChunk:find(">\n", itemChunk:find("<SOURCE"))
  if sourceEnd then
    local newItemChunk = itemChunk:sub(1, sourceEnd) .. "\n<TAKEFX\n" .. fxChunk .. ">\n" .. itemChunk:sub(sourceEnd + 1)
    reaper.SetItemStateChunk(item, newItemChunk, false)
  else
    reaper.ShowConsoleMsg("Could not find a suitable position to insert FX.\n")
  end
else
  reaper.ShowConsoleMsg("FX already exists on item.\n")
end
