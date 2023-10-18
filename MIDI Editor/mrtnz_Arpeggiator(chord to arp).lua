-- @description Arpeggiator(test version)
-- @author mrtnz
-- @version 1.0.25
-- @about
--   test
-- @provides
--   ../MIDI editor/modify.json
--   ../MIDI editor/original.json
--   ../libs/json.lua
--   ../libs/rtk.lua
--   ../images/Plus.png
--   ../images/add.png
--   ../images/bulb1.png
--   ../images/bulb2.png
--   ../images/bulb_en.png
--   ../images/close.png
--   ../images/down.png
--   ../images/gear.png
--   ../images/gear_l.png
--   ../images/gen_p.png
--   ../images/key.png
--   ../images/kick.png
--   ../images/leg.png
--   ../images/link.png
--   ../images/link2.png
--   ../images/loop.png
--   ../images/oct.png
--   ../images/off.png
--   ../images/on.png
--   ../images/onm.png
--   ../images/onof.png
--   ../images/page.png
--   ../images/past.png
--   ../images/pin.png
--   ../images/pinned.png
--   ../images/preset.png
--   ../images/rand.png
--   ../images/refresh.png
--   ../images/rnd.png
--   ../images/save.png
--   ../images/snare.png
--   ../images/ss.png
--   ../images/tab.png
--   ../images/tr.png
--   ../images/trash.png
--   ../images/up-and-down.png
--   ../images/up.png
-- @changelog
--   Bug fix: fix error 'for'





local resourcePath = reaper.GetResourcePath()
local scriptPath = ({reaper.get_action_context()})[2]
local scriptDir = scriptPath:match('^(.*[/\\])')
local rtkPath = resourcePath .. "../libs/"
local imagesPath = scriptDir .. "../images/"
local jsonPath = scriptDir .. "../libs/"  

package.path = package.path .. ";" 
              .. rtkPath .. "?.lua;" 
              .. jsonPath .. "?.lua;"  
              .. scriptDir .. "?.lua"

require 'rtk'
local json = require("json")
rtk.add_image_search_path(imagesPath, 'dark')
reaper.GetSetProjectInfo_String(0, "PROJOFFS", "0", true)


font="Trebuchet MS"
base_color = "#3a3a3a"
base_wight_button = 94

advanced_color_current = base_color
advanced_color_pressed = "#6d694f"

legato_color_current = base_color
legato_color_pressed = "#4a544d" 

auto_apply_color_current="#322a26"
auto_apply_color_pressed="#211c1a"

generate_color_current = "#3d342f"
generate_color_pressed = "#220a04"

modes_button_color_current = base_color
modes_button_color_pressed = "#443433"

knob_rate_label_color = "white"
main_background_color = "#1a1a1a"

advanced_color_main_sl_label="orange"
adv_mode_bg_window = "#242424"
color_b_hb = "#3a3a3a"
color_apps_def="#2a2a2a"

adv_mode_x=30
adv_mode_y=45
adv_mode_w=150
adv_mode_h=100

adv_thumb_size=5
adv_track_size=7
adv_color=advanced_color_main_sl_label
adv_thumbcolor="transparent"
adv_slider_w=110
adv_fontsize=16

bg_all="#262422" --bg advanced wnd

base_w = 35
base_w_slider=58
spacing_1 = base_w/base_w
base_w_for_chord_tabs=54
big_w_for_chord_tabs = base_w_for_chord_tabs + 10
base_h_for_chord_tabs=25
base_color = "#3a3a3a"

pressed_color_tabs = "#6d838f50"
def_color_tabs = "#70809040"

velocity_color_sliders="#55666f"
octave_color_sliders="#666f55"
gate_color_sliders="#6f5e55"
ratchet_color_sliders="#5e556f"
rate_color_sliders="#471726"
v_sliders_modes_pressed_color="#9a9a9a"

modes_button_wight = base_wight_button - 15
height=30
sectionID = "" 
initialW=355
initialH=400
local scale_2
local func_on = true

function p_run()
  if func_on == true then
    run()
  end
end
local sectionID = "YourSectionID"
local savedVisibility = reaper.GetExtState(sectionID, "appVisibility")
local isAppVisible = (savedVisibility ~= "hidden")


local wnd = rtk.Window{
    w = initialW,
    h = initialH,
    title = 'Midi Arpeggiator',
    bg = main_background_color,
    resizasble=true,
    opacity=0.98,
    expand=1,
    minw=100,
    minh=100,
    maxh=1000,
    maxw=1000,
    
}


local hbox_app = wnd:add(rtk.HBox{tooltip='click to hide',h=height,y=wnd.h-height},{fillw=true})
local app = hbox_app:add(rtk.Application())




local grid = 3840

local mode = "down"
local grid_step = 240
local step = 3
local octave = 0 
local step_mode = 1 
local velocity = 100
local extendNotesFlag = false 
local grid_values = {1920, 1280, 960, 640, 480, 320, 240, 160, 120, 80, 60}
--[[
local step_grid = {
  { --frstchord
    mode = "down",
    {step = 1, grid_step = 480, velocity = 100, octave = 0, ratchet = 0, length = 100},
    {step = 2, grid_step = 480, velocity = 100, octave = 0, ratchet = 0, length = 100},
    {step = 3, grid_step = 480, velocity = 100, octave = 0, ratchet = 0, length = 100},
    {step = 4, grid_step = 480, velocity = 100, octave = 0, ratchet = 0, length = 100},
  },
  { --scndchord
    mode = "up",
    {step = 1, grid_step = 480, velocity = 100, octave = 0, ratchet = 0, length = 100},
    {step = 2, grid_step = 480, velocity = 100, octave = 0, ratchet = 0, length = 100},
    {step = 3, grid_step = 480, velocity = 100, octave = 0, ratchet = 0, length = 100},
    {step = 4, grid_step = 480, velocity = 100, octave = 0, ratchet = 0, length = 100},
  },
}
]]


local step_grid = {
  { --frstchord
    mode = "down",
    {step = 1, grid_step = 480, velocity = 100, octave = 0, ratchet = 0, length = 100},
    {step = 2, grid_step = 480, velocity = 100, octave = 0, ratchet = 0, length = 100},
    {step = 3, grid_step = 480, velocity = 100, octave = 0, ratchet = 0, length = 100},
    {step = 4, grid_step = 480, velocity = 100, octave = 0, ratchet = 0, length = 100},
    {step = 5, grid_step = 480, velocity = 100, octave = 0, ratchet = 0, length = 100},
    {step = 6, grid_step = 480, velocity = 100, octave = 0, ratchet = 0, length = 100},
    {step = 7, grid_step = 480, velocity = 100, octave = 0, ratchet = 0, length = 100},
    {step = 8, grid_step = 480, velocity = 100, octave = 0, ratchet = 0, length = 100},
  }
}

--[[
===grid sizes===

- 1/1 - 3840
- 1/2 - 1920
- 1/3 - 1280
- 1/4 - 960
- 1/6 - 640
- 1/8 - 480
- 1/12 - 320
- 1/16 - 240
- 1/24 - 160
- 1/32 - 120
- 1/48 - 80
- 1/64 - 60
]]

function makeDarker(color, amount)
        local r, g, b = color:match("#(%x%x)(%x%x)(%x%x)")
        r = math.floor(math.max(0, tonumber(r, 16) * (1 - amount)))
        g = math.floor(math.max(0, tonumber(g, 16) * (1 - amount)))
        b = math.floor(math.max(0, tonumber(b, 16) * (1 - amount)))
        return string.format("#%02x%02x%02x", r, g, b)
end


local up = rtk.Image.icon('up'):scale(120,120,22,7)
local down = rtk.Image.icon('down'):scale(120,120,22,7)
local rand = rtk.Image.icon('rand'):scale(120,120,22,7)
local rnd = rtk.Image.icon('rnd'):scale(120,120,22,7)
local oct = rtk.Image.icon('oct'):scale(120,120,22,7)
local leg = rtk.Image.icon('leg'):scale(120,120,22,7)
local save = rtk.Image.icon('save'):scale(120,120,22,7)
local delete = rtk.Image.icon('trash'):scale(120,120,22,7)
local page = rtk.Image.icon('page'):scale(120,120,22,7)
local bulb = rtk.Image.icon('bulb1'):scale(120,120,22,7)
local bulb2 = rtk.Image.icon('bulb2'):scale(120,120,22,7)
local bulb_en = rtk.Image.icon('bulb_en'):scale(120,120,22,7)
local tab_b = rtk.Image.icon('tab'):scale(120,120,22,7)
local pin = rtk.Image.icon('pin'):scale(120,120,22,7)
local pinned = rtk.Image.icon('pinned'):scale(120,120,22,7)
local preset = rtk.Image.icon('preset'):scale(120,120,22,7)
local add = rtk.Image.icon('add'):scale(120,120,22,6)
local on = rtk.Image.icon('on'):scale(120,120,22,7)
local off = rtk.Image.icon('off'):scale(120,120,22,7)
local onof = rtk.Image.icon('onof'):scale(120,120,22,7)
local refresh = rtk.Image.icon('refresh'):scale(120,120,22,6.6)
local loop = rtk.Image.icon('loop'):scale(120,120,22,7)
local up_and_down = rtk.Image.icon('up-and-down'):scale(120,120,22,7)




local savedState = reaper.GetExtState(sectionID, "pinState")
local container = wnd:add(rtk.VBox{y=-35})
local vbox2 = container:add(rtk.VBox{y=50,padding=5,x=wnd.w/2-50})
local vbox = container:add(rtk.VBox{spacing=10})

hb_o = vbox:add(rtk.HBox{y=60,x=10,spacing=2,padding=25})
bt2_btgen = hb_o:add(rtk.HBox{w=base_wight_button})
app_hbox=wnd:add(rtk.HBox{padding=2,border='#25252580',bg="#22222250"})

local pin_b = app_hbox:add(rtk.Button{border="#3a3a3a35",gradient=3,color=color_apps_def,padding=4,icon=pinned,flat=true})

local function updatePinState(isPressed)
    if isPressed then
        pin_b:attr('icon', pin)
        pin_b:attr('flat', false)
        wnd:attr('pinned', true)
    else
        pin_b:attr('icon', pinned)
        pin_b:attr('flat', true)
        wnd:attr('pinned', false)
    end
end


if savedState == "true" then
    pin_b.pressed = true
    updatePinState(true)
else
    pin_b.pressed = false
    updatePinState(false)
end


app_hbox:add(rtk.Box.FLEXSPACE)

local reset_b = app_hbox:add(rtk.Button{icon=refresh,border="#3a3a3a65", halign='center', padding=4, gradient=3, color=color_apps_def})

local scale_b = app_hbox:add(rtk.Button{border="#3a3a3a65",halign='center',padding=4,gradient=3,color=color_apps_def,tagged=true,'1.0',iconpos='left',icon=loop,})

local function applyScale(scale)
    rtk.scale.user = scale
    scale_b:attr('label', string.format("%.2f", scale))
    wnd:attr('w', initialW * scale)
    wnd:attr('h', initialH * scale)
    wnd:reflow()
end

local savedScale = reaper.GetExtState(sectionID, "windowScale")
local savedPosX = reaper.GetExtState(sectionID, "windowPosX")
local savedPosY = reaper.GetExtState(sectionID, "windowPosY")

if savedScale ~= "" then
    applyScale(tonumber(savedScale))
end

if savedPosX ~= "" and savedPosY ~= "" then
    wnd:attr('x', tonumber(savedPosX))
    wnd:attr('y', tonumber(savedPosY))
end



local button2 = bt2_btgen:add(rtk.Button{
    gradient=3,
    color=auto_apply_color_current,
    spacing=2,
    padding=4,
    font="Trebuchet MS",
    tagged=true,
    icon=on,
    h=29,
    w=base_wight_button,
    halign='center',
    label='Auto Apply',
    fontsize=16,
    z=2
    
    })
    
    
    
local btn_generate = bt2_btgen:add(rtk.Button{
    gradient=4,
    color=generate_color_current,
    spacing=2,
    padding=4,
    font="Trebuchet MS",
    tagged=true,
    icon=gen,
    h=29,
    w=2,
    halign='center',
    label='Generate',
    z=2,
})
    

nw_value = base_wight_button

advanced_slid_b=hb_o:add(rtk.VBox{})
local button_adv = advanced_slid_b:add(rtk.Button{
        gradient=3,
        color=advanced_color_current,
        spacing=2,
        padding=4,
        font="Trebuchet MS",
        tagged=true,
        icon=bulb,
        h=29,
        w=base_wight_button,
        halign='center',
        label='Advanced',
        z=1,

})


advanced_slider_slider=advanced_slid_b:add(rtk.VBox{h=1.1})
local new_color_advanced = makeDarker("#6d694f", -0.5)


local slider_mod_advanced = advanced_slider_slider:add(rtk.Slider{
  w=nw_value,
  thumbcolor='transparent',
  color=new_color_advanced,
  thumsize=0.2,
  h=1.1,
  min=1,
  max=3,
  step=1,
  tracksize=2,
  value=2,
  hotzone=1,
  lhotzone=1,
  --cursor=rtk.mouse.cursors.REAPER_BORDER_RIGHT,
})

btn_generate:hide()


    
local leg_notes=hb_o:add(rtk.VBox{})
local button_str = leg_notes:add(rtk.Button{
    color=legato_color_current,
    gradient=3,
    spacing=2,
    padding=4,
    font=font,
    tagged=true,
    icon=leg,
    w=base_wight_button,
    halign='center',
    label='Legato',
    h=29,
    z=1,
    })

local new_color = makeDarker("#4a544d", -0.5)



local hb_stac_leg = leg_notes:add(rtk.HBox{h=1.1})
slid_length = hb_stac_leg:add(rtk.Slider{
  w=base_wight_button,
  thumbcolor='transparent',
  color=new_color,
  thumsize=1,
  h=1.1,
  min=0,
  max=100,
  step=1,
  value=100,
  tracksize=2,
  
})
slid_length:hide()

local all_advanced_mode_container = container:add(rtk.VBox{h=240,bg='#FFDAB96',border='#70809019',y=0,x=10,spacing=2,padding=22})
local chord_str = all_advanced_mode_container:add(rtk.HBox{border='gray',spacing=5}) --линия тулбара

b_create_chord = chord_str:add(rtk.Button{flat=true,font=font,halign='center',w=75,tagged=false,icon=page,padding=3,spacing=5,"Create"})
b_save_chord = chord_str:add(rtk.Button{disabled=true,flat=true,font=font,halign='center',w=75,tagged=false,icon=save,padding=3,spacing=5,"Save"})
b_delete_chord = chord_str:add(rtk.Button{disabled=true,flat=true,font=font,halign='center',w=75,tagged=false,icon=preset,padding=3,spacing=5,"Presets"})

local btn_info 
local chord_b_box = all_advanced_mode_container:add(rtk.HBox{x=10,y=-20,spacing=5,padding=25}) --линия кнопок


all_advanced_mode_container:hide()





--------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------
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
    rtk.Spacer.initialize(self, attrs, SimpleSlider.attributes.defaults, ...)
end


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
    local text_to_display
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


-- В функции SimpleSlider:getDisplayValue()
function SimpleSlider:getDisplayValue()
    local calc = self.calc
    local text_to_display
    if self.ticklabels then
        local index = math.floor(calc.value * (#self.ticklabels - 1) + 0.5) + 1
        text_to_display = self.ticklabels[index]
    elseif type(self.min) == "table" and type(self.max) == "table" then
        text_to_display = string.format("%d", math.floor(calc.value * 100))
    else
        local min = type(self.min) == "table" and self.min[1] or self.min
        local max = type(self.max) == "table" and self.max[1] or self.max
        text_to_display = string.format("%d", math.floor(min + calc.value * (max - min)))
    end

    -- Для rate: преобразуем доли в число и умножаем на 480*8
    if self.name == "rate" then
        local fractions = {["1/2"]=0.5, ["1/3"]=1/3, ["1/4"]=0.25, ["1/6"]=1/6, ["1/8"]=0.125, ["1/12"]=1/12, ["1/16"]=1/16, ["1/24"]=1/24, ["1/32"]=1/32, ["1/48"]=1/48, ["1/64"]=1/64}
        local fraction_value = fractions[text_to_display]
        if fraction_value then
            text_to_display = tostring(math.floor(fraction_value * 480 * 8))
        end
    end

    return text_to_display or "No Value!"
end



--------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------

SliderGroup = rtk.class('SliderGroup', rtk.HBox)


function SimpleSlider:_handle_mousedown(event)
    
    local ok = rtk.Spacer._handle_mousedown(self, event)
    if ok == false then
    all_info_sliders(self)
        return ok
    end
    
    if event.button == rtk.mouse.BUTTON_RIGHT then
        local menu2 = rtk.NativeMenu()
        menu2:set({
            {"Random", id='random'},
            {"Ascending", id='ascending'},
            {"Descending", id='descending'},
            {"Wave", id='wave'},
            {"Up from Current", id='up_from_current'},
            {"Down from Current", id='down_from_current'}
        })
        menu2:open_at_mouse():done(function(item)
            if not item then
                return
            end
            self.parent:apply_mode(self, item.id)
        end)
    else
        self:set_from_mouse_y(event.y)
        
    end
    
end

function SliderGroup:apply_mode(current_slider, mode)
    local total_sliders = #self.children
    local current_slider_idx
    local duration = 0.3 

    for i, child in ipairs(self.children) do
        if child[1] == current_slider then
            current_slider_idx = i
            break
        end
    end
    if mode == 'wave' then
        local even_value = 0.1 + 0.8 * math.random()
        local odd_value = even_value + 0.3
        if odd_value > 0.9 then
            odd_value = even_value - 0.3
        end
        for i, child in ipairs(self.children) do
            local slider = child[1]
            if rtk.isa(slider, SimpleSlider) then
                local new_value = i % 2 == 0 and even_value or odd_value
                slider:animate{
                    attr = 'value',
                    dst = new_value,
                    duration = duration
                }
            end
        end
        all_info_sliders(self, children, event, x, y, t)
        return
    end
    for i, child in ipairs(self.children) do
        local slider = child[1]
        if rtk.isa(slider, SimpleSlider) then
            local new_value
            if mode == 'random' then
                new_value = 0.1 + 0.8 * math.random()
            elseif mode == 'ascending' then
                new_value = 0.1 + (0.8 * (i - 1) / (total_sliders - 1))
            elseif mode == 'descending' then
                new_value = 0.1 + (0.8 * (total_sliders - i) / (total_sliders - 1))
            elseif mode == 'up_from_current' then
                if i == current_slider_idx then
                    new_value = 0.9
                elseif i < current_slider_idx then
                    new_value = 0.1 + (0.8 * (i - 1) / (current_slider_idx - 1))
                else
                    new_value = 0.1 + (0.8 * (total_sliders - i) / (total_sliders - current_slider_idx))
                end
            elseif mode == 'down_from_current' then
                if i == current_slider_idx then
                    new_value = 0.1
                elseif i > current_slider_idx then
                    new_value = 0.1 + (0.8 * (i - current_slider_idx) / (total_sliders - current_slider_idx))
                else
                    new_value = 0.1 + (0.8 * (current_slider_idx - i) / (current_slider_idx - 1))
                end
                
            end
            all_info_sliders(self, children, event, x, y, t)
            slider:animate{
                attr = 'value',
                dst = new_value,
                duration = duration
            }
        end
    end
    all_info_sliders(self, children, event, x, y, t)
    
end
local first_slider_value = nil
local focused_slider = nil

function SliderGroup:_handle_mousedown(event, x, y, t)
    all_info_sliders(self, event, x, y, t)
end
function SliderGroup:_handle_dragstart(event, x, y, t)
    first_slider_value = nil
    focused_slider = nil
    local draggable, droppable = rtk.HBox._handle_dragmousemove(self, event)
    if draggable ~= nil then
        return draggable, droppable
    end
    return {lastx=x, lasty=y}, false
end




local last_created_button_number = 0
local buttonCount = 1
local boxes = {}
local container_advanced_3
local index_strip = 8
local next_button_index = 1 
local buttons = {}  
local boxes = {}
local on_deferred = false


function all_info_sliders(self, children, event, x, y, t)
    if step_mode ~= 3 then
        return 
    end


    local chord_index = active_chord_index
    

    if not step_grid[chord_index] then
        step_grid[chord_index] = {mode = "down"}
    end
    
    for i = 1, #self.children do
        local child = self.children[i][1]
        if rtk.isa(child, SimpleSlider) then
            local step = child.slider_index
    
            if not step_grid[chord_index][step] then
                step_grid[chord_index][step] = {
                    step = step,
                    grid_step = 480, 
                    velocity = 100,    
                    octave = 0,  
                    ratchet = 0,  
                    length = 0 
                }
            end
    

            if child.name == "rate" then
                step_grid[chord_index][step].grid_step = tonumber(child:getDisplayValue()) or 480
            elseif child.name == "velocity" then
                step_grid[chord_index][step].velocity = tonumber(child:getDisplayValue()) or 100
            elseif child.name == "octave" then
                step_grid[chord_index][step].octave = tonumber(child:getDisplayValue()) or 0
            elseif child.name == "ratchet" then
                step_grid[chord_index][step].ratchet = tonumber(child:getDisplayValue()) or 0
            elseif child.name == "gate" then
                step_grid[chord_index][step].length = tonumber(child:getDisplayValue()) or 0
            end
        end
    end

    -- Проверяем значение переменной-флага перед вызовом reaper.defer
    if on_deferred then
        reaper.defer(function() all_info_sliders(self, children, event, x, y, t) end)
    end
end



function SliderGroup:_handle_dragend(event, x, y, t)
    all_info_sliders(self, event, x, y, t)
end


local function print_slider_info()
    local msg = "Step Grid Info:\n"
    for chord_idx, chord_data in ipairs(step_grid) do
        msg = msg .. "Chord " .. chord_idx .. " (Mode: " .. chord_data.mode .. ")\n"
        for step, step_data in ipairs(chord_data) do
            if type(step_data) == "table" then
                msg = msg .. "  Step " .. step .. ": "
                for k, v in pairs(step_data) do
                    if k ~= "step" then
                        msg = msg .. k .. "=" .. tostring(v) .. ", "
                    end
                end
                msg = msg:sub(1, -3)
                msg = msg .. "\n"
            end
        end
    end
    reaper.ShowConsoleMsg(msg)
end



function SliderGroup:_handle_mouseup(event, x, y, t)
    all_info_sliders(self, event, x, y, t)
end


function SliderGroup:_handle_dragmousemove(event, arg)
    local ok = rtk.HBox._handle_dragmousemove(self, event)
    if ok == false or event.simulated then
        return ok
    end
    --show_info(self, event, arg, x, y, t)
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
        end
    end
    arg.lastx = event.x
    arg.lasty = event.y
    all_info_sliders(self, event, x, y, t)
end
    
local slider_mode_win
--------------------------------------------------------------------------------------------------------
local function updateActiveChordBorder(color)
    if active_chord_index and buttons[active_chord_index] then
        buttons[active_chord_index]:attr('bborder', color)
        buttons[active_chord_index]:attr('bg', color)
        buttons[active_chord_index]:attr('tborder', color)
    end
end
local function updateChordColors()
    for i, btn in ipairs(buttons) do
        if i == active_chord_index then
            -- Если это активная кнопка, установите специальный цвет
            btn:attr('color', "#708090")
        else
            -- Иначе установите цвет по умолчанию
            btn:attr('color', def_color_tabs)
        end
    end
end
local hibox_buttons_browser=all_advanced_mode_container:add(rtk.HBox{expand=1, w=280,y=-50})
local active_color = '#000000'  -- Изначальный цвет
local function create_new_box()
    

    local container_advanced_3 = all_advanced_mode_container:add(rtk.VBox{})
    local vbox = container_advanced_3:add(rtk.VBox{z=1,y=-48,w=280, h=100})
    local slider_groups = {}
    local buttons2 = {} 
    local slider_colors = {} 
    local button_names = {'velocity', 'octave', 'gate', 'ratchet', 'rate'}
    
    local slider_and_buttons_modes = container_advanced_3:add(rtk.VBox{y=-40,x=-5})
    local container_advanced_vb = slider_and_buttons_modes:add(rtk.HBox{})
    
    local slider_params = {
        velocity = {color=velocity_color_sliders,min=1, max=127, value=0.79},
        octave = {target='center',color=octave_color_sliders, min=-5, max=5, value=0.5},
        gate = {color=gate_color_sliders, min={1, "%"}, max={100, "%"}, value=1},
        ratchet = {color=ratchet_color_sliders, min=0, max=10, value=0.05},
        rate = {color=rate_color_sliders, min=1, max=12, ticklabels={"1/2", "1/3", "1/4", "1/6", "1/8", "1/12", "1/16", "1/24", "1/32", "1/48", "1/64"}, value=0.5}
    }
    local function create_slider(group, params, name, chord_number, slider_type)
        params.w = base_a
        params.lhotzone = 5
        params.font = 'Times'
        params.valign = 'down'
        params.text_color = "#ffffff"
        params.halign = 'left'
        params.rhotzone = 5
        params.name = name  
        
        local slider_line_v = group:add(SimpleSlider(params), {fillw=true})
        
        return slider_line_v
    end
    
    local function add_slider_to_group(group, params, name, j) 
        local slider = create_slider(group, params, name)
        slider.chord_index = last_created_button_number
        slider.slider_index = j 
    end
    
    local function toggle_groups(active_index)
        for i, group in ipairs(slider_groups) do
            if i == active_index then
                group:show()
                buttons2[i]:attr('color', slider_colors[i] .. "50")
                buttons2[i]:attr('gradient', 7)
                updateActiveChordBorder(slider_colors[i])  -- Обновите цвет bborder у активной кнопки chord
            else
                group:hide()
                buttons2[i]:attr('color', '#3a3a3a')
                buttons2[i]:attr('gradient', 2)
                
            end
            updateChordColors()
        end
         
    end
    
    
    
    for i, name in ipairs(button_names) do
        local slider_group = vbox:add(SliderGroup{spacing=spacing_1, expand=5})
        slider_group:hide()
        table.insert(slider_groups, slider_group)
        
        local buttons_type = container_advanced_vb:add(rtk.Button{
            halign='center',
            spacing=2, 
            padding=2,
            w=base_w_slider, 
            label=name, 
            flat=false,
            font="Georgia",
            color="#3a3a3a",
            gradient=2,
            
        })
        buttons_type.onclick = (function(idx)
            return function()
                toggle_groups(idx)
            end
        end)(i)

        for j = 1, index_strip do
            add_slider_to_group(slider_group, slider_params[name], name, j)  -- добавлен параметр j
        end
        table.insert(buttons2, buttons_type)
        table.insert(slider_colors, slider_params[name].color)
    end
    slider_groups[1]:show()
    toggle_groups(1) 
    
    return container_advanced_3, slider_groups, button_names
end
    
btn_info = chord_str:add(rtk.Button{flat=true,font=font,halign='center',w=45,padding=3,spacing=5,"Info"})
btn_info.onclick = function(self)
    print_slider_info()
end
local function hide_all_boxes_and_reset_buttons()
    for _, box in pairs(boxes) do
        box:hide()
    end
end

local function update_labels()
    for i, btn in ipairs(buttons) do
        btn:attr('label', "Chord " .. i)
    end
end
active_chord_index = 1 
local function removeChordFromStepGrid(chordIndex)
    if chordIndex >= 1 and chordIndex <= #step_grid then
        table.remove(step_grid, chordIndex)
    end
end
local function create_new_button_and_box(last_created_button_number)
    local new_box, slider_groups, button_names = create_new_box()
    new_box.slider_groups = slider_groups
    new_box.button_names = button_names
    boxes[last_created_button_number] = new_box
    local new_button = hibox_buttons_browser:add(rtk.Button{
        color=def_color_tabs,
        gradient=3,
        halign='center',
        spacing=4,
        padding=2,
        h=base_h_for_chord_tabs,
        expand=0.1,
        fillw=true,
        label="Chord " .. last_created_button_number,
        bborder=active_color  
    },{fillw=true})
    table.insert(buttons, new_button)
    new_box:show()
    new_button.onclick = function(self, event)
        local handle_right_click = function()
            local menu2 = rtk.NativeMenu()
            menu2:set({{"Delete", id='delete'}})
            menu2:open_at_mouse():done(function(item)
                if item and item.id == 'delete' then

                    hibox_buttons_browser:remove(new_button)
                    all_advanced_mode_container:remove(new_box)
                    for i, btn in ipairs(buttons) do
                        if btn == new_button then
                            table.remove(buttons, i)
                            table.remove(boxes, i)
                            removeChordFromStepGrid(i) 
                            active_chord_index = 1  -- Обновляем active_chord_index
                            break
                        end
                    end
                    
                    table.remove(step_grid, active_chord_index)
                    update_labels()
                end
            end)
             
        end

        local handle_left_click = function()
                    hide_all_boxes_and_reset_buttons()
                    new_box:show()
                    active_chord_index = last_created_button_number  -- обновите индекс активного аккорда
                    updateChordColors()  -- обновите цвета кнопок chord
        end

        if event.button == rtk.mouse.BUTTON_RIGHT then
            handle_right_click()
        elseif event.button == rtk.mouse.BUTTON_LEFT then
            handle_left_click()
        elseif event.button == rtk.mouse.BUTTON_MIDDLE then
            hibox_buttons_browser:remove(new_button)
            all_advanced_mode_container:remove(new_box)
            for i, btn in ipairs(buttons) do
                if btn == new_button then
                    table.remove(buttons, i)
                    table.remove(boxes, i)
                    removeChordFromStepGrid(i) 
                    active_chord_index = 1  -- Обновляем active_chord_index
                    updateChordColors()
                    break
                end
            end
            
            table.remove(step_grid, active_chord_index)
            update_labels()   
        end
        next_button_index = next_button_index + 1
        active_chord_index = last_created_button_number
    end
    update_labels()
    active_chord_index = last_created_button_number
    updateChordColors()
    return new_button, new_box
end





--------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------

local box_second_advanced = vbox:add(rtk.HBox{})
local slider_line = box_second_advanced:add(rtk.VBox{y=27,spacing=2,padding=25})
local sliders_box_v = box_second_advanced:add(rtk.VBox{bg=adv_mode_bg_window,spacing=2,padding=3,x=adv_mode_x,w=adv_mode_w,h=adv_mode_h,y=adv_mode_y})
slider_first=sliders_box_v:add(rtk.HBox{y=10})
local slider_velocity = slider_first:add(rtk.Slider{
    thumbsize=adv_thumb_size,
    tracksize=adv_track_size,
    color=adv_color,
    step=1,
    min=0,
    max=127,
    w=adv_slider_w,
    thumbcolor=adv_thumbcolor,
    value=100,
})
vel_text=slider_first:add(rtk.Text{fontsize=adv_fontsize,w=28,x=4,"VEL",y=-3})
sliders_box_v:hide()
slider_sec=sliders_box_v:add(rtk.HBox{y=14,halign='center'})
step_text=slider_sec:add(rtk.Text{fontsize=adv_fontsize,w=30,y=7,"STEP"})
local slider_velocity2 = slider_sec:add(rtk.Slider{
    thumbsize=adv_thumb_size,
    tracksize=adv_track_size,
    color=adv_color,
    x=-1,
    w=adv_slider_w,
    ticksize=2,
    y=11,
    step=1,
    min=2,
    max=8,
    ticks=true,
    thumbcolor=adv_thumbcolor,
    value=3,
    
})
slider_thr=sliders_box_v:add(rtk.HBox{y=40})
local slider_velocitythr = slider_thr:add(rtk.Slider{
    thumbsize=adv_thumb_size,
    tracksize=adv_track_size,
    color=adv_color,
    step=1,
    min=0,
    max=110,
    w=adv_slider_w,
    thumbcolor=adv_thumbcolor,
    value=0,
    
})
rate_text=slider_thr:add(rtk.Text{w=28,x=4,fontsize=adv_fontsize,"RATE",y=-3})
local vert_b = vbox:add(rtk.HBox{x=10,spacing=2,padding=25})
local b_up = vert_b:add(rtk.Button{flat=true,cursor=rtk.mouse.cursors.HAND,pacing=5,padding=4,font=font,tagged=true,icon=up,halign='center',w=base_wight_button,'Up'})
local b_down = vert_b:add(rtk.Button{cursor=rtk.mouse.cursors.HAND,spacing=5,padding=4,font=font,tagged=true,icon=down,halign='center',w=base_wight_button,'Down'})
vert_b_line=vert_b:add(rtk.HBox{})
local b_rand = vert_b_line:add(rtk.Button{iconpos='left',cursor=rtk.mouse.cursors.HAND,spacing=5,padding=4,font=font,tagged=true,icon=rand,halign='center',w=base_wight_button,'Random'})
local button = vert_b_line:add(rtk.Button{iconpos='left',color=color_b_hb,gradient=3,spacing=5,padding=4,font=font,tagged=true,icon=oct,w=10,h=26,halign='center',label='0'})
button:hide()





--обработчики
rtk.tooltip_delay = 0.1
hbox_app.onclick = function(self)
    if isAppVisible then
        
        app:hide()
        hbox_app:attr('tooltip', 'click to show')
        reaper.SetExtState(sectionID, "appVisibility", "hidden", true)  -- Сохраняем состояние видимости
    else
        app:show()
        hbox_app:attr('tooltip', 'click to hide')
        reaper.SetExtState(sectionID, "appVisibility", "visible", true)  -- Сохраняем состояние видимости
    end

    isAppVisible = not isAppVisible  -- Обновляем состояние переменной
    return true
end



-- Если приложение было скрыто в предыдущей сессии, скрываем его сейчас
if savedVisibility == "hidden" then
    app:hide()
    hbox_app:attr('tooltip', 'click to show')
end

slider_velocity.onmousewheel = function(self, event)
    local _, _, _, wheel_y = tostring(event):find("wheel=(%d+.?%d*),(-?%d+.?%d*)")
    local c_val = tonumber(wheel_y) > 0 and self.value - self.step or self.value + self.step
    self:attr('value', math.max(self.min, math.min(self.max, c_val)))
    return true
end
slider_velocity.onchange=function(self, event)
  if step_mode == 2 then  -- Проверяем, установлен ли нужный режим
    vel_text:attr('text', self.value)
    velocity = self.value  -- Устанавливаем velocity равным текущему значению слайдера
    p_run()
  end
end

slider_velocity.onmousedown = function(self, event)
  -- Здесь можно добавить дополнительный код, если нужно
end


slider_velocity.onmouseleave = function(self, event)
  if step_mode == 2 then  -- Проверяем, установлен ли нужный режим
    vel_text:attr('text', 'VEL')
  end
end
slider_velocity2.onchange=function(self, event)
  if step_mode == 2 then  -- Проверяем, установлен ли нужный режим
    step_text:attr('text', self.value)
    step=self.value
    p_run()
  end
end
slider_velocity2.onmousedown = function(self, event)
  -- Здесь можно добавить дополнительный код, если нужно
end
slider_velocity2.onmousewheel = function(self, event)
    local _, _, _, wheel_y = tostring(event):find("wheel=(%d+.?%d*),(-?%d+.?%d*)")
    local c_val = tonumber(wheel_y) > 0 and self.value - self.step or self.value + self.step
    self:attr('value', math.max(self.min, math.min(self.max, c_val)))
    return true
end


slider_velocity2.onmouseleave = function(self, event)
  if step_mode == 2 then  -- Проверяем, установлен ли нужный режим
    step_text:attr('text', 'STEP')
  end
end

slider_velocitythr.onchange=function(self, event)
  local index = math.floor(self.value / 10 + 0.5) + 1  -- округляем к ближайшему индексу
  if index < 1 then index = 1 end  -- защита от выхода индекса за пределы массива
  if index > #grid_values then index = #grid_values end
  
  grid_step = grid_values[index]  -- устанавливаем grid_step равным значению из таблицы
  p_run()
end
slider_velocitythr.onmousewheel = function(self, event)
    local _, _, _, wheel_y = tostring(event):find("wheel=(%d+.?%d*),(-?%d+.?%d*)")
    local c_val = tonumber(wheel_y) > 0 and self.value - self.step-9 or self.value + self.step+9
    self:attr('value', math.max(self.min, math.min(self.max, c_val)))
    return true
end


pin_b.onclick = function(self)
    pin_b.pressed = not pin_b.pressed
    updatePinState(pin_b.pressed)
    reaper.SetExtState(sectionID, "pinState", tostring(pin_b.pressed), true)
end
wnd.onresize = function(self, w, h)
    if not w or not h then return end

    local scale = h / initialH
    rtk.scale.user = scale
    scale_b:attr('label', string.format("%.2f", scale))

    reaper.SetExtState(sectionID, "windowScale", tostring(scale), true)
    reaper.SetExtState(sectionID, "windowPosX", tostring(self.x), true)
    reaper.SetExtState(sectionID, "windowPosY", tostring(self.y), true)
end
    
    
wnd.onclose = function(self)
    reaper.SetExtState(sectionID, "windowPosX", tostring(self.x), true)
    reaper.SetExtState(sectionID, "windowPosY", tostring(self.y), true)
end
reset_b.onclick = function() applyScale(1.0) end
btn_generate.onmouseleave=function(self)
    self:attr('icon', gen)
end
btn_generate.onmousedown=function(self)
    self:attr('icon', gen_p)
end
btn_generate.onmouseup=function(self)
    self:attr('icon', gen2)
end
btn_generate.onclick=function(self)
    run()
end
slider_mod_advanced.onmouseenter=function(self)
  
end
slider_mod_advanced:onblur()
slider_mod_advanced:hide()
slider_mod_advanced.onchange = function(self, event)
    --self:attr('disabled', true)
end

slider_mod_advanced.onmousewheel = function(self, event)
    local _, _, _, wheel_y = tostring(event):find("wheel=(%d+.?%d*),(-?%d+.?%d*)")
    local c_val = tonumber(wheel_y) > 0 and self.value - self.step or self.value + self.step
    self:attr('value', math.max(self.min, math.min(self.max, c_val)))
    return true
end


button_adv.state = 1
button_adv.current_icon = bulb
button_adv.onmousedown = function(self, event)
    self:attr('icon', bulb_en)  -- Изменение иконки при нажатии кнопки
end

button_adv.onmouseup = function(self, event)
    self:attr('icon', self.current_icon)  -- Восстановление текущей иконки после отпускания кнопки
end

button_adv.onmouseleave = function(self, event)
    self:attr('icon', self.current_icon)  -- Восстановление текущей иконки при уходе курсора
    self:attr("cursor", rtk.mouse.cursors.UNDEFINED)
end
    
button2.state = "on"
button2.current_icon = on
-- При инициализации вашего скрипта:
local extState = reaper.GetExtState("MyScriptUniqueName", "button2_state")
if extState == "off" then
    button2.state = "off"
    button2:attr('color', auto_apply_color_pressed)
    button2:attr('icon', off)
    button2:attr('gradient', 5)
    button2.current_icon = off
    func_on = false
    btn_generate:show()
    btn_generate:animate{'w', dst=71, duration=0.2,"out-bounce"}
    button2:animate{'w', dst=24, duration=0.2,"out-bounce"}
    
     
else
    button2.state = "on"
    button2:attr('color', auto_apply_color_current)
    button2:attr('icon', on)
    button2.current_icon = on
    
    func_on = true
    btn_generate:hide()
    button2:animate{'w', dst=base_wight_button, duration=0.2,"out-bounce"}
    btn_generate:animate{'w', dst=15, duration=0.2,"out-bounce"}
       :after(function()
           return btn_generate:hide()
        end)
end

button2.onclick = function(self, event)
    if self.state == "on" then--выкл
        self.state = "off"
        self:attr('color', auto_apply_color_pressed)
        self:attr('icon', off)
        self:attr('gradient', 5)
        self.current_icon = off
        func_on = false
        btn_generate:show()
        btn_generate:animate{'w', dst=71, duration=0.2,"out-bounce"}
        button2:animate{'w', dst=24, duration=0.2,"out-bounce"}
        
        reaper.SetExtState("MyScriptUniqueName", "button2_state", "off", true)
        
    else --вкл
        self.state = "on"
        self:attr('color', auto_apply_color_current)
        self:attr('icon', on)
        self.current_icon = on
        func_on = true
        self:attr('gradient', 3)
        button2:animate{'w', dst=base_wight_button, duration=0.2,"out-bounce"}
        btn_generate:animate{'w', dst=15, duration=0.2,"out-bounce"}
           :after(function()
               return btn_generate:hide()
            end)
        
        -- Сохраняем состояние
        reaper.SetExtState("MyScriptUniqueName", "button2_state", "on", true)
    end
end

button2.onmousedown = function(self,event)
  self:attr('icon', onof)

end
button2.onmouseup = function(self,event)
  self:attr('icon', self.current_icon)

end
button2.onmouseleave = function(self, event)
  self:attr('icon', self.current_icon)
  self:attr("cursor", rtk.mouse.cursors.UNDEFINED)

end

button_str.onmousewheel = function(self, event)
    local _, _, _, wheel_y = tostring(event):find("wheel=(%d+.?%d*),(-?%d+.?%d*)")
    local c_val = tonumber(wheel_y) > 0 and slid_length.value - slid_length.step-7 or slid_length.value + slid_length.step+7
    slid_length:attr('value', math.max(slid_length.min, math.min(slid_length.max, c_val)))
    return true
end

slid_length.onmousewheel = function(self, event)
    local _, _, _, wheel_y = tostring(event):find("wheel=(%d+.?%d*),(-?%d+.?%d*)")
    local c_val = tonumber(wheel_y) > 0 and self.value - self.step-7 or self.value + self.step+7
    self:attr('value', math.max(self.min, math.min(self.max, c_val)))
    return true
end
local globalSliderValue = 100 
slid_length.onchange = function(self, event)
  amount = self.value / -120
  local new_color = makeDarker("#4a544d", amount)
  self:attr('color', new_color)
  globalSliderValue = self.value

  -- Изменение имени кнопки в зависимости от значения слайдера
  if self.value < 35 then
    button_str:attr('label', 'Staccato')
  else
    button_str:attr('label', 'Legato')
  end
  
  p_run()
end
--slid_length:show()  
button_str.state = "on"
button_str.onclick = function(self, event)
    if self.state == "on" then
        self.state = "off"
        self:attr('color', legato_color_pressed)
        extendNotesFlag = true
        p_run()
        slid_length:show() 
        slid_length:animate{'w', dst=base_wight_button, duration=0.1, easing="in-quad"}
        
    else
        self.state = "on"
        self:attr('color', legato_color_current)
        extendNotesFlag = false
        p_run()
        slid_length:animate{'w', dst=nw_value, duration=0.1, easing="out-quad"}
        :after(function()
            local function jopa()
               slid_length:hide()
            end
            return jopa()
         end)
        
        
    end
end


b_create_chord.onclick = function()
    hide_all_boxes_and_reset_buttons()
    local last_created_button_number = #buttons + 1
    create_new_button_and_box(last_created_button_number)
    --print_slider_info()
end

b_delete_chord.onclick = function()


end
b_rand.onmousedown = function()
  b_rand:attr("icon", rnd)
end


b_rand.onmouseup = function()
  b_rand:attr("icon", rand)
end

local gr = 2

button_adv.onclick = function(self, event)
    if self.state == 1 then  -- выкл
        self.state = 2
        self:attr('icon', bulb2)
        self:attr('color', advanced_color_pressed)
        self.current_icon = bulb2
        slider_mod_advanced:show()
        slider_mod_advanced:animate{'w', dst=base_wight_button, duration=0.1, easing="in-quad"}
        step_mode=2
        sliders_box_v:show()
        all_advanced_mode_container:hide()
        on_deferred = false
    elseif self.state == 2 then  -- вкл
        self.state = 3  -- переход к третьему состоянию
        self:attr('icon', gen22)  -- тут можешь установить другую иконку для третьего состояния, если нужно
        self:attr('color', '#3f0b0b')  -- красный цвет для третьего состояния
        self.current_icon = gen11
        step_mode=3
        sliders_box_v:hide()
        circt1:hide()
        vert_b:hide()
        all_advanced_mode_container:show()
        
        on_deferred = true
    else  -- третье состояние
        self.state = 1
        self:attr('icon', bulb)
        self:attr('color', advanced_color_current)
        self.current_icon = bulb
        slider_mod_advanced:animate{'w', dst=nw_value, duration=0.5, easing="out-quad"}
        :after(function()
            local function jopa2()
               slider_mod_advanced:hide()
            end
            return jopa2()
         end)
         step_mode=1
         sliders_box_v:hide()
         circt1:show()
         vert_b:show()
         all_advanced_mode_container:hide()
         on_deferred = false
    end
    slider_mod_advanced:attr('value', button_adv.state)
    slider_mod_advanced:attr('color', button_adv.color)
    p_run()
    
end
function reset_button()
    b_up:attr("color", modes_button_color_current)
    b_down:attr("color",modes_button_color_current)
    b_rand:attr("color",modes_button_color_current)
    b_up:attr("gradient", gr)
    b_down:attr("gradient",gr)
    b_rand:attr("gradient",gr)
    b_rand:attr("hover",false)
    b_up:attr("hover",false)
    b_down:attr("hover",false)
end
function reset_animate_button()
    local def_dur = 0.3
    local eas="out-back"
    b_down:animate{'w', dst=base_wight_button, duration=def_dur, easing=eas}
    b_up:animate{'w', dst=base_wight_button, duration=def_dur, easing=eas}
    b_rand:animate{'w', dst=base_wight_button, duration=def_dur, easing=eas}
end

reset_button()
b_down:attr("color",modes_button_color_pressed)
b_up.onclick=function()
    reset_button()
    b_up:attr("gradient", 3)
    b_up:attr("color",modes_button_color_pressed)
    b_up:attr("hover",true)
    mode = "up"
    button:attr('label', '0')
    octave=0
    p_run()
    button:animate{'color', dst="#3a3a3a", duration=0.25}
    button:animate{'w', dst=15, duration=0.15, easing='out-expo'}  
       :after(function()
           local function after_button()
              button:hide()
              b_rand:animate{'color', dst="#3a3a3a", duration=0.25}
              
              reset_animate_button()
           end
           return after_button()
        end)
end

b_down.onclick=function()
    reset_button()
    b_down:attr("color",modes_button_color_pressed)
    b_down:attr("gradient", 3)
    b_down:attr("hover",true)
    mode = "down"
    button:attr('label', '0')
    octave=0
    p_run()
    button:animate{'color', dst="#3a3a3a", duration=0.25}
    button:animate{'w', dst=10, duration=0.15, easing='in-expo'}  
       :after(function()
           local function after_button()
              button:hide()
              b_rand:animate{'color', dst="#3a3a3a", duration=0.25}
              reset_animate_button()
           end
           return after_button() 
        end)
        
end



b_rand.onclick=function()
    reset_button()
    b_rand:attr("color",modes_button_color_pressed)
    b_rand:animate{'color', dst=modes_button_color_pressed, duration=0.25}
    local def_dur = 0.31
    local eas="in-out-quad"
    b_rand:attr("gradient", 3)
    b_rand:attr("hover",true)
    mode = "random"
    p_run()
    button:show()
    button:animate{'w', dst=45, duration=def_dur, easing=eas}
    
    button:animate{'color', dst=modes_button_color_pressed, duration=0.85}
    button:attr("gradient", 3)
    button:attr("hover",true)
    b_down:animate{'w', dst=modes_button_wight, duration=def_dur, easing=eas}
    b_up:animate{'w', dst=modes_button_wight, duration=def_dur, easing=eas}
    b_rand:animate{'w', dst=modes_button_wight, duration=def_dur, easing=eas}
    
end


local dragging = false
local currentValue = 0
local prevX, prevY = nil, nil

button.ondragstart = function(self, event, x, y, t)
    dragging = true
    prevX, prevY = x, y
      button:attr("cursor", rtk.mouse.cursors.REAPER_MARKER_VERT)
    return true
end


    

button.onmouseleave = function()
    button:attr("icon", oct)
end
button.ondragend = function(self, event, dragarg)
    dragging = false
    prevX, prevY = nil, nil
    button:attr("cursor", rtk.mouse.cursors.UNDEFINED)
    
    -- передача значения
    octave = currentValue
    p_run()
end
button.onmousewheel = function(self, event)
    local _, _, _, wheel_y = tostring(event):find("wheel=(%d+.?%d*),(-?%d+.?%d*)")
    wheel_y = tonumber(wheel_y)

    if wheel_y > 0 then
        currentValue = currentValue - 1
    else
        currentValue = currentValue + 1
    end

    currentValue = math.max(0, math.min(6, currentValue))

    button:attr('label', tostring(currentValue))

    -- Здесь передаем значение в octave и запускаем функцию run
    octave = currentValue
    p_run()
    return true
end
local dragAccumulatorX = 0
local dragAccumulatorY = 0
local dragThreshold = 25 -- порог для изменения значения
button.ondragmousemove = function(self, event, dragarg)
    if dragging and prevX and prevY then
            local deltaX = event.x - prevX
            local deltaY = event.y - prevY
            
            dragAccumulatorX = dragAccumulatorX + deltaX
            dragAccumulatorY = dragAccumulatorY + deltaY
    
            if math.abs(dragAccumulatorX) > dragThreshold or math.abs(dragAccumulatorY) > dragThreshold then
            if math.abs(deltaX) > math.abs(deltaY) then

            else
                -- Вертикальное движение
                if deltaY > 0 then
                    currentValue = currentValue - 1
                    button:attr("icon", down)
                elseif deltaY < 0 then
                    currentValue = currentValue + 1
                    button:attr("icon", up)
                end
                dragAccumulatorX = 5
                dragAccumulatorY = 5
            end

            -- Ограничение значения от 1 до 11
            currentValue = math.max(0, math.min(6, currentValue))

            button:attr('label', tostring(currentValue))
            prevX, prevY = event.x, event.y
        end
    end
end
--обработчики




--local grid_values = {1920, 1280, 960, 640, 480, 320, 240, 160, 120, 80, 60}






local function save_notes_to_json(filename)
  local take = reaper.MIDIEditor_GetTake(reaper.MIDIEditor_GetActive())
  local pattern = {notes = {}}
  local _, numNotes, _, _ = reaper.MIDI_CountEvts(take)
  for i = 0, numNotes - 1 do
    local _, selected, _, startppqpos, endppqpos, _, pitch, velocity = reaper.MIDI_GetNote(take, i)
    if selected then
      local position = startppqpos
      local length = endppqpos - position
      table.insert(pattern.notes, {position = position, length = length, velocity = velocity, pitch = pitch})
    end
  end
  local jsonString = json.encode(pattern)
  local filePath = rtk.script_path .. filename  -- Изменено здесь
  local file = io.open(filePath, "w")
  if file then
    file:write(jsonString)
    file:close()
  else
    reaper.ShowMessageBox("Error opening file.", "Error", 0)
  end
end

local function load_notes(filename)
  
  local filePath = rtk.script_path .. filename  -- Изменено здесь
  local file_read = io.open(filePath, "r")
  if file_read then
    local content = file_read:read("*all")
    file_read:close()
    return json.decode(content)
  else
    reaper.ShowMessageBox("Error opening file.", "Error", 0)
    return nil
  end
end



local function compare_patterns(pattern1, pattern2)
  if #pattern1.notes ~= #pattern2.notes then return false end
  for i, note1 in ipairs(pattern1.notes) do
    local note2 = pattern2.notes[i]
    if note1.position ~= note2.position or note1.length ~= note2.length or note1.velocity ~= note2.velocity or note1.pitch ~= note2.pitch then
      return false
    end
  end
  return true
end


local function delete_selected_notes(take)
  local _, numNotes, _, _ = reaper.MIDI_CountEvts(take)
  local selected_notes = {}
  
  -- Сначала получаем все выделенные ноты
  for i = 0, numNotes - 1 do
    local _, selected, _, _, _, _, _, _ = reaper.MIDI_GetNote(take, i)
    if selected then
      table.insert(selected_notes, i)
    end
  end
  
  -- Затем удаляем только выделенные ноты
  for i = #selected_notes, 1, -1 do
    reaper.MIDI_DeleteNote(take, selected_notes[i])
  end
end

--------------------------------------

function adjustNoteLengths()
    local take = reaper.MIDIEditor_GetTake(reaper.MIDIEditor_GetActive())
    if not take then return end  -- Выход, если активный редактор MIDI не найден
    
    local _, noteCount, _, _ = reaper.MIDI_CountEvts(take)
    local hasSelectedNotes = false
    
    for i = 0, noteCount - 1 do
        local retval, selected, _, _, _, _, _, _ = reaper.MIDI_GetNote(take, i)
        if selected then
            hasSelectedNotes = true
            break
        end
    end
    local ik=10.1
    for i = 0, noteCount - 1 do
        local retval, selected, muted, startppqpos, endppqpos, chan, pitch, vel = reaper.MIDI_GetNote(take, i)
        if hasSelectedNotes then
            if selected then
                reaper.MIDI_SetNote(take, i, nil, nil, nil, endppqpos - ik, nil, nil, nil, false)
            end
        else
            reaper.MIDI_SetNote(take, i, nil, nil, nil, endppqpos - ik, nil, nil, nil, false)
        end
    end
    
    reaper.MIDI_Sort(take)
end
function extendNotesToEndOfBar(startZone, endZone)
  -- Используем глобальное значение или 100 по умолчанию
  local sliderValue = globalSliderValue or 100

  -- Защита от nil для startZone и endZone
  if not startZone or not endZone then return end

  local midiEditor = reaper.MIDIEditor_GetActive()
  if not midiEditor then return end

  local take = reaper.MIDIEditor_GetTake(midiEditor)
  
  local _, noteCount, _, _ = reaper.MIDI_CountEvts(take)
  local extendTo
  
  for i = 0, noteCount - 1 do
    local retval, sel, muted, startppq, endppq, chan, pitch, vel = reaper.MIDI_GetNote(take, i)
    
    if sel and startppq >= startZone and endppq <= endZone then
      extendTo = endZone
      
      for j = i + 1, noteCount - 1 do
        local _, _, _, startppq2, _, _, pitch2, _ = reaper.MIDI_GetNote(take, j)
        
        if pitch == pitch2 and startppq2 < endZone then
          extendTo = startppq2
          break
        end
      end
      
      -- Рассчитываем новую длину ноты с учетом значения слайдера
      local newLength = extendTo - startppq
      local maxExtendLength = endZone - startppq
      newLength = newLength * (sliderValue / 100)
      
      -- Защита от установки длины меньше 64 тиков и больше максимальной
      newLength = math.max(64, math.min(newLength, maxExtendLength))
      
      -- Рассчитываем новую конечную позицию ноты
      local newExtendTo = startppq + newLength
      
      -- Защита от ситуации, когда конечная позиция меньше начальной
      if newExtendTo > startppq then
        reaper.MIDI_SetNote(take, i, sel, muted, startppq, newExtendTo, chan, pitch, vel, false)
      end
    end
  end
  
  reaper.MIDI_Sort(take)
end

local function splitNote(take, start, endpos, pitch, vel, ratchet)
  local len = endpos - start
  local div = math.floor(len / ratchet)
  local mult_len = start + div * ratchet

  for j = 1, ratchet do
    reaper.MIDI_InsertNote(
      take, 
      true, 
      false, 
      start + (j-1) * div, 
      start + (j-1) * div + div, 
      0, 
      pitch, 
      vel,
      false
    )
    if mult_len < endpos then
      reaper.MIDI_InsertNote(
        take, 
        true, 
        false, 
        start + div * ratchet, 
        endpos, 
        0, 
        pitch, 
        vel,
        false
      )
    end
  end
end

local function sortChord(chord, current_mode)
  table.sort(chord, function(a, b)
    if current_mode == "up" then
      return a.pitch < b.pitch
    else
      return a.pitch > b.pitch
    end
  end)
end

local function createArpeggio(direction, g_length, alternateStep, alternateLength)
    local take = reaper.MIDIEditor_GetTake(reaper.MIDIEditor_GetActive())
    if not take then return end
    local chord_gap_threshold = -1
    reaper.MIDI_Sort(take)
    adjustNoteLengths()
    local _, noteCount = reaper.MIDI_CountEvts(take)
    local chords = {}
    local chord = {}
    local lastEnd = 0
    -- 1) Gathering notes into chords
    local hasSelectedNotes = false
    for i = 0, noteCount - 1 do
        local retval, selected, _, _, _, _, _, _ = reaper.MIDI_GetNote(take, i)
        if selected then
            hasSelectedNotes = true
            break
        end
    end

    for i = 0, noteCount - 1 do
        local retval, selected, _, startpos, endpos, _, pitch, velocity = reaper.MIDI_GetNote(take, i)

        local noteLength = endpos - startpos
        if (not hasSelectedNotes or selected) and noteLength > 120 then
            if #chord > 0 and startpos - chord[#chord].endpos > 10 then -- You can change this threshold
                if #chord > 1 then
                    sortChord(chord, current_mode)
                    table.insert(chords, chord)
                else
                    table.insert(chords, {{startpos = chord[1].startpos, endpos = chord[1].endpos, pitch = chord[1].pitch}})
                end
                chord = {}
            end
            table.insert(chord, {startpos = startpos, endpos = endpos, pitch = pitch, velocity = velocity})
        end
    end
    if #chord == 1 then
        table.insert(chords, {{startpos = chord[1].startpos, endpos = chord[1].endpos, pitch = chord[1].pitch}})
    elseif #chord > 1 then
        sortChord(chord, current_mode)
        table.insert(chords, chord)
    end

    -- 2) Delete all notes
    for i = noteCount - 1, 0, -1 do
        local _, selected, _, startpos, endpos, _, _, _ = reaper.MIDI_GetNote(take, i)
        local noteLength = endpos - startpos
        if (not hasSelectedNotes or selected) and noteLength > 120 then
            reaper.MIDI_DeleteNote(take, i)
        end
    end

    -- 3) Insert arpeggios for each chord
    local chordZones = {}
    for chord_index, chord in ipairs(chords) do
        local insert_position = chord[1].startpos
        local end_position = chord[#chord].endpos

        table.insert(chordZones, {start = insert_position, stop = end_position})

        local current_step_grid = step_grid[(chord_index - 1) % #step_grid + 1]
        local current_mode

        if step_mode == 3 then
            current_mode = current_step_grid.mode or mode
        else
            current_mode = mode
        end

        if #chord == 1 then -- Если есть только одна нота
            while insert_position < end_position do
                local note_length = g_length
                if insert_position + note_length > end_position then
                    note_length = end_position - insert_position
                end

                reaper.MIDI_InsertNote(take, true, false, insert_position, insert_position + note_length, 0, chord[1].pitch, 100, false)
                insert_position = insert_position + note_length
            end
        else
            local note = 1
            local last_note = nil

            local current_step_grid = step_grid[(chord_index - 1) % #step_grid + 1]

            local main_count = 0 -- Основной счетчик для while цикла
            local step_counts = {}
            for i = 1, #current_step_grid do
                step_counts[i] = 0
            end
            local current_length = 100  -- значение по умолчанию
            local current_octave = 0 -- Эта переменная будет хранить текущую октаву
            while insert_position < end_position do
                local note_length = g_length
                local current_velocity = velocity -- Будем использовать эту переменную вместо оригинальной

                main_count = main_count + 1  -- Увеличиваем основной счетчик

                if step_mode == 2 and alternateStep and alternateLength then
                    if main_count % alternateStep == 0 then
                        note_length = alternateLength
                    end
                elseif step_mode == 3 then
                        local matched = false
                        
                        if current_step_grid then
                            for i = #current_step_grid, 1, -1 do
                                step_counts[i] = step_counts[i] + 1
                                local v = current_step_grid[i]
                
                                if step_counts[i] % v.step == 0 then
                                    note_length = v.grid_step
                                    if v.velocity then
                                        current_velocity = v.velocity
                                    end
                                    if v.octave then
                                        current_octave = v.octave
                                    end
                                    if v.ratchet then
                                        ratchet = v.ratchet
                                    else
                                        ratchet = 1
                                    end
                                    if v.length then
                                        current_length = v.length
                                    end
                                    matched = true
                                    break
                                end
                            end
                        end

                    if not matched and step_mode ~= 3 then
                        current_velocity = velocity
                        current_octave = octave
                    end
                else
                    current_velocity = chord[note].velocity
                end
                sortChord(chord, current_mode)
                if current_mode == "random" then
                    repeat
                        note = math.random(#chord)
                    until note ~= last_note or #chord == 1
                end

                last_note = note

                if insert_position + note_length > end_position then
                    note_length = end_position - insert_position
                end

                -- Взрыв октавы
                local pitch = chord[note].pitch + (current_octave * 12)
                local new_note_length = note_length * (current_length / 100)
                if current_length == 0 then
                    new_note_length = note_length
                else
                    new_note_length = note_length * (current_length / 100)
                end
                if octave ~= 0 then
                    local randomOctaveShift = math.random(-octave, octave) * 12
                    pitch = pitch + randomOctaveShift -- Смещение на случайное количество октав вверх или вниз, сохраняя тон
                end
               if ratchet and ratchet > 1 then
                   splitNote(take, insert_position, insert_position + new_note_length, pitch, current_velocity, ratchet)
               else
                   reaper.MIDI_InsertNote(take, true, false, insert_position, insert_position + new_note_length, 0, pitch, current_velocity, false)
               end
                
                reaper.MIDI_InsertNote(take, true, false, insert_position, insert_position + note_length, 0, pitch, current_velocity, false)
                insert_position = insert_position + note_length
                
                if current_mode ~= "random" then
                    note = (note % #chord) + 1
                end
            end
        end
    end
    if extendNotesFlag then
        for _, zone in ipairs(chordZones) do
            extendNotesToEndOfBar(zone.start, zone.stop)
        end
    end

    save_notes_to_json("modify.json")
end

--[[
reaper.Undo_BeginBlock()

reaper.Undo_EndBlock("Create Arpeggio from Chords", -1)]]

local currentValue = 0
CircleWidget = rtk.class('CircleWidget', rtk.Spacer)
CircleWidget.register{
    radius = rtk.Attribute{default=40},
    borderFraction = rtk.Attribute{default=1}, -- Доля границы (от 0 до 1)
    color = rtk.Attribute{type='color', default='red'},
    borderColor = rtk.Attribute{type='color', default='gray'},
    borderwidth = rtk.Attribute{default=5},
    scale = rtk.Attribute{default=1},
}
function CircleWidget:initialize(attrs, ...)
    rtk.Spacer.initialize(self, attrs, CircleWidget.attributes.defaults, ...)
    self.alpha2 = 0.07
    self.currentRadius = 0
    self.scale = attrs.scale or 1  -- Инициализируем масштаб из атрибутов или по умолчанию
end

function CircleWidget:_handle_draw(offx, offy, alpha, event)

    local sliderValueIndex = math.floor(slider_velocitythr.value / 10 + 0.5) + 1  -- округляем к ближайшему индексу
    if sliderValueIndex < 1 then sliderValueIndex = 1 end  -- защита от выхода индекса за пределы массива
    if sliderValueIndex > #grid_values then sliderValueIndex = #grid_values end
    
    
    sliderValueIndex = sliderValueIndex + 1
    
    local calc = self.calc
    local x = offx + calc.x + calc.w / 2
    local y = offy + calc.y + calc.h / 2
    --local knobRadius = calc.radius * self.scale 
    local knobRadius = calc.w / 2
    local startAngle = 90
    local labels = {"Original","1/2", "1/3", "1/4", "1/6", "1/8", "1/12", "1/16",  "1/24", "1/32", "1/48", "1/64"}
    local stepAngle = 360 / #labels
    local labelRadius = knobRadius + 13
    local borderAngle = startAngle + 360 * (currentValue / (#labels - 1))
    local thickness = 12
    local alpha2 = 0.07
    
    for i = 1, 9 do
        local alpha = alpha2 * (10 - i)
        gfx.set(0, 0, 0, alpha)
        gfx.circle(x - 1, y + 4, knobRadius - calc.borderwidth - 17 + i, 20, true)
    end
    
    local outerRadius = math.floor(knobRadius - calc.borderwidth - 12)
    local steps = 20  -- Количество шагов градиента
    local stepSize = outerRadius / steps  -- Размер каждого шага
    local color = '#2a2a2a'
    for i = steps, 1, -1 do
        self:setcolor(color)
        gfx.circle(x, y, stepSize * i, 290, true)
        color = makeDarker(color, -0.035)
    end
        
        local markerAngle = math.rad(startAngle + stepAngle * currentValue)
        
        -- Расстояние от центра большого круга до метки (поменял на knobRadius - 5)
        local markerDistance = knobRadius - 55
        
        -- Координаты метки
        local markerX = x + markerDistance * math.cos(markerAngle)
        local markerY = y + markerDistance * math.sin(markerAngle)
        
        -- Округляем координаты
        markerX = math.floor(markerX + 0.5)
        markerY = math.floor(markerY + 0.5)
        
        bl = 3
        color = makeDarker(color, 0.065)
        self:setcolor(color)  -- Цвет метки, можно выбрать другой
        gfx.circle(markerX, markerY, 6, bl, true)
        
        local markerAngle = math.rad(startAngle + stepAngle * currentValue)
        
        -- Расстояние от центра большого круга до метки (поменял на knobRadius - 5)
        local markerDistance = knobRadius - 25
        
        -- Координаты метки
        local markerX = x + markerDistance * math.cos(markerAngle)
        local markerY = y + markerDistance * math.sin(markerAngle)
        
        -- Округляем координаты
        markerX = math.floor(markerX + 0.5)
        markerY = math.floor(markerY + 0.5)
        
        bl = 3
        round_round_1=math.floor(knobRadius/8.2)
        color = makeDarker(color, -0.035)
        self:setcolor(color)  -- Цвет метки, можно выбрать другой
        gfx.circle(markerX, markerY, round_round_1, bl, true)
        
        ---
    local innerRadius = math.floor((knobRadius - calc.borderwidth - 12) * 0.75)
    local steps = 10  -- Количество шагов градиента
    local stepSize = innerRadius / steps  -- Размер каждого шага
    local color = '#3a3a3a'
    for i = steps, 1, -1 do
        self:setcolor(color)
        gfx.circle(x, y, stepSize * i, 290, true)
        color = makeDarker(color, -0.091)
    end
    
    label_color=knob_rate_label_color
    label_round = 0.5
    
    --local sliderValueIndex = math.floor(self.value / 10) + 1  -- округляем вниз и прибавляем 1
    
    for i, label in ipairs(labels) do
        local angle = math.rad(startAngle + stepAngle * (i - 1))
        local lx = x + labelRadius * math.cos(angle)
        local ly = y + labelRadius * math.sin(angle)
        
        local isNearestLabel = math.abs(i - 1 - currentValue) < label_round
        local isNearestSlider = i == sliderValueIndex  -- новая переменная, которая проверяет, является ли текущая метка ближайшей для слайдера
    
        if step_mode == 2 and isNearestSlider then
            self:setcolor(advanced_color_main_sl_label)
        elseif isNearestLabel then
            self:setcolor(label_color)
        else
            self:setcolor('#8a8a8a')
        end
         --Book Antiqua
        gfx.setfont(1, "Palatino Linotype", 15)
        gfx.x = lx - gfx.measurestr(label) / 2
        gfx.y = ly -9
        gfx.drawstr(label)
    end

    
    local lineLengths = {5}  -- длины линий
    local lineCount = #lineLengths  -- количество разных длин линий
    local totalLines = #labels  -- общее количество линий
    local lineAngleStep = 360 / totalLines  -- шаг угла для каждой линии
    
    for i = 1, totalLines do
        local isNearestLabel = math.abs(i - 1 - currentValue) < label_round
        local isSliderLabel = i == sliderValueIndex  -- новая переменная
        
        if step_mode == 2 and isSliderLabel then  -- новая проверка
            self:setcolor(advanced_color_main_sl_label)
        elseif isNearestLabel then  
            self:setcolor(label_color)
        else
            self:setcolor('#8a8a8a')
        end
    
        local angle = math.rad(startAngle + lineAngleStep * (i - 1))
        local lineLength = lineLengths[(i - 1) % lineCount + 1]  -- выбор длины линии
        local x1 = x + (knobRadius - 5) * math.cos(angle)
        local y1 = y + 1 + (knobRadius - 5) * math.sin(angle)
        local x2 = x + (knobRadius - 5 - lineLength) * math.cos(angle)
        local y2 = y + 1 + (knobRadius - 5 - lineLength) * math.sin(angle)
    
        gfx.line(x1, y1, x2, y2, 1)
    end
    

    
end

local dragging = false
local prevY = nil
local sensitivity = 0.039  -- уменьшено для большей чувствительности
CircleWidget.currentValue = 0

CircleWidget.ondragstart = function(self, event, x, y, t)
    dragging = true
    prevY = y
    self.alpha2 = 0.02
    

    return true
end

CircleWidget.ondragend = function(self, event, dragarg)
    self:attr('cursor', nil)
    dragging = false
    prevY = nil
    self.alpha2 = 0.07

end

local lerpSpeed = 0.01
local lastNearestLabel = nil




CircleWidget.ondragmousemove = function(self, event, dragarg)
    if dragging and prevY then
        local delta = event.y - prevY
        currentValue = currentValue - delta * sensitivity
        currentValue = math.max(0, math.min(11, currentValue))  -- 11 - максимальное значение

        local nearestLabel = math.floor(currentValue)
        if currentValue - nearestLabel >= 0.5 then
            nearestLabel = nearestLabel + 1
        end

        if lastNearestLabel and math.abs(nearestLabel - lastNearestLabel) > 1 then
            nearestLabel = lastNearestLabel + math.sign(nearestLabel - lastNearestLabel)
        end

        lastNearestLabel = nearestLabel

        local threshold = 0.19

        if math.abs(currentValue - nearestLabel) < threshold then
            currentValue = nearestLabel
        else
            currentValue = currentValue * (1 - lerpSpeed) + nearestLabel * lerpSpeed
        end

        local borderFraction = currentValue / 11  -- 11 - максимальное значение
        self:attr('borderFraction', borderFraction)

        prevY = event.y
        self:onchange()
    end
end


CircleWidget.onmousewheel = function(self, event)
    local _, _, _, wheel_y = tostring(event):find("wheel=(%d+.?%d*),(-?%d+.?%d*)")
    wheel_y = tonumber(wheel_y)
    
    local step = 1  -- Шаг изменения. Можешь изменить, если нужно
    local nearestLabel = math.floor(currentValue)

    if wheel_y > 0 then
        nearestLabel = nearestLabel - step
    else
        nearestLabel = nearestLabel + step
    end

    nearestLabel = math.max(0, math.min(11, nearestLabel))  -- 11 - максимальное значение
    lastNearestLabel = nearestLabel
    
    currentValue = nearestLabel  -- Перемещаемся к ближайшей метке
    local borderFraction = currentValue / 11  -- 11 - максимальное значение
    self:attr('borderFraction', borderFraction)
    self:onchange()  -- Если у тебя есть какая-то дополнительная логика при изменении значения
    
    return true
end



function math.sign(x)
    return x > 0 and 1 or x < 0 and -1 or 0
end

local flag_unselect = false

function SelectNotesIfNoneSelected()
  local midi_editor = reaper.MIDIEditor_GetActive()
  if midi_editor ~= nil then
    local take = reaper.MIDIEditor_GetTake(midi_editor)
    if take ~= nil then
      local firstSelectedNote = reaper.MIDI_EnumSelNotes(take, -1)
      if firstSelectedNote == -1 then 
        reaper.MIDI_SelectAll(take, true)
        flag_unselect = true
      else 
        flag_unselect = false
      end
      
    end
  end
end

function unselect_all()
  local trackCount = reaper.CountTracks(0)
  for i = 0, trackCount - 1 do
    local track = reaper.GetTrack(0, i)
    local itemCount = reaper.CountTrackMediaItems(track)
    for j = 0, itemCount - 1 do
      local item = reaper.GetTrackMediaItem(track, j)
      local take = reaper.GetActiveTake(item)
      if take ~= nil then
        reaper.MIDI_SelectAll(take, false)
      end
    end
  end
end


function run()
  SelectNotesIfNoneSelected()
  local selected_pattern = {notes = {}}
  local take = reaper.MIDIEditor_GetTake(reaper.MIDIEditor_GetActive())
  local _, numNotes, _, _ = reaper.MIDI_CountEvts(take)
  for i = 0, numNotes - 1 do
    local _, selected, _, startppqpos, endppqpos, _, pitch, velocity = reaper.MIDI_GetNote(take, i)
    if selected then
      local position = startppqpos
      local length = endppqpos - position
      table.insert(selected_pattern.notes, {position = position, length = length, velocity = velocity, pitch = pitch})
    end
  end
  
  
  local modify_pattern = load_notes("modify.json")
  
  
  
  if compare_patterns(selected_pattern, modify_pattern) then
    local original_pattern = load_notes("original.json")
    delete_selected_notes(take)
    for i, note in ipairs(original_pattern.notes) do
      reaper.MIDI_InsertNote(take, true, false, note.position, note.position + note.length, 0, note.pitch, note.velocity, false)
    end
    createArpeggio(mode, grid, step, grid_step)
  else
    save_notes_to_json("original.json")
    createArpeggio(mode, grid, step, grid_step)
  end
  if flag_unselect == true then
    unselect_all()
  end
end

local lastRoundedValue = nil 

function original_notes()
      local selected_pattern = {notes = {}}
      local take = reaper.MIDIEditor_GetTake(reaper.MIDIEditor_GetActive())
      local _, numNotes, _, _ = reaper.MIDI_CountEvts(take)
      for i = 0, numNotes - 1 do
        local _, selected, _, startppqpos, endppqpos, _, pitch, velocity = reaper.MIDI_GetNote(take, i)
        if selected then
          local position = startppqpos
          local length = endppqpos - position
          table.insert(selected_pattern.notes, {position = position, length = length, velocity = velocity, pitch = pitch})
        end
      end
    local modify_pattern = load_notes("modify.json")
    if compare_patterns(selected_pattern, modify_pattern) then
      local original_pattern = load_notes("original.json")
      delete_selected_notes(take)
      for i, note in ipairs(original_pattern.notes) do
        reaper.MIDI_InsertNote(take, true, false, note.position, note.position + note.length, 0, note.pitch, note.velocity, false)
      end
    else
      save_notes_to_json("original.json")
    end 
end    

circt1=slider_line:add(CircleWidget{scale=scale_2,radius=50,x=15,ref='circle', w=80, h=80, borderFraction=0/11})

    local languages = {
        eng = {
            mainKnob = "Main knob: Set the rate for the arpeggio",
            ascending = "Arpeggio Mode - Ascending",
            descending = "Arpeggio Mode - Descending",
            b_rand = "Arpeggio Mode - Random(With Octave)",
            button = "Octave Explosion (Until 6)",
            button_str = "Set legato end/bar(wheel to change or drag slider)",
            button_adv = "3-mode switch: default, step-mode, advanced",
            button2 = "Auto-mode after change",
            btn_generate = "Generate arpeggios",
            pin_b = "Pin window",
            reset_b = "Double-click to refresh",
            scale_b = "Current scale",
            slider_velocity2 = "Step to change note size",
            slider_velocity = "Set Velocity For Changing Notes",
            slider_velocitythr = 'Settable size for step (check slider "STEP")',
            box_second_advanced = "Advanced Window №2",
            
           
        },
        ru = {
            mainKnob = "Установите размер для арпеджио",
            ascending = "Режим арпеджио - Восходящий",
            descending = "Режим арпеджио - Нисходящий",
            b_rand = "Режим арпеджио - Случайный(с октавой)",
            button = "Взрыв октав (До 6)",
            button_str = "Установить легато конец/такт",
            button_adv = "3-режим переключения",
            button2 = "Авто-режим после изменения",
            btn_generate = "Генерация арпеджио",
            pin_b = "Закрепить окно",
            reset_b = "Двойной клик для обновления",
            scale_b = "Текущая масштаб",
            slider_velocity2 = "Шаг для изменения размера ноты",
            slider_velocity = "Установить скорость для изменения нот",
            slider_velocitythr = 'Установимый размер шага (проверьте ползунок "ШАГ")',
            box_second_advanced = "Окно №2 - Дополнительные настройки",
            
        }
    }
    
    local language = 'eng'  
    function lang_cur()
        if language == 'ru' then
            wnd:attr('title', 'Миди Арпеджиатор')
        else
            wnd:attr('title', 'Midi Arpeggiator')
        end
    end
    lang_cur()
    
    slider_velocity2.onmouseenter = function(self, event)
      if step_mode == 2 then  -- Проверяем, установлен ли нужный режим
        step_text:attr('text', self.value)
      end
      app:attr('status', languages[language].slider_velocity2)
      return true
    end
    slider_velocity.onmouseenter = function(self, event)
      if step_mode == 2 then  -- Проверяем, установлен ли нужный режим
        vel_text:attr('text', self.value)
      end
      app:attr('status', languages[language].slider_velocity)
      return true
    end
    slider_velocitythr.onmouseenter = function(self, event)
      app:attr('status', languages[language].slider_velocitythr)
      return true
    end
    
    circt1.onmouseenter = function(self)
        app:attr('status', languages[language].mainKnob)
        return true
    end
    b_up.onmouseenter = function(self)
        app:attr('status', languages[language].ascending)
        return true
    end
    b_down.onmouseenter = function(self)
        app:attr('status', languages[language].descending)
        return true
    end
    b_rand.onmouseenter = function(self)
        app:attr('status', languages[language].b_rand)
        return true
    end
    button.onmouseenter = function(self)
        app:attr('status', languages[language].button)
        button:attr("cursor", rtk.mouse.cursors.BEAM)
        button:attr("icon", up_and_down)
        return true
    end
    button_str.onmouseenter = function(self)
        app:attr('status', languages[language].button_str)
        self:attr("cursor", rtk.mouse.cursors.HAND)
        return true
    end
    button_adv.onmouseenter = function(self)
        app:attr('status', languages[language].button_adv)
        self:attr('icon', bulb_en)  -- Изменение иконки на bulb_en
        self:attr("cursor", rtk.mouse.cursors.HAND)
        return true
    end
    button2.onmouseenter = function(self, event)
        app:attr('status', languages[language].button2)
        self:attr('icon', onof)
        self:attr("cursor", rtk.mouse.cursors.HAND)
        return true
    end
    btn_generate.onmouseenter=function(self)
        self:attr('icon', gen2)
        app:attr('status', languages[language].btn_generate)
        return true
    end
    pin_b.onmouseenter = function()
        app:attr('status', languages[language].pin_b)
        return true
    end
    reset_b.onmouseenter = function()
        app:attr('status', languages[language].reset_b)
        return true
    end
    scale_b.onmouseenter = function()
        app:attr('status', languages[language].scale_b)
        return true
    end
    

function CircleWidget:onchange()
    if currentValue == 0 then
        original_notes()
    else
        local step = math.floor(currentValue + 0.5)  -- Округляем до ближайшего целого
    
        if lastRoundedValue ~= step then  -- Проверяем, изменилось ли округленное значение
            lastRoundedValue = step  -- Обновляем последнее округленное значение
    
            if step == 0 then
                -- Твой код для обработки step == 0
            else
                grid = grid_values[step]
                p_run()
            end
        end
        --reaper.ShowConsoleMsg("currentValue: " .. tostring(currentValue) .. " Rounded Step: " .. tostring(step) .. "\n")
    end
     
end
wnd:open()
