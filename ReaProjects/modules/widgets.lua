--@noindex
--NoIndex: true

SimpleSlider = rtk.class('SimpleSlider', rtk.Spacer)
VolumeMeter = rtk.class('VolumeMeter', rtk.Spacer)
Entry = rtk.class('Entry', rtk.Entry)

local cyrillic_chars = {
    "а", "б", "в", "г", "д", "е", "ё", "ж", "з", "и", "й", "к", "л", "м", "н", "о", "п", "р", "с", "т", "у", "ф", "х", "ц", "ч", "ш", "щ", "ъ", "ы", "ь", "э", "ю", "я",
    "А", "Б", "В", "Г", "Д", "Е", "Ё", "Ж", "З", "И", "Й", "К", "Л", "М", "Н", "О", "П", "Р", "С", "Т", "У", "Ф", "Х", "Ц", "Ч", "Ш", "Щ", "Ъ", "Ы", "Ь", "Э", "Ю", "Я"
}
local prevValue = 0 

SimpleSlider.register{
    value = rtk.Attribute{default=0},
    min = rtk.Attribute{default=0},
    max = rtk.Attribute{default=1},
    color = rtk.Attribute{type='color', default='crimson'},
    minw = 3,
    roundrad = rtk.Attribute{default=5},
    showtext = rtk.Attribute{default=true},
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

local function hex2rgb(hex)
    hex = hex:gsub("#","")
    return tonumber("0x"..hex:sub(1,2)), tonumber("0x"..hex:sub(3,4)), tonumber("0x"..hex:sub(5,6))
end

local function get_text_color(bg_color)
    local r, g, b = hex2rgb(bg_color)
    -- Проверяем, заданы ли r, g и b
    if r and g and b then
        local brightness = (r * 299 + g * 587 + b * 114) / 1000
        if brightness > 128 then
            return '#000000'  -- Черный текст для светлого фона
        else
            return '#FFFFFF'  -- Белый текст для темного фона
        end
    else
        -- Если r, g или b не заданы, возвращаем черный цвет по умолчанию
        return '#FFFFFF'
    end
end




function SimpleSlider:_handle_draw(offx, offy, alpha, event)
    local calc = self.calc
    local x = math.round(offx + calc.x)
    local y = math.round(offy + calc.y)
    local w = math.round(calc.w)
    local h = math.round(calc.h)
    local round_radius = calc.roundrad
    local thickness = 0.5
    local aa = true
    local col = self.color
    local active_col = shift_color(col, 1, 0.9, 0.5)

    self:setcolor(active_col) --bg
    rtk.gfx.roundrect(x, y, w, h, round_radius, thickness, aa)
    
    if calc.value < 0.1 then
        self:setcolor('transparent')
    else
        self:setcolor( col ) -- active
    end
    local normalized_value = (self.calc.value - self.calc.min) / (self.calc.max - self.calc.min)
    if calc.ttype == 1 then
        local slider_h = math.floor(h * normalized_value)
        rtk.gfx.roundrect(math.round(x), math.round(y + h - slider_h), math.round(w), math.round(slider_h), round_radius, thickness, aa)
    else
        local slider_w = math.floor(w * normalized_value)
        if slider_w < round_radius * 2 then
            round_radius = slider_w / 2
        end
        rtk.gfx.roundrect(x, y, slider_w, h, round_radius, thickness, aa)
    end
    if calc.showtext then
        local displayValue = math.floor(self.calc.value * 100) .. "%" -- добавляем символ "%"
        local text_color = get_text_color(col)
        self:setcolor(text_color)
        gfx.setfont(1, self.calc.font, self.calc.fontsize)
        local str_w, str_h = gfx.measurestr(displayValue) -- измеряем ширину и высоту строки
        -- txt in slider
        gfx.x = x + (w / 2) - (str_w / 2) + self.calc.font_x
        gfx.y = y + (h / 2) - (str_h / 2) + self.calc.font_y -- выравниваем текст по вертикали
        gfx.drawstr(displayValue)
    end
end


function SimpleSlider:set_from_mouse(y_or_x)
    local dimension = self.calc.ttype == 1 and self.calc.h or self.calc.w
    local pos = self.calc.ttype == 1 and (dimension - (y_or_x - self.clienty)) or (y_or_x - self.clientx)
    local normalized_value = rtk.clamp(pos / dimension, 0, 1)
    local value = self.calc.min + normalized_value * (self.calc.max - self.calc.min)
    self:sync('value', value)
    self:animate{
        'value',
        dst = value,
        duration = 1
    }
end

function SimpleSlider:_handle_mousedown(event)
    local ok = rtk.Spacer._handle_mousedown(self, event)
    
    if ok == false then
        return ok
    end
    if event.button == lbm then
        prevValue = self.calc.value
        self:set_from_mouse(self.calc.ttype == 1 and event.y or event.x)
    end
end

function SimpleSlider:_handle_mouseup(event)
    local ok = rtk.Spacer._handle_mouseup(self, event)
    if ok == false then
        return ok
    end
    
    if self.calc.value ~= prevValue then
        local displayValue = math.floor((self.calc.value - self.calc.min) / (self.calc.max - self.calc.min) * 100)
        local callback = self.calc.onchange
        if callback then
            callback(displayValue, self.calc.value)
        end
    end
end

function SimpleSlider:_handle_dragstart(event, x, y, t)
    local draggable, droppable = rtk.Spacer._handle_dragstart(self, event)
    local draggable, droppable = rtk.Spacer._handle_dragmousemove(self, event)
    if draggable ~= nil then
        return draggable, droppable
    end
    if event.button == rtk.mouse.BUTTON_LEFT then
        self:set_from_mouse(self.calc.ttype == 1 and event.y or event.x)
        return {
            initial_pos = self.calc.ttype == 1 and event.y or event.x,
            initial_value = self.calc.value
        }, false
    end
end

function SimpleSlider:_handle_dragend(event)
    local draggable, droppable = rtk.Spacer._handle_dragend(self, event)
    if draggable ~= nil then
        return draggable, droppable
    end
end

function SimpleSlider:_handle_dragmousemove(event, args)
    local ok = rtk.Spacer._handle_dragmousemove(self, event)
    if ok == false or event.simulated then
        return ok
    end
    
    local dpos = (self.calc.ttype == 1 and event.y or event.x) - args.initial_pos
    local dimension = self.calc.ttype == 1 and self.calc.h or self.calc.w
    local delta_normalized_value = dpos / dimension
    local delta_value = delta_normalized_value * (self.calc.max - self.calc.min)
    local new_value = self.calc.ttype == 1 and (args.initial_value - delta_value) or (args.initial_value + delta_value)
    new_value = rtk.clamp(new_value, self.calc.min, self.calc.max)
    
    if new_value ~= self.calc.value then
        self:animate{
            attr = 'value',
            dst = new_value,
            duration = 0.001,
            easing="in-quad"
        }
        local displayValue = math.floor((new_value - self.calc.min) / (self.calc.max - self.calc.min) * 100)
        
        local callback = self.calc.onchange
        if callback then
            callback(displayValue, new_value) 
        end
    end
end


VolumeMeter.register{
    levels = rtk.Attribute{default={0, 0}},
    spacing = rtk.Attribute{default=1},
    mindb = rtk.Attribute{default=-64},
    color = rtk.Attribute{type='color', default='crimson'},
    gutter = rtk.Attribute{default=0.08},
    h = 1.0,
}

function VolumeMeter:initialize(attrs, ...)
    rtk.Spacer.initialize(self, attrs, VolumeMeter.attributes.defaults, ...)
end

function VolumeMeter:_handle_draw(offx, offy, alpha, event)
    local calc = self.calc
    local x = offx + calc.x
    local y = offy + calc.y
    local range = math.abs(calc.mindb)
    local chw = (calc.w - (calc.spacing * (#calc.levels - 1))) / #calc.levels
    self:setcolor(calc.color)
    gfx.a = calc.gutter
    gfx.rect(x, y, calc.w, calc.h)
    gfx.a = 1

    for _, level in ipairs(calc.levels) do
        local db = 20 * math.log(level, 10)
        local chh = (rtk.clamp(db, calc.mindb, 0) + range) / range * calc.h
        gfx.rect(x, y + calc.h - chh, chw, chh)
        x = x + chw + calc.spacing
    end
end

function VolumeMeter:set_from_track(preview, maxch)
    if not preview then
        self:attr('levels', {0})
        return
    end
    local levels = {}
    local nch = 2
    for i = 0, nch - 1 do
        _, levels[#levels+1] = reaper.CF_Preview_GetPeak(preview, i)
    end
    self:attr('levels', levels)
end


Entry.register{
    bg = rtk.Attribute{type='color', default='crimson'},
    z = 1,
    w = 1,
    h = 1,
    value="",
    border_focused = "transparent",
    border_hover = "transparent",
}

function Entry:initialize(attrs, ...)
    rtk.Entry.initialize(self, attrs, Entry.attributes.defaults, ...)
end

function Entry:onkeypress(event)
    local ok = rtk.Entry.onkeypress(self, event)
    if ok == false then
        return ok
    end
    
    local new_char = utf8.char(("0x%08x"):format(event.keycode & 0x0000FFFF))
    for _, char in ipairs(cyrillic_chars) do
        if new_char == char then
            self:delete()
            self:insert(new_char)
            break
        end
    end
    if event.keycode == rtk.keycodes.BACKSPACE then
        local value = self.value
        if value and #value > 0 then
            local byteoffset = utf8.offset(value, -1)
            if byteoffset then
                -- sub удаляет из чего-то что-то
                value = value:sub(1, byteoffset)
                self:attr('value', value)
            else
                self:attr('value', "")
            end
        end
    end
end

--[[
function rtk_FlowBox(params)
    local flowbox = rtk.Container(params)
    local spacing = params.spacing or 0
    flowbox.onreflow = function(self)
        local visible_w, new_y, new_x = 0, 0, 0
        for i, info in pairs(self.children) do
            local elem = info[1]
                if elem.visible then
                if visible_w + elem.calc.w + spacing > self.calc.w then
                    new_x, new_y, visible_w = 0, new_y + elem.calc.h + spacing, 0
                end
                elem:move(new_x, new_y)
                new_x = new_x + elem.calc.w + spacing
                visible_w = visible_w + elem.calc.w
            end
        end
    end
    return flowbox
end]]
function rtk_FlowBox(params)
    local flowbox = rtk.Container(params)
    local spacing = params.spacing or 0
    local min_elem_width = params.min_elem_width or 240 -- minw
    local last_width = nil 
    local last_visible_count = nil -- last count visible
    flowbox.onreflow = function(self)
        local visible_count = 0
        for i, info in ipairs(self.children) do
            if info[1].visible then
                visible_count = visible_count + 1
            end
        end
        if self.calc.w == last_width and visible_count == last_visible_count then
            return
        end
        last_width = self.calc.w
        last_visible_count = visible_count
        local visible_w, new_y, new_x = 0, 0, 0
        local elems_per_row = math.max(1, math.floor(self.calc.w / (min_elem_width + spacing)))
        local elem_width = self.calc.w / elems_per_row
        for i, info in ipairs(self.children) do
            local elem = info[1]
            if elem.visible then
                if visible_w + elem_width + spacing > self.calc.w then
                    new_x, new_y, visible_w = 0, new_y + elem.calc.h + spacing, 0
                end
                elem:resize(elem_width, elem.calc.h)
                elem:move(new_x, new_y)
                new_x = new_x + elem_width + spacing
                visible_w = visible_w + elem_width
            end
        end
    end
    return flowbox
end


OptionMenu = rtk.class('OptionMenu', rtk.Spacer)

OptionMenu.register{
    color = rtk.Attribute{type='color', default='#8a8a8a'},
    minh = rtk.Attribute{default=25},
    minw = rtk.Attribute{default=150},
    roundrad = rtk.Attribute{default=8},
    menu =  rtk.Attribute{},
    w = rtk.Attribute{default=100},
    autofocus = true,
    onchange = rtk.Attribute{default=nil},
    fontsize = rtk.Attribute{default=16},
    pos = rtk.Attribute{default="left"},
    text = rtk.Attribute{default=""},
    current = rtk.Attribute{default=1},
}

function OptionMenu:initialize(attrs, ...)
    rtk.Spacer.initialize(self, attrs, OptionMenu.attributes.defaults, ...)
end

function OptionMenu:_handle_draw(offx, offy, alpha, event)
    local col = self.color
    local bg_col = shift_color(col, 1.0, 1.0, 0.9)
    local bg_col2 = shift_color(bg_col, 1, 0.70, 0.70)
    local current_text = self.menu[self.current][1]

    local calc_x = math.round(offx + self.calc.x)
    local calc_y = math.round(offy + self.calc.y)
    local calc_h = math.round(self.calc.h)
    local calc_w = math.round(self.calc.w)
    
    local square_x = self.pos == "right" and offx or offx + calc_w - calc_h
    
    --main rect --
    self:setcolor(bg_col, alpha)
    rtk.gfx.roundrect(calc_x, calc_y, calc_w, calc_h, self.roundrad, 0.5, true)
    
    -- text in button
    self:setcolor("#FFFFFF", alpha)
    local new_text = rtk.Font{}
    new_text:set('font', 16, 1.0, BOLD)
    x_txt = calc_x + 10
    y_txt = calc_y + 5--calc_h--(calc_h + calc_x+2)/2
    new_text:draw(current_text, x_txt, y_txt, calc_w, calc_h, BOLD)
    
    -- square arrow
    self:setcolor(bg_col2, alpha)
    rtk.gfx.roundrect(square_x+1, calc_y+1, calc_h-2, calc_h-2, self.roundrad+2, 0.5, true)
    
   self:setcolor(col, alpha)
   local arrow_text = rtk.Font{}
   arrow_text:set('font', 17, 0.9, nil)
   local text_w, text_h = arrow_text:measure('▼')
   x_txt = square_x + (calc_h - text_w) / 2
   y_txt = calc_y + (calc_h - text_h) / 2
   arrow_text:draw('▼', x_txt, y_txt)
end

function OptionMenu:_handle_mouseenter(event)
    self.original_color = self.color
    self.hover_color = shift_color(self.color, 1, 1, 1.1)
    self.color = self.hover_color
    return true
end

function OptionMenu:_handle_mouseleave(event)
    self.color = self.original_color
end

function OptionMenu:_handle_mousedown(event)
    local ok = rtk.Spacer._handle_mousedown(self, event)
    if ok == false then
        return ok
    end
    self.color = shift_color(self.color, 1, 1, 1.12)
end

function OptionMenu:_handle_mouseup(event)
    local ok = rtk.Spacer._handle_mouseup(self, event)
    if ok == false then
        return ok
    end
    self.color = self.hover_color
end

function DrawRoundrect(col, rval)
    local spacer = rtk.Spacer{w=1, h=1, z=-1} rval = rval or 10
    spacer.ondraw = function(self, offx, offy, alpha, event)
        self:setcolor(col, alpha)
        rtk.gfx.roundrect(
            math.round(offx + self.calc.x-1),
            math.round(offy + self.calc.y-1),
            math.round(self.calc.w+2),
            math.round(self.calc.h+2),
            rval ,
            1, -- fill
            true  -- antialias
        )
        self:setcolor(shift_color(col, 1, 1, 1.15), alpha)
        rtk.gfx.roundrect(
            math.round(offx + self.calc.x),
            math.round(offy + self.calc.y),
            math.round(self.calc.w),
            math.round(self.calc.h),
            rval-2,
            0.5, -- fill
            true  -- antialias
        )
    end
    return spacer
end

function RoundrectVBox(params, col)
    local vb = rtk.Container(params)
    local cont = vb:add(rtk.Container{ref='cont', w=1, h=1, z=-2, DrawRoundrect(col):attr('ref', 'bg')})
    return vb
end


popupOption = rtk.Popup{h=2, bg='transparent', border='transparent', margin=-2}


function PopupOption(widg, VB, menu)
    VB:remove_index(2)
    new_vb = VB:add(rtk.VBox{w=1})
    
    local menu = widg.menu
    for i, name in ipairs(menu) do
        local elem_name = menu[i][1]
        local txt = new_vb:add(rtk.Text{font='Arial', fontscale=1, fontsize=17, cursor=rtk.mouse.cursors.HAND, lpadding=10, margin=0, w=1, valign='center', bborder='#4a4a4a', text=elem_name},{fillh=true})
        txt.onclick=function(self,event)
            widg:attr('current', i)
            popupOption:close{}
            SELECTED = true
            return SELECTED
        end
        txt.onmouseenter=function(self,event)
            self:attr('bg', "#6a6a6a")
            return true
        end
        txt.onmouseleave=function(self,event)
            self:attr('bg',"transparent")
        end
        if i == #menu then txt:attr('bborder', false) end
        if i == widg.current then txt:attr('text', elem_name.."  ☑") end
    end
    popupOption:attr('anchor', widg)
    popupOption:attr('child', VB)
    popupOption:attr('h', 2)
    popupOption:animate{'h', dst=VB.h, duration=0.1}
    popupOption:open{}
end