-- @noindex  

widg = {}




local script_path = (select(2, reaper.get_action_context())):match('^(.*[/\\])')
local functions_path = script_path .. "../libs/Functions.lua"
local func = dofile(functions_path)

widg.round_size = 30
widg.CircleWidget2 = rtk.class('CircleWidget2', rtk.Spacer)
widg.theme_color = rtk.color.get_reaper_theme_bg() 
widg.CircleWidget2.register{
    radius = rtk.Attribute{default=round_size},
    borderFraction = rtk.Attribute{default=1},
    borderwidth = rtk.Attribute{default=5},
    currentValue = rtk.Attribute{default=0},
    y = rtk.Attribute{default=0},
    sens = rtk.Attribute{default=0.6},
    lastSentValue = rtk.Attribute{default=nil}, 
    color = rtk.Attribute{type='color', default='#335c94'},
    font = rtk.Attribute{default='Arial'},
    textcolor = rtk.Attribute{type='color', default='#ffffff'},
    fontsize = rtk.Attribute{default=16},
    font_x = rtk.Attribute{default=2},
    font_y = rtk.Attribute{default=0},
    value = rtk.Attribute{default=0},
    onChange = rtk.Attribute{default=nil}, 
    
}

widg.count = 0

function widg.CircleWidget2:initialize(attrs, ...)
    widg.count = widg.count + 1
    self.ref = 'circle' .. widg.count
    rtk.Spacer.initialize(self, attrs, widg.CircleWidget2.attributes.defaults, ...)
    self.alpha2 = 0.07
    self.currentRadius = 0
    
    self.calc.w = self.radius * 2
    self.calc.h = self.radius * 2
    
    self.currentValue = self.calc.value

end


function widg.CircleWidget2:_drawOuterCircle(x, y, outerRadius)
    if self.hovered then
        self:setcolor(func.makeDarker(self.calc.color, 0.33))
    else
        self:setcolor(func.makeDarker(self.calc.color, 0.55))
    end
    gfx.circle(x, y, outerRadius, 1)
end

function widg.CircleWidget2:_drawArc(x, y, outerRadius, startAngle, endAngle, arcWidth)
    if self.hovered then
        self:setcolor(func.makeDarker(self.calc.color, -0.5))
    else
        self:setcolor(self.calc.color)
    end
    local step = 0.5
    for i = 1, arcWidth, step do
        gfx.arc(x, y, outerRadius - i, startAngle, endAngle, 1)
    end
end

function widg.CircleWidget2:_drawTriangle(x, y, outerRadius, overlap, triHeight, yOffset)
    self:setcolor(widg.theme_color)
    local triX1, triY1 = x - outerRadius - overlap, y + math.floor(outerRadius * 0.5 + 0.5) + yOffset
    local triX2, triY2 = x + outerRadius + overlap, triY1
    local triX3, triY3 = x, y - triHeight + yOffset
    gfx.triangle(triX1, triY1, triX2, triY2, triX3, triY3)
end

function widg.CircleWidget2:_drawInnerCircleAndText(x, y, innerCircleRadius, percentage)
    gfx.circle(x, y, innerCircleRadius, 1)
    local labelText = percentage .. "%"
    self:setcolor(self.calc.textcolor)
    gfx.setfont(1, "Arial", self.calc.fontsize)  -- Установка шрифта
    gfx.x = math.floor(x - gfx.measurestr(labelText) * 0.5 + self.calc.font_x + 0.5)
    gfx.y = y - 45 + self.calc.font_y
    gfx.drawstr(labelText)
end

function widg.CircleWidget2:_handle_draw(offx, offy, alpha, event)
    local calc = self.calc
    local x = math.floor(offx + calc.x + calc.w * 0.5 + 0.5)
    local y = math.floor(offy + calc.y + calc.h * 0.5 + 0.5)
    local knobRadius = math.floor(calc.radius + self.currentRadius + 0.5)
    local outerRadius = math.floor(knobRadius - calc.borderwidth - 12 + 0.5)
    local startAngle = -2.3561944901923 
    local endAngle = startAngle + 4.7123889803847 * (self.currentValue / 100)
    local arcWidth = calc.borderwidth * 3 * (calc.radius / widg.round_size)
    local overlap = 11
    local triHeight = math.floor(outerRadius * 0.8660254037844 + 0.5) -- sqrt(3) / 2
    local yOffset = triHeight
    local innerCircleRadius = math.floor(outerRadius / 1.9 + 0.5)
    local percentage = math.floor(self.currentValue + 0.5)
    
    self:_drawOuterCircle(x, y, outerRadius)
    self:_drawArc(x, y, outerRadius, startAngle, endAngle, arcWidth)
    self:_drawTriangle(x, y, outerRadius, overlap, triHeight, yOffset)
    self:_drawInnerCircleAndText(x, y, innerCircleRadius, percentage)
end


function widg.CircleWidget2:setCurrentValue(newValue, shouldRedraw)
    self.currentValue = newValue
    if shouldRedraw then
        self:redraw()
    end
end

function widg.CircleWidget2:getValue()
    self:redraw()
    return self.currentValue
end



function widg.CircleWidget2:_handle_mouseenter(event)
    self.hovered = true
    
    return true
end

function widg.CircleWidget2:_handle_mouseleave(event)
    self.hovered = false
    
    return true
end




function widg.CircleWidget2:_handle_dragstart(event, x, y, t)
    self.dragging = true
    self.prevY = y
    self.alpha2 = 0.002
    self.hovered = true

    
    return true
end

function widg.CircleWidget2:_handle_dragend(event, dragarg)
    self.dragging = false
    self.prevY = nil
    self.alpha2 = 0.02
    self.hovered = false
end


function widg.CircleWidget2:_handle_dragmousemove(event, dragarg)
    if self.dragging and self.prevY then
        local delta = event.y - self.prevY
        local sensitivity = self.calc.sens 
        if event.ctrl then
            sensitivity = sensitivity / 6  
        end
        local newValue = self.currentValue - delta * sensitivity
        newValue = math.max(0, math.min(100, newValue))
 
        local snapThreshold = 2 
        if newValue < snapThreshold then
            newValue = 0
        elseif newValue > 100 - snapThreshold then
            newValue = 100
        end
        
    
        if newValue ~= self.currentValue then
            self:animate{
                attr = 'currentValue',
                dst = newValue,
                duration = 0.001
            }
            

            if newValue ~= self.calc.lastSentValue then
                local callback = self.calc.onChange
                if callback then
                    callback(newValue)
                end
                self:attr('lastSentValue', newValue)  
            end
        end
        
        self.prevY = event.y
    end
end

function widg.CircleWidget2:sign(x)
    return x > 0 and 1 or x < 0 and -1 or 0
end



local img_path = script_path .. "../images/cursor.cur"
local null_cursor = reaper.JS_Mouse_LoadCursorFromFile(img_path)


function widg.CircleWidget2:_handle_mousedown(event)
    widg.initial_mx, widg.initial_my = reaper.GetMousePosition()
    self:attr('cursor', null_cursor) -- Скрываем курсор
    --widg.cursorHidden = true
    widg.flag_mousedown = true 
    self.hovered = true
    return true
end

-- Обработчик события dragstart
function widg.CircleWidget2:_handle_dragstart(event, x, y, t)
    if widg.flag_mousedown then  
        self:attr('cursor', null_cursor)
        self.dragging = true
        self.prevY = y
        self.alpha2 = 0.002
        self.hovered = true
        return true
    end
end

-- Обработчики событий dragend и mouseup
function widg.CircleWidget2:_handle_dragend_or_mouseup(event, dragarg)
    --self.hovered = false
    widg.flag_mousedown = false
    if widg.initial_mx and widg.initial_my then
        reaper.JS_Mouse_SetPosition(widg.initial_mx, widg.initial_my)
    end
    self:attr('cursor', UNDEFINED)

end

widg.CircleWidget2._handle_dragend = widg.CircleWidget2._handle_dragend_or_mouseup
widg.CircleWidget2._handle_mouseup = widg.CircleWidget2._handle_dragend_or_mouseup



return widg

--[[



package.path = string.format('%s/Scripts/rtk/1/?.lua;%s?.lua;', reaper.GetResourcePath(), entrypath)
require 'rtk'

local script_path = (select(2, reaper.get_action_context())):match('^(.*[/\\])')
local widg = script_path .. "Widgets.lua"

local widg = dofile(widg)



SimpleSlider = rtk.class('SimpleSlider', rtk.Spacer)
SimpleSlider.register{
    value = rtk.Attribute{default=0},
    color = rtk.Attribute{type='color', default='crimson'},
    minw = 5,
    roundrad = rtk.Attribute{default=5},
    h = 1.0,
    autofocus = true,
    ttype = rtk.Attribute{default=1},
    onchange = rtk.Attribute{default=nil},
    textcolor = rtk.Attribute{type='color', default='#ffffff'},
    fontsize = rtk.Attribute{default=16},
    font_x = rtk.Attribute{default=2},
    font_y = rtk.Attribute{default=0},
}

function SimpleSlider:initialize(attrs, ...)
    rtk.Spacer.initialize(self, attrs, SimpleSlider.attributes.defaults, ...)
end



function SimpleSlider:_handle_draw(offx, offy, alpha, event)
    local calc = self.calc
    local x = math.floor(offx + calc.x)
    local y = math.floor(offy + calc.y)
    local w = math.floor(calc.w)
    local h = math.floor(calc.h)
    local round_radius = calc.roundrad
    local thickness = 0.5
    local aa = true

    -- Задний цвет
    self:setcolor('#481c24')
    rtk.gfx.roundrect(x, y, w, h, round_radius, thickness, aa)
    
    -- Передний цвет
    if calc.value < 0.02 then
        self:setcolor('transparent')
    else
        self:setcolor('#e0143c')
    end

    if calc.ttype == 1 then
        local slider_h = math.floor(h * calc.value)
        rtk.gfx.roundrect(x, y + h - slider_h, w, slider_h, round_radius, thickness, aa)
    else
        local slider_w = math.floor(w * calc.value)
        if slider_w < round_radius * 2 then
            round_radius = slider_w / 2
        end
        rtk.gfx.roundrect(x, y, slider_w, h, round_radius, thickness, aa)
    end
    
    local displayValue = math.floor(self.calc.value * 100)
    
    -- Установка шрифта и цвета текста
    self:setcolor(self.calc.textcolor)
    gfx.setfont(1, self.calc.font, self.calc.fontsize)
    
    -- Расположение текста внутри слайдера
    gfx.x = x + (w / 2) - (gfx.measurestr(tostring(displayValue)) / 2) + self.calc.font_x
    gfx.y = y + self.calc.font_y
    
    -- Отображение значения
    gfx.drawstr(tostring(displayValue))
end


function msg(message)
  reaper.ClearConsole()
  reaper.ShowConsoleMsg(tostring(message) .. "\n")
end

function SimpleSlider:set_from_mouse(y_or_x)
    local dimension = self.calc.ttype == 1 and self.calc.h or self.calc.w
    local pos = self.calc.ttype == 1 and (dimension - (y_or_x - self.clienty)) or (y_or_x - self.clientx)
    local value = rtk.clamp(pos / dimension, 0, 1)
    self:sync('value', value)
    self:animate{
        attr = 'value',
        dst = value,
        duration = 25
    }
end
local prevValue = 0 -- Переменная для хранения предыдущего значения

function SimpleSlider:_handle_mousedown(event)
    prevValue = self.calc.value -- Сохраняем текущее значение
    self:set_from_mouse(self.calc.ttype == 1 and event.y or event.x)
end

function SimpleSlider:_handle_mouseup(event)
    -- Сравниваем текущее значение с предыдущим
    if self.calc.value ~= prevValue then
        local displayValue = math.floor(self.calc.value * 100)
        local callback = self.calc.onchange
        if callback then
            callback(displayValue)
        end
    end
end



function SimpleSlider:_handle_dragstart(event)
    if event.button == rtk.mouse.BUTTON_LEFT then
        self:set_from_mouse(self.calc.ttype == 1 and event.y or event.x)
        return {
            initial_pos = self.calc.ttype == 1 and event.y or event.x,
            initial_value = self.calc.value
        }, false
    end
end

function SimpleSlider:_handle_dragmousemove(event, args)
    local dpos = (self.calc.ttype == 1 and event.y or event.x) - args.initial_pos
    local dimension = self.calc.ttype == 1 and self.calc.h or self.calc.w
    local delta_value = dpos / dimension
    local new_value = self.calc.ttype == 1 and (args.initial_value - delta_value) or (args.initial_value + delta_value)
    new_value = rtk.clamp(new_value, 0, 1)
    
    if new_value ~= self.calc.value then
        self:animate{
            attr = 'value',
            dst = new_value,
            duration = 0.0001
        }
        -- Вычислим displayValue
        local displayValue = math.floor(new_value * 100)
        
        -- Проверка на наличие callback функции onChange
        local callback = self.calc.onchange
        if callback then
            callback(displayValue) -- Передаем displayValue вместо new_value
        else
        end
    end
end







local function main()
    local win = rtk.Window{w=600, h=400, padding=20}
    hbox_2=win:add(rtk.VBox{spacing = 5})
    
    local group = hbox_2:add(rtk.HBox{spacing=5,expand=1})
    
    local group2 = hbox_2:add(rtk.HBox{z=1,expand=1})
    
    group:add(SimpleSlider{roundrad=5,h=120,w=30,ttype=1})
    group:add(SimpleSlider{roundrad=5,h=120,w=30,ttype=1})
    group:add(SimpleSlider{roundrad=5,h=120,w=30,ttype=1})
    group:add(SimpleSlider{roundrad=5,h=120,w=30,ttype=1})
    group:add(SimpleSlider{roundrad=5,h=120,w=30,ttype=1})
    round_size2=32
    
    local values = {
        { "1/1", 3840 },
        { "1/2", 1920 },
        { "1/3", 1280 },
        { "1/4", 960 },
        { "1/6", 640 },
        { "1/8", 480 },
        { "1/12", 320 },
        { "1/16", 240 },
        { "1/24", 160 },
        { "1/32", 120 },
        { "1/48", 80 },
        { "1/64", 60 },
        { "1/128", 30 }
    }
    
    local text = rtk.Text{x=10, y=5, size=14}
    local ar2 = group2:add(SimpleSlider{
    w=170,h=30,roundrad=2,color="#3a3a3a",lhotzone=5, rhotzone=5, ttype = 2,
    onchange = function(value)
        local index = math.floor((value / 100) * #values) + 1
        local selected_value = values[index]
    
        if selected_value then
            text:attr('text', selected_value[1])
        end
    end
    })
    
    local ar = group2:add(SimpleSlider{
        x=5,
        w=25,
        h=30,
        roundrad=5,
        color="#3a3a3a",
        lhotzone=5,
        rhotzone=5,
        ttype = 1, 
        
    })
    
    group2:add(text)
    win:open()
    local vabox = hbox_2:add(rtk.Container{})
    local spacer = rtk.Spacer{w=85,h=30,}
    -- Add the spacer centered on the window (so now the spacer will be
    -- half the width/height of the window)
    vabox:add(spacer, {halign='center', valign='center'})
    -- Create a custom draw handler that draws a circle centered in the
    -- spacer's calculated box.
    spacer.ondraw = function(self, offx, offy, alpha, event)
        self:setcolor('#231709', alpha)
        -- Must draw relative to the supplied offx, offy.
        rtk.gfx.roundrect(
            offx + self.calc.x-1,
            offy + self.calc.y-1,
            self.calc.w+2,
            self.calc.h+2,
            8,
            1, -- fill
            1  -- antialias
        )
        self:setcolor('#964B00', alpha)
        rtk.gfx.roundrect(
            offx + self.calc.x,
            offy + self.calc.y,
            self.calc.w,
            self.calc.h,
            5,
            0, -- fill
            1  -- antialias
        )
    end
    spacer.onclick = function(self, event)
  
    end
end
rtk.call(main)

]]