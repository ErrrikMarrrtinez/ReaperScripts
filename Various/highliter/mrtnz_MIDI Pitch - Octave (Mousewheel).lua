-- @noindex


local r = reaper

-- ==== CONFIG ====
local INVERT_WHEEL = true
local MOVE_AMOUNT = 12 -- Octave (12 semitones)

r.gmem_attach('LordOfThePitch_Shared') 

function Main()
  local is_new,name,sec,cmd,rel,res,val = reaper.get_action_context()
  if val == 0 then return end
  
  local move = 0
  if val > 0 then move = MOVE_AMOUNT else move = -MOVE_AMOUNT end
  if INVERT_WHEEL then move = -move end
  
  local ed = r.MIDIEditor_GetActive()
  if not ed then return end
  local take = r.MIDIEditor_GetTake(ed)
  if not take then return end
  
  r.Undo_BeginBlock()
  r.MIDI_DisableSort(take)
  
  local new_pitches = {}
  local _, note_count = r.MIDI_CountEvts(take)
  
  for i = 0, note_count - 1 do
    local _, sel, muted, startppq, endppq, chan, pitch, vel = r.MIDI_GetNote(take, i)
    if sel then
        local new_p = pitch + move
        if new_p < 0 then new_p = 0 end
        if new_p > 127 then new_p = 127 end
        
        if new_p ~= pitch then
            r.MIDI_SetNote(take, i, sel, muted, startppq, endppq, chan, new_p, vel, true)
            new_pitches[#new_pitches + 1] = new_p
        else
             new_pitches[#new_pitches + 1] = pitch
        end
    end
  end
  
  r.MIDI_Sort(take)
  r.Undo_EndBlock("Move Pitch ±" .. MOVE_AMOUNT, -1)
  
  if #new_pitches > 0 then
      r.gmem_write(1, #new_pitches)
      for i = 1, #new_pitches do
          r.gmem_write(1 + i, new_pitches[i])
      end
      r.gmem_write(0, r.time_precise())
  end
end

Main()
