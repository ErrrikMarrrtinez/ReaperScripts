-- @description Create VCA link for selected tracks after freeze
-- @author mrtnz
-- @version 1.00
-- @about
--   test

local r = reaper
local _VERSION = 0.5

local VCA_FLAGS = {
  "VOLUME_MASTER", "VOLUME_SLAVE", "VOLUME_VCA_MASTER", "VOLUME_VCA_SLAVE",
  "PAN_MASTER", "PAN_SLAVE", "WIDTH_MASTER", "WIDTH_SLAVE",
  "MUTE_MASTER", "MUTE_SLAVE", "SOLO_MASTER", "SOLO_SLAVE",
  "RECARM_MASTER", "RECARM_SLAVE", "POLARITY_MASTER", "POLARITY_SLAVE",
  "AUTOMODE_MASTER", "AUTOMODE_SLAVE"
}

local FLAGS = {"VOLUME_VCA", "VOLUME", "PAN", "MUTE", "SOLO"}

local action_id = 41223 -- freeze to stereo

local function is_tracks()
    local num_selected = r.CountSelectedTracks(0)
    if num_selected < 2 then
      r.ShowMessageBox("Пожалуйста, выберите как минимум два трека.", "Ошибка", 0)
      return false
    end
    return true
end

local function is_send_track(send_track, receive_track)
  local num_sends = r.GetTrackNumSends(send_track, 0)
  for i = 0, num_sends - 1 do
    local dest_track = r.GetTrackSendInfo_Value(send_track, 0, i, "P_DESTTRACK")
    if dest_track == receive_track then
      return true
    end
  end
  return false
end

local function find_free_vca_group()
  local vca_group = {}
  for i = 1, 64 do vca_group[i] = 0 end
  local track_count = r.CountTracks(0)
  for i = 0, track_count - 1 do
    local tr = r.GetTrack(0, i)
    for k = 1, #vca_group do
      for j = 1, #VCA_FLAGS do
        if r.GetSetTrackGroupMembership(tr, VCA_FLAGS[j], 0, 0) == 2 ^ (k - 1) or
           r.GetSetTrackGroupMembershipHigh(tr, VCA_FLAGS[j], 0, 0) == 2 ^ ((k - 32) - 1) then
          vca_group[k] = nil
        end
      end
    end
  end
  for k, v in pairs(vca_group) do
    if v == 0 then
      return k <= 32 and 2 ^ (k - 1) or 2 ^ ((k - 32) - 1), k
    end
  end
  return nil
end

local function get_track_vca_group(track)
  for k = 1, 64 do
    local group = k <= 32 and 2 ^ (k - 1) or 2 ^ ((k - 32) - 1)
    for _, flag in ipairs(VCA_FLAGS) do
      if k <= 32 then
        if r.GetSetTrackGroupMembership(track, flag, 0, 0) == group then
          return group, k
        end
      else
        if r.GetSetTrackGroupMembershipHigh(track, flag, 0, 0) == group then
          return group, k
        end
      end
    end
  end
  return nil
end

local function is_vca_master(track, group, group_index)
  for _, flag in ipairs(FLAGS) do
    local full_flag = flag .. "_MASTER"
    if group_index <= 32 then
      if r.GetSetTrackGroupMembership(track, full_flag, 0, 0) == group then
        return true
      end
    else
      if r.GetSetTrackGroupMembershipHigh(track, full_flag, 0, 0) == group then
        return true
      end
    end
  end
  return false
end

local function set_vca_flags(track, is_lead, free_group, group_index)
  local flag_suffix = is_lead and "MASTER" or "SLAVE"
  for _, flag in ipairs(FLAGS) do
    local full_flag = flag .. "_" .. flag_suffix
    if group_index <= 32 then
      r.GetSetTrackGroupMembership(track, full_flag, free_group, free_group)
    else
      r.GetSetTrackGroupMembershipHigh(track, full_flag, free_group, free_group)
    end
  end
end

local function remove_freeze_from_item_names(track)
  local item_count = r.GetTrackNumMediaItems(track)
  for i = 0, item_count - 1 do
    local item = r.GetTrackMediaItem(track, i)
    local take = r.GetActiveTake(item)
    if take then
      local current_name = r.GetTakeName(take)
      local new_name = current_name:gsub("%s*%-%s*freeze", "")
      r.GetSetMediaItemTakeInfo_String(take, "P_NAME", new_name, true)
    end
  end
end

local function get_send_and_receive_tracks()
  local num_selected = r.CountSelectedTracks(0)
  local send_track = nil
  local receive_tracks = {}
  
  for i = 0, num_selected - 1 do
    local track = r.GetSelectedTrack(0, i)
    local is_send = false
    
    for j = 0, num_selected - 1 do
      if i ~= j then
        local other_track = r.GetSelectedTrack(0, j)
        if is_send_track(track, other_track) then
          is_send = true
          table.insert(receive_tracks, other_track)
        end
      end
    end
    
    if is_send and not send_track then
      send_track = track
    end
  end
  
  return send_track, receive_tracks
end

local function main()
    if not is_tracks() then return end
    
    local original_value = r.SNM_GetIntConfigVar("workrender", -1)
    local was_originally_checked = original_value & 64 == 0
    
    if not was_originally_checked then
      r.SNM_SetIntConfigVar("workrender", original_value & ~64)
    end
    
    local send_track, receive_tracks = get_send_and_receive_tracks()
    
    if not send_track or #receive_tracks == 0 then
      r.ShowMessageBox("Не удалось найти посыл.", "Ошибка", 0)
      return
    end
    
    local existing_group, existing_group_index = get_track_vca_group(send_track)
    local group, group_index
    
    if existing_group and is_vca_master(send_track, existing_group, existing_group_index) then
      group, group_index = existing_group, existing_group_index
    else
      group, group_index = find_free_vca_group()
      if not group then
        r.ShowMessageBox("Нет свободных vca", "Ошибка", 0)
        return
      end
      set_vca_flags(send_track, true, group, group_index)
    end
    
    for _, receive_track in ipairs(receive_tracks) do
      local receive_guid = r.GetTrackGUID(receive_track)
      r.SetOnlyTrackSelected(receive_track)
      r.Main_OnCommand(action_id, 0)
      
      local rendered_track = r.GetSelectedTrack(0, 0)
      remove_freeze_from_item_names(rendered_track)
      set_vca_flags(rendered_track, false, group, group_index)
    end
    
    if not was_originally_checked then
      r.SNM_SetIntConfigVar("workrender", original_value)
    end
end

r.PreventUIRefresh(1)
r.Undo_BeginBlock()
main()
r.Undo_EndBlock("VCA Group and Render Multiple Tracks", -1)
r.PreventUIRefresh(-1)
r.UpdateArrange()
