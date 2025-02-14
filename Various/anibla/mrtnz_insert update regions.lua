--@noindex
--NoIndex: true

dofile(debug.getinfo(1, "S").source:match [[^@?(.*[\/])[^\/]-$]]..'Reateam_RPP-Parser.lua')

function get_parrent_project()
  return reaper.GetSetProjectNotes(0, false, ""):match("main_project=([^\n]+)")
end

function RemoveAllMarkersAndRegions(proj)
  local num_markers, num_regions = reaper.CountProjectMarkers(proj)
  local total = num_markers + num_regions
  for i = total - 1, 0, -1 do
    local retval, isrgn, pos, rgnend, name, markrgnindexnumber = reaper.EnumProjectMarkers(proj, i)
    if retval then reaper.DeleteProjectMarker(proj, markrgnindexnumber, isrgn) end
  end
end

function ImportMarkersFromParent()
  local parent_proj_name = get_parrent_project()
  if not parent_proj_name then
    reaper.ShowMessageBox("Не найден родительский проект в NOTES!", "Ошибка", 0)
    return
  end
  local cur_proj, cur_proj_path = reaper.EnumProjects(-1, "")
  if not cur_proj_path or cur_proj_path == "" then
    reaper.ShowMessageBox("Сохраните проект перед запуском скрипта!", "Ошибка", 0)
    return
  end
  local cur_proj_dir = cur_proj_path:match("(.*)[/\\]") or ""
  local parent_path = cur_proj_dir .. "\\" .. parent_proj_name
  local parent_root = ReadRPP(parent_path)
  if not parent_root then
    reaper.ShowMessageBox("Ошибка парсинга родительского проекта:\n" .. parent_path, "Ошибка", 0)
    return
  end
  RemoveAllMarkersAndRegions(0)
  local custom_color = reaper.ColorToNative(255, 165, 0)
  local children = parent_root.children or {}
  local i = 1
  while i <= #children do
    local node = children[i]
    if node:getName() == "MARKER" or node:getName() == "REGION" then
      local tokens = node:getTokens()
      if #tokens >= 4 then
        local pos = tonumber(tokens[3]:getString()) or 0
        local name = tokens[4]:getString() or ""
        local marker_index = tonumber(tokens[2]:getString()) or -1
        if marker_index > 1000 then marker_index = -1 end
        if #tokens >= 8 and tokens[8]:getString() == "R" then
          local region_start = pos
          local region_end = nil
          if i < #children then
            local next_node = children[i+1]
            if next_node:getName() == "MARKER" then
              local next_tokens = next_node:getTokens()
              if next_tokens[2] and next_tokens[2]:getString() == tokens[2]:getString() then
                region_end = tonumber(next_tokens[3]:getString()) or 0
                i = i + 1
              end
            end
          end
          if region_end and region_end > region_start then
            reaper.AddProjectMarker2(0, true, region_start, region_end, name, custom_color, marker_index)
          else
            reaper.AddProjectMarker2(0, false, region_start, 0, name, custom_color, marker_index)
          end
        else
          reaper.AddProjectMarker2(0, false, pos, 0, name, custom_color, marker_index)
        end
      end
    end
    i = i + 1
  end
end

function ClearTrackAndItems(track)
  if not track then return end
  reaper.SetMediaTrackInfo_Value(track, "I_RECARM", 0)
  reaper.SetMediaTrackInfo_Value(track, "I_RECMON", 0)
  reaper.SetTrackSelected(track, false)
  local item_count = reaper.CountTrackMediaItems(track)
  for i = 0, item_count - 1 do
    local item = reaper.GetTrackMediaItem(track, i)
    reaper.SetMediaItemInfo_Value(item, "B_UISEL", 0)
  end
end

function ImportTrackChunkFromParent()
  local parent_proj_name = get_parrent_project()
  if not parent_proj_name then
    reaper.ShowMessageBox("Не найден родительский проект в NOTES!", "Ошибка", 0)
    return
  end
  local cur_proj, cur_proj_path = reaper.EnumProjects(-1, "")
  if not cur_proj_path or cur_proj_path == "" then
    reaper.ShowMessageBox("Сохраните проект перед запуском скрипта!", "Ошибка", 0)
    return
  end
  local cur_proj_dir = cur_proj_path:match("(.*)[/\\]") or ""
  local parent_path = cur_proj_dir .. "\\" .. parent_proj_name
  local parent_root = ReadRPP(parent_path)
  if not parent_root then
    reaper.ShowMessageBox("Ошибка парсинга родительского проекта:\n" .. parent_path, "Ошибка", 0)
    return
  end
  local current_proj_filename = reaper.GetProjectName(0, "")
  local current_proj_name = current_proj_filename:match("(.+)%.rpp$")
  if not current_proj_name then
    reaper.ShowMessageBox("Не удалось определить имя текущего проекта!", "Ошибка", 0)
    return
  end
  local target_track_name = current_proj_name .. " [subproject]"
  local parent_tracks = parent_root:findAllChunksByName("TRACK")
  local parent_track_chunk = nil
  for i, tr_chunk in ipairs(parent_tracks) do
    local name_node = tr_chunk:findFirstNodeByName("NAME")
    if name_node then
      local token = name_node:getTokens()[2]
      if token then
        local tr_name = token:getString():gsub('^"(.*)"$', "%1")
        if tr_name == target_track_name then
          parent_track_chunk = tr_chunk
          break
        end
      end
    end
  end
  if not parent_track_chunk then
    reaper.ShowMessageBox("Не найден трек в родительском проекте с именем:\n" .. target_track_name, "Информация", 0)
    return
  end
  local function FindTrackIndexByName(name)
    local cnt = reaper.CountTracks(0)
    for i = 0, cnt - 1 do
      local track = reaper.GetTrack(0, i)
      local _, cur_name = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
      if cur_name == name then return i end
    end
    return -1
  end
  local track_idx = FindTrackIndexByName(target_track_name)
  local current_track = nil
  if track_idx >= 0 then
    current_track = reaper.GetTrack(0, track_idx)
  else
    reaper.InsertTrackAtIndex(reaper.CountTracks(0), true)
    current_track = reaper.GetTrack(0, reaper.CountTracks(0) - 1)
    reaper.GetSetMediaTrackInfo_String(current_track, "P_NAME", target_track_name, true)
  end
  if parent_track_chunk.children then
    for i = #parent_track_chunk.children, 1, -1 do
      local child = parent_track_chunk.children[i]
      if child:getName() == "TRACK" then table.remove(parent_track_chunk.children, i) end
    end
  end
  local parent_track_chunk_str = StringifyRPPNode(parent_track_chunk)
  parent_track_chunk_str = parent_track_chunk_str:gsub("I_FOLDERDEPTH%s+%-?%d+", "I_FOLDERDEPTH 0")
  parent_track_chunk_str = parent_track_chunk_str:gsub("ISBUS%s+1%s+1", "ISBUS 0 0")
  reaper.SetTrackStateChunk(current_track, parent_track_chunk_str, false)
  ClearTrackAndItems(current_track)
  reaper.TrackList_AdjustWindows(false)
end

local function rgb2uint(r, g, b)
  r = math.floor(math.max(0, math.min(255, r)))
  g = math.floor(math.max(0, math.min(255, g)))
  b = math.floor(math.max(0, math.min(255, b)))
  return (r << 16) | (g << 8) | b
end

function color_regions()
  reaper.Undo_BeginBlock()
  local _, num_markers, num_regions = reaper.CountProjectMarkers(0)
  local default_color = rgb2uint(135, 206, 235)
  local i = 0
  while i < (num_markers + num_regions) do
    local _, isrgn, pos, rgnend, name, markrgnindexnumber = reaper.EnumProjectMarkers3(0, i)
    if isrgn then reaper.SetProjectMarker3(0, markrgnindexnumber, isrgn, pos, rgnend, name, default_color) end
    i = i + 1
  end
  reaper.Undo_EndBlock("Set all regions to default color", -1)
  reaper.UpdateArrange()
end

reaper.PreventUIRefresh(0)
reaper.Undo_BeginBlock()
ImportMarkersFromParent()
color_regions()
ImportTrackChunkFromParent()
reaper.Undo_EndBlock("Импорт маркеров/регионов из родительского проекта", -1)
reaper.UpdateArrange()
reaper.PreventUIRefresh(-1)
