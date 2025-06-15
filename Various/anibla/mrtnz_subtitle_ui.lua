--@noindex
--NoIndex: true

local UIManager = {}
local im = require 'imgui' '0.9.2.3'

-- Оптимизированные кеши с хешированием
local cachedWrappedText = {}
local cachedTextSizes = {}
local cachedTimeFormats = {}
local frameCounter = 0
local lastCleanupFrame = 0

-- Константы для оптимизации
local maxCacheSize = 800
local cleanupInterval = 500
local shortTextThreshold = 18
local maxWidthThreshold = 50

-- Предварительно вычисленные значения
local lineHeightCache = nil
local standardPadding = 16
local minHeight = 40

-- Локальные ссылки на функции
local string_sub = string.sub
local string_gsub = string.gsub
local string_format = string.format
local string_find = string.find
local math_floor = math.floor
local math_max = math.max
local table_insert = table.insert

-- Хеш-таблицы для быстрого поиска ключей кеша
local wrappedTextKeys = {}
local textSizeKeys = {}

-- Добавим в начало UIManager
local fontSizeCache = nil
local charWidthCache = nil

-- Быстрый расчет ширины текста
local function fastCalcTextWidth(ctx, text)
  if not text or text == "" then return 0 end
  
  -- Кэшируем размер шрифта
  if not fontSizeCache then
    fontSizeCache = im.GetFontSize(ctx)
    charWidthCache = fontSizeCache / 2  -- Ваша формула
  end
  
  local textLen = #text
  
  -- Для коротких строк используем точный расчет
  if textLen <= 45 then
    return im.CalcTextSize(ctx, text)
  end
  
  -- Для длинных - быструю оценку
  local utf8Len = 0
  for i = 1, textLen do
    local byte = text:byte(i)
    if not byte then break end
    if byte < 128 or byte >= 192 then  -- UTF-8 logic
      utf8Len = utf8Len + 1
    end
  end
  
  return charWidthCache * utf8Len
end

-- Функция для быстрого хеширования строк
local function fastHash(str, len)
  local hash = len or #str
  local step = math_floor(hash / 4) + 1
  for i = 1, hash, step do
    hash = hash * 31 + str:byte(i)
  end
  return hash % 10000
end

-- Создание оптимизированных ключей кеша
local function createOptimizedCacheKey(text, width, prefix)
  local textLen = #text
  local widthInt = math_floor(width)
  
  if textLen <= 25 then
    return prefix .. widthInt .. "_" .. text .. "_" .. textLen
  end
  
  local hash = fastHash(text, textLen)
  return prefix .. widthInt .. "_" .. hash .. "_" .. textLen
end

-- Быстрая очистка кеша по паттерну
local function fastClearCacheByPattern(pattern, targetTable, keysTable)
  local keysToRemove = {}
  local count = 0
  
  -- Используем предварительно сохраненные ключи для быстрого поиска
  for key in pairs(keysTable) do
    if string_find(key, pattern, 1, true) then
      count = count + 1
      keysToRemove[count] = key
    end
  end
  
  -- Быстрое удаление без table.insert
  for i = 1, count do
    local key = keysToRemove[i]
    targetTable[key] = nil
    keysTable[key] = nil
  end
end

-- Более эффективная очистка кеша
local function efficientCacheCleanup()
  local wrappedCount = 0
  local sizeCount = 0
  
  for _ in pairs(cachedWrappedText) do
    wrappedCount = wrappedCount + 1
  end
  for _ in pairs(cachedTextSizes) do
    sizeCount = sizeCount + 1
  end
  
  if wrappedCount <= maxCacheSize and sizeCount <= maxCacheSize then 
    return 
  end
  
  -- Удаляем 40% элементов для более редких очисток
  local removeCount = 0
  local targetRemove = math_floor(wrappedCount * 0.4)
  
  for k in pairs(cachedWrappedText) do
    removeCount = removeCount + 1
    if removeCount % 3 == 0 then  -- Удаляем каждый третий
      cachedWrappedText[k] = nil
      wrappedTextKeys[k] = nil
    end
    if removeCount >= targetRemove then break end
  end
  
  removeCount = 0
  targetRemove = math_floor(sizeCount * 0.4)
  for k in pairs(cachedTextSizes) do
    removeCount = removeCount + 1
    if removeCount % 3 == 0 then
      cachedTextSizes[k] = nil
      textSizeKeys[k] = nil
    end
    if removeCount >= targetRemove then break end
  end
end

-- Кеширование форматирования времени
function UIManager.formatSRTTime(timeValue)
  local timeKey = string_format("%.3f", timeValue)
  
  if cachedTimeFormats[timeKey] then
    return cachedTimeFormats[timeKey]
  end
  
  local SubtitleLib = require('mrtnz_srtass-parser')
  local formatted = SubtitleLib.formatSRTTime(timeValue)
  cachedTimeFormats[timeKey] = formatted
  
  return formatted
end

-- Оптимизированный wrapText с исправленной логикой переноса
function UIManager.wrapText(ctx, text, maxWidth, cacheKey)
  if not text or text == "" then return "" end
  
  local roundedWidth = math_floor(maxWidth)
  if roundedWidth <= maxWidthThreshold then return text end
  
  local textLen = #text
  if textLen <= shortTextThreshold then return text end
  
  local fullCacheKey = createOptimizedCacheKey(text, roundedWidth, cacheKey or "w")
  
  if cachedWrappedText[fullCacheKey] then 
    return cachedWrappedText[fullCacheKey] 
  end
  
  -- Быстрая проверка нужности переноса
  local fullTextWidth = fastCalcTextWidth(ctx, text)
  if fullTextWidth <= roundedWidth then
    cachedWrappedText[fullCacheKey] = text
    wrappedTextKeys[fullCacheKey] = true
    return text
  end
  
  -- Исправленный алгоритм переноса
  local result = ""
  local lines = {}
  local lineCount = 0
  
  -- Разбиение по существующим переносам строк
  local startPos = 1
  while startPos <= textLen do
    local newlinePos = string_find(text, "\n", startPos, true)
    local lineEnd = newlinePos and (newlinePos - 1) or textLen
    
    lineCount = lineCount + 1
    lines[lineCount] = string_sub(text, startPos, lineEnd)
    
    startPos = newlinePos and (newlinePos + 1) or (textLen + 1)
  end
  
  -- Обработка каждой строки с улучшенным алгоритмом
  for i = 1, lineCount do
    local line = lines[i]
    
    if line == "" then
      if i > 1 then result = result .. "\n" end
    else
      -- Проверим помещается ли вся строка
      local lineWidth = fastCalcTextWidth(ctx, line)
      if lineWidth <= roundedWidth then
        if i > 1 then result = result .. "\n" end
        result = result .. line
      else
        -- Нужен перенос - улучшенный алгоритм разбиения
        local wrappedLine = ""
        local currentLine = ""
        local words = {}
        local wordCount = 0
        
        -- Разбиение на слова с учетом пунктуации
        local wordStart = 1
        local lineLen = #line
        while wordStart <= lineLen do
          local spacePos = string_find(line, " ", wordStart, true)
          local wordEnd = spacePos and (spacePos - 1) or lineLen
          
          if wordEnd >= wordStart then
            wordCount = wordCount + 1
            words[wordCount] = string_sub(line, wordStart, wordEnd)
          end
          
          wordStart = spacePos and (spacePos + 1) or (lineLen + 1)
        end
        
        -- Сборка строк с переносом
        for j = 1, wordCount do
          local word = words[j]
          local testLine = currentLine == "" and word or currentLine .. " " .. word
          local testWidth = fastCalcTextWidth(ctx, testLine)
          
          if testWidth > roundedWidth and currentLine ~= "" then
            -- Переносим текущую строку
            wrappedLine = wrappedLine == "" and currentLine or wrappedLine .. "\n" .. currentLine
            currentLine = word
          else
            currentLine = testLine
          end
        end
        
        -- Добавляем последнюю часть
        if currentLine ~= "" then
          wrappedLine = wrappedLine == "" and currentLine or wrappedLine .. "\n" .. currentLine
        end
        
        if i > 1 then result = result .. "\n" end
        result = result .. wrappedLine
      end
    end
  end
  
  -- Убираем лишние переносы в конце
  result = string_gsub(result, "\n+$", "")
  
  cachedWrappedText[fullCacheKey] = result
  wrappedTextKeys[fullCacheKey] = true
  
  -- Менее частая очистка кеша
  frameCounter = frameCounter + 1
  if frameCounter - lastCleanupFrame > cleanupInterval then
    efficientCacheCleanup()
    lastCleanupFrame = frameCounter
  end
  
  return result
end

-- Кеширование высоты строки
local function getLineHeight(ctx)
  if not lineHeightCache then
    lineHeightCache = im.GetTextLineHeight(ctx)
  end
  return lineHeightCache
end

-- Оптимизированный расчет высоты текста
function UIManager.calculateTextHeight(ctx, text, width)
  if not text or text == "" then return minHeight end
  
  local textLen = #text
  local roundedWidth = math_floor(width)
  
  if textLen <= shortTextThreshold then return minHeight end
  
  local cacheKey = createOptimizedCacheKey(text, roundedWidth, "h")
  
  if cachedTextSizes[cacheKey] then
    return cachedTextSizes[cacheKey]
  end
  
  local lineHeight = getLineHeight(ctx)
  
  -- Быстрая оценка для очень длинных текстов
  if textLen > 300 then
    local charWidth = 7 -- приблизительная ширина символа
    local estimatedCharsPerLine = math_floor(roundedWidth / charWidth)
    local estimatedLines = math_floor(textLen / estimatedCharsPerLine) + 1
    local height = math_max(minHeight, estimatedLines * lineHeight + standardPadding)
    cachedTextSizes[cacheKey] = height
    textSizeKeys[cacheKey] = true
    return height
  end
  
  local wrapped = UIManager.wrapText(ctx, text, roundedWidth, "calc")
  
  -- Быстрый подсчет строк
  local lineCount = 1
  local pos = 1
  local wrappedLen = #wrapped
  while pos <= wrappedLen do
    pos = string_find(wrapped, "\n", pos, true)
    if not pos then break end
    lineCount = lineCount + 1
    pos = pos + 1
  end
  
  local height = math_max(minHeight, lineCount * lineHeight + standardPadding)
  cachedTextSizes[cacheKey] = height
  textSizeKeys[cacheKey] = true
  
  return height
end

-- Оптимизированное поле ввода
function UIManager.drawTextInput(ctx, colIdx, rowIdx, text, isActive, width, fixedHeight)
  local fieldId = "##txt_" .. colIdx .. "_" .. rowIdx
  
  if isActive then 
    im.PushStyleColor(ctx, im.Col_Border, 0x4080FFFF)
    im.PushStyleColor(ctx, im.Col_FrameBg, 0x3A3A5AFF)
    im.PushStyleVar(ctx, im.StyleVar_FrameBorderSize, 2.0)
  end
  
  im.SetNextItemWidth(ctx, -1)
  im.PushStyleVar(ctx, im.StyleVar_FramePadding, 6, 6)
  
  local actualWidth = math_max(100, width - 20)
  local inputText = text or ""
  local wrappedText = inputText
  
  if not isActive and #inputText > shortTextThreshold then
    local wrapKey = "input_" .. colIdx .. "_" .. rowIdx
    wrappedText = UIManager.wrapText(ctx, inputText, actualWidth, wrapKey)
  elseif #inputText > shortTextThreshold then
    -- Для активных полей НЕ кэшируем, но используем быстрый расчет
    wrappedText = UIManager.wrapText(ctx, inputText, actualWidth, nil)
  end
  
  local dynamicHeight = fixedHeight
  if not fixedHeight then
    dynamicHeight = UIManager.calculateTextHeight(ctx, inputText, actualWidth)
  end
  
  local flags = im.InputTextFlags_AllowTabInput + im.InputTextFlags_NoHorizontalScroll
  if isActive then 
    flags = flags + im.InputTextFlags_AutoSelectAll
  end
  
  local changed, newVal = im.InputTextMultiline(ctx, fieldId, wrappedText, -1, dynamicHeight, flags)
  
  im.PopStyleVar(ctx)
  if isActive then 
    im.PopStyleVar(ctx)
    im.PopStyleColor(ctx, 2)
  end
  
  if changed then
    UIManager.clearCacheForItem(colIdx, rowIdx)
    newVal = string_gsub(newVal, "([^%s])\n([^%s])", "%1 %2")
    newVal = string_gsub(newVal, "([^%s]) \n([^%s])", "%1 %2")
  end
  
  return changed, newVal, dynamicHeight
end

-- Оптимизированная ячейка времени с кешированием
function UIManager.drawTimeCell(ctx, startTime, endTime, height)
  local timeText = UIManager.formatSRTTime(startTime) .. "\n" .. UIManager.formatSRTTime(endTime)
  
  local curX, curY = im.GetCursorPos(ctx)
  local lineHeight = getLineHeight(ctx)
  local offsetY = math_max(0, (height - lineHeight * 2) * 0.5)
  
  im.SetCursorPos(ctx, curX, curY + offsetY)
  im.Text(ctx, timeText)
end

-- Оптимизированная очистка кеша для элемента
function UIManager.clearCacheForItem(colIdx, rowIdx)
  local itemPattern = colIdx .. "_" .. rowIdx
  
  -- Быстрая очистка через предварительно сохраненные ключи
  fastClearCacheByPattern("input_" .. itemPattern, cachedWrappedText, wrappedTextKeys)
  fastClearCacheByPattern(itemPattern, cachedTextSizes, textSizeKeys)
end

function UIManager.clearCacheForColumn(colIdx)
  local colPattern = "input_" .. colIdx .. "_"
  
  fastClearCacheByPattern(colPattern, cachedWrappedText, wrappedTextKeys)
  fastClearCacheByPattern("^" .. colIdx .. "_", cachedTextSizes, textSizeKeys)
end

function UIManager.clearCache()
  cachedWrappedText = {}
  cachedTextSizes = {}
  cachedTimeFormats = {}
  wrappedTextKeys = {}
  textSizeKeys = {}
  lineHeightCache = nil
end

function UIManager.shouldUpdateFrame()
  frameCounter = frameCounter + 1
  return frameCounter % 20 == 0  -- Еще реже обновляем
end

function UIManager.drawProgressBar(ctx, current, total, width)
  local progress = current / total
  im.ProgressBar(ctx, progress, width, 20, string_format("%d/%d", current, total))
end

function UIManager.drawButton(ctx, label, width, height, color)
  if color then
    im.PushStyleColor(ctx, im.Col_Button, color)
    local result = im.Button(ctx, label, width or -1, height or 0)
    im.PopStyleColor(ctx)
    return result
  else
    return im.Button(ctx, label, width or -1, height or 0)
  end
end

function UIManager.drawSeparator(ctx, thickness)
  if thickness and thickness > 1 then
    local drawList = im.GetWindowDrawList(ctx)
    local curX, curY = im.GetCursorScreenPos(ctx)
    local availX = im.GetContentRegionAvail(ctx)
    im.DrawList_AddLine(drawList, curX, curY, curX + availX, curY, 0x555555FF, thickness)
    im.Dummy(ctx, availX, thickness)
  else
    im.Separator(ctx)
  end
end

function UIManager.getCacheSize()
  local wrappedCount = 0
  for _ in pairs(cachedWrappedText) do
    wrappedCount = wrappedCount + 1
  end
  return wrappedCount
end

function UIManager.getCacheStats()
  local wrappedCount = 0
  local sizeCount = 0
  local timeCount = 0
  
  for _ in pairs(cachedWrappedText) do
    wrappedCount = wrappedCount + 1
  end
  for _ in pairs(cachedTextSizes) do
    sizeCount = sizeCount + 1
  end
  for _ in pairs(cachedTimeFormats) do
    timeCount = timeCount + 1
  end
  
  return {
    wrappedTextCache = wrappedCount,
    textSizeCache = sizeCount,
    timeFormatCache = timeCount,
    maxCacheSize = maxCacheSize,
    frameCounter = frameCounter
  }
end

function UIManager.cleanupCache()
  efficientCacheCleanup()
  
  -- Очистка кеша времени
  local timeCount = 0
  for _ in pairs(cachedTimeFormats) do
    timeCount = timeCount + 1
  end
  
  if timeCount > 300 then
    local count = 0
    for k in pairs(cachedTimeFormats) do
      count = count + 1
      if count % 3 == 0 then
        cachedTimeFormats[k] = nil
      end
    end
  end
end

function UIManager.forceCacheCleanup()
  efficientCacheCleanup()
  lineHeightCache = nil
end

-- Пакетное обновление для улучшения производительности
function UIManager.batchUpdateInputs(ctx, inputs, startIdx, endIdx)
  local results = {}
  
  for i = startIdx, math.min(endIdx, #inputs) do
    local input = inputs[i]
    local changed, newVal, height = UIManager.drawTextInput(
      ctx, input.colIdx, input.rowIdx, input.text, 
      input.isActive, input.width, input.fixedHeight
    )
    
    if changed then
      results[i] = {changed = true, newVal = newVal, height = height}
    end
  end
  
  return results
end

return UIManager