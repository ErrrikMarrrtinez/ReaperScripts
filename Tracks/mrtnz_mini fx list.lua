-- @description Mini FX LIST(for track under mouse)
-- @author mrtnz
-- @version 1.0beta1.02

local script_path = (select(2, reaper.get_action_context())):match('^(.*[/\\])')

local functions_path = script_path .. "../libs/Functions.lua"
local window_path = script_path .. "../libs/Window.lua"
local rtk_path = script_path .. "../libs/rtk.lua"
local widg = script_path .. "../libs/Widgets.lua"

local images_path = script_path .. "../images/"

local func = dofile(functions_path)
local via = dofile(window_path)
local rtk = dofile(rtk_path)
local widg = dofile(widg)

rtk.add_image_search_path(images_path, 'dark')
local enable = rtk.Image.icon('on_on'):scale(120,120,22,7)


reaper.BR_GetMouseCursorContext()
local track_under_cursor = reaper.BR_GetMouseCursorContext_Track()

if track_under_cursor == nil then
  local selected_track_count = reaper.CountSelectedTracks(0)
  if selected_track_count > 0 then
    track_under_cursor = reaper.GetSelectedTrack(0, 0)
  else
    track_under_cursor = reaper.GetLastTouchedTrack()
  end
  
end
if track_under_cursor == nil then
  reaper.ShowMessageBox("No track available!", "Error", 0)
  return
end


local original_height = 0
local posy, height = func.getTrackPosAndHeight(track_under_cursor)
local _, x, tcpPanelY, tcpWidth, _ = func.getTCPTopPanelProperties()
local _, mainWndY, _, _ = func.getMainWndDimensions()




local fx_count = reaper.TrackFX_GetCount(track_under_cursor)
local h_buttons = height / fx_count
local def_tpadding = 5
if h_buttons <= 21 then
    original_height = height
    local newHeight = fx_count * 22
    func.setTrackHeight(track_under_cursor, newHeight)
    height = newHeight
    def_tpadding = 1
end



local plus_y = (x >= 201) and 2 or 8
local new_two_y = mainWndY / 2 + plus_y
local new_y = posy + tcpPanelY - new_two_y + new_two_y
--[[
tcpWidth= tcpWidth/2
x=x+tcpWidth*2
]]
local window = rtk.Window{
  dock='left',
  borderless=true,
  h=height,
  w=tcpWidth,
  x=x,
  y=new_y,
  opacity=0.95,
  resizable=false,
}

window:open()

window.onclose = function(self, event)
    if original_height > 0 then
        func.setTrackHeight(track_under_cursor, original_height)
    end
end

window.onkeypress = via.onkeypressHandler(via, func, "main")


local horisontal_wd = window:add(rtk.HBox{})


local vbox = horisontal_wd:add(rtk.VBox{w = tcpWidth / 2, padding = 1})
local function update_proportion()
    reaper.SetExtState("Your_Section", "proportion", tostring(vbox.w / tcpWidth), false)
end
local dragging_2, initialMouseX, initialWidth = false, 0, 0
local defaultColor, lastWidth = '#6F8FAF60', nil
local proportion = tonumber(reaper.GetExtState("Your_Section", "proportion")) or 0.99
vbox:attr('w', tcpWidth * proportion)

local spacer = horisontal_wd:add(rtk.Spacer{
    bg = defaultColor,
    w = 7,
    cursor = rtk.mouse.cursors.SIZE_EW,
    onmouseenter = function(self, event) self:attr('bg', defaultColor:sub(1, -3)); return true end,
    onmouseleave = function(self, event) self:attr('bg', defaultColor); return true end,
    ondragstart = function(self, event) dragging_2, initialMouseX, initialWidth = true, event.x, vbox.w; return true end,
    ondragmousemove = function(self, event)
        if dragging_2 then
            local newWidth = rtk.clamp(initialWidth + event.x - initialMouseX, 140, tcpWidth - 5)
            vbox:attr('w', newWidth)
            update_proportion()
        end
        return true
    end,
    ondragend = function(self, event) dragging_2 = false; update(); return true end,
    onclick = function(self, event) 
        if lastWidth then vbox:attr('w', lastWidth); lastWidth = nil else lastWidth = vbox.w; vbox:attr('w', tcpWidth-5) end
        update_proportion()
        return true
    end
}, {fillh = true})




function move_button(src_hbox, target, vbox, track_under_cursor)

    local src_button = src_hbox:get_child(1)
    local target_button = target:get_child(1)
    
    

    local src_idx = vbox:get_child_index(src_hbox) - 1
    local target_idx = vbox:get_child_index(target) - 1

    if src_hbox ~= target then
        local srcCurrentIndex = src_button.currentIndex
        local targetCurrentIndex = target_button.currentIndex

        src_button.currentIndex, target_button.currentIndex = targetCurrentIndex, srcCurrentIndex

        if src_idx > target_idx then
            vbox:reorder_before(src_hbox, target)
        else
            vbox:reorder_after(src_hbox, target)
        end
        

        reaper.TrackFX_CopyToTrack(track_under_cursor, src_idx, track_under_cursor, target_idx, true)
        func.updateButtonIndices(vbox, reaper.TrackFX_GetCount(track_under_cursor))
        
    end
    
    
    
end
function createOnMouseWheelHandler(track_under_cursor, button, vbox, hbox, height)
    return function(self, event)
    
        local direction = event.wheel > 0 and 1 or -1
        local from_ID = button.currentIndex
        local to_ID = from_ID + direction
        
        if event.shift then
            local fx_count = reaper.TrackFX_GetCount(track_under_cursor)

            if to_ID < 0 then
                return
            end
            if to_ID >= fx_count then
                return
            end

            local src_idx = vbox:get_child_index(hbox)
            local target_idx = src_idx + direction
            local target_hbox = vbox:get_child(target_idx)
            
            
           
            if target_hbox then 
                move_button(hbox, target_hbox, vbox, track_under_cursor, true)
                func.updateButtonIndices(vbox, fx_count)
            end
            
            update()
            
            local x, y = reaper.GetMousePosition()
            local btnHeight = height / fx_count
            local new_y = math.floor(y + (btnHeight * direction))
            reaper.JS_Mouse_SetPosition(x, new_y)
        elseif event.ctrl then
            if to_ID < 0 then
                return
            end
            if to_ID >= fx_count then
                return
            end
            local x, y = reaper.GetMousePosition()
            local btnHeight = height / fx_count
            local new_y = math.floor(y + (btnHeight * direction))
            reaper.JS_Mouse_SetPosition(x, new_y)
            
        end
    end
end


function createOnClickHandler(track_under_cursor, button, vbox, hbox, button_disable)
    return function(self, event)
        local currentIndex = button.currentIndex
        if event.ctrl and event.shift then
            button_disable:onclick()
        elseif event.alt then
            reaper.TrackFX_Delete(track_under_cursor, currentIndex)
            vbox:remove_index(vbox:get_child_index(hbox) + 1)
            update()
        elseif event.shift then
            local bypass = reaper.TrackFX_GetEnabled(track_under_cursor, currentIndex)
            reaper.TrackFX_SetEnabled(track_under_cursor, currentIndex, not bypass)
            update()
        else
            local isOpen = reaper.TrackFX_GetOpen(track_under_cursor, currentIndex)
            reaper.TrackFX_Show(track_under_cursor, currentIndex, isOpen and 2 or 3)
        end
    end
end




enable:recolor("#1c2434")




local disabled_current_color = "#4ac882"
local drag_color = 'green'
local base_button_color = '#345c94'
local offline_color = '#6E260E'
local offline_button_disable_color = '#3a1407'
local disabled_text_color = '#FF0000'
local disabled_button_color = '#2a2a2a'
local disabled_hbox_border = '#6E260E'
local disabled_button_disable_color = '#1a1a1a'
local text_color_default = '#FFFFFF'

function setButtonAttributes(button, button_disable, track, fx_index, hbox)
    local offline = reaper.TrackFX_GetOffline(track, fx_index)
    local enabled = reaper.TrackFX_GetEnabled(track, fx_index)

    local textColor,
    buttonColor,
    buttonDisableColor,
    lborder,
    rborder

    if offline then
        textColor,
        buttonColor,
        buttonDisableColor = text_color_default,
        offline_color,
        offline_button_disable_color
        
    else
        if enabled then
            textColor,
            buttonColor,
            buttonDisableColor,
            lborder,
            rborder = text_color_default,
            base_button_color,
            disabled_current_color,
            false,
            false
            
        else
            textColor,
            buttonColor,
            buttonDisableColor,
            lborder,
            rborder = disabled_text_color,
            disabled_button_color,
            disabled_button_disable_color,
            disabled_hbox_border,
            disabled_hbox_border
        end
    end

    button:attr('textcolor', textColor)
    button:attr('color', buttonColor)
    button_disable:attr('color', buttonDisableColor)
    hbox:attr('rborder', lborder)
end
    
local round_size2=29

function update()
    vbox:remove_all()
    local fx_count1 = reaper.TrackFX_GetCount(track_under_cursor)
    
    
    
    for i = 0, fx_count1 - 1 do
    
        local retval, fxName = reaper.TrackFX_GetFXName(track_under_cursor, i, "")
        local wid = vbox.w 
        fxName = func.trimFXName(fxName, wid)
        
        
        local hbox = vbox:add(rtk.HBox{},{fillw=true,fillh=true})
        
        
        local button_disable = hbox:add(rtk.Button{
        icon=enable,
        halign='center',
        padding=1,
        iconpos='right',
        gradient=3,
        w=30,
        z=4,
        },{fillh=true})
        
   
        
        
        local fx_button = hbox:add(rtk.Button{
        label=fxName,
        color=base_button_color..20,
        wrap=true,
        flat=true,
        tpadding=def_tpadding,
        halign='center',
        bborder='#7a7a7a65',
        
        z=15,
        
        },{fillw=true, fillh=true}) -- кнопка fx
        --fx_button:hide()
        
        local initial_value = func.GetWetFx(track_under_cursor, i)
        
        local circle = hbox:add(widg.CircleWidget2{
            sens=0.8,
            w=round_size2,
            radius=round_size2,
            fontsize=10,
            font='Geneva',
            font_y=40,
            textcolor = 'transparent',
            y=1,
            value=initial_value,
            onChange = function(value)
                func.SetWetFx(track_under_cursor, i, value)
            end
        },{fillh=true})  -- наш кноб
        
        
        
        
        local currentIndex = i
        
        fx_button.currentIndex = i
        fx_button.onclick = createOnClickHandler(track_under_cursor, fx_button,vbox, hbox, button_disable)
        fx_button.onmousewheel = createOnMouseWheelHandler(track_under_cursor, fx_button, vbox, hbox, height)
        
        fx_button.ondragstart = function(self, event)
            button_disable:attr('lborder', drag_color)
            self:attr('rborder', drag_color)
            dragging = hbox
            return true
        end
        
        fx_button.ondragend = function(self, event)
            button_disable:attr('lborder', nil)
            self:attr('rborder', nil)
            dragging = nil
            update()
            return true
        end
        
        fx_button.ondropfocus = function(self, event, _, src_hbox)
            return true
        end
        
        fx_button.ondropmousemove = function(self, event, _, src_hbox)
            if dragging then
                move_button(dragging, hbox, vbox, track_under_cursor, false)
            end
            return true
        end
        
        fx_button.onmouseenter = function(self, event)
            if dragging then
                move_button(dragging, hbox, vbox, track_under_cursor, false)
            end
            if event.shift then
                self:attr('rborder', drag_color)
                --self:attr('color', '#848484')
            else
                --self:attr('color', "#6a6a6a")
            end
            return true
        end
        
        fx_button.onmouseleave = function(self, event)
            self:attr('rborder', false)
            --self:attr('color', "#3a3a3a")
            return true 
        end
        
        
        setButtonAttributes(fx_button, button_disable, track_under_cursor, i, hbox)
        
        button_disable.onclick = function(self, event)
            local offline = reaper.TrackFX_GetOffline(track_under_cursor, i)
            reaper.TrackFX_SetOffline(track_under_cursor, i, not offline)
            setButtonAttributes(fx_button, button_disable, track_under_cursor, i, hbox)  -- Обновим атрибуты
            
            update()
        end
        
    end
end
update()
vbox:focus()

local prevVisibleTracks = nil
local prevX, prevTcpPanelY, prevTcpWidth = nil, nil, nil

local function main()
    local currVisibleTracks = func.collectVisibleTracks()
    
    local _, x, tcpPanelY, tcpWidth, _ = func.getTCPTopPanelProperties()
    
    if prevVisibleTracks and prevX and prevTcpPanelY and prevTcpWidth then
        if func.trackParametersChanged(currVisibleTracks, prevVisibleTracks) 
            or x ~= prevX 
            or tcpPanelY ~= prevTcpPanelY
            or tcpWidth ~= prevTcpWidth then
            window:close()
            return -- выходим из функции, чтобы прекратить цикл
        end
    end
    
    prevVisibleTracks = currVisibleTracks
    prevX, prevTcpPanelY, prevTcpWidth = x, tcpPanelY, tcpWidth
    
    reaper.defer(main) -- перезапускаем функцию
end

main() -- начальный запуск



