-- @description MVarious
-- @author mrtnz
-- @about Functions and various for my scripts.
-- @version 1.22
-- @provides
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
--   ../images/leg.png
--   ../images/link.png
--   ../images/link2.png
--   ../images/loop.png
--   ../images/oct.png
--   ../images/off.png
--   ../images/on.png
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
--   ../images/tab.png
--   ../images/tr.png
--   ../images/up-and-down.png
--   ../images/up.png
--   ../images/sawdown.png
--   ../images/sawup.png
--   ../images/aup.png
--   ../images/adown.png
--   ../images/chance.png
--   ../images/on_on.png
--    rtk.lua
--    Widgets.lua
--    Window.lua
local M = {}
local rpr=reaper


CLASS_TCPDISPLAY = "REAPERTCPDisplay"

function M.GetTCPWidth()
  local tcp_hwnd = M.FindChildByClass(reaper.GetMainHwnd(), 'REAPERTCPDisplay', 1)
  if tcp_hwnd then
    local _, _, w, _ = M.GetClientBounds(tcp_hwnd)
    return w
  end
  return nil
end

function M.getClientBounds(hwnd)
    local ret, left, top, right, bottom = reaper.JS_Window_GetClientRect(hwnd)
    local height = bottom - top
    if reaper.GetOS() == "OSX" then height = top - bottom end
    return left, top, right-left, height
end

function M.getAllChildWindows(hwnd)
    local arr = rpr.new_array({}, 255)
    rpr.JS_Window_ArrayAllChild(hwnd, arr)
    return arr.table()
end

function M.FindChildByClass(hwnd, classname, occurrence)
    local adr = M.getAllChildWindows(hwnd)
    for _, address in ipairs(adr) do
        local hwnd = rpr.JS_Window_HandleFromAddress(address) 
        if rpr.JS_Window_GetClassName(hwnd) == classname then
            occurrence = occurrence - 1
            if occurrence == 0 then
                return hwnd
            end
        end
    end
end

function M.getTCPTopPanelProperties()
    local tcp_hwnd = M.FindChildByClass(rpr.GetMainHwnd(), "REAPERTCPDisplay", 1) 
    if tcp_hwnd then
        local x,y,w,h = M.getClientBounds(tcp_hwnd)
        return tcp_hwnd, x, y, w, h
    end
    return nil, -1, -1, -1, -1
end

function M.getMainWndDimensions()
    local hwnd = reaper.GetMainHwnd() 
    return M.getClientBounds(hwnd)  
end


function M.getTrackPosAndHeight(track)
  local height = rpr.GetMediaTrackInfo_Value(track, "I_WNDH")
  local posy = rpr.GetMediaTrackInfo_Value(track, "I_TCPY")
  return posy, height
end

function M.getLastTCPTrackBinary(tcpheight)
  local numtracks = rpr.CountTracks(CURR_PROJ)
  if numtracks == 0 then return nil, 0 end
  local track = rpr.GetTrack(CURR_PROJ, numtracks-1)
  local posy, _ = M.getTrackPosAndHeight(track)
  if posy < tcpheight then return track, numtracks end
  local left, right = 0, numtracks - 1
  while left <= right do
    local index = math.floor((left + right) / 2)
    local track = rpr.GetTrack(CURR_PROJ, index)
    local posy, height = M.getTrackPosAndHeight(track)
    if posy < tcpheight then
      if posy + height >= tcpheight then return track, index + 1 end
      left = index + 1
    elseif posy > tcpheight then
      right = index - 1
    else
      local track = rpr.GetTrack(CURR_PROJ, index - 1)
      return track, index
    end
  end
  return nil, 0
end

function M.getFirstTCPTrackBinary()
  local fixForMasterTCPgap = false
  if rpr.GetMasterTrackVisibility() & 0x1 == 1 then
    local master = rpr.GetMasterTrack(CURR_PROJ)
    local posy, height = M.getTrackPosAndHeight(master)
    if height + posy > 0 then return master, 0 end
    if height + posy + MFXlist.MASTER_GAP >= 0 then fixForMasterTCPgap = true end
  end
  local numtracks = rpr.CountTracks(CURR_PROJ)
  if numtracks == 0 then return nil, -1 end
  if fixForMasterTCPgap then
    local track = rpr.GetTrack(CURR_PROJ, 0)
    return track, 1
  end
  local left, right = 0, numtracks - 1
  while left <= right do
    local index = math.floor((left + right) / 2)
    local track = rpr.GetTrack(CURR_PROJ, index)
    local posy, height = M.getTrackPosAndHeight(track)
    if posy < 0 then
      if posy + height > 0 then return track, index + 1 end
      left = index + 1
    elseif posy > 0 then
      right = index - 1
    else
      return track, index + 1
    end      
  end
  return nil, -1
end

function M.getLastTCPTrackLinear(tcpheight, firsttrack)
  local numtracks = rpr.CountTracks(CURR_PROJ)
  if numtracks == 0 then return nil, 0 end
  local track = rpr.GetTrack(CURR_PROJ, numtracks-1)
  local posy, _ = M.getTrackPosAndHeight(track)
  if posy < tcpheight then return track, numtracks end
  for i = firsttrack, numtracks do
    local track = rpr.GetTrack(CURR_PROJ, i-1)
    local posy, height = M.getTrackPosAndHeight(track)
    if posy + height > tcpheight then return track, i end
  end
end

function M.collectVisibleTracks()
    local _, y, _, h = M.getMainWndDimensions()
    local new_y = y/2 + h
    local firstTrack, findex = M.getFirstTCPTrackBinary()
    local lastTrack, lindex = M.getLastTCPTrackBinary(new_y)
    local vistracks = {}

    if findex < 0 then return vistracks end

    for i = findex, lindex do
        local track = reaper.GetTrack(0, i-1)
        local posy, trackHeight = M.getTrackPosAndHeight(track)
        
        if posy < 0 then
            trackHeight = trackHeight + posy
            posy = 0
        elseif posy + trackHeight > new_y then
            trackHeight = new_y - posy
        end

        if (posy + trackHeight > 0 and posy < new_y) then
            local trinfo = {
                track = track,
                posy = posy,
                height = trackHeight
            }
            table.insert(vistracks, trinfo)
        end
    end
    return vistracks
end

function M.setTrackHeight(track, height)
  reaper.SetMediaTrackInfo_Value(track, "I_HEIGHTOVERRIDE", height)
  reaper.TrackList_AdjustWindows(false) -- обновляем окно с треками
end


function M.updateButtonIndices(vbox, fx_count)
  for i = 0, fx_count - 1 do
      local hbox = vbox:get_child(i + 1)
      local button = hbox:get_child(1)
      button.currentIndex = i
  end
end



function M.trackParametersChanged(newTracks, prevTracks)
    if #newTracks ~= #prevTracks then return true end
    for i, trackInfo in ipairs(newTracks) do
        local prevTrackInfo = prevTracks[i]
        if trackInfo.posy ~= prevTrackInfo.posy or
           trackInfo.height ~= prevTrackInfo.height then
           return true
        end
    end
    return false
end

function M.trimFXName(fxName, tcpWidth)
  fxName = fxName:match("^%s*(.-)%s*$") 
  
  fxName = fxName:gsub("^VST3?: ", "")
  fxName = fxName:gsub("^VST3?I: ", "")
  fxName = fxName:gsub("^JS: ", "")
  fxName = fxName:gsub("^CLAP: ", "")
  fxName = fxName:gsub(" %b()", "")

  if tcpWidth < 150 then
    fxName = fxName:gsub("[aeiouyAEIOUYаеёиоуыэюяАЕЁИОУЫЭЮЯ]", "")
  end

  return fxName
end

function M.makeDarker(color, amount)
  local r, g, b = color:match("#(%x%x)(%x%x)(%x%x)")
  r = math.floor(math.max(0, tonumber(r, 16) * (1 - amount)))
  g = math.floor(math.max(0, tonumber(g, 16) * (1 - amount)))
  b = math.floor(math.max(0, tonumber(b, 16) * (1 - amount)))
  return string.format("#%02x%02x%02x", r, g, b)
end

function M.GetWetFx(track, fx)
  local six_thirtyseven = reaper.APIExists("TakeFX_GetParamFromIdent")
  local wetparam = six_thirtyseven and reaper.TrackFX_GetParamFromIdent(track, fx, ":wet") or reaper.TrackFX_GetNumParams(track, fx) - 1
  local val = reaper.TrackFX_GetParam(track, fx, wetparam)
  return math.floor(val * 100 + 0.5)
end

function M.SetWetFx(track, fx, value)
  local six_thirtyseven = reaper.APIExists("TakeFX_GetParamFromIdent")
  local wetparam = six_thirtyseven and reaper.TrackFX_GetParamFromIdent(track, fx, ":wet") or reaper.TrackFX_GetNumParams(track, fx) - 1
  reaper.TrackFX_SetParam(track, fx, wetparam, value / 100)
end

function M.msg(message)
  reaper.ClearConsole()
  reaper.ShowConsoleMsg(tostring(message) .. "\n")
end
function M.mousewheel(self, event, mod)
  local _, _, _, wheel_y = tostring(event):find("wheel=(%d+.?%d*),(-?%d+.?%d*)")
  local c_val = tonumber(wheel_y) > 0 and self.value - self.step-mod or self.value + self.step+mod
  self:attr('value', math.max(self.min, math.min(self.max, c_val)))
  return true
end
function M.cursor_checker(window, focusObject)
  keepRunning = window.in_window 
  if keepRunning then 
      focusObject:focus()
      reaper.defer(function() defer(window, focusObject) end)
  else return
  end
  --window.onclose = function(self, event) keepRunning = false return end
end
--[[

local function get_receive_info(target_track)
    local target_track_idx = reaper.GetMediaTrackInfo_Value(target_track, "IP_TRACKNUMBER")
    local num_tracks = reaper.CountTracks(0)
    local info_str = ""

    for i = 0, num_tracks - 1 do
        local track = reaper.GetTrack(0, i)
        local num_sends = reaper.GetTrackNumSends(track, 0)

        for j = 0, num_sends - 1 do
            local dest_track = reaper.BR_GetMediaTrackSendInfo_Track(track, 0, j, 1)
            local dest_track_idx = reaper.GetMediaTrackInfo_Value(dest_track, "IP_TRACKNUMBER")

            if dest_track_idx == target_track_idx then
                -- Этот трек посылает сигнал в целевой трек
                local src_chan = reaper.GetTrackSendInfo_Value(track, 0, j, "I_SRCCHAN") + 1
                local dest_chan = reaper.GetTrackSendInfo_Value(track, 0, j, "I_DSTCHAN") + 1
                local volume = reaper.GetTrackSendInfo_Value(track, 0, j, "D_VOL")
                local volume_dB = 20 * math.log(volume, 10)
                local pan = reaper.GetTrackSendInfo_Value(track, 0, j, "D_PAN")
                
                info_str = info_str .. string.format("From Track %d: audio: %d/%d > %d/%d Pre-Fader(Post-fx), value %.2f dB, pan value %.2f%% L\n",
                                                     i+1, src_chan, dest_chan, src_chan, dest_chan, volume_dB, pan*100)
            end
        end
    end

    return info_str1
end

local function get_send_info(track)
    local num_sends = reaper.GetTrackNumSends(track, 0)
    if num_sends == 0 then return "No sends found for this track." end
    
    local info_str = ""
    
    for i = 0, num_sends - 1 do
        local dest_track = reaper.BR_GetMediaTrackSendInfo_Track(track, 0, i, 1)  -- получаем трек-получатель
        local dest_track_idx = reaper.GetMediaTrackInfo_Value(dest_track, "IP_TRACKNUMBER")
        
        local src_chan = reaper.GetTrackSendInfo_Value(track, 0, i, "I_SRCCHAN") + 1
        local dest_chan = reaper.GetTrackSendInfo_Value(track, 0, i, "I_DSTCHAN") + 1
        
        local volume = reaper.GetTrackSendInfo_Value(track, 0, i, "D_VOL")
        local volume_dB = 20 * math.log(volume, 10)
        
        local pan = reaper.GetTrackSendInfo_Value(track, 0, i, "D_PAN")
        
        local midi_src_chan = reaper.GetTrackSendInfo_Value(track, 0, i, "I_MIDIFLAGS") & 0x0F
        local midi_dest_chan = (reaper.GetTrackSendInfo_Value(track, 0, i, "I_MIDIFLAGS") & 0xF0) >> 4
        
        info_str = info_str .. string.format("Track %d: audio: %d/%d > %d/%d Pre-Fader(Post-fx), value %.2f dB, pan value %.2f%% L midi > %d/%d\n",
                                             dest_track_idx, src_chan, dest_chan, src_chan, dest_chan, volume_dB, pan*100, midi_src_chan, midi_dest_chan)
    end
    
    return info_str
end
local function modify_send_params(track, send_idx, param, value)
    if param == "volume" then
        local volume = math.exp(value / 20 * math.log(10))
        reaper.SetTrackSendInfo_Value(track, 0, send_idx, "D_VOL", volume)
    elseif param == "pan" then
        reaper.SetTrackSendInfo_Value(track, 0, send_idx, "D_PAN", value / 100)
    elseif param == "src_chan" then
        reaper.SetTrackSendInfo_Value(track, 0, send_idx, "I_SRCCHAN", value - 1)
    elseif param == "dest_chan" then
        reaper.SetTrackSendInfo_Value(track, 0, send_idx, "I_DSTCHAN", value - 1)
    elseif param == "midi_src_chan" then
        local flags = reaper.GetTrackSendInfo_Value(track, 0, send_idx, "I_MIDIFLAGS")
        flags = (flags & 0xF0) | (value & 0x0F)
        reaper.SetTrackSendInfo_Value(track, 0, send_idx, "I_MIDIFLAGS", flags)
    elseif param == "midi_dest_chan" then
        local flags = reaper.GetTrackSendInfo_Value(track, 0, send_idx, "I_MIDIFLAGS")
        flags = (flags & 0x0F) | ((value << 4) & 0xF0)
        reaper.SetTrackSendInfo_Value(track, 0, send_idx, "I_MIDIFLAGS", flags)
    end
end

local send_idx = 2 -- индекс send (начиная с 0)
local param = "pan" -- какой параметр изменить ("volume", "pan", "src_chan", "dest_chan", "midi_src_chan", "midi_dest_chan")
local value = -20 -- на какое значение изменить параметр

modify_send_params(track_under_cursor, send_idx, "src_chan", 1)  -- 1/2 канал источника
modify_send_params(track_under_cursor, send_idx, "dest_chan", 3)  -- 3/4 канал назначения



local send_info = get_send_info(track_under_cursor)
]]
--[[
func.msg(send_info)
local receive_info = get_receive_info(track_under_cursor)

func.msg("Receives:\n" .. receive_info)]]
reaper.atexit(function() reaper.defer(function() end) end)
return M