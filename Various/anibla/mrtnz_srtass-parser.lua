--@noindex
--NoIndex: true

--[[
  Библиотека для работы с субтитрами в REAPER.
  Функционал:
    - Импорт регионов из файлов субтитров (SRT или ASS) в проект.
    - Экспорт регионов проекта в SRT-файл с выбором места сохранения через диалог.
    - Конвертация ASS-файла в SRT.
    - Диалоговый импорт файла субтитров (SRT или ASS).
  Использование:
    local SubtitlesLib = require("SubtitlesLib")
    SubtitlesLib.importSubtitlesAsRegions("C:\\Users\\Эрик\\Downloads\\6 (1).srt")
    SubtitlesLib.importSubtitlesAsRegionsDialog()
    SubtitlesLib.exportRegionsAsSRTDialog()  -- вызов диалогового экспорта
    SubtitlesLib.convertASStoSRT("C:\\Users\\Эрик\\Downloads\\Dr. Stoun 06qism.ass")
]]--


local SubtitleLib = {}
local r = reaper
SubtitleLib.simpleCleanMode = false
-------------------------------------------------------------
-- Преобразование времени SRT "HH:MM:SS,mmm" в секунды
local function parseTime(timeStr)
  local h, m, s, ms = timeStr:match("(%d+):(%d+):(%d+),(%d+)")
  if not (h and m and s and ms) then
    return nil, "Неверный формат времени: " .. timeStr
  end
  return tonumber(h) * 3600 + tonumber(m) * 60 + tonumber(s) + tonumber(ms) / 1000
end


local function parseASSTime(timeStr)
  local h, m, s, cs = timeStr:match("(%d+):(%d+):(%d+)[.,](%d+)")
  if not (h and m and s and cs) then
    return nil, "Неверный формат времени в ASS: " .. timeStr
  end
  local csValue = tonumber(cs)
  if #cs == 2 then
    csValue = csValue / 100
  elseif #cs == 3 then
    csValue = csValue / 1000
  else
    csValue = csValue / 1000
  end
  return tonumber(h) * 3600 + tonumber(m) * 60 + tonumber(s) + csValue
end
-- Добавить в начало файла после local SubtitleLib = {}
SubtitleLib.simpleCleanMode = false  -- Флаг для простой очистки

-- Заменить функцию cleanText на эту версию:
function cleanText(text)
  if not text then return text end

  -- Если включен простой режим - используем упрощенную очистку
  if SubtitleLib.simpleCleanMode then
    -- Сначала обрабатываем специфичные паттерны
    text = text:gsub("Рђ'%¦", "j")
    text = text:gsub("\\[Nn]", "  ")
    text = text:gsub("¦", ":")
    text = text:gsub("ђ", "j")
    text = text:gsub("…", "...")

    -- Заменяем все виды кавычек на обычную одинарную кавычку
    -- Обрабатываем все возможные варианты кавычек за один проход
    text = text:gsub("['']", "'")  -- левая и правая одинарные кавычки
    text = text:gsub("`", "'")     -- обратная кавычка
    text = text:gsub("ʻ", "'")     -- модификатор буквы повернутая запятая

    -- Заменяем множественные кавычки на одну
    text = text:gsub("'+", "'")

    -- Убираем символы-заменители
    text = text:gsub("�", "")

    return text
  end

  -- Оригинальная сложная очистка
  text = text:gsub("{\\[^}]+}", "")
  text = text:gsub("Рђ'%¦", "j")
  text = text:gsub("\\[Nn]", "  ")
  text = text:gsub("'", "'")
  text = text:gsub("'", "'")
  text = text:gsub("`", "'")
  text = text:gsub("[''`]+", "'")
  text = text:gsub("…", "...")
  text = text:gsub("ʻ", "'")
  text = text:gsub("¦", ":")
  text = text:gsub("ђ", "j")
  
  -- Удаляем символ замещения � (U+FFFD)
  text = text:gsub("�", "'")
  text = text:gsub("�", "")
  
  -- Более агрессивная очистка: оставляем только безопасные символы
  local cleaned = ""
  local i = 1
  while i <= #text do
    local byte = string.byte(text, i)
    
    if byte then
      -- ASCII printable characters (32-126)
      if byte >= 32 and byte <= 126 then
        cleaned = cleaned .. string.char(byte)
        i = i + 1
      -- Основные пробельные символы
      elseif byte == 9 or byte == 10 or byte == 13 then -- tab, LF, CR
        cleaned = cleaned .. string.char(byte)
        i = i + 1
      -- Latin-1 Supplement (160-255) - но осторожно
      elseif byte >= 160 and byte <= 255 then
        cleaned = cleaned .. string.char(byte)
        i = i + 1
      -- UTF-8 многобайтовые последовательности - пропускаем
      elseif byte >= 194 and byte <= 244 then
        -- Определяем длину UTF-8 последовательности
        local seqLen = 1
        if byte >= 194 and byte <= 223 then seqLen = 2
        elseif byte >= 224 and byte <= 239 then seqLen = 3
        elseif byte >= 240 and byte <= 244 then seqLen = 4
        end
        
        -- Проверяем, что у нас есть полная последовательность
        local validUTF8 = true
        if i + seqLen - 1 <= #text then
          for j = 1, seqLen - 1 do
            local nextByte = string.byte(text, i + j)
            if not nextByte or nextByte < 128 or nextByte > 191 then
              validUTF8 = false
              break
            end
          end
        else
          validUTF8 = false
        end
        
        if validUTF8 then
          local utf8char = text:sub(i, i + seqLen - 1)
          cleaned = cleaned .. " "
        end
        
        i = i + seqLen
      else
        -- Все остальные байты пропускаем
        i = i + 1
      end
    else
      break
    end
  end
  
  -- Очищаем множественные пробелы и пробелы в начале/конце
  cleaned = cleaned:gsub("%s+", " ")
  cleaned = cleaned:gsub("^%s+", "")
  cleaned = cleaned:gsub("%s+$", "")
  
  return cleaned
end
-------------------------------------------------------------
-- Форматирование времени для SRT "HH:MM:SS,mmm"
local function formatSRTTime(seconds)
  local hours = math.floor(seconds / 3600)
  local minutes = math.floor((seconds % 3600) / 60)
  local secs = math.floor(seconds % 60)
  local msecs = math.floor((seconds - math.floor(seconds)) * 1000)
  return string.format("%02d:%02d:%02d,%03d", hours, minutes, secs, msecs)
end
-------------------------------------------------------------
-- Парсинг SRT-файла.
local function parseSRTFile(filePath)
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
    local startSec, errStart = parseTime(startTime)
    local endSec, errEnd = parseTime(endTime)
    if startSec and endSec then
      text = text:gsub("\n", " "):gsub("^%s+", ""):gsub("%s+$", "")
      text = cleanText(text)
      table.insert(regions, {start = startSec, _end = endSec, text = text})
    else
      reaper.ShowConsoleMsg("Ошибка парсинга времени в блоке " .. id .. "\n")
    end
  end

  if #regions == 0 then
    local id, startTime, endTime, text = content:match("(%d+)%s*\n([0-9:,]+)%s*%-%->%s*([0-9:,]+)%s*\n(.*)$")
    if id then
      local startSec, errStart = parseTime(startTime)
      local endSec, errEnd = parseTime(endTime)
      if startSec and endSec then
        text = text:gsub("\n", " "):gsub("^%s+", ""):gsub("%s+$", "")
        text = cleanText(text)
        table.insert(regions, {start = startSec, _end = endSec, text = text})
      end
    end
  end
  
  return regions
end

-------------------------------------------------------------
-- Парсинг ASS-файла (из секции [Events])
local function parseASSFile(filePath)
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
      if dialogueLine then
        if not formatFields then
          return nil, "Не найден формат в секции [Events] файла ASS."
        end
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
          local startSec = parseASSTime(startTime)
          local endSec = parseASSTime(endTime)
          if startSec and endSec then
            text = cleanText(text)
            table.insert(regions, {start = startSec, _end = endSec, text = text})
          else
            reaper.ShowConsoleMsg("Ошибка парсинга времени в диалоге: " .. dialogueLine .. "\n")
          end
        end
      end
    end
    ::continueDialogue::
  end
  
  return regions
end
-------------------------------------------------------------
-- Добавление регионов в проект REAPER.
local function addRegionsToProject(regions)
  if not regions or #regions == 0 then
    reaper.ShowMessageBox("Нет регионов для добавления.", "Ошибка", 0)
    return false
  end
  reaper.Undo_BeginBlock()
  for _, region in ipairs(regions) do
    reaper.AddProjectMarker(0, true, region.start, region._end, region.text, -1)
  end
  reaper.UpdateArrange()
  reaper.Undo_EndBlock("Добавлены регионы из субтитров", -1)
  return true
end
-------------------------------------------------------------
-- Импорт субтитров (SRT или ASS) как регионов в проект.
function importSubtitlesAsRegions(filePath)
  if not filePath or filePath == "" then
    reaper.ShowMessageBox("Путь к файлу не задан.", "Ошибка", 0)
    return
  end
  
  local ext = filePath:match("%.([^%.]+)$")
  if ext then
    ext = ext:lower()
  else
    ext = "srt"
  end
  
  local regions, err
  if ext == "srt" then
    regions, err = parseSRTFile(filePath)
  elseif ext == "ass" then
    regions, err = parseASSFile(filePath)
  else
    reaper.ShowMessageBox("Не поддерживаемое расширение файла: " .. ext, "Ошибка", 0)
    return
  end
  
  if not regions then
    reaper.ShowMessageBox("Ошибка парсинга файла: " .. err, "Ошибка", 0)
    return
  end
  
  if #regions == 0 then
    reaper.ShowMessageBox("Не найдено регионов в файле.", "Ошибка", 0)
    return
  end
  
  local success = addRegionsToProject(regions)
  if success then
    -- reaper.ShowMessageBox("Добавлено регионов: " .. #regions, "Результат", 0)
  end
end

-------------------------------------------------------------
-- Экспорт регионов проекта в SRT-файл через диалог сохранения.
-- Если directory или name не заданы, берутся значения по умолчанию (папка и имя проекта).
function exportRegionsAsSRTDialog(directory, name)
  local totalMarkers = reaper.CountProjectMarkers(0)
  local regions = {}
  for i = 0, totalMarkers - 1 do
    local retval, isrgn, pos, rgnend, nameMarker, markrgnindexnumber = reaper.EnumProjectMarkers(i)
    if retval and isrgn then
      table.insert(regions, {start = pos, _end = rgnend, text = nameMarker})
    end
  end

  if #regions == 0 then
    reaper.ShowMessageBox("В проекте нет регионов для экспорта.", "Ошибка", 0)
    return
  end

  table.sort(regions, function(a, b) return a.start < b.start end)

  local srt_content = ""
  for i, region in ipairs(regions) do
    local start_time = formatSRTTime(region.start)
    local end_time = formatSRTTime(region._end)
    local text = region.text or ""
    srt_content = srt_content .. string.format("%d\n%s --> %s\n%s\n\n", i, start_time, end_time, text)
  end

  local proj, projfn = reaper.EnumProjects(-1)
  if projfn == "" then projfn = "untitled.rpp" end
  local defaultName = name or ((projfn:match("([^\\/:]+)%.rpp$") or projfn) .. ".srt")
  local initialFolder = directory or reaper.GetProjectPath(0, "")

  local extensionList = "SRT files\0.srt\0All files\0.*\0\0"
  local retval, fileName = reaper.JS_Dialog_BrowseForSaveFile("Экспорт SRT", initialFolder, defaultName, extensionList)
  if retval == 1 and fileName and fileName ~= "" then
    fileName = fileName:match("^%s*(.-)%s*$")  -- удаляем пробелы
    if not fileName:lower():match("%.srt$") then
      fileName = fileName .. ".srt"
    end
    local file, err = io.open(fileName, "w")
    if not file then
      reaper.ShowMessageBox("Ошибка создания файла SRT: " .. err, "Ошибка", 0)
      return
    end
    file:write(srt_content)
    file:close()
    reaper.ShowMessageBox("SRT экспортирован: " .. fileName, "Экспорт", 0)
  end
end

-------------------------------------------------------------
-- Конвертация ASS-файла в SRT.
function convertASStoSRT(assFilePath)
  if not assFilePath or assFilePath == "" then
    reaper.ShowMessageBox("Путь к ASS файлу не задан.", "Ошибка", 0)
    return
  end
  
  local regions, err = parseASSFile(assFilePath)
  if not regions then
    reaper.ShowMessageBox("Ошибка парсинга ASS файла: " .. err, "Ошибка", 0)
    return
  end
  if #regions == 0 then
    reaper.ShowMessageBox("Нет регионов в ASS файле.", "Ошибка", 0)
    return
  end
  
  table.sort(regions, function(a, b) return a.start < b.start end)
  
  local srt_content = ""
  for i, region in ipairs(regions) do
    local start_time = formatSRTTime(region.start)
    local end_time = formatSRTTime(region._end)
    local text = region.text or ""
    srt_content = srt_content .. string.format("%d\n%s --> %s\n%s\n\n", i, start_time, end_time, text)
  end
  
  local outFile = assFilePath:gsub("%.ass$", ".srt")
  local file, err = io.open(outFile, "w")
  if not file then
    reaper.ShowMessageBox("Ошибка создания файла SRT: " .. err, "Ошибка", 0)
    return
  end
  file:write(srt_content)
  file:close()
  
  reaper.ShowMessageBox("ASS конвертирован в SRT: " .. outFile, "Конвертация", 0)
end

-------------------------------------------------------------
-- Диалоговый импорт субтитров (SRT или ASS) через JS API.
function importSubtitlesAsRegionsDialog()
  local extensionList = "SRT и ASS файлы\0*.srt;*.ass\0Все файлы\0*.*\0\0"
  local retval, fileNames = reaper.JS_Dialog_BrowseForOpenFiles("Импорт субтитров", "", "", extensionList, false)
  if retval == 1 and fileNames and fileNames ~= "" then
    -- JS API возвращает \0-разделённую строку: первый элемент — путь к папке, второй — имя файла.
    local folder, file = fileNames:match("^(.-)\0(.-)\0")
    local fullPath = ""
    if folder and file and file ~= "" then
      local sep = (reaper.GetOS():find("Win")) and "\\" or "/"
      fullPath = folder .. sep .. file
    else
      fullPath = fileNames
    end

    reaper.Main_OnCommand(reaper.NamedCommandLookup("_SWSMARKERLIST10"), 0)

    importSubtitlesAsRegions(fullPath)
  end

  
end


SubtitleLib.parseASSFile = parseASSFile
SubtitleLib.parseSRTFile = parseSRTFile
SubtitleLib.formatSRTTime = formatSRTTime
-------------------------------------------------------------
-- Публичные функции библиотеки
SubtitleLib.importSubtitlesAsRegions        = importSubtitlesAsRegions
SubtitleLib.exportRegionsAsSRTDialog        = exportRegionsAsSRTDialog
SubtitleLib.convertASStoSRT                 = convertASStoSRT
SubtitleLib.importSubtitlesAsRegionsDialog  = importSubtitlesAsRegionsDialog


return SubtitleLib
