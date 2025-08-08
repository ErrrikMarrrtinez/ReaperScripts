--@noindex 
--NoIndex: true

local r = reaper
local script_path = debug.getinfo(1, "S").source:match("@(.*[\\/])")

local imgui_path = r.ImGui_GetBuiltinPath()..'/?.lua'
package.path = imgui_path..";"..script_path..'?.lua'
local f = require('mrtnz_utils')

local im = require 'imgui' '0.9.3.3'
local ctx04 = im.CreateContext('Enhanced Notes Manager')
local FLT_MIN, FLT_MAX = im.NumericLimits_Float()
local prj = r.EnumProjects(-1)
local preview = nil
local notes = {}
local current_id = nil
local volume = tonumber(r.GetExtState("NotesManager", "Volume")) or 1
local seek_pos = nil
local play_rate = tonumber(r.GetExtState("NotesManager", "PlayRate")) or 1
local paused_position = nil
local is_playing = false
local show_delete_confirm = false
local delete_target_id = nil
local speed_options = {1.0, 1.25, 1.5, 1.75, 2.0}
local current_speed_index = 1
local font = im.CreateFont('sans-serif', 14) -- Основной шрифт
local font_bold = im.CreateFont('sans-serif', 15, im.FontFlags_Bold) -- Жирный шрифт для текста
local styles
local center_x, center_y, width, height
local recording_track_guid = nil
local waveform_cache = {}
im.Attach(ctx04, font)
im.Attach(ctx04, font_bold)

IS_CHILDREN = f.get_parent_project()

function update()
    local rpp_files = f.ScanForRPPFiles()
    for _, file in ipairs(rpp_files) do
        f.UpdateNotesFromSubproject(file.path)
    end
end

function string.trim(s)
    return s:match("^%s*(.-)%s*$")
end

function save_global_settings()
    r.SetExtState("NotesManager", "Volume", tostring(volume), true)
    r.SetExtState("NotesManager", "PlayRate", tostring(play_rate), true)
end

function set_color(color_str)
    if color_str:sub(1,1) == '#' then
        local hex = color_str:sub(2)
        local r = tonumber(hex:sub(1,2), 16) or 0
        local g = tonumber(hex:sub(3,4), 16) or 0
        local b = tonumber(hex:sub(5,6), 16) or 0
        local a = 255
        if #hex == 8 then
            a = tonumber(hex:sub(7,8), 16) or 255
        end
        return (a << 24) | (b << 16) | (g << 8) | r
    end
    return 0xFFFFFFFF
end

function get_selected_track_name()
    local track = r.GetSelectedTrack(0, 0)
    if not track then return nil end
    local _, track_name = r.GetTrackName(track)
    if track_name and track_name ~= "" then
        track_name = track_name:gsub("%[.-%]", ""):trim()
        return track_name
    end
    return nil
end

function find_existing_markers(base_name, prefix)
    prefix = prefix or "#ZAMETKA"
    local markers = {}
    local marker_count = r.CountProjectMarkers(0)
    for i = 0, marker_count - 1 do
        local _, _, _, _, name = r.EnumProjectMarkers(i)
        if name and name:match("^" .. prefix .. " " .. base_name:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")) then
            local num = name:match("^" .. prefix .. " " .. base_name:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1") .. " (%d+)$")
            if num then
                table.insert(markers, tonumber(num))
            else
                table.insert(markers, 1)
            end
        end
    end
    table.sort(markers)
    return markers
end

function get_note_type(note)
    if note.marker_name and note.marker_name:find("^#OSHIBKA") then
        return "error"
    end
    return "note"
end

function get_next_marker_number(base_name, prefix)
    local existing = find_existing_markers(base_name, prefix)
    if #existing == 0 then return 1 end
    for i = 1, #existing + 1 do
        if not existing[i] or existing[i] ~= i then
            return i
        end
    end
    return #existing + 1
end

function get_marker_position()
    local edit_pos = r.GetCursorPosition()
    local marker_count = r.CountProjectMarkers(0)
    for i = 0, marker_count - 1 do
        local _, is_region, region_start, region_end, name = r.EnumProjectMarkers(i)
        if is_region and edit_pos >= region_start and edit_pos <= region_end then
            return region_start
        end
    end
    return edit_pos
end

local show_note_type_popup = false
local pending_track_name = nil

function create_marker_for_note(note_name, note_type)
    local marker_pos = get_marker_position()
    local marker_name
    local prefix = note_type == "error" and "#OSHIBKA" or "#ZAMETKA"
    local number = get_next_marker_number(note_name, prefix)
    
    if number == 1 then
        marker_name = prefix .. " " .. note_name
    else
        marker_name = prefix .. " " .. note_name .. " " .. number
    end
    
    local marker_color
    if note_type == "error" then
        marker_color = f.RGBToReaperColor(255, 0, 0)
    else
        marker_color = f.RGBToReaperColor(0, 255, 0)
    end
    
    local marker_id = r.AddProjectMarker2(0, false, marker_pos, 0, marker_name, -1, marker_color)
    return marker_id, marker_pos, number
end

function move_cursor_to_marker(marker_name)
    local marker_count = r.CountProjectMarkers(0)
    for i = 0, marker_count - 1 do
        local _, _, pos, _, name = r.EnumProjectMarkers(i)
        if name == marker_name then
            r.SetEditCurPos(pos, true, true)
            return true
        end
    end
    return false
end

function delete_marker_by_name(marker_name)
    local marker_count = r.CountProjectMarkers(0)
    for i = marker_count - 1, 0, -1 do
        local _, _, _, _, name, idx = r.EnumProjectMarkers(i)
        if name == marker_name then
            r.DeleteProjectMarker(0, idx, false)
            return true
        end
    end
    return false
end

function hide_marker(note)
    if note.marker_name and note.marker_name ~= "" then
        delete_marker_by_name(note.marker_name)
    end
end

function restore_marker(note)
    if note.marker_name and note.marker_name ~= "" and note.marker_pos then
        local marker_color
        local note_type = get_note_type(note)
        if note_type == "error" then
            marker_color = f.RGBToReaperColor(255, 0, 0)
        else
            marker_color = f.RGBToReaperColor(0, 255, 0)
        end
        r.AddProjectMarker2(0, false, note.marker_pos, 0, note.marker_name, -1, marker_color)
    end
end

function get_note_display_name(note)
    if note.marker_name then
        local base_name = note.marker_name:match("^#[A-Z]+ (.+)")
        if base_name then
            local number = base_name:match(" (%d+)$")
            if number then
                local clean_name = base_name:gsub(" %d+$", "")
                return clean_name .. " " .. number
            else
                return base_name .. " 1"
            end
        end
    end
    return note.recipient ~= "" and note.recipient or "Untitled"
end

function create_note_of_type(track_name, note_type)
    stop_preview()
    
    local marker_id, marker_pos, number = create_marker_for_note(track_name, note_type)
    current_id = "note_" .. tostring(r.time_precise()):gsub("%.", "_")
    
    local prefix = note_type == "error" and "#OSHIBKA" or "#ZAMETKA"
    local marker_name = prefix .. " " .. track_name
    if number > 1 then
        marker_name = marker_name .. " " .. number
    end
    
    notes[current_id] = {
        recipient = track_name,
        content = "",
        audio_path = "",
        timestamp = current_id,
        region = "",
        marker_name = marker_name,
        marker_pos = marker_pos,
        completed = 0
    }
    save_note(current_id)
end

function draw_note_type_popup()
    if show_note_type_popup then
        im.OpenPopup(ctx04, "Note Type Selection")
        show_note_type_popup = false
    end
    
    local center_x_popup = center_x 
    local center_y_popup = center_y
    im.SetNextWindowPos(ctx04, center_x_popup, center_y_popup, im.Cond_Always, 0.5, 0.5)
    
    if im.BeginPopupModal(ctx04, "Note Type Selection", true, im.WindowFlags_AlwaysAutoResize) then
        im.Text(ctx04, "Choose note type for: " .. (pending_track_name or ""))
        im.Separator(ctx04)
        
        im.PushStyleColor(ctx04, im.Col_Button, 0x4CAF50FF)
        if im.Button(ctx04, "Note", 80, 0) then
            if pending_track_name then
                create_note_of_type(pending_track_name, "note")
            end
            pending_track_name = nil
            im.CloseCurrentPopup(ctx04)
        end
        im.PopStyleColor(ctx04)
        
        im.SameLine(ctx04)
        
        im.PushStyleColor(ctx04, im.Col_Button, 0xF44336FF)
        if im.Button(ctx04, "Error", 80, 0) then
            if pending_track_name then
                create_note_of_type(pending_track_name, "error")
            end
            pending_track_name = nil
            im.CloseCurrentPopup(ctx04)
        end
        im.PopStyleColor(ctx04)
        
        if im.Button(ctx04, "Cancel", 165, 0) then
            pending_track_name = nil
            im.CloseCurrentPopup(ctx04)
        end
        
        im.EndPopup(ctx04)
    end
end

function create_recording_track(note_name)
    local track_name = "REC_NOTE_" .. note_name .. "_" .. tostring(r.time_precise()):gsub("%.", "")
    local track_count = r.CountTracks(0)
    local selected_track = r.GetSelectedTrack(0, 0)
    local insert_idx = 0
    if selected_track then
        insert_idx = r.GetMediaTrackInfo_Value(selected_track, "IP_TRACKNUMBER")
    end
    r.InsertTrackAtIndex(insert_idx, false)
    local new_track = r.GetTrack(0, insert_idx)
    r.GetSetMediaTrackInfo_String(new_track, "P_NAME", track_name, true)
    for i = 0, r.CountTracks(0) - 1 do
        local track = r.GetTrack(0, i)
        r.SetMediaTrackInfo_Value(track, "I_RECARM", 0)
    end
    r.SetMediaTrackInfo_Value(new_track, "I_RECARM", 1)
    r.SetOnlyTrackSelected(new_track)
    local guid = r.GetTrackGUID(new_track)
    return guid, track_name
end

function find_track_by_guid(guid)
    if not guid then return nil end
    for i = 0, r.CountTracks(0) - 1 do
        local track = r.GetTrack(0, i)
        if r.GetTrackGUID(track) == guid then
            return track
        end
    end
    return nil
end

function get_audio_from_recording_track(guid)
    local track = find_track_by_guid(guid)
    if not track then return nil end
    local item_count = r.CountTrackMediaItems(track)
    if item_count == 0 then return nil end
    local item = r.GetTrackMediaItem(track, 0)
    local take = r.GetActiveTake(item)
    if not take then return nil end
    if r.TakeIsMIDI(take) then return nil end
    local source = r.GetMediaItemTake_Source(take)
    local filename = r.GetMediaSourceFileName(source, "")
    return filename
end

function delete_recording_track(guid)
    local track = find_track_by_guid(guid)
    if track then
        r.DeleteTrack(track)
        r.TrackList_AdjustWindows(false)
    end
end

function has_audio_file(note)
    return note and note.audio_path and note.audio_path ~= ""
end

function get_source_peaks_in_range(filepath, disp_w)
    local source = r.PCM_Source_CreateFromFile(filepath)
    if not source then return nil, 0, 1, 0 end
    
    local nch = r.GetMediaSourceNumChannels(source)
    local len = r.GetMediaSourceLength(source)
    
    if not nch or nch <= 0 or nch > 32 then
        r.PCM_Source_Destroy(source)
        return nil, 0, 1, 0
    end
    
    if not len or len <= 0 then
        r.PCM_Source_Destroy(source) 
        return nil, 0, nch, 0
    end
    
    if not disp_w or disp_w <= 0 or disp_w ~= disp_w then
        disp_w = 100
    end
    
    local ns = math.max(1, math.floor(disp_w))
    local array_size = ns * nch * 2
    if array_size <= 0 or array_size > 1000000 then
        r.PCM_Source_Destroy(source)
        return nil, 0, nch, len
    end
    
    local pr = ns / len
    local buf = r.new_array(array_size)
    local retval = r.PCM_Source_GetPeaks(source, pr, 0, nch, ns, 0, buf)
    local spl_cnt = retval & 0xFFFFF
    r.PCM_Source_Destroy(source)
    return buf, spl_cnt, nch, len
end

function get_cached_peaks(filepath, disp_w)
    if not filepath or filepath == "" then
        return nil, 0, 1, 0
    end
    
    local cache = waveform_cache[filepath]
    if cache and cache.disp_w == disp_w then
        return cache.peaks, cache.spl_cnt, cache.nch, cache.len
    end
    
    local peaks, spl_cnt, nch, len = get_source_peaks_in_range(filepath, disp_w)
    if peaks then
        waveform_cache[filepath] = {peaks = peaks, spl_cnt = spl_cnt, nch = nch, len = len, disp_w = disp_w}
    end
    return peaks, spl_cnt, nch, len
end

function draw_item_waveform(dat, x, y, w, h)
    local spl_cnt = dat.spl_cnt
    local nch = dat.nch or 1
    local ns = spl_cnt
    local peaks = dat.peaks
    local ch_h = h / nch
    local draw_list = im.GetWindowDrawList(ctx04)
    local win_x, win_y = im.GetCursorScreenPos(ctx04)
    for ch = 0, nch - 1 do
        local ch_y = y + ch * ch_h
        for i = 0, w - 1 do
            local t = math.floor((i / w) * ns)
            local max_idx = t * nch + ch + 1
            local min_idx = ns * nch + t * nch + ch + 1
            local max_val = peaks[max_idx] or 0
            local min_val = peaks[min_idx] or 0
            local top = ch_y + ((1 - max_val) * 0.5) * ch_h
            local bottom = ch_y + ((1 - min_val) * 0.5) * ch_h
            top = math.max(ch_y, top)
            bottom = math.min(ch_y + ch_h, bottom)
            if bottom > top then 
                im.DrawList_AddLine(draw_list, x + i + win_x, top + win_y, x + i + win_x, bottom + win_y, 0x4F8CFFFF, 1)
            end
        end
    end
end

function set_ui_style()
    local bg_color = 0x121212FF
    local accent_color = 0x4F8CFFFF
    local text_color = 0xEEEEEEFF
    local highlight_color = 0x4F8CFFAA
    local button_color = 0x3D3D3DFF
    local button_hovered = 0x5b5b5bFF
    local delete_button = 0xDB4F4FFF
    local speed_button = 0x56B35BFF
    local save_button = 0x4CAF50FF
    
    im.PushStyleColor(ctx04, im.Col_WindowBg, bg_color)
    im.PushStyleColor(ctx04, im.Col_Text, text_color)
    im.PushStyleColor(ctx04, im.Col_Button, button_color)
    im.PushStyleColor(ctx04, im.Col_ButtonHovered, button_hovered)
    im.PushStyleColor(ctx04, im.Col_ButtonActive, accent_color)
    im.PushStyleColor(ctx04, im.Col_FrameBg, 0x333333FF)
    im.PushStyleColor(ctx04, im.Col_FrameBgHovered, 0x3F3F3FFF)
    im.PushStyleColor(ctx04, im.Col_FrameBgActive, 0x484848FF)
    im.PushStyleColor(ctx04, im.Col_Header, 0x3A3A3AFF)
    im.PushStyleColor(ctx04, im.Col_HeaderHovered, highlight_color)
    im.PushStyleColor(ctx04, im.Col_HeaderActive, accent_color)
    im.PushStyleColor(ctx04, im.Col_SliderGrab, accent_color)
    im.PushStyleColor(ctx04, im.Col_SliderGrabActive, 0x6FA5FFFF)
    im.PushStyleColor(ctx04, im.Col_TitleBg, 0x1A1A1AFF)
    im.PushStyleColor(ctx04, im.Col_TitleBgActive, 0x2D2D2DFF)
    im.PushStyleColor(ctx04, im.Col_TitleBgCollapsed, 0x1A1A1AFF)
    
    -- Увеличиваем padding до 8
    im.PushStyleVar(ctx04, im.StyleVar_WindowPadding, 8, 8)
    im.PushStyleVar(ctx04, im.StyleVar_ChildBorderSize, 0)
    im.PushStyleVar(ctx04, im.StyleVar_ChildRounding, 2)
    im.PushStyleVar(ctx04, im.StyleVar_ItemSpacing, 8, 6)
    im.PushStyleVar(ctx04, im.StyleVar_FramePadding, 8, 4)
    im.PushStyleVar(ctx04, im.StyleVar_WindowRounding, 4)
    im.PushStyleVar(ctx04, im.StyleVar_FrameRounding, 2)
    im.PushStyleVar(ctx04, im.StyleVar_GrabRounding, 2)
    im.PushStyleVar(ctx04, im.StyleVar_ScrollbarRounding, 2)
    im.PushStyleVar(ctx04, im.StyleVar_TabRounding, 2)
    
    return {
        delete_button = delete_button,
        speed_button = speed_button,
        save_button = save_button
    }
end

function print(...)
    local args = {...}
    for i = 1, #args do
        reaper.ShowConsoleMsg(tostring(args[i]) .. "\t")
    end
    reaper.ShowConsoleMsg("\n")
end

function reset_ui_style()
    im.PopStyleColor(ctx04, 16)
    im.PopStyleVar(ctx04, 10)
end

function load_notes()
    notes = {}
    local dir = r.GetProjectPath()
    
    for i = 0, math.huge do
        local ok, k, v = r.EnumProjExtState(prj, 'Notes', i)
        if not ok then break end
        if v == "" then goto continue end
        local parts = {}
        for part in v:gmatch("([^|]*)") do
            table.insert(parts, part)
        end
        
        if parts[3] and parts[3] ~= "" and not r.file_exists(parts[3]) then
            local audio_path = parts[3]
            local fname = audio_path:match("([^\\/]+)$")
            if fname then
                fname = fname:match("^%s*(.-)%s*$")
                parts[3] = dir .. '/' .. fname
            end
        end
        
        if #parts >= 6 then
            notes[k] = {
                recipient = parts[1] or "",
                content = parts[2] or "",
                audio_path = parts[3] or "",
                timestamp = parts[4] or tostring(r.time_precise()),
                region = parts[5] or "",
                marker_name = parts[6] or "",
                marker_pos = tonumber(parts[7]) or 0,
                completed = tonumber(parts[8]) or 0 
            }
            if notes[k].content ~= "" then
                notes[k].content = notes[k].content:gsub('\\n', '\n')
            end
        end
        ::continue::
    end
end

function save_note(id)
    if not notes[id] then return end
    local note = notes[id]
    local content_escaped = note.content and note.content:gsub('\n', '\\n') or ""
    local data = table.concat({
        note.recipient or "",
        content_escaped,
        note.audio_path or "",
        note.timestamp or tostring(r.time_precise()),
        note.region or "",
        note.marker_name or "",
        tostring(note.marker_pos or 0),
        tostring(note.completed or 0)
    }, '|')
    r.SetProjExtState(prj, 'Notes', id, data)
end

function delete_note(id)
    if notes[id] and notes[id].marker_name and notes[id].marker_name ~= "" then
        delete_marker_by_name(notes[id].marker_name)
    end
    r.SetProjExtState(prj, 'Notes', id, '')
    notes[id] = nil
    if current_id == id then 
        current_id = nil
        for next_id, _ in pairs(notes) do
            current_id = next_id
            break
        end
    end
end

function find_matching_note()
    local _, project_name = r.EnumProjects(-1, "")
    if not project_name or project_name == "" then
        for id, _ in pairs(notes) do
            return id
        end
        return nil
    end
    project_name = project_name:lower()
    for id, note in pairs(notes) do
        if note.recipient and note.recipient ~= "" then
            if project_name:find(note.recipient:lower()) then
                return id
            end
        end
    end
    for id, _ in pairs(notes) do
        return id
    end
    return nil
end

function stop_preview()
    if preview then
        r.CF_Preview_Stop(preview)
        preview = nil
        is_playing = false
        paused_position = nil
    end
end

function pause_preview()
    if preview and is_playing then
        _, paused_position = r.CF_Preview_GetValue(preview, 'D_POSITION')
        r.CF_Preview_Stop(preview)
        preview = nil
        is_playing = false
    else
        if paused_position ~= nil and current_id and notes[current_id] and notes[current_id].audio_path ~= "" then
            start_preview(notes[current_id].audio_path, paused_position)
        end
    end
end

function start_preview(path, position)
    stop_preview()
    if not path or path == "" then return end
    local source = r.PCM_Source_CreateFromFile(path)
    if not source then return end
    preview = r.CF_CreatePreview(source)
    r.CF_Preview_SetValue(preview, 'D_VOLUME', volume)
    r.CF_Preview_SetValue(preview, 'D_PLAYRATE', play_rate)
    r.CF_Preview_SetValue(preview, 'I_PITCHMODE', (1 << 16) | 3)
    if position then
        r.CF_Preview_SetValue(preview, 'D_POSITION', position)
    end
    r.CF_Preview_Play(preview)
    r.PCM_Source_Destroy(source)
    is_playing = true
end

function toggle_playback()
    if current_id and notes[current_id] and notes[current_id].audio_path ~= "" then
        if is_playing then
            pause_preview()
        else
            if paused_position then
                start_preview(notes[current_id].audio_path, paused_position)
            else
                start_preview(notes[current_id].audio_path)
            end
        end
    end
end

function cycle_playback_speed(forward)
    if forward then
        current_speed_index = current_speed_index % #speed_options + 1
    else
        current_speed_index = current_speed_index - 1
        if current_speed_index < 1 then
            current_speed_index = #speed_options
        end
    end
    play_rate = speed_options[current_speed_index]
    if preview then
        r.CF_Preview_SetValue(preview, 'D_PLAYRATE', play_rate)
    end
    save_global_settings()
end

function get_audio_from_item()
    local item = r.GetSelectedMediaItem(0, 0)
    if not item then return nil end
    local take = r.GetActiveTake(item)
    if not take then return nil end
    if r.TakeIsMIDI(take) then return nil end
    local source = r.GetMediaItemTake_Source(take)
    local filename = r.GetMediaSourceFileName(source, "")
    return filename
end

function db_to_val(x)
    return math.exp(x * 0.11512925464970228420089957273422)
end

function val_to_db(x)
    if x < 0.0000000298023223876953125 then
        return -150
    else
        return math.max(-150, math.log(x) * 8.6858896380650365530225783783321)
    end
end

function format_time(time)
    if not time then return "00:00.000" end
    local minutes = math.floor(time / 60)
    local seconds = time % 60
    return string.format("%02d:%05.2f", minutes, seconds)
end

-- Компактный аудиоплеер, который не показывается если нет аудиофайла
function draw_audio_player()
    if not current_id or not notes[current_id] then return end
    local note = notes[current_id]
    local audio_path = note.audio_path
    
    -- НЕ РИСУЕМ плеер если нет аудиофайла
    if not audio_path or audio_path == "" then
        return
    end
    
    if im.BeginChild(ctx04, "audio_player", -1, -1, 0) then -- Уменьшена высота
        local position, length = 0, 0
        if preview then
            local is_preview_active
            is_preview_active, position = r.CF_Preview_GetValue(preview, 'D_POSITION')
            _, length = r.CF_Preview_GetValue(preview, 'D_LENGTH')
            if is_preview_active and position >= length - 0.1 then
                is_playing = false
            end
        elseif paused_position then
            position = paused_position
        end
        
        local waveform_height = 40 -- Уменьшена высота волны
        local avail_w = im.GetContentRegionAvail(ctx04)
        
        local peaks, spl_cnt, nch, len = get_cached_peaks(audio_path, avail_w)
        if peaks then
            local dat = {peaks = peaks, spl_cnt = spl_cnt, nch = nch, len = len}
            im.PushStyleColor(ctx04, im.Col_ChildBg, 0x16191bFF)
            if im.BeginChild(ctx04, "waveform", -1, waveform_height, 1, im.WindowFlags_NoScrollbar) then
                local c_w, c_h = im.GetContentRegionAvail(ctx04)
                draw_item_waveform(dat, 0, 0, c_w, c_h)
                local rel_pos = length > 0 and (position / length) or 0
                local cursor_x = rel_pos * c_w
                local draw_list = im.GetWindowDrawList(ctx04)
                local win_x, win_y = im.GetCursorScreenPos(ctx04)
                local grab_width = 6 -- Уменьшена ширина
                local grab_x = cursor_x - grab_width/2
                im.DrawList_AddRectFilled(draw_list, grab_x + win_x, win_y, grab_x + grab_width + win_x, win_y + c_h, 0x4F8CFF80, 2)
                im.DrawList_AddRect(draw_list, grab_x + win_x, win_y, grab_x + grab_width + win_x, win_y + c_h, 0x4F8CFFFF, 2, 0, 1)
                im.SetCursorPos(ctx04, 0, 0)
                im.InvisibleButton(ctx04, "waveform_slider", c_w, c_h)
                if im.IsItemActive(ctx04) then
                    local mouse_x, _ = im.GetMousePos(ctx04)
                    local rel_click = math.max(0, math.min(1, (mouse_x - win_x) / c_w))
                    local new_pos = rel_click * length
                    if preview then
                        r.CF_Preview_SetValue(preview, 'D_POSITION', new_pos)
                    else
                        paused_position = new_pos
                    end
                elseif im.IsItemClicked(ctx04) then
                    local mouse_x, _ = im.GetMousePos(ctx04)
                    local rel_click = math.max(0, math.min(1, (mouse_x - win_x) / c_w))
                    local new_pos = rel_click * length
                    if preview then
                        r.CF_Preview_SetValue(preview, 'D_POSITION', new_pos)
                    else
                        paused_position = new_pos
                        start_preview(audio_path, new_pos)
                    end
                end
                -- Закомментировано отображение времени
                -- local time_text = format_time(position) .. " / " .. format_time(length)
                -- im.SetCursorPos(ctx04, 3, 3)
                -- im.PushStyleColor(ctx04, im.Col_Text, 0x00FFFFFF)
                -- im.Text(ctx04, time_text)
                -- im.PopStyleColor(ctx04)
            end
            im.EndChild(ctx04)
            im.PopStyleColor(ctx04)
        end
        
        -- VU meter - индикатор громкости
        for i = 0, 1 do
            local valid, peak = false, 0
            if preview then
                valid, peak = r.CF_Preview_GetPeak(preview, i)
            end
            im.ProgressBar(ctx04, valid and peak or 0, -1, 4, "")
        end
        
        -- Компактные элементы управления
        if im.Button(ctx04, is_playing and "||" or ">", 30, 0) then
            if not is_playing and audio_path ~= "" then
                start_preview(audio_path)
            else
                stop_preview()
            end
        end
        
        im.SameLine(ctx04)
        im.PushStyleColor(ctx04, im.Col_Button, styles.speed_button)
        local speed_text = string.format("%.1fx", play_rate)
        if im.Button(ctx04, speed_text, 40, 0) then
            cycle_playback_speed(true)
        end
        im.PopStyleColor(ctx04)
        
        im.SameLine(ctx04)
        im.SetNextItemWidth(ctx04, -1)
        local vol_db = val_to_db(volume)
        local rv_vol, new_vol_db = im.SliderDouble(ctx04, "##Vol", vol_db, -60, 20, string.format("%.0fdB", vol_db))
        if rv_vol then
            volume = db_to_val(new_vol_db)
            if preview then
                r.CF_Preview_SetValue(preview, 'D_VOLUME', volume)
            end
            save_global_settings()
        end
        
        im.EndChild(ctx04)
    end
end

function draw_delete_confirmation()
    if show_delete_confirm then
        im.OpenPopup(ctx04, "Delete Confirmation")
        show_delete_confirm = false
    end
    center_x = center_x + (width/2)
    center_y = center_y + (height/2)
    im.SetNextWindowPos(ctx04, center_x, center_y, im.Cond_Always, 0.5, 0.5)
    if im.BeginPopupModal(ctx04, "Delete Confirmation", true, im.WindowFlags_AlwaysAutoResize) then
        local note_name = "Unknown"
        if delete_target_id and notes[delete_target_id] then
            note_name = get_note_display_name(notes[delete_target_id])
        end
        im.Text(ctx04, "Delete \"" .. note_name .. "\"?")
        im.Text(ctx04, "This cannot be undone.")
        im.Separator(ctx04)
        if im.Button(ctx04, "Delete", 80, 0) then
            if delete_target_id then
                delete_note(delete_target_id)
            end
            delete_target_id = nil
            im.CloseCurrentPopup(ctx04)
        end
        im.SameLine(ctx04)
        if im.Button(ctx04, "Cancel", 80, 0) then
            delete_target_id = nil
            im.CloseCurrentPopup(ctx04)
        end
        im.EndPopup(ctx04)
    end
end

-- Компактный список заметок (на 30% уже)
function draw_notes_list()
    local list_width = 140 -- Уменьшена ширина списка на ~30%
    if im.BeginChild(ctx04, "notes_list", list_width, -1, 1) then
        local w = im.GetContentRegionAvail(ctx04)
        
        if not IS_CHILDREN then
            -- Закомментирована кнопка Update
            -- if im.Button(ctx04, "Update", w, 0) then
            --     update()
            --     load_notes() 
            -- end
            
            if im.Button(ctx04, "New", w * 0.65, 0) then -- Увеличил ширину кнопки New
                local track_name = get_selected_track_name()
                if not track_name or track_name == "" then
                    track_name = "Note_" .. tostring(math.floor(r.time_precise() * 1000) % 10000)
                end
                pending_track_name = track_name
                show_note_type_popup = true
            end
        
            im.SameLine(ctx04)
            im.PushStyleColor(ctx04, im.Col_Button, styles.delete_button)
            local del_button_width = w - w * 0.65 - 8 -- Уменьшил ширину кнопки X
            if im.Button(ctx04, "X", del_button_width, 0) and current_id then
                show_delete_confirm = true
                delete_target_id = current_id
            end
            im.PopStyleColor(ctx04)
        end
        
        local sorted_notes = {}
        for id, note in pairs(notes) do
            table.insert(sorted_notes, {id = id, note = note})
        end
        
        table.sort(sorted_notes, function(a, b)
            local num_a = 1
            local num_b = 1
            
            if a.note.marker_name then
                local extracted_num = a.note.marker_name:match("%s+(%d+)$")
                if extracted_num then
                    num_a = tonumber(extracted_num) or 1
                end
            end
            
            if b.note.marker_name then
                local extracted_num = b.note.marker_name:match("%s+(%d+)$")
                if extracted_num then
                    num_b = tonumber(extracted_num) or 1
                end
            end
            
            local type_a = get_note_type(a.note)
            local type_b = get_note_type(b.note)
            
            if type_a ~= type_b then
                return type_a == "note"
            end
            
            return num_a < num_b
        end)
        
        for _, item in ipairs(sorted_notes) do
            local id = item.id
            local note = item.note
            local label = get_note_display_name(note)
            local note_type = get_note_type(note)
            
            local text_color
            if note_type == "error" then
                if IS_CHILDREN then
                    text_color = has_audio_file(note) and 0xFF6B6BFF or 0xF44336FF
                else
                    text_color = has_audio_file(note) and 0xFF6B6BFF or 0xF44336FF
                end
            else
                if IS_CHILDREN then
                    text_color = 0x4CAF50FF
                else
                    text_color = has_audio_file(note) and 0x4CAF50FF or 0x66BB6AFF
                end
            end
            
            if note.completed == nil then
                note.completed = 0
            end
            
            im.BeginDisabled(ctx04, not IS_CHILDREN)
            local checkbox_changed, checkbox_value = im.Checkbox(ctx04, "##c" .. tostring(id), note.completed == 1)
            im.EndDisabled(ctx04)
            if IS_CHILDREN and checkbox_changed then
                note.completed = checkbox_value and 1 or 0
                if checkbox_value then
                    -- Скрываем маркер при установке галочки
                    hide_marker(note)
                else
                    -- Восстанавливаем маркер при снятии галочки
                    restore_marker(note)
                end
                save_note(id)
            end
            im.SameLine(ctx04)
            
            im.PushStyleColor(ctx04, im.Col_Text, text_color)
            local is_selected = (tostring(current_id) == tostring(id))
            local unique_label = label .. "##n" .. tostring(id)
            
            if im.Selectable(ctx04, unique_label, is_selected) then
                stop_preview()
                current_id = id
                if note.marker_name and note.marker_name ~= "" then
                    move_cursor_to_marker(note.marker_name)
                end
            end
            
            im.PopStyleColor(ctx04)
        end
        
        im.EndChild(ctx04)
    end
end

-- Компактный редактор заметок
function draw_note_editor()
    if not current_id or not notes[current_id] then 
        return 
    end
    
    local note = notes[current_id]
    
    if not IS_CHILDREN then
        im.SetNextItemWidth(ctx04, -1)
        local current_name = note.recipient or ""
        local rv_recipient, new_recipient = im.InputText(ctx04, "##name", current_name)
        if rv_recipient then 
            local base_name = new_recipient:gsub("%s+%d+$", "")
            local original_number = current_name:match("%s+(%d+)$") or "1"
            note.recipient = base_name .. " " .. original_number
            save_note(current_id)
        end
    else
        im.Text(ctx04, 'KOMY: ' .. (note.recipient or ""))
    end
    
    if not IS_CHILDREN then
        im.PushItemWidth(ctx04, -1)
        local rv_content, new_content = im.InputTextMultiline(ctx04, "##content", note.content or "", -1, 40)
        im.PopItemWidth(ctx04)
        if rv_content then 
            note.content = new_content
            save_note(current_id)
        end
    else
        if note.content and note.content ~= "" then
            im.PushFont(ctx04, font_bold) -- Жирный шрифт для текста заметки
            im.PushStyleColor(ctx04, im.Col_Text, 0xDDDDDDFF) -- Слегка другой цвет
            im.PushTextWrapPos(ctx04, 0.0)
            im.TextWrapped(ctx04, note.content)
            im.PopTextWrapPos(ctx04)
            im.PopStyleColor(ctx04)
            im.PopFont(ctx04)
        end
    end
    
    if not IS_CHILDREN then 
        local button_width = im.GetContentRegionAvail(ctx04)
        
        if not recording_track_guid then
            -- Слегка зеленоватая кнопка Create Track
            im.PushStyleColor(ctx04, im.Col_Button, 0x4A5A4AFF)
            im.PushStyleColor(ctx04, im.Col_ButtonHovered, 0x5A6A5AFF)
            if im.Button(ctx04, "Create Track", button_width, 0) then
                recording_track_guid = create_recording_track(note.recipient or "Note")
            end
            im.PopStyleColor(ctx04, 2)
        else
            -- Слегка синеватая кнопка OK
            im.PushStyleColor(ctx04, im.Col_Button, 0x4A4A5AFF)
            im.PushStyleColor(ctx04, im.Col_ButtonHovered, 0x5A5A6AFF)
            if im.Button(ctx04, "OK", button_width, 0) then
                local recording_state = r.GetPlayState()
                if recording_state & 4 == 4 then
                    r.Main_OnCommand(1016, 0)
                end
                
                local audio_path = get_audio_from_recording_track(recording_track_guid)
                if audio_path then
                    note.audio_path = audio_path
                    stop_preview()
                end
                
                delete_recording_track(recording_track_guid)
                recording_track_guid = nil
                
                note.timestamp = tostring(r.time_precise())
                save_note(current_id)
            end
            im.PopStyleColor(ctx04, 2)
        end
    end
    
    draw_audio_player()
end

function handle_keyboard_input()
    -- Убрано воспроизведение по пробелу
    -- local space_pressed = im.IsKeyPressed(ctx04, im.Key_Space)
    -- if space_pressed and im.IsWindowFocused(ctx04, im.FocusedFlags_RootAndChildWindows) then
    --     toggle_playback()
    --     return true
    -- end
    local del_pressed = im.IsKeyPressed(ctx04, im.Key_Delete)
    if del_pressed and current_id and im.IsWindowFocused(ctx04, im.FocusedFlags_RootAndChildWindows) then
        show_delete_confirm = true
        delete_target_id = current_id
        return true
    end
    return false
end

function main_window()
    -- Уменьшенные размеры окна и минимальные ограничения
    im.SetNextWindowSize(ctx04, 500, 350, im.Cond_FirstUseEver)
    im.SetNextWindowSizeConstraints(ctx04, 400, 250, 1000, 600) -- Меньшие минимальные размеры
    styles = set_ui_style()
    local visible, open = im.Begin(ctx04, "Enhanced Notes Manager", true, im.WindowFlags_NoCollapse)
    center_x, center_y = im.GetWindowPos(ctx04)
    if visible then
        handle_keyboard_input()
        width, height = im.GetWindowSize(ctx04)
        local posX, posY = im.GetCursorPos(ctx04)
        im.SetCursorPos(ctx04, posX, posY)
        draw_notes_list()
        im.SetCursorPos(ctx04, posX + 145, posY)
        if im.BeginChild(ctx04, "editor_area", -1, -1, 1, im.WindowFlags_None) then
            draw_note_editor()
            im.EndChild(ctx04)
        end
        draw_delete_confirmation()
        draw_note_type_popup()
        im.End(ctx04)
    end
    reset_ui_style()
    return open
end

function main_loop()
    im.PushFont(ctx04, font)
    local open = main_window()
    im.PopFont(ctx04)
    if open then
        r.defer(main_loop)
    else
        stop_preview()
    end
end

load_notes()
for i, speed in ipairs(speed_options) do
    if math.abs(play_rate - speed) < 0.01 then
        current_speed_index = i
        break
    end
end
if not current_id then
    current_id = find_matching_note()
end
update()
r.defer(main_loop)
r.atexit(function()
    if preview then
        r.CF_Preview_Stop(preview)
    end
    if recording_track_guid then
        delete_recording_track(recording_track_guid)
    end
end)