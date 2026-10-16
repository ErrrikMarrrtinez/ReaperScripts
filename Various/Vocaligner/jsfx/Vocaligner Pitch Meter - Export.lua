-- @noindex
-- @description Vocaligner Pitch Meter - Export
-- Saves the measurement of "JS: Vocaligner Pitch Meter" as frames.csv,
-- notes.csv and report.txt next to the project, and optionally creates a
-- MIDI item with the detected notes. JSFX cannot write files itself, so the
-- meter publishes its data to shared memory and this script saves it.
local r = reaper
local NAME, NS = 'Vocaligner Pitch Meter', 'VocalignerPitchMeter'
local MAGIC, REG, REGSZ, NSLOT = 5263437, 64, 64, 8
local NFR = 240000
local EXP = 1024 + NSLOT*3*NFR + 4096

local function msg(text, title, kind) return r.ShowMessageBox(text, title or 'Vocaligner Pitch Meter', kind or 0) end
if not r.gmem_attach then msg('This REAPER version has no gmem API.'); return end
r.gmem_attach(NS)
local function rd(i) return r.gmem_read(i) end

-- Find a meter on the selected track (track FX) or in a selected item's take.
local function instance_id(name_of, value_of, count)
  for p = 0, count - 1 do
    local ok, name = name_of(p)
    if ok and name:find('Instance ID', 1, true) then return math.floor(value_of(p) + 0.5) end
  end
end
local targets = {}
for i = 0, r.CountSelectedMediaItems(0) - 1 do
  local item = r.GetSelectedMediaItem(0, i); local take = r.GetActiveTake(item)
  if take then for fx = 0, r.TakeFX_GetCount(take) - 1 do
    local ok, name = r.TakeFX_GetFXName(take, fx, '')
    if ok and name:find(NAME, 1, true) then
      targets[#targets + 1] = {kind = 'take', item = item, track = r.GetMediaItem_Track(item), label = 'take FX in ' .. r.GetTakeName(take),
        id = instance_id(function(p) return r.TakeFX_GetParamName(take, fx, p, '') end, function(p) return r.TakeFX_GetParam(take, fx, p) end, r.TakeFX_GetNumParams(take, fx))}
    end
  end end
end
local function add_track(track)
  for fx = 0, r.TrackFX_GetCount(track) - 1 do
    local ok, name = r.TrackFX_GetFXName(track, fx, '')
    if ok and name:find(NAME, 1, true) then
      local _, tname = r.GetTrackName(track)
      targets[#targets + 1] = {kind = 'track', track = track, label = 'track FX on ' .. tname,
        id = instance_id(function(p) return r.TrackFX_GetParamName(track, fx, p, '') end, function(p) return r.TrackFX_GetParam(track, fx, p) end, r.TrackFX_GetNumParams(track, fx))}
    end
  end
end
for i = 0, r.CountSelectedTracks(0) - 1 do add_track(r.GetSelectedTrack(0, i)) end
if #targets == 0 then for i = 0, r.CountTracks(0) - 1 do add_track(r.GetTrack(0, i)) end end

local target = targets[1]
if #targets > 1 then
  local labels = {}; for i, t in ipairs(targets) do labels[i] = t.label:gsub('|', '/') end
  gfx.init('', 0, 0); gfx.x, gfx.y = gfx.mouse_x, gfx.mouse_y
  local choice = gfx.showmenu(table.concat(labels, '|')); gfx.quit()
  if choice < 1 then return end
  target = targets[choice]
end

local function slot_of(id)
  if not id then return nil end
  for e = 0, NSLOT - 1 do if rd(REG + e*REGSZ) == id then return e end end
end

local function save()
  if rd(EXP + 1) ~= 2 then msg('No published measurement. Open the Pitch Meter window and press Export.'); return end
  local hop, nframes, fstride, foff = rd(EXP + 3), rd(EXP + 5), rd(EXP + 6), rd(EXP + 7)
  local nnotes, nstride, noff = rd(EXP + 8), rd(EXP + 9), rd(EXP + 10)
  local rlen, roff, a4 = rd(EXP + 11), rd(EXP + 12), rd(EXP + 14)
  local placement = rd(EXP + 20) % 2 == 1 and 'take FX' or 'track FX'
  local chars = {}
  for i = 0, rlen - 1 do local c = math.floor(rd(roff + i)); if c > 0 and c < 256 then chars[#chars + 1] = string.char(c) end end
  local report = table.concat(chars)
  local base = r.GetProjectPath('')
  local folder = base .. '/VocalignerPitchMeter/' .. os.date('%Y%m%d-%H%M%S')
  r.RecursiveCreateDirectory(folder, 0)
  local function midi(hz) return hz > 0 and 69 + 12*math.log(hz/a4, 2) or 0 end
  local f = assert(io.open(folder .. '/frames.csv', 'w'))
  f:write('time_s,hz,midi,confidence,level_db,pass,prev_hz,ref_hz,state\n')
  for k = 0, nframes - 1 do
    local o = foff + k*fstride
    local hz = rd(o + 1)
    f:write(string.format('%.4f,%.4f,%.4f,%.4f,%.2f,%d,%.4f,%.4f,%d\n', rd(o), hz, midi(hz), rd(o + 2), rd(o + 3), rd(o + 4), rd(o + 5), rd(o + 6), rd(o + 7)))
  end
  f:close()
  local notes = {}
  f = assert(io.open(folder .. '/notes.csv', 'w'))
  f:write('start_s,end_s,center_midi,et_cents,peak_db,confidence,drift_cents,vibrato_hz,vibrato_cents,min_midi,max_midi,ghost_delta_cents\n')
  for k = 0, nnotes - 1 do
    local o = noff + k*nstride; local v = {}
    for j = 0, 11 do v[j + 1] = rd(o + j) end
    notes[#notes + 1] = v
    f:write(string.format('%.4f,%.4f,%.4f,%.2f,%.2f,%.3f,%.1f,%.2f,%.1f,%.3f,%.3f,%s\n', v[1], v[2], v[3], v[4], v[5], v[6], v[7], v[8], v[9], v[10], v[11], v[12] > -9999 and string.format('%.1f', v[12]) or ''))
  end
  f:close()
  f = assert(io.open(folder .. '/report.txt', 'w'))
  f:write(report)
  f:write(string.format('\nExported %s | %s | %d frames | %d notes | hop %.3f s | A4 %.1f Hz\n', os.date('%Y-%m-%d %H:%M:%S'), placement, nframes, nnotes, hop, a4))
  f:write('Times are the host timeline seen by the meter (project time for a track FX).\n')
  f:close()
  r.ShowConsoleMsg('Vocaligner Pitch Meter export: ' .. folder .. '\n' .. report .. '\n')
  if #notes > 0 and msg(string.format('Saved %d frames and %d notes to\n%s\n\nCreate a MIDI item with the detected notes on a new track?', nframes, #notes, folder), nil, 4) == 6 then
    r.Undo_BeginBlock()
    local index = target and target.track and r.GetMediaTrackInfo_Value(target.track, 'IP_TRACKNUMBER') or r.CountTracks(0)
    r.InsertTrackAtIndex(index, true)
    local track = r.GetTrack(0, index)
    r.GetSetMediaTrackInfo_String(track, 'P_NAME', 'Pitch Meter notes', true)
    local t0, t1 = notes[1][1], notes[#notes][2]
    local item = r.CreateNewMIDIItemInProj(track, t0, t1, false)
    local take = r.GetActiveTake(item)
    for _, v in ipairs(notes) do
      local p0 = r.MIDI_GetPPQPosFromProjTime(take, v[1]); local p1 = r.MIDI_GetPPQPosFromProjTime(take, v[2])
      local vel = math.max(1, math.min(127, math.floor(127 + v[5]*2)))
      r.MIDI_InsertNote(take, false, false, p0, p1, 0, math.floor(v[3] + 0.5), vel, true)
    end
    r.MIDI_Sort(take)
    r.Undo_EndBlock('Vocaligner Pitch Meter: notes to MIDI', -1)
    r.UpdateArrange()
  else
    msg(string.format('Saved %d frames and %d notes to\n%s', nframes, #notes, folder))
  end
end

if rd(0) ~= MAGIC then msg('No running Vocaligner Pitch Meter found.'); return end
local slot = target and slot_of(target.id)
if not slot then
  -- Use whatever the meter's own Export button published last.
  if rd(EXP + 1) == 2 then save() else msg('The meter has no shared-memory slot yet. Open its window once, or press its Export button.') end
  return
end
local eb = REG + slot*REGSZ
local token = math.floor(r.time_precise()*1000) % 1000000000 + 1
r.gmem_write(eb + 24, token)
local started = r.time_precise()
local function wait()
  if rd(eb + 25) == token and rd(EXP) == token and rd(EXP + 1) == 2 then save(); return end
  if r.time_precise() - started > 4 then
    if rd(EXP + 1) == 2 and msg('The meter did not answer (its UI thread may be idle). Save the last published measurement instead?', nil, 4) == 6 then save() end
    return
  end
  r.defer(wait)
end
wait()
