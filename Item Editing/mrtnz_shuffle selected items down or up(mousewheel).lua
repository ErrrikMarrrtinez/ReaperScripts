-- @description Shuffle selected items down or up(mousewheel)
-- @author mrtnz
-- @version 1.0
-- @about
--   Vertical Shuffle selected items 
function Msg(param)
  reaper.ShowConsoleMsg(tostring(param).."\n")
end



function up()
local numSelectedItems = reaper.CountSelectedMediaItems(0)
if numSelectedItems == 0 then return end


local trackGroups = {}
for i = 0, numSelectedItems-1 do
    local item = reaper.GetSelectedMediaItem(0, i)
    local track = reaper.GetMediaItem_Track(item)

    if not trackGroups[track] then
        trackGroups[track] = {items = {}, track = track}
    end
    table.insert(trackGroups[track].items, item)
end

local trackArray = {}
for track, data in pairs(trackGroups) do
    table.insert(trackArray, data)
end


table.sort(trackArray, function(a, b)
    return reaper.GetMediaTrackInfo_Value(a.track, "IP_TRACKNUMBER") < reaper.GetMediaTrackInfo_Value(b.track, "IP_TRACKNUMBER")
end)


for i, data in ipairs(trackArray) do
    local targetTrackIndex = i - 1
    if targetTrackIndex < 1 then
        targetTrackIndex = #trackArray
    end
    local targetTrack = trackArray[targetTrackIndex].track
    for _, item in ipairs(data.items) do
        reaper.MoveMediaItemToTrack(item, targetTrack)
    end
end

reaper.UpdateArrange()
end

function down()
local numSelectedItems = reaper.CountSelectedMediaItems(0)
if numSelectedItems == 0 then return end


local trackGroups = {}
for i = 0, numSelectedItems-1 do
    local item = reaper.GetSelectedMediaItem(0, i)
    local track = reaper.GetMediaItem_Track(item)

    if not trackGroups[track] then
        trackGroups[track] = {items = {}, track = track}
    end
    table.insert(trackGroups[track].items, item)
end

local trackArray = {}
for track, data in pairs(trackGroups) do
    table.insert(trackArray, data)
end


table.sort(trackArray, function(a, b)
    return reaper.GetMediaTrackInfo_Value(a.track, "IP_TRACKNUMBER") < reaper.GetMediaTrackInfo_Value(b.track, "IP_TRACKNUMBER")
end)

for i, data in ipairs(trackArray) do
    local targetTrackIndex = i + 1
    if targetTrackIndex > #trackArray then
        targetTrackIndex = 1
    end
    local targetTrack = trackArray[targetTrackIndex].track
    for _, item in ipairs(data.items) do
        reaper.MoveMediaItemToTrack(item, targetTrack)
    end
end

reaper.UpdateArrange()
end

function run()
  is_new, name, sec, cmd, rel, res, val = reaper.get_action_context()
  

  
    if val > 0 then
      up()
    else
      down()
    end
  end




reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)
run() 
reaper.PreventUIRefresh(-1)
reaper.Undo_EndBlock(" !", -1)
reaper.UpdateArrange()

