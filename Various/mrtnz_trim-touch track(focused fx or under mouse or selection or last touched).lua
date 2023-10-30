-- @description Script: Trim-touch track(focused fx or under mouse or selection or last touched)
-- @author mrtnz
-- @version 1.0
-- @about
--    trim-touch track focused fx or under mouse or selection or last touched



local start_time = reaper.time_precise()
local key_state, KEY = reaper.JS_VKeys_GetState(start_time - 2), nil

reaper.BR_GetMouseCursorContext()

local retval, tracknumber, itemnumber, fxnumber = reaper.GetFocusedFX()

if retval ~= 0 then

  tr = reaper.CSurf_TrackFromID(tracknumber, false)
else

  tr = reaper.BR_GetMouseCursorContext_Track()

  if tr == nil then
    local selected_track_count = reaper.CountSelectedTracks(0)
    if selected_track_count > 0 then
      tr = reaper.GetSelectedTrack(0, 0)
    else
      tr = reaper.GetLastTouchedTrack()
    end
  end
end

for i = 1, 255 do
    if key_state:byte(i) ~= 0 then KEY = i; reaper.JS_VKeys_Intercept(KEY, 1) end
end

if not KEY then return end
function Key_held()
    --local hwnd = reaper.JS_Window_GetFocus()
    key_state = reaper.JS_VKeys_GetState(start_time - 2)
    return key_state:byte(KEY) == 1
end

function Release() 
    reaper.JS_VKeys_Intercept(KEY, -1)
    if tr then
        reaper.SetMediaTrackInfo_Value(tr, "I_AUTOMODE", 0) -- Set back to trim/read mode
    end
end

function Main()
    if not Key_held() then return end
    if not main_executed then

        if tr then
            reaper.SetMediaTrackInfo_Value(tr, "I_AUTOMODE", 2) 
        end
        main_executed = true
    end
    reaper.defer(Main)
end

reaper.defer(Main)
reaper.atexit(Release)
