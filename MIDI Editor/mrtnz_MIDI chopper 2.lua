-- @description MIDI Chopper
-- @author mrtnz
-- @version 1.1
-- @about
--   ..
-- @provides
--   core.lua
--   color.lua

local r=reaper;function print(...) local t = {...} for i = 1, select('#', ...) do t[i] = tostring(t[i]) end reaper.ShowConsoleMsg(table.concat(t, '\t') .. '\n') end

midiEditor = reaper.MIDIEditor_GetActive()
take = reaper.MIDIEditor_GetTake(midiEditor)
if not take or not reaper.TakeIsMIDI(take) then return end

local current_path = debug.getinfo(1, "S").source:match [[^@?(.*[\/])[^\/]-$]]
local imgui_path =  reaper.ImGui_GetBuiltinPath() .. '/?.lua'

package.path = current_path .. '?.lua;' .. imgui_path .. ';' .. package.path

local ImGui = require 'imgui' '0.9.2'
local tk = require 'core'
require 'color'

local bacground_color = tk.color.get_reaper_theme_bg() --r.GetThemeColor('col_main_bg')
local button_color = "#697c87"


local ctx = ImGui.CreateContext('Midi chopper', config_flags)
local calibri = ImGui.CreateFont('calibri', 14)
ImGui.Attach(ctx, calibri)

function CustomSlider(ctx, label, value, min_value, max_value, normal_color, hover_color, active_color, grab_normal_color, grab_active_color)
    ImGui.PushStyleColor(ctx, ImGui.Col_FrameBg, tk.color.set_color(normal_color))
    ImGui.PushStyleColor(ctx, ImGui.Col_FrameBgHovered, tk.color.set_color(hover_color))
    ImGui.PushStyleColor(ctx, ImGui.Col_FrameBgActive, tk.color.set_color(active_color))
    ImGui.PushStyleColor(ctx, ImGui.Col_SliderGrab, tk.color.set_color(grab_normal_color))
    ImGui.PushStyleColor(ctx, ImGui.Col_SliderGrabActive, tk.color.set_color(grab_active_color))

    local rv, new_value = ImGui.SliderDouble(ctx, label, value, min_value, max_value, '')
    local item_active = ImGui.IsItemActive(ctx)

    ImGui.PopStyleColor(ctx, 5)
    return rv, new_value
end

function CustomButton(ctx, label, width, height)
    ImGui.PushStyleColor(ctx, ImGui.Col_Button, tk.color.set_color(button_color))
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, tk.color.set_color(tk.color.lum(button_color, 1.1)))
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, tk.color.set_color(tk.color.lum(button_color, 0.95)))
    if width and height then
        local rv = ImGui.Button(ctx, label, width, height)
        ImGui.PopStyleColor(ctx, 3)
        return rv
    end
end

function push_style(ctx)
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowRounding, 10)
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_FrameRounding, 5)
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_GrabRounding, 5)
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_Alpha, 1.9)
    
    ImGui.PushFont(ctx, calibri)
    
    ImGui.PushStyleColor(ctx, ImGui.Col_WindowBg, tk.color.set_color(tk.color.lum(bacground_color, 2.1)))
    ImGui.PushStyleColor(ctx, ImGui.Col_TitleBg, tk.color.set_color(tk.color.lum(bacground_color, 3.5)))
    ImGui.PushStyleColor(ctx, ImGui.Col_TitleBgActive, tk.color.set_color(tk.color.lum(bacground_color, 3.2)))
    ImGui.PushStyleColor(ctx, ImGui.Col_Border, tk.color.set_color('#4a4a4a'))
    
    ImGui.PushStyleColor(ctx, ImGui.Col_SeparatorHovered, tk.color.set_color('#5a5a5a'))
    ImGui.PushStyleColor(ctx, ImGui.Col_SeparatorActive, tk.color.set_color('#6a6a6a'))
    
    ImGui.PushStyleColor(ctx, ImGui.Col_ResizeGripHovered, tk.color.set_color('#4a4a4a'))
    ImGui.PushStyleColor(ctx, ImGui.Col_ResizeGripActive, tk.color.set_color('#4a4a4a#40'))
    ImGui.PushStyleColor(ctx, ImGui.Col_ResizeGrip, tk.color.set_color('#4a4a4a#50'))
end


local onchange = false
local invert_tension = false
local invert_velocity = false
local interpolation_type = "Cubic"
local split_value = 64
local current_splits = 1
local current_fraction = ""
local ofs_value = 0
local tension_value = 0
local velocity_value = 0

local last_effective_split_value = 64

local original_notes = {}

local grid_values = {
    {ticks = 1920, fraction = "1/2"}, {ticks = 1280, fraction = "1/3"},
    {ticks = 960, fraction = "1/4"}, {ticks = 640, fraction = "1/6"},
    {ticks = 480, fraction = "1/8"}, {ticks = 320, fraction = "1/12"},
    {ticks = 240, fraction = "1/16"}, {ticks = 160, fraction = "1/24"},
    {ticks = 120, fraction = "1/32"}, {ticks = 80, fraction = "1/48"},
    {ticks = 60, fraction = "1/64"}, {ticks = 30, fraction = "1/128"}
}

-- Function to get note data
function getNote(take, sel)
    local retval, selected, muted, startPos, endPos, channel, pitch, vel = reaper.MIDI_GetNote(take, sel)
    return {
        ["retval"]=retval,
        ["selected"]=selected,
        ["muted"]=muted,
        ["startPos"]=startPos,
        ["endPos"]=endPos,
        ["channel"]=channel,
        ["pitch"]=pitch,
        ["vel"]=vel,
        ["sel"]=sel
    }
end

-- Function to get all selected notes
function getSelectedNotes(take)
    local notes = {}
    local _, noteCount = reaper.MIDI_CountEvts(take)
    for i = 0, noteCount - 1 do
        local note = getNote(take, i)
        if note.selected then
            table.insert(notes, note)
        end
    end
    return notes
end

-- Function to delete all notes in the take
function deleteSelectedNotes()
    local i = -1
    while true do 
        i = reaper.MIDI_EnumSelNotes(take, i)
        if i == -1 then 
            break 
        else 
            reaper.MIDI_DeleteNote(take, i) 
            i = i - 1 
        end 
    end 
end
-- Function to insert original notes
function insertOriginalNotes(take, notes)
    for _, note in ipairs(notes) do
        reaper.MIDI_InsertNote(take, note.selected, note.muted, note.startPos, note.endPos, note.channel, note.pitch, note.vel, false)
    end
end

local interp_functions = {
  quadratic = function(t, ofs) return (1 - ofs) * t + ofs * t * t end,
  cubic = function(t, ofs)
    if ofs < 0 then
      t = 1 - t
    end
    local t_cubed = t^3
    local result = (1 - math.abs(ofs)) * t + math.abs(ofs) * t_cubed
    if ofs < 0 then
      result = 1 - result
    end
    return result
  end
}

function getInterpolation(interp_type, t, ofs)
  local func = interp_functions[interp_type:lower()]
  if not func then
    return t
  end
  return func(t, ofs)
end

local function get_effective_split_value(value)
    if value >= 64 then
        return math.floor((value - 64) * (128 / 64))
    else
        local index = math.floor((64 - value) / (64 / (#grid_values * 2 - 1))) + 1
        local grid_index = math.ceil(index / 2)
        return grid_values[grid_index].ticks
    end
end

function split(value, ofs, interp_type, useTick, tension, vel_param, invert_tension, invert_velocity)
  reaper.MIDI_DisableSort(take)
  
  local _, noteCount = reaper.MIDI_CountEvts(take)
  local notesToDelete = {}
  local notesToInsert = {}
  
  for i = 0, noteCount - 1 do
    local retval, selected, muted, startpos, endpos, chan, pitch, originalVel = reaper.MIDI_GetNote(take, i)
    if selected then
      local len = endpos - startpos
      local div = useTick and math.floor(len / value) or value
      
      if div > 1 then
        table.insert(notesToDelete, i)
        for j = 1, div do
          local t = (j - 1) / div
          local interp = getInterpolation(interp_type, t, ofs)
          local next_t = j / div
          local next_interp = getInterpolation(interp_type, next_t, ofs)
          local note_start = startpos + interp * len
          local note_end = startpos + next_interp * len

          -- Calculate indices considering inversion for tension and velocity
          local pitchIndex = (ofs >= 0) ~= invert_tension and j - 1 or div - j
          local newPitch = pitch - math.floor(pitchIndex * tension)

          local velChange = math.floor((originalVel - 1) * vel_param)
          local velIndex = (ofs >= 0) ~= invert_velocity and j - 1 or div - j
          local newVel = originalVel - math.floor(velChange * (velIndex / (div - 1)))
          newVel = math.max(1, newVel)

          table.insert(notesToInsert, {true, muted, note_start, note_end, chan, newPitch, newVel})
        end
      end
    end
  end
   
  for _, noteIdx in ipairs(notesToDelete) do
       reaper.MIDI_DeleteNote(take, noteIdx)
  end
  
  local insertedCount = 0
  for _, noteData in ipairs(notesToInsert) do
       local success = reaper.MIDI_InsertNote(take, table.unpack(noteData))
       if success then
           insertedCount = insertedCount + 1
       end
  end
  
  reaper.MIDI_Sort(take)
   
  return insertedCount
end

function run(useTick)
    local div
    if split_value >= 64 then
        div = math.floor((split_value - 64) * (128 / 64))
        current_splits = div
        current_fraction = ""
    else
        local index = math.floor((64 - split_value) / (64 / (#grid_values * 2 - 1))) + 1
        local grid_index = math.ceil(index / 2)
        div = grid_values[grid_index].ticks
        current_splits = math.floor(1920 / div)
        current_fraction = grid_values[grid_index].fraction
    end
    
    -- Delete all existing notes
    deleteSelectedNotes(take)
    
    -- Insert original notes
    insertOriginalNotes(take, original_notes)
    
    -- Now apply the split function
    current_splits=split(div, ofs_value, interpolation_type:lower(), useTick, tension_value, velocity_value, invert_tension, invert_velocity)
    
end

function loop()
    push_style(ctx)
    local visible, open = ImGui.Begin(ctx, 'Midi Chopper', true, ImGui.WindowFlags_NoDocking|ImGui.WindowFlags_NoCollapse)
    ImGui.PopStyleColor(ctx, 9) 
    
    midiEditor = reaper.MIDIEditor_GetActive()
    take = reaper.MIDIEditor_GetTake(midiEditor)
    
    
    if visible then
        local w, h = ImGui.GetContentRegionAvail(ctx)
      
        ImGui.PushStyleVar(ctx, ImGui.StyleVar_FramePadding, 5, 5)
        ImGui.Text(ctx, "Split")
        ImGui.SetNextItemWidth(ctx, -1 - 90)
        rv1, split_value = CustomSlider(ctx, '##split', split_value, 1, 128, 'gray#60', 'gray#50', 'gray#40', tk.color.lum('aqua#50', 4.5), 'aqua#30')
        ImGui.SameLine(ctx)
        CustomButton(ctx, current_splits .. (current_fraction ~= "" and " (" .. current_fraction .. ")" or ""), -1, 23)
        if rv1 then
            local effective_value = get_effective_split_value(split_value)
            if effective_value ~= last_effective_split_value then
                onchange = true
                last_effective_split_value = effective_value
            end
        end
        
        ImGui.Text(ctx, "Offset")
        ImGui.SetNextItemWidth(ctx, -1 - 90)
        rv2, ofs_value = CustomSlider(ctx, '##Offset', ofs_value, -1, 1, 'gray#60', 'gray#50', 'gray#40', tk.color.lum('aqua#50', 4.5), 'aqua#30')
        if rv2 then onchange = true end
        ImGui.SameLine(ctx)
        if CustomButton(ctx, interpolation_type, -1, 23) then
            interpolation_type = interpolation_type == "Cubic" and "Quadratic" or "Cubic"
            onchange = true
        end
        
        ImGui.Text(ctx, "Tension")
        ImGui.SetNextItemWidth(ctx, -1 - 90)
        rv3, tension_value = CustomSlider(ctx, '##Tension', tension_value, 0, 1, 'gray#60', 'gray#50', 'gray#40', tk.color.lum('aqua#50', 4.5), 'aqua#30')
        if rv3 then onchange = true end
        ImGui.SameLine(ctx)
        if CustomButton(ctx, 'Invert ' .. (invert_tension and 'on' or 'off'), -1, 23) then
            invert_tension = not invert_tension
            onchange = true
        end
        
        ImGui.Text(ctx, "Velocity")
        ImGui.SetNextItemWidth(ctx, -1 - 90)
        rv4, velocity_value = CustomSlider(ctx, '##velocity', velocity_value, 0, 1, 'gray#60', 'gray#50', 'gray#40', tk.color.lum('aqua#50', 4.5), 'aqua#30')
        if rv4 then onchange = true end
        ImGui.SameLine(ctx)
        if CustomButton(ctx, 'Invert  ' .. (invert_velocity and 'on' or 'off'), -1, 23) then
            invert_velocity = not invert_velocity
            onchange = true
        end
        
        ImGui.SetCursorPosY(ctx, ImGui.GetCursorPosY(ctx)+5)
 
        if CustomButton(ctx, 'Get note', 120, 30) then
            local take = reaper.MIDIEditor_GetTake(reaper.MIDIEditor_GetActive())
            if take then
                original_notes = getSelectedNotes(take)
                modified_notes = {} -- Clear previously modified notes
            end
            split_value = 64
            ofs_value = 0
            tension_value = 0
            velocity_value = 0
            invert_tension = false
            invert_velocity = false
            interpolation_type = "Cubic"
            current_splits = 1
            current_fraction = ""
            last_effective_split_value = 64
            
            onchange = true
        end
        ImGui.PopStyleVar(ctx)
        ImGui.End(ctx)
    end
  
    ImGui.PopStyleVar(ctx, 4) 
    ImGui.PopFont(ctx)
    
    if not take or not reaper.TakeIsMIDI(take) then return end
    
    
    if ImGui.IsKeyPressed(ctx, ImGui.Key_Escape) then
        open = false
    end
    if open then
        r.defer(loop)
        if onchange then
            run(split_value < 64)
            onchange = false
        end
    end
end

original_notes = getSelectedNotes(take)

ImGui.SetNextWindowSize(ctx, 300, 265, 1)
r.defer(loop)