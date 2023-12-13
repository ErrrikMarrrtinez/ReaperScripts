-- @description Move velocity note up or down (mousewheel ctx)
-- @author mrtnz
-- @version 1.0
-- @about
--  ...

local r = reaper

function adjustVelocity(take, val)
    local _, notes = r.MIDI_CountEvts(take)
    local adjustValue = val > 0 and 10 or -10
    local newVel
    local hasSelectedNotes = false
    local noteUnderCursorIndex = nil
    for i = 0, notes - 1 do
        local _, selected = r.MIDI_GetNote(take, i)
        if selected then
            hasSelectedNotes = true
            break
        end
    end
    
    local window, segment, details = r.BR_GetMouseCursorContext();
    if window == "midi_editor" and segment == "notes" then
        local noteRow = ({r.BR_GetMouseCursorContext_MIDI()})[3];
        if noteRow >= 0 then
            local mouseTime = r.BR_GetMouseCursorContext_Position();
            local ppqPosition = r.MIDI_GetPPQPosFromProjTime(take, mouseTime);
            for i = 0, notes - 1 do
                local _, _, _, startNote, endNote, _, pitch, _ = r.MIDI_GetNote(take, i);
                if startNote < ppqPosition and endNote > ppqPosition and noteRow == pitch then
                    noteUnderCursorIndex = i
                    break
                end
            end
        end
    end
    
    r.PreventUIRefresh(1)
    for i = 0, notes - 1 do
        local _, selected, _, _, _, _, _, vel = r.MIDI_GetNote(take, i)
        
        if selected or (not hasSelectedNotes and (i == noteUnderCursorIndex or noteUnderCursorIndex == nil)) then
            newVel = math.min(127, math.max(1, vel + adjustValue))
            r.MIDI_SetNote(take, i, nil, nil, nil, nil, nil, nil, newVel, false)
        end
    end
    r.PreventUIRefresh(-1)
end

local take = r.MIDIEditor_GetTake(r.MIDIEditor_GetActive())
if not take then return end

local _, _, _, _, _, _, val = r.get_action_context()

r.Undo_BeginBlock()
adjustVelocity(take, val)
r.Undo_EndBlock("Adjust note velocities", -1)
