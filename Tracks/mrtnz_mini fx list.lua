-- @description mrtnz_Mini FX LIST(for track under mouse)
-- @author mrtnz
-- @version 1.0beta1.040

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
local freeze_ic = rtk.Image.icon('freeze_ic'):scale(120,120,22,8)
local visib = rtk.Image.icon('visib'):scale(120,120,22,8)
local edit = rtk.Image.icon('edit'):scale(120,120,22,8)





--[[
VolumeMeter = rtk.class('VolumeMeter', rtk.Spacer)

VolumeMeter.register{
    levels = rtk.Attribute{default={0, 0}},
    spacing = rtk.Attribute{default=3},
    mindb = rtk.Attribute{default=-64},
    color = rtk.Attribute{type='color', default='cornflowerblue'},
    gutter = rtk.Attribute{default=0.08},
    h = 1.0,
}

function VolumeMeter:initialize(attrs, ...)
    rtk.Spacer.initialize(self, attrs, VolumeMeter.attributes.defaults, ...)
end

function VolumeMeter:_handle_draw(offx, offy, alpha, event)
    local calc = self.calc
    local x, y = offx + calc.x, offy + calc.y
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

function VolumeMeter:set_from_track(track, maxch)
    if not reaper.ValidatePtr2(0, track, 'MediaTrack*') then
        self:attr('levels', {0})
        return
    end
    local levels, nch = {}, rtk.clamp(reaper.GetMediaTrackInfo_Value(track, 'I_NCHAN'), 0, maxch)
    for i = 0, nch - 1 do
        levels[#levels+1] = reaper.Track_GetPeakInfo(track, i)
    end
    self:attr('levels', levels)
end
]]



function getFrozenFxNamesAndIndices(track)
    retval, trackChunk = reaper.GetTrackStateChunk(track, "", false)
    if not retval then return {}, {} end

    local frozenFxNames = {}
    local frozenFxIndices = {}
    local inFreezeBlock = false
    local fxIndex = 0

    for line in string.gmatch(trackChunk, "[^\r\n]+") do
        if line:find("<FREEZE") then
            inFreezeBlock = true
            fxIndex = fxIndex + 1
        elseif inFreezeBlock and line:find("</FXCHAIN>") then
            inFreezeBlock = false
        elseif inFreezeBlock then
            local fxName = line:match('"[^:]+: ([^"]+)"')
            if fxName then
                -- Убираем всё, что находится в скобках
                fxName = fxName:gsub("%s%b()", "")
                table.insert(frozenFxNames, fxName)
                frozenFxIndices[fxIndex - 1] = true
            end
        end
    end

    return frozenFxNames, frozenFxIndices
end





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

local frozenFxNames, frozenFxIndices = getFrozenFxNamesAndIndices(track_under_cursor)

local original_height = 0
local posy, height = func.getTrackPosAndHeight(track_under_cursor)
local _, x, tcpPanelY, tcpWidth, _ = func.getTCPTopPanelProperties()
local _, mainWndY, _, _ = func.getMainWndDimensions()




local fx_count = reaper.TrackFX_GetCount(track_under_cursor)
fx_count = fx_count + #frozenFxNames
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

local settings_width  = 15

local horisontal_wd = window:add(rtk.HBox{})
local curr_scale = rtk.scale.system*rtk.scale.reaper*rtk.scale.user




local vbox = horisontal_wd:add(rtk.VBox{w = tcpWidth / 2, padding = 1})

function update_proportion()
    reaper.SetExtState("MiniFxList", "proportion", tostring(vbox.w / tcpWidth), false)
end

local dragging_2, initialMouseX, initialWidth = false, 0, 0
local defaultColor, lastWidth = '#6F8FAF60', nil
local proportion = tonumber(reaper.GetExtState("MiniFxList", "proportion")) or 0.96 / curr_scale

vbox:attr('w', tcpWidth * proportion)

local spacer = horisontal_wd:add(rtk.Spacer{

    bg = defaultColor,
    w = 7,
    x=-1,
    z=12,
    
    onmouseenter = function(self, event) 
        self:attr('cursor', rtk.mouse.cursors.SIZE_EW)
        self:attr('bg', defaultColor:sub(1, -3));
        return true 
    end,
    
    onmouseleave = function(self, event) 
        self:attr('cursor', rtk.mouse.cursors.UNDEFINED) 
        self:attr('bg', defaultColor); 
        return true 
    end,
    
    ondragstart = function(self, event)
        dragging_2, initialMouseX, initialWidth = true, event.x, vbox.w
        self:attr('cursor', rtk.mouse.cursors.REAPER_VERTICAL_LEFTRIGHT)
        if isVisible then
        end
        return true
    end,
    
    ondragmousemove = function(self, event)
        if dragging_2 then
            local newWidth = rtk.clamp(initialWidth + event.x - initialMouseX, 140, tcpWidth - settings_width-5)
            vbox:attr('w', newWidth)
        end
        return true
    end,
    
    ondragend = function(self, event)
        dragging_2 = false
        self:attr('cursor', rtk.mouse.cursors.UNDEFINED)
        self:onmouseenter()
        update_proportion()
        update()
        return true
    end,
    
    onmousedown = function(self, event)
        self:attr('cursor', rtk.mouse.cursors.REAPER_VERTICAL_LEFTRIGHT)
        return true
    end,
    
    onmouseup = function(self, event)
        self:attr('cursor', rtk.mouse.cursors.REAPER_VERTICAL_LEFTRIGHT)
        self:onmouseenter()
        return true
    end,
    
    onclick = function(self, event)
        if lastWidth then
            vbox:attr('w', lastWidth)
            lastWidth = nil
        else
            lastWidth = vbox.w
            vbox:attr('w', tcpWidth-settings_width-7)
        end
        update_proportion()
        return true
    end,},{
    fillh = true
})




local vbox_sends = horisontal_wd:add(rtk.VBox{bg='#2a2a2a',padding = 1}, {fillw = true})

local new_vbox = horisontal_wd:add(rtk.VBox{padding=1},{fillw=true})
new_vbox:hide()
--local vbox_settings = horisontal_wd:add(rtk.VBox{w = settings_width, bg = '#1a1a1a',},{fillh = true})
local vbox_settings = rtk.VBox{w = settings_width, bg = '#1a1a1a',},{fillh = true}

enable:recolor("#1c2434")
local disabled_current_color = "#4ac88275"
local drag_color = '#3a3a3a10'
local base_button_color = '#345c94'
local offline_color = '#6E260E'
local offline_button_disable_color = '#3a1407'
local disabled_text_color = '#FF0000'
local disabled_button_color = '#2a2a2a'
local disabled_hbox_border = '#6E260E'
local disabled_button_disable_color = '#1a1a1a'
local text_color_default = '#FFFFFF'

local isEnter = false
local track_under_cursor_at_first_click = nil
local current_fx_index = nil
local current_fx_name = nil
local selected_fx_name = nil
local current_mode = 0
local selectedTracks = {}


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

local all_buttons = {}
local all_boxes = {}


function updateButtonBorders(all_buttons, clickedIndex, specialBorder, currentButton)
    for i, button in ipairs(all_buttons) do
        if specialBorder and button == currentButton then
            -- Устанавливаем специальную границу для текущей кнопки
            button:attr('border', 'yellow')
        else
            -- Сброс границ для всех остальных кнопок
            button:attr('tborder', false)
            button:attr('bborder', false)
            button:attr('lborder', false)
            button:attr('rborder', false)
            if not specialBorder then
                -- Применяем логику красной границы, если это не специальная граница
                local borderColor = 'red'
                if clickedIndex == 1 then
                    button:attr('tborder', i == clickedIndex and borderColor or nil)
                    button:attr('bborder', i == clickedIndex and borderColor or nil)
                    button:attr('lborder', i == clickedIndex and borderColor or nil)
                    button:attr('rborder', i == clickedIndex and borderColor or nil)
                elseif i == 1 then
                    button:attr('tborder', i <= clickedIndex and borderColor or nil)
                    button:attr('lborder', i <= clickedIndex and borderColor or nil)
                    button:attr('rborder', i <= clickedIndex and borderColor or nil)
                elseif i == clickedIndex then
                    button:attr('bborder', borderColor)
                    button:attr('lborder', borderColor)
                    button:attr('rborder', borderColor)
                else
                    button:attr('lborder', (i < clickedIndex and i > 1) and borderColor or nil)
                    button:attr('rborder', (i < clickedIndex and i > 1) and borderColor or nil)
                end
            end
        end
    end
    temp_index1 = clickedIndex
end





function freeze_track(value, track_under_cursor)

    reaper.Undo_BeginBlock()
    reaper.PreventUIRefresh(1)
    
    local selected_track = track_under_cursor
    local itemCount = reaper.CountTrackMediaItems(selected_track)
    if itemCount == 0 then
        reaper.ShowConsoleMsg("В треке нет элементов.\n")
        return
    end
    if selected_track then
        local fxCount = reaper.TrackFX_GetCount(selected_track)
        local freeze_count = value
        if freeze_count < fxCount then
            local idx = reaper.GetNumTracks()
            reaper.InsertTrackAtIndex(idx, true)
            local temp_track = reaper.GetTrack(0, idx)
            reaper.SetMediaTrackInfo_Value(temp_track, "I_TCPHIDE", 1)
            
            for i = fxCount-1, freeze_count, -1 do
                reaper.TrackFX_CopyToTrack(selected_track, i, temp_track, 0, true)
            end
    
            reaper.Main_OnCommand(41223, 0)
    
            local new_selected_track = reaper.GetSelectedTrack(0, 0)
            local temp_fx_count = reaper.TrackFX_GetCount(temp_track)
    
            for i = temp_fx_count-1, 0, -1 do
                reaper.TrackFX_CopyToTrack(temp_track, i, new_selected_track, 0, true)
            end
    
            reaper.DeleteTrack(temp_track)
        else
            reaper.ShowConsoleMsg("error.\n")
        end
    else
        reaper.ShowConsoleMsg("Трек не выбран.\n")
    end
  
    reaper.PreventUIRefresh(-1)
    reaper.UpdateArrange()
    reaper.Undo_EndBlock("Freezed", -1)
    
end


local temp_index = 0

local freeze_button_time = vbox_settings: 
     add(
         rtk.Button{
             icon=freeze_ic,
             color="#2f445c",
             padding=0,
             border='#4a4a4a',
             halign='center',
             disabled=true,
             h=20
             },{
             fillw=true,
})

local visible_frozen = vbox_settings: 
     add(
         rtk.Button{
             icon=visib,
             color="#2f445c",
             padding=0,
             border='#4a4a4a',
             halign='center',
             h=20
             },{
             fillw=true,
})

local edit_button_fx = vbox_settings: 
     add(
         rtk.Button{
             icon=edit,
             color="#2f445c",
             padding=0,
             halign='center',
             --disabled=true,
             
             h=20
             },{
             fillw=true,
})

local vp = horisontal_wd:
    add(
        rtk.Viewport{
            child = vbox_settings,
            h = window.h,  
            bg=vbox_settings.bg,
            vscrollbar = true, 
            hscrollbar = false,
            vscrollbar = 0,
            smoothscroll=true,
            },{
            fillh=true
            
})

local active_button = nil
local width_wide = 45
local settings_width = 15



--[[минимальная пропорция 0.68632707774799
]]


local function reset_other_buttons(except)
    for _, button in ipairs({freeze_button_time, visible_frozen, edit_button_fx}) do
        if button ~= except then
            button:animate{'h', dst=20, duration=0.2}
        end
    end
end

local is_active_value = false

function enter_animation(self)
    if active_button ~= self then
        reset_other_buttons(self)
        self:animate{'h', dst=width_wide, duration=0.2}
        vbox_settings:animate{'w', dst=width_wide, duration=0.2}
        update_proportion()

        local proportion = tonumber(reaper.GetExtState("MiniFxList", "proportion")) or 0.94 / curr_scale
        if proportion >= 0.90 and proportion <= 0.96 then
            vbox:animate{'w', dst=tcpWidth-width_wide-spacer.w, duration=0.2}
            
            is_active_value = true
        end
    end
    active_button = self
end

function leave_animation(self)
    if active_button == self then
        vbox_settings:animate{'w', dst=settings_width, duration=0.2}
        self:animate{'h', dst=20, duration=0.2}
        :after(function()
            if active_button == self then
                if is_active_value then
                    vbox:animate{'w', dst=tcpWidth-settings_width-spacer.w, duration=0.2}
                        :after(function()
                            update_proportion()
                        end)
                end
                is_active_value = false
                active_button = nil
            end
        end)
    end
end

freeze_button_time.onmouseenter = function(self, event)
    enter_animation(self)
    return true
end

freeze_button_time.onmouseleave = function(self, event)
    leave_animation(self)
    return true
end

visible_frozen.onmouseenter = function(self, event)
    enter_animation(self)
    return true
end

visible_frozen.onmouseleave = function(self, event)
    leave_animation(self)
    return true
end

edit_button_fx.onmouseenter = function(self, event)
    enter_animation(self)
    return true
end

edit_button_fx.onmouseleave = function(self, event)
    leave_animation(self)
    return true
end

visible_frozen:onmouseleave()

local temp_index1 = 0

function createOnClickHandler(track_under_cursor, button, vbox, hbox, button_disable)
    return function(self, event)
        local currentIndex = button.currentIndex
        local temp_index = currentIndex+1
        if event.button == rtk.mouse.BUTTON_LEFT then
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
        elseif event.button == rtk.mouse.BUTTON_RIGHT then
            --func.msg(temp_index)
            
            updateButtonBorders(all_buttons, temp_index, false)
            
            freeze_button_time:attr('disabled', false)
            edit_button_fx:attr('disabled', true)
            temp_index1 = currentIndex+1
            
        elseif event.button == rtk.mouse.BUTTON_MIDDLE then
        
            freeze_button_time:attr('disabled', true)
            edit_button_fx:attr('disabled', false)
            updateButtonBorders(all_buttons, temp_index, true, button)
            local entry = rtk.Entry{wrap=true,value=button.label,placeholder='Rename fx '..button.label..' to',padding=1, halign='center'}

            hbox:add(entry,{fillw=true, fillh=true})
            hbox:remove(button)
            
            entry:focus()
            entry:select_all()
            entry.onkeypress = function(self, event)
                if event.keycode == rtk.keycodes.ENTER then
                    reaper.TrackFX_SetNamedConfigParm(track_under_cursor, currentIndex, 'renamed_name', self.value )
                    update()
                end
                return 
            end
            
        end
    end
end

freeze_button_time.onclick = function(self, event)
    freeze_track(temp_index1, track_under_cursor)
    update()
end

function createOnClickHandlerForDisable(track_under_cursor, i, fx_button, button_disable, hbox, setButtonAttributes, update)
    return function(self, event)
        local offline = reaper.TrackFX_GetOffline(track_under_cursor, i)
        reaper.TrackFX_SetOffline(track_under_cursor, i, not offline)
        setButtonAttributes(fx_button, button_disable, track_under_cursor, i, hbox)
        update()
    end
end




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
    
    
function getCurrentFXPins(track, fxnumber)
    local retval, inputPins, outputPins = reaper.TrackFX_GetIOSize(track, fxnumber)
    for pin = 2, 3 do
        local low32bits, _ = reaper.TrackFX_GetPinMappings(track, fxnumber, 0, pin)
        if low32bits ~= 0 then
            return (math.log(low32bits) / math.log(2)) + 1
        end
    end
    
    return nil
end


function setSidechainPins(track, fxnumber, value, mode)
    local numOfChannels = math.min(reaper.GetMediaTrackInfo_Value(track, "I_NCHAN"), 32)
    local retval, inputPins, outputPins = reaper.TrackFX_GetIOSize(track, fxnumber)
    for pin = 0, inputPins-1 do
        if pin == 2 or pin == 3 then
            local low32bits, hi32bits = reaper.TrackFX_GetPinMappings(track, fxnumber, 0, pin)
            if low32bits ~= 0 then
                local newPins = 2^(pin + value)
                if mode == "add" then
                    newPins = low32bits | newPins
                end
                reaper.TrackFX_SetPinMappings(track, fxnumber, 0, pin, newPins, 0)
            end
        end
    end
    for pin = 0, outputPins-1 do
        if pin == 2 or pin == 3 then
            local low32bits, hi32bits = reaper.TrackFX_GetPinMappings(track, fxnumber, 1, pin)
            if low32bits ~= 0 then
                local newPins = 2^(pin + value)
                if mode == "add" then
                    newPins = low32bits | newPins
                end
                reaper.TrackFX_SetPinMappings(track, fxnumber, 1, pin, newPins, 0)
            end
        end
    end
end


function findFreeDestChannel(track)
    local occupiedChannels = {}
    for i = 0, reaper.GetTrackNumSends(track, -1) - 1 do
      local dst_chan = reaper.GetTrackSendInfo_Value(track, -1, i, "I_DSTCHAN")
      occupiedChannels[dst_chan] = true
    end
    for i = 2, 18, 2 do
      if not occupiedChannels[i] then
        return i
      end
    end
    return 2
end
    
    
function createSend(freeChannel, source_tracks, destination_track, fx_index)
    for _, selected_track in ipairs(source_tracks) do
        if selected_track and selected_track ~= destination_track then
            reaper.Undo_BeginBlock()
            local ch_count = reaper.GetMediaTrackInfo_Value(destination_track, 'I_NCHAN')
            reaper.SetMediaTrackInfo_Value(destination_track, 'I_NCHAN', math.max(freeChannel + 1, ch_count))
    
            local send = reaper.CreateTrackSend(selected_track, destination_track)
            reaper.SetTrackSendInfo_Value(selected_track, 0, send, 'I_SENDMODE', 3)
            reaper.SetTrackSendInfo_Value(selected_track, 0, send, 'I_DSTCHAN', freeChannel)
            reaper.SetTrackSendInfo_Value(selected_track, 0, send, 'I_MIDIFLAGS', 4177951)
            reaper.Undo_EndBlock("Create send to track under cursor", -1)
        end
    end
end
  
    
function main_send(mode, source_tracks, destination_track, fx_index)
    --if mode == 0 then return end
    local num_selected_tracks = #source_tracks
    local currentPin = getCurrentFXPins(destination_track, fx_index)
    local currentChannel = currentPin or findFreeDestChannel(destination_track)
    
    if mode == 3 then  -- "new_preserve" теперь становится mode 3
        local freeChannel = findFreeDestChannel(destination_track)
        createSend(freeChannel, source_tracks, destination_track, fx_index)
        setSidechainPins(destination_track, fx_index, freeChannel - 2, "add")
    elseif mode == 2 then  -- "new_replace" теперь становится mode 2
        local freeChannel = findFreeDestChannel(destination_track)
        createSend(freeChannel, source_tracks, destination_track, fx_index)
        setSidechainPins(destination_track, fx_index, freeChannel - 2, "replace")
    elseif mode == 1 then  -- "use_current" теперь становится mode 1
        local freeChannel = currentChannel - 1
        createSend(freeChannel, source_tracks, destination_track, fx_index)
    end
end


function updateWidgetText(track, isDragging_2)
    if track and window.in_window then
        
        local _, track_name = reaper.GetTrackName(track, "")
        local text_prefix = isDragging_2 and 'создается посыл с трека ' or 'создался посыл с трека '
        if not isDragging_2 and current_fx_name then
            local _, destination_track_name = reaper.GetTrackName(track_under_cursor, "")
            if track == track_under_cursor then
            else
                local selectedTracksText = track_name
                selectedTracks = {}  -- Очищаем массив перед заполнением
                if reaper.IsTrackSelected(track) then
                    local numTracks = reaper.CountSelectedTracks(0)
                    for j = 0, numTracks - 1 do
                        local selTrack = reaper.GetSelectedTrack(0, j)
                        if selTrack ~= track_under_cursor then
                            table.insert(selectedTracks, selTrack)
                        end
                    end
                else
                    table.insert(selectedTracks, track)
                end

                if current_mode == 0 then
                    --reaper.ShowConsoleMsg('мод = 0')
                    return
                else
                    main_send(current_mode, selectedTracks, track_under_cursor, current_fx_index)
                    update()
                end
            end
        else
            --text:attr('text', text_prefix .. track_name)
        end
        isEnter = isDragging_2
    end
end

local close_1 = false

function checkTrackAndCursor()
    local mouse_state = reaper.JS_Mouse_GetState(5) 
    local isDragging_2 = (mouse_state == 5)
    if close_1 then return end
    if isDragging_2 and not track_under_cursor_at_first_click then
        -- Начало перетаскивания
        reaper.BR_GetMouseCursorContext()
        track_under_cursor_at_first_click = reaper.BR_GetMouseCursorContext_Track()
        
    elseif not isDragging_2 and track_under_cursor_at_first_click then
    
        updateWidgetText(track_under_cursor_at_first_click, false)
        track_under_cursor_at_first_click = nil
        
    end
    
    if track_under_cursor_at_first_click and isDragging_2 then
        updateWidgetText(track_under_cursor_at_first_click, true)
    end
    
    reaper.defer(checkTrackAndCursor) 
end


function getCurrentFXPins2(track, fxnumber)
    local retval, inputPins, outputPins = reaper.TrackFX_GetIOSize(track, fxnumber)
    if inputPins > 4 then  -- Игнорируем FX с большим количеством входных пинов
        return {}
    end

    local pinsUsed = {}
    local pinPairs = {}

    for pin = 2, inputPins - 1 do
        local low32bits, _ = reaper.TrackFX_GetPinMappings(track, fxnumber, 0, pin)
        -- Проверяем каждый бит в low32bits
        for bit = 0, 31 do
            if (low32bits & (1 << bit)) ~= 0 then
                local pinIndex = bit + 1
                if not pinsUsed[pinIndex] then
                    pinsUsed[pinIndex] = true
                    if pin % 2 == 0 then
                        -- Левый пин, ищем его пару (правый пин)
                        local rightPin = pinIndex + 1
                        if pinsUsed[rightPin] then
                            -- Пара найдена
                            table.insert(pinPairs, {left = pinIndex, right = rightPin})
                        end
                    else
                        -- Правый пин, ищем его пару (левый пин)
                        local leftPin = pinIndex - 1
                        if pinsUsed[leftPin] then
                            -- Пара найдена
                            table.insert(pinPairs, {left = leftPin, right = pinIndex})
                        end
                    end
                end
            end
        end
    end
    
    return pinPairs
end


isVisible = false

function toggleVisibility()
    isVisible = not isVisible
    for _, hbox in ipairs(all_hboxes) do
        if isVisible then
            visible_frozen:attr('color', '#bfcfff70')
            hbox:show()
            new_vbox:show()
            vbox_sends:hide()
        else
            hbox:hide()
            new_vbox:hide()
            visible_frozen:attr('color', '#2f445c')
            vbox_sends:show()
        end
    end
    update()
end

visible_frozen.onclick = toggleVisibility

all_hboxes = {}

local round_size2 = 29
local original_track_color = nil 
local current_track = nil  
local selected_fx_index = nil
local selected_fx_track = nil
local red_color = reaper.ColorToNative(255, 0, 0)  -- RGB для красного

function update()

    vbox:remove_all()
    vbox_sends:remove_all()
    new_vbox:remove_all()
    
    all_boxes = {}
    all_buttons = {}
    
    freeze_button_time:attr('disabled', true)
    freeze_button_time:attr('border', false)
    
    visible_frozen:attr('border', false)
    
    local fx_count1 = reaper.TrackFX_GetCount(track_under_cursor)
    local frozenFxNames, frozenFxIndices = getFrozenFxNamesAndIndices(track_under_cursor)
    
    --first create freezed buttons
    
    for i = 1, #frozenFxNames do
        local fxName_frez = frozenFxNames[i]
        local hbox_frez = new_vbox:add(rtk.HBox{},{fillw=true,fillh=true})
        local fx_button_fr = hbox_frez:
            add(
                rtk.Button{
                    label=fxName_frez,
                    color=base_button_color..10,
                    wrap=true,
                    icon=freeze_ic,
                    flat=true,
                    iconpos='left',
                    tagged=true,
                    padding=2,
                    halign='center',
                    bborder='#7a7a7a65',
                    z=15,
                    disabled = true,
                    },{
                    fillw=true,
                    fillh=true
        })
        
    end
    
    for i = 0, fx_count1 - 1 do
        local initial_value = func.GetWetFx(track_under_cursor, i)
        local retval, fxName = reaper.TrackFX_GetFXName(track_under_cursor, i, "")
        
        
        local wid = vbox.w 
        local pinPairs = getCurrentFXPins2(track_under_cursor, i)
        local pinStrings = {}
        for _, pair in ipairs(pinPairs) do
            table.insert(pinStrings, tostring(pair.left) .. "/" .. tostring(pair.right))
        end
        local pinString = #pinStrings > 0 and (" (" .. table.concat(pinStrings , ", ")) .. ")" or ""
        
        fxName = func.trimFXName(fxName, wid)
        
        local hbox = vbox:add(rtk.HBox{},{fillw=true,fillh=true})
        local hbox_send = vbox_sends:add(rtk.HBox{spacing=-2,}, {fillw = true, fillh = true})
        

        local box_button_circ = hbox_send:
            add(
                rtk.HBox{
                z=-1,
                w=20,
                },{
                fillh=true,
        })
        

        local button_circ = box_button_circ:
            add(
                rtk.Button{
                    color=base_button_color..70,
                    wrap=true,
                    w=20,
                    flat=false,
                    halign='center',
                    tmargin=1,
                    bmargin=3,
                    padding=1,
                    z=2,
                    --rhotzone=40,
                    '   ',
                    },{
                    fillh=true
        })
        
        local spacer_box = hbox_send:
            add(
                rtk.HBox{
                    lmargin = 3,
                    rmargin = 6, 
                    bborder='#7a7a7a65',
                    },{
                    fillw=true, 
                    fillh=true
        })
        
        local base_W = 35
        
        local new_free_mode = spacer_box:
            add(
                rtk.Button{
                    padding=1,
                    'FREE',
                    w=base_W,
                    z=2,
                    lhotzone=3,
                    },{
                    fillh=true
        })
        
        new_free_mode:hide()
        
        local new_preserve = spacer_box:
            add(
                rtk.Button{
                    padding=1,
                    'SAVE',
                    z=2,
                    w=base_W,
                    lhotzone=3,
                    },{
                    fillh=true
        })
        
        new_preserve:hide()
        
        local button_disable = hbox:
            add(
                rtk.Button{
                    icon=enable,
                    halign='center',
                    padding=1,
                    iconpos='right',
                    border='#ffffff30',
                    gradient=2,
                    w=30,
                    z=4,
                    },{
                    fillh=true
        })
        
        local fx_button = hbox:
            add(
                rtk.Button{
                    label=fxName .. pinString,
                    color=base_button_color..20,
                    wrap=true,
                    flat=true,
                    tpadding=def_tpadding,
                    halign='center',
                    bborder='#7a7a7a65',
                    z=15,
                    },{
                    fillw=true,
                    fillh=true
        }) -- кнопка fx
        
        local circle = hbox:
            add(
                widg.CircleWidget2{
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
                    },{
                    fillh=true
        })  -- кноб
        
        
        if isFrozen then
            fx_button:attr('disabled', true)
        end
        
        new_free_mode.onmouseenter = function(self, event)
            if isEnter then
                isCursorOnNewFreeMode = true
                self:attr('border', 'red')
                current_mode = 2
            end
            return true
        end
        
        new_preserve.onmouseenter = function(self, event)
            if isEnter then
                isCursorOnNewPreserve = true
                self:attr('border', 'red')
                current_mode = 3
            end
            return true
        end
        
        new_free_mode.onmouseleave = function(self, event)
            isCursorOnNewFreeMode = false
            self:attr('border', false)
            return true
        end
        
        new_preserve.onmouseleave = function(self, event)
            isCursorOnNewPreserve = false
            self:attr('border', false)
            return true
        end
        
        button_circ.onmouseleave = function(self, event)
            self:attr('border', false)
            if not isCursorOnNewFreeMode and not isCursorOnNewPreserve then
                new_preserve:animate{'w', dst=2, duration=0.1}
                    :after(function()
                        new_free_mode:hide()
                        new_preserve:hide()
                        return new_free_mode:animate{'w', dst=2, duration=0.1}
                            :after(function()
                                new_free_mode:hide()
                                new_preserve:hide()
                                
                            end)
                    end)
            end
            return true
        end
        
        button_circ.onmouseenter = function(self, event)
            if isEnter then
                
                self:attr('border', 'red')
                
                new_free_mode:attr('w', 2)
                new_preserve:attr('w', 2)
        
                new_free_mode:show()
                new_preserve:show()
                
                update_proportion()
                
                local proportion = tonumber(reaper.GetExtState("MiniFxList", "proportion")) or 0.94 / curr_scale
                
                if proportion > 0.68 then
                    vbox:animate{'w', dst=tcpWidth/(proportion+0.7), duration=0.2}
                end
                
                new_free_mode:animate{'w', dst=base_W, duration=0.1}
                    :after(function()
                        return new_preserve:animate{'w', dst=base_W, duration=0.1}
                    end)
                
                current_fx_index = i
                current_fx_name = fxName
                current_track = track_under_cursor
                current_mode = 1
            end
            return true
        end
        
        
        circle.ondoubleclick = function(self, event)
            local new_value = self.value == 0 and 100 or 0 
            self.value = new_value
            func.SetWetFx(track_under_cursor, i, new_value) 
            update()
        end
        
        circle.onclick = function(self, event)
            if event.alt then
                local new_value = self.value == 0 and 100 or 0  
                self.value = new_value 
                func.SetWetFx(track_under_cursor, i, new_value) 
                update()
            end
        end
        
        circle.onmousewheel = function(self, event)
            local delta = event.ctrl and 8 or 25  
            local new_value = self.value + (event.wheel < 0 and delta or -delta)
            new_value = math.max(0, math.min(100, new_value))
        
            self.value = new_value
            func.SetWetFx(track_under_cursor, i, new_value)
            update()

            return true 
        end
        
        local currentIndex = i
        fx_button.currentIndex = i
        fx_button.onclick = createOnClickHandler(track_under_cursor, fx_button,vbox, hbox, button_disable)
        fx_button.onmousewheel = createOnMouseWheelHandler(track_under_cursor, fx_button, vbox, hbox, height)
        
        
        fx_button.ondragstart = function(self, event)
            if event.ctrl or event.shift then
                selected_fx_index = i  -- Сохраняем индекс FX
                selected_fx_track = track_under_cursor  -- Сохраняем исходный трек
                self:attr('cursor', rtk.mouse.cursors.REAPER_DRAGDROP_COPY)
            else --тут уже моя другая логика
                dragging = hbox
                button_disable:attr('lborder', drag_color)
                self:attr('gradient', 2)
                self:attr('rborder', drag_color)
            end
            return true
        end
        
        fx_button.ondragend = function(self, event)
            if event.ctrl or event.shift then
                -- Логика завершения перетаскивания
                self:attr('lborder', nil)
                self:attr('rborder', nil)
                if original_track_color and current_track then 
                    reaper.SetMediaTrackInfo_Value(current_track, "I_CUSTOMCOLOR", original_track_color)
                end
                if selected_fx_index ~= nil then
                    reaper.BR_GetMouseCursorContext()
                    local track_under_cursor = reaper.BR_GetMouseCursorContext_Track()
        
                    if track_under_cursor then
                        local is_move = event.shift
                        reaper.TrackFX_CopyToTrack(selected_fx_track, selected_fx_index, track_under_cursor, -1, is_move)
                    end
                    self:attr('cursor', rtk.mouse.cursors.UNDEFINED)
                    original_track_color = nil
                    current_track = nil
                    selected_fx_index = nil
                end
            else --тут уже моя другая логика
                button_disable:attr('lborder', nil)
                self:attr('rborder', nil)
                dragging = nil
                update()
                self:attr('gradient', 1)
                return true
            end
            update()
            return true
        end
        
        fx_button.ondragmousemove = function(self, event)
            if selected_fx_index ~= nil and (event.ctrl or event.shift) then
                -- Логика перемещения с подсветкой трека
                reaper.BR_GetMouseCursorContext()
                local track_under_cursor = reaper.BR_GetMouseCursorContext_Track()
                if track_under_cursor and track_under_cursor ~= current_track then
                    if original_track_color and current_track then 
                        reaper.SetMediaTrackInfo_Value(current_track, "I_CUSTOMCOLOR", original_track_color)
                    end
                    original_track_color = reaper.GetMediaTrackInfo_Value(track_under_cursor, "I_CUSTOMCOLOR") 
                    current_track = track_under_cursor
                end
                if track_under_cursor then
                    reaper.SetMediaTrackInfo_Value(track_under_cursor, "I_CUSTOMCOLOR", red_color|0x1000000)
                end
                return true
            end
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
            end
            current_mode = 0
            return true
        end
        
        fx_button.onmouseleave = function(self, event)
            if dragging then
            self:attr('rborder', false)
            end
            return true 
        end
        
        
        if #pinPairs == 0 then
             button_circ:attr('disabled', true)
             
             box_button_circ.onmouseenter = function(self, event)
                 self:attr('border', '#ffffff30')
                 isEnter = false
 
                 return true
             end
             
             box_button_circ.onmouseleave = function(self, event)
                 self:attr('border', false)
                 isEnter = false
                 return true
             end
             
         end
         
        setButtonAttributes(fx_button, button_disable, track_under_cursor, i, hbox)
        
        button_disable.onclick = createOnClickHandlerForDisable(track_under_cursor, i, fx_button, button_disable, hbox, setButtonAttributes, update)
        
        table.insert(all_buttons, fx_button)
        table.insert(all_hboxes, hbox)
    end
    
end

checkTrackAndCursor()
update()

vbox:focus()

local prevVisibleTracks = nil
local prevX, prevTcpPanelY, prevTcpWidth = nil, nil, nil

function main()
    local currVisibleTracks = func.collectVisibleTracks()
    local _, x, tcpPanelY, tcpWidth, _ = func.getTCPTopPanelProperties()
    
    if prevVisibleTracks and prevX and prevTcpPanelY and prevTcpWidth then
        if func.trackParametersChanged(currVisibleTracks, prevVisibleTracks) 
            or x ~= prevX 
            or tcpPanelY ~= prevTcpPanelY
            or tcpWidth ~= prevTcpWidth then
            window:close()
            close_1 = true
            return -- выходим из функции, чтобы прекратить цикл
        end
    end
    
    prevVisibleTracks = currVisibleTracks
    prevX, prevTcpPanelY, prevTcpWidth = x, tcpPanelY, tcpWidth
    
    reaper.defer(main) -- перезапускаем функцию
end



main() -- начальный запуск


        --[[
        if hasSidechainInputs(track_under_cursor, i) then
            hbox_send:remove(button_circ)
            local meter = VolumeMeter{w = 15}
            hbox_send:add(meter)
            table.insert(meters, meter)  -- Добавляем индикатор в список
            meter.onmouseenter=function(self, event)
                meter:attr('border','red')
                return true
            end
            meter.onmouseleave=function(self, event)
                meter:attr('border',false)
                return true
            end
        end
        window.onupdate = function()
            for _, meter in ipairs(meters) do
                meter:set_from_track(track_under_cursor)
            end
        end
        ]]