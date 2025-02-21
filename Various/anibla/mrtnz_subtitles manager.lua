--@noindex
--NoIndex: true

local r = reaper;r.defer(function()end)
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
]]                               -- srtass.importSubtitlesAsRegionsDialog()

if not f.checkDependencies() then
  return
end

local ctx = ImGui.CreateContext('Subtitles Window')
local COLOR_ACTIVE   = 0xFFFFFFFF
local COLOR_NEIGHBOR = 0x5a5a5aFF
local COLOR_INACTIVE = 0x3a3a3aFF
local fontSize = 25
local savedFontSize = r.GetExtState("SubtitlesWindow", "fontSize")
if savedFontSize and savedFontSize ~= "" then fontSize = tonumber(savedFontSize) or fontSize end

local reloadFont = false
local cachedRegions = {}
local cachedRegionsTime = 0
local CACHE_INTERVAL = 0.25
local regionColors = {}
local scrollY = 0

local showProgressBar = true
local savedProgressBarState = r.GetExtState("SubtitlesWindow", "showProgressBar")
if savedProgressBarState and savedProgressBarState ~= "" then 
    showProgressBar = savedProgressBarState == "true"
end

local font = ImGui.CreateFont("sans-serif", fontSize, 0)
local font2 = ImGui.CreateFont("sans-serif", 15, 0)
ImGui.Attach(ctx, font2)
ImGui.Attach(ctx, font)
local textHeightsCache = {}

f.AddScriptStartup()

function calculateWrappedTextHeight(ctx, text, wrap_width)
  wrap_width = wrap_width or ImGui.GetContentRegionAvail(ctx)
  local lines = {}
  local currentLine = ""
  local lineHeight = select(2, ImGui.CalcTextSize(ctx, "Ag"))
  local extraSpacing = lineHeight * 0.3
  for word in string.gmatch(text.."\n", "([^\n]*)\n") do
    local subLines = {}
    local currentSubLine = ""
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

local function draw_centered_wrapped_text(ctx, text, wrap_width)
  wrap_width = wrap_width or ImGui.GetContentRegionAvail(ctx)
  local totalHeight, lines, lineHeight, extraSpacing = calculateWrappedTextHeight(ctx, text, wrap_width)
  local startX = ImGui.GetCursorPosX(ctx)
  local startY = ImGui.GetCursorPosY(ctx)
  for i, line in ipairs(lines) do
    local textWidth = select(1, ImGui.CalcTextSize(ctx, line))
    local offset = (wrap_width - textWidth) * 0.5
    offset = math.max(offset, 0)
    ImGui.SetCursorPos(ctx, startX + offset, startY + (i-1) * (lineHeight + extraSpacing))
    ImGui.Text(ctx, line)
  end
  return totalHeight
end

function get_cached_regions()
  local now = r.time_precise()
  if now - cachedRegionsTime > CACHE_INTERVAL then
    cachedRegions = f.get_regions()
    cachedRegionsTime = now
  end
  return cachedRegions
end

function draw_progress_subtitle(activeIndex, regions, cursor_pos)
    if activeIndex then
        local activeRegion = regions[activeIndex]
        local regionLength = activeRegion.endPos - activeRegion.start
        local progress = (cursor_pos - activeRegion.start) / regionLength
        progress = math.min(math.max(progress, 0), 1)
        
        local draw_list = reaper.ImGui_GetForegroundDrawList(ctx)
        local win_pos_x, win_pos_y = ImGui.GetWindowPos(ctx)
        local win_size_x, win_size_y = ImGui.GetWindowSize(ctx)
        
        local margin = 10
        local bar_height = 15
        local bar_x1 = win_pos_x + margin
        local bar_y1 = win_pos_y + win_size_y - margin - bar_height
        local bar_x2 = win_pos_x + win_size_x - margin
        local bar_y2 = win_pos_y + win_size_y - margin
        
        local bar_color = 0xFF8B0000    -- базовый багровый цвет
        local progress_color = 0xcd583320  -- цвет заполненной части
        local border_color = 0xFFFFFF40 -- белая рамка
 -- белая рамка
        
        -- Рисуем основной фон
        ImGui.DrawList_AddRectFilled(draw_list, bar_x1, bar_y1, bar_x2, bar_y2, bar_color, 0, 0)
        
        -- Рисуем прогресс
        local progress_x = bar_x1 + (bar_x2 - bar_x1) * progress
        ImGui.DrawList_AddRectFilled(draw_list, bar_x1, bar_y1, progress_x, bar_y2, progress_color, 0, 0)
        
        -- Рисуем рамку
        --ImGui.DrawList_AddRect(draw_list, bar_x1, bar_y1, bar_x2, bar_y2, border_color, 0, 0, 1)
    end
end

local theme = r.GetExtState("SubtitlesWindow", "theme")
if theme == "" then theme = "default" end

local function apply_theme()
  if theme == "alternative" then
    COLOR_ACTIVE   = 0x000000FF   -- Чёрный текст
    COLOR_NEIGHBOR = 0x333333FF   -- Чуть светлее, чем чёрный
    COLOR_INACTIVE = 0x6a6a6aff   -- Фон окна (светлый)
    WINDOW_BG      = 0xABB1B1FF   -- Цвет фона окна
  else
    COLOR_ACTIVE   = 0xFFFFFFFF   -- Белый текст
    COLOR_NEIGHBOR = 0x5a5a5aFF   -- Серый
    COLOR_INACTIVE = 0x3a3a3aFF   -- Тёмно-серый фон
    WINDOW_BG      = 0x1c1c1cFF   -- Чёрный фон окна
  end
end

apply_theme()
-- Функция безопасного отсоединения шрифта
-- Если переменные ещё не определены, задаём начальные значения
if showProgressBar == nil then showProgressBar = false end
if font2_attached == nil then font2_attached = false end

local function safeDetachFont(ctx, font)
  if font and r.ImGui_ValidatePtr(font, "ImGui_Font*") then
    pcall(function() ImGui.Detach(ctx, font) end)
  end
end

function main_loop()
  if not r.ImGui_ValidatePtr(ctx, "ImGui_Context*") then
    ctx = r.ImGui_CreateContext("Subtitles Window")
    reloadFont = true
    font2_attached = false
  end

  if reloadFont then
    if font then safeDetachFont(ctx, font) end
    font = ImGui.CreateFont("sans-serif", fontSize, 0)
    ImGui.Attach(ctx, font)
    reloadFont = false
    r.SetExtState("SubtitlesWindow", "fontSize", tostring(fontSize), true)
    textHeightsCache = {}
  end

  ImGui.SetNextWindowSize(ctx, 640, 640, ImGui.Cond_FirstUseEver)
  ImGui.PushStyleColor(ctx, ImGui.Col_WindowBg, WINDOW_BG)
  local visible, open = ImGui.Begin(ctx, "Subtitles", true)
  ImGui.PopStyleColor(ctx)

  if visible then

    --ImGui.PushFont(ctx, font2)

    local avail_w, avail_h = ImGui.GetContentRegionAvail(ctx)
    if lastAvailW ~= avail_w then
      textHeightsCache = {}
      lastAvailW = avail_w
    end

    if ImGui.BeginChild(ctx, "ScrollingChild", avail_w, avail_h, 1, ImGui.WindowFlags_NoScrollWithMouse | ImGui.WindowFlags_NoScrollbar) then
      local win_x, win_y = ImGui.GetWindowPos(ctx)
      local win_w, _ = ImGui.GetWindowSize(ctx)
      ImGui.SetCursorScreenPos(ctx, win_x + win_w - 40, win_y + 10)
      if ImGui.Button(ctx, "Col") then
        theme = (theme == "default") and "alternative" or "default"
        r.SetExtState("SubtitlesWindow", "theme", theme, true)
        apply_theme()
      end

      if ImGui.BeginPopupContextWindow(ctx, "context_menu") then
        if ImGui.MenuItem(ctx, "Import subtitles (.srt or .ass)") then
          r.Main_OnCommand(r.NamedCommandLookup("_SWSMARKERLIST10"), 0)
          if srtass.importSubtitlesAsRegionsDialog() then
            
          end
          
          
        end
        if ImGui.MenuItem(ctx, "Export subtitles (.srt file)") then
          srtass.exportRegionsAsSRTDialog()
        end
        ImGui.Separator(ctx)
        if ImGui.MenuItem(ctx, "Show progress bar", nil, showProgressBar) then
          showProgressBar = not showProgressBar
          r.SetExtState("SubtitlesWindow", "showProgressBar", tostring(showProgressBar), true)
        end
        ImGui.EndPopup(ctx)
      end

      ImGui.Dummy(ctx, 0, avail_h * 0.25)
      --ImGui.PopFont(ctx)

      local fontPushed = false
      if font and r.ImGui_ValidatePtr(font, "ImGui_Font*") then
        ImGui.PushFont(ctx, font)
        fontPushed = true
      end

      local regions = get_cached_regions()
      local play_state = r.GetPlayState()
      local cursor_pos = ((play_state & 1) == 1) and r.GetPlayPosition() or r.GetCursorPosition()
      local activeIndex = nil
      for i, region in ipairs(regions) do
        if cursor_pos >= region.start and cursor_pos < region.endPos then
          activeIndex = i
          break
        elseif cursor_pos == region.endPos then
          if regions[i+1] and regions[i+1].start == cursor_pos then
            activeIndex = i+1
          else
            activeIndex = i
          end
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
          local currentBrightness = f.getBrightness(regionColors[i])
          local targetBrightness = f.getBrightness(target)
          local factor = darkenFactor
          if targetBrightness > currentBrightness then
            factor = brightenFactor * brightenFactor * brightenFactor
          end
          regionColors[i] = f.lerpColor(regionColors[i], target, factor)
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
      if fontPushed then ImGui.PopFont(ctx) end
      ImGui.EndChild(ctx)

      if showProgressBar then
        draw_progress_subtitle(activeIndex, regions, cursor_pos)
      end
    end

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
    cachedRegions = f.get_regions()
    cachedRegionsTime = r.time_precise()
  end

  if open then r.defer(main_loop) end
end

r.atexit()
r.defer(main_loop)