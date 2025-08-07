--@noindex
--NoIndex: true
local r = reaper
local script_path = debug.getinfo(1, "S").source:match("@(.*[\\/])")
local imgui_path = r.ImGui_GetBuiltinPath()..'/?.lua'
package.path = imgui_path..";"..script_path..'?.lua'


local im = require 'imgui' '0.9.2.3'
local SubtitleLib = require('mrtnz_srtass-parser')
local SessionManager = require('mrtnz_subtitle_session')
local SyncManager = require('mrtnz_subtitle_sync')
local UIManager = require('mrtnz_subtitle_ui')

local ctx, font, activeColumn, activeRow = nil, nil, 1, 1
local columns = {}
local maxColumns = 5
local previewCtx, previewFont = nil, nil
local showPreview = false
local isDirty = false

-- Оптимизация сохранений
local lastSaveTime = 0
local saveInterval = 2.0  -- Сохраняем не чаще раза в 2 секунды
local forceSave = false

-- Кеш для времени
local timeDisplayCache = {}
local lastTimeDisplayClear = 0

local dragColumn = nil
local columnInsertPos = nil
local columnOrder = {1, 2, 3, 4, 5}  -- Порядок колонок по умолчанию


function math.abs(x)
  return x < 0 and -x or x
end

local function getSyncModeFromExtState()
  local retval, value = r.GetExtState("SubtitleEditorPro", "SyncMode")
  if retval == 1 then
    return value == "1"
  else
    return true
  end
end

local syncMode = getSyncModeFromExtState()
local scrollToRow = nil
local lastCursorPos = -1
local lastPlayPos = -1
local manualClickTime = 0
local manualClickCooldown = 0.5

local lastRegionCheck = 0
local regionCheckInterval = 1.5  -- Увеличили интервал
local lastRegionState = {}

local columnWidths = {}
local lastFrameWidths = {}

local pendingChanges = {}
local lastFocusedInput = nil
local focusChangeTime = 0

-- Защита от race conditions
local operationInProgress = false
local operationQueue = {}

function SafeOperation(func, ...)
  if operationInProgress then
    table.insert(operationQueue, {func = func, args = {...}})
    return
  end
  
  operationInProgress = true
  func(...)
  operationInProgress = false
  
  -- Обработать очередь
  if #operationQueue > 0 then
    local op = table.remove(operationQueue, 1)
    SafeOperation(op.func, table.unpack(op.args))
  end
end


for i = 1, maxColumns do
  columns[i] = {
    subtitles = {},
    values = {},
    enabled = false,
    name = "Language " .. i,
    selected = {}
  }
end

local ctx = im.CreateContext('Subtitle Editor Pro 2')
local font = im.CreateFont('sans-serif', 14)
im.Attach(ctx, font)

function HandleColumnDragDrop(visibleEnabledCols)
  local mx, my = im.GetMousePos(ctx)
  
  -- Обновляем позицию вставки при перетаскивании
  if dragColumn then
    columnInsertPos = 1
    for i, colNum in ipairs(visibleEnabledCols) do
      if colNum ~= dragColumn then
        im.TableSetColumnIndex(ctx, i + 1)
        local colX = im.GetCursorScreenPos(ctx)
        local colWidth = columnWidths[colNum] or 200
        if mx > colX + colWidth / 2 then
          columnInsertPos = i + 1
        end
      end
    end
  end
  
  -- Завершаем перетаскивание
  if dragColumn and not im.IsMouseDragging(ctx, 0) then
    if columnInsertPos then
      -- Находим позицию dragColumn в глобальном порядке
      local dragPosInOrder = nil
      for i = 1, maxColumns do
        if columnOrder[i] == dragColumn then
          dragPosInOrder = i
          break
        end
      end
      
      -- Находим позицию insertPos в глобальном порядке
      local insertPosInOrder = nil
      if columnInsertPos <= #visibleEnabledCols then
        local targetCol = visibleEnabledCols[columnInsertPos]
        for i = 1, maxColumns do
          if columnOrder[i] == targetCol then
            insertPosInOrder = i
            break
          end
        end
      else
        -- Вставляем в конец видимых колонок
        local lastVisibleCol = visibleEnabledCols[#visibleEnabledCols]
        for i = 1, maxColumns do
          if columnOrder[i] == lastVisibleCol then
            insertPosInOrder = i + 1
            break
          end
        end
      end
      
      if dragPosInOrder and insertPosInOrder and dragPosInOrder ~= insertPosInOrder then
        -- Перемещаем в глобальном порядке
        local movedCol = table.remove(columnOrder, dragPosInOrder)
        local newPos = insertPosInOrder > dragPosInOrder and insertPosInOrder - 1 or insertPosInOrder
        table.insert(columnOrder, newPos, movedCol)
        
        isDirty = true
        forceSave = true  -- Принудительное сохранение порядка
      end
    end
    dragColumn = nil
    columnInsertPos = nil
  end
end

function LoadSubtitles(columnNumber)
  local extensionList = "SRT/ASS files\0*.srt;*.ass\0All\0*.*\0\0"
  local retval, fileNames = r.JS_Dialog_BrowseForOpenFiles("Load subtitles", "", "", extensionList, false)
  if retval == 1 and fileNames and fileNames ~= "" then
    local folder, file = fileNames:match("^(.-)\0(.-)\0")
    local fullPath = ""
    if folder and file and file ~= "" then
      local sep = (r.GetOS():find("Win")) and "\\" or "/"
      fullPath = folder .. sep .. file
    else
      fullPath = fileNames
    end

    local ext = fullPath:match("%.([^%.]+)$"):lower()
    local parsed_subtitles
    if ext == "srt" then
      parsed_subtitles = SubtitleLib.parseSRTFile(fullPath)
    elseif ext == "ass" then
      parsed_subtitles = SubtitleLib.parseASSFile(fullPath)
    else
      r.ShowMessageBox("Unsupported format: " .. ext, "Error", 0)
      return
    end
    
    if not parsed_subtitles or #parsed_subtitles == 0 then
      r.ShowMessageBox("No subtitles found", "Error", 0)
      return
    end
    
    table.sort(parsed_subtitles, function(a, b) return a.start < b.start end)
    
    -- ВРЕМЕННО отключаем синхронизацию во время импорта
    local originalSyncMode = syncMode
    syncMode = false
    
    -- Удаляем старые регионы этой колонки если она уже была загружена
    if columns[columnNumber].enabled then
      SyncManager.removeColumnRegions(columnNumber)
    end
    
    columns[columnNumber].subtitles = parsed_subtitles
    columns[columnNumber].values = {}
    for i, sub in ipairs(parsed_subtitles) do
      columns[columnNumber].values[i] = sub.text or ""
    end
    columns[columnNumber].enabled = true
    columns[columnNumber].filePath = fullPath
    
    if not columns[activeColumn].enabled then
      activeColumn = columnNumber
    end
    
    UIManager.clearCache()
    timeDisplayCache = {}
    isDirty = true
    forceSave = true
    
    -- Восстанавливаем синхронизацию
    syncMode = originalSyncMode
    
    -- КЛЮЧЕВОЕ ИЗМЕНЕНИЕ: Применяем регионы из ПЕРВОЙ колонки, а не текущей!
    local firstActiveCol = nil
    for i = 1, maxColumns do
      local colNum = columnOrder[i]
      if colNum and columns[colNum].enabled then
        firstActiveCol = colNum
        break
      end
    end
    
    if firstActiveCol then
      ApplyToRegions(firstActiveCol)  -- Применяем из первой колонки!
    end
    
    -- Принудительно обновляем состояние
    lastRegionState = SyncManager.getCurrentRegionState()
    
    r.ShowMessageBox("Loaded " .. #parsed_subtitles .. " subtitles", "Info", 0)
  end
end

function ExportSubtitles(columnNumber)
  local col = columns[columnNumber]
  if not col.enabled or #col.subtitles == 0 then
    r.ShowMessageBox("No subtitles to export", "Error", 0)
    return
  end
  
  for i, subtitle in ipairs(col.subtitles) do
    if col.values[i] then
      subtitle.text = col.values[i]
    end
  end
  
  local srt_content = ""
  for i, subtitle in ipairs(col.subtitles) do
    -- Используем кешированное форматирование времени
    local start_time = UIManager.formatSRTTime(subtitle.start)
    local end_time = UIManager.formatSRTTime(subtitle._end)
    local text = subtitle.text or ""
    srt_content = srt_content .. string.format("%d\n%s --> %s\n%s\n\n", i, start_time, end_time, text)
  end
  
  local proj, projfn = r.EnumProjects(-1)
  if projfn == "" then projfn = "untitled.rpp" end
  local defaultName = (projfn:match("([^\\/:]+)%.rpp$") or projfn) .. "_" .. col.name .. ".srt"
  local initialFolder = r.GetProjectPath(0, "")
  
  local extensionList = "SRT files\0.srt\0All files\0.*\0\0"
  local retval, fileName = r.JS_Dialog_BrowseForSaveFile("Export SRT", initialFolder, defaultName, extensionList)
  if retval == 1 and fileName and fileName ~= "" then
    fileName = fileName:match("^%s*(.-)%s*$")
    if not fileName:lower():match("%.srt$") then
      fileName = fileName .. ".srt"
    end
    local file = io.open(fileName, "w")
    if file then
      file:write(srt_content)
      file:close()
      r.ShowMessageBox("Exported: " .. fileName, "Success", 0)
    end
  end
end

function AddRowAfter(row)
  local firstActiveCol = nil
  for i = 1, maxColumns do
    local colNum = columnOrder[i]
    if colNum and columns[colNum].enabled then
      firstActiveCol = colNum
      break
    end
  end
  
  if not firstActiveCol then return end
  
  local currentSubtitle = columns[firstActiveCol].subtitles[row]
  local nextSubtitle = columns[firstActiveCol].subtitles[row + 1]
  
  if not currentSubtitle then return end
  
  local newStart, newEnd
  
  if nextSubtitle then
    local nextDuration = nextSubtitle._end - nextSubtitle.start
    
    -- Если следующий длинный (>3 сек) - съедаем справа
    if nextDuration > 3.0 then
      newStart = currentSubtitle._end
      newEnd = currentSubtitle._end + 1.0
      
      -- Сдвигаем следующий
      for colIdx = 1, maxColumns do
        local col = columns[colIdx]
        if col.enabled and col.subtitles[row + 1] then
          col.subtitles[row + 1].start = newEnd
        end
      end
    else
      -- Иначе съедаем слева из текущего
      newStart = currentSubtitle._end - 1.0
      newEnd = currentSubtitle._end
      
      -- Укорачиваем текущий
      for colIdx = 1, maxColumns do
        local col = columns[colIdx]
        if col.enabled and col.subtitles[row] then
          col.subtitles[row]._end = newStart
        end
      end
    end
  else
    -- Нет следующего субтитра, просто добавляем
    newStart = currentSubtitle._end
    newEnd = currentSubtitle._end + 1.0
  end
  
  -- Создаем новый субтитр во всех колонках
  for colIdx = 1, maxColumns do
    local col = columns[colIdx]
    if col.enabled then
      table.insert(col.subtitles, row + 1, {
        start = newStart,
        _end = newEnd,
        text = ""
      })
      table.insert(col.values, row + 1, "")
    end
  end
  
  -- ПОЛНАЯ ОЧИСТКА всех кешей
  UIManager.clearCache()
  timeDisplayCache = {}
  SyncManager.clearCache()
  -- Принудительная пересинхронизация
  lastRegionState = {}
  
  isDirty = true
  forceSave = true
  ApplyToRegions(firstActiveCol)
end

function GetFromRegions(columnNumber)
  local regions = SyncManager.getRegionsForColumn(columnNumber)
  if #regions == 0 then
    r.ShowMessageBox("No regions found", "Info", 0)
    return
  end
  
  -- Очищаем существующие данные
  columns[columnNumber].subtitles = {}
  columns[columnNumber].values = {}
  
  -- Импортируем из регионов
  for i, region in ipairs(regions) do
    columns[columnNumber].subtitles[i] = {
      start = region.start,
      _end = region._end,
      text = region.text
    }
    columns[columnNumber].values[i] = region.text
  end
  
  -- Синхронизируем остальные колонки по временным меткам
  for colIdx = 1, maxColumns do
    if colIdx ~= columnNumber and columns[colIdx].enabled then
      -- Подстраиваем под новые временные метки
      local newValues = {}
      for i, sub in ipairs(columns[columnNumber].subtitles) do
        -- Ищем ближайшее совпадение по времени
        local found = false
        for j, oldSub in ipairs(columns[colIdx].subtitles) do
          if math.abs(oldSub.start - sub.start) < 0.5 then
            newValues[i] = columns[colIdx].values[j] or ""
            found = true
            break
          end
        end
        if not found then
          newValues[i] = ""
        end
      end
      
      -- Обновляем структуру
      columns[colIdx].subtitles = {}
      columns[colIdx].values = newValues
      for i, sub in ipairs(columns[columnNumber].subtitles) do
        columns[colIdx].subtitles[i] = {
          start = sub.start,
          _end = sub._end,
          text = newValues[i]
        }
      end
    end
  end
  
  -- Полная очистка кешей
  UIManager.clearCache()
  timeDisplayCache = {}
  SyncManager.clearCache()
  isDirty = true
  forceSave = true
end

function AddEmptyColumn()
  -- Находим свободную колонку
  local emptyColIdx = nil
  for i = 1, maxColumns do
    if not columns[i].enabled then
      emptyColIdx = i
      break
    end
  end
  
  if not emptyColIdx then
    r.ShowMessageBox("Maximum columns reached", "Info", 0)
    return
  end
  
  -- Находим первую активную колонку для копирования тайминга
  local firstActiveCol = nil
  for i = 1, maxColumns do
    local colNum = columnOrder[i]
    if colNum and columns[colNum].enabled then
      firstActiveCol = colNum
      break
    end
  end
  
  if not firstActiveCol then
    r.ShowMessageBox("No reference column found", "Error", 0)
    return
  end
  
  -- Копируем структуру из первой колонки
  columns[emptyColIdx].subtitles = {}
  columns[emptyColIdx].values = {}
  
  for i, sub in ipairs(columns[firstActiveCol].subtitles) do
    local newSub = {
      start = sub.start,
      _end = sub._end,
      text = ""
    }
    table.insert(columns[emptyColIdx].subtitles, newSub)
    table.insert(columns[emptyColIdx].values, "")
  end
  
  columns[emptyColIdx].enabled = true
  columns[emptyColIdx].name = "New Language"
  
  UIManager.clearCache()
  timeDisplayCache = {}
  isDirty = true
  forceSave = true
  
  -- r.ShowMessageBox("Added empty column with " .. #columns[emptyColIdx].subtitles .. " rows", "Info", 0)
end

function ApplyToRegions(columnNumber)
  local col = columns[columnNumber]
      reaper.Main_OnCommand(reaper.NamedCommandLookup("_SWSMARKERLIST10"), 0)
  if not col.enabled or #col.subtitles == 0 then
    r.ShowMessageBox("No subtitles to apply", "Error", 0)
    return
  end
  
  for i, subtitle in ipairs(col.subtitles) do
    if col.values[i] then
      subtitle.text = col.values[i]
    end
  end
  
  SyncManager.applySubtitlesToRegions(col.subtitles, columnNumber)
  lastRegionState = SyncManager.getCurrentRegionState()
  
  if not syncMode then
    r.ShowMessageBox("Applied " .. #col.subtitles .. " regions", "Success", 0)
  end
end

function ApplySingleSubtitle(columnNumber, rowIndex)
  local col = columns[columnNumber]
  if not col.enabled or not col.subtitles[rowIndex] then return end
  
  local subtitle = col.subtitles[rowIndex]
  if col.values[rowIndex] then
    subtitle.text = col.values[rowIndex]
  end
  
  SyncManager.updateSingleRegion(columnNumber, rowIndex, subtitle)
end

function ScheduleSingleUpdate(columnNumber, rowIndex, newText)
  if not syncMode then return end
  
  local key = columnNumber .. "_" .. rowIndex
  local currentTime = r.time_precise()
  
  if pendingChanges[key] and pendingChanges[key].text == newText then
    return
  end
  
  pendingChanges[key] = {
    columnNumber = columnNumber,
    rowIndex = rowIndex,
    text = newText,
    time = currentTime + 1.5  -- Увеличили задержку
  }
end

function ProcessPendingChanges()
  if not syncMode then return end
  
  local currentTime = r.time_precise()
  local toProcess = {}
  
  for key, change in pairs(pendingChanges) do
    if currentTime >= change.time then
      table.insert(toProcess, change)
      pendingChanges[key] = nil
    end
  end
  
  for _, change in ipairs(toProcess) do
    ApplySingleSubtitle(change.columnNumber, change.rowIndex)
  end
end

function ProcessFocusLostUpdate()
  if not syncMode or not lastFocusedInput then return end
  
  local currentTime = r.time_precise()
  if currentTime - focusChangeTime < 0.5 then return end  -- Увеличили задержку
  
  local col, row = lastFocusedInput.col, lastFocusedInput.row
  local key = col .. "_" .. row
  
  if pendingChanges[key] then
    ApplySingleSubtitle(col, row)
    pendingChanges[key] = nil
  end
  
  lastFocusedInput = nil
end

function AddColumn()
  for i = 1, maxColumns do
    if not columns[i].enabled then
      LoadSubtitles(i)
      return
    end
  end
  r.ShowMessageBox("Maximum columns reached", "Info", 0)
end

function RemoveColumn(idx)
  if columns[idx].enabled then
    -- ВРЕМЕННО отключаем синхронизацию
    local originalSyncMode = syncMode
    syncMode = false
    
    -- Удаляем регионы ПЕРЕД очисткой данных
    SyncManager.removeColumnRegions(idx)
    
    columns[idx].subtitles = {}
    columns[idx].values = {}
    columns[idx].enabled = false
    columns[idx].selected = {}
    columns[idx].filePath = nil
    UIManager.clearCache()
    
    if activeColumn == idx then
      for i = 1, maxColumns do
        if columns[i].enabled then
          activeColumn = i
          break
        end
      end
    end
    
    isDirty = true
    forceSave = true
    
    -- Восстанавливаем синхронизацию
    syncMode = originalSyncMode
    
    -- Принудительно обновляем состояние
    lastRegionState = SyncManager.getCurrentRegionState()
  end
end

function MergeSelected()
  local activeCol = columns[activeColumn]
  if not activeCol.enabled or not activeCol.selected then return end
  
  local indices = {}
  for i, v in pairs(activeCol.selected) do
    if v then table.insert(indices, i) end
  end
  
  if #indices < 2 then return end
  
  table.sort(indices)
  local first = indices[1]
  local last = indices[#indices]
  
  for colIdx = 1, maxColumns do
    local col = columns[colIdx]
    if col.enabled and #col.subtitles > 0 then
      local validIndices = {}
      for _, i in ipairs(indices) do
        if i <= #col.subtitles then
          table.insert(validIndices, i)
        end
      end
      
      if #validIndices >= 2 then
        local mergedText = {}
        for _, i in ipairs(validIndices) do
          if col.values[i] and col.values[i] ~= "" then
            table.insert(mergedText, col.values[i])
          end
        end
        
        local validFirst = validIndices[1]
        local validLast = validIndices[#validIndices]
        
        col.subtitles[validFirst]._end = col.subtitles[validLast]._end
        col.values[validFirst] = table.concat(mergedText, " ")
        
        for i = #validIndices, 2, -1 do
          local idx = validIndices[i]
          table.remove(col.subtitles, idx)
          table.remove(col.values, idx)
        end
      end
    end
  end
  
  activeCol.selected = {}
  UIManager.clearCache()
  timeDisplayCache = {}
  isDirty = true
  forceSave = true
  ApplyToRegions(activeColumn)
end

function DeleteSelected()
  SafeOperation(function()
    local activeCol = columns[activeColumn]
    if not activeCol.enabled or not activeCol.selected then return end
    
    local indices = {}
    for i, v in pairs(activeCol.selected) do
      if v then table.insert(indices, i) end
    end
    
    if #indices == 0 then return end
    
    local result = r.ShowMessageBox("Delete " .. #indices .. " selected subtitle(s)?", "Confirm Delete", 4)
    if result ~= 6 then return end
    
    -- Добавить защиту от обработки во время массовых операций
    SyncManager.pauseSync()
    
    -- ВРЕМЕННО отключаем синхронизацию
    local originalSyncMode = syncMode
    syncMode = false
    
    table.sort(indices, function(a, b) return a > b end)
    
    -- Удаляем во ВСЕХ колонках
    for colIdx = 1, maxColumns do
      local col = columns[colIdx]
      if col.enabled then
        for _, idx in ipairs(indices) do
          if idx <= #col.subtitles then
            table.remove(col.subtitles, idx)
            table.remove(col.values, idx)
          end
        end
      end
    end
    
    activeCol.selected = {}
    -- ПОЛНАЯ ОЧИСТКА всех кешей
    UIManager.clearCache()
    timeDisplayCache = {}
    SyncManager.clearCache()
    isDirty = true
    forceSave = true
    
    -- Принудительная пересинхронизация
    lastRegionState = {}
    
    -- Применяем из первой колонки
    syncMode = originalSyncMode
    SyncManager.resumeSync()
    
    local firstActiveCol = nil
    for i = 1, maxColumns do
      local colNum = columnOrder[i]
      if colNum and columns[colNum].enabled then
        firstActiveCol = colNum
        break
      end
    end
    
    if firstActiveCol then
      ApplyToRegions(firstActiveCol)
    end
    
    lastRegionState = SyncManager.getCurrentRegionState()
  end)
end


function DeleteAllSubtitles()
  local activeCol = columns[activeColumn]
  if not activeCol.enabled or #activeCol.subtitles == 0 then return end
  
  -- Подтверждение удаления
  local result = r.ShowMessageBox("Delete ALL subtitles in active column?\nThis cannot be undone!", "Confirm Delete All", 4)
  if result ~= 6 then return end -- 6 = Yes
  
  RemoveColumn(activeColumn)
end

function DeleteSingleRow(row)
  SafeOperation(function()
    local activeCol = columns[activeColumn]
    if not activeCol.enabled or row > #activeCol.subtitles then return end
    
    -- Подтверждение удаления
    local result = r.ShowMessageBox("Delete subtitle #" .. row .. "?", "Confirm Delete", 4)
    if result ~= 6 then return end -- 6 = Yes
    
    -- Добавить защиту от обработки во время массовых операций
    SyncManager.pauseSync()
    
    -- ВРЕМЕННО отключаем синхронизацию
    local originalSyncMode = syncMode
    syncMode = false
    
    -- ВАЖНО: Удаляем строку во ВСЕХ колонках чтобы избежать рассинхронизации
    for colIdx = 1, maxColumns do
      local col = columns[colIdx]
      if col.enabled and row <= #col.subtitles then
        table.remove(col.subtitles, row)
        table.remove(col.values, row)
      end
    end
    
    activeCol.selected = {}
    -- ПОЛНАЯ ОЧИСТКА всех кешей
    UIManager.clearCache()
    timeDisplayCache = {}
    SyncManager.clearCache()
    isDirty = true
    forceSave = true
    
    -- Принудительная пересинхронизация
    lastRegionState = {}
    
    -- Восстанавливаем синхронизацию и применяем из ПЕРВОЙ колонки
    syncMode = originalSyncMode
    SyncManager.resumeSync()
    
    local firstActiveCol = nil
    for i = 1, maxColumns do
      local colNum = columnOrder[i]
      if colNum and columns[colNum].enabled then
        firstActiveCol = colNum
        break
      end
    end
    
    if firstActiveCol then
      ApplyToRegions(firstActiveCol)  -- Всегда из первой колонки!
    end
    
    lastRegionState = SyncManager.getCurrentRegionState()
  end)
end

function MergeWithNext(row)
  local activeCol = columns[activeColumn]
  if not activeCol.enabled or row >= #activeCol.subtitles then return end
  
  for colIdx = 1, maxColumns do
    local col = columns[colIdx]
    if col.enabled and row < #col.subtitles then
      -- Объединяем текст
      local currentText = col.values[row] or ""
      local nextText = col.values[row + 1] or ""
      local mergedText = currentText
      if nextText ~= "" then
        mergedText = mergedText == "" and nextText or currentText .. " " .. nextText
      end
      
      -- Обновляем время окончания
      col.subtitles[row]._end = col.subtitles[row + 1]._end
      col.values[row] = mergedText
      
      -- Удаляем следующую строку
      table.remove(col.subtitles, row + 1)
      table.remove(col.values, row + 1)
    end
  end
  
  activeCol.selected = {}
  UIManager.clearCache()
  timeDisplayCache = {}
  isDirty = true
  forceSave = true
  ApplyToRegions(activeColumn)
end

function SplitAtCursor()
  local col = columns[activeColumn]
  if not col.enabled or activeRow > #col.subtitles then return end
  
  local sub = col.subtitles[activeRow]
  local cursorPos = r.GetCursorPosition()
  
  if cursorPos <= sub.start or cursorPos >= sub._end then return end
  
  for colIdx = 1, maxColumns do
    local column = columns[colIdx]
    if column.enabled and activeRow <= #column.subtitles then
      local currentSub = column.subtitles[activeRow]
      
      local newSub = {
        start = cursorPos,
        _end = currentSub._end,
        text = column.values[activeRow] or ""
      }
      
      currentSub._end = cursorPos
      
      table.insert(column.subtitles, activeRow + 1, newSub)
      table.insert(column.values, activeRow + 1, newSub.text)
    end
  end
  
  UIManager.clearCache()
  timeDisplayCache = {}
  isDirty = true
  forceSave = true
  ApplyToRegions(activeColumn)
end

function FindSubtitleAtTimeWithPriority(subtitles, time)
  if not subtitles or #subtitles == 0 then return 1 end
  
  -- Кеширование для частых запросов
  local timeKey = string.format("%.2f", time)
  if timeDisplayCache[timeKey] then
    return timeDisplayCache[timeKey]
  end
  
  local result = 1
  
  for i, sub in ipairs(subtitles) do
    if math.abs(sub.start - time) < 0.001 then
      result = i
      timeDisplayCache[timeKey] = result
      return result
    end
  end
  
  for i, sub in ipairs(subtitles) do
    if time >= sub.start and time <= sub._end then
      result = i
      timeDisplayCache[timeKey] = result
      return result
    end
  end
  
  for i = #subtitles, 1, -1 do
    if time >= subtitles[i]._end then
      result = math.min(i + 1, #subtitles)
      timeDisplayCache[timeKey] = result
      return result
    end
  end
  
  timeDisplayCache[timeKey] = result
  return result
end

function CheckTimelineSync()
  -- ВСЕГДА берем время из ПЕРВОЙ активной колонки
  local firstActiveCol = nil
  for i = 1, maxColumns do
    if columns[i].enabled and not columns[i].deactivated then
      firstActiveCol = i
      break
    end
  end
  
  if not syncMode or not firstActiveCol then return end
  
  local currentTime = r.time_precise()
  
  if currentTime - manualClickTime < manualClickCooldown then return end
  
  -- Проверяем есть ли выделенные строки
  local activeCol = columns[activeColumn]
  local hasSelected = false
  if activeCol.selected then
    for i, v in pairs(activeCol.selected) do
      if v then 
        hasSelected = true
        break 
      end
    end
  end
  
  if hasSelected then return end
  
  local playState = r.GetPlayState()
  local pos
  
  if playState ~= 0 then
    pos = r.GetPlayPosition()
    if math.abs(pos - lastPlayPos) > 0.1 then
      lastPlayPos = pos
      local newRow = FindSubtitleAtTimeWithPriority(columns[firstActiveCol].subtitles, pos)
      if newRow ~= activeRow then
        activeRow = newRow
        scrollToRow = activeRow
      end
    end
  else
    pos = r.GetCursorPosition()
    if math.abs(pos - lastCursorPos) > 0.1 then
      lastCursorPos = pos
      local newRow = FindSubtitleAtTimeWithPriority(columns[firstActiveCol].subtitles, pos)
      if newRow ~= activeRow then
        activeRow = newRow
        scrollToRow = activeRow
      end
    end
  end
end

function CheckRegionChanges()
  if not syncMode then return end
  
  local currentTime = r.time_precise()
  if currentTime - lastRegionCheck < regionCheckInterval then return end
  lastRegionCheck = currentTime
  
  -- ЗАЩИТА: не синхронизируем если идет массовое обновление
  if forceSave then return end
  
  local hasChanges, newState = SyncManager.performOptimizedRegionSync(columns, lastRegionState)
  if hasChanges then
    lastRegionState = newState
    UIManager.clearCache()
    timeDisplayCache = {}
    isDirty = true
  end
end

function SetCursorToSubtitle(row)
  -- Берем первую колонку по текущему порядку columnOrder
  local firstActiveCol = nil
  for i = 1, maxColumns do
    local colNum = columnOrder[i]
    if colNum and columns[colNum].enabled then
      firstActiveCol = colNum
      break
    end
  end
  
  if firstActiveCol and row <= #columns[firstActiveCol].subtitles then
    local sub = columns[firstActiveCol].subtitles[row]
    r.SetEditCurPos(sub.start, true, false)
  end
end

local previewFont = im.CreateFont('sans-serif', 20)
im.Attach(ctx, previewFont)

function ShowPreviewWindow()
  if not previewCtx then
    previewCtx = ctx --im.CreateContext('Active Subtitle Preview')
    
  end
  
  local visible, open = im.Begin(previewCtx, 'Active Subtitle', true, im.WindowFlags_NoCollapse)
  if visible then
    im.PushFont(previewCtx, previewFont)
    local col = columns[activeColumn]
    if col.enabled and activeRow <= #col.values then
      local text = col.values[activeRow] or ""
      local w = im.GetContentRegionAvail(previewCtx)
      local wrapped = UIManager.wrapText(previewCtx, text, w, "preview_"..activeRow)
      im.TextWrapped(previewCtx, wrapped)
    else
      im.Text(previewCtx, "No active subtitle")
    end
    im.PopFont(previewCtx)
    im.End(previewCtx)
  end
  
  showPreview = open
  
  if not open and previewCtx then
    -- im.DestroyContext(previewCtx)
    -- previewCtx = nil
    --previewFont = nil
  end
end

function DrawColumnHeader(col, idx)
  local isActive = (activeColumn == idx)
  
  im.PushStyleVar(ctx, im.StyleVar_ButtonTextAlign, 0.5, 0.5)
  im.PushStyleVar(ctx, im.StyleVar_FramePadding, 4, 2)
  
  if isActive then
    im.PushStyleColor(ctx, im.Col_Button, 0x7878D7FF)
    im.PushStyleColor(ctx, im.Col_ButtonHovered, 0x8888E7FF)
    im.PushStyleColor(ctx, im.Col_ButtonActive, 0x9898F7FF)
  end
  
-- Проверяем состояние колонки (активна/деактивирована)
local isEnabled = columns[idx].enabled and not columns[idx].deactivated
if not isEnabled then
  im.PushStyleColor(ctx, im.Col_Button, 0x404040FF)
  im.PushStyleColor(ctx, im.Col_ButtonHovered, 0x505050FF)
  im.PushStyleColor(ctx, im.Col_ButtonActive, 0x505050FF)
  im.PushStyleColor(ctx, im.Col_Text, 0xDDDDDDFF)  -- Светло-серый вместо темно-серого
end
  
  if im.Button(ctx, col.name .. "##col"..idx, -1, 24) then
    if isEnabled then
      activeColumn = idx
    end
  end
  
  if isEnabled then
    if im.IsItemHovered(ctx) and im.IsMouseDoubleClicked(ctx, 0) then
    
      ApplyToRegions(idx)
    end
    
    if im.IsItemHovered(ctx) then
      im.SetTooltip(ctx, "Right-click for menu\nDouble-click to apply to regions")
    end
    
    -- Поддержка перетаскивания только для активных колонок
    if im.BeginDragDropSource(ctx, im.DragDropFlags_None) then
      if not dragColumn then dragColumn = idx end
      im.SetDragDropPayload(ctx, "COLUMN", tostring(idx))
      im.Text(ctx, "Moving: " .. col.name)
      im.EndDragDropSource(ctx)
    end
  end
  
  if not isEnabled then
    im.PopStyleColor(ctx, 4)
  end
  
  if isActive then
    im.PopStyleColor(ctx, 3)
  end
  
  im.PopStyleVar(ctx, 2)
  
  if im.BeginPopupContextItem(ctx, "colmenu"..idx) then
    -- Поле переименования
    local changed, newName = im.InputText(ctx, "Name##rename"..idx, col.name)
    if changed then 
      columns[idx].name = newName
      isDirty = true
    end
    
    im.Separator(ctx)
    
    if im.Button(ctx, "Load", -1) then LoadSubtitles(idx) end
    if im.Button(ctx, "Export", -1) then ExportSubtitles(idx) end
    if im.Button(ctx, "Apply to Regions", -1) then ApplyToRegions(idx) end
    if im.Button(ctx, "Get from Regions", -1) then 
      GetFromRegions(idx) 
      im.CloseCurrentPopup(ctx)
    end
    
    im.Separator(ctx)
    
    -- Деактивация/активация
    local deactivated = columns[idx].deactivated or false
    local clicked, newDeactivated = im.Checkbox(ctx, "Deactivate", deactivated)
    if clicked then
      columns[idx].deactivated = newDeactivated
      isDirty = true
      forceSave = true  -- Принудительное сохранение состояния
    end
    
    im.Separator(ctx)
    if im.Button(ctx, "Clear", -1) then RemoveColumn(idx) end
    
    im.EndPopup(ctx)
  end
end

function UpdateColumnWidths(enabledCols)
  for idx, colNum in ipairs(enabledCols) do
    im.TableSetColumnIndex(ctx, idx + 1)
    local width = im.GetContentRegionAvail(ctx)
    if width > 0 then
      columnWidths[colNum] = width
      if lastFrameWidths[colNum] and math.abs(lastFrameWidths[colNum] - width) > 20 then
        UIManager.clearCacheForColumn(colNum)
      end
      lastFrameWidths[colNum] = width
    end
  end
end

function HandleRowSelection(row)
  local activeCol = columns[activeColumn]
  if not activeCol.enabled then return end
  
  activeCol.selected = activeCol.selected or {}
  local isCurrentlySelected = activeCol.selected[row]
  
  if isCurrentlySelected then
    activeCol.selected[row] = nil
    
    local hasSelected = false
    for i, v in pairs(activeCol.selected) do
      if v then 
        hasSelected = true
        break 
      end
    end
    
    if not hasSelected and activeCol.subtitles[row] then
      r.SetEditCurPos(activeCol.subtitles[row].start, true, false)
    elseif hasSelected then
      SetCursorToFirstSelected()
    end
    
    return
  end
  
  local selectedRows = {}
  for i, v in pairs(activeCol.selected) do
    if v then table.insert(selectedRows, i) end
  end
  
  if #selectedRows == 0 then
    activeCol.selected[row] = true
  else
    table.sort(selectedRows)
    local minSelected = selectedRows[1]
    local maxSelected = selectedRows[#selectedRows]
    
    if row == minSelected - 1 or row == maxSelected + 1 then
      activeCol.selected[row] = true
    else
      activeCol.selected = {}
      activeCol.selected[row] = true
    end
  end
  
  SetTimeSelectionBasedOnSelection()
  SetCursorToFirstSelected()
end

function SetCursorToFirstSelected()
  local activeCol = columns[activeColumn]
  if not activeCol.enabled then return end
  
  local selectedRows = {}
  for i, v in pairs(activeCol.selected or {}) do
    if v then table.insert(selectedRows, i) end
  end
  
  if #selectedRows == 0 then return end
  
  table.sort(selectedRows)
  local firstRow = selectedRows[1]
  
  if activeCol.subtitles[firstRow] then
    r.SetEditCurPos(activeCol.subtitles[firstRow].start, true, false)
  end
end

function SetTimeSelectionBasedOnSelection()
  local activeCol = columns[activeColumn]
  if not activeCol.enabled then return end
  
  local selectedRows = {}
  for i, v in pairs(activeCol.selected or {}) do
    if v then table.insert(selectedRows, i) end
  end
  
  if #selectedRows == 0 then return end
  
  table.sort(selectedRows)
  local firstRow = selectedRows[1]
  local lastRow = selectedRows[#selectedRows]
  
  if not activeCol.subtitles[firstRow] or not activeCol.subtitles[lastRow] then
    return
  end
  
  local startTime = activeCol.subtitles[firstRow].start
  local endTime = activeCol.subtitles[lastRow]._end
  
  r.GetSet_LoopTimeRange2(0, true, false, startTime, endTime, false)
  r.UpdateTimeline()
end

function HandleRowClick(row, colNum)
  local currentTime = r.time_precise()
  
  manualClickTime = currentTime
  
  activeColumn = colNum
  activeRow = row
  
  local activeCol = columns[activeColumn]
  if activeCol.enabled then
    activeCol.selected = {}
  end
  
  SetCursorToSubtitle(row)
end

function HandleInputFocus(colNum, row, isFocused)
  local currentTime = r.time_precise()
  
  if not isFocused and lastFocusedInput and 
     lastFocusedInput.col == colNum and lastFocusedInput.row == row then
    focusChangeTime = currentTime
    ProcessFocusLostUpdate()
  elseif isFocused then
    lastFocusedInput = {col = colNum, row = row}
  end
end

-- Кешированное отображение времени
function GetCachedTimeDisplay(startTime, endTime)
  local key = string.format("%.3f_%.3f", startTime, endTime)
  
  if timeDisplayCache[key] then
    return timeDisplayCache[key]
  end
  
  local timeText = UIManager.formatSRTTime(startTime) .. "\n" .. UIManager.formatSRTTime(endTime)
  timeDisplayCache[key] = timeText
  
  -- Очистка кеша раз в минуту
  local currentTime = r.time_precise()
  if currentTime - lastTimeDisplayClear > 60 then
    local count = 0
    for k in pairs(timeDisplayCache) do
      count = count + 1
      if count % 3 == 0 then
        timeDisplayCache[k] = nil
      end
    end
    lastTimeDisplayClear = currentTime
  end
  
  return timeText
end


-- Переменные для поиска
local search_window = false
local searchText = ""
local replaceText = ""
local searchResults = {}
local currentSearchIndex = 1
local editText = ""
local displayColumn = 1
local searchCtx, searchFont = nil, nil
-- Добавить эти переменные в начало основного файла после других переменных поиска
local lastActiveRowForSearch = nil
local lastActiveColumnForSearch = nil
local shouldFocusEditField = false
local wrappedEditTextCache = "" -- Кэш для обернутого текста

-- Функция для обновления результатов поиска (добавить перед DrawSearchWindow)
function UpdateSearchResults()
  searchResults = {}
  if searchText ~= "" and columns[activeColumn].enabled then
    for i, value in ipairs(columns[activeColumn].values) do
      if value and value:lower():find(searchText:lower()) then
        table.insert(searchResults, i)
      end
    end
  end
  -- Обновляем текущий индекс если он вышел за границы
  if #searchResults == 0 then
    currentSearchIndex = 1
  elseif currentSearchIndex > #searchResults then
    currentSearchIndex = #searchResults
  end
end

-- Функция принудительного скролла к строке (добавить перед DrawSearchWindow)  
function ForceScrollToRow(targetRow)
  activeRow = targetRow
  scrollToRow = activeRow
  manualClickTime = r.time_precise()
  
  -- Дополнительно устанавливаем курсор для принудительного обновления
  if columns[activeColumn].enabled and targetRow <= #columns[activeColumn].subtitles then
    local sub = columns[activeColumn].subtitles[targetRow]
    r.SetEditCurPos(sub.start, true, false)
  end
end

function DrawSearchWindow()
  if not search_window then return end
  
  if not searchCtx then
    searchCtx = ctx
  end
  
  im.SetNextWindowSize(searchCtx, 600, 450, im.Cond_FirstUseEver)
  local visible, open = im.Begin(searchCtx, 'Search & Replace', true)
  if visible then
    
    -- Проверяем изменение активной строки/колонки и обновляем поле ввода
    if lastActiveRowForSearch ~= activeRow or lastActiveColumnForSearch ~= activeColumn then
      if columns[activeColumn].enabled and activeRow <= #columns[activeColumn].values then
        editText = columns[activeColumn].values[activeRow] or ""
        wrappedEditTextCache = "" -- Сбрасываем кэш при смене строки
        shouldFocusEditField = true -- Запланировать фокус и выделение
      end
      lastActiveRowForSearch = activeRow
      lastActiveColumnForSearch = activeColumn
    end
    
    -- ПОИСК (заголовок слева от поля)
    im.Text(searchCtx, "Search:")
    im.SameLine(searchCtx)
    im.SetNextItemWidth(searchCtx, -120)
    local searchChanged, newSearch = im.InputText(searchCtx, '##search', searchText)
    if searchChanged then
      searchText = newSearch
      UpdateSearchResults()
      currentSearchIndex = 1
    end
    
    -- Навигация с компактным счетчиком
    im.SameLine(searchCtx)
    if im.Button(searchCtx, "<") and #searchResults > 0 then
      currentSearchIndex = currentSearchIndex > 1 and currentSearchIndex - 1 or #searchResults
      ForceScrollToRow(searchResults[currentSearchIndex])
      shouldFocusEditField = true
    end
    im.SameLine(searchCtx)
    if im.Button(searchCtx, ">") and #searchResults > 0 then
      currentSearchIndex = currentSearchIndex < #searchResults and currentSearchIndex + 1 or 1
      ForceScrollToRow(searchResults[currentSearchIndex])
      shouldFocusEditField = true
    end
    
    -- Компактный счетчик справа от кнопок
    im.SameLine(searchCtx)
    local countText = #searchResults > 0 and 
      string.format("%d/%d #%d", currentSearchIndex, #searchResults, activeRow) or "0/0"
    im.Text(searchCtx, countText)
    
    -- ЗАМЕНА (заголовок слева от поля)
    im.Text(searchCtx, "Replace:")
    im.SameLine(searchCtx)
    im.SetNextItemWidth(searchCtx, -120)
    local replaceChanged, newReplace = im.InputText(searchCtx, '##replace', replaceText)
    if replaceChanged then replaceText = newReplace end
    
    im.SameLine(searchCtx)
    if im.Button(searchCtx, "Replace") and #searchResults > 0 and activeRow <= #columns[activeColumn].values then
      local oldText = columns[activeColumn].values[activeRow] or ""
      local newText = oldText:gsub(searchText, replaceText)
      columns[activeColumn].values[activeRow] = newText
      editText = newText -- Обновляем поле ввода
      ScheduleSingleUpdate(activeColumn, activeRow, newText)
      isDirty = true
      
      -- Обновляем результаты поиска после замены
      UpdateSearchResults()
      
      -- Принудительный скролл к замененной строке
      ForceScrollToRow(activeRow)
      shouldFocusEditField = true
    end
    
    im.SameLine(searchCtx)
    if im.Button(searchCtx, "All") and searchText ~= "" and columns[activeColumn].enabled then
      for _, rowIdx in ipairs(searchResults) do
        local oldText = columns[activeColumn].values[rowIdx] or ""
        local newText = oldText:gsub(searchText, replaceText)
        columns[activeColumn].values[rowIdx] = newText
        ScheduleSingleUpdate(activeColumn, rowIdx, newText)
      end
      isDirty = true
      
      -- Обновляем editText если текущая строка была заменена
      if columns[activeColumn].enabled and activeRow <= #columns[activeColumn].values then
        editText = columns[activeColumn].values[activeRow] or ""
      end
      
      -- Обновляем результаты поиска после замены всех
      UpdateSearchResults()
      shouldFocusEditField = true
    end
    
    im.Separator(searchCtx)
    
    -- Кнопки переключения колонок для отображения
    for i = 1, maxColumns do
      if columns[i].enabled then
        if i > 1 then im.SameLine(searchCtx) end
        local isSelected = (displayColumn == i)
        if isSelected then im.PushStyleColor(searchCtx, im.Col_Button, 0x7878D7FF) end
        
        if im.Button(searchCtx, columns[i].name .. "##view" .. i) then
          displayColumn = i
        end
        
        if isSelected then im.PopStyleColor(searchCtx) end
      end
    end
    
    -- Функция переноса текста
    local function wrapText(text, maxWidth)
      if not text or text == "" then return text end
      if text:find("\n") then return text end
      local wrappedText, currentLine = "", ""
      for word in text:gmatch("%S+") do
        if currentLine == "" then 
          currentLine = word 
        else
          local potentialLineWidth = im.CalcTextSize(searchCtx, currentLine.." "..word)
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
      return wrappedText
    end
    
    local availX = im.GetContentRegionAvail(searchCtx)
    local halfWidth = (availX - 10) / 2
    
    -- ГОРИЗОНТАЛЬНОЕ РАСПОЛОЖЕНИЕ: слева текст, справа поле ввода
    
    -- Левая часть - отображение текущей строки
    if im.BeginChild(searchCtx, "##leftpane", halfWidth, -50, 0) then
      local currentText = ""
      if columns[displayColumn].enabled and activeRow <= #columns[displayColumn].values then
        currentText = columns[displayColumn].values[activeRow] or ""
      end
      
      im.Text(searchCtx, string.format("Row %d:", activeRow))
      local wrappedCurrent = wrapText(currentText, halfWidth - 15)
      im.TextWrapped(searchCtx, wrappedCurrent)
      im.EndChild(searchCtx)
    end
    
    -- Правая часть - поле ввода
    im.SameLine(searchCtx)
    local ctrlEnterPressed = false -- Объявляем переменную заранее
    if im.BeginChild(searchCtx, "##rightpane", halfWidth, -50, 0) then
      
      -- Заполняем поле ввода содержимым текущей строки если оно пустое
      if editText == "" and columns[activeColumn].enabled and activeRow <= #columns[activeColumn].values then
        editText = columns[activeColumn].values[activeRow] or ""
      end
      
      -- Функция переноса для поля ввода
      local function wrapTextForInput(text, maxWidth)
        if not text or text == "" then return text end
        if text:find("\n") then return text end
        local wrappedText, currentLine = "", ""
        for word in text:gmatch("%S+") do
          if currentLine == "" then 
            currentLine = word 
          else
            local potentialLineWidth = im.CalcTextSize(searchCtx, currentLine.." "..word)
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
        return wrappedText
      end
      
      -- Подготавливаем текст с переносами
      local inputWidth = halfWidth - 20
      
      -- Обновляем кэш обернутого текста когда editText изменился
      local currentWrapped = wrapTextForInput(editText, inputWidth)
      if wrappedEditTextCache == "" or editText ~= wrappedEditTextCache:gsub("\n", " ") then
        wrappedEditTextCache = currentWrapped
      end
      
      -- Вычисляем динамическую высоту
      local lineCount = 1
      for _ in wrappedEditTextCache:gmatch("\n") do 
        lineCount = lineCount + 1 
      end
      local dynamicHeight = math.max(60, lineCount * im.GetTextLineHeight(searchCtx) + 20)
      
      -- Используем флаг AutoSelectAll для автоматического выделения при фокусе
      local inputFlags = im.InputTextFlags_NoHorizontalScroll
      if shouldFocusEditField then
        inputFlags = inputFlags + im.InputTextFlags_AutoSelectAll
      end
      
      local editChanged, newEdit = im.InputTextMultiline(searchCtx, '##edit', wrappedEditTextCache, -1, dynamicHeight, inputFlags)
      if editChanged then 
        -- Убираем переносы строк при изменении и сохраняем в editText
        local cleanText = newEdit:gsub("\n", " ")
        editText = cleanText
        
        -- Сразу обновляем кэш с новым переносом
        wrappedEditTextCache = wrapTextForInput(cleanText, inputWidth)
      end
      
      -- Устанавливаем фокус если запланировано
      if shouldFocusEditField then
        im.SetKeyboardFocusHere(searchCtx, -1)
        shouldFocusEditField = false
      end
      
      -- Проверка Ctrl+Enter (после создания поля)
      if  im.IsKeyPressed(searchCtx, im.Key_Enter) and im.IsKeyDown(searchCtx, im.Key_LeftCtrl) then
        ctrlEnterPressed = true
        shouldFocusEditField = true -- Планируем перефокус с выделением после применения
      end
      
      im.EndChild(searchCtx)
    end
    
    -- Кнопки управления под полями
    if im.Button(searchCtx, "<< Prev") then
      if activeRow > 1 then
        ForceScrollToRow(activeRow - 1)
        shouldFocusEditField = true
      end
    end
    
    im.SameLine(searchCtx)
    local applyClicked = im.Button(searchCtx, "Apply (Ctrl+Enter)")
    
    im.SameLine(searchCtx)
    if im.Button(searchCtx, "Next >>") then
      if columns[activeColumn].enabled and activeRow < #columns[activeColumn].values then
        ForceScrollToRow(activeRow + 1)
        shouldFocusEditField = true
      end
    end
    
    -- Применение изменений
    local applyEdit = applyClicked or ctrlEnterPressed
    
    if applyEdit and columns[activeColumn].enabled and activeRow <= #columns[activeColumn].values then
      columns[activeColumn].values[activeRow] = editText
      ScheduleSingleUpdate(activeColumn, activeRow, editText)
      isDirty = true
      
      -- Обновляем результаты поиска если изменили текст с поисковым запросом
      if searchText ~= "" then
        UpdateSearchResults()
      end
      
      -- Переход к следующей строке
      if activeRow < #columns[activeColumn].values then
        ForceScrollToRow(activeRow + 1)
        shouldFocusEditField = true
      else
        shouldFocusEditField = true -- Остаемся на текущей строке но перефокусируемся с выделением
      end
    end
    
    -- Устанавливаем фокус на поле ввода при первом открытии окна
    if im.IsWindowAppearing(searchCtx) then
      shouldFocusEditField = true
    end
    
    im.End(searchCtx)
  end
  
  search_window = open
  
  if not open then
    searchFont = nil
    lastActiveRowForSearch = nil
    lastActiveColumnForSearch = nil
    shouldFocusEditField = false
    wrappedEditTextCache = "" -- Сбрасываем кэш при закрытии
  end
end
function DrawInputWithSideBorders(ctx, id, text, isActive, width, height, isActiveColumn)
  local cursorPos = {im.GetCursorScreenPos(ctx)}
  local changed, newVal, actualHeight
  
  -- Рисуем обычный input
  if isActive then
    changed, newVal, actualHeight = UIManager.drawTextInput(ctx, 
      string.match(id, "(%d+)"), string.match(id, "_(%d+)"), 
      text, isActive, width, height)
  else
    -- Для неактивных используем обычную функцию
    changed, newVal, actualHeight = UIManager.drawTextInput(ctx, 
      string.match(id, "(%d+)"), string.match(id, "_(%d+)"), 
      text, isActive, width, height)
  end
  
  -- Если это активная колонка - рисуем боковые границы
  if isActiveColumn then
    local drawList = im.GetWindowDrawList(ctx)
    local borderColor = 0x7878D7FF  -- Синий цвет как у заголовка
    local borderThickness = 2.0
    
    local x1, y1 = cursorPos[1], cursorPos[2] 
    local x2, y2 = x1 + width, y1 + (actualHeight or height)
    
    -- Левая вертикальная линия
    im.DrawList_AddLine(drawList, x1, y1, x1, y2, borderColor, borderThickness)
    
    -- Правая вертикальная линия  
    im.DrawList_AddLine(drawList, x2, y1, x2, y2, borderColor, borderThickness)
  end
  
  return changed, newVal, actualHeight
end

function Main()
  im.PushFont(ctx, font)
  
  local BUFFER_ROWS = 12  -- Дополнительные строки для плавности
  local AVERAGE_ROW_HEIGHT = 40  -- Приблизительная высота строки
  
  local availX, availY = im.GetContentRegionAvail(ctx)
  
  -- Sync Mode checkbox
  local changed, newSync = im.Checkbox(ctx, "Sync Mode", syncMode)
  if changed then 
    syncMode = newSync
    r.SetExtState("SubtitleEditorPro", "SyncMode", syncMode and "1" or "0", true)
    
    if not syncMode then
      pendingChanges = {}
    elseif syncMode then
      lastRegionState = SyncManager.getCurrentRegionState()
    end
  end


  if im.IsWindowFocused(ctx) and im.IsKeyPressed(ctx, im.Key_F) and im.IsKeyDown(ctx, im.Key_LeftCtrl) then
    search_window = not search_window
    if search_window then
      searchText = ""
      searchResults = {}
      currentSearchIndex = 1
    end
  end
  
  -- Control buttons
  im.SameLine(ctx)
  im.Dummy(ctx, 50, 0)
  im.SameLine(ctx)
  
  if im.Button(ctx, "Add Column") then 
    AddColumn() 
  end
  im.SameLine(ctx)
  
  if im.Button(ctx, "Add Empty") then 
    AddEmptyColumn() 
  end
  im.SameLine(ctx)
  
  
  if columns[activeColumn].enabled then
    if im.Button(ctx, "Remove Active") then 
      RemoveColumn(activeColumn) 
    end
    im.SameLine(ctx)
    
    if not syncMode then
      if im.Button(ctx, "Apply") then 
        ApplyToRegions(activeColumn) 
      end
      im.SameLine(ctx)
    end
    
    if im.Button(ctx, "Export") then 
      ExportSubtitles(activeColumn) 
    end
    im.SameLine(ctx)
  end
  
  if im.Button(ctx, showPreview and "Hide Preview" or "Show Preview") then
    showPreview = not showPreview
  end
  
  -- Count enabled columns
  local enabledCount = 0
  local enabledCols = {}
  for i = 1, maxColumns do
    if columns[i].enabled then
      enabledCount = enabledCount + 1
      table.insert(enabledCols, i)
    end
  end
  
  -- Main content area
  if enabledCount == 0 then
    im.Text(ctx, "Click the button below to add your first subtitle column:")
    im.Spacing(ctx)
  else
    local tableHeight = im.GetWindowHeight(ctx) - 150 -- Увеличили отступ для кнопок снизу
    local headerHeight = 0 -- Уменьшили высоту заголовков
    
    -- Prepare visible columns
    local visibleEnabledCols = {}
    for i = 1, maxColumns do
      local colNum = columnOrder[i]
      if colNum and columns[colNum].enabled then
        table.insert(visibleEnabledCols, colNum)
      end
    end
    
    local visibleColumnCount = #visibleEnabledCols

    im.PushStyleVar(ctx, im.StyleVar_CellPadding, 0, 0)
    
    if im.BeginTable(ctx, "headers", visibleColumnCount + 2, 
        im.TableFlags_Borders + im.TableFlags_Resizable + im.TableFlags_PreciseWidths + im.TableFlags_NoHostExtendX,
        0, headerHeight) then

      im.TableSetupColumn(ctx, '#', im.TableColumnFlags_WidthFixed + im.TableColumnFlags_NoResize, 30)
      im.TableSetupColumn(ctx, 'Time', im.TableColumnFlags_WidthFixed + im.TableColumnFlags_NoResize, 74)
      
      for _, colNum in ipairs(visibleEnabledCols) do
        im.TableSetupColumn(ctx, '', im.TableColumnFlags_WidthStretch)
      end

      im.TableNextRow(ctx, im.TableRowFlags_Headers)

      im.TableSetColumnIndex(ctx, 0)
      im.Text(ctx, "#")

      im.TableSetColumnIndex(ctx, 1)
      im.Text(ctx, "Time")

      for idx, colNum in ipairs(visibleEnabledCols) do
        im.TableSetColumnIndex(ctx, idx + 1)

        local width = im.GetContentRegionAvail(ctx)
        if width > 0 then
          columnWidths[colNum] = width
          if lastFrameWidths[colNum] and math.abs(lastFrameWidths[colNum] - width) > 20 then
            UIManager.clearCacheForColumn(colNum)
          end
          lastFrameWidths[colNum] = width
        end

        DrawColumnHeader(columns[colNum], colNum)
      end
      
      -- Handle drag/drop для заголовков
      HandleColumnDragDrop(visibleEnabledCols)
      
      im.EndTable(ctx)
    end
    
    im.PopStyleVar(ctx)
    
    -- СКРОЛЛИРУЕМОЕ СОДЕРЖИМОЕ
    if im.BeginChild(ctx, "TableContainer", -1, tableHeight - headerHeight, 0) then
      im.PushStyleVar(ctx, im.StyleVar_CellPadding, 0, 0)
      
      -- Основная таблица содержимого (БЕЗ заголовков)
      if im.BeginTable(ctx, "subtitles", visibleColumnCount + 2, 
          im.TableFlags_Borders + im.TableFlags_ScrollY + im.TableFlags_RowBg + 
          im.TableFlags_PreciseWidths + im.TableFlags_NoHostExtendX) then
        
        -- Setup columns для содержимого (точно такие же размеры как у заголовков)
        im.TableSetupColumn(ctx, '', im.TableColumnFlags_WidthFixed + im.TableColumnFlags_NoResize, 30)
        im.TableSetupColumn(ctx, '', im.TableColumnFlags_WidthFixed + im.TableColumnFlags_NoResize, 74)
        
        for _, colNum in ipairs(visibleEnabledCols) do
          local width = columnWidths[colNum] or 200
          im.TableSetupColumn(ctx, '', im.TableColumnFlags_WidthFixed + im.TableColumnFlags_NoResize, width)
        end
        
        -- Calculate max rows
        local maxRows = 0
        for _, colNum in ipairs(visibleEnabledCols) do
          maxRows = math.max(maxRows, #columns[colNum].subtitles)
        end
        
        -- Virtual scrolling setup
        local scrollY = im.GetScrollY(ctx)
        
        -- Принудительный скролл к строке если запрошен
        if scrollToRow then
          -- Принудительно пересчитать позицию скролла
          local targetScrollY = (scrollToRow - 1) * AVERAGE_ROW_HEIGHT
          im.SetScrollY(ctx, targetScrollY)
          scrollY = targetScrollY
        end
        
        -- Вычисляем видимые строки
        local contentHeight = tableHeight - headerHeight
        local visibleRowsCount = math.ceil(contentHeight / AVERAGE_ROW_HEIGHT)
        local firstVisibleRow = math.max(1, math.floor(scrollY / AVERAGE_ROW_HEIGHT) - BUFFER_ROWS)
        local lastVisibleRow = math.min(maxRows, firstVisibleRow + visibleRowsCount + BUFFER_ROWS * 2)
        
        -- Добавляем верхний spacer если есть пропущенные строки
        if firstVisibleRow > 1 then
          local spacerHeight = (firstVisibleRow - 1) * AVERAGE_ROW_HEIGHT
          im.TableNextRow(ctx)
          im.TableSetColumnIndex(ctx, 0)
          im.Dummy(ctx, 0, spacerHeight)
        end
        
        -- Draw table rows (только видимые)
        for row = firstVisibleRow, lastVisibleRow do
          im.TableNextRow(ctx)
          
          if scrollToRow and scrollToRow == row then
            scrollToRow = nil
          end
          
          -- Calculate max row height
          local maxRowHeight = 40
          for idx, colNum in ipairs(visibleEnabledCols) do
            if row <= #columns[colNum].values and columnWidths[colNum] then
              local text = columns[colNum].values[row] or ""
              local height = UIManager.calculateTextHeight(ctx, text, columnWidths[colNum] - 20)
              maxRowHeight = math.max(maxRowHeight, height)
            end
          end
          
          local col = columns[activeColumn]
          local isRowSelected = col.selected and col.selected[row]
          
          -- Row number column
          im.TableSetColumnIndex(ctx, 0)
          
          if isRowSelected then
            im.PushStyleColor(ctx, im.Col_Button, 0xFF6B47FF)
            im.PushStyleColor(ctx, im.Col_ButtonHovered, 0xFF7B57FF)
            im.PushStyleColor(ctx, im.Col_ButtonActive, 0xFF8B67FF)
          end
          
          local buttonText = tostring(row) .. "##sel"..row
          im.PushStyleVar(ctx, im.StyleVar_ButtonTextAlign, 0.5, 0.5)
          
          if im.Button(ctx, buttonText, -1, maxRowHeight) then
            HandleRowSelection(row)
          end
          
          if im.IsItemClicked(ctx, 1) then
            local currentCol = columns[activeColumn]
            if currentCol.enabled then
              currentCol.selected = {}
              currentCol.selected[row] = true
            end
          end

          if im.BeginPopupContextItem(ctx, "row_context_" .. row) then
            if im.MenuItem(ctx, "+ Add After") then
              AddRowAfter(row)
            end
            
            im.Separator(ctx)
            
            if im.MenuItem(ctx, "Delete Row") then
              DeleteSingleRow(row)
            end
            
            local currentCol = columns[activeColumn]
            if currentCol.enabled and row < #currentCol.subtitles then
              if im.MenuItem(ctx, "Merge with Next") then
                MergeWithNext(row)
              end
            end
            
            im.EndPopup(ctx)
          end
          
          im.PopStyleVar(ctx)
          
          if isRowSelected then
            im.PopStyleColor(ctx, 3)
          end
          
          -- Time column
          im.TableSetColumnIndex(ctx, 1)
          
          local timeText = ""
          -- Всегда берем время из первой активной колонки по порядку columnOrder
          local firstActiveCol = nil
          for i = 1, maxColumns do
            local colNum = columnOrder[i]
            if colNum and columns[colNum].enabled then
              firstActiveCol = colNum
              break
            end
          end
          
          if firstActiveCol and columns[firstActiveCol].subtitles[row] then
            local sub = columns[firstActiveCol].subtitles[row]
            timeText = GetCachedTimeDisplay(sub.start, sub._end)
          end
          local cursorPosY = im.GetCursorPosY(ctx)
          local lineHeight = im.GetTextLineHeight(ctx)
          local offsetY = math.max(0, (maxRowHeight - lineHeight * 2) * 0.5)
          im.SetCursorPosY(ctx, cursorPosY + offsetY)
          im.Text(ctx, timeText)
          for idx, colNum in ipairs(visibleEnabledCols) do
            im.TableSetColumnIndex(ctx, idx + 1)
            
            if row <= #columns[colNum].values then
              local isActive = (activeColumn == colNum and activeRow == row)
              local isActiveColumn = (activeColumn == colNum)
              local colWidth = columnWidths[colNum] or 200
              local isColEnabled = not columns[colNum].deactivated
              
              -- УЧИТЫВАЕМ ЧЕРЕДОВАНИЕ СТРОК (четные/нечетные)
              local isEvenRow = (row % 2 == 0)
              
              -- Базовые цвета с чередованием (БЕЗ изменения для активной колонки)
              local baseBg = isEvenRow and 0x2A2A2AFF or 0x323232FF
              local baseHover = isEvenRow and 0x3A3A3AFF or 0x424242FF
              local baseActive = isEvenRow and 0x4A4A4AFF or 0x525252FF
              
              im.PushStyleColor(ctx, im.Col_FrameBg, baseBg)
              im.PushStyleColor(ctx, im.Col_FrameBgHovered, baseHover)
              im.PushStyleColor(ctx, im.Col_FrameBgActive, baseActive)
              im.PushStyleColor(ctx, im.Col_Text, 0xFFFFFFFF)
              local colorsPushed = 4
              
              -- Если строка выделена - более яркие цвета (тоже с чередованием)
              if isRowSelected then
                local selectedBg = isEvenRow and 0x444466FF or 0x4C4C6EFF
                local selectedHover = isEvenRow and 0x555577FF or 0x5D5D7FFF
                local selectedActive = isEvenRow and 0x666688FF or 0x6E6E90FF
                
                im.PushStyleColor(ctx, im.Col_FrameBg, selectedBg)
                im.PushStyleColor(ctx, im.Col_FrameBgHovered, selectedHover)
                im.PushStyleColor(ctx, im.Col_FrameBgActive, selectedActive)
                colorsPushed = colorsPushed + 3
              end
              
              -- Если колонка деактивирована - серый фон с чередованием, НО белый текст
              if not isColEnabled then
                local disabledBg = isEvenRow and 0x1A1A1AFF or 0x222222FF
                local disabledHover = isEvenRow and 0x252525FF or 0x2D2D2DFF
                
                im.PushStyleColor(ctx, im.Col_FrameBg, disabledBg)
                im.PushStyleColor(ctx, im.Col_FrameBgHovered, disabledHover)
                im.PushStyleColor(ctx, im.Col_FrameBgActive, disabledHover)
                im.PushStyleColor(ctx, im.Col_Text, 0xFFFFFFFF)  -- Белый текст
                colorsPushed = colorsPushed + 4
              end
              
              local inputActive = isActive and isColEnabled
              local changed, newVal, height
              
              if isColEnabled then
                -- ИСПОЛЬЗУЕМ НОВУЮ ФУНКЦИЮ С БОКОВЫМИ ГРАНИЦАМИ
                changed, newVal, height = DrawInputWithSideBorders(ctx, 
                  colNum .. "_" .. row, columns[colNum].values[row], 
                  inputActive, colWidth, maxRowHeight, isActiveColumn)
              else
                -- For disabled columns use regular text with better styling
                local text = columns[colNum].values[row] or ""
                local wrappedText = UIManager.wrapText(ctx, text, colWidth - 20, "disabled_"..colNum.."_"..row)
                
                im.PushStyleVar(ctx, im.StyleVar_FramePadding, 6, 6)
                
                if im.BeginChild(ctx, "##disabled_" .. colNum .. "_" .. row, colWidth, maxRowHeight, 0, im.WindowFlags_NoScrollbar) then
                  im.TextWrapped(ctx, wrappedText)
                  im.EndChild(ctx)
                end
                
                im.PopStyleVar(ctx)
                changed, newVal = false, text
              end
              
              local isFocused = im.IsItemActive(ctx)
              if isColEnabled then
                HandleInputFocus(colNum, row, isFocused)
              end
              
              -- Убираем все стили
              im.PopStyleColor(ctx, colorsPushed)
              
              if changed and isColEnabled then
                columns[colNum].values[row] = newVal
                isDirty = true
                
                ScheduleSingleUpdate(colNum, row, newVal)
                
                local newHeight = UIManager.calculateTextHeight(ctx, newVal, colWidth - 20)
                if newHeight > maxRowHeight then
                  maxRowHeight = newHeight
                end
              end
              
              if im.IsItemClicked(ctx) and isColEnabled then
                HandleRowClick(row, colNum)
              end
            end
          end
        end
        
        -- Добавляем нижний spacer для оставшихся строк
        if lastVisibleRow < maxRows then
          local remainingRows = maxRows - lastVisibleRow
          local spacerHeight = remainingRows * AVERAGE_ROW_HEIGHT
          im.TableNextRow(ctx)
          im.TableSetColumnIndex(ctx, 0)
          im.Dummy(ctx, 0, spacerHeight)
        end
        
        im.EndTable(ctx)
      end
      
      im.PopStyleVar(ctx)
      im.EndChild(ctx)
    end
    
    -- Bottom control buttons
    if columns[activeColumn].enabled then
      im.Spacing(ctx) -- Небольшой отступ сверху
      
      local buttonWidth = 80
      
      if im.Button(ctx, "Merge", buttonWidth, 30) then 
        MergeSelected() 
      end
      im.SameLine(ctx)
      
      if im.Button(ctx, "Split", buttonWidth, 30) then 
        SplitAtCursor() 
      end
      im.SameLine(ctx)
      
      -- Delete selected button
      local activeCol = columns[activeColumn]
      local selectedCount = 0
      if activeCol.selected then
        for i, v in pairs(activeCol.selected) do
          if v then selectedCount = selectedCount + 1 end
        end
      end
      
      local deleteText = selectedCount > 0 and ("Delete (" .. selectedCount .. ")") or "Delete"
      if im.Button(ctx, deleteText, buttonWidth + 20, 30) then 
        if selectedCount > 0 then
          DeleteSelected()
        end
      end
      im.SameLine(ctx)
      
      if im.Button(ctx, "Delete All", buttonWidth, 30) then 
        DeleteAllSubtitles() 
      end
    end
  end
  
  DrawSearchWindow()

  im.PopFont(ctx)
  
  if showPreview then 
    ShowPreviewWindow() 
  end
  
  CheckTimelineSync()
  CheckRegionChanges()
  ProcessPendingChanges()
end

function SaveSession()
  if not isDirty then return end
  
  local currentTime = r.time_precise()
  
  -- Сохраняем только если прошло достаточно времени или принудительное сохранение
  if not forceSave and currentTime - lastSaveTime < saveInterval then
    return
  end
  
  SessionManager.saveSession(columns, columnOrder)
  isDirty = false
  forceSave = false
  lastSaveTime = currentTime
end

function LoadSession()
  local loadedColumns, loadedColumnOrder = SessionManager.loadSession()
  if loadedColumns then
    columns = loadedColumns
    for i = 1, maxColumns do
      if columns[i].enabled then
        activeColumn = i
        break
      end
    end
  end
  
  -- Загружаем или инициализируем порядок колонок
  if loadedColumnOrder then
    columnOrder = loadedColumnOrder
  else
    columnOrder = {1, 2, 3, 4, 5}
  end
end

function Defer()
  local visible, open = im.Begin(ctx, 'Subtitle Editor Pro', true)
  if visible then 
    Main()
    im.End(ctx)
  end
  
  if open then 
    SaveSession()
    r.defer(Defer)
  else 
    if previewCtx then
     -- im.DestroyContext(previewCtx)
      previewCtx = nil
      previewFont = nil
    end
    
    local _, _, sectionID, cmdID = r.get_action_context()
    r.SetToggleCommandState(sectionID, cmdID, 0)
    r.RefreshToolbar2(sectionID, cmdID)
  end
end

function Init()
  local _, _, sectionID, cmdID = r.get_action_context()
  r.SetToggleCommandState(sectionID, cmdID, 1)
  r.RefreshToolbar2(sectionID, cmdID)
  LoadSession()
  for i = 1, maxColumns do
    if columns[i].deactivated == nil then
      columns[i].deactivated = false
    end
  end
  Defer()
end
Init()