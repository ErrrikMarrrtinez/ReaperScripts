-- @noindex

local r = reaper
package.path = package.path .. ";" .. string.match(({r.get_action_context()})[2], "(.-)([^\\/]-%.?([^%.\\/]*))$") .. "?.lua"

local json = require "json"
require "rtk"
local func = {}

local script_path = ({r.get_action_context()})[2]:match("(.*[/\\])")
local USE_SELECTION_MODE = true


function func.formatDate()
  local current_time = os.date("*t")
  local months = {"Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"}
  local year_short = current_time.year % 100
  local formatted_time = string.format("%02d %s, %02d %02d:%02d", 
                                       current_time.day, 
                                       months[current_time.month], 
                                       year_short, 
                                       current_time.hour, 
                                       current_time.min)
  return formatted_time
end

function func.openActionListWithSearch(searchText)
  r.ShowActionList()
  local hwnd = r.JS_Window_Find("Actions", true)
  if not hwnd then return end
  local search_edit = r.JS_Window_FindChildByID(hwnd, 1324)
  if not search_edit then return end
  r.JS_Window_SetTitle(search_edit, searchText)
  r.JS_Window_SetFocus(search_edit)
end

function func.createScript(index)
    local name = 'mrtnz_Track View slot '
    local script_template = [[
package.path = package.path .. ";" .. string.match(({reaper.get_action_context()})[2], "(.-)([^\\/]-%%.?([^%%.\\/]*))$") .. "?.lua"
local f = require "functions"
f.restoreVisibleTracksSnapshot(%d)
]]
    local filename = name .. string.format("%d.lua", index)
    local filepath = script_path .. filename
    local file = io.open(filepath, "w")
    if file then
        file:write(script_template:format(index))
        file:close()
        r.AddRemoveReaScript(true, 0, filepath, true)
        func.openActionListWithSearch(name)
        r.RefreshToolbar2(0, 0)
        
        return true
    end
    return false
end

function func.scrollTrackToTop(track)
  local track_tcpy = r.GetMediaTrackInfo_Value(track, "I_TCPY")
  local mainHWND = r.GetMainHwnd()
  local windowHWND = r.JS_Window_FindChildByID(mainHWND, 1000)
  r.JS_Window_SetScrollPos(windowHWND, "v", track_tcpy)
  r.TrackList_AdjustWindows(true)
  r.TrackList_AdjustWindows(false)
end

function func.restoreVisibleTracksSnapshot(index)
  local retval, encoded_data = r.GetProjExtState(0, "VisibleTracksSnapshot", "data_" .. index)
  if retval ~= 1 then
    return "No data found for slot " .. index
  end

  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)
  r.UpdateArrange()
  
  -- Декодируем данные
  local data = json.decode(encoded_data)
  local all_tracks = {}
  local first_track = nil
  
  -- Собираем информацию о треках, как в main_loader
  if data and data.tracks then
    for guid, track_info in pairs(data.tracks) do
      all_tracks[guid] = track_info
    end
  end
  
  -- Найдем первый видимый трек
  if data and data.first_visible then
    first_track = r.BR_GetMediaTrackByGUID(0, data.first_visible.guid)
  end
  
  -- Применяем изменения ко всем трекам
  local track_count = r.CountTracks(0)
  local hideAllTracks = data and data.hideAllTracks
  
  if hideAllTracks then
    -- Сначала скрываем все треки, если нужно
    for i = 0, track_count - 1 do
      local track = r.GetTrack(0, i)
      r.SetMediaTrackInfo_Value(track, "B_SHOWINTCP", 0)
    end
  end
  
  -- Затем показываем нужные треки
  for guid, track_info in pairs(all_tracks) do
    local track = r.BR_GetMediaTrackByGUID(0, guid)
    if track then
      r.SetMediaTrackInfo_Value(track, "B_SHOWINTCP", 1)
      r.SetMediaTrackInfo_Value(track, "I_HEIGHTOVERRIDE", track_info.height)
    end
  end
  
  -- Обновляем интерфейс и завершаем операцию
  r.TrackList_AdjustWindows(false)
  r.TrackList_UpdateAllExternalSurfaces()
  r.PreventUIRefresh(-1)
  r.UpdateArrange()
  r.Undo_EndBlock("Restore visible tracks snapshot " .. index, -1)
  
  if first_track then
    rtk.callafter(0.3, function()
      r.PreventUIRefresh(1)
      -- Гарантируем, что трек виден
      r.SetMediaTrackInfo_Value(first_track, "B_SHOWINTCP", 1)
      
      -- Скроллинг с дополнительными обновлениями
      func.scrollTrackToTop(first_track)
      r.UpdateArrange()
      r.TrackList_AdjustWindows(false)
      r.TrackList_AdjustWindows(true)
      r.PreventUIRefresh(-1)
      
      -- Повторный скроллинг для надежности
      rtk.callafter(0.1, function()
        func.scrollTrackToTop(first_track)
      end)
    end)
  else
    r.TrackList_AdjustWindows(true)
  end
  
  return nil
end

function func.createHeader(container)
    local header = container:add(rtk.Container{bg='#f6f6f6', cell={fillw=true}, h=31})
    local hb_header = header:add(rtk.HBox{lmargin=5, padding=3}, fills)
    rtk.themes['light']['button_normal_border_mul']=0
    hb_header:add(rtk.Text{font='Arial', valign='center', h=1, fontsize=15, color='black', '☰'}, {spacing=6})
    hb_header:add(rtk.Text{font='Arial', valign='center', h=1, fontsize=15, color='black', rtk.window.title})
    hb_header:add(rtk.Button{
        cell={halign='right', expand=1},
        flat=true, color='red',
        halign='center',
        alpha=0.7,
        cursor=rtk.mouse.cursors.HAND,
        w=27, h=1, fontsize=14,
        rpadding=2.5,
        x=5,
        textcolor='white', textcolor2='black', '❌'
    }).onclick=function(self,event)
        rtk.quit()
    end
end

function func.createHeaderTab(main_vbox)
    local hb_top = main_vbox:add(rtk.HBox{spacing=1, padding=-2})
    local b_header = hb_top:add(rtk.Text{x=5, valign='center', padding=4, fontsize=15, 'Slot name'})
    hb_top:add(rtk.Text{spacing=-2, textalign='center', w=40, wrap=true, x=5, fontsize=15, 'Show only'})

    hb_top:add(rtk.Spacer{w=43})

    return b_header
end

function func.getTrackInfo(track)
  local guid = r.GetTrackGUID(track)
  local height = r.GetMediaTrackInfo_Value(track, "I_TCPH")
  local y = r.GetMediaTrackInfo_Value(track, "I_TCPY")
  return {guid = guid, height = height, y = y}
end

function func.getClientBounds(hwnd)
  local _, left, top, right, bottom = r.JS_Window_GetClientRect(hwnd)
  local height = bottom - top
  if r.GetOS():match("^OSX") then height = top - bottom end
  return left, top, right-left, height
end

function func.saveVisibleTracks(index)
  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)
  local visible_tracks = {}
  local first_visible_track = nil

  if USE_SELECTION_MODE then
    -- Режим выбора определенных треков
    local selected_track_count = r.CountSelectedTracks(0)
    for i = 0, selected_track_count - 1 do
      local track = r.GetSelectedTrack(0, i)
      local track_info = func.getTrackInfo(track)
      visible_tracks[track_info.guid] = track_info
      if not first_visible_track or track_info.y < first_visible_track.y then
        first_visible_track = track_info
      end
    end
  else
    -- Текущий режим (поиск по высоте)
    local _, _, _, tcp_height = func.getClientBounds(r.JS_Window_FindChildByID(r.GetMainHwnd(), 1000))
    local first_selected_track = r.GetSelectedTrack(0, 0)
    if first_selected_track then
      first_visible_track = func.getTrackInfo(first_selected_track)
      visible_tracks[first_visible_track.guid] = first_visible_track
      local track_count = r.CountTracks(0)
      for i = r.GetMediaTrackInfo_Value(first_selected_track, "IP_TRACKNUMBER"), track_count do
        local track = r.GetTrack(0, i-1)
        if r.GetMediaTrackInfo_Value(track, "B_SHOWINTCP") == 1 then
          local track_info = func.getTrackInfo(track)
          if track_info.y >= tcp_height then break end
          visible_tracks[track_info.guid] = track_info
        end
      end
    end
  end

  local data_to_save = {
    first_visible = first_visible_track,
    tracks = visible_tracks
  }
  local encoded_data = json.encode(data_to_save)
  r.SetProjExtState(0, "VisibleTracksSnapshot", "data_" .. index, encoded_data)
  r.PreventUIRefresh(-1)
  r.UpdateArrange()
  r.Undo_EndBlock("Save visible tracks snapshot", -1)
end

function func.setAllVisibleTracks()
    local track_count = r.CountTracks(0)
    for i = 0, track_count - 1 do
      local track = r.GetTrack(0, i)
      
      r.SetMediaTrackInfo_Value(track, "B_SHOWINTCP", 1)
      
      if track then
        r.SetMediaTrackInfo_Value(track, "B_SHOWINTCP", 1)
        r.SetMediaTrackInfo_Value(track, "I_HEIGHTOVERRIDE", 50)
      end

      if i == 0 then
        func.scrollTrackToTop(track)
      end
    end

    
    r.TrackList_AdjustWindows(false)
end

function func.restoreVisibleTracks(encoded_data)
  r.PreventUIRefresh(1)

  local data = json.decode(encoded_data)
  local isEmpty = not data or not data.name or data.name == ""
  if data.hideAllTracks and not isEmpty then
    local track_count = r.CountTracks(0)
    for i = 0, track_count - 1 do
      local track = r.GetTrack(0, i)
      r.SetMediaTrackInfo_Value(track, "B_SHOWINTCP", 0)
    end
    r.TrackList_AdjustWindows(false)
  end

  if data.tracks then
    for guid, track_info in pairs(data.tracks) do
      local track = r.BR_GetMediaTrackByGUID(0, guid)
      if track then
        r.SetMediaTrackInfo_Value(track, "B_SHOWINTCP", 1)
        r.SetMediaTrackInfo_Value(track, "I_HEIGHTOVERRIDE", track_info.height)
      end
    end
  end

  if data.first_visible then
    return r.BR_GetMediaTrackByGUID(0, data.first_visible.guid)
  end
end

function func.main_loader(selected_slots)
  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)
  r.UpdateArrange()
  
  local first_tracks = {}
  local all_tracks = {}
  local lowest_track_number = 999999 -- Большое число для начального сравнения
  local top_track = nil

  -- Сначала собираем данные со всех слотов
  for index in pairs(selected_slots) do
    local retval, encoded_data = r.GetProjExtState(0, "VisibleTracksSnapshot", "data_" .. index)
    if retval ~= 0 then
      local data = json.decode(encoded_data)
      if data.tracks then
        for guid, track_info in pairs(data.tracks) do
          all_tracks[guid] = track_info
        end
      end
      if data.first_visible then
        local first_track = r.BR_GetMediaTrackByGUID(0, data.first_visible.guid)
        if first_track then
          table.insert(first_tracks, first_track)
          
          -- Сразу находим трек с наименьшим номером
          local track_number = r.GetMediaTrackInfo_Value(first_track, "IP_TRACKNUMBER")
          if track_number < lowest_track_number then
            lowest_track_number = track_number
            top_track = first_track
          end
        end
      end
    end
  end

  -- Теперь применяем изменения один раз
  local track_count = r.CountTracks(0)
  for i = 0, track_count - 1 do
    local track = r.GetTrack(0, i)
    local guid = r.GetTrackGUID(track)
    if all_tracks[guid] then
      r.SetMediaTrackInfo_Value(track, "B_SHOWINTCP", 1)
      r.SetMediaTrackInfo_Value(track, "I_HEIGHTOVERRIDE", all_tracks[guid].height)
    else
      r.SetMediaTrackInfo_Value(track, "B_SHOWINTCP", 0)
    end
  end

  -- Принудительно обновляем интерфейс
  r.TrackList_AdjustWindows(false)
  r.TrackList_UpdateAllExternalSurfaces()
  r.UpdateArrange()
  r.PreventUIRefresh(-1)
  r.Undo_EndBlock("Restore visible tracks snapshot", -1)

  -- Улучшенный скроллинг: сначала скроллим с большой задержкой
  if top_track then
    -- Первый скроллинг с большой задержкой
    rtk.callafter(0.3, function()
      r.PreventUIRefresh(1)
      
      -- Дополнительная проверка, чтобы top_track был виден
      r.SetMediaTrackInfo_Value(top_track, "B_SHOWINTCP", 1)
      
      -- Принудительное обновление перед скроллингом
      r.UpdateArrange()
      r.TrackList_AdjustWindows(false)
      
      -- Скролл к самому верхнему треку
      func.scrollTrackToTop(top_track)
      
      -- Повторное обновление после скроллинга
      r.UpdateArrange()
      r.TrackList_AdjustWindows(false)
      r.TrackList_AdjustWindows(true)
      r.PreventUIRefresh(-1)
      
      -- Второй скроллинг для надежности после небольшой задержки
      rtk.callafter(0.1, function()
        r.PreventUIRefresh(1)
        func.scrollTrackToTop(top_track)
        r.UpdateArrange()
        r.TrackList_AdjustWindows(false)
        r.TrackList_AdjustWindows(true)
        r.PreventUIRefresh(-1)
      end)
    end)
  else
    r.TrackList_AdjustWindows(true)
  end
end

function func.saveSlotData(index, name, checkboxState)
  local retval, encoded_data = r.GetProjExtState(0, "VisibleTracksSnapshot", "data_" .. index)
  if retval == 0 or encoded_data == "" then
    return
  end
  local data = json.decode(encoded_data) or {}

  data.name = (name and name ~= "" and name ~= false) and name or (data.name and data.name ~= "" and data.name ~= false) and data.name or func.formatDate()

  data.hideAllTracks = checkboxState ~= nil and checkboxState or data.hideAllTracks

  local encoded_data = json.encode(data)
  r.SetProjExtState(0, "VisibleTracksSnapshot", "data_" .. index, encoded_data)
end

function func.loadSlotData(index)
  local retval, encoded_data = r.GetProjExtState(0, "VisibleTracksSnapshot", "data_" .. index)
  if retval == 1 then
    --print(encoded_data)
    return json.decode(encoded_data)
  end
  return nil
end

function func.updateButtonAppearance(button, index, slotData, hbox)
  local isEmpty = not slotData or not slotData.name or slotData.name == ""
  button:attr('textcolor', isEmpty and 'gray' or 'white')
  button:attr('textcolor2', isEmpty and 'gray' or 'white')
  button:attr('label', isEmpty and ('Slot ' .. index) or '(' .. index..') '..slotData.name)
end

function func.hoverHbox(hbox)
  if hbox then
    local col = '#4a4a4a'
    local current_border = hbox.bg
    if hbox.mouseover and current_border ~= col then
      hbox:attr('bg', col)
    elseif not hbox.mouseover and current_border == col then
      hbox:attr('bg', '#2a2a2a')
    end
    rtk.defer(hoverHbox, hbox)
  end
end

function func.isInteger(str)
  if type(str) == 'string' or type(str) == 'number' then
    return not (str == "" or str:find("%D"))
  end
end

function func.shift(color, hue, sat, val)
  local hue, sat, val = hue or 1, sat or 1, val or 1
  
  local h, s, l, a = rtk.color.hsl(color)
  h = (h + hue) % 1
  s = rtk.clamp(s * sat, 0, 1)
  l = rtk.clamp(l * val, 0, 1)
  local r, g, b = rtk.color.hsl2rgb(h, s, l)

  return rtk.color.rgba2hex(r, g, b, a)
end

function func.closeAfterDelay(delay)
  rtk.callafter(delay, rtk.quit)
end

return func