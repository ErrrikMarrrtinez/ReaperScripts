-- @description ReaProjects - Project Manager
-- @author mrtnz
-- @version 0.1.26-alpha
-- @changelog
--  More Added Widgets
-- @provides
--   libs/*.lua
--   modules/*.lua
--   data/*.ini
--   icons/*.png
--   customImages/*.png




--if reaper.ShowMessageBox("This is an alpha version of the script that is not yet suitable for use, you can only superficially familiarize yourself. Click 'OK' to continue or 'CANCEL' to exit.",  "WARNING!", 1) == 1 then else return end
function print(...) local t = {...} for i = 1, select('#', ...) do t[i] = tostring(t[i]) end reaper.ShowConsoleMsg(table.concat(t, '\t') .. '\n') end
--- collect paths ---
sep          = package.config:sub(1,1)
cur_path     = ({reaper.get_action_context()})[2]:match('^.+' .. sep)
ini_path     = reaper.get_ini_file()
icon_path    = cur_path .. "icons"
data_path    = cur_path .. "data"
package.path = cur_path ..'libs' .. sep .. '?.lua'
----------------------

--- req libraries ---
rtk  = require('rtk')
json = require('json')
---------------------F

--- main dictionary ---
all_paths      = {}
all_paths_list = {}
-----------------------


--- modules ---
dofile(cur_path.."modules"..sep.."widgets.lua")
dofile(cur_path.."modules"..sep.."func.lua");                 check_and_create_files(data_path);if check_exts() then return end; 
dofile(cur_path.."modules"..sep.."variables.lua")                
rtk.add_image_search_path(cur_path..sep.."icons", 'dark')
--------------------
--- initialize ---
def_bg_color              = rtk.color.get_reaper_theme_bg()
def_pad_color             = hex_darker (def_bg_color, -0.46)
ic, img                   = loadIcons(icon_path)
data_files                = loadIniFiles(data_path)

                            
collections_file          = data_files.collections
workspace_file            = data_files.workspaces
archives_file             = data_files.archives
params_file               = data_files.params
settings_file             = data_files.settings
-------------------

 
 
--- constains ---
lbm                       = rtk.mouse.BUTTON_LEFT
rbm                       = rtk.mouse.BUTTON_RIGHT
cbm                       = rtk.mouse.BUTTON_MIDDLE
def_spacing               = 5
rtk.double_click_delay    = 0.4
-----------------

BACKUPS_CURRENT           = true
scale   = 1.0
preview = nil


MAIN_PARAMS               = update_params(MAIN_PARAMS, settings_file)
CURRENT_media_path        = MAIN_PARAMS.current_media_path
GENERAL_media_path        = MAIN_PARAMS.general_media_path
INDIVIDUAL_media_path     = MAIN_PARAMS.individ_media_path
TYPE_module               = MAIN_PARAMS.last_type_opened
--- return projects ---

recent_projects_path      = get_recent_projects(ini_path)
new_paths, all_paths_list = get_all_paths(recent_projects_path)
sorted_paths              = sort_paths(new_paths, all_paths_list, MAIN_PARAMS.sort, MAIN_PARAMS.sort_dir)

ALL_PROJECTS_INIT         = {}
-----------------------
-----create window-----
-----------------------




local wnd = rtk.Window{opacity=0.98, borderless=false, x=MAIN_PARAMS.last_x,y=MAIN_PARAMS.last_y,bg=COL0, expand=1, w=MAIN_PARAMS.wnd_w*rtk.scale.value, h=MAIN_PARAMS.wnd_h, padding=10, minh=500, minw=500, } 
wnd.onresize = function(self, w, h)
    self:reflow()
end 

if MAIN_PARAMS.last_x < 0 then
    wnd:move(1,  _)
end

wnd.onclose = function() 
    MAIN_PARAMS.last_x, MAIN_PARAMS.last_y,MAIN_PARAMS.wnd_w, MAIN_PARAMS.wnd_h = wnd.x, wnd.y, wnd.calc.w, wnd.calc.h
    save_parameter("MAIN", MAIN_PARAMS, settings_file) 
    reaper.CF_Preview_StopAll();rtk.quit() 
end
--------scale problems---------
if rtk.scale.value ~= 1.0 then
    rtk.scale.user = scale/rtk.scale.value
    GLOBAL_ANIMATE = false
    wnd:attr('w', wnd.calc.w * rtk.scale.value) -- last w
    wnd:attr('h', wnd.calc.h * rtk.scale.value) -- last h
end

local MAIN_CONTAINER_WINDOW = wnd:add(rtk.Container{},{expand=1, })


--local WND_vbox=wnd:add(rtk.VBox{spacing=def_spacing})
local main_vbox_window = MAIN_CONTAINER_WINDOW:add(rtk.VBox{minh=400, minw=370, spacing=def_spacing},{expand=1, fillh=true})

local app_main_hbox = main_vbox_window:add(rtk.HBox{w=1, h=32})

--left side application
local cont_left_app = app_main_hbox:add(rtk.Container{h=34, w=0.2, minw=60})
local left_app_hbox=cont_left_app:add(rtk.HBox{w=1},{halign='left', valign='center'})

--right side applications
local cont_edge_app = app_main_hbox:add(rtk.Container{h=34, w=1})
local app_right = cont_edge_app:add(rtk.HBox{spacing=def_spacing,lmargin=3,rmargin=1,},{halign='right', valign='center'}) 
--app_right:add(--addhere)
app_right:add(rtk.Box.FLEXSPACE)
local pin_app = create_b(app_right, "PIN", 40, 30, true, ic.pin:scale(120,120,22,5):recolor("white"))
local settings_app = create_b(app_right, "STNGS", 40, 30, true, ic.settings:scale(120,120,22,5):recolor("white") ) settings_app.click=1


local main_hbox_window = main_vbox_window:add(rtk.HBox{minh=350,  spacing=def_spacing},{fillw=true, fillh=true})
local left_vbox_sect = main_hbox_window:add(rtk.VBox{h=1, B_heigh=27, spacing=def_spacing},{stretch=25, fillh=true,})



--settings block--
local main_settings_box = main_vbox_window:add(rtk.VBox{ref='set', w=1, visible=false})
local VP_settings_vbox = rtk.VBox{spacing=def_spacing, padding=2, w=1}
local VP_settings = main_settings_box:add(rtk.Viewport{child = VP_settings_vbox, smoothscroll = true,scrollbar_size = 12,z=2})

local cont_player = VP_settings_vbox:add(rtk.Container{w=1})
cont_player:add(rtk.VBox{padding=12, ref='player', spacing=def_spacing})



local hbox_settings_heading_1 = cont_player.refs.player:add(
    rtk.HBox{spacing=20,valign='center',lmargin=50,})
hbox_settings_heading_1:add(
    rtk.Spacer{border='2px '..COL11},{fillw=true})
hbox_settings_heading_1:add(
    rtk.Heading{fontsize=24,font='Verdena', "Global settings"})
hbox_settings_heading_1:add(
    rtk.Spacer{bborder='4px '..COL11},{fillw=true})

local VB_media=cont_player.refs.player:add(
    rtk.VBox{
        minw=420,
        maxw=600,
        padding=30,
        halign='center', 
        w=1, 
        tmargin=1,
        spacing=5,
        ref='vb',
            rtk.Heading{
                fontsize=22,
                font='Verdena',
                "Preview mode"
            }, 
        },
    {halign='center',}
)




local self_inst = VB_media:add(RoundButton{round=14, halign='left', color='#5a5a5a', h=30, w=1, fontsize=22, text="Self-installation"})
local gen_dir = VB_media:add(RoundButton{round=14, halign='left', color='#5a5a5a', h=30, w=1, fontsize=22, text="General directory"})

local hb_entry = VB_media:add(rtk.HBox{bmargin=4,spacing=20, h=30, w=1})
hb_entry:add(rtk.Heading{x=10,fontsize=22, valign='center', h=1, "Default render path:"})

local entry_custom_path, custom_path_cont = rtk_Entry(hb_entry, COL2, COL0, 6, "Custom media path")
entry_custom_path:attr('value', update_defrender_path());entry_custom_path:attr("caret", 0)

local cont_button_finder = create_b(hb_entry, "DIR", 40, 30, true, ic.dir:scale(120,120,22,5):recolor("white"), false);cont_button_finder:move(-10, 2)


local current_inst = VB_media:add(RoundButton{round=14, halign='left', color='#5a5a5a', h=30, w=1, fontsize=22, "Path to rpp"})

VB_media:add(
    rtk.Heading{
        fontsize=22,
        font='Verdena',
        "Name"
    }
)

local one_name_b = VB_media:add(RoundButton{round=14, halign='left', h=30, w=0.8, color='#5a5a5a', fontsize=22, text="One similar last name"},{})
local all_similar_b = VB_media:add(RoundButton{round=14, halign='left', color='#5a5a5a', h=30, w=0.8, fontsize=22, text="All similar names (by date)"})
local all_names_dir = VB_media:add(RoundButton{state='on', round=14, halign='left', color='#5a5a5a', h=30, w=0.8, fontsize=22, "All names"})



local media_buttons = {current_inst, self_inst, gen_dir}
local curr_childs = {one_name_b, all_similar_b, all_names_dir}


local function reset_m_b(self, event, tab)
    if LBM(event)then
        for _, b in ipairs(tab) do
            b:attr('state', 'off')
        end
        GENERAL_media_path[1] = false
        MAIN_PARAMS.general_media_path[1] = GENERAL_media_path[1]
        
        INDIVIDUAL_media_path = false
        MAIN_PARAMS.individ_media_path = INDIVIDUAL_media_path
        
        CURRENT_media_path = false
        MAIN_PARAMS.current_media_path = CURRENT_media_path
    end
end

gen_dir.onmousedown=function(self,event)
    reset_m_b(self, event, media_buttons)
    GENERAL_media_path[1] = true
    MAIN_PARAMS.general_media_path[1] = GENERAL_media_path[1]
end
self_inst.onmousedown=function(self,event)
    reset_m_b(self, event, media_buttons)
    INDIVIDUAL_media_path = true
    MAIN_PARAMS.individ_media_path = INDIVIDUAL_media_path
end
current_inst.onmousedown=function(self,event)
    reset_m_b(self, event, media_buttons)
    CURRENT_media_path = true
    MAIN_PARAMS.current_media_path = CURRENT_media_path
end


one_name_b.onmousedown=function(self,event)
    reset_m_b(self, event, curr_childs)
end
all_similar_b.onmousedown=function(self,event)
    reset_m_b(self, event, curr_childs)
end
all_names_dir.onmousedown=function(self,event)
    reset_m_b(self, event, curr_childs)
end


custom_path_cont.onkeypress = function(self, event)
    if event.keycode == rtk.keycodes.ENTER and entry_custom_path.focused then
        entry_custom_path:blur()
    end
end
cont_button_finder.onclick = function(self,event)
    local rv, new_file = reaper.JS_Dialog_BrowseForFolder('Select preview directory', '')
    if rv then
        entry_custom_path:attr('value', new_file)
    end
end
entry_custom_path.onchange=function(self,event)
    MAIN_PARAMS.general_media_path[2] = self.value
end


if INDIVIDUAL_media_path then
    self_inst:attr('state', 'on')
elseif GENERAL_media_path[1] then
    gen_dir:attr('state', 'on')
elseif CURRENT_media_path then
    current_inst:attr('state', 'on')
end


--[[
local checkboxes={self_inst, gen_dir, current_inst}

function reset_checks(self)
    for _, b in ipairs(checkboxes) do
        b:attr('border',false)
    end
    self:attr('border','red')
end

self_inst.onclick=function(self,event)
    reset_checks(self, checkboxes)
end

gen_dir.onclick=function(self,event)
    reset_checks(self, checkboxes)
end

current_inst.onclick=function(self,event)
    reset_checks(self, checkboxes)
end
]]
--[[

    --upd_checks()
    
    
    GENERAL_media_path[1] = true
    MAIN_PARAMS.general_media_path[1] = true
    
    
    INDIVIDUAL_media_path = false
    MAIN_PARAMS.individ_media_path = false
    CURRENT_media_path = false
    MAIN_PARAMS.current_media_path = false
    
    
-- Инициализация

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
local GRP_minw,GRP_maxw,GRP_minh,GRP_w, bh =95,175,145,0.25, 24
local OPEN_container, OPEN_heading, OPEN_vp_vbox = create_container({minw=GRP_minw, maxw=GRP_maxw, w=GRP_w}, left_vbox_sect,'OPEN PROJECTS')
local NEW_container, NEW_heading, NEW_vp_vbox = create_container({minw=GRP_minw, maxw=GRP_maxw, w=GRP_w}, left_vbox_sect, 'NEW PROJECTS')
local GROUP_container, group_heading, group_vp_vbox = create_container({minw=GRP_minw, maxw=GRP_maxw, w=GRP_w}, left_vbox_sect, ' ');group_vp_vbox:attr('spacing', 2)


local IMG_container, IMG_head, vp_images2 = create_container({minw=GRP_minw, maxw=GRP_maxw, h=1, w=GRP_w}, left_vbox_sect, '[<]   IMG   [>]')

IMG_container.refs.VBOX:remove(IMG_container.refs.VBOX.refs.HEAD)


reorder_box(left_vbox_sect, OPEN_container, {expand=1.1, fillh=true})
reorder_box(left_vbox_sect, NEW_container, {expand=1.1, fillh=true})
reorder_box(left_vbox_sect, GROUP_container, {expand=1.3, fillh=true})
reorder_box(left_vbox_sect, IMG_container, {expand=0.8, fillh=true})

OPEN_vp_vbox:attr('padding', 4)
NEW_vp_vbox:attr('padding', 4)
OPEN_vp_vbox:attr('spacing', 4)
NEW_vp_vbox:attr('spacing', 4)

local OPEN_selected_project = OPEN_vp_vbox:add(RoundButton{halign='center', h=1, "OPEN", color="#6a6a6a", toggle=false}, {fillw=true, expand=1, fillh=true})
local OPEN_selected_projects_newt = OPEN_vp_vbox:add(RoundButton{halign='center', h=1, "NEW TAB", color="#6a6a6a", toggle=false}, {fillw=true, expand=1, fillh=true})
local OPEN_selected_projects_recovery = OPEN_vp_vbox:add(RoundButton{halign='center', h=1, "RECOVERY", color="#6a6a6a", toggle=false}, {fillw=true, expand=1, fillh=true})

local NEW_project_tab = NEW_vp_vbox:add(RoundButton{halign='center', h=1, "NEW TAB", color="#6a6a6a", toggle=false}, {fillw=true, expand=1, fillh=true})
local NEW_project_current = NEW_vp_vbox:add(RoundButton{halign='center', h=1, "NEW PROJECT", color="#6a6a6a", toggle=false}, {fillw=true, expand=1, fillh=true})
local NEW_project_close = NEW_vp_vbox:add(RoundButton{halign='center', h=1, "", color="#6a6a6a", toggle=false}, {fillw=true, expand=1, fillh=true})

NEW_project_close.onreflow = function(self); self:attr('text', self.calc.w > 137 and "NEW TAB(PRESERVE)" or "NEW TAB(PS)") end

NEW_project_current.onclick = function(self, event)
    if LBM(event) then
        reaper.Main_OnCommand(40859, 0)
    end
end

NEW_project_tab.onclick = function(self, event)
    if LBM(event) then
        reaper.Main_OnCommand(41929, 0)
    end
end

NEW_project_close.onclick = function(self, event)
    if LBM(event) then
        reaper.Main_OnCommand(40026, 0)
        reaper.Main_OnCommand(40023, 0)
    end
end

OPEN_selected_project.onclick = function(self, event)
    if LBM(event) then
        local paths = get_selected_path()
        for i, path in ipairs(paths) do
            if i == #paths then
                reaper.Main_openProject(path)
            end
        end
    end
end

OPEN_selected_projects_newt.onclick = function(self, event)
    if LBM(event) then
        local paths = get_selected_path()
        for i, path in ipairs(paths) do
            reaper.Main_OnCommand(41929, 0)
            reaper.Main_openProject(path)
        end
    end
end

OPEN_selected_projects_recovery.onclick = function(self, event)
    if LBM(event) then
        local paths = get_selected_path()
        for i, path in ipairs(paths) do
            open_project_recovery(path)
        end
    end
end


----------------------
local main_vbox_list = main_hbox_window:add(rtk.VBox{debug=false,  spacing=def_spacing},{fillh=true, fillh=true})

local hbox_sorting_modul = main_vbox_list:add(rtk.HBox{x=8, spacing=def_spacing, h=25})

local hbox_listmode = hbox_sorting_modul:add( 
    rtk.HBox{
        cursor=rtk.mouse.cursors.HAND, 
        w=150, 
        lhotzone=5, 
        hotzone=15, 
        lmargin=5, 
        spacing=5, 
        rtk.Button{
            disabled=true, 
            color='#ffffff50',
            ref='b',
            circular=true,
            }, 
        rtk.Text{
            ref='t',
            x=5, 
            y=1,
            "List mode"
            },
        }
    )
hbox_sorting_modul:add(rtk.Box.FLEXSPACE)
hbox_sorting_modul:add(rtk.Text{y=1, fontsize=19, valign='center', h=1, "SORT BY"})


if TYPE_module == 0 then
    hbox_listmode.refs.t:attr('text', 'Block mode')
else 
    hbox_listmode.refs.t:attr('text', 'List mode')
end

hbox_listmode.onmouseenter=function(self,event)
    --for i, elems in ipairs(self.children) do
    --    
    --end
    self.refs.b:attr('color', 'orange')
    self.refs.t:attr('color', 'orange')
    return true
end

hbox_listmode.onclick=function(self,event)
    if TYPE_module == 1 then
        TYPE_module = 0
        MAIN_PARAMS.last_type_opened = 0
        self.refs.t:attr('text', 'Block mode')
    else 
        TYPE_module = 1
        MAIN_PARAMS.last_type_opened = 1
        self.refs.t:attr('text', 'List mode')
    end

    save_parameter("MAIN", MAIN_PARAMS, settings_file)
    main_run()
end

hbox_listmode.onmouseleave=function(self,event)
    self.refs.b:attr('color', '#ffffff50')
    self.refs.t:attr('color', '#ffffff')
end
local menu = {
    {'New ➤ Old', 'date', 1},
    {'Old ➤ New', 'date', 0},
    {'A ➤ Z', 'az', 1},
    {'Z ➤ A', 'az', 0},
    {'Small ➤ Large', 'size', 1},
    {'Large ➤ Small', 'size', 0},
    {'First ➤ Last','opened', 1},
    {'Last ➤ First','opened', 0},
}

local HB_sort = hbox_sorting_modul:add(rtk.VBox{})
local option_menu = HB_sort:add(OptionMenu{ pos='left', minw=140, current=MAIN_PARAMS.sort_type, menu=menu, cursor=rtk.mouse.cursors.HAND, color=COL8, h=25,w=0.3},{})
local VB_RVB = RoundrectVBox({y=3, margin=-12, w=1, h=200}, "#353535", 8)
 
option_menu.onmousedown=function(self,event)
    if popupOption.opened then
        popupOption:close()
    else
        PopupOption(self, VB_RVB)
        popupOption.onclose=function(self,event)
            local key = menu[option_menu.current][2]
            local direction = menu[option_menu.current][3]
            sorted_paths = sort_paths(new_paths, all_paths_list, key, direction)
            
            MAIN_PARAMS.sort, MAIN_PARAMS.sort_dir, MAIN_PARAMS.sort_type = key, direction, option_menu.current
            save_parameter("MAIN", MAIN_PARAMS, settings_file)
            main_run(TYPE)
        end
    end
    return true
end

local list_container, container_heading, list_vbox_group, vp_main_list = create_container({fillw=true}, main_vbox_list) 


reorder_box(main_vbox_list, list_container, {fillh=true})
--[[
local cont_idx = main_vbox_list:get_child_index(list_container)
local NEW_list_container = main_vbox_list:remove_index(cont_idx) 
main_vbox_list:add(NEW_list_container, {fillh=true})]]
--list_container:attr('border','red')

list_vbox_group:attr('bmargin', 6)
list_vbox_group:attr('spacing', 3)

list_vbox_group.onmousewheel=function(self,event)
    if event.alt then
        local new_h = update_heigh_list(event.wheel)
        return true
    end
end

--[[---------------------------------
----------resizible list----------

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
        local new_h = rtk.clamp(mouseH + event.y - mouseX, 300, main_vbox_window.minh-120)
        --norm_h = norm(new_h, 0, wnd.calc.h)
        list_container:attr('h', new_h)
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


local cont_vb_popup_nm = rtk.Container{w=1, h=1}
local bg_native_menu = cont_vb_popup_nm:add(RoundButton{round=16, h=1, toggle=false, color='#7a7a7a'," ", disabled=true},{fillw=true, fillh=true})
local vbox_popup = cont_vb_popup_nm:add (rtk.VBox{y=2, padding=3, h=1}, {fillh=true} )

local def_h_b = 28
local popup_by_path = rtk.Popup{
    autofocus=false, margin=-15, padding=0,
    x=1, y=1, alpha=0.9, bg=COL9, 
    border='transparent', bg='transparent', 
    shadow="transparent",
    child=cont_vb_popup_nm, w=175, h=50, overlay='black#50'}


all_windows = rtk.VBox{z=10}
popup_backups = rtk.Popup{z=10, autofocus=true, autoclose=true, child=all_windows}

local function nm_button(name, round)
    local round = round or 8
    return RoundButton{toggle=false, round=round, h=def_h_b ,padding=2,  color="#6a6a6a",text=name, w=1}
end

function native_menu(n)
    vbox_popup:remove_all()
    
    local x_offset = math.max(0, rtk.mouse.x - wnd.calc.w + popup_by_path.calc.w) + 20
    local y_offset = math.max(0, rtk.mouse.y - wnd.calc.h + popup_by_path.calc.h) + 15
    local x_norm = (rtk.mouse.x - x_offset) / rtk.scale.value
    local y_norm = (rtk.mouse.y - y_offset) / rtk.scale.value
    popup_by_path:move(x_norm, y_norm)
    popup_by_path:open{}

    local open_cur_proj_b = vbox_popup:add(nm_button("OPEN"))open_cur_proj_b:attr('y', 2)
    local new_tab_proj_b = vbox_popup:add(nm_button("NEW TAB", 2))new_tab_proj_b:attr('z',2)
    local b_offline = vbox_popup:add(nm_button( "OFFLINE", 2))
    local b_backups_open = vbox_popup:add(nm_button("BACKUPS", 2))
    local b_open_folder = vbox_popup:add(nm_button("OPEN PATH", 2))
    
    vbox_popup:add(nm_button("RECOLOR", 2))
    local b_settings = vbox_popup:add(nm_button("SETTINGS", 2))b_settings:attr('z',2)
    local b_remove = vbox_popup:add(nm_button("REMOVE" ))b_remove:attr('y', -2)
    
    
    popup_by_path:attr('h', def_h_b*#vbox_popup.children+13)
    b_open_folder.onclick=function(self,event)
        if LBM(event) then
            local paths = get_selected_path()
            for i, path in ipairs(paths) do
                reaper.CF_LocateInExplorer(path)
            end
            popup_by_path:close()
        end
        
    end
    
    new_tab_proj_b.onclick=function(self,event)
        if LBM(event) then
            OPEN_selected_projects_newt:onclick()
            popup_by_path:close()
        end
    end
    
    open_cur_proj_b.onclick=function(self,event)
        if LBM(event) then
            OPEN_selected_project:onclick()
            popup_by_path:close()
        end
    end
    
    b_offline.onclick=function(self,event)
        if LBM(event) then
            local paths = get_selected_path()
            for i, path in ipairs(paths) do
                open_project_recovery(path)
                popup_by_path:close()
            end
        end
    end
    
    b_backups_open.onclick=function(self,event)
        if LBM(event) then
            PROJECT_PATH_BACKUPS = get_backups_folder(n.dir)
            dofile(cur_path.."modules"..sep.."backups.lua")
            create_backups()
            popup_by_path:close()
            popup_backups:open()
        end
    end

end
local HEADING_types_hbox = rtk.HBox{ref='heading', y=-6.5,}

function create_block_list()
    HEADING_types_hbox:hide()
    local flowbox_main
    if rtk.scale.value ~= 1.0 then
        --flowbox_main = rtk.FlowBox{bmargin=6, expand=4, spacing=-1, }, {stretch=1}
    else
        --flowbox_main = rtk_FlowBox({bmargin=6, expand=4, spacing=-1, w=1})
    end
    flowbox_main = rtk_FlowBox({bmargin=6, expand=4, spacing=-1, w=1})
    --local flowbox_main = rtk.FlowBox{margin=4, expand=4, spacing=-2, w=1}
    flowbox_main:remove_all()
    list_vbox_group:remove_all()
    vp_main_list:attr('child', flowbox_main)
    --list_vbox_group
    for i, path in ipairs(sorted_paths) do
        local n = new_paths[path]
        
        
        
        local data = n.DATA or {
            progress = 0,
            padcolor = COL13,
            rating = 0,
            comment = "",
            dl="",
            img="1.png",
            tags={},
        }
        
        
        n.DATA = data        
        
        local image = data.img or "1.png"
        local raiting = data.raiting or 4
        local def_padcol = data.padcolor or COL13
        local norm_prog_val = data.progress/100 or 0
        
        
        local BG_COL = shift_color(def_padcol, 1.0, 0.5, 1)
        local PAD_COL = shift_color(def_padcol, 1.0, 0.35, 0.7)
        local HOVER_COL = shift_color(def_padcol, 1.0, 1, 1.3)
        local SELECTED_COL = shift_color(def_padcol, 1.0, 1, 1.4)
        
        
        local odd_col_bg = i % 2 == 0 and '#3a3a3a' or '#323232'

        local container_hbox = flowbox_main:add(rtk.Container{minw=230, hotzone=-3, expand=3, h=135,padding=4,},{stretch=i, expand=i, fillw=true})
        
      
        local bg_roundrect = create_spacer(container_hbox, odd_col_bg, odd_col_bg, round_rect_list+5) bg_roundrect:attr('ref', 'bg_spacer')
        local def_vb = container_hbox:add(rtk.HBox{w=1, h=1})
        
        local left_img_progress=def_vb:add(rtk.VBox{y=1, h=1, w=130})
        
        
        local image = rtk.Image():load(CUSTOM_IMAGE_local .. image)
        local cont_img=left_img_progress:add(rtk.Container{lmargin=5, h=125, w=125},{valign='center', stretch=2, expand=2, fillh=true})
        local img = cont_img:add(rtk.ImageBox{padding=4,image=image,h=1}, {valign='center', stretch=4, expand=1,}) 
        cont_img.onclick=function(self,event)
            local ext_list = "Image files (*.png;*.jpg;*.jpeg)\0*.png;*.jpg;*.jpeg\0\0"
            local rv, img_path = reaper.JS_Dialog_BrowseForOpenFiles('Select custom image', '', '', ext_list, true)
            if rv == 1 then
                update_image(n, img_path, img, data)
                update_player(n)
            end
            
        end
        
        local slider_length_audio = left_img_progress:add(SimpleSlider{
        y=-30, x=14, w=100, value=norm_prog_val, croll_on_drag=false, color=PAD_COL, 
        hotzone=5, roundrad=round_rect_list, ttype=3, z=15, minh=18, textcolor="#ffffff80",
        onchange=function(val)
            data.progress=val
            save_parameter(n.path, data)
        end,
        },{fillh=true})
        slider_length_audio:hide()
        
        
        local right_sect_cont = def_vb:add(rtk.Container{x=-2, margin=2,},{fillw=true, fillh=true})
        local in_box_spacer = create_spacer(right_sect_cont, PAD_COL, PAD_COL, 16) in_box_spacer:attr('ref', 'bg_in')
        
        local right_section = right_sect_cont:add(rtk.VBox{padding=4,})
        local HD_name = right_section:add(rtk.Heading{autofocus=-1, spacing=-5, fontflags=rtk.font.BOLD, fontsize=21,halign='center' , h=0.45, wrap=true, text=n.filename})
        local HD_date = right_section:add(rtk.Heading{autofocus=-1, tborder='2px white#10', fontsize=20, w=1, wrap=true, text=n.form_date:gsub(", %d%d:%d%d", "")})
        
        --raiting  
        local icon_raiting_proj = right_section:add(rtk.Button{cursor=rtk.mouse.cursors.HAND,color='red',z=8, elevation=0,alpha=0.9, circular=true, lpadding=6, flat=true,icon=rait_icons.angry, w=40, h=32}) 
        
        local rait_hbox = rtk.Container{}
        local pop_up_raiting = rtk.Popup{w=50, y=100, margin=-2, shadow="transparent", bg="transparent", border="transparent", padding=1, child=rait_hbox, --[[anchor=icon_raiting_proj]]}
        local rait_cont, rait_heading, rait_vp, VP_1 = create_container({halign='right', w=1, h=150}, rait_hbox, " ") rait_vp:attr('x', 2)
        recolor(rait_cont.refs.BG, def_padcol, "#5a5a5a80")
        
        local heading=rait_cont.refs.VBOX.refs.HEAD rait_cont.refs.VBOX:remove(heading)
         
        ---------
        slider_length_audio.onclick = function(self, event)
            if event.button == cbm then
                local ret, col = reaper.GR_SelectColor(wnd.hwnd, rtk.color.int(data.padcolor, true))
                if ret then 
                    local col_hex = rtk.color.int2hex(col, true)
                    data.padcolor = col_hex == "#000000" and def_pad_color or col_hex
                    slider_length_audio:attr('color', data.padcolor)
                    recolor(in_box_spacer, shift_color(col_hex, 1.0, 0.35, 0.7))
                    recolor(bg_roundrect, col_hex)
                    save_parameter(n.path, data)
                    
                end
            end
            return true
        end
        
        
        n.form_date_1 = n.form_date:gsub(" %d+, %d+:%d+", "")
        n.form_date_2 = n.form_date:gsub(", %d%d:%d%d", "")
        n.hbox = hbox_projects
        n.cont = container_hbox
        n.sel = 0

        local new_cont = container_hbox:add(rtk.Container{hotzone=2, z=5},{fillw=true,fillh=true})
        
        new_cont.onmousedown = function(self, event)
            local lbm = event.button == lbm
            local rbm = event.button == rbm
            local ctrl = event.ctrl
            local nsel = n.sel == 0
        
            if lbm then
                if nsel then
                    update_player(n)
                end
                if ctrl then
                    local color = n.sel == 1 and BG_COL or SELECTED_COL
                    recolor(bg_roundrect, color, color)
                    n.sel = 1 - n.sel
                elseif not event.shift then
                    unselect_all_path(BG_COL)
                    recolor(bg_roundrect, SELECTED_COL, hex_darker(SELECTED_COL, 0.2))
                    n.sel = 1
                end
            elseif rbm then
                
                --popup_by_path:attr('shadow', SELECTED_COL.."1")
                --popup_by_path:attr('alpha', 0.94)
                if n.sel == 0 and not ctrl then
                    unselect_all_path()
                end
                recolor(bg_roundrect, SELECTED_COL, smooth)
                n.sel = 1
                native_menu(n)
            end
        end
        
        VP_1:scrollto(0, 0, false)
        icon_raiting_proj:attr('icon', rait_icons[icons_row1[raiting]])
        icon_raiting_proj.onclick=function(self, event)
            pop_up_raiting:open{}
            VP_1:scrollto(0, 0, false)
            pop_up_raiting:attr('x', (self.clientx/rtk.scale.value)-12 )
            pop_up_raiting:attr('y', (self.clienty/rtk.scale.value)-60)
            
            
            pop_up_raiting.child.SELF = icon_raiting_proj
            
            --raiting
            local Y = ( 40/rtk.scale.value + (raiting - 1) * 40 - 33/rtk.scale.value ) 
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
            recolor(bg_roundrect, SELECTED_COL, hex_darker(SELECTED_COL, 0.2))
        end
        
        -------

        new_cont.onmouseenter=function(self,event)
            if n.sel == 0 then
                recolor(bg_roundrect, HOVER_COL, hex_darker(HOVER_COL, 0.2))
            end
            
            return true
        end
        new_cont.onmouseleave=function(self,event)
            if n.sel == 0 then
                recolor(bg_roundrect, odd_col_bg, odd_col_bg)
            end
            
        end
        local function update_hover()
            local val_touchscroll = get_modifier_value(KEY_FOR_TOUCHSCROLL)
            mouse_state = reaper.JS_Mouse_GetState(val_touchscroll)  
            rtk.touchscroll = (mouse_state == val_touchscroll) -- true or false
            isRunning = false
            
            if n.sel == 1 and slider_length_audio.visible == false then
                slider_length_audio:show()
            elseif n.sel ~= 1 and slider_length_audio.visible == true then 
                slider_length_audio:hide()
            end
            
            rtk.defer(update_hover)
        end
        
        rtk.defer(update_hover)
    end
end



function create_list()
    HEADING_types_hbox:show()
    list_vbox_group:remove_all()
    container_heading:remove(HEADING_types_hbox)
    vp_main_list:attr('child', list_vbox_group)
    container_heading:add(HEADING_types_hbox)
    HEADING_types_hbox:remove_all()
    --HEADING--
    HEADING_types_hbox:add(rtk.Button{x=5,ref="info", surface=false, minw=52*rtk.scale.value, icon=ic.info, halign='center',fontflags=rtk.font.BOLD,halign='center' },{ halign='center', fillh=true})
    HEADING_types_hbox:add(rtk.Button{w=0.4, ref="fnames", surface=false, minw=nil, label="FILE NAME", icon=ic.filename,fontflags=rtk.font.BOLD},{fillh=true})
    local date_cont_Test=HEADING_types_hbox:add(rtk.Container{lmargin=4, halign='right'})
    date_cont_Test:add(rtk.Button{ref="dates", surface=false, minw=32*rtk.scale.value, maxw=104*rtk.scale.value, label="DATE", icon=ic.time, halign="center",fontflags=rtk.font.BOLD},{halign="center", fillh=true, fillw=true})
    HEADING_types_hbox:add(rtk.Button{lmargin=20, ref="paths", surface=false, minw=nil, label="PATH", icon=ic.folder,fontflags=rtk.font.BOLD},{fillh=true, fillw=true})
    HEADING_types_hbox:add(rtk.Button{ref="sizes", surface=false, minw=62*rtk.scale.value, label="SIZE", icon=ic.mem, halign="right",fontflags=rtk.font.BOLD},{halign="right", fillh=true})
    
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
        local heigh_elems = MAIN_PARAMS.heigh_elems
        local odd_col_bg = i % 2 == 0 and '#3a3a3a' or '#323232'
        
        local container_hbox = list_vbox_group:add(rtk.Container{h=heigh_elems,},{fillw=true})
        local bg_roundrect = create_spacer(container_hbox, odd_col_bg, odd_col_bg, round_rect_list) bg_roundrect:attr('ref', 'bg_spacer')
        local short_path = shorten_path(n.dir, sep)
        local hbox_projects = container_hbox:add(rtk.HBox{ref="HBOX_P", padding=-2,thotzone=3,bhotzone=3,margin=2,spacing=2},{fillh=true,fillw=true})
        
        
        --container and pad\text in pad--
        local container_sq = hbox_projects:add(rtk.Container{lmargin=8,tpadding=4,margin=2,z=-2, w=32},{fillh=true,valign='center',halign='center'})
        local pad_status = create_spacer(container_sq, padcolor, padcolor, round_rect_list, false, progress_val):attr('scroll_on_drag', false) pad_status:attr('hotzone', 5)
        
        local b_name = hbox_projects:add(rtk.Text{w=0.4, ref='text_name', lmargin=1,fontflags=rtk.font.BOLD, valign='center', n.filename},{fillh=true})
        
        local date_cont_Test=hbox_projects:add(rtk.Container{halign='right'})
        local b_date = date_cont_Test:add(rtk.Text{
            ref='date', maxw=HEADING_types_hbox.refs.dates.calc.maxw,
            minw=HEADING_types_hbox.refs.dates.calc.minw ,valign='center',
            halign='center',n.form_date},{fillh=true, fillw=true,halign='center'})
        
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
            local lbm = event.button == lbm
            if lbm then
                reaper.CF_LocateInExplorer(self.ref)
            end
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
                if padcolor ~= def_pad_color then
                    --popup_by_path:attr('shadow', padcolor..2)
                else
                    --popup_by_path:attr('shadow', "#1a1a1a20")
                end
                popup_by_path:attr('alpha', 0.98)
                if n.sel == 0 then
                    unselect_all_path()
                end
                recolor(bg_roundrect, "#9a9a9a", smooth)
                n.sel = 1
                
                --popup_by_path:open{}
                native_menu(n)
                --popup_by_path:open{}
                
            end
            
            --get_selected_path()
        end
        hbox_projects.ondoubleclick=function(self, event)
            local lbm = event.button == lbm
                if lbm then
                local paths = get_selected_path()
                for i, path in ipairs(paths) do
                    if i == #paths then
                        reaper.Main_openProject(path)
                    end
                end
            end
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
            if event.button == cbm then
                local ret, col = reaper.GR_SelectColor(wnd.hwnd, rtk.color.int(data.padcolor, true))
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
        
        pad_status:ondragmousemove()
        
        pad_status.ondoubleclick = function(self, event)
            local lbm = event.button == lbm
            if lbm then
                progress_val=0
                recolor(self, padcolor, padcolor, progress_val)
                --[[
                
                data.dl = "2024.04.29 18:00:00"
                data.raiting = 4
                data.comment = "last version"
                data.tags = {"#OLDEST", "#TEST", "#WARIOUS"}
                p-rint(n.path, data.dl, data.raiting, data.comment, table.concat(data.tags) )
                ]]
                save_parameter(n.path, data)
            end
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
    
    if TYPE_module ~= 1 then
        new_paths[sorted_paths[1]].hbox.refs.date.onreflow = function(self, event)
            update_window(wnd, wnd.w, wnd.h)
        end
    end
    entry_find:onchange()
end




collection_all = {
name="3",
sec_name="Грустный",
img="1.png",
list={
"F:\\Projects Reaper\\Тима Проекты\\Ливнем от дождя\\Ливнем от дождя.RPP",
"F:\\Projects Reaper\\Тима Проекты\\Мелодия\\Мелодия.rpp",
"F:\\Projects Reaper\\Тима Проекты\\Оставлю на врем я\\Оставлю на врем я.rpp",
"F:\\Projects Reaper\\Тима Проекты\\Оставлю на врем я\\Штаны вкусные.rpp",
"F:\\Projects Reaper\\Тима Проекты\\Оставлю на врем я\\Любовь по памяти.rpp",
"F:\\Projects Reaper\\Тима Проекты\\Оставлю на врем я\\Ширинка.rpp",},

tags={},
comment="",
raiting=3,
bgcol="#7a7a7a",
}
--save_parameter("Тридэ",collection_all, workspace_file)
--get_all_names(collections_file)


function initialize_data(name, file)
    local data
    local uuid
    if name ~= nil and file ~= nil then
        data = get_parameter(name, file)
    end

    if data == nil then
        data = {
            name = "Empty Name",
            sec_name = "Empty Name",
            bgcol = "#7a7a7a",
            rating = 0,
            comment = "",
            img = "",
            list = {},
            tags = {},
        }
        uuid = rtk.uuid4()
    end

    return data, uuid
end

function move_button(src_button, target, box)
    local src_idx = box:get_child_index(src_button)
    local target_idx = box:get_child_index(target)
    if src_button ~= target and src_idx > target_idx then
        box:reorder_before(src_button, target)
    elseif src_button ~= target then
        box:reorder_after(src_button, target)
    end
end

function update_data_list(DATA, children)
    DATA.list = {}
    for i, hbox in ipairs(children) do
        local hbox=hbox[1]
        table.insert(DATA.list, hbox.inf)
    end
end

function contains(table, element)
    for _, value in ipairs(table) do
        if value == element then
            return true
        end
    end
    return false
end 

function replace_tab(tab, old_name, new_name)
    for i, value in ipairs(tab) do
        if value == old_name then
            tab[i] = new_name
            return true
        end
    end
    return false
end

function get_file_state(path)
    local ret, 
          _, 
          _,
          _, 
          _, 
          _, 
          _, 
          _, 
          _, 
          _, 
          _, 
          _ 
          = reaper.JS_File_Stat(path)
          return ret
end

function update_state(state, condition, vbox_list)
    for i, elems in ipairs(vbox_list) do
        local hbox = elems[1]
        for j, elms in ipairs(hbox.children) do
            if j == 2 then
                local button = elms[1]
                if condition(button) then
                    button:attr('state', state)
                end
            end
        end
    end
end
        
function browse_rpp_files(title)
    local title = title or 'Select new project file'
    local ext_list = "RPP files (*.rpp;*.RPP)\0*.rpp;*.RPP\0RTrackTemplate files (*.RTrackTemplate)\0*.RTrackTemplate\0\0"
    local ret, path = reaper.JS_Dialog_BrowseForOpenFiles(
                      title , 
                      "", 
                      projects, 
                      ext_list, 
                      false)
    return ret, path
end

local menu_group_elems = rtk.NativeMenu()
 
menu_group_elems:set({
    {'Open path', id='path'},
    {'Show folder', id='show_folder'},
    {'Open project', id='open', submenu={
        {'Open project', id='open_project'},
        {'New tab', id='new_tab'},
        {'Recovery', id='recovery'},
    }},
    rtk.NativeMenu.SEPARATOR,
    {'Move to' , id='move_to', submenu={
        rtk.NativeMenu.SEPARATOR,--{'Open project', id='open_project'},
        rtk.NativeMenu.SEPARATOR,--{'New tab', id='new_tab'},
        rtk.NativeMenu.SEPARATOR,--{'Recovery', id='recovery'},
    }},
    {'Show statistic (Does not work)' , id='stat'},
    {'Remove' , id='remove'},
})

function show_list_group(vbox_list, DATA, hbox_buttons, group, parent)
    vbox_list:remove_all()
    local col = "#9a9a9a"
    local dragging = nil
    local str_list = DATA.list
    local not_founded = 0
    hbox_buttons:remove_all()
    --
    
    
    
    hbox_buttons:add(RoundButton{ref='add', round=8, halign='center', h=1, toggle=false, color='#9a9a9a', 'ADD PATH'},{fillw=true})
    hbox_buttons:add(RoundButton{z=2, rmargin=-6, lmargin=-6, round=0, halign='center', h=1, toggle=false, color='#9a9a9a', 'COPY'},{fillw=true})
    hbox_buttons:add(RoundButton{disabled=true, z=2, rmargin=-6, lmargin=-6, round=0, halign='center', h=1, toggle=false, color='#9a9a9a', 'PAST'},{fillw=true})
    hbox_buttons:add(RoundButton{round=8, halign='center', h=1, toggle=false, color='#9a9a9a', 'REMOVE ALL'},{fillw=true})
    
    hbox_buttons.refs.add.onclick = function(self, event)
        local ret, dir = reaper.JS_Dialog_BrowseForFolder("Select a folder to scan the rpp", "")
        if ret then
            local paths = check_rpp_files(dir)
            for _, path in ipairs(paths) do
                if not contains(str_list, path) then
                    table.insert(str_list, path)
                end
            end
            save_parameter(group, DATA, workspace_file)
            show_list_group(vbox_list, DATA, hbox_buttons, group, parent)
        end
    end
    
    
    for i, projects in ipairs(str_list) do
        if i == #str_list then vbox_list:focus() end
        local filename, path = extract_name(projects)
        local title
        
        local hbox = vbox_list:add(
            rtk.HBox{
                spacing=4,
                ref='hb',
                inf = projects,
                h=23,
                --padding=2,
                z=10,
                w=1,
                }
        )
        
        local shadow_cont_dnd =  vbox_list.refs.hb:add(rtk.Container{w=30, h=1})
        local drag_n_drop_b = shadow_cont_dnd:add(
            RoundButton{
                ref='edit',
                round=8,
                halign='center', 
                color = 'transparent',
                w=30,
                h=1,
                cursor = rtk.mouse.cursors.SIZE_NS,
                toggle=false,
                fontsize=26,
                text="☰"
                } )
                
        local btn_name = vbox_list.refs.hb:add(
            RoundButton{
                ref='b',
                round=8,
                color=col, 
                halign='left', 
                z=5,
                h=1,
                autohover=false, 
                toggle=true,
                text= filename,
                }, { fillw=true} )
                
        local edit_b = vbox_list.refs.hb:add(
            RoundButton{
                ref='edit',
                round=8,
                color=col, 
                halign='center', 
                w=25,
                h=1,
                toggle=false,
                fontsize=27,
                text="✎"
                } )
                
        local delete_b = vbox_list.refs.hb:add(
            RoundButton{
                ref='delete',
                round=8,
                color='#ba1515', 
                halign='center', 
                w=25,
                h=1,
                toggle=false,
                fontsize=19,
                text="✖"
                } )
        
        local x
        
        drag_n_drop_b.ondragstart = function(self, event)
            if LBM(event) and #str_list > 1 then
                btn_name:attr('toggle', false)
                btn_name:attr('color', 'red')
                btn_name:attr('disabled', true)
                btn_name:blur()
                hbox:attr('border','orange#20')
                edit_b:hide()
                delete_b:hide()
                
                self:attr('color', 'crimson')
                self:attr('rmargin', 30)
                dragging = hbox
                
                self.mousex, self.mousey = reaper.GetMousePosition()
                self.new_x = math.round(hbox.calc.w/2.1)
                
                reaper.JS_Mouse_SetPosition(self.mousex+self.new_x, self.mousey)
            end
            return true
        end
        
        drag_n_drop_b.ondragend = function(self, event)
            btn_name:attr('color', col)
            btn_name:attr('toggle', true)
            
            
            btn_name:attr('disabled', false)
            self:attr('color', 'transparent')
            hbox:attr('border', false)
            self:attr('rmargin', 0)
            edit_b:show()
            delete_b:show()
            dragging = nil
            update_data_list(DATA, vbox_list.children)
            save_parameter(group, DATA, workspace_file)
            
            _, self.mousey = reaper.GetMousePosition()
            reaper.JS_Mouse_SetPosition(self.mousex, self.mousey)
            return true
        end
        
        edit_b.onclick = function(self, event)
            local ret, path = browse_rpp_files(title)
            if ret == 1 then
                replace_tab(DATA.list, projects, path)
                save_parameter(group, DATA, workspace_file)
                show_list_group(vbox_list, DATA, hbox_buttons, group, parent)
            end
            
        end
        
        vbox_list.refs.hb.refs.delete.onclick = function(self, event)
            vbox_list:remove_index(i)
             
            update_data_list(DATA, vbox_list.children)
            save_parameter(group, DATA, workspace_file)
            show_list_group(vbox_list, DATA, hbox_buttons, group, parent)
            for i, n in ipairs(parent.children) do
                local b = n[1]
                if b.ref == 'b' then
                    b:attr('text', #str_list .. " projects")
                end
            end
        end
        
        drag_n_drop_b.ondropfocus = function(self, event, _, src_button)
            return true
        end
        
        drag_n_drop_b.ondropmousemove = function(self, event, _, src_button)
            if dragging ~= nil then
                move_button(dragging , hbox , vbox_list)
                
            end
            return true
        end
        
        local vbox_children = vbox_list.children

        btn_name.onmousedown = function(self, event)
            local shift = event.shift
            local alt = event.alt
            local ctrl = event.ctrl
            if LBM(event) then
                self:attr('state', self.state == 'off' and 'on' or 'off')
                if shift then
                    local idx_current
                    local last_idx = 1
                    for i, elems in ipairs(vbox_list.children) do
                        local hbox = elems[1]
                        for j, elms in ipairs(hbox.children) do
                            if j == 2 then
                                local button = elms[1]
                                if button == self then
                                    idx_current = i
                                end
                                if button.state == 'on' and button ~= self then
                                    last_idx = i
                                end
                                button:attr('state', 'off')
                            end
                        end
                    end
                    local start_idx = math.min(idx_current, last_idx)
                    local end_idx = math.max(idx_current, last_idx)
                    for i = start_idx, end_idx do
                        local hbox = vbox_list.children[i][1]
                        hbox.children[2][1]:attr('state', 'on')
                    end
                elseif alt then
                    update_state('off', function(button) return true end, vbox_children)
                end
            end
            if ctrl or RBM(event) then
                update_state('off', function(button) return true end, vbox_children)
                self:attr('state', 'on')
            end
            return true
        end
        
        vbox_list.onkeypress=function(self,event)
            if event.ctrl and event.char == 'a' then
                update_state('on', function(button) return true end, vbox_children)
            end
            return true
        end
        
        btn_name.ondropfocus = drag_n_drop_b.ondropfocus
        
        btn_name.ondropmousemove = drag_n_drop_b.ondropmousemove
        
        if get_file_state(projects) == -1 then
            title = "Replace project file"
            btn_name:attr('toggle',false)
            btn_name:attr('text',btn_name.text.." (NOT FOUND)")
            hbox:attr('bg','red#20')
            edit_b:attr('color', '#00b200')
            not_founded = not_founded + 1

            for i, n in ipairs(parent.children) do
                local b = n[1]
                
                --parent:add(new_b)
                
                if b.ref == 'not_found' then
                   b:show()
                   b:attr('text', not_founded .. " not found")

                end
            end
            
        end
        
        for i, n in ipairs(parent.children) do
            local b = n[1]
            if b.ref == 'b' then
                b:attr('text', #str_list .. " projects")
            end
        end
        
        drag_n_drop_b.onclick=function(self,event)
            if RBM(event) then
                menu_group_elems:open_at_widget(shadow_cont_dnd, "left", "bottom"):done(function(item) 
                    if not item then return end
                    if item.id == 'path' then
                        reaper.CF_LocateInExplorer(projects)
                    elseif item.id == 'show_folder' then
                        reaper.CF_LocateInExplorer(path)
                    elseif item.id == 'open_project' then
                        reaper.Main_openProject(projects)
                    elseif item.id == 'new_tab' then
                        NEW_project_tab:onclick()
                        reaper.Main_openProject(projects)
                    elseif item.id == 'recovery' then
                        NEW_project_tab:onclick()
                        open_project_recovery(projects)
                    end
                end)
            end
        end
    end
    
    local vbox_children = vbox_list.children
    
    vbox_list.refs.hb.onreflow=function(self,event)
        for i, elems in ipairs(vbox_children) do
            local hbox = elems[1]
            if self.calc.w <= 330 and self.calc.w >= wnd.minw/2 then
                local norm_value = norm(self.calc.w, wnd.minw/2, 330)
                local val = lerp(0, 5, norm_value)
                hbox:attr('spacing', val)
            end
        end
    end
end

function create_group_container(vbox, data, height, color_shift)
    local COL = data.bgcol
    local NEW_COL = shift_color(COL, 1.0, color_shift, color_shift)
    
    local cont_collections = vbox:add(rtk.Container{ref='cont', h=height},{fillw=true})
    local first_bg_spacer = create_spacer(cont_collections, NEW_COL, NEW_COL, round_rect_window)
    first_bg_spacer:attr('ref', 'first_bg_spacer')
    
    return cont_collections, NEW_COL
end

function create_group_editor()
    local entry_tag, cont_tag = rtk_Entry(cont_hbox, "#3a3a3a", "#3a3a3a", 12, "Set name for group")
    entry_tag:attr('value', DATA.name)
    entry_tag:attr('font', 'Verdena')
end

function remove_elems(tab)
    local new_tab = {}
    local missed = 0
    for i = #tab, 1, -1 do
        if get_file_state(tab[i]) == -1 then
            table.remove(tab, i)
            missed = missed + 1
        else
            table.insert(new_tab, tab[i])
        end
    end
    return new_tab, missed
end


group_vp_vbox:attr('margin', 5)
group_vp_vbox:attr('padding', 5)

function create_group_leftsection(gr, DATA, data_list)
    local vbox = gr
    local new_tab = {}
    
    for i, n in ipairs(data_list) do
        table.insert(new_tab, n)
    end
    
    local clean_paths, missed_paths = remove_elems(new_tab)
    table.insert(ALL_PROJECTS_INIT, clean_paths)
    
    vbox:add(RoundButton{ref='_group', round=2, color=DATA.bgcol, halign='center',w=1, h=25, toggle=false, text=DATA.name})
    vbox.refs._group.onclick = function(self, event)
        if LBM(event) then
            if #clean_paths > 0 then
                new_paths, all_paths_list = get_all_paths(clean_paths)
                sorted_paths              = sort_paths(new_paths, all_paths_list, MAIN_PARAMS.sort, MAIN_PARAMS.sort_dir)
                main_run()
            end
            
        end
    end
    if #new_tab == 0 then
        vbox.refs._group:attr('disabled', true)
    end
    
    return missed_paths
end

function show_input_window()

end


function create_group_block(vbox, vbox_list, DATA, all_tabs, group, i, hbox_buttons)
    local cont_collections = create_group_container(vbox, DATA, 80, 0.8)
    local vbox_grp = cont_collections:add(rtk.VBox{spacing=def_spacing, h=1, padding=5})
    local cont_hbox = vbox_grp:add(rtk.Container{w=1})
    cont_hbox:add(RoundButton{disabled=true, ref='b', round=16, text="",color='#5a5a5a', halign='center', y=-1, h=40, w=1, toggle=false})
    cont_hbox:add(rtk.Heading{padding=4, w=1, h=cont_hbox.refs.b.calc.h, wrap=true, fontflags=rtk.font.BOLD, fontsize=18, valign='center', halign='center', font='Verdena', text=DATA.name})
    vbox_grp:add(rtk.HBox{
        ref='hbox',
        RoundButton{autohover=false, ref='b', round=8, color='#6a6a6a', halign='center', y=-1, w=80, disabled=true, h=25, toggle=false, text=#DATA.list.. " projects"},
        RoundButton{autohover=false, x=2,ref='not_found', round=8, color='#952222', halign='center', y=-1, w=80, disabled=true, h=25, toggle=false, text=" "},
        --RoundButton{x=4, ref='scan', round=8, color='purple', halign='left', w=0.64,y=-1, disabled=false, h=25, toggle=true, text="Auto-scan"},
        rtk.Box.FLEXSPACE,
        RoundButton{ref='edit', round=8, color='#6a6a6a', halign='center', y=-1, w=35, x=-2, h=25, toggle=false, fontsize=27, text="✎"},
        RoundButton{ref='delete', round=8, color='#ba1515', halign='center', y=-1, w=35, h=25, toggle=false, fontsize=19, text="✖"}
    })
    
    local missed_paths = create_group_leftsection(group_vp_vbox, DATA, DATA.list)
    vbox_grp.refs.not_found:hide()
    if missed_paths > 0 then
        
        vbox_grp.refs.not_found:show()
        vbox_grp.refs.not_found:attr('text', missed_paths.." not found")
    end
    
    cont_collections.onmouseenter = function(self, event) recolor(cont_collections.refs.first_bg_spacer, active_col) return true end
    cont_collections.onmouseleave = function(self, event) recolor(cont_collections.refs.first_bg_spacer, shift_color(DATA.bgcol, 1.0, 0.7, 0.8)) end
    cont_collections.onmousedown = function(self, event)
        if LBM(event) then
            for _, tab in ipairs(all_tabs) do 
                tab.refs.b:attr('color', shift_color(DATA.bgcol, 1.0, 0.7, 0.8)) 
            end
            cont_hbox.refs.b:attr('color', active_col)
            show_list_group(vbox_list, DATA, hbox_buttons, group, vbox_grp.refs.hbox)
            --show_input_window()
        end
        return true
    end
    vbox_grp.refs.delete.onclick=function(self,event)
        delete_array(group, workspace_file)
        local idx = vbox:get_child_index(cont_collections)
        vbox:remove_index(idx)
    end
    table.insert(all_tabs, cont_hbox)
end

function create_workspace(vbox, vbox_list, hbox_buttons, bottom_section_group)
    vbox:remove_all()

    local button_add = vbox:add( rtk.Button{w=1, h=45, "ADD"} )
    
    button_add.onclick=function()
        local key = rtk.uuid4() 
        local DATA_temp, key = initialize_data(nil, nil)
        
        save_parameter_sort(key, DATA_temp, workspace_file)
        create_workspace(vbox, vbox_list, hbox_buttons, bottom_section_group)
    end
    
    local all_tabs = {}
    --local names = get_all_names2(workspace_file)
    local names = get_all_names(workspace_file)
    for i, group in ipairs(names) do
        local DATA = initialize_data(group, workspace_file)
        local cont_hbox = create_group_block(vbox, vbox_list, DATA, all_tabs, group, i, hbox_buttons)
        
    end
    
    local vb = bottom_section_group:add(rtk.VBox{},{expand=1, stretch = 2})
    vb:add(rtk.CheckBox{w=0.4, 'Auto Scaning Folder'},{})
    vb:add(rtk.Entry{w=0.5, 'Add path to scan'},{expand = 1, stretch = 2})
    vb:add(rtk.Entry{w=0.5, 'Set Name group'},{expand=1, stretch =1})
    
end
 

function create_collection(vbox, vbox_list)
    vbox:remove_all()
    --Get all names in saved collections
    local all_names = get_all_names(collections_file)
    
    
    
    for i, blan in ipairs(all_names) do
        --import data info for collection
        local DATA = initialize_data(group, workspace_file)
        
        local COL = DATA.bgcol
        local NEW_COL = shift_color(COL, 1.0, 0.7, 0.7)
        
        local image, name, second_name, tags = DATA.img, DATA.name, DATA.sec_name, DATA.tags
        --create bg roundrect
        local cont_collections, NEW_COL = create_group_container(vbox, DATA, 130, 0.7);local fbg_spacer = cont_collections.refs.first_bg_spacer
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
        local edit = hbox_second_name:add(rtk.Button{alpha=0.5, flat=true, icon=ic.draw, padding=2})
        
        local icon_raiting_proj = main_vbox_right:add(rtk.Button{cursor=rtk.mouse.cursors.HAND,color='red',z=8, elevation=0,alpha=0.5, circular=true, lpadding=6, flat=true,icon=rait_icons.angry, w=40, h=32}) 
        
        edit.onclick=function(self, event)
            local ret, col = reaper.GR_SelectColor(wnd.hwnd, rtk.color.int(COL, true))
            if ret then 
                if col == 0 then return end
                local col_hex = rtk.color.int2hex(col, true)
                DATA.bgcol = col_hex
                COL = DATA.bgcol
                NEW_COL = shift_color(COL, 1.0, 0.7, 0.7)
                
                recolor(fbg_spacer, COL)
                recolor(info_bg_spacer, NEW_COL)
                
                save_parameter(DATA.name, DATA, collections_file)
            end
            
        end
        
        main_vbox_right:add(rtk.Box.FLEXSPACE)
        --hbox tags secton (maybe viewport)
        local hbox_tags = main_vbox_right:add(rtk.HBox{bmargin=-24,spacing=2, valign='bottom', halign='center'},{valign='bottom', halign='center'})
        
        --[[local entry_tag, cont_tag = rtk_Entry(hbox_tags, "#3a3a3a", "#3a3a3a", 5, "#tag") cont_tag:resize(1, 27) entry_tag:resize(1, 27)
        --entry_tag:attr('value', DATA.comment)
        
        cont_tag.onkeypress=function(self, event)
            if event.keycode == rtk.keycodes.ENTER and entry_tag.focused  then
                DATA.comment=entry_tag.value
                entry_tag:blur()
                save_parameter(DATA.name, DATA, collections_file)
            end
            return true
        endg
        ]]
        cont_collections.onclick=function(self, event)
            show_list_group(vbox_list, DATA.list)
            
        end
    end
end



--local open_group_editor = group_heading:add(RoundButton{halign='center', y=-1, h=26, w=36, toggle=false, color='#4a4a4a', lmargin=16,"←",tmargin=-7},{valign='center',  halign='left'})
--local open_group_editor = group_heading:add(RoundButton{halign='center', y=-1, h=26, w=36, toggle=false, color='#9a9a9a', fontsize=35, rmargin=16,"⛮",tmargin=-7},{valign='center',  halign='right'})
local HB_GR_BUTTON_SECT = group_heading:add(rtk.HBox{ x=4, spacing=def_spacing, padding=3,},{})
local VB_GR_B_MN = HB_GR_BUTTON_SECT:add(rtk.VBox{spacing=2, x=2,},{})

VB_GR_B_MN:add(RoundButton{halign='center', fontsize=11, round=1, w=25, h=11, toggle=false, color="#5a5a5a", "↑"},{ })
VB_GR_B_MN:add(RoundButton{halign='center', fontsize=11, round=1, w=25,h=11, toggle=false, color="#5a5a5a", "↓"},{})
HB_GR_BUTTON_SECT:add(RoundButton{halign='center', h=25, toggle=false, color="#4a4a4a", "GROUPS"},{fillw=true, expand=3, halign='right', })
local open_group_editor = create_b(HB_GR_BUTTON_SECT, "param_group", 34, 25, true, ic.settings:scale(120,120,22,6.2):recolor("white"), false ) settings_app.click=1


--reorder_box(HB_GR_BUTTON_SECT, open_group_editor, {expand=1, fillw=true})



local group_editor = rtk.Container{w=1,h=1}
local pop_up_editor = rtk.Popup{margin=6, autoclose=false, border='transparent', padding=2, bg='transparent', child=group_editor}
local cont_group, hb_heading_group, vp_group = create_container({halign='right', w=1, h=1}, group_editor, "GROUP EDITOR") vp_group:attr('x', 2)



local hbox_head_grp=hb_heading_group:add(rtk.HBox{w=1})

back_from_grp=create_b(hbox_head_grp, '←   back', 70, 27, nil, nil, false) back_from_grp:move(4,3) 

local main_vbox_COLLECTIONS = vp_group:add(rtk.VBox{spacing=def_spacing, border='aqua', w=1, h=90})

--HBOX AND BUTTONS TAB COLLECTIONS\WORKSPACE\ARCHIVE
local tab_group_hbox = main_vbox_COLLECTIONS:add(rtk.HBox{spacing=def_spacing})
local button_create_collect = tab_group_hbox:add(rtk.Button{halign='center', 'Collection'},{fillw=true})
local button_create_workspace = tab_group_hbox:add(rtk.Button{disabled=true, halign='center', 'Workspace'},{fillw=true})
local button_create_unused = tab_group_hbox:add(rtk.Button{disabled=true, halign='center', 'Archive'},{fillw=true})

--HBOX BUTTONS CREATE MODUL
local ORGANIZE_BUTTONS_HB = main_vbox_COLLECTIONS:add(rtk.HBox{spacing=def_spacing},{ valign='bottom', fillh=true, fillw=true})
ORGANIZE_BUTTONS_HB:add(RoundButton{round=6, halign='center', y=-1, h=26, w=120, toggle=false, color='#9a9a9a', 'Create',})
ORGANIZE_BUTTONS_HB:add(RoundButton{round=6, halign='center', y=-1, h=26, w=120, toggle=false, color='#9a9a9a', 'Remove'})
--RIGHT AND LEFT SECTIONS
local collections_main = vp_group:add(rtk.HBox{spacing=def_spacing})
local COLLECTIONS_VB=collections_main:add(rtk.VBox{h=0.64, w=0.5, },{fillh=true, })




local vb_right_sect_grp = collections_main:add(rtk.Container{},{})
local list_cont_gr, hb_head_gr_list, vp_gr_list, viewport_group_l = create_container({halign='center', w=1, h=0.64}, vb_right_sect_grp)
          hb_head_gr_list:attr('h', 50)
          viewport_group_l:attr('y', -2)
          vp_gr_list:attr('z', 10)
          vp_gr_list:attr('tmargin', -10)
          hb_head_gr_list.refs.HIDE:attr('bg', "#3a3a3a")
          recolor(list_cont_gr.refs.BG, "#3a3a3a")
          
hb_head_gr_list:add(rtk.HBox{h=0.64, padding=3, ref='hb'},{fillh=true, fillw=true})
--viewport_group_l:attr('border','red')

--local COLL_LIST_VB = rtk.VBox{padding=6, spacing=2, w=1}

--local VB_COLL_LIST = vb_right_sect_grp:add( rtk.Viewport{scrollbar_size=8, border='red', h=0.64, w=1, child = COLL_LIST_VB} )
--MAIN VBOX LIST PROJECTS
--local COLLECTIONS_VB_child=rtk.FlowBox{hspacing=def_spacing, vspacing=def_spacing, w=1}

local vb_left_sect_grp = COLLECTIONS_VB:add(rtk.Container{},{})
local list_cont_gr_right, hb_head_gr_right, vp_grlist_right, viewport_group_2 = create_container({halign='center', w=1 }, vb_left_sect_grp)
          hb_head_gr_right:attr('h', 50)
          viewport_group_2:attr('y', -2)
          vp_grlist_right:attr('z', 10)
          vp_grlist_right:attr('tmargin', -10)
          vp_gr_list:attr('spacing', 4)
          hb_head_gr_right.refs.HIDE:attr('bg', "#3a3a3a")
          recolor(list_cont_gr_right.refs.BG, "#3a3a3a")
          --vp_grlist_right=rtk.FlowBox{hspacing=def_spacing, vspacing=def_spacing, w=1}
hb_head_gr_right:add(rtk.HBox{h=0.64, padding=3, ref='hb'},{fillh=true, fillw=true})
--local COLLECTIONS_VB_VIEWPORT=COLLECTIONS_VB:add(rtk.Viewport{child=COLLECTIONS_VB_child})


--[[
vb_right_sect_grp:add(
    RoundButton{
        ref='dnd',
        round=8,
        color='#9a9a9a', 
        halign='center', 
        y=-60,
        w=0.97,
        font = 'Arial',
        h=40,
        toggle=false,
        text="DROP PROJECTS HERE"
    },{halign='center'} )
]]

--EXTRACT ALL SAVED COLLECTIONS
--create_collection(COLLECTIONS_VB_child, COLL_LIST_VB)


--BOTTOM SECTION UNDER list
local bottom_section_group = vp_group:add(rtk.HBox{border='orange', rmargin=4, h=0.2,  w=1})

create_workspace(vp_grlist_right, vp_gr_list, hb_head_gr_list.refs.hb, bottom_section_group)

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
entry_find, cont = rtk_Entry(bottom_right_section, COL9, COL9, nil, "Find project") cont:resize(1, 30) entry_find:focus()


local comment_widgets_hbox = bottom_right_section:add(rtk.HBox{spacing=5, })

--DEAD LINE CONTAINER
local cont_bg_right_sect_1 = comment_widgets_hbox:add(rtk.Container{minw=70,w=0.3})
create_spacer(cont_bg_right_sect_1, COL1, COL3, round_rect_window)

    

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
        if RBM(event) then
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

    --local METER_volume = player_container:add(VolumeMeter{color=col_meter, ref='meter2', w=8, h=60},{--[[valign='center',]] })-- METER_volume:hide()
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
      
    --[[raiting  
    local icon_raiting_proj = file_info_HBox:add(rtk.Button{x=2, lpadding=8,y=4,flat=true,icon=rait_icons.angry, lmargin=6, w=45, h=45},{valign='top'}) icon_raiting_proj:hide()
    local rait_hbox = rtk.HBox{},{fillw=true}
    local pop_up_raiting = rtk.Popup{alpha=0.9, bg=COL3, border=COL5, padding=4, child=rait_hbox, anchor=icon_raiting_proj,width_from_anchor=false}
    ---------
    ]]
    local b_settings_list = file_info_HBox:add(rtk.Button{surface=false,icon=ic_list, w=45, h=45},{valign='top'})
    local audio_filename = file_info_HBox:add(rtk.Heading{wrap=true, fontsize=22, text=first_media},{fillw=true, valign='center'})
    
    
    local slider_value_vbox = vbox_player:add(rtk.VBox{z=10,tmargin=-5,maxh=20, lpadding=15,rpadding=15})
    
    local slider_length_audio = slider_value_vbox:add(SimpleSlider{color=col_shadow, showtext=false, disabled=true, hotzone=15, w=1,h=5, roundrad=round_rect_list, ttype=3, textcolor="transparent"},{valign='center'})
    
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
    local volume_slider = hbox_player:add(SimpleSlider{color=col_shadow, showtext=false, value=1,max=1.5,maxw=85,minw=30,hotzone=15,y=1, w=0.2,h=5, roundrad=2, ttype=3, textcolor="transparent",
    
    onchange=function(normval, val)
        reaper.CF_Preview_SetValue(preview, 'D_VOLUME', val)
    end
    },{valign='center'})
    
    --local METER_volume2 = vp_images2:add(VolumeMeter{color=col_meter, ref='meter', w=8}) wnd.onupdate = function() --[[main_hbox_player.refs.meter:set_from_track(preview)main_hbox_player.refs.meter2:set_from_track(preview) ]]end
    --METER_volume2:hide()
    
    
    draging = true
    text_end.tog = true
    
    local prev_position = nil
    local prev_time_text = nil
    
    local last_update_time = os.clock() -- Получаем текущее время
    
    local function upd()
        if cont_img.mouseover then
            spacer:show()
        else
            spacer:hide()
        end
        
        if preview and draging then
            time, want_pos, position, length = get_play_info(preview)
            
            
            if os.clock() - last_update_time > 1 and position ~= prev_position then
                slider_length_audio:attr('value', position)
                prev_position = position
                last_update_time = os.clock()
                reaper.CF_Preview_SetValue(preview, 'D_VOLUME', volume_slider.value)
            end
            
            local time_text = time:match("([^%.]*)")
            if time_text ~= prev_time_text then
                text_start:attr('text', time_text)
                prev_time_text = time_text
            end
            
            if text_end.tog then
                slider_length_audio:attr('max', length)
                text_end:attr('text', want_pos:match("([^%.]*)"))
                text_end.tog = false
            end
    
            for i = 0, 2 - 1 do
                local valid, peak = reaper.CF_Preview_GetPeak(preview, i)
            end
        end
        rtk.defer(upd)
    end
    
    -- Запуск функции обновления
    upd()
    
    
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
        local lbm = event.button == lbm
            if lbm then
            if GLOBAL_ANIMATE then
                self:animate{'value', dst = 1, duration = 0.3, easing = "out-cubic"}
            else
                self:attr{'value', 1}
            end
            reaper.CF_Preview_SetValue(preview, 'D_VOLUME', 1)
        end
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
    --[[
    icon_raiting_proj.onclick=function(self, event)
        pop_up_raiting:open()
        pop_up_raiting.child.SELF = icon_raiting_proj
    end
    
    
    icon_raiting_proj:attr('icon', rait_icons[icons_row1[raiting] )
    
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
    end]]

    rtk.defer(upd)
end

local cont_info_bar = main_vbox_list:add(rtk.Container{h=25, w=1},{})
local info_bar = create_spacer(cont_info_bar, COL1, COL3, round_rect_window)



function main_run()
    if TYPE_module == 1 then
        create_list()
    else
        create_block_list()
    end
    table.insert(ALL_PROJECTS_INIT, sorted_paths)
    
    if AUTO_CLEAN_INFO then
        clean_old_projects(ALL_PROJECTS_INIT, params_file)
    end
end

main_run()


function update_geometry(w, h)
    if w < 550 * rtk.scale.value then
        if cont_bg_right_sect_1.visible then
            cont_bg_right_sect_1:hide()
        end
    else
        if not cont_bg_right_sect_1.visible then
            cont_bg_right_sect_1:show()
        end
    end
    if main_vbox_window.calc.h < 600 * rtk.scale.value then
        IMG_container:hide()
    else
        IMG_container:show()
    end
end

wnd:open()

wnd.onresize = function(self, w, h) 
    update_geometry(w, h)
end

update_geometry(wnd.w)

wnd.onupdate=function()
end



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

