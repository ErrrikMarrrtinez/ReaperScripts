-- @description MIDI Chopper v1.21
-- @author mrtnz
-- @version 1.21
-- @about
--  ...
-- @changelog
--   - fix 
midiEditor = reaper.MIDIEditor_GetActive()
take = reaper.MIDIEditor_GetTake(midiEditor)
if not take or not reaper.TakeIsMIDI(take) then return end
--Chopper(Split notes) for midi editor
function table.serialize(obj)
  local lua = ""
  local t = type(obj)
  if t == "number" then
      lua = lua .. obj
  elseif t == "boolean" then
      lua = lua .. tostring(obj)
  elseif t == "string" then
      lua = lua .. string.format("%q", obj)
  elseif t == "table" then
      lua = lua .. "{\n"
  for k, v in pairs(obj) do
      lua = lua .. "[" .. table.serialize(k) .. "]=" .. table.serialize(v) .. ",\n"
  end
      lua = lua .. "}"
  elseif t == "nil" then
      return nil
  else
      error("can not serialize a " .. t .. " type.")
  end
  return lua
end
function table.unserialize(lua)
    local t = assert(load("return "..lua))()
    return t
end
function getNote(sel)
    local retval, selected, muted, startPos, endPos, channel, pitch, vel = reaper.MIDI_GetNote(take, sel)
    return {
        ["retval"]=retval,
        ["selected"]=selected,
        ["muted"]=muted,
        ["startPos"]=startPos,
        ["endPos"]=endPos,
        ["channel"]=channel,
        ["pitch"]=pitch,
        ["vel"]=vel,
        ["sel"]=sel
    }
end
function selNoteIterator()
    local sel=-1
    return function()
        sel=reaper.MIDI_EnumSelNotes(take, sel)
        if sel==-1 then return end
        return getNote(sel)
    end
end
function deleteSelectedNotes()
    local i = -1
    while true do 
        i = reaper.MIDI_EnumSelNotes(take, i)
        if i == -1 then 
            break 
        else 
            reaper.MIDI_DeleteNote(take, i) 
            i = i - 1 
        end 
    end 
end

local interp_functions = {
  quadratic = function(t, ofs) return (1 - ofs) * t + ofs * t * t end,
  cubic = function(t, ofs)
    if ofs < 0 then
      t = 1 - t
    end
    local t_cubed = t^3
    local result = (1 - math.abs(ofs)) * t + math.abs(ofs) * t_cubed
    if ofs < 0 then
      result = 1 - result
    end
    return result
  end
}



local interp_type='cubic'
local div=1
local ofs=0
local statesStack = {}


function getInterpolation(interp_type, t, ofs)
  local func = interp_functions[interp_type]
  if not func then
    return t
  end
  return func(t, ofs)
end

local tension = 0
local vel_param = 0
local invert_velocity = false
local invert_tension = false

function split(value, ofs, interp_type, useTick, tension, vel_param, invert_tension, invert_velocity)
  reaper.MIDI_DisableSort(take)
  
  local _, noteCount = reaper.MIDI_CountEvts(take)
  local notesToDelete = {}
  local notesToInsert = {}
  
  for i = 0, noteCount - 1 do
    local retval, selected, muted, startpos, endpos, chan, pitch, originalVel = reaper.MIDI_GetNote(take, i)
    if selected then
      local len = endpos - startpos
      local div = useTick and math.floor(len / value) or value
      
      if div > 1 then
        table.insert(notesToDelete, i)
        for j = 1, div do
          local t = (j - 1) / div
          local interp = getInterpolation(interp_type, t, ofs)
          local next_t = j / div
          local next_interp = getInterpolation(interp_type, next_t, ofs)
          local note_start = startpos + interp * len
          local note_end = startpos + next_interp * len

          -- Расчет индексов с учетом инверсии для tension и velocity
          local pitchIndex = (ofs >= 0) ~= invert_tension and j - 1 or div - j
          local newPitch = pitch - math.floor(pitchIndex * tension)

          local velChange = math.floor((originalVel - 1) * vel_param)
          local velIndex = (ofs >= 0) ~= invert_velocity and j - 1 or div - j
          local newVel = originalVel - math.floor(velChange * (velIndex / (div - 1)))
          newVel = math.max(1, newVel)

          table.insert(notesToInsert, {true, muted, note_start, note_end, chan, newPitch, newVel})
        end
      end
    end
  end
   
  for _, noteIdx in ipairs(notesToDelete) do
       reaper.MIDI_DeleteNote(take, noteIdx)
  end
  for _, noteData in ipairs(notesToInsert) do
       reaper.MIDI_InsertNote(take, table.unpack(noteData))
  end
  reaper.MIDI_Sort(take)
   
  return
end




local originalState = nil

-- Функция для сохранения исходного состояния
function saveOriginalState()
    local notes = {}
    for note in selNoteIterator() do
        table.insert(notes, note)
    end
    originalState = table.serialize(notes)
end

-- Измененная функция pushState, которая теперь сохраняет текущее состояние
function pushState()
    local notes = {}
    for note in selNoteIterator() do
        table.insert(notes, note)
    end
    table.insert(statesStack, table.serialize(notes))
end

-- Измененная функция popState
function popState()
    if #statesStack > 0 then
        local notesData = table.remove(statesStack)
        deleteSelectedNotes()
        local notes = table.unserialize(notesData)
        for _, note in ipairs(notes) do
            reaper.MIDI_InsertNote(take, note.selected, note.muted, note.startPos, note.endPos, note.channel, note.pitch, note.vel, false)
        end
        reaper.MIDI_Sort(take)
    end
end

-- Измененная функция run
function run(useTick)
    -- Возвращаемся к исходному состоянию перед применением split
    if originalState then
        deleteSelectedNotes()
        local notes = table.unserialize(originalState)
        for _, note in ipairs(notes) do
            reaper.MIDI_InsertNote(take, note.selected, note.muted, note.startPos, note.endPos, note.channel, note.pitch, note.vel, false)
        end
        reaper.MIDI_Sort(take)
    end

    pushState() -- сохраняем текущее состояние
    split(div, ofs, interp_type, useTick, tension, vel_param, invert_tension, invert_velocity)
    reaper.UpdateArrange()
end
saveOriginalState()



function hex_to_rgba(hex)
    hex = hex:gsub("#","")
    if #hex == 6 then hex = hex .. "FF" end
    local a, r, g, b = tonumber(hex:sub(1, 2), 16) or 255, tonumber(hex:sub(3, 4), 16), tonumber(hex:sub(5, 6), 16), tonumber(hex:sub(7, 8), 16)
    return ((a << 24) | (r << 16) | (g << 8) | b)
end



function makeDarker(color, amount)
    local r, g, b = color:match("#(%x%x)(%x%x)(%x%x)")
    r = math.floor(math.max(0, tonumber(r, 16) * (1 - amount)))
    g = math.floor(math.max(0, tonumber(g, 16) * (1 - amount)))
    b = math.floor(math.max(0, tonumber(b, 16) * (1 - amount)))
    return string.format("#%02x%02x%02x", r, g, b)
end

--[[
local col_window_bg = hex_to_rgba("#1b1b1b")
local col_title_bg_active = hex_to_rgba("#333333")
local color_border = hex_to_rgba("#FFFFFF")
]]
theme_path = reaper.GetLastColorThemeFile()

function GetAllThemeColors(themePath)
  local colors = {}
  -- Add all the color identifiers you're interested in here.
  local color_identifiers = {
    "col_main_bg2",
    "col_main_bg",
    "col_main_text",
    "col_main_text2",
    "col_main_textshadow",
    "col_main_editbk",
    "col_main_buttonbg",
  }
  
  for _, color_id in ipairs(color_identifiers) do
    local colorval = reaper.GetThemeColor(color_id)
    if colorval and colorval ~= -1 then  -- -1 means the color is not defined
      -- Convert the number to hex and ensure it's in the format RRGGBB
      local hexcolor = string.format("%06x", colorval & 0xFFFFFF)
      colors[color_id] = hexcolor
    end
  end
  return colors
end

local colors = GetAllThemeColors(theme_path)  -- Get all theme colors without reloading the theme

local col_window_bg = colors["col_main_bg"] and hex_to_rgba('#' .. colors["col_main_editbk"]) or hex_to_rgba("#1b1b1b")
local col_title_bg_active = colors["col_main_bg2"] and hex_to_rgba('#' .. colors["col_main_bg"]) or hex_to_rgba("#333333")
local color_border = col_title_bg_active
local color_button_normal = "#586871"
local color_slider_normal = "#5a5a5a"
local color_grab_normal = "#2c8a75"

local slider_ofs_value = 0
local slider_div_value = 64
local cursor_hidden = false -- Флаг для отслеживания состояния курсора
local mouse_was_released = false -- Флаг для отслеживания отпускания кнопки мыши

local need_to_set_mouse_position = false
local stored_mouse_x = nil
local stored_mouse_y = nil
local useAverage = false
local grid_values = {1920, 1280, 960, 640, 480, 320, 240, 160, 120, 80, 60, 30}


function MouseCursorBusy(enable)
    local hwnd = reaper.JS_Window_FindTop(title, true)
    if enable then
        reaper.JS_Mouse_SetCursor(reaper.JS_Mouse_LoadCursor(10002)) -- Курсор "песочные часы"
        reaper.JS_WindowMessage_Intercept(hwnd, "WM_SETCURSOR", false)
    else
        reaper.JS_Mouse_SetCursor(reaper.JS_Mouse_LoadCursor(32512)) -- Курсор "пустышка"
        reaper.JS_WindowMessage_Release(hwnd, "WM_SETCURSOR")
    end
end


function CustomButton(ctx, label, normal_color, hover_color, active_color, width, height)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), hex_to_rgba(normal_color))
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), hex_to_rgba(hover_color))
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), hex_to_rgba(active_color))
    
    if width and height then
        -- Устанавливаем ширину и высоту кнопки перед ее созданием
        local rv = reaper.ImGui_Button(ctx, label, width, height)
        reaper.ImGui_PopStyleColor(ctx, 3)
        return rv
    else
        -- Если ширина и высота не указаны, рисуем кнопку без фиксированного размера
        local rv = reaper.ImGui_Button(ctx, label)
        reaper.ImGui_PopStyleColor(ctx, 3)
        return rv
    end
end


local slider_width = 200
function CustomSlider(ctx, label, value, min_value, max_value, normal_color, hover_color, active_color, grab_normal_color, grab_active_color)
    reaper.ImGui_SetNextItemWidth(ctx, slider_width)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBg(), hex_to_rgba(normal_color))
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBgHovered(), hex_to_rgba(hover_color))
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBgActive(), hex_to_rgba(active_color))
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_SliderGrab(), hex_to_rgba(grab_normal_color))
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_SliderGrabActive(), hex_to_rgba(makeDarker(grab_normal_color, -0.55)))

    local rv, new_value = reaper.ImGui_SliderDouble(ctx, label, value, min_value, max_value)
    local item_active = reaper.ImGui_IsItemActive(ctx)

    if item_active and reaper.ImGui_IsMouseDown(ctx, 0) then
        reaper.ImGui_SetMouseCursor(ctx, -1) -- Установка невидимого курсора
    elseif item_active and reaper.ImGui_IsMouseReleased(ctx, 0) then
        reaper.ImGui_SetMouseCursor(ctx, 0) -- Установка обычного курсора (стрелка)
    end

    reaper.ImGui_PopStyleColor(ctx, 5)
    return rv, new_value
end


local title = 'MIDI Chopper'
local ctx = reaper.ImGui_CreateContext(title)
local font_main = reaper.ImGui_CreateFont("Palatino Linotype", 14)
local font_button = reaper.ImGui_CreateFont("Textile", 15)
local window_flags = reaper.ImGui_WindowFlags_NoCollapse()















local function loop()
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowRounding(), 10)
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FrameRounding(), 5)
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_GrabRounding(), 5)
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_Alpha(), 22)
    reaper.ImGui_PushFont(ctx, font_main)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_WindowBg(), col_window_bg)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_TitleBgActive(), col_title_bg_active)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Border(), color_border)
    
    local visible, open = reaper.ImGui_Begin(ctx, title, true, window_flags)
    
    if visible then
        local rv1, rv2, useAverage = false, false, false
    
        reaper.ImGui_PushFont(ctx, font_button)
    
        -- Цвета и их модификации
        local sliderColor = color_slider_normal
        local sliderColorDarker1 = makeDarker(sliderColor, -0.1)
        local sliderColorDarker2 = makeDarker(sliderColor, -0.25)
        local grabColor = color_grab_normal
        local grabColorDarker = makeDarker(grabColor, -0.55)
    
        local buttonColor = color_button_normal
        local buttonColorDarker1 = makeDarker(buttonColor, -0.2)
        local buttonColorDarker2 = makeDarker(buttonColor, -0.3)
    
        -- Создание слайдеров
        
        reaper.ImGui_Text(ctx, "Split")
        rv2, slider_div_value = CustomSlider(ctx, '##split', slider_div_value, 1, 128, sliderColor, sliderColorDarker1, sliderColorDarker2, grabColor, makeDarker(grabColor, -0.40))
        
        reaper.ImGui_Text(ctx, "Offset")
        rv1, slider_ofs_value = CustomSlider(ctx, '##offset', slider_ofs_value, -1, 1, sliderColor, sliderColorDarker1, sliderColorDarker2, grabColor, grabColorDarker)
        reaper.ImGui_SameLine(ctx)  -- Это помещает следующую кнопку на ту же линию, что и слайдер
        button_change_interp = CustomButton(ctx, interp_type, buttonColor, buttonColorDarker1, buttonColorDarker2, 60, 20)
        
        -- Теперь группируем слайдер Tension и кнопку Invert Tension вместе
        reaper.ImGui_BeginGroup(ctx)
        reaper.ImGui_Text(ctx, "Tension")
        rv3, slider_tension_value = CustomSlider(ctx, '##tension', slider_tension_value, 0, 1, sliderColor, sliderColorDarker1, sliderColorDarker2, grabColor, grabColorDarker)
        reaper.ImGui_SameLine(ctx)
        button_invert_tension = CustomButton(ctx, 'Invert ' .. (invert_tension and 'on' or 'off'), buttonColor, buttonColorDarker1, buttonColorDarker2)
        reaper.ImGui_EndGroup(ctx)
        
        reaper.ImGui_BeginGroup(ctx)
        reaper.ImGui_Text(ctx, "Velocity")
        rv4, slider_vel = CustomSlider(ctx, '##velocity', slider_vel, 0, 1, sliderColor, sliderColorDarker1, sliderColorDarker2, grabColor, grabColorDarker)
        reaper.ImGui_SameLine(ctx)
        button_invert_velocity = CustomButton(ctx, 'Invert ' .. (invert_velocity and 'on ' or 'off '), buttonColor, buttonColorDarker1, buttonColorDarker2)
        reaper.ImGui_EndGroup(ctx)
        local offset_y = 10
        reaper.ImGui_BeginGroup(ctx)
        reaper.ImGui_SetCursorPosY(ctx, reaper.ImGui_GetCursorPosY(ctx) + offset_y)
        button_get_note = CustomButton(ctx, 'Get Note', buttonColor, buttonColorDarker1, buttonColorDarker2,80,35)
        reaper.ImGui_EndGroup(ctx)
        
        local stateChanged = false
    
        -- Обработка событий
        if button_invert_tension then
            invert_tension = not invert_tension
            stateChanged = true
        elseif button_invert_velocity then
            invert_velocity = not invert_velocity
            stateChanged = true
        elseif button_get_note then
            saveOriginalState()
            slider_div_value=64
            slider_ofs_value=0
            slider_vel=0
            slider_tension_value=0
        elseif button_change_interp then
            interp_type = interp_type == 'cubic' and 'quadratic' or 'cubic' -- Переключение между 'cubic' и 'quadratic'
            stateChanged = true
        elseif rv4 then
            vel_param = slider_vel
            stateChanged = true
        elseif rv3 then
            tension = slider_tension_value
            stateChanged = true
        elseif rv1 then
            ofs = slider_ofs_value
            stateChanged = true
        elseif rv2 then
            stateChanged = true
            if slider_div_value >= 64 then
                div = math.floor((slider_div_value - 64) * (128 / 64))
            else
                local index = math.floor((64 - slider_div_value) / (64 / (#grid_values * 2 - 1))) + 1
                div = useAverage and index % 2 == 0 and index / 2 < #grid_values and math.floor((grid_values[index / 2] + grid_values[index / 2 + 1]) / 2) or grid_values[math.ceil(index / 2)]
            end
        end
    
        if stateChanged then
            run(slider_div_value < 64)
        end
    
        reaper.ImGui_PopFont(ctx)
        reaper.ImGui_End(ctx)
    end
    
    reaper.ImGui_PopStyleColor(ctx,3)
    reaper.ImGui_PopStyleVar(ctx, 4) 
    reaper.ImGui_PopFont(ctx)
    
    if open then reaper.defer(loop) end
end

reaper.ImGui_Attach(ctx, font_main)
reaper.ImGui_Attach(ctx, font_button)
reaper.defer(loop)

