-- @description ReaProjects - Project Manager
-- @author mrtnz
-- @version 0.1.12-alpha
-- @changelog
--  Beta
-- @provides
--   libs/*.lua
--   modules/*.lua
--   data/*.ini
--   icons/*.png
--   customImages/*.png




if reaper.ShowMessageBox("This is an alpha version of the script that is not yet suitable for use, you can only superficially familiarize yourself. Click 'OK' to continue or 'CANCEL' to exit.",  "WARNING!", 1) == 1 then else return end
function print(...) local t = {...} for i = 1, select('#', ...) do t[i] = tostring(t[i]) end reaper.ShowConsoleMsg(table.concat(t, '\t') .. '\n') end
--- collect paths ---
sep = package.config:sub(1,1)
cur_path = ({reaper.get_action_context()})[2]:match('^.+' .. sep)
ini_path = reaper.get_ini_file()
icon_path = cur_path .. "icons"
data_path = cur_path .. "data"
package.path = cur_path ..'libs' .. sep .. '?.lua'
----------------------

--- req libraries ---
rtk = require('rtk')
json = require('json')
---------------------F

--- main dictionary ---
all_paths = {}
all_paths_list = {}
-----------------------

--- settings ---
round_rect_window = 14 --def 8/ min 2 max 20
round_rect_list = 6 -- def 6, min 1, max 12
GLOBAL_ANIMATE = true
KEY_FOR_TOUCHSCROLL="ctrl+shift"

max_visible=150
---------------

--media settings
CURRENT_media_path = true
GENERAL_media_path = {false, INDIVIDUAL_path}
INDIVIDUAL_media_path = false
INDIVIDUAL_path = "C:\\Users\\Эрик\\Desktop\\Портфель"
---------------

---------------
CUSTOM_IMAGE_local = 'customImages' .. sep
CUSTOM_IMAGE_global = cur_path .. CUSTOM_IMAGE_local

DEF_IMG_W = 450
DEF_IMG_H = 450
----------------


----------------
deadline_warning_color = "red#55"
elevation_warning = 13
----------------

--- scan modules ---
dofile(cur_path.."modules"..sep.."widgets.lua")
dofile(cur_path.."modules"..sep.."func.lua")
rtk.add_image_search_path(cur_path..sep.."icons", 'dark')
--------------------
--- initialize ---
def_bg_color = rtk.color.get_reaper_theme_bg()
def_pad_color = hex_darker (def_bg_color, -0.46)
ic, img = loadIcons(icon_path)
data_files = loadIniFiles(data_path)
params_data=data_files.data_path
params_file=data_files.params
-------------------

--- return projects ---
new_paths, all_paths_list = get_recent_projects(ini_path)
sorted_paths = sort_paths(new_paths, all_paths_list, "size", 0)

-----------------------
 
--- constains ---
lbm=rtk.mouse.BUTTON_LEFT
rbm=rtk.mouse.BUTTON_RIGHT
cbm=rtk.mouse.BUTTON_CENTER
def_spacing=5
rtk.double_click_delay=0.23
-----------------

MAIN_PARAMS = {
    w=550,
    h=800,
}
scale=1.0
preview=nil

--print(rtk.uuid4())

--main bg
COL0="#1a1a1a" -- main bg col \ def_bg_color
--list and header
COL1="transparent" --#5a5a5a" -- rect_bg_heading border\all border list \ #5a5a5a
COL2="#4a4a4a" -- bg heading  \ 4a4a4a
COL3="#2a2a2a" -- bg list \ 2a2a2a
--popup
COL4=COL3..50 -- shadow bg
COL5=COL1..75-- border \hex_darker(COL0, -1.2)
COL6=COL1 -- bg \hex_darker(COL0, -0.7)
--ENTRY
COL7="#6a6a6a" -- border \6a6a6a
COL8="#2a2a2a" -- bg \3a3a3a
--ELEMENTS
COL9="#3a3a3a" -- odd \3a3a3a
COL10="#323232" --even \323232

COL11="#6a6a6a" -- mouseenter \6a6a6a
COl12="#9a9a9a" -- selected \9a9a9a

COL13=COL0 .. 50 -- def pad color\ 
COL18 = "#3a3a3a"

 
--create window
local wnd = rtk.Window{x=50,y=50,bg=COL0, expand=1, w=700, h=800, padding=10} wnd:open() wnd.onresize = function(self, w, h)self:reflow()end wnd.onclose = function() reaper.CF_Preview_StopAll() rtk.quit()end
--------scale problems---------
if rtk.scale.value ~= 1.0 then
    rtk.scale.user = scale/rtk.scale.value
    wnd:attr('w', MAIN_PARAMS.w * scale) -- last w
    wnd:attr('h', MAIN_PARAMS.h * scale) -- last h
end

--local WND_vbox=wnd:add(rtk.VBox{spacing=def_spacing})
local main_vbox_window = wnd:add(rtk.VBox{spacing=def_spacing},{})

app_main_hbox = main_vbox_window:add(rtk.HBox{w=1, h=32})

--left side application
cont_left_app = app_main_hbox:add(rtk.Container{h=34, w=0.2, minw=60})
local left_app_hbox=cont_left_app:add(rtk.HBox{w=1},{halign='left', valign='center'})

--right side applications
cont_edge_app = app_main_hbox:add(rtk.Container{h=34, w=1})
local app_right = cont_edge_app:add(rtk.HBox{spacing=def_spacing,lmargin=3,rmargin=1,},{halign='right', valign='center'}) 
--app_right:add(--addhere)
app_right:add(rtk.Box.FLEXSPACE)
local pin_app = create_b(app_right, "PIN", 40, 30, true, ic.pin:scale(120,120,22,5):recolor("white"))
local settings_app = create_b(app_right, "STNGS", 40, 30, true, ic.settings:scale(120,120,22,5):recolor("white") ) settings_app.click=1

local main_hbox_window = main_vbox_window:add(rtk.HBox{minh=350, h=0.7, spacing=def_spacing},{fillw=true, fillh=true})
local left_vbox_sect = main_hbox_window:add(rtk.VBox{B_heigh=27, spacing=def_spacing},{fillh=true})



--settings block--
local main_settings_box = main_vbox_window:add(rtk.VBox{ref='set', w=1, visible=false})
local VP_settings_vbox = rtk.VBox{spacing=def_spacing, padding=2, margin=2,w=1}
local VP_settings = main_settings_box:add(rtk.Viewport{child = VP_settings_vbox, smoothscroll = true,scrollbar_size = 12,z=2})

local cont_player = VP_settings_vbox:add(rtk.Container{w=1})
cont_player:add(rtk.VBox{padding=12, ref='player', spacing=def_spacing})

cont_player.refs.player:add(rtk.HBox{
spacing=20,valign='center',
rtk.Spacer{w=0.1, bborder='2px '..COL11},
rtk.Heading{fontsize=24,font='Verdena', "Media Player Paths"},
rtk.Spacer{w=1, bborder='2px '..COL11},
})



buttons_settings = {}
VB_media=cont_player.refs.player:add(rtk.VBox{padding=30, halign='center', w=1, tmargin=1, spacing=5, ref='vb',rtk.Heading{fontsize=22,font='Verdena', ""}, },{})
ic_on = ic.on:scale(120,120,22,4):blur(1) ic_off = ic.off:scale(120,120,22,4):blur(22)ic_on:recolor('white#40')

local hb_ind = VB_media:add(rtk.HBox{h=35, w=1})
buttons_settings.self_inst = hb_ind:add(create_b_set("selfinst","Self-installation"))

local hb_gen = VB_media:add(rtk.HBox{h=35, w=1})
buttons_settings.gen_dir = hb_gen:add(create_b_set("gen","General directory"))

local hb_entry = VB_media:add(rtk.HBox{disabled=true, y=3, spacing=10, h=35, w=1})
local entry_custom_path, custom_path_cont = rtk_Entry(hb_entry, COL10, COL13, 3, "Custom media path") 
custom_path_cont:attr('lmargin', 50)custom_path_cont:attr('x', 18)custom_path_cont:resize(1, 30)

--hb_entry:add(rtk.Box.FLEXSPACE)
local cont_button_finder = create_b(hb_entry, "DIR", 40, 32, true, ic.dir:scale(120,120,22,5):recolor("white"), false)cont_button_finder:move(18, -1.5)
custom_path_cont.onkeypress=function(self, event)
    entry_custom_path:blur()
end
local hb_cur_path = VB_media:add(rtk.HBox{h=40, w=1})
buttons_settings.cur_path_to_rpp = hb_cur_path:add(create_b_set("cur", "Current path to rpp"))
-----------------


local function reset_buttons()
    for _, b in pairs(buttons_settings) do
        b:attr('flat', true)
        b:attr('hover', false)
        b:attr('icon', ic_off)
        b:attr('bg', '#3a3a3a10')
        b:attr('surface', true)
    end
end

local function activate_buttons(b)
    reset_buttons()
    b:attr('flat', false)
    b:attr('icon', ic_on)
    b:attr('hover', true)
    b:attr('bg', '#ffffff40')
    b:attr('surface', false)
end


for _, b in pairs(buttons_settings) do
    b.onclick=function(self,event)
        activate_buttons(b)
    end
end
 
activate_buttons(buttons_settings.cur_path_to_rpp)
--[[
self_inst
gen_dir
cur_path_to_tpp
]]



settings_app.onclick = function(self, event)
    if event.button == lbm then
        main_hbox_window:toggle()
        main_settings_box:toggle()
    
        if main_hbox_window.visible then
            left_app_hbox:remove_index(1)
        else
            lback_from_st=create_b(left_app_hbox, '←   BACK', 70, 32, nil, nil, false)
            lback_from_st:attr('ref', 'back')
            lback_from_st.onclick = function(sel, even) 
                main_hbox_window:toggle()
                main_settings_box:toggle()
                left_app_hbox:remove_all()
            end
            
        end
    end
end

---------LEFT SIDE SECTION---------
GRP_minw=95
GRP_maxw=150
GRP_minh=145
GRP_w=0.25

local OPEN_container, OPEN_heading, OPEN_vp_vbox = create_container({minh=GRP_minh, minw=GRP_minw, maxw=GRP_maxw, h=0.25, w=GRP_w}, left_vbox_sect,'OPEN PROJECTS')
local NEW_container, NEW_heading, NEW_vp_vbox = create_container({minh=GRP_minh, minw=GRP_minw, maxw=GRP_maxw, h=0.335, w=GRP_w}, left_vbox_sect, 'NEW PROJECTS')
local GROUP_container, group_heading, group_vp_vbox = create_container({minh=GRP_minh, minw=GRP_minw, maxw=GRP_maxw, h=1, w=GRP_w}, left_vbox_sect, 'GROUPS')
local IMG_container, IMG_head, vp_images2 = create_container({minh=GRP_minh, minw=GRP_minw, maxw=GRP_maxw, h=1, w=GRP_w}, left_vbox_sect, '[<]   IMG   [>]')

create_b(OPEN_vp_vbox, "OPEN", 1, left_vbox_sect.B_heigh)
create_b(OPEN_vp_vbox, "NEW TAB", 1, left_vbox_sect.B_heigh)
create_b(OPEN_vp_vbox, "RECOVERY", 1, left_vbox_sect.B_heigh).onclick=function(self,event)print("AA")end

create_b(NEW_vp_vbox, "NEW PROJECT", 1, left_vbox_sect.B_heigh)
create_b(NEW_vp_vbox, "NEW TAB", 1, left_vbox_sect.B_heigh)
create_b(NEW_vp_vbox, "NEW TAB(SV)", 1, left_vbox_sect.B_heigh).onreflow = function(self); self.refs.NEW_TAB_SV_:attr('text', self.calc.w > 122 and "NEW TAB(PRESERVE)" or "NEW TAB(PS)") end


---------LIST MAIN SECTION---------
local main_vbox_list = main_hbox_window:add(rtk.VBox{ spacing=def_spacing},{fillh=true, fillh=true})
local list_container, container_heading, list_vbox_group, vp_main_list = create_container({h=1, fillw=true}, main_vbox_list) 
list_vbox_group:attr('bmargin', 6)
list_vbox_group:attr('spacing', 3)
list_vbox_group.onmousewheel=function(self,event)
    if event.alt then
        local new_h = update_heigh_list(event.wheel)
        return true
    end
end

-----------------------------------
----------resizible list----------
--[[
local DRAG_LINE, mouseX, mouseH = false, 0, 0
RESIZE_LINE = list_container:add(rtk.Spacer{hotzone=5, cursor=rtk.mouse.cursors.SIZE_NS, y=3, h=4,w=0.9, bg='transparent'},{halign='center', valign='bottom'})

RESIZE_LINE.ondragstart = function(self, event)
    DRAG_LINE, mouseX, mouseH = true, event.y, list_container.calc.h
    return true
end
RESIZE_LINE.ondragend = function(self, event)
    DRAG_LINE = false
end
RESIZE_LINE.ondragmousemove = function(self, event)
    if DRAG_LINE then
        local new_h = rtk.clamp(mouseH + event.y - mouseX, 300, wnd.calc.h - 180 )
        reaper.ClearConsole()
        print(mouseH , event.y)
        norm_h = norm(new_h, 0, wnd.calc.h)
        list_container:attr('h', norm_h)
    end
end


RESIZE_LINE.onmouseenter = function(self, event)
    self:attr('bg', hex_darker(def_bg_color, -1))
    return true
end
RESIZE_LINE.onmouseleave = function(self, event)
    self:attr('bg', 'transparent')
end
]]
-----------------------------------
-----------------------------------

--create icons
local ic_loop = ic.loop:scale(120,120,22,4.5);local ic_backw = ic.backward:scale(120,120,22,4);
local ic_stop = ic.stop:scale(120,120,22,3);local ic_play = ic.play:scale(120,120,22,3);
local ic_draw = ic.draw:scale(120,120,22,6);local ic_forw = ic.forward:scale(120,120,22,4);
local ic_list = ic.list:scale(120,120,22,4.5);
--const settings
local col_meter = "green#10"
local surface = false
rait_icons = icons_raiting(34, icons_cols)


local vbox_popup = rtk.VBox{spacing=1, h=1}, {fillh=true}

local popup_by_path = rtk.Popup{x=1, y=1, alpha=0.9, bg=COL9, padding=2,shadow="#1a1a1a90",border=COL9, child=vbox_popup, w=145, h=188, overlay=COL4}

vbox_popup:add(rtk.Button{color=THEME_darker,flat=true,"OPEN", w=1})
vbox_popup:add(rtk.Button{color=THEME_darker,flat=true,"NEW TAB", w=1})
vbox_popup:add(rtk.Button{color=THEME_darker,flat=true,"OFFLINE", w=1})
vbox_popup:add(rtk.Button{color=THEME_darker,flat=true,"BACKUPS", w=1})
vbox_popup:add(rtk.Button{color=THEME_darker,flat=true,"PREVIEW", w=1})
vbox_popup:add(rtk.Button{color=THEME_darker,flat=true,"SETTINGS", w=1},{})

local HEADING_types_hbox = rtk.HBox{ref='heading', y=-6.5,}
local log = rtk.log

function is_mouse_in_box(self)
    local mousex, mousey = reaper.GetMousePosition()
    local x, y = self.clientx-self.offx, self.clienty-self.offy
    local w, h = self.calc.w, self.calc.h
    return rtk.point_in_box(mousex,mousey,x,y,w,h)
end

function create_block_list()
    
    local flowbox_main = rtk_FlowBox({margin=4, expand=4, spacing=-2, w=1})
    --local flowbox_main = rtk.FlowBox{margin=4, expand=4, spacing=-2, w=1}
    list_vbox_group:remove_all()
    vp_main_list:attr('child', flowbox_main)
    --list_vbox_group
    for i, path in ipairs(sorted_paths) do
        local n = new_paths[path]
        
        
        
        local data = n.DATA or {
            progress = 0,
            padcolor = "#6a6a6a",
            rating = 0,
            comment = "",
            dl="",
            img="1.png",
            tags={},
        }
        
        
        n.DATA = data        
        
        image = data.img or "1.png"
        raiting = data.raiting or 4
        def_padcol = data.padcolor or "#6a6a6a"
        norm_prog_val = data.progress/100 or 0
        
        
        
        local odd_col_bg = i % 2 == 0 and '#3a3a3a' or '#323232'

        local container_hbox = flowbox_main:add(rtk.Container{minw=230, hotzone=-3, expand=3, h=130,padding=4,},{fillw=true})
        local bg_roundrect = create_spacer(container_hbox, odd_col_bg, odd_col_bg, round_rect_list) bg_roundrect:attr('ref', 'bg_spacer')
        local def_vb = container_hbox:add(rtk.HBox{w=1, h=1})
        
        local left_img_progress=def_vb:add(rtk.VBox{h=1, w=0.45})
        
        
        local image = rtk.Image():load(CUSTOM_IMAGE_local .. image)
        local cont_img=left_img_progress:add(rtk.Container{lmargin=5, h=100, w=100},{fillh=true})
        local img = cont_img:add(rtk.ImageBox{padding=4,image=image,}, {}) 
        cont_img.onclick=function(self,event)
            
            --[[add image
            local rv, img_path = reaper.JS_Dialog_BrowseForOpenFiles('Select custom image', '', FILE, '', true) 
            if rv == 1 then
                update_image(n, img_path, img, data)
            end
            ]]
        end
        
        local slider_length_audio = left_img_progress:add(SimpleSlider{
        w=cont_img.calc.w, y=2, value=norm_prog_val, maxh=18,z=-1, scroll_on_drag=false, color=def_padcol, 
        tmargin=-2, rmargin=8, x=-2, lmargin=8,hotzone=5, roundrad=round_rect_list, ttype=3, textcolor="#ffffff80",
        onchange=function(val)
            data.progress=val
            save_parameter(n.path, data)
        end,
        },{fillh=true})
        
        right_section = def_vb:add(rtk.VBox{})
        local HD_name = right_section:add(rtk.Heading{autofocus=-1, spacing=-5, fontflags=rtk.font.BOLD, fontsize=20,halign='center' , h=0.45, wrap=true, text=n.filename})
        local HD_date = right_section:add(rtk.Heading{autofocus=-1, tborder='2px white#10', fontsize=20, w=1, wrap=true, text=n.form_date:gsub(", %d%d:%d%d", "")})
        
        --raiting  
        local icon_raiting_proj = right_section:add(rtk.Button{cursor=rtk.mouse.cursors.HAND,color='red',z=8, elevation=0,alpha=0.5, circular=true, lpadding=6, flat=true,icon=rait_icons.angry, w=40, h=32}) 
        
        local rait_hbox = rtk.Container{}
        local pop_up_raiting = rtk.Popup{w=50, y=100, margin=-2, shadow="transparent", bg="transparent", border="transparent", padding=1, child=rait_hbox, --[[anchor=icon_raiting_proj]]}
        local rait_cont, rait_heading, rait_vp, VP_1 = create_container({halign='right', w=1, h=150}, rait_hbox, " ") rait_vp:attr('x', 2)
        recolor(rait_cont.refs.BG, def_padcol, "#5a5a5a80")
        local heading=rait_cont.refs.VBOX.refs.HEAD rait_cont.refs.VBOX:remove(heading)
         
        
        
        n.form_date_1 = n.form_date:gsub(" %d+, %d+:%d+", "")
        n.form_date_2 = n.form_date:gsub(", %d%d:%d%d", "")
        n.hbox = hbox_projects
        n.cont = container_hbox
        n.sel = 0

        local new_cont = container_hbox:add(rtk.Container{hotzone=2, z=5},{fillw=true,fillh=true})
        
        
        new_cont.onmousedown = function(self, event)
            if event.button == lbm then
                if n.sel == 0 then
                    update_player(n)
                end
                if event.ctrl then
                    if n.sel == 1 then --unselect
                        recolor(bg_roundrect, odd_col_bg, odd_col_bg)
                        
                        n.sel = 0
                    else --select
                        recolor(bg_roundrect, "#8a8a8a", hex_darker("#8a8a8a", 0.2))
                        n.sel = 1
                    end
                elseif event.shift then
                    
                else
                    unselect_all_path()
                    recolor(bg_roundrect, "#8a8a8a", hex_darker("#8a8a8a", 0.2))
                    n.sel = 1
                end
            elseif event.button == rbm then

                local x_offset = rtk.mouse.x-wnd.calc.w+popup_by_path.calc.w
                local y_offset = rtk.mouse.y-wnd.calc.h+popup_by_path.calc.h
                
                OFFSETX, OFFSETY = 24.5, 24.5 -- when scale default
                
                local x_norm = rtk.mouse.x-OFFSETX-(x_offset > -1 and x_offset or 0)
                local y_norm = rtk.mouse.y-OFFSETY-(y_offset > -1 and y_offset or 0)
                
                popup_by_path:move(x_norm, y_norm)
                a,s,d,v=popup_by_path:_get_padding()
                print(a,s,d,v)
                
                if padcolor ~= def_pad_color then
                    popup_by_path:attr('shadow', def_padcol..10)
                else
                    popup_by_path:attr('shadow', "#1a1a1a90")
                end
                popup_by_path:attr('alpha', 0.94)
                if n.sel == 0 then
                    unselect_all_path()
                end
                recolor(bg_roundrect, "#9a9a9a", smooth)
                n.sel = 1
                
                popup_by_path:open{}
                --popup_by_path:open{}
                
                
            end
            
            --get_selected_path()
        end
        
        
        ---------
        slider_length_audio.onclick=function(self,event)
            if event.button == rbm then
                local ret, col = reaper.GR_SelectColor(wnd.hwnd)
                if ret then 
                    local col_hex = rtk.color.int2hex(col, true)
                    if col_hex == "#000000" then 
                        padcolor=def_pad_color 
                    else
                        data.padcolor=col_hex
                        slider_length_audio:attr('color', col_hex)
                        save_parameter(n.path, data)
                    end
                end
            end
        end
        
VP_1:scrollto(0, 0, false)
        icon_raiting_proj:attr('icon', rait_icons[icons_row1[raiting]])
        
        icon_raiting_proj.onclick=function(self, event)
            VP_1:scrollto(0, 0, false)
            pop_up_raiting:attr('x', self.clientx-12)
            pop_up_raiting:attr('y', self.clienty-60)
            
            pop_up_raiting:open{}
            pop_up_raiting.child.SELF = icon_raiting_proj
            
            --raiting
            local Y = 40 + (raiting - 1) * 40 - 30
            VP_1:scrollto(0, Y, true)
        end
        
        rait_vp:add(rtk.Spacer{h=50})
        for i, icon_name in ipairs(icons_row1) do
            local icon = rait_icons[icon_name]
            local b = rait_vp:add(rtk.Button{cursor=rtk.mouse.cursors.HAND, alpha=0.6, elevation=1, circular=true, x=-1, lpadding=-5,color=shift_color(icons_cols[i], 1.0, 0.6, 0.6)..90, flat=false,w=35, h=35, icon=icon})
            if i == raiting then
                b:attr('6px border', 'red')
                b:attr('bg', 'red')
            end
            b.onclick = function(self, event)
                data.raiting = i
                raiting = i
                rait_hbox.SELF:attr('icon', icon)
                pop_up_raiting:close()
                save_parameter(n.path,data)
            end
        end
        rait_vp:add(rtk.Spacer{h=50})
        if i == 1 then 
            update_player(n)
            n.sel = 1
            recolor(bg_roundrect, "#9a9a9a", hex_darker("#9a9a9a", 0.2))
        end
        
        -------
        
        new_cont.onmouseenter=function(self,event)
            if n.sel == 0 then
                recolor(bg_roundrect, "#6a6a6a", hex_darker("#6a6a6a", 0.2))
            end
            return true
        end
        new_cont.onmouseleave=function(self,event)
            if n.sel == 0 then
                recolor(bg_roundrect, odd_col_bg, odd_col_bg)
            end
        end
        local function update_hover()--[[
            if new_cont.mouseover
            or container_hbox.mouseover then
                if n.sel == 0 then
                    recolor(bg_roundrect, "#6a6a6a", hex_darker("#6a6a6a", 0.2))
                end
            else
                if n.sel == 0 then
                    recolor(bg_roundrect, odd_col_bg, odd_col_bg)
                end
            end]]
            val_touchscroll = get_modifier_value(KEY_FOR_TOUCHSCROLL)
            mouse_state = reaper.JS_Mouse_GetState(val_touchscroll)  
            rtk.touchscroll = (mouse_state == val_touchscroll) -- true or false
            isRunning = false
            rtk.defer(update_hover)
        end
        
        rtk.defer(update_hover)
        
    end
    
end



function create_list()
    
    list_vbox_group:remove_all()
    container_heading:remove(HEADING_types_hbox)
    vp_main_list:attr('child', list_vbox_group)
    container_heading:add(HEADING_types_hbox)
    --HEADING--
    HEADING_types_hbox:add(rtk.Button{x=5,ref="info", surface=false, minw=52, icon=ic.info, halign='center',fontflags=rtk.font.BOLD,halign='center' },{ halign='center', fillh=true})
    HEADING_types_hbox:add(rtk.Button{w=0.4, ref="fnames", surface=false, minw=nil, label="FILE NAME", icon=ic.filename,fontflags=rtk.font.BOLD},{fillh=true})
    local date_cont_Test=HEADING_types_hbox:add(rtk.Container{lmargin=4, halign='right'})
    date_cont_Test:add(rtk.Button{ref="dates", surface=false, minw=32, maxw=104, label="DATE", icon=ic.time, halign="center",fontflags=rtk.font.BOLD},{halign="center", fillh=true, fillw=true})
    HEADING_types_hbox:add(rtk.Button{lmargin=20, ref="paths", surface=false, minw=nil, label="PATH", icon=ic.folder,fontflags=rtk.font.BOLD},{fillh=true, fillw=true})
    HEADING_types_hbox:add(rtk.Button{ref="sizes", surface=false, minw=62, label="SIZE", icon=ic.mem, halign="right",fontflags=rtk.font.BOLD},{halign="right", fillh=true})
    
    for i, path in ipairs(sorted_paths) do
        local n = new_paths[path]
        
        local data = n.DATA or {
            progress = 0,
            padcolor = COL13,
            rating = 0,
            comment = "",
            dl="",
            tags={},
        }
        
        n.DATA = data
        
        local progress_val = data.progress 
        local padcolor = hex_darker(data.padcolor, lerp(-0.2, 0.2, 0.2 - ( progress_val / 100 ) ))
        local padcolor_dim = padcolor
        local padcolor_dim_border = padcolor
        
        local odd_col_bg = i % 2 == 0 and '#3a3a3a' or '#323232'
        
        local container_hbox = list_vbox_group:add(rtk.Container{h=24,},{fillw=true})
        local bg_roundrect = create_spacer(container_hbox, odd_col_bg, odd_col_bg, round_rect_list) bg_roundrect:attr('ref', 'bg_spacer')
        local short_path = shorten_path(n.dir, sep)
        local hbox_projects = container_hbox:add(rtk.HBox{ref="HBOX_P", padding=-2,thotzone=3,bhotzone=3,margin=2,spacing=2},{fillh=true,fillw=true})
        
        
        --container and pad\text in pad--
        local container_sq = hbox_projects:add(rtk.Container{lmargin=8,tpadding=4,margin=2,z=-2, w=32},{fillh=true,valign='center',halign='center'})
        local pad_status = create_spacer(container_sq, padcolor, padcolor, round_rect_list, false, progress_val):attr('scroll_on_drag', false) pad_status:attr('hotzone', 5)
        
        local b_name = hbox_projects:add(rtk.Text{w=0.4, ref='text_name', lmargin=1,fontflags=rtk.font.BOLD, valign='center', n.filename},{fillh=true})
        
        local date_cont_Test=hbox_projects:add(rtk.Container{halign='right'})
        local b_date = date_cont_Test:add(rtk.Text{ref='date', maxw=HEADING_types_hbox.refs.dates.calc.maxw,minw=HEADING_types_hbox.refs.dates.calc.minw,valign='center',halign='center',n.form_date},{fillh=true, fillw=true,halign='center'})
        
        local b_path_box= hbox_projects:add(rtk.Container{ref='path_box'},{fillw=true,fillh=true})
        local b_path = b_path_box:add(rtk.Text{lmargin=8, ref='paths', thotzone=1,bhotzone=1,cursor=rtk.mouse.cursors.HAND, valign='center', short_path, ref=n.path},{fillw=true,fillh=true})
        
        local b_size = hbox_projects:add(rtk.Text{minw=62,valign='center',n.form_size},{halign='right',fillh=true})
        
        b_path.onclick=function(self,event)
            if event.button == rbm then
                rtk.clipboard.set(self.ref) 
            elseif event.button == lbm then
                pad_status:onclick( event)
            end
        end
        b_path.ondoubleclick=function(self,event)
            reaper.CF_LocateInExplorer(self.ref)
        end
        
        n.form_date_1 = n.form_date:gsub(" %d+, %d+:%d+", "")
        n.form_date_2 = n.form_date:gsub(", %d%d:%d%d", "")
        n.hbox = hbox_projects
        n.cont = container_hbox
        n.pad = pad_status
        n.sel = 0
        

        
        hbox_projects.onmouseenter = function(self, event)
            if n.sel == 0 then
                recolor(bg_roundrect, "#6a6a6a", hex_darker("#6a6a6a", 0.2))
            end
            return true
        end
        
        hbox_projects.onmouseleave = function(self, event)
            --снимаем выделение, если они не были выбраны
            if n.sel == 0 then
                recolor(bg_roundrect, odd_col_bg, odd_col_bg)
            end
        end
        
        hbox_projects.onclick = function(self, event)
            if event.button == lbm then
                if n.sel == 0 then
                    update_player(n)
                end
                if event.ctrl then
                    if n.sel == 1 then --unselect
                        recolor(bg_roundrect, odd_col_bg, odd_col_bg)
                        
                        n.sel = 0
                    else --select
                        recolor(bg_roundrect, "#9a9a9a", hex_darker("#9a9a9a", 0.2))
                        
                        n.sel = 1
                    end
                elseif event.shift then
                    
                else
                    unselect_all_path()
                    recolor(bg_roundrect, "#9a9a9a", hex_darker("#9a9a9a", 0.2))
                    n.sel = 1
                end
            elseif event.button == rbm then
                --local x_offset = wnd.w/2-wnd.w+popup_by_path.w/2
                --local y_offset = wnd.h/2-wnd.h+popup_by_path.h/2
                
                local x_offset = rtk.mouse.x-wnd.calc.w+popup_by_path.calc.w
                local y_offset = rtk.mouse.y-wnd.calc.h+popup_by_path.calc.h
                
                
                OFFSETX, OFFSETY = 24.5, 24.5 -- when scale default
                
                
                local x_norm = rtk.mouse.x-OFFSETX-(x_offset > -1 and x_offset or 0) --(popup_by_path.calc.w - wnd.calc.w)/2+rtk.mouse.x - (x_offset > -1 and x_offset or 0) 
                local y_norm = rtk.mouse.y-OFFSETY-(y_offset > -1 and y_offset or 0)--(popup_by_path.calc.h - wnd.calc.h)/2+rtk.mouse.y - (y_offset > -1 and y_offset or 0)
                
                popup_by_path:move(x_norm, y_norm)
                
                
                if padcolor ~= def_pad_color then
                    popup_by_path:attr('shadow', padcolor..10)
                else
                    popup_by_path:attr('shadow', "#1a1a1a90")
                end
                popup_by_path:attr('alpha', 0.94)
                if n.sel == 0 then
                    unselect_all_path()
                end
                recolor(bg_roundrect, "#9a9a9a", smooth)
                n.sel = 1
                
                popup_by_path:open{}
                --popup_by_path:open{}
                
            end
            
            --get_selected_path()
        end
        hbox_projects.ondoubleclick=function(self, event)
            get_selected_path()
        end
        pad_status.sensitivity = 0.15
        
        pad_status.ondragstart = function(self, event, x, y, t)
            self.dragging = true
            self.prevY = y
            return true
        end
        
        pad_status.ondragend = function(self, event, dragarg)
            self.dragging = false
            self.prevY = nil
            
            pad_status=recolor(pad_status, padcolor_dim, padcolor_dim, progress_val)
            save_parameter(n.path, data)
        end
        
        pad_status.ondragmousemove = function(self, event, dragarg)
            -- if vertical drag --
            if self.dragging and self.prevY then
                local deltaY = event.y - self.prevY
                -- limit and round the progress value --
                if event.ctrl then self.sensitivity = 0.1 end
                progress_val = math.floor(math.max(0, math.min(100, progress_val - deltaY * self.sensitivity)))
                local progress_val_col = lerp(-0.2, 0.2, 0.2 - ( progress_val / 100 ))
                padcolor_dim = hex_darker(padcolor, progress_val_col)
                padcolor_dim_border = hex_darker(padcolor_dim, -0.5)
                recolor(self, padcolor_dim_border, padcolor_dim, progress_val)
                
                data.padcolor = padcolor
                data.progress = progress_val
                
                self.prevY = event.y
                
            end
            return
        end
        
        pad_status.onmousewheel = function(self, event)
            progress_val = math.floor(math.max(0, math.min(100, progress_val - event.wheel * 4)))
            local progress_val_col = lerp(-0.2, 0.2, 0.2 - ( progress_val / 100 ))
            padcolor_dim = hex_darker(padcolor, progress_val_col)
            padcolor_dim_border = hex_darker(padcolor_dim, -1.5)
            recolor(self, padcolor_dim, padcolor_dim, progress_val)
            
            data.padcolor = padcolor
            data.progress = progress_val
            save_parameter(n.path, data)
            return true
        end
        
        pad_status.onclick = function(self, event)
            if event.button == rbm then
                local ret, col = reaper.GR_SelectColor(wnd.hwnd)
                if ret then 
                    local col_hex = rtk.color.int2hex(col, true)
                    if col_hex == "#000000" then 
                        padcolor=def_pad_color 
                    else
                        padcolor=col_hex
                        recolor(self, col_hex, col_hex, progress_val)
                        
                        data.padcolor = padcolor
                        data.progress = progress_val
                        save_parameter(n.path, data)
                    end
                end
            elseif event.button == lbm and event.alt then
                clear_parameter(n.path) 
                progress_val=0
                padcolor=hex_darker(def_pad_color, lerp(-0.2, 0.2, 0.2 - ( progress_val / 100 ) ))
                recolor(self, padcolor, padcolor, progress_val)
            end
            
            
        end
        
        pad_status.ondoubleclick = function(self, event)
            progress_val=0
            recolor(self, padcolor, padcolor, progress_val)
            --[[
            clear_parameter(n.path) 
            data.dl = "2024.04.29 18:00:00"
            data.raiting = 4
            data.comment = "last version"
            data.tags = {"#OLDEST", "#TEST", "#WARIOUS"}
            print(n.path, data.dl, data.raiting, data.comment, table.concat(data.tags) )
            ]]
            save_parameter(n.path, data)
        end
        
        if data.dl ~= "" then 
            local current_time = os.time()
            local year, month, day, hour, min, sec = data.dl:match("(%d+)%.(%d+)%.(%d+) (%d+):(%d+):(%d+)")
            local deadline = os.time({year=year, month=month, day=day, hour=hour, min=min, sec=sec})
            
            local difference_in_seconds = os.difftime(deadline, current_time)
            
            local N = 5
            if difference_in_seconds <= N * 24 * 60 * 60 then
                local days = math.floor(difference_in_seconds / (24 * 60 * 60))
                difference_in_seconds = difference_in_seconds - (days * 24 * 60 * 60)
                local hours = math.floor(difference_in_seconds / (60 * 60))
                difference_in_seconds = difference_in_seconds - (hours * 60 * 60)
                local minutes = math.floor(difference_in_seconds / 60)
                create_shadow(container_hbox, 'transparent', deadline_warning_color, elevation_warning)
                --print(n.path, "Осталось" .. days .. ", часов: " .. hours .. ", минут: " .. minutes)
            end
        end
        
        local function text_enter()
            if b_path_box.mouseover then
                b_path:attr('fontflags', rtk.font.UNDERLINE) --подчеркнуть текст
                b_path:attr('text',n.dir) --подчеркнуть текст
            else
                b_path:attr('fontflags', false)
                b_path:attr('text',short_path) --подчеркнуть текст
            end
            val_touchscroll = get_modifier_value(KEY_FOR_TOUCHSCROLL)
            mouse_state = reaper.JS_Mouse_GetState(val_touchscroll)  
            rtk.touchscroll = (mouse_state == val_touchscroll) -- true or false
            rtk.defer(text_enter)
        end
        
        rtk.defer(text_enter)
        
        if i == 1 then 
            update_player(n)
            n.sel = 1
            recolor(bg_roundrect, "#9a9a9a", hex_darker("#9a9a9a", 0.2))
        end
    end
end




collection_all = {
name="Искушённый соблазном",
sec_name="Грустный",
img="удалю_фыв.png",
list={
"F:\\Projects Reaper\\Тима Проекты\\Ливнем от дождя\\Ливнем от дождя.RPP",
"F:\\Projects Reaper\\Тима Проекты\\Мелодия\\Мелодия.rpp",
"F:\\Projects Reaper\\Тима Проекты\\Оставлю на врем я\\Оставлю на врем я.rpp",
"F:\\Projects Reaper\\Тима Проекты\\Параллели судьбы\\Параллели судьбы.rpp",
}
}


--save_parameter("Искушённый соблазном",collection_all, params_data)
--get_all_names(params_data)
--

function create_list_collection(vbox_list, str_list)
    vbox_list:remove_all()
    for i, projects in ipairs(str_list) do
        local filename, path = extract_name(projects)
        vbox_list:add(rtk.Button{filename})
    end
end

function create_collection(vbox, vbox_list)
    
    vbox:remove_all()
    --Get all names in saved collections
    all_names = get_all_names(params_data)
    for i, blan in pairs(all_names) do
        --import data info for collection
        local DATA = get_parameter(blan, params_data)
        
        DATA = DATA or {
            name="",
            sec_name="",
            bgcol = "#7a7a7a",
            rating = 0,
            comment = "",
            img="",
            list={""},
            tags={},
        }
        local COL = DATA.col
        local NEW_COL= shift_color(COL, 1.0, 0.7, 0.7)
        
        image, name, second_name, tags = DATA.img, DATA.name, DATA.sec_name, DATA.tags
        --create bg roundrect
        local cont_collections=vbox:add(rtk.Container{ h=130,  w=1})
        local first_bg_spacer = create_spacer(cont_collections, NEW_COL, NEW_COL, round_rect_window)
        --main horisontal container
        local cont_hbox = cont_collections:add(rtk.HBox{padding=4,w=1})
        --create image
        local image = rtk.Image():load(CUSTOM_IMAGE_local .. DATA.img)
        local cont_img=cont_hbox:add(rtk.Container{},{fillh=true})
        local img = cont_img:add(rtk.ImageBox{padding=4,image=image,}, {}) 
        
        
        --main vbox section
        
        local cont_spacer = cont_hbox:add(rtk.Container{halign='center'})
        local info_bg_spacer = create_spacer(cont_spacer, COL, COL, round_rect_window)
        local main_vbox_right=cont_spacer:add(rtk.VBox{spacing=10, padding=4, w=1, },{halign='right', fillh=true})
        main_vbox_right:add(rtk.Heading{w=1, wrap=true, fontflags=rtk.font.BOLD, fontsize=20, font='Verdena', text=name})
        local hbox_second_name =main_vbox_right:add(rtk.HBox{})
        hbox_second_name:add(rtk.Heading{fontflags=rtk.font.BOLD, fontsize=16, font='Arial', text=second_name})
        hbox_second_name:add(rtk.Box.FLEXSPACE)
        local edit = hbox_second_name:add(rtk.Button{flat=true, icon=ic.draw, padding=-1})
        
        edit.onclick=function(self, event)
            local ret, col = reaper.GR_SelectColor(wnd.hwnd)
            if ret then 
                local col_hex = rtk.color.int2hex(col, true)
                
                recolor(first_bg_spacer, COL)
                recolor(info_bg_spacer, NEW_COL)
                
                save_parameter(DATA.name, DATA, params_data)
            end
            
        end
        
        main_vbox_right:add(rtk.Box.FLEXSPACE)
        
        
        --hbox tags secton (maybe viewport)
        local hbox_tags = main_vbox_right:add(rtk.HBox{bmargin=-24,spacing=2, valign='bottom', halign='center'},{valign='bottom', halign='center'})
        
        local entry_tag, cont_tag = rtk_Entry(hbox_tags, "#3a3a3a", "#3a3a3a", 5, "#tag") cont_tag:resize(1, 27) entry_tag:resize(1, 27)
        entry_tag:attr('value', DATA.comment)
        
        cont_tag.onkeypress=function(self, event)
            if event.keycode == rtk.keycodes.ENTER and entry_tag.focused  then
                DATA.comment=entry_tag.value
                entry_tag:blur()
                save_parameter(DATA.name, DATA, params_data)
            end
            return true
        end
        
        cont_collections.onclick=function(self, event)
            create_list_collection(vbox_list, DATA.list)
        end
    end
end


local open_group_editor = group_heading:add(rtk.Button{rmargin=14,">",tmargin=-7},{valign='center',  halign='right'})

local group_editor = rtk.Container{w=1,h=1}
local pop_up_editor = rtk.Popup{margin=-2, autoclose=false, border='transparent', padding=2, bg='transparent', child=group_editor}
local cont_group, hb_heading_group, vp_group = create_container({halign='right', w=1, h=1}, group_editor, "GROUP EDITOR") vp_group:attr('x', 2)



local hbox_head_grp=hb_heading_group:add(rtk.HBox{w=0.3})

back_from_grp=create_b(hbox_head_grp, '←   back', 70, 27, nil, nil, false) back_from_grp:move(4,3) 

main_vbox_COLLECTIONS = vp_group:add(rtk.VBox{border='red', w=1, h=90})

--HBOX AND BUTTONS TAB COLLECTIONS\WORKSPACE\ARCHIVE
tab_group_hbox = main_vbox_COLLECTIONS:add(rtk.HBox{spacing=def_spacing})
button_create_collect = tab_group_hbox:add(rtk.Button{halign='center', 'Collection'},{fillw=true})
button_create_workspace = tab_group_hbox:add(rtk.Button{halign='center', 'Workspace'},{fillw=true})
button_create_unused = tab_group_hbox:add(rtk.Button{halign='center', 'Archive'},{fillw=true})

--RIGHT AND LEFT SECTIONS
collections_main = vp_group:add(rtk.HBox{spacing=def_spacing})
COLLECTIONS_VB=collections_main:add(rtk.VBox{w=0.56, h=0.7, },{})

COLL_LIST_VB=collections_main:add(rtk.VBox{border='red', h=0.7, },{fillw=true})

--MAIN VBOX LIST PROJECTS
COLLECTIONS_VB_child=rtk.FlowBox{hspacing=def_spacing, vspacing=def_spacing, w=1}
COLLECTIONS_VB_VIEWPORT=COLLECTIONS_VB:add(rtk.Viewport{child=COLLECTIONS_VB_child})

--EXTRACT ALL SAVED COLLECTIONS
create_collection(COLLECTIONS_VB_child, COLL_LIST_VB)


--BOTTOM SECTION UNDER list
vp_group:add(rtk.HBox{border='blue', rmargin=4, h=0.2,  w=1})


back_from_grp.onclick=function(self,event)
    pop_up_editor:close()
end
open_group_editor.onclick=function(self,event)
    main_vbox_window:hide()
    pop_up_editor:open()
end
pop_up_editor.onclose=function(self,event)
    main_vbox_window:show()
end
--open_group_editor:onclick()






local bottom_section_vb = main_vbox_list:add(rtk.VBox{w=1, spacing=def_spacing})

local bottom_hbox_section = bottom_section_vb:add(rtk.HBox{spacing=def_spacing})
local player_container = bottom_hbox_section:add(rtk.Container{minw=220, h=110},{valign='center', fillw=true})

local bottom_right_section = bottom_hbox_section:add(rtk.VBox{h=110, spacing=def_spacing},{fillw=true})
local entry_find, cont = rtk_Entry(bottom_right_section, COL9, COL9, nil, "Find project") cont:resize(1, 30) entry_find:focus()


local comment_widgets_hbox = bottom_right_section:add(rtk.HBox{spacing=5, })

--DEAD LINE CONTAINER
local cont_bg_right_sect = comment_widgets_hbox:add(rtk.Container{minw=70,w=0.3})
create_spacer(cont_bg_right_sect, COL1, COL3, round_rect_window)


--TAGS BLOCK
local cont_bg_right_sect = comment_widgets_hbox:add(rtk.Container{})
create_spacer(cont_bg_right_sect, COL1, COL3, round_rect_window)

local tags_hbox_widgets = rtk.HBox{spacing=5,}
local TAGS_VP=cont_bg_right_sect:add(rtk.Viewport{hotzone=5, scrollbar_size=5, padding=4, h=1, scroll_left = 1,scroll_top=0, flexh =false, flexw = true, child=tags_hbox_widgets},{fillw=true})

local MENU_TAGS = rtk.NativeMenu()

MENU_TAGS:set({
    {'Add tag', id='add'},
    rtk.NativeMenu.SEPARATOR,
    {'Remove all tags' , id='project_all'},
})

TAGS_VP.onmousewheel=function(self, event)
    if event.wheel > 0 then
        TAGS_VP:scrollby(TAGS_VP.calc.w/2, nil)
    else
        TAGS_VP:scrollby(-TAGS_VP.calc.w/2, nil)
    end
end


local popup = rtk.Popup{shadow="purple#5", padding=-3, margin=-8, border='transparent', bg='transparent', ref='popup', child=rtk.VBox{w=0.5, h=95, ref='vb'}}
local cont_group, hb_heading_group, vp_group = create_container({halign='CENTER', w=1, h=1}, popup.refs.popup.refs.vb, "ADD TAGS") vp_group:attr('x', 2)
local b_close_cont=hb_heading_group:add(rtk.HBox{h=28, h=28, halign='right'},{fillw=true})
b_close_cont:add(rtk.Box.FLEXSPACE)
local b_close_p = create_b(b_close_cont, "X" , 28, 28, nil, nil, false) b_close_p.refs.X:attr('w', 28)b_close_p:move(-4, 2)
b_close_p.onclick=function()popup:close()end

function create_popup(heading,all_info,DATA)
    local tags=DATA.tags
    vp_group:remove_all()popup:open()
    local hbox=vp_group:add(rtk.HBox{padding=6,valign='center',spacing=def_spacing})
    local cont_1=hbox:add(rtk.Container{})
    local entry,cont=rtk_Entry(cont_1,'#3a3a3a',"#3a3a3a",5,heading)entry:resize(1,29)cont:resize(0.8,29)entry:focus()
    local b=create_b(hbox,"ADD",1,29,nil,nil,false)
    b.onclick=function(self,event)
        table.insert(tags,tostring(entry.value))
        save_parameter(all_info.path, DATA)
        update_player(all_info)-------------------- !!!!!!!!!!!!!!!!!!!!!! DONT UPDATE FUNCTION
        popup:close()
    end
    popup.onclose=function(self,event)
        
    end
    cont.onkeypress = function(self, event)
        if event.keycode == rtk.keycodes.ENTER then
            b:onclick()
        end
    end
end

function create_tag(DATA, tags_hbox_widgets, all_info)
    tags_hbox_widgets:remove_all()
    local tags=DATA.tags
    local VB_TAGS_01=nil

    for i = 1, #tags do
        if i % 2 == 1 then
            -- create VBox every 3 iterations
            VB_TAGS_01 = tags_hbox_widgets:add(rtk.VBox{spacing=2})
        end
        -- new hbox in vbox 
        local b_h = VB_TAGS_01:add(rtk.HBox{spacing=2})
        local b=create_b(b_h, tags[i],nil, 29, nil, nil, false)
        b:attr('maxw', 100)
        b:get_child(2):attr('wrap',true)
        b:get_child(2):attr('fontsize',15)
        local b_remove = b_h:add(rtk.Button{color='#2a2a2a90', fontscale=1.5,halign='center', w=15,x=2, h=32,textcolor2='white',textcolor='red', z=4, flat=true, padding=1,"×"},{valign='', halign=''})
        b_remove.onclick=function(self, event)
            table_remove(tags, tags[i])
            save_parameter(all_info.path, DATA)
            update_player(all_info) -------------------- !!!!!!!!!!!!!!!!!!!!!! DONT UPDATE FUNCTION
        end
    end
    
    TAGS_VP.onmousedown=function(self, event)
        if event.button == rtk.mouse.BUTTON_RIGHT then
            MENU_TAGS:open_at_mouse(TAGS_VP, "right", "bottom"):done(function(item) 
                if not item then return end
                if item.id == 'add' then
                    create_popup("ADD TAGS", all_info, DATA)
                elseif item.id == 'project_all' then
                    DATA.tags={}
                    save_parameter(all_info.path, DATA)
                    update_player(all_info)-------------------- !!!!!!!!!!!!!!!!!!!!!! DONT UPDATE FUNCTION
                end
            end)
        end
    end
end

function update_visibility(data, query, new_paths)
    query = tolower(query, 1)
    local first_visible = nil
    for i, item in ipairs(data) do
        local n = new_paths and new_paths[item] or item
        local path = n.path and tolower(n.path, 1)
        local filename = n.filename and tolower(n.filename, 1)
        local date = n.form_date and tolower(n.form_date, 1)
        n.sel = 0
        
        local tags, comments
        if new_paths then
            tags = n.DATA.tags and tolower(table.concat(n.DATA.tags), 1) or ""
            comments = n.DATA.comments and lower(n.DATA.comments, 1) or ""
        end
        -- find matching
        if path:find(query)
          or filename:find(query)
          or date:find(query)
          or (tags and tags:find(query))
          or (comments and comments:find(query)) then
            if new_paths then
                n.cont:show()
            else
                item:show()
            end
            if not first_visible then
                first_visible = n
            end
        else
            if new_paths then
                n.cont:hide()
            else
                item:hide()
            end
        end
    end
    
    if first_visible then
        update_player(first_visible)
        unselect_all_path()
        first_visible.sel = 1
        recolor(first_visible.cont.refs.bg_spacer, "#8a8a8a", hex_darker("#8a8a8a", 0.2))
    end
end

entry_find.onchange = function(self, event)
    update_visibility(sorted_paths, self.value, new_paths)
end


entry_find.onchange = function(self, event)
    -- or send one table - container with elements:
    --          filename; path; date 
    --      example:
    --  update_visibility(visible_list, self.value)
    --      visible_list - rtk.Container have string names
    update_visibility(sorted_paths, self.value, new_paths)
end



function update_player(all_info)
    
    volume, pan, loop, seek_pos, file = 1, 0, false, nil, ""
    output_chan, play_rate, pitch, preserve_pitch = 0, 1, 0, true
    ps_mode, ps_modes = 1, {{v=-1, n='Project default'}}
    time, want_pos, position, length = 0, 0, 0, 0
    
    
    local media_files = scan_dir(all_info.path)

    reaper.CF_Preview_StopAll()
    
    preview=nil
 
    file = media_files[1]
    player_container:remove_all()
    vp_images2:remove_all()
    
    if file ~= nil then 
        first_media = file:match("^.+\\(.+)%..+$") 
    end
    
    DATA = all_info.DATA--get_parameter(global_path)
    
    tags = DATA.tags
    raiting = DATA.raiting or 4
    col_shadow = DATA.padcolor
    image = DATA.img or "1.png"
    
    create_tag(DATA, tags_hbox_widgets, all_info)
    
    
    create_spacer(player_container, COL1, COL3, round_rect_window)
    --local PV_cont, HB_heading, VP_player = create_container({--[[minh=GRP_minh, minw=GRP_minw, maxw=GRP_maxw, ]]h=1, w=1}, player_container, "PREVIEW PLAYER")
    local main_hbox_player = VP_player or player_container:add(rtk.HBox{--[[ minw=400, ]]minh=105, h=1, w=1,  },{})

    --local METER_volume = vp_images2:add(VolumeMeter{color=col_meter, ref='meter2', w=8, h=60},{--[[valign='center',]] })-- METER_volume:hide()
    --------------------------------------------
    --------------- IMAGE BLOCK ----------------
    --------------------------------------------
    local picture_container_main = vp_images2:add(rtk.VBox{},{fillw=true,fillh=true}) vp_images2:attr('z', 4)
    local picture_box = picture_container_main:add(rtk.Container{halign='center',padding=5,minw=80,w=1, },{halign='center', valign='center', fillh=true})
    
    local image = rtk.Image():load(CUSTOM_IMAGE_local .. image)
    local cont_img=picture_box:add(rtk.Container{w=1},{fillh=true})
    local img = cont_img:add(rtk.ImageBox{minh=55, padding=2,image=image,}, {halign='center'}) 
    
    local spacer_shadow_cont=cont_img:add(rtk.Container{w=1},{fillw=true, fillh=true})
    local spacer = spacer_shadow_cont:add(rtk.Spacer{visible=false},{fillw=true,fillh=true})
    local shadow = rtk.Shadow(col_shadow.."20")
    
    --local b_change = rtk.Button{visible=false, color="#6a6a6a40",padding=1,x=3, visible=false, icon=ic_draw:recolor('gray')}
    --cont_img:add(b_change)
    if wnd.calc.w < 400 then
        --picture_container_main:hide()
    else
        --picture_container_main:show()
    end
    
    --------------------------------------------
    --------------------------------------------
    --------------------------------------------
    
    --- main player section ---
    local vbox_player = main_hbox_player:add(rtk.VBox{},{fillw=true})
    
    --------------------------------------------
    ---------------- MEDIA INFO ----------------
    --------------------------------------------
    local widgets_info_cont = vbox_player:add(rtk.Container{},{fillw=true})
    
    local file_info_HBox = widgets_info_cont:add(rtk.HBox{padding=1, h=0.457, spacing=6}, {fillw=true})
      
    --raiting  
    local icon_raiting_proj = file_info_HBox:add(rtk.Button{x=2, lpadding=8,y=4,flat=true,icon=rait_icons.angry, lmargin=6, w=45, h=45},{valign='top'}) icon_raiting_proj:hide()
    local rait_hbox = rtk.HBox{},{fillw=true}
    local pop_up_raiting = rtk.Popup{alpha=0.9, bg=COL3, border=COL5, padding=4, child=rait_hbox, anchor=icon_raiting_proj,width_from_anchor=false}
    ---------
    
    local b_settings_list = file_info_HBox:add(rtk.Button{surface=false,icon=ic_list, w=45, h=45},{valign='top'})
    local audio_filename = file_info_HBox:add(rtk.Heading{wrap=true, fontsize=22, text=first_media},{fillw=true, valign='center'})
    
    --local text_info_cont = file_info_HBox:add(rtk.Container{},{})
    
    
    --local file_info_VBox = text_info_cont:add(rtk.VBox{tmargin=10,w=1}, {valign='center',fillh=true})
    
    --filename
    
    ----tags
    --local tags_and_commets = file_info_VBox:add(rtk.Text{h=0.5, text=tags, fontsize=14.5, color="#5a5a5a", valign='bottom'},{})
    
    --local spacing = file_info_HBox:add(rtk.Spacer{w=0.4,},{fillh=true})
    
    
    --------------------------------------------
    --------------------------------------------
    --------------------------------------------
    
    local slider_value_vbox = vbox_player:add(rtk.VBox{z=10,tmargin=-5,maxh=20, lpadding=15,rpadding=15})
    
    local slider_length_audio = slider_value_vbox:add(SimpleSlider{showtext=false, disabled=true, hotzone=15, w=1,h=5, roundrad=round_rect_list, ttype=3, textcolor="transparent"},{valign='center'})
    
    local text_time_hbox = slider_value_vbox:add(rtk.HBox{lmargin=2, rmargin=2,},{fillw=true})
    local text_start = text_time_hbox:add(rtk.Text{"0:00"},{halign='right',valign='center'})
    local spacing_length = text_time_hbox:add(rtk.Spacer{},{fillw=true})
    local text_end = text_time_hbox:add(rtk.Text{"0:00"},{halign='right',valign='center'})
    
    -------- transport ---------
    local buttons_transport_cont = vbox_player:add(rtk.Container{y=-8,minh=50}, {fillh=true, fillw=true})
    
    local hbox_player = buttons_transport_cont:add(rtk.HBox{spacing=6},{valign='center', halign='center'})
    
    local b_loop_player = hbox_player:add(rtk.Button{surface=surface,halign='center',icon=ic_loop, w=35, h=35},{halign='right', valign='center'})
    --HERE SPACER
    hbox_player:add(rtk.Box.FLEXSPACE)
    local b_backward_player = hbox_player:add(rtk.Button{y=-2,surface=surface,icon=ic_backw, w=35, h=35, halign='center'},{valign='center'})
    local b_play_player = hbox_player:add(rtk.Button{tpadding=2,surface=surface,icon=ic_play, halign='center', w=50, h=40},{valign='center'})
    local b_forward_player = hbox_player:add(rtk.Button{y=-2,surface=surface,icon=ic_forw, halign='center',w=35, h=35},{valign='center'})
    --HERE SPACER
    hbox_player:add(rtk.Box.FLEXSPACE)
    local volume_slider = hbox_player:add(SimpleSlider{showtext=false, value=1,max=1.5,maxw=85,minw=30,hotzone=15,y=1, w=0.2,h=5, roundrad=2, ttype=3, textcolor="transparent",
    onchange=function(normval, val)
        reaper.CF_Preview_SetValue(preview, 'D_VOLUME', val)
    end
    },{valign='center'})
    
    --local METER_volume2 = vp_images2:add(VolumeMeter{color=col_meter, ref='meter', w=8}) wnd.onupdate = function() --[[main_hbox_player.refs.meter:set_from_track(preview)main_hbox_player.refs.meter2:set_from_track(preview) ]]end
    --METER_volume2:hide()
    
    
    
    draging = true

    local function upd()
        if cont_img.mouseover then
            spacer:show()
        else
            spacer:hide()
        end
        
        update_state(vp_images2, wnd, img)

        if preview and draging then
            time, want_pos, position, length = get_play_info(preview)
            slider_length_audio:attr('max', length)
            slider_length_audio:attr('value', position)
            text_start:attr('text', time:match("([^%.]*)"))
            text_end:attr('text', want_pos:match("([^%.]*)"))
            for i = 0, 2 - 1 do
              local valid, peak = reaper.CF_Preview_GetPeak(preview, i)
            end
        end
        rtk.defer(upd)
    end
    
    img.onmousedown = function(self, event)
        waitingForRelease=false
        return true
    end
    
    img.onmouseup = function(self, event)
        waitingForRelease=false
    end
    
    cont_img.ondropfile = function(self, event)
        dropped_path = event.files[#event.files]
        update_image(all_info, dropped_path, img)
        waitingForRelease = false
        startedOutside = false
        img:attr('border', 'transparent')
    end
    
    spacer.onreflow = function(self)
        shadow:set_rectangle(img.calc.w-8, img.calc.h-8, 30)
    end
    
    spacer.ondraw = function(self, offx, offy, alpha, event)
        shadow:draw(img.calc.x+4 + offx, img.calc.y+4 + offy, alpha)
        --b_change:attr('y', img.calc.y+3)
    end
    --[[
    b_change.onclick = function(self, event)
        local rv, img_path = reaper.JS_Dialog_BrowseForOpenFiles('Select custom image', '', FILE, '', true) 
        if rv == 1 then
            update_image(all_info, img_path, img)
        end
        waitingForRelease = false
        startedOutside = false
        img:attr('border', 'transparent')
    end
    ]]
    b_play_player.onclick=function(self, event)
        if preview then
            reaper.CF_Preview_Stop(preview)
            preview=nil
            slider_length_audio:attr('disabled', true)
            self:attr('icon', ic_play)
        else
            self:attr('icon', ic_stop)
            start()
            reaper.CF_Preview_SetValue(preview, 'D_VOLUME', volume_slider.value)
            slider_length_audio:attr('disabled', false)
        end
    end
    
    slider_length_audio.ondragstart = function(self, event)
        draging = false
        reaper.CF_Preview_SetValue(preview, 'D_POSITION', slider_length_audio.value)
        if GLOBAL_ANIMATE then
            slider_length_audio:animate{'h', dst=20, duration=0.3}
            text_time_hbox:animate{'tmargin', dst=-20, duration=0.3}
        else
            slider_length_audio:attr{'h', 20}
            text_time_hbox:attr{'tmargin', -20}
        end
        return true
    end
    
    slider_length_audio.ondragend=function(self, event)
        draging=true
        reaper.CF_Preview_SetValue(preview, 'D_POSITION', slider_length_audio.value)
        return true
    end
    
    slider_length_audio.onmouseup=function(self, event)
        draging=true
        reaper.CF_Preview_SetValue(preview, 'D_POSITION', slider_length_audio.value)
        return true
    end
    
    slider_length_audio.onmousedown=function(self, event)
        draging=false
        return true
    end
    
    volume_slider.onmouseenter = function(self, event)
        if GLOBAL_ANIMATE then
            self:animate{'h', dst=10, duration=0.1}
            self:animate{'w', dst=0.24, duration=0.1}
        else
            self:attr{'h', 10}
            self:attr{'w', 0.24}
        end
        return true
    end
    
    volume_slider.onmouseleave = function(self, event)
        if GLOBAL_ANIMATE then
            self:animate{'h', dst=5, duration=0.2}
            self:animate{'w', dst=0.2, duration=0.2}
        else
            self:attr{'h', 5}
            self:attr{'w', 0.2}
        end
        return true
    end
    
    volume_slider.onmousewheel = function(self, event)
        local delta = event.wheel < 1 and 0.2 or -0.2
        if GLOBAL_ANIMATE then
            self:animate{'value', dst = volume_slider.value + delta, duration = 0.2, easing = "out-cubic"}
        else
            self:attr{'value', volume_slider.value + delta}
        end
        reaper.CF_Preview_SetValue(preview, 'D_VOLUME', volume_slider.value)
    end
    
    volume_slider.ondoubleclick = function(self, event)
        if GLOBAL_ANIMATE then
            self:animate{'value', dst = 1, duration = 0.3, easing = "out-cubic"}
        else
            self:attr{'value', 1}
        end
        reaper.CF_Preview_SetValue(preview, 'D_VOLUME', 1)
    end
    
    slider_length_audio.onmouseenter = function(self, event)
        if GLOBAL_ANIMATE then
            slider_length_audio:animate{'h', dst=20, duration=0.1}
            text_time_hbox:animate{'tmargin', dst=-20, duration=0.1}
        else
            slider_length_audio:attr{'h', 20}
            text_time_hbox:attr{'tmargin', -20}
        end
        return true
    end
    
    slider_length_audio.onmouseleave = function(self, event)
        if GLOBAL_ANIMATE then
            slider_length_audio:animate{'h', dst=5, duration=0.2}
            text_time_hbox:animate{'tmargin', dst=0, duration=0.2}
        else
            slider_length_audio:attr{'h', 5}
            text_time_hbox:attr{'tmargin', 0}
        end
        return true
    end
    
    icon_raiting_proj.onclick=function(self, event)
        pop_up_raiting:open()
        pop_up_raiting.child.SELF = icon_raiting_proj
    end
    
    
    icon_raiting_proj:attr('icon', rait_icons[icons_row1[raiting]])
    
    for i, icon_name in ipairs(icons_row1) do
        local icon = rait_icons[icon_name]
        local b = rait_hbox:add(rtk.Button{border=COL9, color=COL1, flat=true, icon=icon})
        b.onclick = function(self, event)
            DATA.raiting  = i
            raiting = 1
            rait_hbox.SELF:attr('icon', icon)
            pop_up_raiting:close()
            save_parameter(all_info.path,DATA)
            -- 
            
        end
    end

    rtk.defer(upd)
end

local cont_info_bar = main_vbox_list:add(rtk.Container{w=1, h=30})
local info_bar = create_spacer(cont_info_bar, COL1, COL3, round_rect_window)

create_block_list()


--create_list()


--new_paths[sorted_paths[1]].hbox.refs.date.onreflow = function(self, event)
--    update_window(wnd, wnd.w, wnd.h)
--end


--[[
COLLECTIONS_VB_VIEWPORT=COLLECTIONS_VB:add(rtk.Viewport{scroll_left = 1, flexw = true, child=COLLECTIONS_VB_child})

for i = 1,26 do
    local b=COLLECTIONS_VB_child:add(rtk.Button{'Hello ' .. tostring(i)})
    b.onclick = function(self, event)
        if event.button == lbm then
            COLLECTIONS_VB_VIEWPORT:scrollby(50, nil)
        elseif event.button == rbm then
            COLLECTIONS_VB_VIEWPORT:scrollby(-50, nil)
        end
    end
end
]]
