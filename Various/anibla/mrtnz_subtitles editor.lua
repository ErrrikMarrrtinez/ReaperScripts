--@noindex
--NoIndex: true

local r = reaper
local script_path = debug.getinfo(1, "S").source:match("@(.*[\\/])")
local imgui_path = r.ImGui_GetBuiltinPath()..'/?.lua'
package.path = imgui_path..";"..script_path..'?.lua'
local im = require 'imgui' '0.9.2.3'

local SubtitleLib = require('mrtnz_srtass-parser')


local ctx, font, activeField, activeRow = nil, nil, nil, nil
local first_column_values, second_column_values = {}, {}
local subtitles1, subtitles2 = {}, {}  -- Таблицы для субтитров
local cachedWrappedText = {}

-- Режим работы только с субтитрами (привязка к регионам отключена)
local subtitle_mode = true

-- Функция для преобразования субтитров в массив текстовых значений (если понадобится)
function SubtitlesToDisplayValues(subtitles)
  local values = {}
  for i, subtitle in ipairs(subtitles) do
    values[i] = subtitle.text or ""
  end
  return values
end

-- Функция загрузки субтитров
function LoadSubtitles(columnNumber)
  local extensionList = "SRT и ASS файлы\0*.srt;*.ass\0Все файлы\0*.*\0\0"
  local retval, fileNames = r.JS_Dialog_BrowseForOpenFiles("Загрузить субтитры", "", "", extensionList, false)
  if retval == 1 and fileNames and fileNames ~= "" then
    local folder, file = fileNames:match("^(.-)\0(.-)\0")
    local fullPath = ""
    if folder and file and file ~= "" then
      local sep = (r.GetOS():find("Win")) and "\\" or "/"
      fullPath = folder .. sep .. file
    else
      fullPath = fileNames
    end

    local ext = fullPath:match("%.([^%.]+)$")
    if ext then
      ext = ext:lower()
    else
      ext = "srt"
    end
    
    local parsed_subtitles, err
    if ext == "srt" then
      parsed_subtitles = SubtitleLib.parseSRTFile(fullPath)
    elseif ext == "ass" then
      parsed_subtitles = SubtitleLib.parseASSFile(fullPath)
    else
      r.ShowMessageBox("Неподдерживаемый формат файла: " .. ext, "Ошибка", 0)
      return
    end
    
    if not parsed_subtitles then
      r.ShowMessageBox("Ошибка загрузки субтитров: " .. (err or "неизвестная ошибка"), "Ошибка", 0)
      return
    end
    
    if #parsed_subtitles == 0 then
      r.ShowMessageBox("Нет субтитров в файле", "Ошибка", 0)
      return
    end
    
    table.sort(parsed_subtitles, function(a, b) return a.start < b.start end)
    
    if columnNumber == 1 then
      subtitles1 = parsed_subtitles
      first_column_values = SubtitlesToDisplayValues(subtitles1)
    else
      subtitles2 = parsed_subtitles
      second_column_values = SubtitlesToDisplayValues(subtitles2)
    end
    
    subtitle_mode = true
    cachedWrappedText = {}
    r.ShowMessageBox("Загружено субтитров: " .. #parsed_subtitles, "Информация", 0)
  end
end

-- Функция экспорта субтитров в SRT
function ExportSubtitles(columnNumber)
  local subtitles = (columnNumber == 1) and subtitles1 or subtitles2
  local values = (columnNumber == 1) and first_column_values or second_column_values
  
  if #subtitles == 0 then
    r.ShowMessageBox("Нет субтитров для экспорта", "Ошибка", 0)
    return
  end
  
  for i, subtitle in ipairs(subtitles) do
    if values[i] then
      subtitle.text = values[i]
    end
  end
  
  local srt_content = ""
  for i, subtitle in ipairs(subtitles) do
    local start_time = SubtitleLib.formatSRTTime(subtitle.start)
    local end_time = SubtitleLib.formatSRTTime(subtitle._end)
    local text = subtitle.text or ""
    srt_content = srt_content .. string.format("%d\n%s --> %s\n%s\n\n", i, start_time, end_time, text)
  end
  
  local proj, projfn = r.EnumProjects(-1)
  if projfn == "" then projfn = "untitled.rpp" end
  local defaultName = (projfn:match("([^\\/:]+)%.rpp$") or projfn) .. "_column" .. columnNumber .. ".srt"
  local initialFolder = r.GetProjectPath(0, "")
  
  local extensionList = "SRT files\0.srt\0All files\0.*\0\0"
  local retval, fileName = r.JS_Dialog_BrowseForSaveFile("Экспорт SRT", initialFolder, defaultName, extensionList)
  if retval == 1 and fileName and fileName ~= "" then
    fileName = fileName:match("^%s*(.-)%s*$")
    if not fileName:lower():match("%.srt$") then
      fileName = fileName .. ".srt"
    end
    local file, err = io.open(fileName, "w")
    if not file then
      r.ShowMessageBox("Ошибка создания файла SRT: " .. err, "Ошибка", 0)
      return
    end
    file:write(srt_content)
    file:close()
    r.ShowMessageBox("SRT экспортирован: " .. fileName, "Экспорт", 0)
  end
end

-- Функция импорта субтитров как регионов
function ImportSubtitlesAsRegions(columnNumber)
  local subtitles = (columnNumber == 1) and subtitles1 or subtitles2
  local values = (columnNumber == 1) and first_column_values or second_column_values
  
  if #subtitles == 0 then
    r.ShowMessageBox("Нет субтитров для импорта", "Ошибка", 0)
    return
  end
  
  for i, subtitle in ipairs(subtitles) do
    if values[i] then
      subtitle.text = values[i]
    end
  end
  
  r.Undo_BeginBlock()
  -- Перед импортом удаляем все регионы
  r.Main_OnCommand(reaper.NamedCommandLookup("_SWSMARKERLIST10"), 0)
  
  for _, subtitle in ipairs(subtitles) do
    r.AddProjectMarker(0, true, subtitle.start, subtitle._end, subtitle.text, -1)
  end
  
  r.UpdateArrange()
  r.Undo_EndBlock("Импорт субтитров как регионы", -1)
  
  r.ShowMessageBox("Импортировано " .. #subtitles .. " регионов", "Импорт", 0)
end

-- Функция для автопереноса текста
function WrapText(text, maxWidth, cacheKey)
  if not text or text == "" then return text end
  if text:find("\n") then return text end
  if cachedWrappedText[cacheKey] then return cachedWrappedText[cacheKey] end
  local wrappedText, currentLine = "", ""
  for word in text:gmatch("%S+") do
    if currentLine == "" then 
      currentLine = word 
    else
      local potentialLineWidth = im.CalcTextSize(ctx, currentLine.." "..word)
      if potentialLineWidth > maxWidth then 
        wrappedText = wrappedText..currentLine.."\n"
        currentLine = word 
      else 
        currentLine = currentLine.." "..word 
      end
    end
  end
  if currentLine ~= "" then 
    wrappedText = wrappedText..currentLine 
  end
  cachedWrappedText[cacheKey] = wrappedText
  return wrappedText
end

function InitImGui()
  if not r.APIExists("ImGui_CreateContext") then 
    r.ShowMessageBox("ReaImGui требуется для этого скрипта. Установите его через ReaPack.", "Ошибка", 0)
    return false 
  end
  ctx = im.CreateContext('Project Regions and Subtitles')
  font = im.CreateFont('sans-serif', 18)
  im.Attach(ctx, font)
  return true
end

-- Рисует ячейку ввода с поддержкой автопереноса
function DrawCellInput(fieldName, rowIndex, text, finalHeight, updateCallback)
  local isActive = (activeField == fieldName and activeRow == rowIndex)
  if isActive then 
    im.PushStyleColor(ctx, im.Col_Border, 0x4080FFFF)
    im.PushStyleColor(ctx, im.Col_FrameBg, 0x3A3A5AFF)
    im.PushStyleVar(ctx, im.StyleVar_FrameBorderSize, 2.0)
  end
  im.SetNextItemWidth(ctx, -1)
  im.PushStyleVar(ctx, im.StyleVar_FramePadding, 2, 4)
  local flags = im.InputTextFlags_NoHorizontalScroll
  if isActive then 
    flags = flags + im.InputTextFlags_AutoSelectAll 
  end
  local changed, newVal = im.InputTextMultiline(ctx, '##'..fieldName..rowIndex, text, -1, finalHeight, flags)
  im.PopStyleVar(ctx)
  if im.IsItemActive(ctx) then 
    activeField = fieldName 
    activeRow = rowIndex 
  end
  if changed then 
    updateCallback(newVal) 
  end
  if isActive then 
    im.PopStyleVar(ctx)
    im.PopStyleColor(ctx, 2)
  end
  return changed, newVal
end

function Main()
  im.PushFont(ctx, font)
  local availX, availY = im.GetContentRegionAvail(ctx)
  
  -- Стили кнопок (высота чуть меньше за счёт заданного frame padding)
  im.PushStyleVar(ctx, im.StyleVar_FramePadding, 0, 3)
  im.PushStyleVar(ctx, im.StyleVar_FrameRounding, 7.0)
  im.PushStyleVar(ctx, im.StyleVar_FrameBorderSize, 0.1)
  im.PushStyleColor(ctx, im.Col_Button, 0x4F4F4FFF)
  im.PushStyleColor(ctx, im.Col_ButtonHovered, 0x5A5A5AFF)
  im.PushStyleColor(ctx, im.Col_ButtonActive, 0x7878D7FF)
  
  local buttonWidth = availX / 2 - 4
  
  -- Первая строка: кнопки загрузки субтитров
  if im.Button(ctx, 'Load subtitles #1', buttonWidth, 0) then
    LoadSubtitles(1)
  end
  im.SameLine(ctx)
  if im.Button(ctx, 'Load subtitles #2', buttonWidth, 0) then
    LoadSubtitles(2)
  end
  
  -- Вторая строка: кнопки экспорта SRT
  if im.Button(ctx, 'Export SRT #1', buttonWidth, 0) then
    ExportSubtitles(1)
  end
  im.SameLine(ctx)
  if im.Button(ctx, 'Export SRT #2', buttonWidth, 0) then
    ExportSubtitles(2)
  end
  
  -- Третья строка: кнопки импорта субтитров как регионов (удаляем регионы перед импортом)
  if im.Button(ctx, 'Import as regions #1', buttonWidth, 0) then
    r.Main_OnCommand(r.NamedCommandLookup("_SWSMARKERLIST10"), 0)
    ImportSubtitlesAsRegions(1)
  end
  im.SameLine(ctx)
  if im.Button(ctx, 'Import as regions #2', buttonWidth, 0) then
    r.Main_OnCommand(r.NamedCommandLookup("_SWSMARKERLIST10"), 0)
    ImportSubtitlesAsRegions(2)
  end
  
  im.PopStyleColor(ctx, 3)
  im.PopStyleVar(ctx, 3)
  im.Separator(ctx)
  
  -- Настройки области контента
  im.PushStyleVar(ctx, im.StyleVar_FramePadding, 6, 6)
  im.PushStyleVar(ctx, im.StyleVar_FrameRounding, 4.0)
  im.PushStyleVar(ctx, im.StyleVar_FrameBorderSize, 0.5)
  im.PushStyleVar(ctx, im.StyleVar_CellPadding, 1.0, 1.0)
  im.PushStyleColor(ctx, im.Col_FrameBg, 0x2A2A2AFF)
  im.PushStyleColor(ctx, im.Col_FrameBgHovered, 0x3A3A3AFF)
  im.PushStyleColor(ctx, im.Col_FrameBgActive, 0x3A3A5AFF)
  im.PushStyleColor(ctx, im.Col_Border, 0x555555FF)
  im.PushStyleColor(ctx, im.Col_BorderShadow, 0x00000066)
  im.PushStyleColor(ctx, im.Col_TextSelectedBg, 0x8a8a8a99)
  
  local contentHeight = availY - 120
  if im.BeginChild(ctx, 'chld', availX, contentHeight) then
    
    if (#subtitles1 == 0 and #subtitles2 == 0) then
      im.Text(ctx, "Загрузите субтитры в колонки.")
      im.EndChild(ctx)
      im.PopStyleVar(ctx, 4)
      im.PopStyleColor(ctx, 6)
      im.PopFont(ctx)
      return
    end
    
    local itemCount = math.max(#subtitles1, #subtitles2)
    if im.BeginTable(ctx, 'regions_table', 3, im.TableFlags_Borders + im.TableFlags_ScrollY) then
      -- Замените настройку колонки в BeginTable:
      im.TableSetupColumn(ctx, 'Time Interval', im.TableColumnFlags_WidthFixed, 110)
      
      im.TableSetupColumn(ctx, 'Subtitle 1', im.TableColumnFlags_WidthStretch, 1.0)
      im.TableSetupColumn(ctx, 'Subtitle 2', im.TableColumnFlags_WidthStretch, 1.0)
      im.TableHeadersRow(ctx)
      
      local _, headerTop = im.GetCursorScreenPos(ctx)
      local headerHeight = 20
      local cumulative = headerHeight
      local activeCenter = nil
      local lineHeight = im.GetTextLineHeight(ctx)
      local padding = 4
      local columnWidth = availX / 3
      
      for i = 1, itemCount do
        im.TableNextRow(ctx)
        local text1 = first_column_values[i] or ""
        local text2 = second_column_values[i] or ""
        
        local cacheKey1 = "col1_" .. i .. "_" .. tostring(columnWidth) .. "_" .. text1
        local displayText1 = WrapText(text1, columnWidth, cacheKey1)
        local lineCount1 = 1 
        for _ in displayText1:gmatch("\n") do lineCount1 = lineCount1 + 1 end
        local dynHeight1 = lineCount1 * lineHeight + padding + 15
        
        local cacheKey2 = "col2_" .. i .. "_" .. tostring(columnWidth) .. "_" .. text2
        local displayText2 = WrapText(text2, columnWidth, cacheKey2)
        local lineCount2 = 1 
        for _ in displayText2:gmatch("\n") do lineCount2 = lineCount2 + 1 end
        local dynHeight2 = lineCount2 * lineHeight + padding + 15
        
        local dynHeightTime = (2 * lineHeight) + padding + 15  -- фиксированно 2 строки для времени
        local finalHeight = math.max(dynHeightTime, dynHeight1, dynHeight2)
        
        local row_top = cumulative
        if activeRow == i then 
          activeCenter = row_top + finalHeight / 2 
        end
        ------------
        -- Первая колонка: Вывод временного интервала с фиксированной шириной (105px), с выравниванием по центру
        im.TableSetColumnIndex(ctx, 0)
        local cellWidth = 105  -- фиксированная ширина колонки
        local timeText = ""
        if subtitles1[i] then
          timeText = SubtitleLib.formatSRTTime(subtitles1[i].start) .. "\n" .. SubtitleLib.formatSRTTime(subtitles1[i]._end)
        elseif subtitles2[i] then
          timeText = SubtitleLib.formatSRTTime(subtitles2[i].start) .. "\n" .. SubtitleLib.formatSRTTime(subtitles2[i]._end)
        end
        
        -- Разбиваем текст на строки для вычисления размеров
        local lines = {}
        for line in timeText:gmatch("([^\n]+)") do
          table.insert(lines, line)
        end
        local maxLineWidth = 0
        for _, line in ipairs(lines) do
          local w = im.CalcTextSize(ctx, line)
          if w > maxLineWidth then maxLineWidth = w end
        end
        local lineHeight = im.GetTextLineHeight(ctx)
        local totalTextHeight = #lines * lineHeight
        
        -- Вычисляем отступы для центрирования по горизонтали и вертикали
        local offsetX = (cellWidth - maxLineWidth) * 0.5
        local offsetY = (finalHeight - totalTextHeight) * 0.5
        
        -- Запоминаем текущую позицию курсора и сдвигаем её
        local curX, curY = im.GetCursorPos(ctx)
        im.SetCursorPos(ctx, curX + offsetX, curY + offsetY)
        im.Text(ctx, timeText)
        
        -------------
        
        -- Вторая колонка: Текст субтитра 1
        im.TableSetColumnIndex(ctx, 1)
        im.PushID(ctx, 'col1_'..i)
        DrawCellInput("col1", i, displayText1, finalHeight, function(val)
          first_column_values[i] = val
          cachedWrappedText[cacheKey1] = nil
        end)
        im.PopID(ctx)
        
        -- Третья колонка: Текст субтитра 2
        im.TableSetColumnIndex(ctx, 2)
        im.PushID(ctx, 'col2_'..i)
        DrawCellInput("col2", i, displayText2, finalHeight, function(val)
          second_column_values[i] = val
          cachedWrappedText[cacheKey2] = nil
        end)
        im.PopID(ctx)
        
        cumulative = cumulative + finalHeight
      end
      
      im.EndTable(ctx)
    end
    im.EndChild(ctx)
  end
  
  im.PopStyleVar(ctx, 4)
  im.PopStyleColor(ctx, 6)
  im.PopFont(ctx)
end

function Defer()
  local visible, open = im.Begin(ctx, 'Project Regions and Subtitles', true, im.WindowFlags_NoDocking)
  if visible then 
    Main()
    im.End(ctx)
  end
  if open then 
    r.defer(Defer)
  else 
    local _, _, sectionID, cmdID = r.get_action_context()
    r.SetToggleCommandState(sectionID, cmdID, 0)
    r.RefreshToolbar2(sectionID, cmdID)
  end
end

function Init()
  local _, _, sectionID, cmdID = r.get_action_context()
  r.SetToggleCommandState(sectionID, cmdID, 1)
  r.RefreshToolbar2(sectionID, cmdID)
  if not InitImGui() then return end
  Defer()
end

-- Если в SubtitleLib не реализованы функции разбора SRT/ASS, добавляем их
if not SubtitleLib.parseSRTFile then
  SubtitleLib.parseSRTFile = function(filePath)
    local file, err = io.open(filePath, "r")
    if not file then
      return nil, "Не удалось открыть файл: " .. err
    end
    local content = file:read("*a")
    file:close()
    
    content = content:gsub("\r\n", "\n")
    
    local regions = {}
    local pattern = "(%d+)%s*\n([0-9:,]+)%s*%-%->%s*([0-9:,]+)%s*\n(.-)\n%s*\n"
    for id, startTime, endTime, text in content:gmatch(pattern) do
      local startSec = SubtitleLib.parseTime(startTime)
      local endSec = SubtitleLib.parseTime(endTime)
      if startSec and endSec then
        text = text:gsub("\n", " "):gsub("^%s+", ""):gsub("%s+$", "")
        text = SubtitleLib.cleanText and SubtitleLib.cleanText(text) or text
        table.insert(regions, {start = startSec, _end = endSec, text = text})
      end
    end
    
    if #regions == 0 then
      local id, startTime, endTime, text = content:match("(%d+)%s*\n([0-9:,]+)%s*%-%->%s*([0-9:,]+)%s*\n(.*)$")
      if id then
        local startSec = SubtitleLib.parseTime(startTime)
        local endSec = SubtitleLib.parseTime(endTime)
        if startSec and endSec then
          text = text:gsub("\n", " "):gsub("^%s+", ""):gsub("%s+$", "")
          text = SubtitleLib.cleanText and SubtitleLib.cleanText(text) or text
          table.insert(regions, {start = startSec, _end = endSec, text = text})
        end
      end
    end
    
    return regions
  end
end

if not SubtitleLib.parseASSFile then
  SubtitleLib.parseASSFile = function(filePath)
    local file, err = io.open(filePath, "r")
    if not file then
      return nil, "Не удалось открыть файл: " .. err
    end
    local content = file:read("*a")
    file:close()
    
    content = content:gsub("\r\n", "\n")
    
    local eventsSection = false
    local formatFields = nil
    local regions = {}
    
    for line in content:gmatch("[^\n]+") do
      if line:match("^%s*%[Events%]") then
        eventsSection = true
      elseif eventsSection then
        if line:match("^%s*%[") then break end
        
        local formatLine = line:match("^%s*Format:%s*(.+)")
        if formatLine then
          formatFields = {}
          for field in formatLine:gmatch("[^,]+") do
            field = field:match("^%s*(.-)%s*$")
            table.insert(formatFields, field)
          end
        end
        
        local dialogueLine = line:match("^%s*Dialogue:%s*(.+)")
        if dialogueLine and formatFields then
          local fields = {}
          local fieldCount = #formatFields
          local currentIndex = 1
          for i = 1, fieldCount - 1 do
            local commaPos = dialogueLine:find(",", currentIndex, true)
            if not commaPos then break end
            local fieldVal = dialogueLine:sub(currentIndex, commaPos - 1)
            fieldVal = fieldVal:match("^%s*(.-)%s*$")
            table.insert(fields, fieldVal)
            currentIndex = commaPos + 1
          end
          local lastField = dialogueLine:sub(currentIndex)
          lastField = lastField:match("^%s*(.-)%s*$")
          table.insert(fields, lastField)
          
          if #fields < fieldCount then
            goto continueDialogue
          end
          
          local startTime, endTime, text = nil, nil, nil
          for idx, fieldName in ipairs(formatFields) do
            local lowerField = fieldName:lower()
            if lowerField == "start" then
              startTime = fields[idx]
            elseif lowerField == "end" then
              endTime = fields[idx]
            elseif lowerField == "text" then
              text = fields[idx]
            end
          end
          
          if startTime and endTime and text then
            local startSec = SubtitleLib.parseASSTime(startTime)
            local endSec = SubtitleLib.parseASSTime(endTime)
            if startSec and endSec then
              text = SubtitleLib.cleanText and SubtitleLib.cleanText(text) or text
              table.insert(regions, {start = startSec, _end = endSec, text = text})
            end
          end
        end
      end
      ::continueDialogue::
    end
    
    return regions
  end
end

if not SubtitleLib.formatSRTTime then
  SubtitleLib.formatSRTTime = function(seconds)
    local hours = math.floor(seconds / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    local secs = math.floor(seconds % 60)
    local msecs = math.floor((seconds - math.floor(seconds)) * 1000)
    return string.format("%02d:%02d:%02d,%03d", hours, minutes, secs, msecs)
  end
end

Init()
