-- @description Split note to equal parts(mousewheel ctx)
-- @author mrtnz
-- @version 1.0
-- @about
--  ...



local midiEditor = reaper.MIDIEditor_GetActive()
local take = reaper.MIDIEditor_GetTake(midiEditor)
if not take or not reaper.TakeIsMIDI(take) then return end



function table.serialize(obj)
  local lua = ""
  local t = type(obj)
  if t == "number" then
      lua = lua .. obj
  elseif t == "boolean" then
      lua = lua .. tostring(obj)
  elseif t == "string" then
      lua = lua .. string.format("%q", obj)
  elseif t == "table" then
      lua = lua .. "{\n"
  for k, v in pairs(obj) do
      lua = lua .. "[" .. table.serialize(k) .. "]=" .. table.serialize(v) .. ",\n"
  end
      lua = lua .. "}"
  elseif t == "nil" then
      return nil
  else
      error("can not serialize a " .. t .. " type.")
  end
  return lua
end

function table.unserialize(lua)
    local t = assert(load("return "..lua))()
    return t
end

function getNote(sel)
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

function selNoteIterator()
    local sel=-1
    return function()
        sel=reaper.MIDI_EnumSelNotes(take, sel)
        if sel==-1 then return end
        return getNote(sel)
    end
end

function saveData(key1,key2,data)
  reaper.SetExtState(key1, key2, data, false)
end

function loadData(key1,key2)
    return reaper.GetExtState(key1, key2)
end


function saveSelectedNotesToExstate(key)
    local notes={}
    for note in selNoteIterator() do
        table.insert(notes,note)
    end
    saveData(key,"data",table.serialize(notes))
end


function loadNotesFromExstateAndInsert(key)
    local data = loadData(key,"data")
    local notes = table.unserialize(data)

    for _, note in ipairs(notes) do
        reaper.MIDI_InsertNote(take, note.selected, note.muted, note.startPos, note.endPos, note.channel, note.pitch, note.vel, false)
    end

    reaper.MIDI_Sort(take)
end


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

function checkIdenticalNotesWithSaved(key)
    local savedData = loadData(key,"data")
    if savedData == "" then 
        saveData(key, "data", "0")
        return false
    end
    local savedNotes = table.unserialize(savedData)

    local currentNotes={}
    for note in selNoteIterator() do
        table.insert(currentNotes,note)
    end

    if #savedNotes ~= #currentNotes then
        return false
    end

    for i, note in ipairs(currentNotes) do
        for k, v in pairs(note) do
            if savedNotes[i][k] ~= v then
                return false
            end
        end
    end

    return true
end

local interp_type = "quadr"

function split(value, ofs, interp_type, useTick)
  if midiEditor == nil or value == nil then return end
  reaper.MIDI_DisableSort(take)
  local _, noteCount = reaper.MIDI_CountEvts(take)
  if noteCount > 0 then
    local notes = {}
    for i = 1, noteCount do
      local note = {}
      _, note.sel, note.muted, note.start, note.ending, note.chan, note.pitch, note.vel = reaper.MIDI_GetNote(take, i - 1)
      if note.sel and (useTick and value > note.ending - note.start or not useTick and value <= 0) then return end
      table.insert(notes, note)
    end
    for i = 1, noteCount do reaper.MIDI_DeleteNote(take, 0) end
    for _, note in ipairs(notes) do
      local len = note.ending - note.start
      local div = useTick and math.floor(len / value) or value
      if note.sel then
        for j = 1, div do
          local t = (j-1)/div
          local interp = (1-ofs)*t + ofs*t*t -- квадратичная интерполяция
          local next_t = j / div
          local next_interp = (1-ofs)*next_t + ofs*next_t*next_t
          local note_start = note.start + interp*len
          local note_end = note.start + next_interp*len
          reaper.MIDI_InsertNote(take, note.sel, note.muted, note_start, note_end, note.chan, note.pitch, note.vel, false)
        end
      else
        reaper.MIDI_InsertNote(take, note.sel, note.muted, note.start, note.ending, note.chan, note.pitch, note.vel, false)
      end
    end
    reaper.MIDI_Sort(take)
  end
end

div=2
ofs=0


local r = reaper


function run(useTick, increaseDiv) 
    local lastDiv = tonumber(r.GetExtState("MyScript", "lastDiv")) or 1
    if checkIdenticalNotesWithSaved("SaveSelectedNotes_B") then 
        if increaseDiv then
            div = lastDiv + 1 
        else
            div = math.max(1, lastDiv - 1)  
        end
        deleteSelectedNotes() 
        loadNotesFromExstateAndInsert("SaveSelectedNotes_A")
    else 
        saveSelectedNotesToExstate("SaveSelectedNotes_A")
        div = 2
    end
    
    split(div, ofs, interp_type, useTick) 
    saveSelectedNotesToExstate("SaveSelectedNotes_B")
    r.SetExtState("MyScript", "lastDiv", tostring(div), false)
    r.UpdateArrange()
end


function adjustWithMouseWheel()
    local _, _, _, _, _, _, val = r.get_action_context()
    r.Undo_BeginBlock()
    if val > 0 then
        run(false, true)
    else
        run(false, false) 
    end
    r.Undo_EndBlock("Split note to equal", -1)
end


adjustWithMouseWheel()

