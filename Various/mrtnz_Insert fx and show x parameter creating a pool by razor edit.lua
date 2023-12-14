-- @description Insert fx and show x parameter creating a pool by razor edit
-- @author mrtnz
-- @version 1.04
-- @about
--   I've long needed a quick way to create a tape slowdown, tape stop, tape stop effect.
--   I usually use a free plugin for this - [b][url=https://kilohearts.com/products/tape_stop]kHs Tape Stop[/url][/b],
--   and for a faster speed I wrote a simple script that does the following just for this fx:
--   Along the length of the razor edit creates an envelope item,
--   and in that area sets the stop parameter to "on" mode to activate it in the desired range.
--   And also sets the stop time relative to the length of the razor-edit.
--   You can disable the automatic length setting by clearing the flag in the editor here to false:
--   local razorLength = true --this flag 
--   To quickly create the desired slowdown effects without auto-setting.
--   Also, the exact same script will be attached to this script soon,
--   but it will be placed inside an athame and set the envelope points.
--   Demo link - https://imgur.com/ZdGodGG
-- @changelog
--    *Added flag to change the parameter, 
--    *default is true



local FX = "kHs Tape Stop (Kilohearts)"
local razorLength = true



local TrackIdx = 0
local TrackCount = reaper.CountSelectedTracks(0)
local action_id = 42459

function getCommandState(commandId)
  local _, _, sectionId = reaper.get_action_context()
  return reaper.GetToggleCommandStateEx(sectionId, commandId)
end

function ensureCommandState(commandId, activateIfOff)
  local currentState = getCommandState(commandId)
  if (currentState == 0 and activateIfOff) or (currentState == 1 and not activateIfOff) then
    reaper.Main_OnCommand(commandId, 0)
  end
  return tostring(activateIfOff)
end

local check_actions = ensureCommandState(42459, false)

function getRazorTracks()
    local tracks = {}
    for i = 0, reaper.CountTracks(0) - 1 do
        local track = reaper.GetTrack(0, i)
        local _, str = reaper.GetSetMediaTrackInfo_String(track, "P_RAZOREDITS", "", false)
        if str ~= "" then 
            table.insert(tracks, track) 
            reaper.Main_OnCommand(40297, 0)
            reaper.SetTrackSelected(track, true)
        end
    end
    return tracks
end

function getRazorEditLengthInMilliseconds(track)
    local _, razorEdit = reaper.GetSetMediaTrackInfo_String(track, "P_RAZOREDITS", "", false)
    if razorEdit ~= "" then
        local start_time, end_time = razorEdit:match("(%S+)%s+(%S+)")
        return (start_time and end_time) and (end_time - start_time) * 1000 or nil
    end
    return nil
end

function processTrack(track)
    local fxIdx = reaper.TrackFX_GetByName(track, FX, 1)
    local isOpen = reaper.TrackFX_GetOpen(track, fxIdx)
    reaper.TrackFX_SetOpen(track, fxIdx, isOpen == 0 and 1 or 0)
    
    if razorLength then
        local length = getRazorEditLengthInMilliseconds(track)
        if length then
            local fx_value
            if length <= 1000 then
                local def =  0.45
                if length > 500 then def = 0.42 end
                if length > 600 then def = 0.41 end
                if length > 700 then def = 0.35 end
                if length > 800 then def = 0.39 end
                if length < 200 then def = 0.49 end
                
                fx_value = (length / 1000) ^ def * 0.78760969638824
            else
                local normalized_length = (length - 1000) / 1000
                fx_value = 0.78760969638824 + normalized_length * (1.0 - 0.78760969638824)
            end
            reaper.TrackFX_SetParam(track, fxIdx, 2, fx_value)
        end
    end
    
    local paramIdx = TrackIdx
    local envelope = reaper.GetFXEnvelope(track, fxIdx, paramIdx, true)
    if envelope then
        reaper.SetCursorContext(2, envelope)
        local startTime, endTime = reaper.GetSet_LoopTimeRange(0, 0, 0, 0, 0)
        if startTime ~= endTime then
            local retval, value, _, _, _ = reaper.Envelope_Evaluate(envelope, startTime, 0, 0)
            reaper.DeleteEnvelopePointRange(envelope, startTime-0.01, startTime+0.01)
            reaper.InsertEnvelopePoint(envelope, startTime, value, 0, 0, 1, true)
            reaper.Envelope_SortPoints(envelope)
        end
    end
end

reaper.PreventUIRefresh(1)
reaper.Undo_BeginBlock()

function env_pool()
    if reaper.CountTracks(0) == 0 then return reaper.defer(function() end) end
    local removeRE = 1
    local envs = {}
    local tracks = {}
    
    for tr = 0, reaper.CountTracks(0) - 1 do
        local track = reaper.GetTrack(0, tr)
        local _, area = reaper.GetSetMediaTrackInfo_String(track, "P_RAZOREDITS", "", false)
        if area ~= "" then
            local arSt, arEn
            tracks[track] = true
            for str in area:gmatch("(%S+)") do
                if not arSt then arSt = str
                elseif not arEn then arEn = str
                else
                    if str ~= '""' then
                        table.insert(envs, { reaper.GetTrackEnvelopeByChunkName(track, str:sub(2, -1)), tonumber(arSt), tonumber(arEn) })
                    end
                    arSt, arEn = nil, nil
                end
            end
        end
    end
    if #envs == 0 then return reaper.defer(function() end) end
    
    local pool_id
    for e = 1, #envs do
        local id = reaper.InsertAutomationItem(envs[e][1], pool_id or -1, envs[e][2], envs[e][3] - envs[e][2])
        if not pool_id then
            pool_id = reaper.GetSetAutomationItemInfo(envs[e][1], id, "D_POOL_ID", 0, false)
        end
        
        local env = envs[e][1]
        reaper.GetSetAutomationItemInfo(env, id, "D_BASELINE", 0, true)  
        reaper.GetSetAutomationItemInfo(env, id, "D_AMPLITUDE", -1, true)  
    end
    if removeRE == 1 then
      for track in pairs(tracks) do
        reaper.GetSetMediaTrackInfo_String(track, "P_RAZOREDITS", "", true)
      end
    end
    reaper.UpdateArrange()
end

function toggleActionAndPool()
    local initial_state = reaper.GetToggleCommandState(action_id)
    if initial_state == 0 then
        reaper.Main_OnCommand(action_id, 0)
        env_pool()
        reaper.Main_OnCommand(action_id, 0)
        
    else
        env_pool()
    end
end

getRazorTracks()

for i = 0, TrackCount - 1 do
    local track = reaper.GetSelectedTrack(0, i)
    processTrack(track)
end

toggleActionAndPool()

if check_actions == "false" then reaper.Main_OnCommand(42459, 0) end

reaper.TrackList_AdjustWindows(false)

reaper.PreventUIRefresh(-1)
reaper.Undo_EndBlock("s", 1)
reaper.UpdateArrange()