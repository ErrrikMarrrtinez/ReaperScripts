-- @description Smart solo-playitem (under cursor or selected) while the key is held down 
-- @author mrtnz
-- @version 1.0
-- @about
--   solo play-item (under cursor or selected) while the key is held down (saving the time selection, mute and repeat)

local start_time = reaper.time_precise()
local key_state, KEY = reaper.JS_VKeys_GetState(start_time - 2), nil
local itemStates = {}
local timeSelection = {}
local repeatState = reaper.GetSetRepeat(-1) -- Get current repeat state

for i = 1, 255 do
    if key_state:byte(i) ~= 0 then KEY = i; reaper.JS_VKeys_Intercept(KEY, 1) end
end

if not KEY then return end

function Key_held()
    key_state = reaper.JS_VKeys_GetState(start_time - 2)
    return key_state:byte(KEY) == 1
end

function Release() 
    reaper.JS_VKeys_Intercept(KEY, -1)
    reaper.Main_OnCommand(40044, 0) -- Transport: Stop

    -- Restore item states
    for item, state in pairs(itemStates) do
        reaper.SetMediaItemInfo_Value(item, "B_MUTE", state.mute)
    end
    
    -- Restore time selection
    if timeSelection.start and timeSelection.endd then
        reaper.GetSet_LoopTimeRange(true, false, timeSelection.start, timeSelection.endd, false)
    else
        reaper.GetSet_LoopTimeRange(true, false, 0, 0, false)
    end
    
    -- Restore repeat state
    reaper.GetSetRepeat(repeatState)
end

function Main()
  if not Key_held() then return end
  if not main_executed then

     -- Check if items are selected or under cursor
     local item = reaper.GetSelectedMediaItem(0, 0)
     if not item then
        item = reaper.BR_ItemAtMouseCursor()
     end
     
     if not item then
        reaper.ShowMessageBox("Please select an item or hover over it.", "Error", 0)
        Release()
        return
     end
     
     -- Save and set time selection
     local start_time, end_time = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
     if start_time ~= end_time then
        timeSelection.start = start_time
        timeSelection.endd = end_time
     end
     
     local item_start = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
     local item_end = item_start + reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
     reaper.GetSet_LoopTimeRange(true, false, item_start, item_end, false)

     -- Mute all items except the one under cursor or selected
     for i = 0, reaper.CountMediaItems(0) - 1 do
        local current_item = reaper.GetMediaItem(0, i)
        local muteState = reaper.GetMediaItemInfo_Value(current_item, "B_MUTE")
        itemStates[current_item] = {mute = muteState}
        
        if current_item ~= item then
            reaper.SetMediaItemInfo_Value(current_item, "B_MUTE", 1)
        else
            reaper.SetMediaItemInfo_Value(current_item, "B_MUTE", 0)
        end
     end
    
    -- Enable repeat if it's not enabled already
    if repeatState == 0 then
        reaper.GetSetRepeat(1)
    end
    
    -- Play from the start of the time selection
    reaper.SetEditCurPos(item_start, true, true)
    reaper.Main_OnCommand(1007, 0) -- Transport: Play
    
    main_executed = true
end

reaper.defer(Main)
   
end

reaper.defer(Main)
reaper.atexit(Release)

