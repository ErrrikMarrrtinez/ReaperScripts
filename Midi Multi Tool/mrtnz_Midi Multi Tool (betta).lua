-- @description Midi Multi Tool (betta)
-- @author mrtnz
-- @version 0.1.2-betta.1
-- @provides
--   color-and-utils.lua
--   other.lua
-- @changelog
--   - fix scale > 1.0 in dpi and reaper scale




local r = reaper
function print(...) local t = {...} for i = 1, select('#', ...) do t[i] = tostring(t[i]) end reaper.ShowConsoleMsg(table.concat(t, '\t') .. '\n') end

r.set_action_options(5)

local current_path = debug.getinfo(1, "S").source:match [[^@?(.*[\/])[^\/]-$]]
local imgui_path = r.ImGui_GetBuiltinPath() .. '/?.lua'
package.path = current_path .. '?.lua;' .. imgui_path .. ';' .. package.path
local im = require 'imgui' '0.9.3.2'
local tk = require 'color-and-utils'


-- Create two separate contexts
ctx = im.CreateContext('MIDI Editor Frame')

-- Globals for controller window
local selected_scale = tk.ordered_scales[1]
local selected_key = tk.keys[1]
local checkbox_state = true
local last_checkbox_state = false

-- Constants for both windows
local MIDI_RULLER_OFFSET = 64
local midiview = 0x000003E9
local rv_scale, scale = r.get_config_var_string("uiscale")
dpi_scale = r.ImGui_GetWindowDpiScale(ctx)

-- Controller window flags
flags_control = im.WindowFlags_NoResize | 
                     im.WindowFlags_NoCollapse | 
                     im.WindowFlags_NoTitleBar | 
                     im.WindowFlags_NoMove 

-- Piano window flags
FLAGS_PIANO = im.WindowFlags_NoBackground | 
                   im.WindowFlags_NoDecoration | 
                   im.WindowFlags_NoMove | 
                   im.WindowFlags_NoInputs | 
                   im.WindowFlags_NoFocusOnAppearing 
                   -- |  im.WindowFlags_TopMost


local mode = 'split'

local LINE_COLOR = 0xFFFFFF85
local LINE_THICKNESS = 2.7
local WINDOW_ALPHA = 0.11
local BORDER_COLOR = 0xFFFFFF40
local FILL_COLOR = 0x908A8A8A
local MOUSE_LEFT_BUTTON = 1

local WX, WY = 0, 0

local noteBoxes = {}

local LassoDrawer = {
  points = {},
  isDrawing = false,

  reset = function(self)
    self.points = {}
    self.isDrawing = false
  end,

  addPoint = function(self, x, y)
    if #self.points > 0 then
      local lx, ly = self.points[#self.points].x, self.points[#self.points].y
      if (x-lx)^2 + (y-ly)^2 < 25 then 
        return 
      end
    end
    self.points[#self.points+1] = { x = x, y = y }
  end,

  drawLines = function(self, dl)
    for i = 2, #self.points do
      im.DrawList_AddLine(dl,
        self.points[i-1].x, self.points[i-1].y,
        self.points[i].x, self.points[i].y,
        LINE_COLOR, LINE_THICKNESS
      )
    end
  end
}

local function isPointInPoly(px, py, poly)
  local inside = false
  local n = #poly
  for i=1, n do
    local j = (i < n) and (i+1) or 1
    local ix, iy = poly[i].x, poly[i].y
    local jx, jy = poly[j].x, poly[j].y
    local intersect = ((iy > py) ~= (jy > py)) 
                   and (px < (jx - ix) * (py - iy) / (jy - iy) + ix)
    if intersect then 
      inside = not inside 
    end
  end
  return inside
end

local function selectNotesInPolygon(poly)
  local take = r.MIDIEditor_GetTake(r.MIDIEditor_GetActive())
  if not take then return end
  
  r.MIDI_SelectAll(take, false)
  for _, box in ipairs(noteBoxes) do
    local cx = (box.x1 + box.x2) * 0.5
    local cy = (box.y1 + box.y2) * 0.5
    if isPointInPoly(cx, cy, poly) then
      r.MIDI_SetNote(take, box.idx, true, nil, nil, nil, nil, nil, nil, true)
    end
  end
  r.MIDI_Sort(take)
end

local function MidiInfo()
  local take = r.MIDIEditor_GetTake(r.MIDIEditor_GetActive()) 
  local item = r.GetMediaItemTake_Item(take)
  local retval, m_chunk = r.GetItemStateChunk(item, "") 
  local ME_LeftmostTick, ME_HorzZoom, ME_TopPitch, ME_PixelsPerPitch = m_chunk:match("\nCFGEDITVIEW (%S+) (%S+) (%S+) (%S+)")
  local activeChannel, ME_TimeBase = m_chunk:match("\nCFGEDIT %S+ %S+ %S+ %S+ %S+ %S+ %S+ %S+ (%S+) %S+ %S+ %S+ %S+ %S+ %S+ %S+ %S+ %S+ (%S+)")
  ME_TopPitch = 127 - ME_TopPitch
  return take, ME_LeftmostTick, ME_HorzZoom, ME_TopPitch, ME_PixelsPerPitch, ME_TimeBase
end


local SplitDrawer = {
  startX = nil, startY = nil,
  curX = nil, curY = nil,
  isDrawing = false,

  reset = function(self)
    self.startX, self.startY = nil, nil
    self.curX, self.curY = nil, nil
    self.isDrawing = false
  end,

  setStart = function(self, x, y)
    self.startX, self.startY = x, y
    self.curX, self.curY = x, y
    self.isDrawing = true
  end,

  updateCurrent = function(self, x, y)
    self.curX, self.curY = x, y
  end,

  drawLine = function(self, dl)
    if self.startX and self.startY and self.curX and self.curY then
      im.DrawList_AddLine(dl,
        self.startX, self.startY,
        self.curX, self.curY,
        0xFFFF00FF, 3.0)
    end
  end
}

local set_attempts = 0
local script_hwnd = r.JS_Window_Find('MIDI Editor Frame', false)

local function UpdateZOrder(midi_hwnd)
    local foreground_hwnd = r.JS_Window_GetForeground()
    local is_midi_foreground = (foreground_hwnd == midi_hwnd or r.JS_Window_GetParent(foreground_hwnd) == midi_hwnd)
    
    if is_midi_foreground then
        flags_control = flags_control | im.WindowFlags_TopMost
        FLAGS_PIANO = FLAGS_PIANO | im.WindowFlags_TopMost
        
        previous_hwnd = nil
        set_attempts = 0
    else
    
        if script_hwnd and set_attempts < 20 then
            r.JS_Window_SetZOrder(foreground_hwnd, "TOP", nil)
            set_attempts = set_attempts + 1
        end
        
        flags_control = flags_control & ~im.WindowFlags_TopMost
        FLAGS_PIANO = FLAGS_PIANO & ~im.WindowFlags_TopMost
        
        if script_hwnd and foreground_hwnd ~= previous_hwnd then
            previous_hwnd = foreground_hwnd
            set_attempts = 0
        end
        
    end
end

local function lineIntersectSegments(x1, y1, x2, y2, x3, y3, x4, y4)
  local denom = (y4 - y3)*(x2 - x1) - (x4 - x3)*(y2 - y1)
  if math.abs(denom) < 1e-15 then 
    return nil 
  end
  local t = ((x4 - x3)*(y1 - y3) - (y4 - y3)*(x1 - x3)) / denom
  local u = ((x2 - x1)*(y1 - y3) - (y2 - y1)*(x1 - x3)) / denom
  
  if t >= 0 and t <= 1 and u >= 0 and u <= 1 then
    local px = x1 + t*(x2 - x1)
    local py = y1 + t*(y2 - y1)
    return px, py, t
  end
  return nil
end

local function lineRectIntersection(x1, y1, x2, y2, rx1, ry1, rx2, ry2)
  if rx2 < rx1 then rx1, rx2 = rx2, rx1 end
  if ry2 < ry1 then ry1, ry2 = ry2, ry1 end
  
  local candidates = {}
  local px, py, t = lineIntersectSegments(x1, y1, x2, y2, rx1, ry1, rx1, ry2)
  if px then candidates[#candidates+1] = {px=px, py=py, t=t} end
  px, py, t = lineIntersectSegments(x1, y1, x2, y2, rx2, ry1, rx2, ry2)
  if px then candidates[#candidates+1] = {px=px, py=py, t=t} end
  px, py, t = lineIntersectSegments(x1, y1, x2, y2, rx1, ry1, rx2, ry1)
  if px then candidates[#candidates+1] = {px=px, py=py, t=t} end
  px, py, t = lineIntersectSegments(x1, y1, x2, y2, rx1, ry2, rx2, ry2)
  if px then candidates[#candidates+1] = {px=px, py=py, t=t} end
  
  if #candidates == 0 then
    return nil
  end
  
  table.sort(candidates, function(a, b) return a.t < b.t end)
  return candidates[1].px, candidates[1].py
end

  
-- Helper functions
local function isNoteInPattern(pitch, pattern)
    if not pattern then return false end
    local noteInOctave = pitch % 12 + 1
    return pattern[noteInOctave] == 1
end

local function splitNotesByLine(x1, y1, x2, y2)
  local take, LTick, zoom, topPitch, ppP, timebase = MidiInfo()
  if not take then return end
  
  r.MIDI_DisableSort(take)
  
  local _, noteCount = r.MIDI_CountEvts(take)
  local notesToSplit = {}
  
  for i = 0, noteCount - 1 do
    local retval, selected, muted,
          startppq, endppq, chan, pitch, vel = r.MIDI_GetNote(take, i)
    if retval then
      local box = noteBoxes[i+1]
      if box then

        
        local px, py = lineRectIntersection(x1, y1, x2, y2, box.x1, box.y1, box.x2, box.y2)
        
        if px then
          -- схуяли так оно работает я так и не понял
          local localX = (px - WX) * dpi_scale
          local splitPosPPQ

          if timebase == "1" then
            local timeLeftmost = r.MIDI_GetProjTimeFromPPQPos(take, LTick)
            local rawTime = timeLeftmost + (localX / zoom)
            local snappedTime = r.SnapToGrid(0, rawTime)
            splitPosPPQ = r.MIDI_GetPPQPosFromProjTime(take, snappedTime)
          else
            splitPosPPQ = LTick + (localX / zoom)
            splitPosPPQ = math.floor(splitPosPPQ + 0.5)
          end
          
          if splitPosPPQ > startppq and splitPosPPQ < endppq then
            notesToSplit[#notesToSplit+1] = {
              idx = i,
              selected = selected,
              muted = muted,
              startppq = startppq,
              endppq = endppq,
              chan = chan,
              pitch = pitch,
              vel = vel,
              splitPosPPQ= splitPosPPQ
            }
          end
        end
      end
    end
  end
  
  table.sort(notesToSplit, function(a, b) return a.idx > b.idx end)
  
  for _, noteData in ipairs(notesToSplit) do
    r.MIDI_DeleteNote(take, noteData.idx)
    r.MIDI_InsertNote(take,
      noteData.selected, 
      noteData.muted,
      noteData.startppq,
      noteData.splitPosPPQ,
      noteData.chan,
      noteData.pitch,
      noteData.vel,
      true)
    r.MIDI_InsertNote(take,
      noteData.selected,
      noteData.muted,
      noteData.splitPosPPQ,
      noteData.endppq,
      noteData.chan,
      noteData.pitch,
      noteData.vel,
      true)
  end
  
  r.MIDI_Sort(take)
end


local function getNoteText(pitch)
    local noteInOctave = pitch % 12
    local octave = math.floor(pitch / 12) - 1
    return tk.keys[noteInOctave + 1] .. octave
end


function ApplyDPIScale(value)
  
  return value / dpi_scale
end

function GetVelocityLanes()
  local HWND = r.MIDIEditor_GetActive()
  local take = r.MIDIEditor_GetTake(HWND)
  local item = r.GetMediaItemTake_Item(take)
  local retval, m_chunk = r.GetItemStateChunk(item, "")
  
  local v_s = m_chunk:find("VELLANE", nil, false)
  local v_e = m_chunk:find("CFGEDITVIEW", nil, false)
  local vel_lanes = m_chunk:sub(v_s, v_e)
  
  local lanes = {}
  local total_height = 0
  
  for lane_h in vel_lanes:gmatch("VELLANE %S+ (%S+)") do
    local height = tonumber(lane_h)
    total_height = total_height + height
    lanes[#lanes + 1] = height
  end
  
  return lanes, ApplyDPIScale(total_height)
end

local function DrawOverMidi(hwnd, ctx)
    local retval, left, top, right, bottom = r.JS_Window_GetClientRect(hwnd)

    local lanes, total_lane_height = GetVelocityLanes()
    
    ctx_piano = ctx
    
    if old_val ~= left + top + right + bottom  or old_val2 ~= total_lane_height then
        old_val, old_val2 = left + top + right + bottom, total_lane_height
        left, top = im.PointConvertNative(ctx_piano, left, top)
        top = top + MIDI_RULLER_OFFSET * scale
        
        right, bottom = im.PointConvertNative(ctx_piano, right, bottom)
        im.SetNextWindowPos(ctx_piano, left, top)
        im.SetNextWindowSize(ctx_piano, (right - left), (bottom - top) - total_lane_height)
    end
end

local function DrawMidiNotes(dl)
  noteBoxes = {}
  local take, LTick, zoom, topPitch, ppP, timebase = MidiInfo()
  if not take then return end
  
  local _, noteCount = r.MIDI_CountEvts(take)
  for i = 0, noteCount - 1 do
    local _, sel, _, startppq, endppq, _, pitch = r.MIDI_GetNote(take, i)
    local note_x, note_w
    
    if timebase == "1" then
      local startTime = r.MIDI_GetProjTimeFromPPQPos(take, startppq)
      local endTime = r.MIDI_GetProjTimeFromPPQPos(take, endppq)
      local leftTime = r.MIDI_GetProjTimeFromPPQPos(take, LTick)
      note_x = ApplyDPIScale((startTime - leftTime) * zoom)
      note_w = ApplyDPIScale((endTime - startTime) * zoom)
    else
      local ppq_diff = startppq - LTick
      note_x = ApplyDPIScale(ppq_diff * zoom)
      note_w = ApplyDPIScale((endppq - startppq) * zoom)
    end
    
    local diff = ApplyDPIScale((topPitch - pitch))
    local note_y = diff * ppP + MIDI_RULLER_OFFSET
    
    local xs, ys = WX + note_x, WY + note_y - MIDI_RULLER_OFFSET 
    local xe, ye = xs + note_w, ys + ApplyDPIScale(ppP)
    local col = sel and 0xFF00FF00 or 0xFF0000FF
    
    im.DrawList_AddRect(dl, xs, ys, xe, ye, col, nil, nil, 2) 
    
    noteBoxes[#noteBoxes+1] = {
      idx = i,
      x1 = xs, y1 = ys, 
      x2 = xe, y2 = ye,
      startppq = startppq,
      endppq = endppq,
      pitch = pitch
    }
  end
end

local function DrawPianoKeys(draw_list, windowWidth, windowHeight, ME_TopPitch, ME_PixelsPerPitch, scalePattern)
    local keyHeight = ApplyDPIScale( ME_PixelsPerPitch )
    
    for pitch = 0, 127 do
        local pitch_diff = (ME_TopPitch - pitch)
        local key_y = WY + ApplyDPIScale(pitch_diff) * ME_PixelsPerPitch
        
        local keyColor = isNoteInPattern(pitch, scalePattern) 
            and tk.set_color('purple#30') 
            or tk.set_color('#1a1a1a80')
        
        im.DrawList_AddRectFilled(
            draw_list,
            WX,
            key_y,
            WX + windowWidth,
            key_y + keyHeight,
            keyColor
        )
        
        local fontSize = math.min(keyHeight * 0.8, 12)
        im.DrawList_AddText(
            draw_list,
            WX + 5,
            key_y + (keyHeight - fontSize) / 2,
            0xFFFFFFFF,
            getNoteText(pitch)
        )
    end
end

local function DrawControlWindow(HWND, child_hwnd)
    local retval, left, top, right, bottom = r.JS_Window_GetRect(child_hwnd)
    local width_window = tk.clamp((right-left) * 0.55, 150, 420)
    
    ctx_control = ctx
    if not HWND and ctx then left = -100 top = -100 end
    im.SetNextWindowPos(ctx, ApplyDPIScale(left + 1), ApplyDPIScale(top + 1))
    im.SetNextWindowSize(ctx, width_window, 35)
    
    -- Style setup
    im.PushStyleColor(ctx, im.Col_Border, tk.set_color('transparent'))
    
    im.PushStyleVar(ctx_control, im.StyleVar_FramePadding, 2.5, 2.5)
    im.PushStyleVar(ctx_control, im.StyleVar_FrameRounding, 2)
    --im.PushStyleVar(ctx_control, im.StyleVar_Alpha, 0.9)
    im.SetNextWindowBgAlpha( ctx, 0 )
    local visible, open = im.Begin(ctx_control, 'MIDI Editor Frame', true, flags_control)
    
    if visible then
        local rv, new_checkbox_state = im.Checkbox(ctx_control, "##Enable", checkbox_state)
        if rv then
            checkbox_state = new_checkbox_state
        end
        
        im.SameLine(ctx_control)
        
        -- Key selector
        im.PushItemWidth(ctx_control, 40)
        if im.BeginCombo(ctx_control, "##Key", selected_key) then
            for _, key in ipairs(tk.keys) do
                local is_selected = (selected_key == key)
                if im.Selectable(ctx_control, key, is_selected) then
                    selected_key = key
                end
                if is_selected then
                    im.SetItemDefaultFocus(ctx_control)
                end
            end
            im.EndCombo(ctx_control)
        end
        im.PopItemWidth(ctx_control)
        im.SameLine(ctx_control)
        
        -- Scale selector
        --local window_width = im.GetWindowWidth(ctx_control)
       -- local remaining_width = 150--window_width - im.GetCursorPosX(ctx_control) - 80
        im.PushItemWidth(ctx_control, 150)
        if im.BeginCombo(ctx_control, "##Scale", selected_scale) then
            for _, scale_name in ipairs(tk.ordered_scales) do
                local is_selected = (selected_scale == scale_name)
                if im.Selectable(ctx_control, scale_name, is_selected) then
                    selected_scale = scale_name
                end
                if is_selected then
                    im.SetItemDefaultFocus(ctx_control)
                end
            end
            im.EndCombo(ctx_control)
        end
        im.PopItemWidth(ctx_control)
        
        im.SameLine(ctx_control)
        
        
        if im.Button(ctx, ""..mode, 65) then
          mode = (mode == "lasso") and "split" or "lasso"
        end
        
        
        im.End(ctx_control)
    end
    
    im.PopStyleVar(ctx_control, 2)
    im.PopStyleColor(ctx_control, 1)
    return open
end


local function DrawPianoWindow(child_hwnd)
    if not checkbox_state then return true end
    
    DrawOverMidi(child_hwnd, ctx)
    im.PushStyleVar(ctx, im.StyleVar_Alpha, 0.1)
    local visible, open = im.Begin(ctx, 'Piano Roll Overlay', true, FLAGS_PIANO)
    
    if visible then
        
        WX, WY = im.GetWindowPos(ctx)
        draw_list = im.GetWindowDrawList(ctx)
        -- DrawMidiNotes(draw_list)
        local _, _, _, ME_TopPitch, ME_PixelsPerPitch = MidiInfo()
        local windowWidth = im.GetWindowWidth(ctx)
        local windowHeight = im.GetWindowHeight(ctx)
        local scalePattern = tk.getScalePattern(selected_key, selected_scale)
        DrawPianoKeys(draw_list, windowWidth, windowHeight, ME_TopPitch, ME_PixelsPerPitch, scalePattern)
        
        
        local mx, my = r.GetMousePosition()
        mx, my = ApplyDPIScale(mx), ApplyDPIScale(my)
        local _, l, t, rr, bb = r.JS_Window_GetClientRect(child_hwnd)
        l, t, rr, bb = ApplyDPIScale(l), ApplyDPIScale(t), ApplyDPIScale(rr), ApplyDPIScale(bb)
        local mouseState = r.JS_Mouse_GetState(14)
        
        if mode == "lasso" then
          if mouseState == 14 then
          
            if mx>=l and mx<=rr and my>=t and my<=bb then
              LassoDrawer.isDrawing = true
              LassoDrawer:addPoint(mx, my)
              
              LassoDrawer:drawLines(draw_list)
            end
          else
            if LassoDrawer.isDrawing then
              DrawMidiNotes(draw_list)
              selectNotesInPolygon(LassoDrawer.points)
              LassoDrawer:reset()
            end
          end
          
        else
          if mouseState == 14 then
            if not SplitDrawer.isDrawing then
              SplitDrawer:setStart(mx, my)
            else
              SplitDrawer:updateCurrent(mx, my)
              SplitDrawer:drawLine(draw_list)
            end
          else
            
            if SplitDrawer.isDrawing then
              DrawMidiNotes(draw_list)
              splitNotesByLine(
                SplitDrawer.startX, SplitDrawer.startY,
                SplitDrawer.curX, SplitDrawer.curY
              )
              SplitDrawer:reset()
            end
          end
        end
        
        im.End(ctx)
    end
    
    
    
    im.PopStyleVar(ctx_piano, 1)
    return open
end

local function main()
    local midi_hwnd = r.MIDIEditor_GetActive()
    if not midi_hwnd then 
        r.defer(main)
        im.SetNextWindowPos(ctx, 0, 0)
        return
    end
    
    
    
    local child_hwnd = r.JS_Window_FindChildByID(midi_hwnd, midiview)
    UpdateZOrder(midi_hwnd)
    local control_open = DrawControlWindow(midi_hwnd, child_hwnd)
    local piano_open = DrawPianoWindow(child_hwnd)
    
    if control_open and piano_open then
        r.defer(main)
    end
end

r.atexit(function() r.set_action_options(8) end)
r.defer(main)