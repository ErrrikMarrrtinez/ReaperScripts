-- @description Fast sidechain from selected tracks to track under mouse
-- @author mrtnz
-- @version 1.0.21
-- @about
--   This script provides:
--   
--   - Quick sidechain routing from selected tracks to the track under the mouse.
--   - Default setup of a 3/4 sidechain with corresponding 3/4 L\R pins for input.
--   
--   Usage:
--   
--   1. Select multiple tracks.
--   2. Hover over a target track.
--   3. A window will display available plugins.
--   4. Click "Create New Channel" after selecting a plugin to auto-create the next available send. For instance, if 3/4 is occupied, it will select 5/6, and if 5/6 is occupied, it will select 7/8, and so on.
--   5. Clicking "Yes" will route the send to the current sidechain pins of the selected plugin.
--   
--   Language Support:
--   
--   - English and Russian.
--   - Toggle language by changing "local language = 'eng'" to 'ru' for Russian.
-- @changelog
--   Bug fix: Library search error 2
-- @provides
--   ../libs/rtk.lua


local language = 'eng' --eng or ru






local script_path = string.match(({reaper.get_action_context()})[2], "(.-)([^\\/]-%.?([^%.\\/]*))$")
package.path = package.path .. ";" .. script_path .. "../libs/?.lua"
local rtk = require("rtk")





function main()
    function setSidechainPins(track, fxnumber, value)
        local numOfChannels = math.min(reaper.GetMediaTrackInfo_Value(track, "I_NCHAN"), 32)
        local retval, inputPins, outputPins = reaper.TrackFX_GetIOSize(track, fxnumber)
        
        for pin = 0, inputPins-1 do
            if pin == 2 or pin == 3 then
                local low32bits, hi32bits = reaper.TrackFX_GetPinMappings(track, fxnumber, 0, pin)
                if low32bits ~= 0 then
                    reaper.TrackFX_SetPinMappings(track, fxnumber, 0, pin, 2^(pin + value), 0)
                end
            end
        end
    
        for pin = 0, outputPins-1 do
            if pin == 2 or pin == 3 then
                local low32bits, hi32bits = reaper.TrackFX_GetPinMappings(track, fxnumber, 1, pin)
                if low32bits ~= 0 then
                    reaper.TrackFX_SetPinMappings(track, fxnumber, 1, pin, 2^(pin + value), 0)
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
    
    function cleanFXName(fx_name)
        local clean_name = fx_name:gsub("^VST3:", "") 
        clean_name = clean_name:gsub("^VST:", "") 
        clean_name = clean_name:gsub("^VSTI:", "") 
        clean_name = clean_name:gsub("^VST3I:", "") 
        clean_name = clean_name:gsub("^JS:", "")
        clean_name = clean_name:gsub(" %(.*%)$", "")
        clean_name = clean_name:gsub("%[.*%]", "")    
        return clean_name
    end
    
    
    
    function getTrackPosAndHeight(track)
      if track then
        local height = reaper.GetMediaTrackInfo_Value(track, "I_WNDH")
        local posy = reaper.GetMediaTrackInfo_Value(track, "I_TCPY")
        return posy, height
      end
    end
    
    function saveWindowSize()
        reaper.SetExtState("vt_window", "width", tostring(wnd.w), true)
        reaper.SetExtState("vt_window", "height", tostring(wnd.h), true)
    end
    
    local track_under_cursor = reaper.BR_TrackAtMouseCursor()
    local fx_names = {}
    
    function tr_undm()
        if track_under_cursor then
            local fx_count = reaper.TrackFX_GetCount(track_under_cursor)
            for i = 0, fx_count - 1 do
                local retval, fx_name = reaper.TrackFX_GetFXName(track_under_cursor, i, "")
                table.insert(fx_names, fx_name)
            end
        end
    end
    
    
    
    local savedW = tonumber(reaper.GetExtState("vt_window", "width")) or 400
    local savedH = tonumber(reaper.GetExtState("vt_window", "height")) or 310
    local initialW = savedW
    local initialH = savedH
    local scale_2
    main_background_color = "#1a1a1a"
    local stringLength, stringValue = reaper.BR_Win32_GetPrivateProfileString("REAPER", "toppane", "", reaper.get_ini_file())
    if stringLength > 0 then 
       stringValue=stringValue--*3.06
    end
    
    local mouse_x, mouse_y = reaper.GetMousePosition()
    local track = reaper.BR_TrackAtMouseCursor()
    
    if not track then
        if language == 'ru' then
            reaper.ShowMessageBox("Нет трека под курсором. Используйте трек под курсором как целевой трек для отправки в него выбранных треков", "Ошибка", 0)
        else
            reaper.ShowMessageBox("No track under the cursor. Use the track under the cursor as the target track to send the selected tracks to it.", "Error", 0)
        end
        return
    end
    
    local color = reaper.GetTrackColor(track) or "#2a2a2a"
    
    -- Проверка на наличие выбранных треков
    local count_sel_tracks = reaper.CountSelectedTracks(0)
    
    if count_sel_tracks == 0 then
        if language == 'ru' then
            reaper.ShowMessageBox("Нет выбранных треков. Пожалуйста, выберите необходимые треки для отправки в трек под курсором.", "Ошибка", 0)
        else
            reaper.ShowMessageBox("No tracks selected. Please select the necessary tracks to send to the track under the cursor.", "Error", 0)
        end
        return
    end
    
    -- Проверка, не является ли выбранный трек тем же треком, что и трек под курсором
    for i = 0, count_sel_tracks - 1 do
        local sel_track = reaper.GetSelectedTrack(0, i)
        if sel_track == track then
            if language == 'ru' then
                reaper.ShowMessageBox("Выбран тот же трек, что и под курсором!", "Ошибка", 0)
            else
                reaper.ShowMessageBox("The same track is selected as the one under the cursor!", "Error", 0)
            end
            return
        end
    end
    
    -- Оставшийся код
    
    local color = reaper.GetTrackColor(track) or "#2a2a2a"
    
    
    
    local function openRTKWindow(posy, height)
        wnd = rtk.Window{
            x = mouse_x-initialW/2,
            y = mouse_y, 
            w = initialW,
            h = initialH,
            title = 'Fast sidechain',
            bg = color ,
            resizable=true,
            opacity=0.95,
            borderless=true,
        }
            wnd:open()
            v_box=wnd:add(rtk.VBox{})
            local hbox=v_box:add(rtk.HBox{bg='#2a2a2a'})
            local label_icon = hbox:add(rtk.Text{border='gray',y=5,x=5,font='Arial','⛓',})
            
            local title_text = (language == 'ru') and 'Быстрый сайдчейн' or 'Fast sidechain'
            
            local label_name = hbox:add(rtk.Text{spacing=25,x=8,tpadding=6,font='Comic Sans MS', title_text})
            
            hbox:add(rtk.Box.FLEXSPACE)
            local close_button = hbox:add(rtk.Button{rpadding=2,halign='center',w=30,h=30,flat=true,'✕'})
            close_button.onclick=function()
                wnd:close()
            end
        end
    
    reaper.BR_GetMouseCursorContext()
    local track_under_cursor = reaper.BR_GetMouseCursorContext_Track()
    
    if track_under_cursor then
      local posy, height = getTrackPosAndHeight(track_under_cursor)
      if posy and height then
        openRTKWindow(posy, height)
      end
    end
    wnd.onresize = function(self, w, h)
        scale_2 = math.min(w / initialW, h / initialH)
        rtk.scale.user = scale_2
        self:reflow()
        saveWindowSize() 
    end
    
    
    local v_box = v_box:add(rtk.VBox{expand=1,spacing=2,padding=6})
    
    
    
    tr_undm()
    
    
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
    for i, fx_name in ipairs(fx_names) do
        local currentPin = getCurrentFXPins(track_under_cursor, i - 1)
        local currentChannel = currentPin or findFreeDestChannel(track_under_cursor)
        local pinString = currentPin and (" (" .. tostring(math.floor(currentChannel)) .. "/" .. tostring(math.floor(currentChannel + 1)) .. ")") or ""
        local cleaned_fx_name_with_pins = cleanFXName(fx_name) .. pinString
        
        local button = v_box:add(rtk.Button{
        flat=true,
        border='#2a2a2a',
        label=cleaned_fx_name_with_pins,
        bg='#3a3a3a',
        --fontscale=1.2,
        halign='center',
        font='Courier New',wrap=true,
        padding=4,
        },
        
        {fillw = true,fillh = true},
        {}
        )
        button.onclick = function(self, event)
            local num_selected_tracks = reaper.CountSelectedTracks(0)
            local currentPin = getCurrentFXPins(track_under_cursor, i - 1)
            local currentChannel = currentPin or findFreeDestChannel(track_under_cursor)
        
            if event.shift then  -- Если зажат Shift
                -- Здесь код, который сейчас выполняет button_no.onclick
                local freeChannel = findFreeDestChannel(track_under_cursor)
                createSend(freeChannel, num_selected_tracks, track_under_cursor, i - 1)
            else  -- Если Shift не зажат
                -- Здесь код, который сейчас выполняет button_yes.onclick
                local freeChannel = currentChannel - 1
                createSend(freeChannel, num_selected_tracks, track_under_cursor, i - 1)
            end
        end
        
        
        function createSend(freeChannel, num_selected_tracks, track_under_cursor, fx_index)
            for sel_idx = 0, num_selected_tracks - 1 do
                local selected_track = reaper.GetSelectedTrack(0, sel_idx)
                if selected_track and selected_track ~= track_under_cursor then
                    reaper.Undo_BeginBlock()
                    local ch_count = reaper.GetMediaTrackInfo_Value(track_under_cursor, 'I_NCHAN')
                    local send = reaper.CreateTrackSend(selected_track, track_under_cursor)
                    --reaper.SetMediaTrackInfo_Value(track_under_cursor, 'I_NCHAN', math.max(4, ch_count))
                    reaper.SetMediaTrackInfo_Value(track_under_cursor, 'I_NCHAN', math.max(freeChannel + 1, ch_count))
                    
                    reaper.SetTrackSendInfo_Value(selected_track, 0, send, 'I_SENDMODE', 3)
                    reaper.SetTrackSendInfo_Value(selected_track, 0, send, 'I_DSTCHAN', freeChannel)
                    reaper.SetTrackSendInfo_Value(selected_track, 0, send, 'I_MIDIFLAGS', 4177951)
        
                    setSidechainPins(track_under_cursor, fx_index, freeChannel - 2)
                        
                    reaper.Undo_EndBlock("Create send to track under cursor", -1)
                end
            end
            wnd:close()
        end
            
        
        
    end
    wnd:open()
end


local function init(attempts)
    local ok
    ok, rtk = pcall(function() return require('rtk') end)
    if ok then
        
        return main()
    end
    local installmsg = 'Visit https://reapertoolkit.dev for installation instructions.'
        if not attempts then
            if not reaper.ReaPack_AddSetRepository then
                return reaper.MB(
                    'This script requires the REAPER Toolkit ReaPack. ' .. installmsg,
                    'Missing Library',
                    0 
                )
            end
            local response = reaper.MB(
                'This script requires the REAPER Toolkit ReaPack. Would you like to automatically install it?',
                'Automatically install REAPER Toolkit ReaPack?',
                4 
            )
            if response ~= 6 then
                return reaper.MB(installmsg, 'Automatic Installation Refused', 0)
            end
            local ok, err = reaper.ReaPack_AddSetRepository('rtk', 'https://reapertoolkit.dev/index.xml', true, 1)
            if not ok then
                return reaper.MB(
                    string.format('Automatic install failed: %s.\n\n%s', err, installmsg),
                    'ReaPack installation failed',
                    0 
                )
            end
            reaper.ReaPack_ProcessQueue(true)
        elseif attempts > 150 then
            return reaper.MB(
                'Installation took too long. Assuming a ReaPack error occurred and giving up. ' .. installmsg,
                'ReaPack installation failed',
                0 
            )
        end
        reaper.defer(function() init((attempts or 0) + 1) end)
end
init()
