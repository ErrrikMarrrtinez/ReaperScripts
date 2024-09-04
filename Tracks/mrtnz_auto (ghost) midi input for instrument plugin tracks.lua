-- @description Auto (ghost) midi input for instrument plugin tracks
-- @author mrtnz
-- @version 1.2
-- @about
--  ...



local _, _, section_id, command_id = reaper.get_action_context()

function ToolbarButton(enable)
  reaper.SetToggleCommandState(section_id, command_id, enable)
  reaper.RefreshToolbar2(section_id, command_id)
end


local renamedTracks = {}

function CheckInstrumentTracks()
  local c_tracks = reaper.CountTracks(0)
  if c_tracks ~= nil then
    for i = 1, c_tracks do
      local tr = reaper.GetTrack(0, i-1)
      if tr ~= nil then
        local id = reaper.TrackFX_GetInstrument(tr)
        if id ~= -1 then
          -- Set to all MIDI input channels
          local midi_input_value = 4096 + (63 << 5)
          reaper.SetMediaTrackInfo_Value(tr, 'I_RECINPUT', midi_input_value)

          if not renamedTracks[tr] then
            local _, fx_full_name = reaper.TrackFX_GetFXName(tr, id, "")
            local fx_name = fx_full_name:match(":%s*(.-)%s*%(") or fx_full_name
            
            reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", fx_name, true)

            renamedTracks[tr] = true
          end
        end
      end
    end
  end
  reaper.defer(CheckInstrumentTracks) 
end



function Exit()
  ToolbarButton(0)
end

if reaper.GetToggleCommandStateEx(section_id, command_id) == 0 then
  reaper.atexit(Exit)
  ToolbarButton(1)
  CheckInstrumentTracks()
else
  ToolbarButton(0)
end
