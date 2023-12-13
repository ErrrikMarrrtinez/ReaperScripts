-- @description Set track color red while ARM is enabled
-- @author mrtnz
-- @version 1.0
-- @about
--  ...



local red_color = 0x0000FF -- red color in BGR format
local is_running = false -- script running state
local original_colors = {} -- stores original track colors

-- updates track colors based on recording state
local function update_track_colors()
    if not is_running then return end
    for i = 0, reaper.CountTracks(0) - 1 do
        local track = reaper.GetTrack(0, i)
        local armed = reaper.GetMediaTrackInfo_Value(track, "I_RECARM") == 1
        if armed then
            if original_colors[track] == nil then
                original_colors[track] = reaper.GetTrackColor(track)
                reaper.SetTrackColor(track, red_color)
            end
        elseif original_colors[track] ~= nil then
            if original_colors[track] == 0 then
                reaper.SetMediaTrackInfo_Value(track, "I_CUSTOMCOLOR", 0)
            else
                reaper.SetTrackColor(track, original_colors[track])
            end
            original_colors[track] = nil
        end
    end
end

-- toggles script state
local function toggle_state()
    is_running = not is_running
    local state = is_running and 1 or 0
    local _, _, section_id, cmd_id = reaper.get_action_context()
    reaper.SetToggleCommandState(section_id, cmd_id, state)
    reaper.RefreshToolbar2(section_id, cmd_id)
end

-- cleans up on script exit
local function exit_script()
    toggle_state() -- set state to OFF on exit
    for track, color in pairs(original_colors) do
        if reaper.ValidatePtr(track, "MediaTrack*") then
            if color == 0 then
                reaper.SetMediaTrackInfo_Value(track, "I_CUSTOMCOLOR", 0)
            else
                reaper.SetTrackColor(track, color)
            end
        end
    end
end

-- main loop
local function main()
    update_track_colors()
    if is_running then reaper.defer(main) end
end

-- initialize and start script
toggle_state() -- initial toggle to ON
main()
reaper.atexit(exit_script)
