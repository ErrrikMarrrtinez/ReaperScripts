-- @description MVelocity Tool
-- @author mrtnz
-- @version 1.0.25
-- @about
--  ...
-- @changelog
--   - Fix font size for vertical sliders (overlap)




package.path = string.format('%s/Scripts/rtk/1/?.lua;%s?.lua;', reaper.GetResourcePath(), "")
local script_path = string.match(({reaper.get_action_context()})[2], "(.-)([^\\/]-%.?([^%.\\/]*))$")
package.path = package.path .. ";" .. script_path .. "../libs/?.lua"
local rtk = require("rtk")


initialW=415
initialH=400
local scale_2
main_background_color = "#1a1a1a"
local wnd = rtk.Window{
    w = initialW,
    h = initialH,
    title = 'MVelocity',
    bg = main_background_color,
    resizable=true,
    opacity=0.98,padding=8,
    
}
wnd:open()
wnd.onresize=function(self, w, h)
    scale_2 = math.min(w / initialW, h / initialH)
    rtk.scale.user = scale_2
    self:reflow()
end





main_line_color = "#5a5a5a"
SimpleSlider = rtk.class('SimpleSlider', rtk.Spacer)
SimpleSlider.register{
    value = rtk.Attribute{default=0.5},
    color = rtk.Attribute{type='color', default=main_line_color},
    minw = 5,
    h = 1.0,
    autofocus = true,
    min = rtk.Attribute{default=0},
    max = rtk.Attribute{default=1},
    ticklabels = rtk.Attribute{default=nil},
    text_color = rtk.Attribute{type='color', default='#ffffff'},
    align = rtk.Attribute{default='center'},
    valign = rtk.Attribute{default='top'},
    font = rtk.Attribute{default='arial'},
    fontsize = rtk.Attribute{default=18},
    target = rtk.Attribute{default='top'},
    
}

function SimpleSlider:initialize(attrs, ...)
    -- Добавьте следующую проверку, чтобы установить значение в соответствии с min и max.
    if attrs.value then
        local min_value = attrs.min or self.min
        local max_value = attrs.max or self.max
        local range = max_value - min_value
        local normalized_value = (attrs.value - min_value) / range
        attrs.value = rtk.clamp(normalized_value, 0, 1)
    end
    rtk.Spacer.initialize(self, attrs, SimpleSlider.attributes.defaults, ...)
end


--[[
function SimpleSlider:set_from_mouse_y(y)
    local h = self.calc.h - (y - self.clienty)
    local value = rtk.clamp(h / self.calc.h, 0, 1)
    local min_value = type(self.min) == "table" and self.min[1] or self.min
    local max_value = type(self.max) == "table" and self.max[1] or self.max
    local range = max_value - min_value
    self:animate{
        attr = 'value',
        dst = (value * range + min_value) / range,  -- Обновленный расчет dst
        duration = 0.0070
    }
end

]]
function SimpleSlider:set_from_mouse_y(y)
    local h = self.calc.h - (y - self.clienty)
    local value = rtk.clamp(h / self.calc.h, 0, 1)
    self:animate{
        attr = 'value',
        dst = value,
        duration = 0.0070
    }
end
function adjust_brightness(color, amount)
    local r, g, b = color:match("#(%x%x)(%x%x)(%x%x)")
    r = math.floor(math.min(255, math.max(0, tonumber(r, 16) * (1 + amount))))
    g = math.floor(math.min(255, math.max(0, tonumber(g, 16) * (1 + amount))))
    b = math.floor(math.min(255, math.max(0, tonumber(b, 16) * (1 + amount))))
    return string.format("#%02x%02x%02x", r, g, b)
end

function SimpleSlider:_handle_draw(offx, offy, alpha, event)
    local calc = self.calc
    local x = offx + calc.x
    local y = offy + calc.y
    local h = calc.h * calc.value
    
    self:setcolor(calc.color)
    gfx.a = 0.2
    gfx.rect(x, y, calc.w, calc.h)
    
    if self.target == 'top' then
        draw_h = h
        draw_y = y + calc.h - h
    elseif self.target == 'down' then
        draw_h = h
        draw_y = y
    elseif self.target == 'center' then
        local half_h = calc.h / 2
        draw_h = math.abs(h - half_h)
        
        gfx.a = 0.4
        gfx.rect(x, y + half_h, calc.w, 1)
    
        if calc.value >= 0.5 then
            draw_y = y + half_h - draw_h
        else
            draw_y = y + half_h
        end
    end
    
    local adjustedColor = adjust_brightness(calc.color, calc.value - 0.5)
    self:setcolor(adjustedColor)
    gfx.a = 1.0
    gfx.rect(x, draw_y, calc.w, draw_h)
    
    local fmt = type(self.min) == "table" and "%d%%" or "%d"
    --local text_to_display
    
    
    local min_value = type(self.min) == "table" and self.min[1] or self.min
    local max_value = type(self.max) == "table" and self.max[1] or self.max
    local range = max_value - min_value
    local displayed_value = min_value + calc.value * range
    local text_to_display = string.format("%d", math.floor(displayed_value))
    
    if self.ticklabels then
        local index = math.floor(calc.value * (#self.ticklabels - 1) + 0.5) + 1
        text_to_display = self.ticklabels[index]
    elseif type(self.min) == "table" and type(self.max) == "table" then
        text_to_display = string.format("%d%%", math.floor(calc.value * 100))
    else
        local min = type(self.min) == "table" and self.min[1] or self.min
        local max = type(self.max) == "table" and self.max[1] or self.max
        text_to_display = string.format("%d", math.floor(min + calc.value * (max - min)))
    end
    gfx.setfont(1, self.font, self.fontsize)

    local str_w, str_h = gfx.measurestr(text_to_display)
    
    if self.align == 'left' then
        gfx.x = x
    elseif self.align == 'center' then
        gfx.x = x + (calc.w - str_w) / 2
    else
        gfx.x = x + calc.w - str_w
    end

    if self.valign == 'top' then
        gfx.y = y
    else
        gfx.y = y + calc.h - str_h
    end
    
    self:setcolor(self.text_color)
    gfx.drawstr(text_to_display)
end


function round(num)
    return math.floor(num + 0.5)
end

-- Обновленный метод getDisplayValue
function SimpleSlider:getDisplayValue()
    local min_value = type(self.min) == "table" and self.min[1] or self.min
    local max_value = type(self.max) == "table" and self.max[1] or self.max
    local range = max_value - min_value
    local displayed_value = min_value + self.calc.value * range

    return string.format("%d", round(displayed_value))  -- Использование функции округления вместо math.floor
end



SliderGroup = rtk.class('SliderGroup', rtk.HBox)
local midi_editor = reaper.MIDIEditor_GetActive()


local first_slider_value = nil
local focused_slider = nil

function SliderGroup:_handle_mousedown(event, x, y, t)
end
















base_w_sliders=150
rand_color_slider="#36231f"
range_color_slider="#3e1718"

step_color_slider=1
steps_more_color_slider=2
font = Verdana
vertical_step_slider_colors=3
tracksizex = 14
base_font=Arial
base_b_color="#6c848c50"




local 







spacing_value = 5
local mainhb_b=wnd:add(rtk.HBox{y=8,spacing=2,x=10,halign='center'})
local icon_main = mainhb_b:add(rtk.Text{"⏺"})
local head_text = mainhb_b:add(rtk.Heading{y=-4,'MVelocity'})

local horison_line_widgets = wnd:add(rtk.HBox{y=18})
local line = horison_line_widgets:add(rtk.VBox{spacing=5,y=10,padding=10})
local vert_box_c1 = line:add(rtk.VBox{bg="#FFDAB96",border='#70809019'})
local vert_box_c2 = line:add(rtk.VBox{bg="#FFDAB96",border='#70809019'})
local vet_line_default2 = horison_line_widgets:add(rtk.VBox{padding=10})
local vertical_line_box = vet_line_default2:add(rtk.VBox{x=-15,y=10,padding=10,bg="#FFDAB96",border='#70809019'})






local shelf_1 = vert_box_c1:add(rtk.VBox{padding=10,spacing=spacing_value})
local shelf_2_2 = vert_box_c1:add(rtk.HBox{padding=10,spacing=spacing_value})
local shelf_2_3 = vert_box_c1:add(rtk.HBox{padding=10,spacing=spacing_value})

local shelf_3 = vert_box_c2:add(rtk.VBox{padding=10,spacing=1})
local shelf_comp_exp_txt = shelf_3:add(rtk.HBox{x=4,padding=10,spacing=18})
local shelf_comp_exp = shelf_3:add(rtk.HBox{})


local shelf_buttons = shelf_3:add(rtk.HBox{padding=10,spacing=10})



local txt_rand = shelf_1:add(rtk.Text{x=33,padding=5,'RANDOMIZE'})
local slider22 = shelf_1:add(rtk.Slider{
    value = 0,
    w = base_w_sliders,
    tooltip = 'ранд',
    thumbsize = 6,
    tracksize = tracksizex,
    trackcolor = '#b7b1b7',
    thumbcolor='transparent',
    color = rand_color_slider,
    ticks = false
})
local txt_rang = shelf_1:add(rtk.Text{font=font,x=49,padding=5,'RANGE'})
local shelf_1_1 = shelf_1:add(rtk.HBox{x=-1,spacing=1})
local min = shelf_1_1:add(rtk.Text{x=5, y=-2, z=1, '25', w=24})
local slider_range = shelf_1_1:add(rtk.Slider{
    value={10, 120},
    min=1,
    max=127,
    step=1,
    w = base_w_sliders - 50,
    thumbsize = 6,
    tracksize = tracksizex,
    trackcolor = '#b7b1b7',
    thumbcolor='transparent',
    tooltip='ранг',
    color = range_color_slider,
    ticks = false
})
local max = shelf_1_1:add(rtk.Text{font=font,y=-2,'120', w=24})

local btn_box_h=shelf_1:add(rtk.HBox{y=10,})
local buttonchik = btn_box_h:add(rtk.Button{
    color = base_b_color,
    font = base_font,
    halign = 'center',
    padding = 2,
    w = base_w_sliders,
    'UPDATE',
    
 
})


local label_slider_expand = shelf_comp_exp_txt:add(rtk.Text{'Expand'})
local label_slider_compress = shelf_comp_exp_txt:add(rtk.Text{'Compress'})
local slider_reduce = shelf_comp_exp:add(rtk.Slider{
    value = 50.01,
    w = base_w_sliders,
    tooltip = 'expand',
    thumbsize = 10,
    tracksize = tracksizex,
    trackcolor = '#b7b1b7',
    thumbcolor = '#422315',
    color = 'transparent',
    ticks = false,
})
local target_button_factor=shelf_buttons:add(rtk.Button{color = base_b_color,padding=4,tpadding=2,font=font,halign='center','FACTOR',w=60})
local target_button_target=shelf_buttons:add(rtk.Button{color = base_b_color,padding=4,tpadding=2,font=font,halign='center','TARGET',w=60})


local dragging = false
local currentValue = 80
local prevY = nil
local dragAccumulatorY = 5
local dragThreshold = 0.1
local sensitivity = 5 -- усиление движения
local targetExpandValues = {80}

target_button_target.ondragstart = function(self, event, x, y, t)
    dragging = true
    prevY = y
    self:attr("cursor", rtk.mouse.cursors.REAPER_MARKER_VERT)
    return true
end

target_button_target.ondragend = function(self, event, dragarg)
    dragging = false
    prevY = nil
    self:attr("cursor", rtk.mouse.cursors.UNDEFINED)
    targetExpandValues = {currentValue}  -- Обновляем массив при завершении перетаскивания
    slider_reduce:onchange()
end

target_button_target.onmousewheel = function(self, event)
    local _, _, _, wheel_y = tostring(event):find("wheel=(%d+.?%d*),(-?%d+.?%d*)")
    wheel_y = tonumber(wheel_y)
    currentValue = math.max(1, math.min(127, currentValue - wheel_y * sensitivity))  -- инвертировано
    self:attr('label', tostring(math.floor(currentValue)))  -- Убрана десятичная часть
    targetExpandValues = {currentValue}  -- Обновляем массив
    slider_reduce:onchange()
    return true
end

target_button_target.ondragmousemove = function(self, event, dragarg)
    if dragging and prevY then
        local deltaY = event.y - prevY
        dragAccumulatorY = dragAccumulatorY + deltaY
        if math.abs(dragAccumulatorY) > dragThreshold then
            currentValue = math.max(1, math.min(127, currentValue - math.floor(dragAccumulatorY / sensitivity)))
            self:attr('label', tostring(math.floor(currentValue)))  -- Убрана десятичная часть
            prevY = event.y
            dragAccumulatorY = 0
        end
    end
    slider_reduce:onchange()
end
local sensitivity = 1  -- чувствительность колеса мыши, можно настроить по желанию

slider_range.onmousewheel = function(self, event)
    local step = 12  -- Шаг изменения, можно поставить 15 если нужно
    local increment = event.wheel < 0 and step or -step  -- Знак изменен на противоположный

    if event.ctrl then
        -- Двигаем оба значения вместе
        local value1 = math.max(1, math.min(127, self.value[1] + increment))
        local value2 = math.max(1, math.min(127, self.value[2] + increment))
        self:attr('value', {value1, value2})
    elseif event.shift then
        -- Сужаем/расширяем диапазон, двигая оба предела
        local value1 = math.max(1, math.min(127, self.value[1] - increment))
        local value2 = math.max(1, math.min(127, self.value[2] + increment))
        self:attr('value', {value1, value2})
    end
end


slider_range.onclick = function(self, event)
    if event.button == rtk.mouse.BUTTON_RIGHT then
        self:attr('value', {1, 127})
    end
end

slider_reduce.onmousedown = function(self, event)
    --self:attr('thumbsize', 9)
    return true
end
slider_reduce.onmouseup = function(self, event)
    --self:attr('thumbsize', 10)
end
local window_interpolate_box = vertical_line_box:add(rtk.VBox{})




local shelf_3_3 = vet_line_default2:add(rtk.VBox{w=202,x=-15,h=200,bg="#FFDAB96",border='#70809019',padding=20,spacing=4,y=15})
local head_step = shelf_3_3:add(rtk.Text{x=28,font='Textile',fontsize=16,y=-7,"STEP VELOCITY"})
local horison_slider = shelf_3_3:add(rtk.HBox{bg="#302c3430",padding=3,border="#1a1a1a",x=-10,y=-2,spacing=6,})
local slider_gr = horison_slider:add(rtk.Slider{
    value = 0,
    w = base_w_sliders-40,
    tooltip = 'Gain',
    thumbsize = 10,
    y=2,
    x=-5,
    tracksize = tracksizex+2,
    trackcolor = '#b7b1b7',
    thumbcolor = 'transparent',
    color = '#401818',
    ticks = false,
})

aw_w = 28
local buttons_plus_minus=horison_slider:add(rtk.HBox{x=-9,spacing=2})
--local button_remove_sliders = buttons_plus_minus:add(rtk.Button{padding=2,halign='center',w=80,color =  "#886c9450","REMOVE"})
--local button_add_sliders =buttons_plus_minus:add(rtk.Button{padding=2,halign='center',w=80,color = "#886c9450","ADD"})
local button_remove_sliders = buttons_plus_minus:add(rtk.Button{padding=2,halign='center',"-",w=aw_w,h=aw_w-5,icon=remove,color =  base_b_color})
local button_add_sliders =buttons_plus_minus:add(rtk.Button{padding=2,halign='center',"+",w=aw_w,h=aw_w-5,icon=add,color = base_b_color})


local mini_sliders_box = vet_line_default2:add(rtk.HBox{})
local group = vet_line_default2:add(SliderGroup{y=-100,x=-4,w=182,h=100,spacing=1, expand=1})


local targetVelocitiesArray = {100, 20, 90, 25}

local sliders_dict = {}
local function handle_click(slider, event)
    local i = sliders_dict[slider]  -- Получаем индекс слайдера
    if i then
        local displayValue = slider:getDisplayValue()
        targetVelocitiesArray[i] = displayValue  -- Обновляем значение в массиве
        
        -- Проверка значения слайдера slider_gr перед вызовом onchange
        if slider_gr.value > 0 then
            slider_gr:onchange()
        end
    end
end
local sliders = {} 
local sliders_values = {} 

local slider_params = {
    color = '#381414',
    lhotzone = 5,
    font = 'Times',
    min = 1,
    max = 127,
    valign = 'down',
    text_color = "#ffffff",
    halign = 'left',
    w = base_w,
    lhotzone = 5,
    fontsize=14,
    rhotzone = 5,
}

local function add_slider()
    if #sliders < 10 then  -- Проверка на максимальное количество слайдеров
        local value = sliders_values[#sliders + 1] or 64  -- Используем значение по умолчанию 64, если сохраненное значение отсутствует
        slider_params.value = value  -- Устанавливаем значение для слайдера
        local mini_slider = group:add(SimpleSlider(slider_params), {fillw = true})
        table.insert(sliders, mini_slider)  -- Добавляем слайдер в массив
        sliders_dict[mini_slider] = #sliders  -- Обновляем словарь индексов
        mini_slider.onclick = handle_click  -- Назначаем handle_click обработчиком события onclick
        targetVelocitiesArray[#sliders] = value  -- Обновляем значение в массиве
    end
end
for i = 1, 4 do
    sliders_values[i] = targetVelocitiesArray[i]
    add_slider()
end
local function remove_slider()
    if #sliders > 0 then
        local mini_slider = table.remove(sliders)  -- Удаляем последний слайдер из массива
        sliders_dict[mini_slider] = nil  -- Удаляем слайдер из словаря
        sliders_values[#sliders + 1] = mini_slider:getDisplayValue()  -- Сохраняем значение слайдера
        group:remove(mini_slider)  -- Удаляем слайдер из группы
        table.remove(targetVelocitiesArray)  -- Удаляем последнее значение из массива
    end
end

button_add_sliders.onclick = add_slider 
button_remove_sliders.onclick = remove_slider 





local add_timer_running = false
local remove_timer_running = false

local add_last_time = 1
local remove_last_time = 0
local delay = 0.2  -- начальная задержка в секундах
local fast_delay = 0.05  -- ускоренная задержка в секундах

local add_call_count = 0
local remove_call_count = 0
local acceleration_threshold = 3

local function start_add_timer()
    add_timer_running = true
    add_call_count = 0  -- сброс счетчика вызовов при старте таймера
    local function timer()
        if add_timer_running then
            local current_time = reaper.time_precise()
            if current_time - add_last_time >= (add_call_count >= acceleration_threshold and fast_delay or delay) then
                add_slider()  -- Вызов функции add_slider
                add_last_time = current_time
                add_call_count = add_call_count + 1  -- увеличение счетчика вызовов
            end
            reaper.defer(timer)  -- Повторный вызов таймера через небольшой промежуток времени
        end
    end
    timer()  -- Запуск таймера
end

local function start_remove_timer()
    remove_timer_running = true
    remove_call_count = 0  -- сброс счетчика вызовов при старте таймера
    local function timer()
        if remove_timer_running then
            local current_time = reaper.time_precise()
            if current_time - remove_last_time >= (remove_call_count >= acceleration_threshold and fast_delay or delay) then
                remove_slider()  -- Вызов функции remove_slider
                remove_last_time = current_time
                remove_call_count = remove_call_count + 1  -- увеличение счетчика вызовов
            end
            reaper.defer(timer)  -- Повторный вызов таймера через небольшой промежуток времени
        end
    end
    timer()  -- Запуск таймера
end

-- Функции для остановки таймеров
local function stop_add_timer()
    add_timer_running = false
    add_call_count = 0  -- сброс счетчика вызовов при остановке таймера
end

local function stop_remove_timer()
    remove_timer_running = false
    remove_call_count = 0  -- сброс счетчика вызовов при остановке таймера
end

-- Определение обработчиков событий для кнопок
button_add_sliders.onlongpress = start_add_timer
button_remove_sliders.onlongpress = start_remove_timer

button_add_sliders.onmouseup = stop_add_timer
button_remove_sliders.onmouseup = stop_remove_timer












local midiEditor = reaper.MIDIEditor_GetActive()
if not midiEditor then return reaper.MB("No active MIDI Editor found", "Error", 0) end
local take = reaper.MIDIEditor_GetTake(midiEditor)
if not take then return reaper.MB("No take found in MIDI Editor", "Error", 0) end
local _, noteCount = reaper.MIDI_CountEvts(take)

local notesTable = {}

function storeInitialVelocities(take, noteCount)
    local velocities = {}
    for i = 0, noteCount - 1 do
        local _, _, _, _, _, _, _, vel = reaper.MIDI_GetNote(take, i)
        velocities[i + 1] = vel
    end
    return velocities
end
local initialVelocities = {}
local initialVelocities = storeInitialVelocities(take, noteCount)


local function updateTargetVelocitiesFromArray()
    for i, note in pairs(notesTable) do
        local arrayIdx = (i % #targetVelocitiesArray) + 1
        note.targetVelocity = targetVelocitiesArray[arrayIdx]
    end
end

-- Хранит исходные значения скорости нот при запуске
local baseInitialVelocities = storeInitialVelocities(take, noteCount)
local currentBaseVelocities = storeInitialVelocities(take, noteCount)
local lastUsedSlider = nil
slider_gr.onchange = function(self)
    local sliderValue = self.value
    local anySelected = false
    -- Проверяем, есть ли выбранные ноты
    for _, note in pairs(notesTable) do
        local _, selected = reaper.MIDI_GetNote(take, note.idx)
        anySelected = anySelected or selected
    end

    for i, note in pairs(notesTable) do
        local _, selected = reaper.MIDI_GetNote(take, note.idx)
        local baseInitialVelocity = baseInitialVelocities[i + 1]  -- Исходная скорость при запуске
        local arrayIdx = (i % #targetVelocitiesArray) + 1

        if baseInitialVelocity and targetVelocitiesArray[arrayIdx] then  -- Проверка на nil перед арифметической операцией
            if selected or not anySelected then
                local newVelocity = baseInitialVelocity + (targetVelocitiesArray[arrayIdx] - baseInitialVelocity) * (sliderValue / 100)
                newVelocity = math.floor(math.max(1, math.min(127, newVelocity)))

                reaper.MIDI_SetNote(take, note.idx, nil, note.muted, note.startppq, note.endppq, note.chan, note.pitch, newVelocity, false)
                note.velocity = newVelocity
                note.initialVelocity = newVelocity  -- Убираем эту строку
                currentBaseVelocities[i + 1] = newVelocity
            end
        end
    end

    currentBaseVelocities = storeInitialVelocities(take, noteCount)
    lastUsedSlider = slider_gr
    reaper.MIDIEditor_OnCommand(midiEditor, 40237)
    reaper.MIDI_Sort(take)
end






local expandFactor = 2  -- Усиление эффекта разжатия

slider_reduce.onchange = function(self)
    local sliderValue = self.value
    local velocityRange = slider_range.value
    local anySelected = false
    if lastUsedSlider == slider_gr then
            baseInitialVelocities = storeInitialVelocities(take, noteCount)
    end
    for _, note in pairs(notesTable) do
        local _, selected = reaper.MIDI_GetNote(take, note.idx)
        anySelected = anySelected or selected
    end

    for i, note in pairs(notesTable) do
        local _, selected = reaper.MIDI_GetNote(take, note.idx)
        local baseInitialVelocity = baseInitialVelocities[i + 1]

        if selected or not anySelected then
            local closestTarget = currentValue  

            -- Находим ближайшую целевую скорость, если установлено два значения
            if #targetExpandValues == 2 then
                closestTarget = math.abs(targetExpandValues[1] - baseInitialVelocity) < math.abs(targetExpandValues[2] - baseInitialVelocity) and targetExpandValues[1] or targetExpandValues[2]
            end

            local newVelocity = baseInitialVelocity
            if sliderValue > 50 then
                -- Работаем как slider_expand
                newVelocity = baseInitialVelocity + (closestTarget - baseInitialVelocity) * ((sliderValue - 50) / 50)
            elseif sliderValue < 50 then
                -- Работаем как slider_reduce
                newVelocity = baseInitialVelocity - expandFactor * (closestTarget - baseInitialVelocity) * ((50 - sliderValue) / 50)
            end

            newVelocity = math.floor(math.max(velocityRange[1], math.min(velocityRange[2], newVelocity)))
            
            reaper.MIDI_SetNote(take, note.idx, nil, note.muted, note.startppq, note.endppq, note.chan, note.pitch, newVelocity, false)
            note.velocity = newVelocity
        end
    end
    if self.value > 50 then
        label_slider_expand:attr('color', 'white')
        label_slider_compress:attr('color', '#793802')
        target_button_target:attr('border', '#79380260')
        target_button_factor:attr('border', false)
        
    else
        label_slider_expand:attr('color', '#793802')
        label_slider_compress:attr('color', 'white')
        target_button_target:attr('border', false)
        target_button_factor:attr('border', '#79380260')
    end
    lastUsedSlider = slider_reduce
    currentBaseVelocities = storeInitialVelocities(take, noteCount)
    reaper.MIDIEditor_OnCommand(midiEditor, 40237)
    reaper.MIDI_Sort(take)
end


updateTargetVelocitiesFromArray()



local function processNotes()
  local velocityMin, velocityMax = slider_range.value[1], slider_range.value[2]
  local take = reaper.MIDIEditor_GetTake(midiEditor)
  local _, noteCount = reaper.MIDI_CountEvts(take)
  local minVelocity, maxVelocity = 127, 1

  for i = 0, noteCount - 1 do
    local _, _, _, startppq, endppq, chan, pitch, vel = reaper.MIDI_GetNote(take, i)
    if not targetVelocity[i] then
      targetVelocity[i] = math.random(velocityMin, velocityMax)
    end
    if buttonchik.pressed then
      local newVelocity = vel + math.random(2, 6) * (targetVelocity[i] < vel and -1 or 1)
      newVelocity = math.max(1, math.min(127, newVelocity))
      reaper.MIDI_SetNote(take, i, nil, nil, startppq, endppq, chan, pitch, newVelocity, false)
    end
    minVelocity = math.min(minVelocity, targetVelocity[i])
    maxVelocity = math.max(maxVelocity, targetVelocity[i])
  end
  reaper.MIDI_Sort(take)
  slider_range:attr('value', {minVelocity, maxVelocity})
  min:attr('text', minVelocity)
  max:attr('text', maxVelocity)
end
 local function updateBaseInitialVelocities()
     for i, note in pairs(notesTable) do
         local _, _, _, _, _, _, _, vel = reaper.MIDI_GetNote(take, i)
         baseInitialVelocities[i + 1] = vel
     end
 end
 
function update_velocity_all()
    for i = 0, noteCount - 1 do
      local _, _, muted, startppq, endppq, chan, pitch, vel = reaper.MIDI_GetNote(take, i)
      local targetVelocity = math.random(10, 126)
      notesTable[i] = {idx = i, muted = muted, startppq = startppq, endppq = endppq, chan = chan, pitch = pitch, velocity = vel, targetVelocity = targetVelocity, initialVelocity = vel}
    end
end
update_velocity_all()
local function moveVelocity()
  local sliderValue = slider22.value
  local velocityRange = slider_range.value
  local anySelected = false
  for _, note in pairs(notesTable) do
    local _, selected = reaper.MIDI_GetNote(take, note.idx)
    anySelected = anySelected or selected
  end
  for i, note in pairs(notesTable) do
    local _, selected = reaper.MIDI_GetNote(take, note.idx) 
    if selected or not anySelected then
      local currentVelocity = note.velocity
      local targetVelocity = note.targetVelocity
      local initialVelocity = note.initialVelocity
      local newVelocity = initialVelocity + (targetVelocity - initialVelocity) * (sliderValue / 100)
      newVelocity = math.floor(math.max(velocityRange[1], math.min(velocityRange[2], newVelocity)))
      reaper.MIDI_SetNote(take, note.idx, nil, note.muted, note.startppq, note.endppq, note.chan, note.pitch, newVelocity, false)
      note.velocity = newVelocity
      initialVelocities[i + 1] = newVelocity
      currentBaseVelocities[i + 1] = newVelocity
    end
  end
  reaper.MIDIEditor_OnCommand(midi_editor, 40237)
  reaper.MIDI_Sort(take)
end
local function randomizeTargetVelocities()
  local velocityMin, velocityMax = slider_range.value[1], slider_range.value[2]
  for i, note in pairs(notesTable) do
    note.targetVelocity = math.random(velocityMin, velocityMax)
  end
end
local keepRunning = true 

wnd.onclose = function()
  keepRunning = false 
end

local function deferFunction()
  if not keepRunning then return end 
  
  local kk, currentNoteCount = reaper.MIDI_CountEvts(take)
  if not kk then
      keepRunning = false
      wnd:close()  -- Закрыть окно
      return
  end
  if currentNoteCount ~= noteCount then
      noteCount = currentNoteCount
      notesTable = {}
      initialVelocities = storeInitialVelocities(take, noteCount)
      baseInitialVelocities = storeInitialVelocities(take, noteCount)  -- обновляем baseInitialVelocities
  end
  
  for i = 0, noteCount - 1 do
    local _, selected, muted, startppq, endppq, chan, pitch, vel = reaper.MIDI_GetNote(take, i)
    if notesTable[i] then
      notesTable[i].startppq = startppq
      notesTable[i].endppq = endppq
      notesTable[i].pitch = pitch
      notesTable[i].velocity = vel -- Обновляем текущую скорость
    else
      local targetVelocity = math.random(10, 126)
      notesTable[i] = {idx = i, selected = selected, muted = muted, startppq = startppq, endppq = endppq, chan = chan, pitch = pitch, velocity = vel, targetVelocity = targetVelocity, initialVelocity = vel}
    end
  end
  if currentNoteCount ~= noteCount then
      for i, note in pairs(notesTable) do
          local _, _, _, _, _, _, _, vel = reaper.MIDI_GetNote(take, i)
          note.initialVelocity = vel
      end
  end
  reaper.defer(deferFunction)
end
deferFunction()
buttonchik.onclick = function()
  randomizeTargetVelocities() 
  moveVelocity() 
  
end
slider22.onchange = function(self)
    moveVelocity()
    updateBaseInitialVelocities()
end


slider_range.onchange = function(self, event)
        min:attr('text', self.value[1])
        max:attr('text', self.value[2])
        moveVelocity()
        updateBaseInitialVelocities()
end





local font = rtk.Font()
local selected_point = nil

CurveWidget = rtk.class('CurveWidget', rtk.Spacer)
CurveWidget.register{
    points = rtk.Attribute{default={}},
    w = rtk.Attribute{default=200},
    h = rtk.Attribute{default=200},
    v_thumbcolor = rtk.Attribute{default='yellow'},
    main_thumbcolor = rtk.Attribute{default='blue'},
    v_thumb = rtk.Attribute{default=5, type='number|nil|boolean'},
    main_thumb = rtk.Attribute{default=5, type='number|nil|boolean'},
    bg = rtk.Attribute{default='#4c5c64'},
    line_color = rtk.Attribute{default='red'},
    autofocus = true,
    v_thumb_value = rtk.Attribute{default={0.5, 0.5}, type='table'},
}

function CurveWidget:initialize(attrs, ...)
    rtk.Spacer.initialize(self, attrs, CurveWidget.attributes.defaults, ...)
    self.points = {{0.01, self.v_thumb_value[1]}, {0.4, 0.7}, {0.6, 0.2}, {0.99, self.v_thumb_value[2]}}
    self.coord_text = ""
end

font_y_x="Verdena"
function CurveWidget:_handle_draw(offx, offy, alpha, event)
    local calc = self.calc
    local x = offx + calc.x
    local y = offy + calc.y
    local w = calc.w  -- Изменено с self.w
    local h = calc.h  -- Изменено с self.h

    -- Draw background
    self:setcolor(self.bg)
    gfx.rect(x, y, w, h)

    -- Draw border
    self:setcolor('gray')
    gfx.rect(x, y, w, h, 0)

    -- Draw cross
    gfx.line(x, y + h / 2, x + w, y + h / 2)
    gfx.line(x + w / 2, y, x + w / 2, y + h)

    -- Draw Bezier curve
    self:setcolor(self.line_color)
    local last_px, last_py = nil, nil
    local circle_radius = 2  -- радиус каждой окружности
    for t = 0, 1, 0.09 do
        local x, y = self:evaluate_bezier(t)
        local px = x * w + offx + calc.x
        local py = (1 - y) * h + offy + calc.y
        gfx.circle(px, py, circle_radius, 1)
    end
    

    -- Draw points
    for i, point in ipairs(self.points) do
        if i == 1 or i == #self.points then
            -- Draw v_thumb only if it's not nil or false
            if self.v_thumb then
                self:setcolor(self.v_thumbcolor)
                gfx.circle(x + point[1] * w, y + (1 - point[2]) * h, self.v_thumb, 1)
            end
        else
            -- Draw main_thumb only if it's not nil or false
            if self.main_thumb then
                self:setcolor(self.main_thumbcolor)
                gfx.circle(x + point[1] * w, y + (1 - point[2]) * h, self.main_thumb, 1)
            end
        end
    end

    gfx.set(1, 1, 1)
    font:set(font_y_x, 12)
    font:draw(self.coord_text, x+2, y-109 + h + 10)
end
local function factorial(n)
    local res = 1
    for i = 2, n do
        res = res * i
    end
    return res
end
local function comb(n, k)
    return factorial(n) / (factorial(k) * factorial(n - k))
end
function CurveWidget:evaluate_bezier(t)
    local x, y = 0, 0
    local points_to_use = {}
    
    if self.v_thumb ~= false and self.v_thumb ~= nil then
        table.insert(points_to_use, self.points[1])
    end
    
    if self.main_thumb ~= false and self.main_thumb ~= nil then
        for i = 2, #self.points - 1 do
            table.insert(points_to_use, self.points[i])
        end
    end
    
    if self.v_thumb ~= false and self.v_thumb ~= nil then
        table.insert(points_to_use, self.points[#self.points])
    end

    local n = #points_to_use - 1

    for i, point in ipairs(points_to_use) do
        local coef = comb(n, i-1) * (t^(i-1)) * ((1-t)^(n-i+1))
        x = x + coef * point[1]
        y = y + coef * point[2]
    end

    return x, y
end

function apply_interpolation(curve_widget)
    local midiEditor = reaper.MIDIEditor_GetActive()
    local midiTake = reaper.MIDIEditor_GetTake(midiEditor)
    local _, noteCount, _, _ = reaper.MIDI_CountEvts(midiTake)

    local x1, y1 = curve_widget:evaluate_bezier(0)
    local firstNoteVelocity = y1 * 127
    local x2, y2 = curve_widget:evaluate_bezier(1)
    local lastNoteVelocity = y2 * 127

    local firstNotePos = -1
    local lastNotePos = -1

    local invert = curve_widget.points[1][2] > curve_widget.points[#curve_widget.points][2]
    local anySelected = false

    for i = 0, noteCount - 1 do
        local retval, selected, _, startppq, _, _, _, vel = reaper.MIDI_GetNote(midiTake, i)
        if selected then
            anySelected = true
            if firstNotePos == -1 then
                firstNotePos = i
            end
            lastNotePos = i
        end
    end

    if not anySelected then
        firstNotePos = 0
        lastNotePos = noteCount - 1
    end

    if firstNotePos == -1 or lastNotePos == -1 then
        return
    end

    for i = firstNotePos, lastNotePos do
        local retval, selected, _, _, _, _, _, _ = reaper.MIDI_GetNote(midiTake, i)
        if selected or not anySelected then
            local pos = i - firstNotePos
            local total = lastNotePos - firstNotePos
            local t = pos / total
            local _, y = curve_widget:evaluate_bezier(t)
            if invert then
                y = 1 - y
            end
            local interpolatedVelocity = math.max(1, math.floor(firstNoteVelocity + (lastNoteVelocity - firstNoteVelocity) * y))
            reaper.MIDI_SetNote(midiTake, i, selected, nil, nil, nil, nil, nil, interpolatedVelocity, true)  -- оставляем выделение, если оно уже есть
        end
    end
    
        baseInitialVelocities = storeInitialVelocities(midiTake, noteCount)
        currentBaseVelocities = storeInitialVelocities(midiTake, noteCount)
        
    reaper.MIDI_Sort(midiTake)
end
th_color_m="#1a1a1a"

local curve_widget_instance = window_interpolate_box:add(CurveWidget{
    autofocus=true,
    line_color=th_color_m .. "91",
    w=180,
    bg='#383c3c',
    h=100,
    v_thumbcolor=th_color_m,
    main_thumbcolor="#3c1c1c",
    v_thumb=7,
    main_thumb=3,
    padding=5,
    v_thumb_value = {0.2, 0.8},
})







--[[
function CurveWidget:_handle_dragend(event)
    selected_point = nil  -- сбросим выбранную точку при окончании перетаскивания

    -- Собираем текущие координаты точек в строку
    local points_str = "{"
    for i, point in ipairs(self.points) do
        points_str = points_str .. "{" .. string.format("%.2f", point[1]) .. ", " .. string.format("%.2f", point[2]) .. "}"
        if i < #self.points then
            points_str = points_str .. ", "
        end
    end
    points_str = points_str .. "}"

    -- Выводим строку, например, в консоль Reaper
    reaper.ShowConsoleMsg("Current points: " .. points_str .. "\n")

    apply_interpolation(curve_widget_instance)
end
]]

local selected_point = nil
local threshold = 0.2  -- Увеличил порог
function CurveWidget:_handle_dragend(event)
    selected_point = nil
    if self.main_thumb == false then
        self.points[1][2] = 0.5
        self.points[#self.points][2] = 0.5
        
    else 
        apply_interpolation(curve_widget_instance)
        slider_gr:onchange()
        slider_reduce:onchange()
    end
    
end
local selected_points = {}  -- Теперь это массив

function CurveWidget:_handle_dragstart(event)
    local calc = self.calc
    local x = (event.x - self.clientx) / calc.w
    local y = 1 - (event.y - self.clienty) / calc.h

    local closest_point_index = nil
    local min_distance = math.huge

    selected_points = {}  -- Очищаем массив выбранных точек

    if event.ctrl and event.shift then  -- Ctrl+Shift
        for i, _ in ipairs(self.points) do
            table.insert(selected_points, i)
        end
        return true
    end

    for i, point in ipairs(self.points) do
        local dx = x - point[1]
        local dy = y - point[2]
        local distance = math.sqrt(dx * dx + dy * dy)

        if event.ctrl and (i == 1 or i == #self.points) then  -- Ctrl + v_thumb
            if distance < min_distance then
                min_distance = distance
                closest_point_index = i
            end
        elseif event.shift and (i ~= 1 and i ~= #self.points) then  -- Shift + main_thumb
            if distance < min_distance then
                min_distance = distance
                closest_point_index = i
            end
        elseif not event.shift and not event.ctrl then  -- Ни Ctrl, ни Shift не зажаты
            if distance < min_distance then
                min_distance = distance
                closest_point_index = i
            end
        end
    end

    if closest_point_index then
        table.insert(selected_points, closest_point_index)
        return true
    end
end

function CurveWidget:_handle_dragmousemove(event)
    if #selected_points == 0 then return end

    local calc_w, calc_h = self.calc.w, self.calc.h
    local x = (event.x - self.clientx) / calc_w
    local y = 1 - (event.y - self.clienty) / calc_h

    if x < 0 then x = 0 elseif x > 1 then x = 1 end
    if y < 0 then y = 0 elseif y > 1 then y = 1 end

    for _, i in ipairs(selected_points) do
        if i == 1 or i == #self.points then  -- для v_thumb, двигаем только по оси y
            self.points[i] = {self.points[i][1], y}
        else
            self.points[i] = {x, y}
        end
    end

    self.coord_text = string.format("X: %.2f, Y: %.2f", x*100, (1-y)*100)
    apply_interpolation(curve_widget_instance)
    self:queue_draw()
end



function CurveWidget:_handle_mousedown(event)
    if event.button == rtk.mouse.BUTTON_RIGHT then
        local menu = rtk.NativeMenu()
        menu:set({
            {'Left interpolation', submenu={
                {current_preset == 'preset2' and '✔ Liner L' or 'Liner L', id='preset2'},
                {current_preset == 'preset3' and '✔ Sin L' or 'Sin L', id='preset3'},
                {current_preset == 'preset5' and '✔ Cubic L' or 'Cubic L', id='preset5'},
                {current_preset == 'preset7' and '✔ In Cubic L' or 'In Cubic L', id='preset7'},
                {current_preset == 'preset10' and '✔ Out Cubic L' or 'Out Cubic L', id='preset10'}
            }},
            {'Right interpolation', submenu={
                {current_preset == 'preset1' and '✔ Liner R' or 'Liner R', id='preset1'},
                {current_preset == 'preset4' and '✔ Sin R' or 'Sin R', id='preset4'},
                {current_preset == 'preset6' and '✔ Cubic R' or 'Cubic R', id='preset6'},
                {current_preset == 'preset8' and '✔ In Cubic R' or 'In Cubic R', id='preset8'},
                {current_preset == 'preset9' and '✔ Out Cubic R' or 'Out Cubic R', id='preset9'}
            }},
            rtk.NativeMenu.SEPARATOR,
            {"Invert", id='Invert'}
        })
        menu:open_at_mouse():done(function(item)
            if not item then
                return
            end
            current_preset = item.id
            curve_widget_instance:apply_preset(item.id)  -- Здесь изменено с self на curve_widget_instance
            slider_gr:onchange()
            slider_reduce:onchange()
        end)
    end
    if not event.shift then
        return false
    end

    local calc = self.calc
    local x = (event.x - self.clientx) / calc.w
    local y = 1 - (event.y - self.clienty) / calc.h

    local closest_point_index = nil
    local min_distance = math.huge  -- Инициализируем наибольшим возможным значением

    for i, point in ipairs(self.points) do
        if i ~= 1 and i ~= #self.points then  -- Игнорируем v_thumb
            local dx = x - point[1]
            local dy = y - point[2]
            local distance = math.sqrt(dx * dx + dy * dy)

            if distance < min_distance then
                min_distance = distance
                closest_point_index = i
            end
        end
    end

    if closest_point_index then
        selected_point = closest_point_index
        self.points[selected_point] = {x, y}
        self:queue_draw()  -- Перерисовываем виджет
        return true  -- Возвращаем true, чтобы начать drag событие
    end
    baseInitialVelocities = storeInitialVelocities(take, noteCount)
    currentBaseVelocities = storeInitialVelocities(take, noteCount)
end


local current_preset = nil

function CurveWidget:apply_preset(preset_id)
    if preset_id == 'save' then
    else
        -- Применяем один из сохраненных пресетов
        local preset
        if preset_id == 'preset1' then
            preset = {{0.01, 0.00}, {0.33, 0.30}, {0.69, 0.63}, {0.99, 1.00}}
        elseif preset_id == 'preset2' then
            preset = {{0.01, 1.00}, {0.33, 0.63}, {0.59, 0.36}, {0.99, 0.00}}
        elseif preset_id == 'preset3' then
            preset = {{0.01, 1.00}, {0.00, 0.00}, {1.00, 1.00}, {0.99, 0.00}}
        elseif preset_id == 'preset4' then
            preset = {{0.01, 0.00}, {0.00, 1.00}, {1.00, 0.00}, {0.99, 1.00}}
        elseif preset_id == 'preset5' then
            preset = {{0.01, 1.00}, {1.00, 1.00}, {0.00, 0.00}, {0.99, 0.00}} --c_l
        elseif preset_id == 'preset6' then
            preset = {{0.01, 0.00}, {1.00, 0.00}, {0.00, 1.00}, {0.99, 1.00}}
        elseif preset_id == 'preset7' then
            preset = {{0.01, 1.00}, {0.00, 0.00}, {0.00, 0.00}, {0.99, 0.00}}
        elseif preset_id == 'preset8' then
            preset = {{0.01, 0.00}, {1.00, 0.00}, {1.00, 0.00}, {0.99, 1.00}}
        elseif preset_id == 'preset9' then
            preset = {{0.01, 0.00}, {0.00, 1.00}, {0.00, 1.00}, {0.99, 1.00}}
        elseif preset_id == 'preset10' then
            preset = {{0.01, 1.00}, {1.00, 1.00}, {1.00, 1.00}, {0.99, 0.00}}
        elseif preset_id == 'Invert' then
               for i, point in ipairs(self.points) do
                           self.points[i] = {point[1], 1 - point[2]}
               end
            
        end

        if preset then
            self.points = preset
            self:queue_draw()  -- Перерисовываем виджет
        end
    end
    apply_interpolation(curve_widget_instance)
end
















function SliderGroup:_handle_dragmousemove(event, arg)
    local ok = rtk.HBox._handle_dragmousemove(self, event)
    if ok == false or event.simulated then
        return ok
    end

    local x0 = math.min(arg.lastx, event.x)
    local x1 = math.max(arg.lastx, event.x)
    
    for i = 1, #self.children do
        local child = self.children[i][1]
        if child.clientx >= x1 then
            break
        elseif child.clientx + child.calc.w > x0 and rtk.isa(child, SimpleSlider) then
            if event.ctrl and not focused_slider then
                focused_slider = child
                
            end

            if event.shift then
                if first_slider_value == nil then
                    first_slider_value = child.value
                   
                end
                child:attr('value', first_slider_value)
            elseif focused_slider then
                focused_slider:set_from_mouse_y(event.y)
                
            else
                child:set_from_mouse_y(event.y)
                
            end
            
            handle_click(child, nil)
        end
    end
    arg.lastx = event.x
    arg.lasty = event.y
    
end
local initial_slider_gr_value = nil  -- Переменная для сохранения первоначального значения slider_gr

function SliderGroup:_handle_dragstart(event, x, y, t)
    first_slider_value = nil
    focused_slider = nil
    local draggable, droppable = rtk.HBox._handle_dragmousemove(self, event)
    if draggable ~= nil then
        return draggable, droppable
    end
    if event.alt then
        -- Сохраняем первоначальное значение slider_gr и устанавливаем его значение в 0
        initial_slider_gr_value = slider_gr.value
        slider_gr.value = 0
    else
        handle_click(event, nil)
    end
    return {lastx=x, lasty=y}, false
end
function SliderGroup:_handle_dragend(event, arg)
    if initial_slider_gr_value ~= nil then
        -- Восстанавливаем первоначальное значение slider_gr после окончания перетаскивания
        slider_gr.value = initial_slider_gr_value
        slider_gr:onchange()
        initial_slider_gr_value = nil  -- Сбрасываем переменную
    end
end
function SimpleSlider:_handle_mousedown(event)
    
    local ok = rtk.Spacer._handle_mousedown(self, event)
    if ok == false then
        return ok
    end
    handle_click(self, event)
    if event.button == rtk.mouse.BUTTON_RIGHT then
        
    else
        self:set_from_mouse_y(event.y)
        
    end
    handle_click(self, event)
    
end

reaper.atexit(function() reaper.defer(function() end) end)