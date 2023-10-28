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
        self:setcolor(func.makeDarker(self.calc.color, -0.2))
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
--[[
function widg.CircleWidget2:_drawInnerCircleAndText(x, y, innerCircleRadius, percentage)
    gfx.circle(x, y, innerCircleRadius, 1)
    local labelText = percentage .. "%"
    self:setcolor(self.calc.textcolor)
    rtk.Font:set(self.calc.font, self.calc.fontsize)
    gfx.x = math.floor(x - gfx.measurestr(labelText) * 0.5 + self.calc.font_x + 0.5)
    gfx.y = y - 45 + self.calc.font_y
    gfx.drawstr(labelText)
end

]]
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
    return self.currentValue
end



function widg.CircleWidget2:_handle_mouseenter(event)
    --self.hovered = true
    
    return true
end

function widg.CircleWidget2:_handle_mouseleave(event)
    --self.hovered = false
    
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

return widg


--[[
widg.window = nil
widg.cursorHidden = false
widg.initial_mx = nil
widg.initial_my = nil
widg.wnd_w = 9000  -- здесь получаем ширину окна
widg.flag_mousedown = false  -- Флаг для проверки, было ли событие mousedown




function widg.Loop()
    if widg.cursorHidden then
        reaper.JS_Mouse_SetCursor(nil)
        reaper.defer(widg.Loop)
    else
        reaper.JS_WindowMessage_Release(widg.window, "WM_SETCURSOR")
    end
end

-- Обработчик события mousedown
function widg.CircleWidget2:_handle_mousedown(event)
    widg.initial_mx, widg.initial_my = reaper.GetMousePosition()
    widg.window = reaper.JS_Window_FromPoint(widg.initial_mx, widg.initial_my)
    reaper.JS_Mouse_SetPosition(widg.wnd_w, widg.initial_my)
    widg.cursorHidden = true
    reaper.JS_WindowMessage_Intercept(widg.window, "WM_SETCURSOR", false)
    widg.Loop()
    widg.flag_mousedown = true 
    return true
end

-- Обработчик события dragstart
function widg.CircleWidget2:_handle_dragstart(event, x, y, t)
    if widg.flag_mousedown then  
        self.dragging = true
        self.prevY = y
        self.alpha2 = 0.002
        self.hovered = true
        -- Скрываем курсор
        widg.cursorHidden = true
        reaper.JS_WindowMessage_Intercept(widg.window, "WM_SETCURSOR", false)
        widg.Loop()
        return true
    end
end

-- Обработчики событий dragend и mouseup
function widg.CircleWidget2:_handle_dragend_or_mouseup(event, dragarg)
    -- Возвращаем курсор на начальную позицию
    reaper.JS_Mouse_SetPosition(widg.initial_mx, widg.initial_my)
    -- Показываем курсор
    widg.cursorHidden = false
    -- Сбрасываем флаг
    widg.flag_mousedown = false
end

widg.CircleWidget2._handle_dragend = widg.CircleWidget2._handle_dragend_or_mouseup
widg.CircleWidget2._handle_mouseup = widg.CircleWidget2._handle_dragend_or_mouseup
]]