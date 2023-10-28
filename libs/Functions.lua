-- @description MVarious
-- @author mrtnz
-- @about Functions and various for my scripts.
-- @version 1.1
-- @provides
--    rtk.lua
--    Widgets.lua
--    Window.lua
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


return M