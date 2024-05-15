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
    if r and g and b then
        local brightness = (r * 299 + g * 587 + b * 114) / 1000
        if brightness > 128 then
            return '#000000'
        else
            return '#FFFFFF'
        end
    else
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


RoundButton = rtk.class('RoundButton', rtk.Text)

RoundButton.register{
    color = rtk.Attribute{type='color', default='#3a3a3a'},
    round = rtk.Attribute{default=6},
    h = rtk.Attribute{default=35},
    surface=false,
    pos = rtk.Attribute{default="left"},
    state = rtk.Attribute{default='off'},
    new_x = rtk.Attribute{default=0},
    toggle = rtk.Attribute{default=true},
    hotzone = rtk.Attribute{default=1},
    cursor=rtk.Attribute{default=rtk.mouse.cursors.HAND},
}

function RoundButton:_draw(offx, offy, alpha, event, clipw, cliph, cltargetx, cltargety, parentx, parenty)
    local calc = self.calc
    local x = math.round(offx + calc.x)
    local y = math.round(offy + calc.y)
    local w = math.round(calc.w)
    local h = math.round(calc.h)
    local color = self.color
    local color_bg = shift_color(color, 1, 0.8, 0.6)
    local round = self.round
    local activ_col 
    if self.state == 'on' then
        color = color
        activ_col = '#085308'
    else
        color = color_bg
        activ_col = '#4a4a4a'
    end
    --bg
    self:setcolor(color)
    rtk.gfx.roundrect(x,y,math.round(w),math.round(h),round,0,true)
    local square_x = x + w - (h*2+10)
    
    if self.toggle then
    --rect 
    local w_box = h*2-8
    self:setcolor(activ_col)
    rtk.gfx.roundrect(square_x+1, y+1, w_box, h-2, round-2, 0.5, true)


    --circle
    self.x_off = x+w-h-22
    self.x_on = x+w-h-6
    self.new_x = self.state == 'off' and self.x_off or self.x_on
    self:setcolor(self.state == 'off' and color.."80" or '#ffffff70')
        gfx.circle(
        self.new_x,
        y+h/2-1,
        math.min(w, h)/2.5,
        1, -- fill
        1  
        )    
    end
    --other code
    local font = rtk.Font(calc.font, calc.fontsize)
    local text = calc.text
    local textw, texth = font:measure(text)
    local textx
    local texty
    if calc.halign == 1 then
        textx = x + (w - textw) / 2
        texty = y + (h - texth) / 2
    elseif calc.halign == 2 then
        textx = x + w - textw - 10
        texty = y + (h - texth) / 2
    elseif calc.halign == 0 then
        textx = x + 10
        texty = y + (h - texth) / 2
    end
    self:setcolor("#FFFFFF")
    font:draw(text, textx, texty)
end



function RoundButton:_handle_mousedown(event)
    local ok = rtk.Text._handle_mousedown(self, event)
    if ok ~= false then
        return ok
    end
    local calc = self.calc
    local x = math.round(calc.x)
    local y = math.round(calc.y)
    local w = math.round(calc.w)
    local h = math.round(calc.h)
    if event.button == lbm then
        self.color = shift_color(self.color, 1, 1, 0.8)
        if self.toggle then
            self.state = self.state == 'off' and 'on' or 'off'
            self.new_x = self.state == 'off' and self.x_off or self.x_on
        end
    end
end

function RoundButton:_handle_mouseup(event)
    local ok = rtk.Text._handle_mouseup(self, event)
    local hover_color = self.hover_color
    if hover_color == nil then
        hover_color = self.color
    end
    self.color = hover_color
end

function RoundButton:_handle_mouseenter(event)
    local ok = rtk.Text._handle_mouseenter(self, event)
    local ok = rtk.Text.onmouseenter(self, event)
    if ok ~= nil then
        return ok
    end
    self.original_color = self.color
    self.hover_color = shift_color(self.color, 1, 1, 1.1)
    self.color = self.hover_color
    
    return true
end

function RoundButton:_handle_mouseleave(event)
    self.color = self.original_color
end



function create_shadow(parent, bgcol, borcol, dim, new_spacer)
    local spacer = new_spacer or parent:add(rtk.Spacer{margin=5,z=-4},{fillw=true,fillh=true})
    local shadow = rtk.Shadow(borcol)
    local dim =  dim * rtk.scale.reaper    

    --reset deep
    if bgcol == "transparent" and borcol == "transparent" then
        parent:attr('z', 0)
        parent:get_child(1):attr('z', -5)
        
    else
        parent:attr('z', 3)
        parent:get_child(1):attr('z', -1)
    end

    spacer.onreflow = function(self)
        shadow:set_rectangle(math.round(self.calc.w), math.round(self.calc.h), dim)
    end

    spacer.ondraw = function(self, offx, offy, alpha)
        shadow:draw(math.round(self.calc.x + offx), math.round(self.calc.y) + offy, alpha)
    end
    
    return spacer
end

function create_spacer(parent, bgcol, borcol, rval, externalSpacer, text)
    local spacer = externalSpacer or parent:add(rtk.Spacer{w=1, z=-5},{fillw=true,fillh=true})
    bgcol = bgcol or spacer.bgcol
    borcol = borcol or bgcol
    
    spacer.ondraw = function(self, offx, offy, alpha, event)
        self:setcolor(bgcol, alpha)
        rtk.gfx.roundrect(
            math.round(offx + self.calc.x-1),
            math.round(offy + self.calc.y-1),
            math.round(self.calc.w+2),
            math.round(self.calc.h+2),
            rval,
            1, -- fill
            true  -- antialias
        )
        self:setcolor(borcol, alpha)
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
    if text then
        local pad_procent = parent:add(
            rtk.Text{
                bg=bgcol,
                margin=2,
                padding=-4,
                text.."%",
                y=-1,
                valign='center'}
                ,{
                fillh=true,
                halign='center'
        })

        spacer.text=pad_procent

    end
    spacer.col=bgcol
    spacer.borcol=borcol
    spacer.round=rval
    return spacer, text
end

function recolor(spacer, bgcol, borcol, text)
    bgcol = bgcol or spacer.bgcol
    borcol = borcol or bgcol
    spacer.ondraw = function(self, offx, offy, alpha, event)
        self:setcolor(borcol, alpha)
        rtk.gfx.roundrect(
            math.round(offx + self.calc.x),
            math.round(offy + self.calc.y),
            math.round(self.calc.w),
            math.round(self.calc.h),
            self.round-2,
            0.5, -- fill
            true  -- antialias
        )
        self:setcolor(bgcol, alpha)
        rtk.gfx.roundrect(
            math.round(offx + self.calc.x-1),
            math.round(offy + self.calc.y-1),
            math.round(self.calc.w+2),
            math.round(self.calc.h+2),
            self.round,
            1, -- fill
            true  -- antialias
        )

        
    end
    if text then
        spacer.text:attr('text', text .. "%")
        spacer.text:attr('bg', borcol)
    end
    spacer.col=bgcol
    spacer.borcol=borcol
    return spacer
end

function rtk_Entry(parent, borcol, bgcol, round, placeholder)
    local borcol_act = hex_darker(borcol, -0.5)
    local bgcol_act = hex_darker(bgcol, -0.2)
    local round = round or round_rect_window
    local container_entry = parent:add(rtk.Container{cursor=rtk.mouse.cursors.BEAM, h=35}, {fillw=true, halign='right'})
    local bg_entry = create_spacer(container_entry, borcol, bgcol, round)
    
    local entry = container_entry:add(Entry{placeholder=placeholder, hotzone=5, lhotzone=10, rhotzone=10, tpadding=2, fontscale=1.2, lmargin=10,rmargin=10, w=container_entry.calc.w, h=container_entry.calc.h-8, bg=bgcol},{valign='center', })
    
    entry.onfocus = function(self, event)
        bg_entry = recolor(bg_entry, hex_darker(borcol_act, -0.2), hex_darker(bgcol_act, -0.3))
        self:attr('bg', bg_entry.bg)
        self.FOCUSED = true
        return true
    end
    
    entry.onblur = function(self, event)
        bg_entry = recolor(bg_entry, borcol, bgcol)
        self:attr('bg', bgcol)
        self.FOCUSED = false
    end
    
    entry.onmouseleave = function(self, event)
        if not self.FOCUSED then
            bg_entry = recolor(bg_entry, borcol, bgcol)
            self:attr('bg', bgcol)
        end
    end
    
    entry.onmouseenter = function(self, event)
        if not self.FOCUSED then
            bg_entry = recolor(bg_entry, borcol_act , bgcol_act)
            self:attr('bg', bgcol_act)
        end
    end

    container_entry.onclick = function(self, event)
        entry:focus()
    end

    entry:onmouseenter()
    entry:onmouseleave()
    return entry, container_entry
end

function create_container(params, parent, txt)
    local container = parent:add(rtk.Container(params))
    local vbox = container:add(rtk.VBox{ref='VBOX', fillw=true},{})
    local heading = vbox:add(rtk.Container{ref='HEAD', margin=0,h=40},{fillw=true})
    if txt then heading:add(rtk.Text{fontsize=18,fontflags=rtk.font.BOLD,y=heading.calc.h/5,txt,halign='center',h=1,w=1}) end
    local rect_heading = create_spacer(heading, COL1, COL2, round_rect_window)
    local hiden_bottom = heading:add(rtk.Spacer{ref='HIDE', margin=0,y=32,h=35,w=1,bg=COL3})
    local bg_roundrect = create_spacer(container, COL1, COL3, round_rect_window)
    bg_roundrect:attr('ref','BG')
    local vp_vbox = rtk.VBox{spacing=def_spacing, padding=2, margin=2,w=1}
    local viewport = vbox:add(rtk.Viewport{child = vp_vbox, smoothscroll = true,scrollbar_size = 2,z=2})
    
    return container, heading, vp_vbox, viewport
end

function create_b_set(ref, text)
    return rtk.Button{tagalpha=0.1, color='#3a3a3a20',tagged=true, cursor=rtk.mouse.cursors.HAND,gradient=0, padding=1,fontsize=21, ref=ref, icon=ic_off, w=1, h=1, flat=true, text}
end

function create_b(CONT, txt, w, h, bparms, icon, animate)
    animate = animate == nil and true or animate
    local b_ref = txt:gsub(" ", "_"):gsub("%W", "_")
    local container = CONT:add(rtk.Container{cursor=rtk.mouse.cursors.HAND, hotzone=3, h=h, w=w, halign='center'},{halign='center'})
    local b_spacer = create_spacer(container, COL8, COL18, round_rect_list); b_spacer:attr('ref', b_ref); b_spacer:attr('w', w)
    
    local function animate_or_attr(self, attr, value)
        if animate then
            if GLOBAL_ANIMATE then
                self:animate{attr, dst=value, duration=0.05}
            else
                self:attr(attr, value)
            end
        end
    end

    local txt_v
    if bparms then
        txt_v = container:add(rtk.Button{tpadding=3.5,lpadding=7.5,disabled=true,surface=false, icon=icon, fontsize=18, w=container.calc.w, h=container.calc.h, ref=b_ref},{ valign='center', halign='center'})
    else
        txt_v = container:add(rtk.Text{fontsize=18, w=1, h=1, ref=b_ref, txt, valign='center', halign='center'})
    end

    container.onmouseenter = function(self, event)
        animate_or_attr(self, 'h', h+(h/6))
        animate_or_attr(txt_v, 'fontscale', 1.1)
        b_spacer = recolor(b_spacer, COL4, COL7)
        return true
    end

    container.onmouseleave = function(self, event)
        animate_or_attr(self, 'h', h)
        animate_or_attr(txt_v, 'fontscale', 1.0)
        b_spacer = recolor(b_spacer, COL18, COL18)
        return true
    end

    container.onmousedown = function(self, event)
        animate_or_attr(txt_v, 'fontscale', 1.01)
        b_spacer = recolor(b_spacer, COL18, COl12)
        return true
    end

    container.onmouseup = container.onmouseenter
    return container
end