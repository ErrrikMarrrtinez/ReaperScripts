--@noindex
--NoIndex: true

local r = reaper; r.defer(function() end)
local script_path = debug.getinfo(1, "S").source:match("@(.*[\\/])")

if not reaper.ImGui_GetBuiltinPath then 
    package.path = script_path .. '?.lua'
else
    imgui_path = reaper.ImGui_GetBuiltinPath() .. '/?.lua'
    package.path = imgui_path .. ";" .. script_path .. '?.lua'
    ImGui = require 'imgui' '0.9.2.3'
end

local f = require('mrtnz_utils')
local srtass = require('mrtnz_srtass-parser')

local state = f.checkDependencies()
if not state then return end

--[[
f.importSubtitlesAsRegions        = importSubtitlesAsRegions
f.exportRegionsAsSRTDialog        = exportRegionsAsSRTDialog
f.convertASStoSRT                 = convertASStoSRT
f.importSubtitlesAsRegionsDialog  = importSubtitlesAsRegionsDialog
]]                               -- srtass.importSubtitlesAsRegionsDialog()

local ctx = ImGui.CreateContext('Subtitles Window')
local COLOR_ACTIVE   = 0xFFFFFFFF
local COLOR_NEIGHBOR = 0x5a5a5aFF
local COLOR_INACTIVE = 0x3a3a3aFF
local fontSize = 25
local savedFontSize = r.GetExtState("SubtitlesWindow", "fontSize")
if savedFontSize and savedFontSize ~= "" then fontSize = tonumber(savedFontSize) or fontSize end

local reloadFont = true
local cachedRegions = {}
local cachedRegionsTime = 0
local CACHE_INTERVAL = 0.78  -- базовый интервал (при воспроизведении)
local regionColors = {}
local scrollY = 0

local showProgressBar = true
local savedProgressBarState = r.GetExtState("SubtitlesWindow", "showProgressBar")
if savedProgressBarState and savedProgressBarState ~= "" then 
    showProgressBar = savedProgressBarState == "true"
end

local textHeightsCache = {}

-- Дополнительное кеширование вычислений при отсутствии движения курсора
local lastCursorPos = nil
local cachedActiveIndices = {}
local cachedRegionCenters = {}
local cachedTotalHeight = 0

-- Переменные для редактора субтитров
local editorOpen = false
local editingIndices = {}  -- номера регионов, которые редактируются
local editorTexts = {}     -- текущие тексты для редактирования

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

-- Функция динамического кеширования регионов (с динамическим интервалом обновления)
function get_cached_regions(dynamicInterval)
  local now = r.time_precise()
  if now - cachedRegionsTime > dynamicInterval then
    cachedRegions = f.get_regions()
    cachedRegionsTime = now
  end
  return cachedRegions
end

-- Функция отрисовки прогресс-бара для каждого активного субтитра (если их несколько)
function draw_progress_subtitles(activeIndices, regions, cursor_pos)
    if #activeIndices > 0 then
        local draw_list = reaper.ImGui_GetForegroundDrawList(ctx)
        local win_pos_x, win_pos_y = ImGui.GetWindowPos(ctx)
        local win_size_x, win_size_y = ImGui.GetWindowSize(ctx)
        local margin = 10
        local bar_height = 15
        for j, index in ipairs(activeIndices) do
            local activeRegion = regions[index]
            local regionLength = activeRegion.endPos - activeRegion.start
            local progress = (cursor_pos - activeRegion.start) / regionLength
            progress = math.min(math.max(progress, 0), 1)
            
            local offset_y = win_size_y - margin - bar_height - (j-1) * (bar_height + 5)
            local bar_x1 = win_pos_x + margin
            local bar_y1 = win_pos_y + offset_y
            local bar_x2 = win_pos_x + win_size_x - margin
            local bar_y2 = bar_y1 + bar_height
            
            local bar_color = 0xFF8B0000
            local progress_color = 0xcd583320
            local border_color = 0xFFFFFF40
            
            ImGui.DrawList_AddRectFilled(draw_list, bar_x1, bar_y1, bar_x2, bar_y2, bar_color, 0, 0)
            local progress_x = bar_x1 + (bar_x2 - bar_x1) * progress
            ImGui.DrawList_AddRectFilled(draw_list, bar_x1, bar_y1, progress_x, bar_y2, progress_color, 0, 0)
        end
    end
end

local theme = r.GetExtState("SubtitlesWindow", "theme")
if theme == "" then theme = "default" end

local function apply_theme()
  if theme == "alternative" then
    COLOR_ACTIVE   = 0x000000FF
    COLOR_NEIGHBOR = 0x333333FF
    COLOR_INACTIVE = 0x6a6a6aff
    WINDOW_BG      = 0xABB1B1FF
  else
    COLOR_ACTIVE   = 0xFFFFFFFF
    COLOR_NEIGHBOR = 0x5a5a5aFF
    COLOR_INACTIVE = 0x3a3a3aFF
    WINDOW_BG      = 0x1c1c1cFF
  end
end

apply_theme()
if showProgressBar == nil then showProgressBar = false end
if font2_attached == nil then font2_attached = false end

local function safeDetachFont(ctx, font)
  if font and r.ImGui_ValidatePtr(font, "ImGui_Font*") then
    pcall(function() ImGui.Detach(ctx, font) end)
  end
end


local function isActive(i, indices)
    for _, idx in ipairs(indices) do
        if idx == i then return true end
    end
    return false
end

local function isNeighbor(i, indices)
    for _, idx in ipairs(indices) do
        if i == idx - 1 or i == idx + 1 then return true end
    end
    return false
end

local function update_region_name(region, newName)
    local cursor_pos = reaper.GetCursorPosition()
    local num_regions = reaper.CountProjectMarkers(0)
    
    for i = 0, num_regions - 1 do
        local retval, isrgn, pos, rgnend, name, markrgnindexnumber = reaper.EnumProjectMarkers(i)
        -- Если курсор на начале региона, приоритетно выбираем этот регион
        if isrgn and cursor_pos == pos then
            reaper.SetProjectMarkerByIndex(0, i, isrgn, pos, rgnend, markrgnindexnumber, newName, 0)
            return true
        end
    end
    
    -- Если не нашли регион по началу, ищем регион, содержащий курсор
    for i = 0, num_regions - 1 do
        local retval, isrgn, pos, rgnend, name, markrgnindexnumber = reaper.EnumProjectMarkers(i)
        if isrgn and cursor_pos > pos and cursor_pos <= rgnend then
            reaper.SetProjectMarkerByIndex(0, i, isrgn, pos, rgnend, markrgnindexnumber, newName, 0)
            return true
        end
    end
    
    reaper.UpdateArrange()
    return false
end
function main_loop()
  if not r.ImGui_ValidatePtr(ctx, "ImGui_Context*") then
    ctx = r.ImGui_CreateContext("Subtitles Window")
    reloadFont = true
    font2_attached = false
  end

  if reloadFont then
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
          if srtass.importSubtitlesAsRegionsDialog() then
            -- обработка импорта
          end
          f.CreateVideoItemsInRegions()
          f.ToggleMarkerTrackMute()
        end
        if ImGui.MenuItem(ctx, "Export subtitles (.srt file)") then
          srtass.exportRegionsAsSRTDialog()
        end
        
        if ImGui.MenuItem(ctx, "Show/hide subtitles in video player") then
          if f.find_marker_track() == nil then
          f.CreateVideoItemsInRegions()
          
          else
          
          f.ToggleMarkerTrackMute()
          end
        end
        
        
        ImGui.Separator(ctx)
        if ImGui.MenuItem(ctx, "Show progress bar", nil, showProgressBar) then
          showProgressBar = not showProgressBar
          r.SetExtState("SubtitlesWindow", "showProgressBar", tostring(showProgressBar), true)
        end
        ImGui.EndPopup(ctx)
      end

      ImGui.Dummy(ctx, 0, avail_h * 0.25)

      local fontPushed = false
      if font and r.ImGui_ValidatePtr(font, "ImGui_Font*") then
        ImGui.PushFont(ctx, font)
        fontPushed = true
      end

      local play_state = r.GetPlayState()
      local cursor_pos = ((play_state & 1) == 1) and r.GetPlayPosition() or r.GetCursorPosition()
      local dynamicInterval = ((play_state & 1) == 1) and 0.25 or 1.0

      local regions = get_cached_regions(dynamicInterval)

      -- Всегда пересчитываем активные субтитры, чтобы изменения курсора не игнорировались
      local recalcData = true

      local brightenFactor = 0.89
      local darkenFactor = 0.1
      local activeIndices = {}
      local regionCenters = {}
      local totalHeight = 0

      if recalcData then
          for i, region in ipairs(regions) do
            if cursor_pos >= region.start and cursor_pos < region.endPos then
              table.insert(activeIndices, i)
            end
          end
          cachedActiveIndices = activeIndices

          for i, region in ipairs(regions) do
            local target = COLOR_INACTIVE
            if isActive(i, activeIndices) then
                target = COLOR_ACTIVE
            elseif isNeighbor(i, activeIndices) then
                target = COLOR_NEIGHBOR
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

          for i, region in ipairs(regions) do
            if not textHeightsCache[region.name] then
              textHeightsCache[region.name] = calculateWrappedTextHeight(ctx, region.name, avail_w - 8)
            end
            totalHeight = totalHeight + textHeightsCache[region.name] + 5
          end
          local verticalOffset = 0
          if totalHeight < avail_h then verticalOffset = (avail_h - totalHeight) * 0.5 end
          local currentY = verticalOffset
          for i, region in ipairs(regions) do
            regionCenters[i] = currentY + textHeightsCache[region.name] * 0.5
            currentY = currentY + textHeightsCache[region.name] + 5
          end
          cachedRegionCenters = regionCenters
          cachedTotalHeight = totalHeight
          lastCursorPos = cursor_pos
      else
          activeIndices = cachedActiveIndices or {}
          regionCenters = cachedRegionCenters or {}
          totalHeight = cachedTotalHeight or 0
      end

      local desiredCenter = nil
      if #activeIndices > 0 then
          local sum = 0
          for _, idx in ipairs(activeIndices) do
              sum = sum + regionCenters[idx]
          end
          desiredCenter = sum / #activeIndices
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
          local delta = desiredScroll - scrollY
          local smoothFactor = 0.35  -- уменьшенный фактор для более плавного движения
          scrollY = scrollY + delta * smoothFactor
          ImGui.SetScrollY(ctx, scrollY)
      end
      

      local verticalOffset = 0
      if totalHeight < avail_h then verticalOffset = (avail_h - totalHeight) * 0.5 end
      local currentY = verticalOffset
      for i, region in ipairs(regions) do
        ImGui.PushStyleColor(ctx, ImGui.Col_Text, regionColors[i] or COLOR_INACTIVE)
        ImGui.SetCursorPosY(ctx, currentY)
        draw_centered_wrapped_text(ctx, region.name, avail_w - 8)
        ImGui.PopStyleColor(ctx)
        local height = textHeightsCache[region.name]
        if not height then
          height = calculateWrappedTextHeight(ctx, region.name, avail_w - 8)
          textHeightsCache[region.name] = height
        end
        currentY = currentY + height + 5
      end
      

      ImGui.Dummy(ctx, 0, avail_h * 0.25)
      if fontPushed then ImGui.PopFont(ctx) end
      ImGui.EndChild(ctx)

      if showProgressBar then
        draw_progress_subtitles(activeIndices, regions, cursor_pos)
      end

      if ImGui.IsMouseDoubleClicked(ctx, 0) and #activeIndices > 0 then
          editorOpen = true
          editingIndices = {}
          editorTexts = {}
          for _, idx in ipairs(activeIndices) do
              table.insert(editingIndices, idx)
              editorTexts[idx] = regions[idx].name or ""
          end
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
          textHeightsCache = {}
          lastCursorPos = nil
        end
      end
  end
  
  if ImGui.IsMouseClicked(ctx, 0) then
    cachedRegions = f.get_regions()
    cachedRegionsTime = r.time_precise()
  end

  if editorOpen and editorFirstFrame == nil then
    editorFirstFrame = true
    for i, idx in ipairs(editingIndices) do
        local region = cachedRegions[idx]
        if region then
            editorTexts[idx] = region.name or ""
        end
    end
  end

  if editorOpen then
    ImGui.SetNextWindowSize(ctx, 300, 300, ImGui.Cond_FirstUseEver)
    local editorVisible, editorOpenFlag = ImGui.Begin(ctx, "Subtitle Editor", true, ImGui.WindowFlags_NoCollapse|ImGui.WindowFlags_NoDocking)
    if not editorOpenFlag then
        editorOpen = false
    end
    if editorVisible then
        ImGui.Text(ctx, "Edit active subtitle(s):")
        local flags = ImGui.InputTextFlags_NoHorizontalScroll 
                    | ImGui.InputTextFlags_AutoSelectAll 
                    | ImGui.InputTextFlags_CtrlEnterForNewLine
        for i, idx in ipairs(editingIndices) do
            local region = cachedRegions[idx]
            if region then
                ImGui.Text(ctx, "Region " .. idx)
                local input_width = ImGui.GetContentRegionAvail(ctx)
                if i == 1 and editorFirstFrame then
                    ImGui.SetKeyboardFocusHere(ctx)
                    editorFirstFrame = false
                end
                
                if not editorTexts[idx] then
                    editorTexts[idx] = ""
                end
                
                if #editorTexts[idx] > 1000 then
                    editorTexts[idx] = string.sub(editorTexts[idx], 1, 1000)
                end
                
                local changed, newText = ImGui.InputTextMultiline(ctx, "##editor" .. idx, editorTexts[idx], 1024, input_width, 80, flags, nil)
                if changed and newText then
                    editorTexts[idx] = newText
                end
            end
        end
        if ImGui.Button(ctx, "Apply") then
            for _, idx in ipairs(editingIndices) do
                local region = cachedRegions[idx]
                if region and editorTexts[idx] then
                    update_region_name(region, editorTexts[idx])
                end
            end
            editorOpen = false
            editorFirstFrame = nil
        end
        ImGui.SameLine(ctx)
        if ImGui.Button(ctx, "Cancel") then
            editorOpen = false
            editorFirstFrame = nil
        end
        if ImGui.IsKeyPressed(ctx, ImGui.Key_Escape) then
            editorOpen = false
            editorFirstFrame = nil
        elseif ImGui.IsKeyPressed(ctx, ImGui.Key_Enter) then
            for _, idx in ipairs(editingIndices) do
                local region = cachedRegions[idx]
                if region and editorTexts[idx] then
                    update_region_name(region, editorTexts[idx])
                end
            end
            editorOpen = false
            editorFirstFrame = nil
        end
    end
    ImGui.End(ctx)
  end

  if open then r.defer(main_loop) end
end


r.atexit()
r.defer(main_loop)