-- @description Insert fx and show x parameter creating a pool by razor edit
-- @author mrtnz
-- @version 1.0
-- @about
--   insert fx and show x parameter creating a pool by razor edit

local FX = "kHs Tape Stop (Kilohearts)"
local TrackIdx = 0
local TrackCount = reaper.CountSelectedTracks(0)
local action_id = 42459

local function getRazorTracks()
    local tracks = {}
    for i = 0, reaper.CountTracks(0) - 1 do
        local track = reaper.GetTrack(0, i)
        local _, str = reaper.GetSetMediaTrackInfo_String(track, "P_RAZOREDITS", "", false)
        if str ~= "" then 
            table.insert(tracks, track) 
            reaper.Main_OnCommand(40297, 0)
            reaper.SetTrackSelected(track, true)  -- Select the track
        end
    end
    return tracks
end

local function processTrack(track)
    local fxIdx = reaper.TrackFX_GetByName(track, FX, 1)
    local isOpen = reaper.TrackFX_GetOpen(track, fxIdx)
    reaper.TrackFX_SetOpen(track, fxIdx, isOpen == 0 and 1 or 0)
    
    local paramIdx = 0
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

local function env_pool()
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
    end
    if removeRE == 1 then
      for track in pairs(tracks) do
        reaper.GetSetMediaTrackInfo_String(track, "P_RAZOREDITS", "", true)
      end
    end
end

local function toggleActionAndPool()
    local initial_state = reaper.GetToggleCommandState(action_id)
    if initial_state == 0 then
        reaper.Main_OnCommand(action_id, 0)
        env_pool()
        reaper.Main_OnCommand(action_id, 0)
        
    else
        env_pool()
    end
end
reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)

getRazorTracks()
for i = 0, TrackCount - 1 do
    local track = reaper.GetSelectedTrack(0, i)
    processTrack(track)
end
toggleActionAndPool()

reaper.TrackList_AdjustWindows(false)
reaper.PreventUIRefresh(-1)
reaper.Undo_EndBlock("s", 1)
reaper.UpdateArrange()

