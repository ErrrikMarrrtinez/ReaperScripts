-- @description Track View Manager
-- @author mrtnz
-- @version 1.1
-- @about
--  Track View Manager
-- @provides
--   [main] .
--   [main] mrtnz_Track view - Save by slot number.lua
--   [main] mrtnz_Track view - Load by slot number.lua
--   rtk.lua
--   json.lua
--   functions.lua


local r = reaper ; function print(...) local t = {...} for i = 1, select('#', ...) do t[i] = tostring(t[i]) end r.ShowConsoleMsg(table.concat(t, '\t') .. '\n') end
r.gmem_attach('Viewer')


package.path = package.path .. ";" .. string.match(({r.get_action_context()})[2], "(.-)([^\\/]-%.?([^%.\\/]*))$") .. "?.lua"
local json = require "json"
require 'rtk'

local functions = require 'functions' for name, func in pairs(functions) do _G[name] = func end

local fills = {fillw=true, fillh=true}
local DAT = {}
local cells_menu = rtk.NativeMenu()
cells_menu:set({
    {'Create screenset', id='2'},
    {'Rename', id='rename'},    
    rtk.NativeMenu.SEPARATOR,
    {'Create action', id='1'},
})

local wnd = rtk.Window{opacity=0.975, minw=230, minh=250, border='#5a5a5a', borderless=true, title='Track View Manager', w=300, h=400, x=440}
local container = wnd:add(rtk.VBox{}, fills)

function Main()
    local DATA = {
        widgets = {
          b = {},
          e = {},
          x = {},
          h = {},
          c = {},
        }
    }
    
    local widgets = DATA.widgets
    
    container:remove_all()
    
    createHeader(container)
    
    local main_cont = container:add(rtk.Container{padding=12})
    local main_vbox = main_cont:add(rtk.VBox{spacing=5}, fills)
    local b_header = createHeaderTab(main_vbox)
    
    local viewport = main_vbox:add(rtk.Viewport{scrollbar_size=2, vscrollbar='hover', child=rtk.VBox{border='#1a1a1a50'}}, fills)
    
    for i=0, 25 do
        local hbox = viewport.child:add(rtk.HBox{hotzone=-1, border=false, padding=1, w=1, bg='#2a2a2a', h=27})
        hoverHbox(hbox)
        local entry = hbox:add(rtk.Entry{visible=false, cell={fillw=true, fillh=true, spacing=5}})
        local button_screenset = hbox:add(rtk.Button{
            padding=4, 
            valign='center', 
            gradient=0, 
            cursor=rtk.mouse.cursors.HAND, 
            cell={fillw=true, fillh=true, spacing=5}, 
            color='#4a4a4a', 
            alpha=0.8,
        })
        
        local slotData = loadSlotData(i)
        --if i == 5 then print(table.tostring(slotData), type(i)) end
        updateButtonAppearance(button_screenset, i, slotData)
        
        local hide_all_checkbox = hbox:add(rtk.CheckBox{
            hotzone=6,
            valign='center',
            halign='center',
            flat=true, 
            color='#3a3a3a',
            cursor=rtk.mouse.cursors.HAND,
            h=1, 
            fontsize=15,
            value=slotData and slotData.hideAllTracks or false
        }, {spacing=5})
        
        button_screenset.onreflow=function(self,event)
            b_header:attr('w', self.calc.w)
        end
        
        local delete_button = hbox:add(rtk.Button{
            cell={spacing=-10, halign='right'},
            flat=true, color='#3a3a3a',
            cursor=rtk.mouse.cursors.HAND,
            padding=5, h=1, fontsize=15,
            fontflags=rtk.font.BOLD, gradient=0,
            textcolor='red', textcolor2='#75000070', '❌'
        })
       
        button_screenset.onclick = function(self, event)
            for _, v in pairs(widgets.b) do
                v:attr('color', '#4a4a4a')
                v.click = false
            end
            
            for _, v in pairs(widgets.h) do
                v:attr('bg', '#2a2a2a')
                v.click = false
            end
            self.click = not self.click
            self:attr('color', self.click and '#8a8a8a' or '#4a4a4a')
            hbox:attr('bg', self.click and '#8a8a8a59' or '#4a4a4a59')
            idx_cell = i
            
            if event.button == rtk.mouse.BUTTON_RIGHT then
                cells_menu:open_at_mouse(self, "right", "bottom"):done(function(item) 
                    if not item then return end
                    if item.id == '1' then
                        createScript(i)
                    elseif item.id == '2' then
                        if idx_cell >= 0 and idx_cell <= 25 then
                            local retval, _ = r.GetProjExtState(0, "VisibleTracksSnapshot", "data_" .. idx_cell)
                            if retval ~= 0 then
                                local ok = r.ShowMessageBox("This slot already contains data. Do you want to overwrite it?", "Confirm Overwrite", 1)
                                if ok ~= 1 then return end
                            end
                            saveVisibleTracks(idx_cell)
                            widgets.b[idx_cell]:hide()
                            widgets.e[idx_cell]:show()
                            widgets.e[idx_cell]:focus()
                        else
                            r.ShowMessageBox("Please select a slot first.", "Error", 0)
                        end
                    elseif item.id == 'rename' then

                        widgets.b[idx_cell]:hide()
                        widgets.e[idx_cell]:show()
                        widgets.e[idx_cell]:focus()
                        
                        --saveSlotData(idx_cell, 
                    -- TODO: вызвать entry onfocus, т.е чтоб оно открылось с полем для ввода
                    end
                end)
            end
        end
      
        button_screenset.ondoubleclick = function(self, event)
            main_loader(i)
        end
        
        entry.onfocus = function(self)
            return true
        end
        
        entry.onblur = function(self)
            local slotData = loadSlotData(i) or {}
            slotData.name = self.value == '' and formatDate() or self.value
            saveSlotData(i, slotData.name, hide_all_checkbox.value)
            updateButtonAppearance(button_screenset, i, slotData)
            
            self:hide()
            button_screenset:show()
        end
        
        entry.onkeypress = function(self, event)
            if event.keycode == rtk.keycodes.ENTER then
                local slotData = loadSlotData(i) or {}
                slotData.name = self.value
                if DAT.button_save then
                    saveSlotData(i, slotData.name, hide_all_checkbox.value)
                    DAT.button_save = false
                else
                    saveSlotData(i, slotData.name)
                end
                updateButtonAppearance(button_screenset, i, slotData)
                
                self:hide()
                button_screenset:show()
            end
        end
        
        hide_all_checkbox.onchange = function(self)
            local slotData = loadSlotData(i) or {}
            saveSlotData(i, slotData.name, self.value)
        end
        
        delete_button.onclick = function(self, event)
            r.SetProjExtState(0, "VisibleTracksSnapshot", "data_" .. i, "") -- Очищаем данные для этого слота
            updateButtonAppearance(button_screenset, i, nil)
            hide_all_checkbox:attr('value', false)
        end
        
        widgets.b[i] = button_screenset
        widgets.e[i] = entry
        widgets.x[i] = delete_button
        widgets.h[i] = hbox
        widgets.c[i] = hide_all_checkbox
    end
    
    local hbox = main_vbox:add(rtk.HBox{spacing=5, padding=5, alpha=0.8, h=40}, {fillw=true})
    local load_button = hbox:add(rtk.Button{cursor=rtk.mouse.cursors.HAND, cell=fills, wrap=true, halign='center', color=shift('#3c6be5', 1, 0.5, 0.5), gradient=0.5, 'Load', padding=2})
    local save_button = hbox:add(rtk.Button{cursor=rtk.mouse.cursors.HAND, cell=fills, wrap=true, halign='center', color=shift('#6ba295', 1, 0.5, 0.5), gradient=0.5, 'Save', padding=2})
    local show_button = hbox:add(rtk.Button{cursor=rtk.mouse.cursors.HAND, cell=fills, wrap=true, halign='center', color=shift('#6ba295', 0.5, 0.5, 0.5), gradient=0.5, 'Show all', padding=2, onclick=setAllVisibleTracks})
    
    load_button.onclick = function()
        if idx_cell >= 0 and idx_cell <= 25 then
            main_loader(idx_cell)
        end
    end
    
    save_button.onclick = function()
        if idx_cell >= 0 and idx_cell <= 25 then
            DAT.button_save = true
            local retval, _ = r.GetProjExtState(0, "VisibleTracksSnapshot", "data_" .. idx_cell)
            if retval ~= 0 then
                --local ok = r.ShowMessageBox("This slot already contains data. Do you want to overwrite it?", "Confirm Overwrite", 1)
                --if ok ~= 1 then return end
            end
            saveVisibleTracks(idx_cell)
            widgets.b[idx_cell]:hide()
            widgets.e[idx_cell]:show()
            widgets.e[idx_cell]:focus()
        else
            r.ShowMessageBox("Please select a slot first.", "Error", 0)
        end
    end
end

local currentProject = r.EnumProjects(-1)
local mainCalled = false
local lastGmemValue = r.gmem_read(0)

local function checkGmem()
    local currentGmemValue = r.gmem_read(0)
    
    if currentGmemValue ~= lastGmemValue then
        lastGmemValue = currentGmemValue
        return true
    end
    return false
end

wnd.onupdate = function(self)
    local newProject = r.EnumProjects(-1)
    local gmemChanged = checkGmem()
    
    if newProject ~= currentProject or gmemChanged then
        currentProject = newProject
        mainCalled = false
    end
    
    if not mainCalled then
        rtk.call(Main)
        mainCalled = true
    end
end

wnd.onmousedown=function(self,event)
    
    return true
end
wnd:open()


