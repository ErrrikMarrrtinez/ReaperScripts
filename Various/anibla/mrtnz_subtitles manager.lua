

local r = reaper
local script_path = debug.getinfo(1, "S").source:match("@(.*[\\/])")
local imgui_path = reaper.ImGui_GetBuiltinPath() .. '/?.lua'
package.path = imgui_path .. ";" .. script_path .. '?.lua'

local f = require('mrtnz_utils')
local srtass = require('mrtnz_srtass-parser')
local ImGui = require 'imgui' '0.9.2.3'

--[[
f.importSubtitlesAsRegions        = importSubtitlesAsRegions
f.exportRegionsAsSRTDialog        = exportRegionsAsSRTDialog
f.convertASStoSRT                 = convertASStoSRT
f.importSubtitlesAsRegionsDialog  = importSubtitlesAsRegionsDialog
]]

--srtass.importSubtitlesAsRegionsDialog()
local function checkDependencies()
  if not reaper.ReaPack_BrowsePackages then
    local msg = "Для работы скрипта требуется ReaPack.\n" ..
                "Skript ishlashi uchun ReaPack kerak.\n\n" ..
                "Хотите перейти на страницу загрузки?\n" ..
                "Yuklab olish sahifasiga o'tishni xohlaysizmi?"
    
    local ret = reaper.ShowMessageBox(msg, "ReaPack не установлен / ReaPack o'rnatilmagan", 4)
    
    if ret == 6 then -- Yes
      reaper.CF_ShellExecute("https://reapack.com/upload/reascript")
    end
    return false
  end
  
  if not reaper.APIExists("ImGui_GetBuiltinPath") then
    local msg = "Для работы скрипта требуется ReaImGui.\n" ..
                "Skript ishlashi uchun ReaImGui kerak.\n\n" ..
                "Хотите установить его через ReaPack?\n" ..
                "Uni ReaPack orqali o'rnatishni xohlaysizmi?"
                
    local ret = reaper.ShowMessageBox(
      msg,
      "Требуется ReaImGui / ReaImGui kerak",
      4 -- Yes/No
    )
    
    if ret == 6 then 
      reaper.ReaPack_BrowsePackages("ReaImGui: ReaScript binding for Dear ImGui")
      return false
    else
      return false
    end
  end
  
  return true 
end

if not checkDependencies() then
  return
end


local ctx = ImGui.CreateContext('Subtitles Window')
local COLOR_ACTIVE   = 0xFFFFFFFF
local COLOR_NEIGHBOR = 0x4a4a4aFF
local COLOR_INACTIVE = 0x1a1a1aFF
local fontSize = 25
local savedFontSize = reaper.GetExtState("SubtitlesWindow", "fontSize")
if savedFontSize and savedFontSize ~= "" then fontSize = tonumber(savedFontSize) or fontSize end
local font = ImGui.CreateFont("sans-serif", fontSize, 0)
ImGui.Attach(ctx, font)
local reloadFont = false
local cachedRegions = {}
local cachedRegionsTime = 0
local CACHE_INTERVAL = 0.25
local regionColors = {}


f.AddScriptStartup()

local function get_regions()
  local regions = {}
  local count = reaper.CountProjectMarkers(0)
  for i = 0, count - 1 do
    local retval, isrgn, pos, rgnend, name = reaper.EnumProjectMarkers3(0, i)
    if isrgn then 
      regions[#regions+1] = {start = pos, endPos = rgnend, name = name} 
    end
  end
  return regions
end

local function get_cached_regions()
  local now = reaper.time_precise()
  if now - cachedRegionsTime > CACHE_INTERVAL then
    cachedRegions = get_regions()
    cachedRegionsTime = now
  end
  return cachedRegions
end



local function lerp(a, b, t) 
  return a + (b - a) * t 
end

local function getColorComponents(color)
  local a = math.floor(color / 0x1000000) % 256
  local b = math.floor(color / 0x10000) % 256
  local g = math.floor(color / 0x100) % 256
  local r = color % 256
  return a, b, g, r
end

local function combineColor(a, b, g, r)
  return ((a * 0x1000000) + (b * 0x10000) + (g * 0x100) + r)
end

local function lerpColor(c1, c2, t)
  local a1, b1, g1, r1 = getColorComponents(c1)
  local a2, b2, g2, r2 = getColorComponents(c2)
  local a = math.floor(lerp(a1, a2, t) + 0.5)
  local b = math.floor(lerp(b1, b2, t) + 0.5)
  local g = math.floor(lerp(g1, g2, t) + 0.5)
  local r = math.floor(lerp(r1, r2, t) + 0.5)
  return combineColor(a, b, g, r)
end

local scrollY = 0

font2 = ImGui.CreateFont("sans-serif", 15, 0)
ImGui.Attach(ctx, font2)

-- Кэш для высот текста

local function getBrightness(color)
  local a, b, g, r = getColorComponents(color)
  return (r + g + b) / 3
end


local textHeightsCache = {}


local function calculateWrappedTextHeight(ctx, text, wrap_width)
  wrap_width = wrap_width or ImGui.GetContentRegionAvail(ctx)
  local lines = {}
  local currentLine = ""
  
  -- Get exact line height for the current font
  local lineHeight = select(2, ImGui.CalcTextSize(ctx, "Ag"))  -- Using "Ag" to get max height
  local extraSpacing = lineHeight * 0.3  -- Dynamic spacing based on line height
  
  -- Split text into words and respect newlines
  for word in string.gmatch(text.."\n", "([^\n]*)\n") do
    local subLines = {}
    local currentSubLine = ""
    
    -- Process each line separately
    for subWord in string.gmatch(word, "%S+") do
      local candidate = (currentSubLine == "" and subWord or currentSubLine .. " " .. subWord)
      local textWidth = select(1, ImGui.CalcTextSize(ctx, candidate))
      
      if textWidth > wrap_width and currentSubLine ~= "" then
        table.insert(subLines, currentSubLine)
        currentSubLine = subWord
      else
        currentSubLine = candidate
      end
    end
    
    if currentSubLine ~= "" then
      table.insert(subLines, currentSubLine)
    end
    
    for _, line in ipairs(subLines) do
      table.insert(lines, line)
    end
  end
  
  return #lines * lineHeight + (#lines - 1) * extraSpacing, lines, lineHeight, extraSpacing
end

-- Improved text drawing function with proper vertical spacing
local function draw_centered_wrapped_text(ctx, text, wrap_width)
  wrap_width = wrap_width or ImGui.GetContentRegionAvail(ctx)
  local totalHeight, lines, lineHeight, extraSpacing = calculateWrappedTextHeight(ctx, text, wrap_width)
  
  -- Store initial cursor position
  local startX = ImGui.GetCursorPosX(ctx)
  local startY = ImGui.GetCursorPosY(ctx)
  
  -- Draw each line with proper spacing
  for i, line in ipairs(lines) do
    local textWidth = select(1, ImGui.CalcTextSize(ctx, line))
    local offset = (wrap_width - textWidth) * 0.5
    
    -- Ensure minimum left margin
    offset = math.max(offset, 0)
    
    -- Set position for this line
    ImGui.SetCursorPos(ctx, startX + offset, startY + (i-1) * (lineHeight + extraSpacing))
    ImGui.Text(ctx, line)
  end
  
  -- Return total height used
  return totalHeight
end



local lastAvailW = nil
local function main_loop()
  if reloadFont then
    if font then ImGui.Detach(ctx, font) end
    font = ImGui.CreateFont("sans-serif", fontSize, 0)
    ImGui.Attach(ctx, font)
    reloadFont = false
    reaper.SetExtState("SubtitlesWindow", "fontSize", tostring(fontSize), true)
    textHeightsCache = {}
  end
  ImGui.SetNextWindowSize(ctx, 640, 640, ImGui.Cond_FirstUseEver)
  local visible, open = ImGui.Begin(ctx, "Subtitles", true)
  if visible then
    ImGui.PushFont(ctx, font2)
    local avail_w, avail_h = ImGui.GetContentRegionAvail(ctx)
    if lastAvailW ~= avail_w then
      textHeightsCache = {}
      lastAvailW = avail_w
    end
    if ImGui.BeginChild(ctx, "ScrollingChild", avail_w, avail_h, 1, ImGui.WindowFlags_NoScrollWithMouse | ImGui.WindowFlags_NoScrollbar) then
      if ImGui.BeginPopupContextWindow(ctx, "context_menu") then
        if ImGui.MenuItem(ctx, "Import subtitles (.srt or .ass)") then
          reaper.Main_OnCommand(reaper.NamedCommandLookup("_SWSMARKERLIST10"), 0)
          srtass.importSubtitlesAsRegionsDialog()
        end
        if ImGui.MenuItem(ctx, "Export subtitles (.srt file)") then
          srtass.exportRegionsAsSRTDialog()
        end
        ImGui.EndPopup(ctx)
      end
      ImGui.Dummy(ctx, 0, avail_h * 0.25)
      ImGui.PopFont(ctx)
      ImGui.PushFont(ctx, font)
      local regions = get_cached_regions()
      local play_state = reaper.GetPlayState()
      local cursor_pos = ((play_state & 1) == 1) and reaper.GetPlayPosition() or reaper.GetCursorPosition()
      local activeIndex = nil
      for i, region in ipairs(regions) do
        if cursor_pos >= region.start and cursor_pos <= region.endPos then
          activeIndex = i
          break
        end
      end
      local brightenFactor = 0.89
      local darkenFactor = 0.1
      for i, region in ipairs(regions) do
        local target = COLOR_INACTIVE
        if activeIndex then
          if i == activeIndex then
            target = COLOR_ACTIVE
          elseif i == activeIndex - 1 or i == activeIndex + 1 then
            target = COLOR_NEIGHBOR
          end
        end
        if not regionColors[i] then
          regionColors[i] = target
        else
          local currentBrightness = getBrightness(regionColors[i])
          local targetBrightness = getBrightness(target)
          local factor = darkenFactor
          if targetBrightness > currentBrightness then
            factor = brightenFactor * brightenFactor * brightenFactor
          end
          regionColors[i] = lerpColor(regionColors[i], target, factor)
        end
      end
      local totalHeight = 0
      for i, region in ipairs(regions) do
        if not textHeightsCache[region.name] then
          textHeightsCache[region.name] = calculateWrappedTextHeight(ctx, region.name, avail_w - 8)
        end
        totalHeight = totalHeight + textHeightsCache[region.name] + 5
      end
      local verticalOffset = 0
      if totalHeight < avail_h then verticalOffset = (avail_h - totalHeight) * 0.5 end
      local currentY = verticalOffset
      local regionCenters = {}
      for i, region in ipairs(regions) do
        ImGui.PushStyleColor(ctx, ImGui.Col_Text, regionColors[i] or COLOR_INACTIVE)
        local textHeight = textHeightsCache[region.name]
        ImGui.SetCursorPosY(ctx, currentY)
        draw_centered_wrapped_text(ctx, region.name, avail_w - 8)
        ImGui.PopStyleColor(ctx)
        regionCenters[i] = currentY + textHeight * 0.5
        currentY = currentY + textHeight + 5
      end
      local desiredCenter = nil
      if activeIndex then
        desiredCenter = regionCenters[activeIndex]
      elseif #regions > 0 then
        if cursor_pos <= regions[1].start then
          desiredCenter = regionCenters[1]
        elseif cursor_pos >= regions[#regions].endPos then
          desiredCenter = regionCenters[#regions]
        else
          for i = 1, #regions - 1 do
            if cursor_pos > regions[i].endPos and cursor_pos < regions[i+1].start then
              local t = (cursor_pos - regions[i].endPos) / (regions[i+1].start - regions[i].endPos)
              desiredCenter = regionCenters[i] * (1 - t) + regionCenters[i+1] * t
              break
            end
          end
        end
      end
      if desiredCenter then
        local desiredScroll = desiredCenter - avail_h * 0.5
        scrollY = scrollY + (desiredScroll - scrollY) * 0.2
        ImGui.SetScrollY(ctx, scrollY)
      end
      ImGui.Dummy(ctx, 0, avail_h * 0.25)
      ImGui.EndChild(ctx)
    end
    ImGui.PopFont(ctx)
    ImGui.End(ctx)
  end
  if ImGui.IsKeyDown(ctx, ImGui.Key_LeftCtrl) then
    local wheel = ImGui.GetMouseWheel(ctx)
    if wheel ~= 0 then
      local newSize = math.max(8, fontSize + wheel * 2)
      if newSize ~= fontSize then
        fontSize = newSize
        reloadFont = true
      end
    end
  end
  if ImGui.IsMouseClicked(ctx, 0) then
    cachedRegions = get_regions()
    cachedRegionsTime = reaper.time_precise()
  end
  if open then reaper.defer(main_loop) end
end


reaper.atexit()
reaper.defer(main_loop)
