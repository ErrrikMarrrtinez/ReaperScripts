--@noindex
--NoIndex: true

local SyncManager = {}
local r = reaper

local regionPrefix = ""
local lastAppliedColumn = 0
local isUpdating = false
local updateQueue = {}
local updateIndex = 1

-- Кеш для оптимизации
local regionCache = {}
local lastMarkerCount = -1
local lastFullScan = 0
local fullScanInterval = 2.5  -- Полное сканирование раз в 2.5 секунды

-- Кеш для маркеров
local markerCache = {}
local lastMarkerCacheUpdate = 0
local markerCacheInterval = 2.0

function SyncManager.detectOrderChanges(columns, currentRegions)
  -- Берем первую активную колонку как референс
  local firstActiveCol = nil
  for colIdx = 1, #columns do
    if columns[colIdx] and columns[colIdx].enabled then
      firstActiveCol = colIdx
      break
    end
  end
  
  if not firstActiveCol or not columns[firstActiveCol] or not columns[firstActiveCol].subtitles then 
    return false 
  end
  
  -- Получаем регионы первой колонки, отсортированные по времени
  local firstColRegions = {}
  for _, region in ipairs(currentRegions) do
    if region and region.column == firstActiveCol then
      table.insert(firstColRegions, region)
    end
  end
  
  if #firstColRegions == 0 then return false end
  
  table.sort(firstColRegions, function(a, b) return a.start < b.start end)
  
  local subtitlesCount = #columns[firstActiveCol].subtitles
  
  -- ЗАЩИТА: Если разница в количестве больше чем на 5 элементов - 
  -- скорее всего это временное состояние при массовом обновлении
  local countDiff = math.abs(#firstColRegions - subtitlesCount)
  if countDiff > 5 then
    return false  -- Игнорируем временные большие расхождения
  end
  
  -- Если количества сильно не совпадают - переупорядочиваем
  if #firstColRegions ~= subtitlesCount then
    if subtitlesCount > 0 then
      SyncManager.reorderSubtitles(columns, firstColRegions, firstActiveCol)
      return true
    end
    return false
  end
  
  -- Проверяем только ПОРЯДОК (минимум из двух массивов)
  local minCount = math.min(#firstColRegions - 1, subtitlesCount - 1)
  if minCount <= 0 then return false end
  
  local hasOrderChange = false
  for i = 1, minCount do
    local currentRegion = firstColRegions[i]
    local nextRegion = firstColRegions[i + 1]
    local currentSub = columns[firstActiveCol].subtitles[i]
    local nextSub = columns[firstActiveCol].subtitles[i + 1]
    
    if currentSub and nextSub and currentRegion and nextRegion then
      local regionOrderCorrect = currentRegion.start < nextRegion.start
      local subtitleOrderCorrect = currentSub.start < nextSub.start
      
      if regionOrderCorrect ~= subtitleOrderCorrect then
        hasOrderChange = true
        break
      end
    end
  end
  
  if hasOrderChange then
    SyncManager.reorderSubtitles(columns, firstColRegions, firstActiveCol)
    return true
  end
  
  return false
end
function SyncManager.reorderSubtitles(columns, orderedRegions, firstActiveCol)
  -- Создаем карту старых данных
  local oldSubtitles = {}
  for i, sub in ipairs(columns[firstActiveCol].subtitles) do
    if sub then  -- Проверка на nil
      oldSubtitles[i] = {
        subtitle = {
          start = sub.start,
          _end = sub._end,
          text = sub.text or ""
        },
        values = {},
        used = false  -- Флаг использования
      }
      -- Собираем значения из всех колонок для этой строки
      for colIdx = 1, #columns do
        if columns[colIdx].enabled and columns[colIdx].values and columns[colIdx].values[i] then
          oldSubtitles[i].values[colIdx] = columns[colIdx].values[i]
        end
      end
    end
  end
  
  -- Переупорядочиваем все колонки согласно новому порядку регионов
  for colIdx = 1, #columns do
    if columns[colIdx].enabled then
      columns[colIdx].subtitles = {}
      columns[colIdx].values = {}
    end
  end
  
  -- Заполняем в новом порядке
  for newIndex, region in ipairs(orderedRegions) do
    local matchedOldIndex = nil
    local bestMatch = nil
    local bestScore = math.huge
    
    -- БЕЗОПАСНЫЙ поиск соответствия
    for oldIndex, oldData in pairs(oldSubtitles) do
      if oldData and not oldData.used and oldData.subtitle then
        local startDiff = math.abs(oldData.subtitle.start - region.start)
        local endDiff = math.abs(oldData.subtitle._end - region._end)
        local score = startDiff + endDiff
        
        if score < bestScore and score < 1.0 then
          bestScore = score
          bestMatch = oldIndex
        end
      end
    end
    
    matchedOldIndex = bestMatch
    
    -- Добавляем в новом порядке
    for colIdx = 1, #columns do
      if columns[colIdx].enabled then
        if matchedOldIndex and oldSubtitles[matchedOldIndex] and oldSubtitles[matchedOldIndex].subtitle then
          -- Восстанавливаем данные из старой позиции с ОБНОВЛЕННЫМ временем
          local oldData = oldSubtitles[matchedOldIndex]
          local newSubtitle = {
            start = region.start,
            _end = region._end,
            text = oldData.subtitle.text or ""
          }
          table.insert(columns[colIdx].subtitles, newSubtitle)
          table.insert(columns[colIdx].values, oldData.values[colIdx] or "")
        else
          -- Создаем новую строку если не нашли соответствие
          table.insert(columns[colIdx].subtitles, {
            start = region.start,
            _end = region._end,
            text = ""
          })
          table.insert(columns[colIdx].values, "")
        end
      end
    end
    
    -- Помечаем как использованный ПОСЛЕ обработки всех колонок
    if matchedOldIndex and oldSubtitles[matchedOldIndex] then
      oldSubtitles[matchedOldIndex].used = true
    end
  end
end
function SyncManager.findSubtitleAtTime(subtitles, time)
  if not subtitles or #subtitles == 0 then return 1 end
  
  for i, sub in ipairs(subtitles) do
    if time >= sub.start and time <= sub._end then
      return i
    end
  end
  
  for i = #subtitles, 1, -1 do
    if time >= subtitles[i]._end then
      return math.min(i + 1, #subtitles)
    end
  end
  
  return 1
end

-- Оптимизированное получение маркеров с кешированием
function SyncManager.getCachedMarkers()
  local currentTime = r.time_precise()
  local totalMarkers = r.CountProjectMarkers(0)
  
  -- Используем кеш если данные свежие и количество маркеров не изменилось
  if markerCache.data and 
     currentTime - lastMarkerCacheUpdate < markerCacheInterval and
     markerCache.count == totalMarkers then
    return markerCache.data
  end
  
  -- Обновляем кеш
  local markers = {}
  for i = 0, totalMarkers - 1 do
    local retval, isrgn, pos, rgnend, name, markrgnindexnumber = r.EnumProjectMarkers(i)
    if retval and isrgn then
      table.insert(markers, {
        index = markrgnindexnumber,
        pos = pos,
        rgnend = rgnend,
        name = name
      })
    end
  end
  
  markerCache = {
    data = markers,
    count = totalMarkers
  }
  lastMarkerCacheUpdate = currentTime
  
  return markers
end

function SyncManager.getSubtitleRegions()
  local markers = SyncManager.getCachedMarkers()
  local regions = {}
  
  for _, marker in ipairs(markers) do
    if regionPrefix == "" then
      table.insert(regions, {
        index = marker.index,
        column = 1,
        start = marker.pos,
        _end = marker.rgnend,
        text = marker.name
      })
    else
      if marker.name:match("^" .. regionPrefix) then
        local colNum = marker.name:match("^" .. regionPrefix .. "(%d+)_")
        if colNum then
          table.insert(regions, {
            index = marker.index,
            column = tonumber(colNum),
            start = marker.pos,
            _end = marker.rgnend,
            text = marker.name:gsub("^" .. regionPrefix .. "%d+_", "")
          })
        end
      end
    end
  end
  
  return regions
end

function SyncManager.getCurrentRegionState()
  local regions = SyncManager.getSubtitleRegions()
  local state = {}
  
  for _, region in ipairs(regions) do
    state[region.index] = {
      start = region.start,
      _end = region._end,
      text = region.text
    }
  end
  
  return state
end

function SyncManager.removeColumnRegions(columnNumber)
  -- Получаем ВСЕ маркеры
  local totalMarkers = r.CountProjectMarkers(0)
  local toRemove = {}
  
  if regionPrefix == "" then
    -- Если нет префикса - удаляем ВСЕ регионы
    for i = 0, totalMarkers - 1 do
      local retval, isrgn, pos, rgnend, name, markrgnindexnumber = r.EnumProjectMarkers(i)
      if retval and isrgn then
        table.insert(toRemove, markrgnindexnumber)
      end
    end
  else
    -- Удаляем только регионы конкретной колонки
    for i = 0, totalMarkers - 1 do
      local retval, isrgn, pos, rgnend, name, markrgnindexnumber = r.EnumProjectMarkers(i)
      if retval and isrgn then
        local colNum = name:match("^" .. regionPrefix .. "(%d+)_")
        if colNum and tonumber(colNum) == columnNumber then
          table.insert(toRemove, markrgnindexnumber)
        end
      end
    end
  end
  
  -- Удаляем в обратном порядке (от большего к меньшему)
  table.sort(toRemove, function(a, b) return a > b end)
  
  r.Undo_BeginBlock()
  for _, index in ipairs(toRemove) do
    r.DeleteProjectMarkerByIndex(0, index)
  end
  r.Undo_EndBlock("Remove column regions", -1)
  
  -- Принудительно очищаем кеш
  markerCache = {}
  lastMarkerCacheUpdate = 0
end

function SyncManager.removeAllRegions()
  r.Undo_BeginBlock()
  
  -- Удаляем ВСЕ регионы подряд пока они есть
  local totalMarkers = r.CountProjectMarkers(0)
  while totalMarkers > 0 do
    local foundRegions = false
    
    for i = totalMarkers - 1, 0, -1 do  -- В обратном порядке
      local retval, isrgn, pos, rgnend, name, markrgnindexnumber = r.EnumProjectMarkers(i)
      if retval and isrgn then
        r.DeleteProjectMarkerByIndex(0, markrgnindexnumber)
        foundRegions = true
      end
    end
    
    if not foundRegions then break end
    totalMarkers = r.CountProjectMarkers(0)
  end
  
  r.Undo_EndBlock("Remove all regions", -1)
  
  -- Очищаем кеш
  markerCache = {}
  lastMarkerCacheUpdate = 0
end

-- Оптимизированная пакетная обработка
function processUpdateBatch()
  if updateIndex > #updateQueue then 
    isUpdating = false
    updateQueue = {}
    updateIndex = 1
    markerCache = {}  -- Очищаем кеш после обновления
    return 
  end
  
  local batchSize = 50  -- Увеличили размер пакета
  local endIndex = math.min(updateIndex + batchSize - 1, #updateQueue)
  
  -- Группируем операции в один undo блок
  r.Undo_BeginBlock()
  
  for i = updateIndex, endIndex do
    local item = updateQueue[i]
    r.AddProjectMarker2(0, true, item.start, item._end, item.name, -1, 0)
  end
  
  r.Undo_EndBlock("Batch add markers", -1)
  
  updateIndex = endIndex + 1
  
  if updateIndex <= #updateQueue then
    r.defer(processUpdateBatch)
  else
    isUpdating = false
    updateQueue = {}
    updateIndex = 1
    markerCache = {}
  end
end

function SyncManager.updateSingleRegion(columnNumber, subtitleIndex, subtitle)
  local regionName = subtitle.text or ""
  if regionPrefix ~= "" then
    regionName = regionPrefix .. columnNumber .. "_" .. regionName
  end
  
  local regions = SyncManager.getSubtitleRegions()
  local sortedRegions = {}
  
  for _, region in ipairs(regions) do
    if region.column == columnNumber then
      table.insert(sortedRegions, region)
    end
  end
  
  table.sort(sortedRegions, function(a, b) return a.start < b.start end)
  
  local targetRegion = sortedRegions[subtitleIndex]
  
  if targetRegion then
    if targetRegion.text ~= regionName then
      r.SetProjectMarker4(0, targetRegion.index, true, subtitle.start, subtitle._end, 
        regionName, targetRegion.index, 0)
      markerCache = {}  -- Очищаем кеш после изменения
    end
  else
    r.AddProjectMarker2(0, true, subtitle.start, subtitle._end, regionName, -1, 0)
    markerCache = {}
  end
end

function SyncManager.applySubtitlesToRegions(subtitles, columnNumber)
  if isUpdating then return end
  isUpdating = true
  
  r.Undo_BeginBlock()
  
  SyncManager.removeColumnRegions(columnNumber)
  
  updateQueue = {}
  for i, sub in ipairs(subtitles) do
    local regionName = sub.text or ""
    if regionPrefix ~= "" then
      regionName = regionPrefix .. columnNumber .. "_" .. regionName
    end
    
    table.insert(updateQueue, {
      start = sub.start,
      _end = sub._end,
      name = regionName
    })
  end
  
  updateIndex = 1
  lastAppliedColumn = columnNumber
  processUpdateBatch()
  
  r.Undo_EndBlock("Apply subtitles to regions", -1)
end

function SyncManager.applySubtitleChanges(subtitles, columnNumber, changedIndices)
  if not changedIndices or #changedIndices == 0 then return end
  
  r.Undo_BeginBlock()
  
  for _, index in ipairs(changedIndices) do
    if subtitles[index] then
      SyncManager.updateSingleRegion(columnNumber, index, subtitles[index])
    end
  end
  
  r.Undo_EndBlock("Update subtitle regions", -1)
end

function SyncManager.updateRegionText(columnNumber, subtitleIndex, newText, subtitles)
  local regions = SyncManager.getSubtitleRegions()
  
  for _, region in ipairs(regions) do
    if region.column == columnNumber then
      local sub = subtitles[subtitleIndex]
      if sub and math.abs(region.start - sub.start) < 0.001 then
        local regionName = newText
        if regionPrefix ~= "" then
          regionName = regionPrefix .. columnNumber .. "_" .. newText
        end
        
        r.SetProjectMarker4(0, region.index, true, region.start, region._end, 
          regionName, region.index, 0)
        markerCache = {}
        break
      end
    end
  end
end

function SyncManager.syncRegionToSubtitles(regionIndex, newStart, newEnd, columns)
  local regions = SyncManager.getSubtitleRegions()
  local targetRegion = nil
  
  for _, region in ipairs(regions) do
    if region.index == regionIndex then
      targetRegion = region
      break
    end
  end
  
  if not targetRegion then return end
  
  for colIdx = 1, #columns do
    local col = columns[colIdx]
    if col.enabled then
      for i, sub in ipairs(col.subtitles) do
        if math.abs(sub.start - targetRegion.start) < 0.1 then
          SyncManager.updateTimingForRow(columns, i, newStart, newEnd)
          return
        end
      end
    end
  end
end

function SyncManager.updateTimingForRow(columns, rowIndex, newStart, newEnd)
  for colIdx = 1, #columns do
    local col = columns[colIdx]
    if col.enabled and col.subtitles[rowIndex] then
      col.subtitles[rowIndex].start = newStart
      col.subtitles[rowIndex]._end = newEnd
    end
  end
end

function SyncManager.checkTimelineSync(activeColumn, activeRow, columns)
  if not columns[activeColumn].enabled then return end
  
  local playState = r.GetPlayState()
  if playState == 0 then return end
  
  local pos = r.GetPlayPosition()
  local newRow = SyncManager.findSubtitleAtTime(columns[activeColumn].subtitles, pos)
  
  if newRow ~= activeRow then
    return newRow
  end
  
  return activeRow
end

function SyncManager.getRegionsForColumn(columnNumber)
  local regions = SyncManager.getSubtitleRegions()
  local result = {}
  
  for _, region in ipairs(regions) do
    if region.column == columnNumber then
      table.insert(result, region)
    end
  end
  
  table.sort(result, function(a, b) return a.start < b.start end)
  return result
end

-- Оптимизированное обнаружение изменений регионов
function SyncManager.detectRegionChanges(columns, lastKnownRegions)
  local currentTime = r.time_precise()
  
  -- Проверяем количество маркеров для быстрой проверки изменений
  local currentMarkerCount = r.CountProjectMarkers(0)
  if lastMarkerCount == currentMarkerCount and 
     currentTime - lastFullScan < fullScanInterval then
    return {}, lastKnownRegions
  end
  
  lastMarkerCount = currentMarkerCount
  lastFullScan = currentTime
  
  local currentRegions = SyncManager.getSubtitleRegions()
  local changes = {}
  
  local currentMap = {}
  for _, region in ipairs(currentRegions) do
    currentMap[region.index] = region
  end
  
  local lastMap = {}
  if lastKnownRegions then
    for index, regionData in pairs(lastKnownRegions) do
      lastMap[index] = regionData
    end
  end
  
  for index, current in pairs(currentMap) do
    local last = lastMap[index]
    if last then
      if math.abs(current.start - last.start) > 0.001 or 
         math.abs(current._end - last._end) > 0.001 then
        table.insert(changes, {
          index = index,
          oldStart = last.start,
          oldEnd = last._end,
          newStart = current.start,
          newEnd = current._end,
          region = current
        })
      end
    end
  end
  
  return changes, SyncManager.getCurrentRegionState()
end

function SyncManager.applyRegionChanges(changes, columns)
  if #changes == 0 then return false end
  
  local hasChanges = false
  
  for _, change in ipairs(changes) do
    for colIdx = 1, #columns do
      local col = columns[colIdx]
      if col.enabled then
        for i, sub in ipairs(col.subtitles) do
          if math.abs(sub.start - change.oldStart) < 0.2 and
             math.abs(sub._end - change.oldEnd) < 0.2 then
            SyncManager.updateTimingForRow(columns, i, change.newStart, change.newEnd)
            hasChanges = true
            goto next_change
          end
        end
      end
    end
    ::next_change::
  end
  
  return hasChanges
end

function SyncManager.performOptimizedRegionSync(columns, lastKnownRegions)
  local currentTime = r.time_precise()
  
  if regionCache.lastCheck and currentTime - regionCache.lastCheck < 1.0 then
    return false, lastKnownRegions
  end
  
  regionCache.lastCheck = currentTime
  
  -- ЗАЩИТА: Если нет активных колонок - ничего не делаем
  local hasActiveColumns = false
  for i = 1, #columns do
    if columns[i] and columns[i].enabled then
      hasActiveColumns = true
      break
    end
  end
  
  if not hasActiveColumns then
    return false, lastKnownRegions
  end
  
  local changes, currentRegions = SyncManager.detectRegionChanges(columns, lastKnownRegions)
  local hasChanges = false
  
  -- Проверяем изменения порядка ТОЛЬКО если нет активных изменений времени
  if #changes == 0 then
    local currentRegionsList = SyncManager.getSubtitleRegions()
    local orderChanged = SyncManager.detectOrderChanges(columns, currentRegionsList)
    
    if orderChanged then
      hasChanges = true
      currentRegions = SyncManager.getCurrentRegionState()
    end
  else
    -- Применяем только изменения времени
    local applied = SyncManager.applyRegionChanges(changes, columns)
    hasChanges = applied
  end
  
  return hasChanges, currentRegions or lastKnownRegions
end
function SyncManager.clearCache()
  regionCache = {}
  markerCache = {}
  lastMarkerCount = -1
  lastFullScan = 0
  lastMarkerCacheUpdate = 0
end

function SyncManager.getCacheStats()
  return {
    lastCheck = regionCache.lastCheck,
    markerCacheSize = markerCache.data and #markerCache.data or 0,
    lastMarkerCacheUpdate = lastMarkerCacheUpdate,
    lastFullScan = lastFullScan
  }
end

-- Принудительное обновление кеша маркеров
function SyncManager.forceMarkerCacheUpdate()
  markerCache = {}
  lastMarkerCacheUpdate = 0
end

return SyncManager