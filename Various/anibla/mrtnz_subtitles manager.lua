--@noindex
--NoIndex: true

local r = reaper; r.defer(function() end)
local script_path = debug.getinfo(1, "S").source:match("@(.*[\\/])")

if not r.ImGui_GetBuiltinPath then 
    package.path = script_path .. '?.lua'
else
    imgui_path = reaper.ImGui_GetBuiltinPath() .. '/?.lua'
    package.path = imgui_path .. ";" .. script_path .. '?.lua'
    ImGui = require 'imgui' '0.9.2.3'
end

local f = require('mrtnz_utils')
local srtass = require('mrtnz_srtass-parser')
srtass.simpleCleanMode = true

local state = f.checkDependencies()
if not state then return end

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
local regionColors = {}
local scrollY = 0

local showProgressBar = true
local savedProgressBarState = r.GetExtState("SubtitlesWindow", "showProgressBar")
if savedProgressBarState and savedProgressBarState ~= "" then 
    showProgressBar = savedProgressBarState == "true"
end

-- ИСПРАВЛЕНИЕ УТЕЧКИ ПАМЯТИ: Ограниченные кеши
local MAX_CACHE_SIZE = 500
local textHeightsCache = {}
local textHeightsCacheCount = 0
local lastCursorPos = nil
local cachedActiveIndices = {}
local cachedRegionCenters = {}
local cachedTotalHeight = 0

-- Переменные для редактора субтитров
local editorOpen = false
local editingIndices = {}
local editorTexts = {}

local lastCursorPos = nil
local cachedActiveIndices = {}
local cachedRegionCenters = {}
local cachedTotalHeight = 0
local targetSubtitleIndex = nil  -- индекс субтитра к которому скроллим
local scrollProgress = 0  -- прогресс скролла (0-1)

-- Добавить новый цвет для "целевого" субтитра
local COLOR_TARGET = 0xAAAAAAFF  -- более светлый чем соседний

-- ИСПРАВЛЕНИЕ УТЕЧКИ: Ограниченный кеш ключей
local cacheKeyLookup = {}
local cacheKeyCount = 0



-- Новые цвета для тегов
local COLOR_ERROR = 0xFF4444FF    -- красный для ошибок
local COLOR_NOTE = 0x44FF44FF     -- зеленый для заметок
local COLOR_ERROR_FRAME = 0xFF0000FF  -- красная рамка
local COLOR_NOTE_FRAME = 0x00FF00FF   -- зеленая рамка

-- Функция проверки тегов в тексте
local function checkSpecialTags(text)
    if not text then return nil end
    local upperText = text:upper()
    
    if upperText:find("#OSHIBKA") then
        return "error"
    elseif upperText:find("#ZAMETKA") then
        return "note"  
    end
    
    return nil
end

-- Функция для отрисовки рамки вокруг текста
local function drawTextWithFrame(ctx, text, wrap_width, cachedData, frameColor)
    if not cachedData or not cachedData.lines then return 0 end
    
    wrap_width = wrap_width or ImGui.GetContentRegionAvail(ctx)
    local startX = ImGui.GetCursorPosX(ctx)
    local startY = ImGui.GetCursorPosY(ctx)
    
    -- Получаем draw list для рисования рамки
    local draw_list = ImGui.GetWindowDrawList(ctx)
    local winPosX, winPosY = ImGui.GetWindowPos(ctx)
    
    -- Вычисляем границы рамки
    local frameLeft = winPosX + startX - 8
    local frameTop = winPosY + startY - 4
    local frameRight = winPosX + startX + wrap_width + 8
    local frameBottom = winPosY + startY + cachedData.height + 8
    
    -- Рисуем рамку
    ImGui.DrawList_AddRect(draw_list, frameLeft, frameTop, frameRight, frameBottom, frameColor, 4.0, 0, 2.0)
    
    -- Рисуем текст как обычно
    for i, line in ipairs(cachedData.lines) do
        local _, textWidth = transformAndMeasure(line)
        local offset = (wrap_width - textWidth) * 0.5
        offset = math.max(offset, 0)
        ImGui.SetCursorPos(ctx, startX + offset - 4, startY + (i - 1) * (cachedData.lineHeight + cachedData.extraSpacing))
        local trans_line, _ = transformAndMeasure(line)
        ImGui.Text(ctx, trans_line)
    end
    
    return cachedData.height
end

local function get_cache_key(sub)
    if not sub then return "" end
    
    local cached = cacheKeyLookup[sub]
    if cached then return cached end
    
    -- Очищаем кеш при достижении лимита
    if cacheKeyCount > MAX_CACHE_SIZE then
        cacheKeyLookup = {}
        cacheKeyCount = 0
    end
    
    local key = sub.type .. "_" .. sub.start .. "_" .. sub.name
    cacheKeyLookup[sub] = key
    cacheKeyCount = cacheKeyCount + 1
    return key
end

-- Быстрые цветовые функции (ускорены)
local function fastLerpColor(color1, color2, factor)
    local r1 = (color1 >> 24) & 0xFF
    local g1 = (color1 >> 16) & 0xFF
    local b1 = (color1 >> 8) & 0xFF
    local a1 = color1 & 0xFF
    
    local r2 = (color2 >> 24) & 0xFF
    local g2 = (color2 >> 16) & 0xFF
    local b2 = (color2 >> 8) & 0xFF
    local a2 = color2 & 0xFF
    
    local nr = math.floor(r1 + (r2 - r1) * factor)
    local ng = math.floor(g1 + (g2 - g1) * factor)
    local nb = math.floor(b1 + (b2 - b1) * factor)
    local na = math.floor(a1 + (a2 - a1) * factor)
    
    return (nr << 24) | (ng << 16) | (nb << 8) | na
end

local function fastGetBrightness(color)
    local r = (color >> 24) & 0xFF
    local g = (color >> 16) & 0xFF
    local b = (color >> 8) & 0xFF
    return (r * 0.299 + g * 0.587 + b * 0.114) / 255
end

-- Кеширование с ограничением частоты
local itemsCacheData = {
    items = {},
    lastUpdate = 0,
    updateInterval = 0.3
}

-- Общие данные для всех окон (избегаем дублирования вычислений)
local sharedData = {
    subtitles = {},
    activeIndices = {},
    regionCenters = {},
    totalHeight = 0,
    lastUpdate = 0,
    visibleIndices = {},
    lastColorUpdate = 0
}

f.AddScriptStartup()

-- Функция для очистки текста
local function sanitizeText(text)
    if not text or text == "" then return "" end
    local clean = text:gsub("\239\191\189", "") -- UTF-8 для символа замены
    return clean
end

-- Автоперенос для поля ввода
local function autoWrapText(text, maxWidth, ctx)
    if not text or text == "" or maxWidth <= 0 then return text end
    
    local lines = {}
    for line in text:gmatch("[^\r\n]*") do
        if line ~= "" then
            local lineWidth = select(1, ImGui.CalcTextSize(ctx, line))
            if lineWidth <= maxWidth then
                table.insert(lines, line)
            else
                local words = {}
                for word in line:gmatch("%S+") do
                    table.insert(words, word)
                end
                
                local currentLine = ""
                for _, word in ipairs(words) do
                    local testLine = (currentLine == "") and word or (currentLine .. " " .. word)
                    local testWidth = select(1, ImGui.CalcTextSize(ctx, testLine))
                    
                    if testWidth > maxWidth and currentLine ~= "" then
                        table.insert(lines, currentLine)
                        currentLine = word
                    else
                        currentLine = testLine
                    end
                end
                
                if currentLine ~= "" then
                    table.insert(lines, currentLine)
                end
            end
        else
            table.insert(lines, "")
        end
    end
    
    return table.concat(lines, "\n")
end
-- Add this in the global area of your script (outside all functions):
editorFont = ImGui.CreateFont('Calibri', 16)
ImGui.Attach(ctx, editorFont)

-- Store wrapped text for real-time updates
local editorWrappedTexts = {}

-- Auto-wrap function for text input (outside the main function)
local function wrapTextForInput(ctx, text, maxWidth)
    if not text or text == "" then return text end
    if text:find("\n") then return text end
    
    local wrappedText, currentLine = "", ""
    for word in text:gmatch("%S+") do
        if currentLine == "" then 
            currentLine = word 
        else
            local potentialLineWidth = ImGui.CalcTextSize(ctx, currentLine.." "..word)
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

function processSubtitleEditor(ctx, editorOpen, editorFirstFrame, editingIndices, editorTexts, cachedRegions, f, r, update_region_name)
    if ImGui.IsMouseClicked(ctx, 0) then
        cachedRegions = f.get_regions()
        cachedRegionsTime = r.time_precise()
    end

    if editorOpen and editorFirstFrame == nil then
        editorFirstFrame = true
    end

    if editorOpen then
        -- Enhanced styling
        ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowRounding, 12)
        ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowPadding, 16, 12)
        ImGui.PushStyleVar(ctx, ImGui.StyleVar_ItemSpacing, 6, 6)
        ImGui.PushStyleVar(ctx, ImGui.StyleVar_FrameRounding, 8)
        ImGui.PushStyleVar(ctx, ImGui.StyleVar_FramePadding, 8, 6)
        
        -- Color styling
        ImGui.PushStyleColor(ctx, ImGui.Col_WindowBg, 0x2a2a2aFF)
        ImGui.PushStyleColor(ctx, ImGui.Col_FrameBg, 0x3a3a3aFF)
        ImGui.PushStyleColor(ctx, ImGui.Col_FrameBgHovered, 0x4a4a4aFF)
        ImGui.PushStyleColor(ctx, ImGui.Col_FrameBgActive, 0x5a5a5aFF)
        ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0xf0f0f0FF)
        ImGui.PushStyleColor(ctx, ImGui.Col_Button, 0x4a90e2FF)
        ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, 0x5ba0f2FF)
        ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, 0x3a80d2FF)
        
        -- Calculate total height dynamically
        local baseHeight = 80 -- Base padding and buttons
        local totalTextHeight = 0
        local availWidth = 480
        local inputWidth = availWidth - 32
        
        ImGui.PushFont(ctx, editorFont)
        
        -- Pre-calculate heights for each text field
        local fieldHeights = {}
        for i, idx in ipairs(editingIndices) do
            if not editorTexts[idx] then editorTexts[idx] = "" end
            local cleanText = sanitizeText(editorTexts[idx] or "")
            
            -- Initialize wrapped text if not exists
            if not editorWrappedTexts[idx] then
                editorWrappedTexts[idx] = wrapTextForInput(ctx, cleanText, inputWidth - 24)
            end
            
            local lineCount = 1
            for _ in (editorWrappedTexts[idx] or ""):gmatch("\n") do 
                lineCount = lineCount + 1 
            end
            local textHeight = lineCount * ImGui.GetTextLineHeight(ctx) + 20
            textHeight = math.max(100, math.min(300, textHeight))
            fieldHeights[i] = textHeight
            totalTextHeight = totalTextHeight + textHeight + 20 -- +20 for label
        end
        
        ImGui.PopFont(ctx)
        
        local windowHeight = baseHeight + totalTextHeight + (#editingIndices * 6) + 30 -- +30 extra pixels
        
        ImGui.SetNextWindowSize(ctx, availWidth, windowHeight, ImGui.Cond_Always)
        local editorVisible, editorOpenFlag = ImGui.Begin(ctx, "Subtitle Editor", true, 
            ImGui.WindowFlags_NoCollapse | ImGui.WindowFlags_NoDocking | ImGui.WindowFlags_NoResize)
        
        if not editorOpenFlag then
            editorOpen = false
        end
        
        if editorVisible then
            ImGui.PushFont(ctx, editorFont)
            
            local realAvailWidth = ImGui.GetContentRegionAvail(ctx)
            local realInputWidth = realAvailWidth - 8
            
            for i, idx in ipairs(editingIndices) do
                ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0xc0c0c0FF)
                ImGui.Text(ctx, "Region " .. idx .. ":")
                ImGui.PopStyleColor(ctx)
                
                if i == 1 and editorFirstFrame then
                    ImGui.SetKeyboardFocusHere(ctx)
                    editorFirstFrame = false
                end
                
                if not editorTexts[idx] then
                    editorTexts[idx] = ""
                end
                
                -- Initialize wrapped text if not exists
                if not editorWrappedTexts[idx] then
                    local originalText = sanitizeText(editorTexts[idx] or "")
                    editorWrappedTexts[idx] = wrapTextForInput(ctx, originalText, realInputWidth - 24)
                end
                
                -- Calculate dynamic height based on current wrapped text
                local currentWrappedText = editorWrappedTexts[idx] or ""
                local lineCount = 1
                for _ in currentWrappedText:gmatch("\n") do 
                    lineCount = lineCount + 1 
                end
                local dynamicHeight = lineCount * ImGui.GetTextLineHeight(ctx) + 20
                dynamicHeight = math.max(100, math.min(300, dynamicHeight))
                
                -- Input text flags for proper wrapping
                local flags = ImGui.InputTextFlags_NoHorizontalScroll
                
                ImGui.SetNextItemWidth(ctx, realInputWidth)
                local success, changed, newText = pcall(function()
                    return ImGui.InputTextMultiline(ctx, "##editor" .. idx, currentWrappedText, 
                        2048, realInputWidth, dynamicHeight, flags, nil)
                end)
                
                if success and changed and newText then
                    -- Real-time wrapping: immediately update wrapped text and original text
                    local cleanNewText = sanitizeText(newText or "")
                    if #cleanNewText > 1000 then
                        cleanNewText = string.sub(cleanNewText, 1, 1000)
                    end
                    
                    -- Save original text without line breaks
                    editorTexts[idx] = cleanNewText:gsub("\n", " ")
                    
                    -- Update wrapped text for immediate display
                    editorWrappedTexts[idx] = wrapTextForInput(ctx, editorTexts[idx], realInputWidth - 24)
                elseif not success then
                    editorTexts[idx] = sanitizeText(editorTexts[idx] or "")
                    editorWrappedTexts[idx] = wrapTextForInput(ctx, editorTexts[idx], realInputWidth - 24)
                end
            end
            
            -- Button styling
            local buttonWidth = (realAvailWidth - 12) / 2
            
            if ImGui.Button(ctx, "Apply Changes", buttonWidth, 26) then
                for _, idx in ipairs(editingIndices) do
                    if editorTexts[idx] then
                        local retval, isrgn, pos, rgnend, name, markrgnindexnumber = r.EnumProjectMarkers(idx - 1)
                        if isrgn then
                            local cleanText = sanitizeText(editorTexts[idx])
                            r.SetProjectMarkerByIndex(0, idx - 1, isrgn, pos, rgnend, markrgnindexnumber, cleanText, 0)
                            r.UpdateArrange()
                        end
                    end
                end
                editorOpen = false
                editorFirstFrame = nil
                editorWrappedTexts = {} -- Clear wrapped texts
                itemsCacheData.items = {}
                itemsCacheData.lastUpdate = 0
            end
            
            ImGui.SameLine(ctx)
            
            -- Cancel button with different color
            ImGui.PushStyleColor(ctx, ImGui.Col_Button, 0x666666FF)
            ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, 0x777777FF)
            ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, 0x555555FF)
            
            if ImGui.Button(ctx, "Cancel", buttonWidth, 26) then
                editorOpen = false
                editorFirstFrame = nil
                editorWrappedTexts = {} -- Clear wrapped texts
            end
            
            ImGui.PopStyleColor(ctx, 3)
            
            -- Keyboard shortcuts
            if ImGui.IsKeyPressed(ctx, ImGui.Key_Escape) then
                editorOpen = false
                editorFirstFrame = nil
                editorWrappedTexts = {} -- Clear wrapped texts
            elseif ImGui.IsKeyDown(ctx, ImGui.Key_LeftCtrl) and ImGui.IsKeyPressed(ctx, ImGui.Key_Enter) then
                -- Ctrl+Enter to apply
                for _, idx in ipairs(editingIndices) do
                    if editorTexts[idx] then
                        local retval, isrgn, pos, rgnend, name, markrgnindexnumber = r.EnumProjectMarkers(idx - 1)
                        if isrgn then
                            local cleanText = sanitizeText(editorTexts[idx])
                            r.SetProjectMarkerByIndex(0, idx - 1, isrgn, pos, rgnend, markrgnindexnumber, cleanText, 0)
                            r.UpdateArrange()
                        end
                    end
                end
                editorOpen = false
                editorFirstFrame = nil
                editorWrappedTexts = {} -- Clear wrapped texts
                itemsCacheData.items = {}
                itemsCacheData.lastUpdate = 0
            end
            
            ImGui.PopFont(ctx)
        end
        
        ImGui.End(ctx)
        
        -- Pop all style modifications
        ImGui.PopStyleColor(ctx, 8)
        ImGui.PopStyleVar(ctx, 5)
    end

    return {
        cachedRegions = cachedRegions,
        cachedRegionsTime = cachedRegionsTime,
        editorOpen = editorOpen,
        editorFirstFrame = editorFirstFrame,
        editorTexts = editorTexts
    }
end

function draw_progress_subtitles(activeIndices, regions, cursor_pos)
    if #activeIndices > 0 then
        local draw_list = reaper.ImGui_GetForegroundDrawList(ctx)
        local win_pos_x, win_pos_y = ImGui.GetWindowPos(ctx)
        local win_size_x, win_size_y = ImGui.GetWindowSize(ctx)
        local margin = 10
        local bar_height = 15
        for j, index in ipairs(activeIndices) do
            local activeRegion = regions[index]
            if activeRegion then
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
                
                ImGui.DrawList_AddRectFilled(draw_list, bar_x1, bar_y1, bar_x2, bar_y2, bar_color, 0, 0)
                local progress_x = bar_x1 + (bar_x2 - bar_x1) * progress
                ImGui.DrawList_AddRectFilled(draw_list, bar_x1, bar_y1, progress_x, bar_y2, progress_color, 0, 0)
            end
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
        -- Цвета тегов остаются постоянными
        COLOR_ERROR = 0xFF4444FF
        COLOR_NOTE = 0x44FF44FF
        COLOR_ERROR_FRAME = 0xFF0000FF
        COLOR_NOTE_FRAME = 0x00FF00FF
    else
        COLOR_ACTIVE   = 0xFFFFFFFF
        COLOR_NEIGHBOR = 0x5a5a5aFF
        COLOR_INACTIVE = 0x3a3a3aFF
        WINDOW_BG      = 0x1c1c1cFF
        -- Цвета тегов остаются постоянными
        COLOR_ERROR = 0xFF4444FF
        COLOR_NOTE = 0x44FF44FF
        COLOR_ERROR_FRAME = 0xFF0000FF
        COLOR_NOTE_FRAME = 0x00FF00FF
    end
end

apply_theme()
if showProgressBar == nil then showProgressBar = false end
if font2_attached == nil then font2_attached = false end

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
    -- Используем прямой доступ к региону по его позиции
    if region and region.start then
        local num_regions = reaper.CountProjectMarkers(0)
        
        for i = 0, num_regions - 1 do
            local retval, isrgn, pos, rgnend, name, markrgnindexnumber = reaper.EnumProjectMarkers(i)
            if isrgn and math.abs(pos - region.start) < 0.001 then  -- сравниваем позиции с допуском
                reaper.SetProjectMarkerByIndex(0, i, isrgn, pos, rgnend, markrgnindexnumber, newName, 0)
                reaper.UpdateArrange()
                return true
            end
        end
    end
    
    -- Фолбэк - старая логика по курсору
    local cursor_pos = reaper.GetCursorPosition()
    local num_regions = reaper.CountProjectMarkers(0)
    
    for i = 0, num_regions - 1 do
        local retval, isrgn, pos, rgnend, name, markrgnindexnumber = reaper.EnumProjectMarkers(i)
        if isrgn and cursor_pos >= pos and cursor_pos <= rgnend then
            reaper.SetProjectMarkerByIndex(0, i, isrgn, pos, rgnend, markrgnindexnumber, newName, 0)
            reaper.UpdateArrange()
            return true
        end
    end
    
    return false
end

local custom_alphabet = "АБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯабвгдеёжзийклмнопрстуфхцчшщъыьэюя"
local lookup = {}
local index = 1
for _, code in utf8.codes(custom_alphabet) do
    local ch = utf8.char(code)
    lookup[ch] = utf8.char(160 + index)
    index = index + 1
end

local function safe_utf8_text(text)
    local len = #text
    local i = 1
    local clean = {}
    while i <= len do
        local byte1 = text:byte(i)
        local cp, valid = nil, false
        if byte1 < 0x80 then
            cp = text:sub(i, i)
            valid = true
            i = i + 1
        elseif byte1 >= 0xC2 and byte1 <= 0xDF and i + 1 <= len then
            local byte2 = text:byte(i + 1)
            if byte2 >= 0x80 and byte2 <= 0xBF then
                cp = text:sub(i, i + 1)
                valid = true
                i = i + 2
            else
                i = i + 1
            end
        elseif byte1 >= 0xE0 and byte1 <= 0xEF and i + 2 <= len then
            local byte2 = text:byte(i + 1)
            local byte3 = text:byte(i + 2)
            if byte2 >= 0x80 and byte2 <= 0xBF and byte3 >= 0x80 and byte3 <= 0xBF then
                cp = text:sub(i, i + 2)
                valid = true
                i = i + 3
            else
                i = i + 1
            end
        elseif byte1 >= 0xF0 and byte1 <= 0xF4 and i + 3 <= len then
            local byte2 = text:byte(i + 1)
            local byte3 = text:byte(i + 2)
            local byte4 = text:byte(i + 3)
            if byte2 >= 0x80 and byte2 <= 0xBF and byte3 >= 0x80 and byte3 <= 0xBF and byte4 >= 0x80 and byte4 <= 0xBF then
                cp = text:sub(i, i + 3)
                valid = true
                i = i + 4
            else
                i = i + 1
            end
        else
            i = i + 1
        end
        if valid then
            clean[#clean + 1] = cp
        end
    end
    return table.concat(clean)
end

-- ИСПРАВЛЕНИЕ УТЕЧКИ: Ограниченный кеш трансформации
local transform_measure_cache = {}
local transform_cache_count = 0
local function transformAndMeasure(text)
    if not text then return "", 0 end
    
    if transform_measure_cache[text] then
        return transform_measure_cache[text].trans, transform_measure_cache[text].width
    end
    
    -- Очищаем кеш при достижении лимита
    if transform_cache_count > MAX_CACHE_SIZE then
        transform_measure_cache = {}
        transform_cache_count = 0
    end
    
    local parts = {}
    text = safe_utf8_text(text)
    
    for _, code in utf8.codes(text) do
        local ch = utf8.char(code)
        table.insert(parts, lookup[ch] or ch)
    end
    
    local trans = table.concat(parts)
    local width = select(1, ImGui.CalcTextSize(ctx, trans))
    transform_measure_cache[text] = { trans = trans, width = width }
    transform_cache_count = transform_cache_count + 1
    return trans, width
end

function f.get_markers_and_regions()
    local items = {}
    local count = reaper.CountProjectMarkers(0)
    for i = 0, count - 1 do
        local retval, isrgn, pos, rgnend, name = reaper.EnumProjectMarkers3(0, i)
        name = name:gsub("%-", " ")
        if isrgn then 
            items[#items+1] = { type = "region", start = pos, endPos = rgnend, name = name }
        else
            items[#items+1] = { type = "marker", start = pos, name = name }
        end
    end
    table.sort(items, function(a, b) return a.start < b.start end)

    local projectLength = reaper.GetProjectLength(0)
    for i, item in ipairs(items) do
        if item.type == "marker" then
            local nextStart = (items[i+1] and items[i+1].start) or projectLength
            item.endPos = nextStart
        end
    end
    return items
end

local function filter_markers(items)
    local filtered = {}
    for _, item in ipairs(items) do
        if item.type == "marker" then
            -- Проверяем наличие специальных тегов
            local tagType = checkSpecialTags(item.name)
            
            if tagType then
                -- Маркеры с тегами всегда включаем
                table.insert(filtered, item)
            else
                -- Обычная логика для маркеров без тегов
                local insideRegion = false
                for _, r in ipairs(items) do
                    if r.type == "region" and item.start > r.start and item.start < r.endPos then
                        insideRegion = true
                        break
                    end
                end
                if not insideRegion then
                    table.insert(filtered, item)
                end
            end
        else
            table.insert(filtered, item)
        end
    end
    return filtered
end

-- Оптимизированное получение элементов БЕЗ асинхронности
function get_cached_items(dynamicInterval)
    local now = r.time_precise()
    if not itemsCacheData.items or #itemsCacheData.items == 0 or (now - itemsCacheData.lastUpdate > itemsCacheData.updateInterval) then
        local freshItems = f.get_markers_and_regions()
        itemsCacheData.items = filter_markers(freshItems)
        itemsCacheData.lastUpdate = now
    end
    return itemsCacheData.items
end

duplicateWindowActive = duplicateWindowActive or false
mainScrollY = mainScrollY or 0
dupScrollY   = dupScrollY or 0

function showContextMenu(ctx)
    if ImGui.BeginPopupContextWindow(ctx, "context_menu") then
        if ImGui.MenuItem(ctx, "Import subtitles (.srt or .ass)") then
            if srtass.importSubtitlesAsRegionsDialog() then
            end
            f.ToggleMarkerTrackMute()
        end
        if ImGui.MenuItem(ctx, "Export subtitles (.srt file)") then
            srtass.exportRegionsAsSRTDialog()
        end

        ImGui.Separator(ctx)
        if ImGui.MenuItem(ctx, "Show progress bar", nil, showProgressBar) then
            showProgressBar = not showProgressBar
            r.SetExtState("SubtitlesWindow", "showProgressBar", tostring(showProgressBar), true)
        end

        if ImGui.MenuItem(ctx, "Duplicate Window") then
            duplicateWindowActive = not duplicateWindowActive
        end

        ImGui.EndPopup(ctx)
    end
    return showProgressBar
end

-- ИСПРАВЛЕНИЕ УТЕЧКИ: Ограниченный кеш высот
function calculateWrappedTextHeight(ctx, text, wrap_width)
    if not text or text == "" then return { height = 20, lines = {""}, lineHeight = 20, extraSpacing = 0 } end
    
    wrap_width = wrap_width or ImGui.GetContentRegionAvail(ctx)
    local lineHeight = select(2, ImGui.CalcTextSize(ctx, "Ag"))
    local extraSpacing = lineHeight * 0.3
    local lines = {}

    for originalLine in text:gmatch("[^\r\n]+") do
        local words = {}
        for word in originalLine:gmatch("%S+") do
            table.insert(words, word)
        end
        local currentLine = ""
        for _, word in ipairs(words) do
            local candidate = (currentLine == "") and word or (currentLine .. " " .. word)
            local _, candidateWidth = transformAndMeasure(candidate)
            if candidateWidth > wrap_width and currentLine ~= "" then
                table.insert(lines, currentLine)
                currentLine = word
            else
                currentLine = candidate
            end
        end
        if currentLine ~= "" then
            table.insert(lines, currentLine)
        end
    end

    if #lines == 0 then lines = {""} end
    
    local totalHeight = #lines * lineHeight + (#lines - 1) * extraSpacing
    return { height = totalHeight, lines = lines, lineHeight = lineHeight, extraSpacing = extraSpacing }
end

local function draw_centered_wrapped_text(ctx, text, wrap_width, cachedData)
    if not cachedData or not cachedData.lines then return 0 end
    
    wrap_width = wrap_width or ImGui.GetContentRegionAvail(ctx)
    local startX = ImGui.GetCursorPosX(ctx)
    local startY = ImGui.GetCursorPosY(ctx)
    for i, line in ipairs(cachedData.lines) do
        local _, textWidth = transformAndMeasure(line)
        local offset = (wrap_width - textWidth) * 0.5
        offset = math.max(offset, 0)
        ImGui.SetCursorPos(ctx, startX + offset - 4, startY + (i - 1) * (cachedData.lineHeight + cachedData.extraSpacing))
        local trans_line, _ = transformAndMeasure(line)
        ImGui.Text(ctx, trans_line)
    end
    return cachedData.height
end

local function get_original_region_text_at_cursor()
    local cursor_pos = r.GetCursorPosition()
    local region_count = r.CountProjectMarkers(0)
    local regions_at_cursor = {}
    
    for i = 0, region_count - 1 do
        local retval, isrgn, pos, rgnend, name, markrgnindexnumber = r.EnumProjectMarkers(i)
        
        -- Проверяем, что это регион и курсор внутри него
        if isrgn and cursor_pos >= pos and cursor_pos <= rgnend then
            -- Добавляем +1 к индексу для соответствия с логикой основного скрипта
            table.insert(regions_at_cursor, {
                index = i + 1,
                original_name = name or "",
                pos = pos,
                rgnend = rgnend,
                markrgnindexnumber = markrgnindexnumber
            })
        end
    end
    
    return regions_at_cursor
end

-- ИСПРАВЛЕННАЯ функция определения видимых субтитров
local function getVisibleSubtitleIndices(subtitles, currentScrollY, windowHeight, textHeightsCache, avail_w)
    local visibleIndices = {}
    local BUFFER_COUNT = 5
    
    if #subtitles == 0 then return visibleIndices end
    
    local totalHeight = 0
    local positions = {}
    
    -- БЕЗОПАСНОЕ вычисление позиций с проверками
    for i, sub in ipairs(subtitles) do
        if sub then
            local cacheKey = get_cache_key(sub)
            if not textHeightsCache[cacheKey] then
                -- Очищаем кеш при достижении лимита
                if textHeightsCacheCount > MAX_CACHE_SIZE then
                    textHeightsCache = {}
                    textHeightsCacheCount = 0
                end
                textHeightsCache[cacheKey] = calculateWrappedTextHeight(ctx, sub.name, avail_w - 8)
                textHeightsCacheCount = textHeightsCacheCount + 1
            end
            
            local heightData = textHeightsCache[cacheKey]
            if heightData and heightData.height then
                positions[i] = totalHeight
                totalHeight = totalHeight + heightData.height + 5
            else
                positions[i] = totalHeight
                totalHeight = totalHeight + 40 + 5  -- фолбэк высота
            end
        end
    end
    
    local verticalOffset = (totalHeight < windowHeight) and ((windowHeight - totalHeight) * 0.5) or 0
    local visibleTop = currentScrollY - verticalOffset
    local visibleBottom = visibleTop + windowHeight
    
    local firstVisible, lastVisible = nil, nil
    
    -- БЕЗОПАСНЫЙ поиск видимых элементов
    for i, sub in ipairs(subtitles) do
        if sub and positions[i] then
            local subTop = positions[i]
            if subTop > visibleBottom then
                break  -- если элемент ниже видимой области, прерываем цикл
            end
            
            local cacheKey = get_cache_key(sub)
            local heightData = textHeightsCache[cacheKey]
            local height = (heightData and heightData.height) and heightData.height or 40
            local subBottom = subTop + height
            
            if subBottom >= visibleTop and subTop <= visibleBottom then
                if not firstVisible then firstVisible = i end
                lastVisible = i
            end
        end
    end
    
    if firstVisible and lastVisible then
        local startIdx = math.max(1, firstVisible - BUFFER_COUNT)
        local endIdx = math.min(#subtitles, lastVisible + BUFFER_COUNT)
        
        for i = startIdx, endIdx do
            table.insert(visibleIndices, i)
        end
    end
    
    return visibleIndices
end

local isFirstRun = true
function updateSharedData(avail_w, avail_h, cursor_pos)
    local now = r.time_precise()
    if now - sharedData.lastUpdate < 0.05 then return end -- 50ms
    
    sharedData.lastUpdate = now
    
    local items = get_cached_items()
    sharedData.subtitles = {}
    for _, item in ipairs(items) do
        if item then
            table.insert(sharedData.subtitles, {
                type   = item.type,
                start  = item.start,
                endPos = item.endPos,
                name   = item.name
            })
        end
    end
    
    -- Всегда пересчитываем активные субтитры для отслеживания изменений курсора
    local recalcData = (lastCursorPos ~= cursor_pos)
    
    -- Активные субтитры
    local activeIndices = {}
    for i, sub in ipairs(sharedData.subtitles) do
        if sub and cursor_pos >= sub.start and cursor_pos < sub.endPos then
            table.insert(activeIndices, i)
        end
    end
    sharedData.activeIndices = activeIndices
    
    -- Определяем целевой субтитр для скролла
    if recalcData then
        if #activeIndices > 0 then
            targetSubtitleIndex = activeIndices[1] -- берем первый активный
        elseif #sharedData.subtitles > 0 then
            -- Найти ближайший субтитр
            if cursor_pos <= sharedData.subtitles[1].start then
                targetSubtitleIndex = 1
            elseif cursor_pos >= sharedData.subtitles[#sharedData.subtitles].endPos then
                targetSubtitleIndex = #sharedData.subtitles
            else
                -- Найти следующий субтитр
                for i = 1, #sharedData.subtitles - 1 do
                    if sharedData.subtitles[i] and sharedData.subtitles[i+1] and 
                       cursor_pos > sharedData.subtitles[i].endPos and cursor_pos < sharedData.subtitles[i+1].start then
                        targetSubtitleIndex = i + 1  -- следующий субтитр
                        break
                    end
                end
            end
        end
    end
    
    -- Заменить этот блок в updateSharedData:
    if now - sharedData.lastColorUpdate > 0.03 then
        sharedData.lastColorUpdate = now
        
        for i, sub in ipairs(sharedData.subtitles) do
            if sub then
                local target = COLOR_INACTIVE
                
                -- Проверяем специальные теги
                local tagType = checkSpecialTags(sub.name)
                if tagType == "error" then
                    target = COLOR_ERROR
                elseif tagType == "note" then
                    target = COLOR_NOTE
                elseif isActive(i, sharedData.activeIndices) then
                    target = COLOR_ACTIVE
                elseif isNeighbor(i, sharedData.activeIndices) then
                    target = COLOR_NEIGHBOR
                elseif i == targetSubtitleIndex and #sharedData.activeIndices == 0 then
                    -- Подсвечиваем целевой субтитр во время скролла
                    target = COLOR_TARGET
                end
                
                if not regionColors[i] then
                    regionColors[i] = target
                else
                    local currentBrightness = fastGetBrightness(regionColors[i])
                    local targetBrightness = fastGetBrightness(target)
                    local factor = 0.1  -- darkenFactor
                    if targetBrightness > currentBrightness then
                        factor = 0.75  -- немного быстрее для целевого субтитра
                    end
                    regionColors[i] = fastLerpColor(regionColors[i], target, factor)
                end
            end
        end
    end
    
    -- Пересчитываем позиции только при изменении курсора или первом запуске
    if recalcData then
        sharedData.totalHeight = 0
        sharedData.regionCenters = {}
        
        for i, sub in ipairs(sharedData.subtitles) do
            if sub then
                local cacheKey = get_cache_key(sub)
                local heightData = textHeightsCache[cacheKey]
                if not heightData then
                    if textHeightsCacheCount > MAX_CACHE_SIZE then
                        textHeightsCache = {}
                        textHeightsCacheCount = 0
                    end
                    textHeightsCache[cacheKey] = calculateWrappedTextHeight(ctx, sub.name, avail_w - 8)
                    textHeightsCacheCount = textHeightsCacheCount + 1
                    heightData = textHeightsCache[cacheKey]
                end
                if heightData and heightData.height then
                    sharedData.totalHeight = sharedData.totalHeight + heightData.height + 5
                end
            end
        end
        
        local verticalOffset = 0
        if sharedData.totalHeight < avail_h then 
            verticalOffset = (avail_h - sharedData.totalHeight) * 0.5 
        end
        local currentY = verticalOffset
        
        for i, sub in ipairs(sharedData.subtitles) do
            if sub then
                local cacheKey = get_cache_key(sub)
                local heightData = textHeightsCache[cacheKey]
                if heightData and heightData.height then
                    sharedData.regionCenters[i] = currentY + heightData.height * 0.5
                    currentY = currentY + heightData.height + 5
                end
            end
        end
        
        cachedActiveIndices = activeIndices
        cachedRegionCenters = sharedData.regionCenters
        cachedTotalHeight = sharedData.totalHeight
        lastCursorPos = cursor_pos
    else
        sharedData.activeIndices = cachedActiveIndices or {}
        sharedData.regionCenters = cachedRegionCenters or {}
        sharedData.totalHeight = cachedTotalHeight or 0
    end
end

function drawSubtitlesWindow(windowTitle, scrollY, isMainWindow)
    ImGui.SetNextWindowSize(ctx, 640, 640, ImGui.Cond_FirstUseEver)
    ImGui.PushStyleColor(ctx, ImGui.Col_WindowBg, WINDOW_BG)
    
    -- Для дублирующего окна другой флаг
    local windowFlags = 0
    if not isMainWindow then
        windowFlags = ImGui.WindowFlags_NoCollapse
    end
    
    visible, open = ImGui.Begin(ctx, windowTitle, true, windowFlags)
    ImGui.PopStyleColor(ctx)

    if visible then
        local avail_w, avail_h = ImGui.GetContentRegionAvail(ctx)
        
        if lastAvailW ~= avail_w then
            textHeightsCache = {}
            textHeightsCacheCount = 0
            lastAvailW = avail_w
        end

        if ImGui.BeginChild(ctx, windowTitle.."ScrollingChild", avail_w, avail_h, 1,
             ImGui.WindowFlags_NoScrollWithMouse | ImGui.WindowFlags_NoScrollbar) then
            
            -- Кнопки только в главном окне
            if isMainWindow then
                local win_x, win_y = ImGui.GetWindowPos(ctx)
                local win_w, _ = ImGui.GetWindowSize(ctx)
                ImGui.SetCursorScreenPos(ctx, win_x + win_w - 40, win_y + 10)
                if ImGui.Button(ctx, "Col") then
                    theme = (theme == "default") and "alternative" or "default"
                    r.SetExtState("SubtitlesWindow", "theme", theme, true)
                    apply_theme()
                end

                showContextMenu(ctx)
            end
            
            ImGui.Dummy(ctx, 0, avail_h * 0.25)

            local fontPushed = false
            if font and r.ImGui_ValidatePtr(font, "ImGui_Font*") then
                ImGui.PushFont(ctx, font)
                fontPushed = true
            end

            local play_state = r.GetPlayState()
            local cursor_pos = ((play_state & 1) == 1) and r.GetPlayPosition() or r.GetCursorPosition()
            
            -- Обновляем общие данные только в главном окне
            if isMainWindow then
                updateSharedData(avail_w, avail_h, cursor_pos)
            end
            
            local subtitles = sharedData.subtitles
            local activeIndices = sharedData.activeIndices
            local regionCenters = sharedData.regionCenters
            local totalHeight = sharedData.totalHeight

if #activeIndices > 0 then
    local sum = 0
    local count = 0
    for _, idx in ipairs(activeIndices) do
        if regionCenters[idx] then
            sum = sum + regionCenters[idx]
            count = count + 1
        end
    end
    if count > 0 then
        local desiredCenter = sum / count
        local desiredScroll = desiredCenter - avail_h * 0.5
        local delta = desiredScroll - scrollY
        local smoothFactor = 0.35  -- уменьшенный фактор для более плавного движения (как в старой версии)
        scrollY = scrollY + delta * smoothFactor
        ImGui.SetScrollY(ctx, scrollY)
    end
elseif #subtitles > 0 then
    -- Логика для случаев, когда курсор находится между субтитрами
    local desiredCenter = nil
    if cursor_pos <= subtitles[1].start then
        desiredCenter = regionCenters[1]
    elseif cursor_pos >= subtitles[#subtitles].endPos then
        desiredCenter = regionCenters[#subtitles]
    else
        -- Интерполяция между субтитрами
        for i = 1, #subtitles - 1 do
            if subtitles[i] and subtitles[i+1] and 
               cursor_pos > subtitles[i].endPos and cursor_pos < subtitles[i+1].start then
                local t = (cursor_pos - subtitles[i].endPos) / (subtitles[i+1].start - subtitles[i].endPos)
                if regionCenters[i] and regionCenters[i+1] then
                    desiredCenter = regionCenters[i] * (1 - t) + regionCenters[i+1] * t
                end
                break
            end
        end
    end
    
    if desiredCenter then
        local desiredScroll = desiredCenter - avail_h * 0.5
        local delta = desiredScroll - scrollY
        local smoothFactor = 0.35  -- тот же фактор для плавности
        scrollY = scrollY + delta * smoothFactor
        ImGui.SetScrollY(ctx, scrollY)
    end
end

            -- Видимые субтитры
            local currentScrollY = ImGui.GetScrollY(ctx)
            local visibleIndices = getVisibleSubtitleIndices(subtitles, currentScrollY, avail_h, textHeightsCache, avail_w)
            
            local visibleSet = {}
            for _, idx in ipairs(visibleIndices) do
                visibleSet[idx] = true
            end

            local verticalOffset = (totalHeight < avail_h) and ((avail_h - totalHeight) * 0.5) or 0
            local currentY = verticalOffset
            
            for i, sub in ipairs(subtitles) do
                if sub then
                    local cacheKey = get_cache_key(sub)
                    local heightData = textHeightsCache[cacheKey]
                    
                    if heightData and heightData.height then
                        if visibleSet[i] then
                            ImGui.PushStyleColor(ctx, ImGui.Col_Text, regionColors[i] or COLOR_INACTIVE)
                            ImGui.SetCursorPosY(ctx, currentY)
                            draw_centered_wrapped_text(ctx, sub.name, avail_w - 8, heightData)
                            ImGui.PopStyleColor(ctx)
                        else
                            ImGui.SetCursorPosY(ctx, currentY)
                            ImGui.Dummy(ctx, avail_w, heightData.height)
                        end
                        currentY = currentY + heightData.height + 5
                    else
                        -- Фолбэк для случаев без данных о высоте
                        currentY = currentY + 45
                    end
                end
            end

            ImGui.Dummy(ctx, 0, avail_h * 0.25)
            if fontPushed then ImGui.PopFont(ctx) end
            ImGui.EndChild(ctx)

            if showProgressBar and isMainWindow then
                draw_progress_subtitles(activeIndices, subtitles, cursor_pos)
            end
            local function cleanQuotes(text)
                if not text then return "" end
                text = text:gsub("`", "'")   
                text = text:gsub("ʻ", "'")  
                text = text:gsub("'", "'")
                return text
            end
            if ImGui.IsMouseDoubleClicked(ctx, 0) and isMainWindow then
                local regions_at_cursor = get_original_region_text_at_cursor()
                
                if #regions_at_cursor > 0 then
                    editorOpen = true
                    local x,y =ImGui.GetMousePos(ctx)
                    ImGui.SetNextWindowPos(ctx, x - 240, y - 85)
                    
                    editingIndices = {}
                    editorTexts = {}
                    
                    for _, region_data in ipairs(regions_at_cursor) do
                        table.insert(editingIndices, region_data.index)
                        
                       -- editorTexts[region_data.index] = region_data.original_name
                        editorTexts[region_data.index] = cleanQuotes(region_data.original_name)
                    end
                end
            end
        end
        ImGui.End(ctx)
    end
    
    -- Закрытие дублирующего окна не влияет на основное
    if not isMainWindow and not visible then
        duplicateWindowActive = false
    end
    
    return scrollY
end

-- Периодическая очистка памяти
local lastMemoryCleanup = 0
function cleanupMemory()
    local now = r.time_precise()
    if now - lastMemoryCleanup > 60 then -- раз в минуту
        lastMemoryCleanup = now
        
        -- Очищаем большие кеши
        if cacheKeyCount > MAX_CACHE_SIZE * 0.8 then
            cacheKeyLookup = {}
            cacheKeyCount = 0
        end
        
        if transform_cache_count > MAX_CACHE_SIZE * 0.8 then
            transform_measure_cache = {}
            transform_cache_count = 0
        end
        
        if textHeightsCacheCount > MAX_CACHE_SIZE * 0.8 then
            textHeightsCache = {}
            textHeightsCacheCount = 0
        end
        
        collectgarbage("collect")
    end
end

local _,_,num_regs=r.CountProjectMarkers(-1)
local play_state = r.GetPlayState()
function main_loop()
    if num_regs >= 350 and not need_stop and (play_state & 1) == 1 then
        r.OnStopButton()
        need_stop = true
    end
    
    if not r.ImGui_ValidatePtr(ctx, "ImGui_Context*") then
        ctx = r.ImGui_CreateContext("Subtitles Window")
        reloadFont = true
        font2_attached = false
    end

    if reloadFont then
        font = ImGui.CreateFont(script_path..[[clnew.ttc]], fontSize)
        ImGui.Attach(ctx, font)
        reloadFont = false
        r.SetExtState("SubtitlesWindow", "fontSize", tostring(fontSize), true)
        textHeightsCache = {}
        textHeightsCacheCount = 0
    end

    -- Главное окно
    mainScrollY = drawSubtitlesWindow("Subtitles", mainScrollY, true)

    -- Дублирующее окно (использует те же данные)
    if duplicateWindowActive then
        dupScrollY = drawSubtitlesWindow("Subtitles (View Only)", dupScrollY, false)
    end

    if ImGui.IsKeyDown(ctx, ImGui.Key_LeftCtrl) then
        local wheel = ImGui.GetMouseWheel(ctx)
        if wheel ~= 0 then
            local newSize = math.max(8, fontSize + wheel * 2)
            if newSize ~= fontSize then
                fontSize = newSize
                reloadFont = true
                textHeightsCache = {}
                textHeightsCacheCount = 0
                lastCursorPos = nil
                transform_measure_cache = {}
                transform_cache_count = 0
            end
        end
    end

    if ImGui.IsMouseClicked(ctx, 0) then
        cachedItems = f.get_markers_and_regions()
        cachedItemsTime = r.time_precise()
    end

    local updatedData = processSubtitleEditor(ctx, editorOpen, editorFirstFrame, editingIndices, editorTexts, cachedItems, f, r, update_region_name)
    editorOpen = updatedData.editorOpen
    editorFirstFrame = updatedData.editorFirstFrame
    editorTexts = updatedData.editorTexts
    cachedItems = updatedData.cachedRegions
    checkNotesAndShowManager()
    -- Очистка памяти
    cleanupMemory()
    
    if open then
        r.defer(main_loop)
    end
end


local notesManagerShown = false
local lastNotesCheck = 0
local lastProject = nil

function checkNotesAndShowManager()
    local now = r.time_precise()
    local currentProject = r.EnumProjects(-1, "")
    if currentProject ~= lastProject then
        notesManagerShown = false
        lastNotesCheck = 0
        lastProject = currentProject
        itemsCacheData.items = {}
        itemsCacheData.lastUpdate = 0
        sharedData.subtitles = {}
        sharedData.lastUpdate = 0
        textHeightsCache = {}
        textHeightsCacheCount = 0
        transform_measure_cache = {}
        transform_cache_count = 0
        lastCursorPos = nil
        return
    end
    
    if notesManagerShown or (now - lastNotesCheck) < 5 or not f.IsCurrentProjectSubproject() then
        return
    end
    
    lastNotesCheck = now
    local freshItems = f.get_markers_and_regions()
    local filteredItems = filter_markers(freshItems)
    
    if not filteredItems or #filteredItems == 0 then 
        notesManagerShown = true
        return 
    end
    
    local errorCount, noteCount = 0, 0
    for _, item in ipairs(filteredItems) do
        if item and item.name then
            local upperText = item.name:upper()
            if upperText:find("#OSHIBKA") then
                errorCount = errorCount + 1
            elseif upperText:find("#ZAMETKA") then
                noteCount = noteCount + 1
            end
        end
    end
    
    if errorCount == 0 and noteCount == 0 then
        notesManagerShown = true
        return
    end
    
    local russianText = ""
    local uzbekText = ""
    
    if errorCount > 0 and noteCount > 0 then
        russianText = string.format("У вас %d ошибок и %d заметок.", errorCount, noteCount)
        uzbekText = string.format("Sizda %d xato va %d izoh bor.", errorCount, noteCount)
    elseif errorCount > 0 then
        russianText = string.format("У вас %d ошибок.", errorCount)
        uzbekText = string.format("Sizda %d xato bor.", errorCount)
    else
        russianText = string.format("У вас %d заметок.", noteCount)
        uzbekText = string.format("Sizda %d izoh bor.", noteCount)
    end
    
    local dialogText = russianText .. "\n" .. uzbekText .. "\n\nОткрыть менеджер заметок?\nIzohlar menejerini ochishni xohlaysizmi?"
    local result = r.ShowMessageBox(dialogText, "Менеджер заметок / Izohlar menejeri", 3)
    
    if result == 6 then
        local notesManagerPath = script_path .. 'mrtnz_Note manager.lua'
        local file = io.open(notesManagerPath, "r")
        if file then
            file:close()
            local command_id = reaper.AddRemoveReaScript(true, 0, notesManagerPath, true)
            if command_id ~= 0 then
                reaper.Main_OnCommand(command_id, 0)
            else
                reaper.ShowMessageBox("Не удалось зарегистрировать скрипт:\n" .. notesManagerPath, "Ошибка", 0)
            end
        else
            reaper.ShowMessageBox("Файл не найден:\n" .. notesManagerPath, "Ошибка", 0)
        end
    end
    
    notesManagerShown = true
end
r.atexit()
r.defer(main_loop)

