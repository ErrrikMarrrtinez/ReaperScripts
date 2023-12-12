-- @description Pre-reverb, reverse reverb for item(time selection) 
-- @author mrtnz
-- @version 1.2
-- @about
--  ...



local presetName = 'preverb'



local vintage = "ValhallaVintageVerb"
local plate = "ValhallaPlate"
local room = "ValhallaRoom"


reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)

local last_fx_name = reaper.GetExtState("LastFXName", "FXName")
if last_fx_name == "" then last_fx_name = "FX name" end

function VF_BFpluginparam_GetFormattedParamInternal(tr, fx, param, val)
    local param_n
    if val then reaper.TakeFX_SetParamNormalized(tr, fx, param, val) end
    local _, buf = reaper.TakeFX_GetFormattedParamValue(tr, fx, param, '')
    local param_str = buf:match('[%d%a%-%.]+')
    if param_str then param_n = tonumber(param_str) end
    if not param_n and param_str:lower():match('%-inf') then param_n = -math.huge
    elseif not param_n and param_str:lower():match('inf') then param_n = math.huge end
    return param_n
end
function VF_BFpluginparam_PreciseCheck(tr, fx, param, find_val, min, max, precision)
    for value_precise = min, max, precision do
        local param_form = VF_BFpluginparam_GetFormattedParamInternal(tr, fx, param, value_precise)
        if find_val == param_form then return value_precise end
    end
    return min + (max - min) / 2
end
function VF_BFpluginparam(find_Str, tr, fx, param)
    if not find_Str then return end
    local find_Str_val = find_Str:match('[%d%-%.]+')
    if not (find_Str_val and tonumber(find_Str_val)) then return end
    local find_val = tonumber(find_Str_val)

    local iterations = 300
    local mindiff = 10^-14
    local precision = 10^-7
    local min, max = 0, 1
    for i = 1, iterations do
        local param_low = VF_BFpluginparam_GetFormattedParamInternal(tr, fx, param, min)
        local param_mid = VF_BFpluginparam_GetFormattedParamInternal(tr, fx, param, min + (max - min) / 2)
        local param_high = VF_BFpluginparam_GetFormattedParamInternal(tr, fx, param, max)
        if find_val <= param_low then return min end
        if find_val == param_mid and math.abs(min - max) < mindiff then
            return VF_BFpluginparam_PreciseCheck(tr, fx, param, find_val, min, max, precision)
        end
        if find_val >= param_high then return max end
        if find_val > param_low and find_val < param_mid then
            min = min
            max = min + (max - min) / 2
            if math.abs(min - max) < mindiff then
                return VF_BFpluginparam_PreciseCheck(tr, fx, param, find_val, min, max, precision)
            end
        else
            min = min + (max - min) / 2
            max = max
            if math.abs(min - max) < mindiff then
                return VF_BFpluginparam_PreciseCheck(tr, fx, param, find_val, min, max, precision)
            end
        end
    end
end
function main()
    local start_time, end_time = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
    if start_time == end_time then
      reaper.ShowMessageBox("No time selection", "Error", 0)
      reaper.Undo_EndBlock("No time selection", -1)
      reaper.PreventUIRefresh(-1)
      return
    end
    
    local item = reaper.GetSelectedMediaItem(0, 0)
    if not item then 
      reaper.Undo_EndBlock("No item selected", -1)
      reaper.PreventUIRefresh(-1)
      return 
    end
    
    local retval, fx = reaper.GetUserInputs("Enter FX Name", 1, "FX Name:,extrawidth=100", last_fx_name)
    if not retval or fx == "" then
      reaper.Undo_EndBlock("Operation Cancelled", -1)
      reaper.PreventUIRefresh(-1)
      return
    end
    
    reaper.SetExtState("LastFXName", "FXName", fx, true)
    
    local track = reaper.GetMediaItem_Track(item)
    local track_idx = reaper.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER") - 1
    local mode = reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH") < 1 and 1 or 2
    local newTrack
    
    if mode == 1 then
      reaper.InsertTrackAtIndex(track_idx, false)
      newTrack = reaper.GetTrack(0, track_idx)
    elseif mode == 2 then
      while reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH") < 1 and track_idx > 0 do
        track_idx = track_idx - 1
        track = reaper.GetTrack(0, track_idx)
      end
      reaper.InsertTrackAtIndex(track_idx, false)
      newTrack = reaper.GetTrack(0, track_idx)
    end
    
    local item_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    local _, item_chunk = reaper.GetItemStateChunk(item, '')
    local new_item = reaper.AddMediaItemToTrack(newTrack)
    reaper.SetMediaItemInfo_Value(new_item, "D_POSITION", item_pos)
    reaper.SetItemStateChunk(new_item, item_chunk)
    
    reaper.SetMediaItemSelected(item, false)
    reaper.SetMediaItemSelected(new_item, true)
    reaper.TrackList_AdjustWindows(false)
    reaper.UpdateArrange()
    
    reaper.Main_OnCommand(40297, 0)  -- Unselect all tracks
    reaper.SetMediaTrackInfo_Value(newTrack, "I_SELECTED", 1)  -- Select the new track only
    reaper.Main_OnCommand(41051, 0)
    
    local start_time, end_time = reaper.GetSet_LoopTimeRange2(0, false, false, 0, 0, false)
    reaper.SetMediaItemPosition(new_item, start_time, false)
    local take = reaper.GetActiveTake(new_item)
    local length = end_time - start_time
    
    
    if not reaper.TakeFX_AddByName(take, fx, 1) then
      reaper.Undo_EndBlock("FX not found", -1)
      reaper.PreventUIRefresh(-1)
      return
    end
    
    function main2()
        local roundedLength = length 
        local ReaperVal
        reaper.ShowConsoleMsg(length)
        local startTime, endTime = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
        local length = endTime - startTime
        if fx ~= vintage and fx ~= plate and fx ~= room then return end
        
        local numFX = reaper.TakeFX_GetCount(take)
        if numFX == 0 then return end
        
        local fx = 0
        local param = 2
        reaper.TakeFX_SetPreset(take, fx, presetName)
        local find = tostring(roundedLength) 
       
        ReaperVal = VF_BFpluginparam(find, take, fx, param)
        if ReaperVal then reaper.TakeFX_SetParamNormalized(take, fx, param, ReaperVal) end
        
        
    end
    local tail_length_ms = 20000 
    reaper.SNM_SetIntConfigVar("deffadelen", tail_length_ms)
    
    
    main2()
    
    
    reaper.Main_OnCommand(42009, 0) 
    reaper.Main_OnCommand(41051, 0) 
    local new_item = reaper.GetSelectedMediaItem(0, 0) 
    
    if new_item then
      local take = reaper.GetActiveTake(new_item)
      if take then
        local name = ""
        retval, name = reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)
        local new_name = string.gsub(name, "-glued.*", "[reversed]")
        reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", new_name, true)
      end
    end
    reaper.Main_OnCommand(40635, 0) 
    reaper.Undo_EndBlock("Pre-verb item", -1)
    reaper.PreventUIRefresh(-1)
    
    
end




main()

