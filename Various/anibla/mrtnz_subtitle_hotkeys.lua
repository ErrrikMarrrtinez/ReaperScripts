--@noindex
--NoIndex: true

local r = reaper
local script_path = debug.getinfo(1, "S").source:match("@(.*[\\/])")
package.path = script_path..'?.lua'

local SyncManager = require('mrtnz_subtitle_sync')

function JumpToNextSubtitle()
  local playPos = r.GetPlayPosition()
  local regions = SyncManager.getSubtitleRegions()
  
  table.sort(regions, function(a, b) return a.start < b.start end)
  
  for _, region in ipairs(regions) do
    if region.start > playPos then
      r.SetEditCurPos(region.start, true, true)
      return
    end
  end
end

function JumpToPrevSubtitle()
  local playPos = r.GetPlayPosition()
  local regions = SyncManager.getSubtitleRegions()
  
  table.sort(regions, function(a, b) return a.start > b.start end)
  
  for _, region in ipairs(regions) do
    if region._end < playPos then
      r.SetEditCurPos(region.start, true, true)
      return
    end
  end
end

function SetSubtitleStart()
  local cursorPos = r.GetCursorPosition()
  local regions = SyncManager.getSubtitleRegions()
  
  for _, region in ipairs(regions) do
    if cursorPos >= region.start and cursorPos <= region._end then
      r.SetProjectMarker4(0, region.index, true, cursorPos, region._end, 
        region.text, region.index, 0)
      r.UpdateArrange()
      return
    end
  end
end

function SetSubtitleEnd()
  local cursorPos = r.GetCursorPosition()
  local regions = SyncManager.getSubtitleRegions()
  
  for _, region in ipairs(regions) do
    if cursorPos >= region.start and cursorPos <= region._end then
      r.SetProjectMarker4(0, region.index, true, region.start, cursorPos, 
        region.text, region.index, 0)
      r.UpdateArrange()
      return
    end
  end
end

function ExtendSubtitleToNext()
  local regions = SyncManager.getSubtitleRegions()
  table.sort(regions, function(a, b) return a.start < b.start end)
  
  local cursorPos = r.GetCursorPosition()
  
  for i, region in ipairs(regions) do
    if cursorPos >= region.start and cursorPos <= region._end then
      if i < #regions then
        local nextStart = regions[i + 1].start
        r.SetProjectMarker4(0, region.index, true, region.start, nextStart - 0.05, 
          region.text, region.index, 0)
        r.UpdateArrange()
      end
      return
    end
  end
end

local action = ({...})[1]
if action == "next" then
  JumpToNextSubtitle()
elseif action == "prev" then
  JumpToPrevSubtitle()
elseif action == "setstart" then
  SetSubtitleStart()
elseif action == "setend" then
  SetSubtitleEnd()
elseif action == "extend" then
  ExtendSubtitleToNext()
end