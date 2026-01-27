-- @description MIDI Pitch Highlighter
-- @author mrtnz
-- @version 1.1
-- @about
--   Visual overlay for MIDI editor that highlights selected pitches on piano roll.
--   Works with pitch move scripts via gmem.
-- @provides
--   [main] .
--   [main] mrtnz_MIDI Pitch - Semitone (Mousewheel).lua
--   [main] mrtnz_MIDI Pitch - Octave (Mousewheel).lua


function AddScriptStartup()
    local ac = {reaper.get_action_context()}
    local scriptPath = ac[2]
    if not scriptPath or scriptPath == "" then return end
  
    local cmdID = reaper.NamedCommandLookup(scriptPath)
    if cmdID == 0 then
      cmdID = reaper.AddRemoveReaScript(true, 0, scriptPath, true)
      if cmdID == 0 then return end
    end
  
    local scriptID = reaper.ReverseNamedCommandLookup(cmdID)
    if not scriptID or scriptID == "" then return end
  
    if scriptID:sub(1,1) ~= "_" then
      scriptID = "_" .. scriptID
    end
  
    local startupFile = reaper.GetResourcePath() .. '/Scripts/__startup.lua'
    local exists = false
    local f, err = io.open(startupFile, "r")
    if f then
      for line in f:lines() do
        if line:find('reaper%.NamedCommandLookup%("%s*' .. scriptID .. '%s*"%)') then
          exists = true
          break
        end
      end
      f:close()
    end
  
    if exists then return end
  
    local newCmd = string.format('reaper.Main_OnCommand(reaper.NamedCommandLookup("%s"), 0) -- %s erik', scriptID, scriptID)
    f, err = io.open(startupFile, "a")
    if f then
      f:write("\n" .. newCmd .. "\n")
      f:close()
    end
end


function RemoveScriptStartup()
    local ac = {reaper.get_action_context()}
    local scriptPath = ac[2]
    if not scriptPath or scriptPath == "" then return end
  
    local cmdID = reaper.NamedCommandLookup(scriptPath)
    if cmdID == 0 then
      cmdID = reaper.AddRemoveReaScript(true, 0, scriptPath, true)
      if cmdID == 0 then return end
    end
  
    local scriptID = reaper.ReverseNamedCommandLookup(cmdID)
    if not scriptID or scriptID == "" then return end
  
    if scriptID:sub(1,1) ~= "_" then
      scriptID = "_" .. scriptID
    end
  
    local startupFile = reaper.GetResourcePath() .. '/Scripts/__startup.lua'
    local lines = {}
    local f, err = io.open(startupFile, "r")
    if f then
      for line in f:lines() do
        if not line:find('reaper%.NamedCommandLookup%("%s*' .. scriptID .. '%s*"%)') then
          table.insert(lines, line)
        end
      end
      f:close()
    end
  
    f, err = io.open(startupFile, "w")
    if f then
      f:write(table.concat(lines, "\n"))
      f:close()
    end
end


local r = reaper
r.set_action_options(5)

-- ==== GMEM SETUP ====
r.gmem_attach('LordOfThePitch_Shared') 


AddScriptStartup()

-- ==== IMGUI IMPORT ====
local current_path = debug.getinfo(1, "S").source:match [[^@?(.*[\\/])[^\\/]-$]]
local imgui_path = r.ImGui_GetBuiltinPath() .. '/?.lua'
package.path = current_path .. '?.lua;' .. imgui_path .. ';' .. package.path
local im = require 'imgui' '0.9.3.2'

-- ==== CONFIG ====
local FADE_TIME = 2.0 
local MIDI_RULER_OFFSET = 64
local MIDIVIEW_ID = 0x000003E9
local BASE_COLOR = 0x7d4a83 -- Базовый цвет (RGB)

-- Auto-generate colors from base
local COL_PROD_WHITE_SEL = (BASE_COLOR << 8) | 0x90
local COL_PROD_BLACK_SEL = (BASE_COLOR << 8) | 0xFF
local COL_PROD_MIDI_SEL  = (BASE_COLOR << 8) | 0x30
local COL_BLACK_MASK     = 0x141414FF -- 303030

local FLAGS = 
    im.WindowFlags_NoBackground |
    im.WindowFlags_NoDecoration |
    im.WindowFlags_NoMove |
    im.WindowFlags_NoInputs |
    im.WindowFlags_NoFocusOnAppearing

local ctx = im.CreateContext('Lord of the Windows: GMEM Overlay')
local dpi_scale = 1
local WX, WY = 0, 0
local old_rect = ""

-- State
local active_pitches = {}
local last_update_id = -1
local fade_timer = 0.0
local last_time = r.time_precise()

-- ==== HELPERS ====
local function GetUIScale()
  local ok, s = r.get_config_var_string("uiscale")
  local v = tonumber(s)
  if ok and v and v > 0 then return v end
  return 1
end

local function ApplyDPI(v)
  if not dpi_scale or dpi_scale == 0 then return v end
  return v / dpi_scale
end

local function ModulateAlpha(col, timer)
  if timer <= 0 then return 0 end
  local factor = math.min(timer, 0.5) / 0.5 
  if timer > 0.5 then factor = 1.0 end
  local r, g, b, a = (col >> 24) & 0xFF, (col >> 16) & 0xFF, (col >> 8) & 0xFF, col & 0xFF
  a = math.floor(a * factor)
  return (r << 24) | (g << 16) | (b << 8) | a
end

local function MidiInfo()
  local ed = r.MIDIEditor_GetActive()
  if not ed then return nil end
  local take = r.MIDIEditor_GetTake(ed)
  if not take then return nil end
  local item = r.GetMediaItemTake_Item(take)
  if not item then return nil end
  local _, chunk = r.GetItemStateChunk(item, "")
  local LTick, zoom, topPitch, ppP = chunk:match("\nCFGEDITVIEW (%S+) (%S+) (%S+) (%S+)")
  if not topPitch or not ppP then return nil end
  return take, chunk, 127 - tonumber(topPitch), tonumber(ppP)
end

local function GetVelLanesHeight(chunk)
  local total = 0
  for h in chunk:gmatch("VELLANE %S+ (%S+)") do total = total + tonumber(h) end
  return total
end

local function GetMidiChildRects()
  local midi_hwnd = r.MIDIEditor_GetActive()
  if not midi_hwnd then return nil end
  local midiview_hwnd = r.JS_Window_FindChildByID(midi_hwnd, MIDIVIEW_ID)
  if not midiview_hwnd then midiview_hwnd = r.JS_Window_FindChild(midi_hwnd, "midiview", true) end
  local pianoview_hwnd = r.JS_Window_FindChild(midi_hwnd, "midipianoview", true)
  if not midiview_hwnd then return nil end
  return midi_hwnd, midiview_hwnd, pianoview_hwnd
end

local note_names = {"C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"}
local function GetNoteName(pitch)
  local octave = math.floor(pitch / 12) - 1
  local note = note_names[(pitch % 12) + 1]
  return note .. octave
end

local function IsBlackKey(pitch)
  local n = pitch % 12
  return n == 1 or n == 3 or n == 6 or n == 8 or n == 10
end

-- ==== GEOMETRY ====
local function GetPianoKeyGeometry(pitch, baseY, ppP)
  local n = pitch % 12
  if IsBlackKey(pitch) then return baseY - 1, ppP + 2 end
  local whiteH = ppP * 1.714 
  local midY    = baseY + (ppP / 2)
  local bottomY = baseY + ppP
  local y = baseY
  
  if n == 0 then y = bottomY - whiteH
  elseif n == 2 then y = midY - (whiteH / 2)
  elseif n == 4 then y = baseY
  elseif n == 5 then y = bottomY - whiteH
  elseif n == 7 then 
    local offset = ppP * 0.12
    whiteH = ppP * 1.72
    y = midY - (whiteH / 2) - offset
  elseif n == 9 then 
    local offset = ppP * 0.12
    whiteH = ppP * 1.76
    y = midY - (whiteH / 2) + offset
  elseif n == 11 then y = baseY
  end
  return y, whiteH
end

-- ==== DRAWING ====
local function DrawVisuals(dl, piano_width, width, height, topPitch, ppP)
  if fade_timer <= 0 then return end
  
  local keyH_base = ApplyDPI(ppP)
  
  local col_white = ModulateAlpha(COL_PROD_WHITE_SEL, fade_timer)
  local col_black = ModulateAlpha(COL_PROD_BLACK_SEL, fade_timer)
  local col_midi  = ModulateAlpha(COL_PROD_MIDI_SEL, fade_timer)
  local col_mask  = ModulateAlpha(COL_BLACK_MASK, fade_timer)
  local col_text  = ModulateAlpha(0x000000FF, fade_timer)
  local col_text_w= ModulateAlpha(0xFFFFFFFF, fade_timer)

  -- 1. WHITE KEYS (Подложка)
  for pitch = 0, 127 do
    if not IsBlackKey(pitch) then
      local baseY = WY + ApplyDPI((topPitch - pitch) * ppP)
      local keyY, keyH = GetPianoKeyGeometry(pitch, baseY, keyH_base)
      if keyY + keyH >= WY and keyY <= WY + height then
        if active_pitches[pitch] then
            im.DrawList_AddRectFilled(dl, WX, keyY, WX + piano_width, keyY + keyH, col_white)
            
            -- РИСУЕМ ТЕКСТ ТОЛЬКО ЕСЛИ ЭТО НЕ "C" (ДО)
            if pitch % 12 ~= 0 then
                local note_name = GetNoteName(pitch)
                local tw, th = im.CalcTextSize(ctx, note_name)
                local textX = WX + piano_width - tw - 4
                local textY = keyY + (keyH/2) - (th/2)
                
                im.DrawList_AddText(dl, textX, textY, col_text, note_name)
            end
        end
      end
    end
  end


  -- 2. BLACK KEYS (Поверх белых)
  for pitch = 0, 127 do
    if IsBlackKey(pitch) then
      local baseY = WY + ApplyDPI((topPitch - pitch) * ppP)
      local keyY, keyH = GetPianoKeyGeometry(pitch, baseY, keyH_base)
      if keyY + keyH >= WY and keyY <= WY + height then
        local blackW = piano_width * 0.58 
        
        if active_pitches[pitch] then
            -- Если черная выбрана - рисуем выделение
            im.DrawList_AddRectFilled(dl, WX, keyY, WX + blackW, keyY + keyH + 1, col_black)
            
            local note_name = GetNoteName(pitch)
            local _, th = im.CalcTextSize(ctx, note_name)
            im.DrawList_AddText(dl, WX + 2, keyY + (keyH/2) - (th/2), col_text_w, note_name)
        else
            -- [МАСКИРОВКА] Если черная не выбрана, но соседние белые "залезли" под неё
            if active_pitches[pitch-1] or active_pitches[pitch+1] then
               -- Рисуем её непрозрачной (или фейдящейся) маской поверх белого выделения
               im.DrawList_AddRectFilled(dl, WX, keyY, WX + blackW, keyY + keyH + 1, col_mask)
            end
        end
      end
    end
  end
  
  -- 3. MIDI LINES
  local boundary = piano_width
  local midi_keyH = ApplyDPI(ppP)
  for pitch = 0, 127 do
    if active_pitches[pitch] then
        local y = WY + ApplyDPI((topPitch - pitch) * ppP)
        if y >= WY and y <= WY + height then
             im.DrawList_AddRectFilled(dl, WX + boundary, y, WX + width, y + midi_keyH, col_midi)
        end
    end
  end
end

local function Frame()
  local now = r.time_precise()
  local dt = now - last_time
  last_time = now
  
  local current_id = r.gmem_read(0)
  if current_id ~= last_update_id then
      last_update_id = current_id
      active_pitches = {}
      local count = r.gmem_read(1)
      for i = 1, count do
         local p = r.gmem_read(1 + i)
         active_pitches[p] = true
      end
      fade_timer = FADE_TIME
  end
  
  if fade_timer > 0 then fade_timer = fade_timer - dt end
  
  if not im.ValidatePtr(ctx, "ImGui_Context*") then ctx = im.CreateContext('Lord of the Windows: GMEM Overlay') end
  dpi_scale = im.GetWindowDpiScale(ctx)
  local take, chunk, topPitch, ppP = MidiInfo()
  if not take then r.defer(Frame); return end 
  
  local _, midiview_hwnd, pianoview_hwnd = GetMidiChildRects()
  if not midiview_hwnd then r.defer(Frame); return end
  
  local uiscale = GetUIScale()
  local ok, l, t, rr, bb = r.JS_Window_GetClientRect(midiview_hwnd)
  if not ok then ok, l, t, rr, bb = r.JS_Window_GetRect(midiview_hwnd); if not ok then r.defer(Frame); return end end
  local piano_left, piano_right = l, l
  if pianoview_hwnd then
    local okp, pl, pt, pr, pb = r.JS_Window_GetRect(pianoview_hwnd)
    if okp then piano_left, piano_right = pl, pr end
  end
  local velH = GetVelLanesHeight(chunk)
  local rect_key = piano_left..l..t..rr..bb..velH
  if rect_key ~= old_rect then
    old_rect = rect_key
    local left, top = im.PointConvertNative(ctx, piano_left, t)
    local right, bottom = im.PointConvertNative(ctx, rr, bb)
    top = top + MIDI_RULER_OFFSET * uiscale
    local velH_scaled = ApplyDPI(velH * uiscale)
    im.SetNextWindowPos(ctx, left, top)
    im.SetNextWindowSize(ctx, right - left, bottom - top - velH_scaled)
  end
  
  local visible, open = im.Begin(ctx, 'MIDI Pitch Lines GMEM', true, FLAGS)
  if visible then
    if fade_timer > 0 and topPitch and ppP then
        WX, WY = im.GetWindowPos(ctx)
        local dl = im.GetWindowDrawList(ctx)
        local width, height = im.GetWindowWidth(ctx), im.GetWindowHeight(ctx)
        local piano_left_imgui, _ = im.PointConvertNative(ctx, piano_left, t)
        local piano_right_imgui, _ = im.PointConvertNative(ctx, piano_right, t)
        local piano_width = piano_right_imgui - piano_left_imgui
        
        DrawVisuals(dl, piano_width, width, height, topPitch, ppP)
    end
    im.End(ctx)
  end
  if open then r.defer(Frame) end
end

r.atexit(function() r.set_action_options(8) end)
r.defer(Frame)
