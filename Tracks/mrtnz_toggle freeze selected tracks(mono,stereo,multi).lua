-- @description Toggle freeze selected tracks(mono, stereo, multi)
-- @author mrtnz
-- @version 1.1

function toggle_freeze_track()
    local selected_track = reaper.GetSelectedTrack(0, 0)
    if selected_track then
        local _, chunk = reaper.GetTrackStateChunk(selected_track, "", false)
        if chunk:find("<FREEZE") then
            reaper.Main_OnCommand(41644, 0) -- Unfreeze
        else
            local menu = "Stereo|Mono|Multichannel"
            local choice = gfx.showmenu(menu)
            if choice == 1 then
                reaper.Main_OnCommand(41223, 0) -- Freeze to stereo
            elseif choice == 2 then
                reaper.Main_OnCommand(40901, 0) -- Freeze to mono
            elseif choice == 3 then
                reaper.Main_OnCommand(40877, 0) -- Freeze to multichannel
            end
        end
    else
        reaper.ShowMessageBox("Track not selected", "Error", 0)
    end
end

toggle_freeze_track()
