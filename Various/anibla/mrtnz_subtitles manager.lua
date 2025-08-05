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
local needScrollToActive = false


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
        local textWidth = ImGui.CalcTextSize(ctx, line)
        local offset = (wrap_width - textWidth) * 0.5
        offset = math.max(offset, 0)
        ImGui.SetCursorPos(ctx, startX + offset - 4, startY + (i - 1) * (cachedData.lineHeight + cachedData.extraSpacing))
        ImGui.Text(ctx, line)
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

local function wrapTextForInput(ctx, text, maxWidth)
    if not text or text == "" then return text end
    
    -- Если уже есть ручные переносы - не трогаем их, только добавляем автопереносы
    local lines = {}
    for line in text:gmatch("[^\n]+") do
        if line == "" then 
            table.insert(lines, "")
        else
            -- Проверяем нужен ли автоперенос для этой строки
            local lineWidth = ImGui.CalcTextSize(ctx, line)
            if lineWidth <= maxWidth then
                table.insert(lines, line)
            else
                -- Добавляем автопереносы с специальным маркером
                local words = {}
                for word in line:gmatch("%S+") do
                    table.insert(words, word)
                end
                
                local currentLine = ""
                for _, word in ipairs(words) do
                    local testLine = (currentLine == "") and word or (currentLine .. " " .. word)
                    local testWidth = ImGui.CalcTextSize(ctx, testLine)
                    
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
        end
    end
    
    return table.concat(lines, "\n")
end
-- Новая функция для умного удаления только автопереносов
local function removeAutoWrapping(originalText, editedText, maxWidth, ctx)
    if not editedText or editedText == "" then return "" end
    
    -- Разбиваем текст на строки
    local editedLines = {}
    for line in editedText:gmatch("[^\n]*") do
        table.insert(editedLines, line)
    end
    
    -- Восстанавливаем исходные параграфы, убирая только автопереносы
    local result = {}
    local i = 1
    
    while i <= #editedLines do
        local paragraph = editedLines[i]
        i = i + 1
        
        -- Собираем строки в параграф пока не встретим пустую строку или конец
        while i <= #editedLines and editedLines[i] ~= "" do
            local nextLine = editedLines[i]
            local testCombined = paragraph .. " " .. nextLine
            local combinedWidth = ImGui.CalcTextSize(ctx, testCombined)
            
            -- Если объединенная строка помещается в ширину - это был автоперенос
            if combinedWidth <= maxWidth * 1.1 then -- небольшой запас
                paragraph = testCombined
            else
                -- Это скорее всего ручной перенос, начинаем новый параграф
                table.insert(result, paragraph)
                paragraph = nextLine
            end
            i = i + 1
        end
        
        table.insert(result, paragraph)
        
        -- Если была пустая строка - добавляем её (ручной перенос абзаца)
        if i <= #editedLines and editedLines[i] == "" then
            table.insert(result, "")
            i = i + 1
        end
    end
    
    return table.concat(result, "\n")
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

local scrollY = 0

function showContextMenu(ctx)
    if ImGui.BeginPopupContextWindow(ctx, "context_menu") then
        if ImGui.MenuItem(ctx, "Import subtitles (.srt or .ass)") then
            if srtass.importSubtitlesAsRegionsDialog() then
                needScrollToActive = true
                itemsCacheData.items = {}
                itemsCacheData.lastUpdate = 0
            end
            f.ToggleMarkerTrackMute()
        end
        if ImGui.MenuItem(ctx, "Export subtitles (.srt file)") then
            srtass.exportRegionsAsSRTDialog()
        end

        ImGui.Separator(ctx)


        ImGui.EndPopup(ctx)
    end
    return
end

-- ИСПРАВЛЕНИЕ УТЕЧКИ: Ограниченный кеш высот
function calculateWrappedTextHeight(ctx, text, wrap_width)
    if not text or text == "" then return { height = 20, lines = {""}, lineHeight = 20, extraSpacing = 0 } end
    
    wrap_width = wrap_width or ImGui.GetContentRegionAvail(ctx)
    local lineHeight = select(2, ImGui.CalcTextSize(ctx, "Ag"))
    local extraSpacing = 0
    local lines = {}

    for originalLine in text:gmatch("[^\r\n]+") do
        local words = {}
        for word in originalLine:gmatch("%S+") do
            table.insert(words, word)
        end
        local currentLine = ""
        for _, word in ipairs(words) do
            local candidate = (currentLine == "") and word or (currentLine .. " " .. word)
            local candidateWidth = ImGui.CalcTextSize(ctx, candidate)
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
        local textWidth = ImGui.CalcTextSize(ctx, line)
        local offset = (wrap_width - textWidth) * 0.5
        offset = math.max(offset, 0)
        ImGui.SetCursorPos(ctx, startX + offset - 4, startY + (i - 1) * (cachedData.lineHeight + cachedData.extraSpacing))
        ImGui.Text(ctx, line)
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
                totalHeight = totalHeight + heightData.height + 2
            else
                positions[i] = totalHeight
                totalHeight = totalHeight + 40 + 2  -- фолбэк высота
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
                    sharedData.totalHeight = sharedData.totalHeight + heightData.height + 2
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
                    currentY = currentY + heightData.height + 2
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

function drawSubtitlesWindow(windowTitle, scrollY)
    ImGui.SetNextWindowSize(ctx, 640, 640, ImGui.Cond_FirstUseEver)
    ImGui.PushStyleColor(ctx, ImGui.Col_WindowBg, WINDOW_BG)
    
    local windowFlags = 0
    
    visible, open = ImGui.Begin(ctx, windowTitle, true, windowFlags)
    ImGui.PopStyleColor(ctx)

    if visible then
        local avail_w, avail_h = ImGui.GetContentRegionAvail(ctx)
        
        if lastAvailW ~= avail_w then
            -- очищаем кеш высот
            textHeightsCache = {}
            textHeightsCacheCount = 0
        
            -- сбросить sharedData, чтобы пересчитать regionCenters
            sharedData.lastUpdate = 0
            lastCursorPos = nil
        
            lastAvailW = avail_w
            needScrollToActive = true
        end
        

        if ImGui.BeginChild(ctx, windowTitle.."ScrollingChild", avail_w, avail_h, 1,
             ImGui.WindowFlags_NoScrollWithMouse | ImGui.WindowFlags_NoScrollbar) then
            
            -- Кнопки
            local win_x, win_y = ImGui.GetWindowPos(ctx)
            local win_w, _ = ImGui.GetWindowSize(ctx)
            ImGui.SetCursorScreenPos(ctx, win_x + win_w - 40, win_y + 10)
            if ImGui.Button(ctx, "Col") then
                theme = (theme == "default") and "alternative" or "default"
                r.SetExtState("SubtitlesWindow", "theme", theme, true)
                apply_theme()
            end

            showContextMenu(ctx)
            
            ImGui.Dummy(ctx, 0, avail_h * 0.25)

            local fontPushed = false
            if font and r.ImGui_ValidatePtr(font, "ImGui_Font*") then
                ImGui.PushFont(ctx, font)
                fontPushed = true
            end

            local play_state = r.GetPlayState()
            local cursor_pos = ((play_state & 1) == 1) and r.GetPlayPosition() or r.GetCursorPosition()
            
            -- Обновляем общие данные
            updateSharedData(avail_w, avail_h, cursor_pos)
            
            
            
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

--[[ Принудительный скролл после импорта
if needScrollToActive and #activeIndices > 0 then
    local sum = 0
    reaper.ShowConsoleMsg('net')
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
        scrollY = desiredScroll
        ImGui.SetScrollY(ctx, desiredScroll)
        needScrollToActive = false
    end
end]]

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
                        currentY = currentY + heightData.height + 2
                    else
                        -- Фолбэк для случаев без данных о высоте
                        currentY = currentY + 45
                    end
                end
            end
            
            if needScrollToActive then
                -- если курсор на каком-то субтитре
                if #sharedData.activeIndices > 0 then
                    -- берем первый активный
                    local idx = sharedData.activeIndices[1]
                    local centerY = sharedData.regionCenters[idx] or 0
                    -- желаемая позиция scrollY, чтобы центр субтитра был по середине окна
                    scrollY = centerY - avail_h * 0.5
                    ImGui.SetScrollY(ctx, scrollY)
                end
                
                needScrollToActive = false
            end

            ImGui.Dummy(ctx, 0, avail_h * 0.25)
            if fontPushed then ImGui.PopFont(ctx) end
            ImGui.EndChild(ctx)

            
            local function cleanQuotes(text)
                if not text then return "" end
                text = text:gsub("`", "'")   
                text = text:gsub("ʻ", "'")  
                text = text:gsub("'", "'")
                text = text:gsub("’", "'")
                
                return text
            end
            
            if ImGui.IsMouseDoubleClicked(ctx, 0) then
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
    end

    if reloadFont then
        font = ImGui.CreateFont('Arial', fontSize)
        ImGui.Attach(ctx, font)
        reloadFont = false
        r.SetExtState("SubtitlesWindow", "fontSize", tostring(fontSize), true)
        textHeightsCache = {}
        textHeightsCacheCount = 0
    end

    -- Главное окно
    scrollY = drawSubtitlesWindow("Subtitles", scrollY)

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

-- Функция для получения заметок из проекта
function getProjectNotes()
    local notes = {}
    local prj = r.EnumProjects(-1)
    
    for i = 0, math.huge do
        local ok, k, v = r.EnumProjExtState(prj, 'Notes', i)
        if not ok then break end
        if v == "" then goto continue end
        
        local parts = {}
        for part in v:gmatch("([^|]*)") do
            table.insert(parts, part)
        end
        
        if #parts >= 7 then
            notes[k] = {
                recipient = parts[1] or "",
                content = parts[2] or "",
                audio_path = parts[3] or "",
                timestamp = parts[4] or tostring(r.time_precise()),
                region = parts[5] or "",
                marker_name = parts[6] or "",
                marker_pos = tonumber(parts[7]) or 0,
                completed = tonumber(parts[8]) or 0  -- Параметр completed
            }
        end
        ::continue::
    end
    
    return notes
end

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
        lastCursorPos = nil
        return
    end
    
    if notesManagerShown or (now - lastNotesCheck) < 5 or not f.IsCurrentProjectSubproject() then
        return
    end
    
    -- СОХРАНЯЕМ локальные состояния completed ПЕРЕД импортом
    local localCompletedStates = {}
    local existingNotes = getProjectNotes()
    for noteId, note in pairs(existingNotes) do
        if note.marker_name and note.marker_name ~= "" then
            localCompletedStates[note.marker_name] = note.completed
        end
    end
    
    -- связка двух функций 
    f.ImportMarkersFromParent(pname)
    f.ImportNotesFromParent()
    f.color_regions()
    -----
    
    -- ВОССТАНАВЛИВАЕМ локальные состояния completed ПОСЛЕ импорта
    local prj = r.EnumProjects(-1)
    for i = 0, math.huge do
        local ok, k, v = r.EnumProjExtState(prj, 'Notes', i)
        if not ok then break end
        if v == "" then goto continue end
        
        local parts = {}
        for part in v:gmatch("([^|]*)") do
            table.insert(parts, part)
        end
        
        if #parts >= 7 then
            local marker_name = parts[6] or ""
            -- Если у нас есть сохраненное локальное состояние для этой заметки
            if marker_name ~= "" and localCompletedStates[marker_name] ~= nil then
                -- Восстанавливаем локальное состояние completed
                parts[8] = tostring(localCompletedStates[marker_name])
                
                -- Пересохраняем заметку с восстановленным состоянием
                local updated_data = table.concat(parts, '|')
                r.SetProjExtState(prj, 'Notes', k, updated_data)
            end
        end
        ::continue::
    end
    
    lastNotesCheck = now
    
    -- Получаем заметки из проекта (уже с восстановленными состояниями)
    local projectNotes = getProjectNotes()
    
    -- Получаем маркеры и регионы
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
            local isError = upperText:find("#OSHIBKA")
            local isNote = upperText:find("#ZAMETKA")
            
            if isError or isNote then
                -- Ищем соответствующую заметку в projectNotes
                local noteFound = false
                local noteCompleted = false
                
                for noteId, note in pairs(projectNotes) do
                    if note.marker_name == item.name then
                        noteFound = true
                        noteCompleted = (note.completed == 1)
                        break
                    end
                end
                
                -- Считаем только если заметка не найдена или не выполнена
                if not noteFound or not noteCompleted then
                    if isError then
                        errorCount = errorCount + 1
                    elseif isNote then
                        noteCount = noteCount + 1
                    end
                end
            end
        end
    end
    
    -- Если все заметки выполнены, не показываем уведомление
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

