--@noindex
--NoIndex: true

-- Импорт RPP-парсера (файл Reateam_RPP-Parser.lua должен быть в той же папке)
dofile(debug.getinfo(1, "S").source:match([[^@?(.*[\/])[^\/]-$]]) .. 'Reateam_RPP-Parser.lua')
local r = reaper
local f = {}

-------------------------------------------------------
-- Общие утилиты
-------------------------------------------------------
function f.TrimEdges(str)
  return (str or ""):match("^%s*(.-)%s*$")
end

function f.GetTrackChunk(track)
  if not track then return nil end
  local _, chunk = reaper.GetTrackStateChunk(track, "", false)
  return chunk
end

-------------------------------------------------------
-- Работа с треками и их чанками
-------------------------------------------------------
function f.RemoveChildTracks(parentTrack)
  if not parentTrack then return false end
  local depth = reaper.GetTrackDepth(parentTrack)
  local parentIndex = reaper.GetMediaTrackInfo_Value(parentTrack, "IP_TRACKNUMBER") - 1
  local childrenToDelete = {}
  local lastChildIndex = parentIndex

  local i = parentIndex + 1
  while true do
    local track = reaper.GetTrack(0, i)
    if not track then break end
    local currentDepth = reaper.GetTrackDepth(track)
    if currentDepth <= depth then break end
    table.insert(childrenToDelete, track)
    lastChildIndex = i
    i = i + 1
  end

  local nextTrack = reaper.GetTrack(0, lastChildIndex + 1)
  local nextTrackDepth = nextTrack and reaper.GetTrackDepth(nextTrack) or -1

  for i = #childrenToDelete, 1, -1 do
    reaper.DeleteTrack(childrenToDelete[i])
  end

  if nextTrack then
    if nextTrackDepth <= depth then
      reaper.SetMediaTrackInfo_Value(parentTrack, "I_FOLDERDEPTH", 0)
    else
      local depthDiff = nextTrackDepth - depth
      reaper.SetMediaTrackInfo_Value(parentTrack, "I_FOLDERDEPTH", depthDiff)
    end
  else
    reaper.SetMediaTrackInfo_Value(parentTrack, "I_FOLDERDEPTH", 0)
  end

  return true
end

function f.MakeTrackStateChunk(rpp_chunk, depth_offset)
  local full = StringifyRPPNode(rpp_chunk)
  local lines = {}
  for line in full:gmatch("[^\r\n]+") do
    table.insert(lines, line)
  end
  if #lines >= 2 then
    table.remove(lines)
    lines[1] = lines[1]:gsub("^<TRACK", "TRACK")
  end
  if depth_offset and depth_offset ~= 0 then
    for i, line in ipairs(lines) do
      local before, val = line:match("^(I_FOLDERDEPTH)%s+([%-]?%d+)")
      if before and val then
        lines[i] = string.format("%s %d", before, tonumber(val) + depth_offset)
      end
    end
  end
  return table.concat(lines, "\n")
end

function f.InsertTrackFromChunk(rpp_chunk, idx, depth_offset)
  reaper.InsertTrackAtIndex(idx, true)
  local tr = reaper.GetTrack(0, idx)
  local chunk = f.MakeTrackStateChunk(rpp_chunk, depth_offset or 0)
  reaper.SetTrackStateChunk(tr, chunk, true)
  return tr
end

function f.FindTrackIndexByName(name)
  local cnt = reaper.CountTracks(0)
  for i = 0, cnt - 1 do
    local track = reaper.GetTrack(0, i)
    local _, cur_name = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
    if cur_name == name then
      return i
    end
  end
  return -1
end

-------------------------------------------------------
-- Работа с проектами и файлами
-------------------------------------------------------
function f.GetCurrentProjectPath()
  local project_path = reaper.GetProjectPath("")
  if project_path == "" then return nil end
  local directory = project_path:match("(.*[/\\])")
  return directory
end

function f.ScanForRPPFiles(directory)
  local rpp_files = {}
  local _, current_proj_name = reaper.GetProjectName(0, "")
  if current_proj_name then
    current_proj_name = current_proj_name:match("(.+)%.rpp$")
  end
  
  local idx = 0
  while true do
    local file = reaper.EnumerateFiles(directory, idx)
    if not file then break end
    if file:match("%.rpp$") or file:match("%.RPP$") then
      local name_without_ext = file:match("(.+)%.rpp$") or file:match("(.+)%.RPP$")
      if name_without_ext ~= current_proj_name then
        table.insert(rpp_files, {
          name = name_without_ext,
          path = directory .. file
        })
      end
    end
    idx = idx + 1
  end
  
  local subdir_idx = 0
  while true do
    local subdir = reaper.EnumerateSubdirectories(directory, subdir_idx)
    if not subdir then break end
    local subdir_path = directory .. subdir .. "\\"
    local subdir_files = f.ScanForRPPFiles(subdir_path)
    for _, file in ipairs(subdir_files) do
      table.insert(rpp_files, file)
    end
    subdir_idx = subdir_idx + 1
  end
  
  return rpp_files
end

function f.RemoveParams(tr)
  reaper.SetMediaTrackInfo_Value(tr, "I_RECARM", 0)
  reaper.SetMediaTrackInfo_Value(tr, "I_RECMON", 0)
  reaper.SetTrackSelected(tr, false)
end

-------------------------------------------------------
-- Импорт подпроекта (из существующего .rpp)
-------------------------------------------------------
function f.ImportSubproject(subproj_path)
  local subproj_name = subproj_path:match("([^/\\]+)%.rpp$")
  if not subproj_name then return end
  
  local current_proj_filename = reaper.GetProjectName(0, "")
  if not current_proj_filename or current_proj_filename == "" then return end
  
  local root = ReadRPP(subproj_path)
  if not root or type(root) ~= "table" then
    reaper.ShowMessageBox("Не удалось прочесть подпроект:\n" .. tostring(subproj_path), "Ошибка", 0)
    return
  end
  
  local notes_found = false
  local main_project_in_notes = nil
  for i, node in ipairs(root.children or {}) do
    if node:getName() == "NOTES" then
      local notes_str = StringifyRPPNode(node)
      main_project_in_notes = notes_str:match("|main[_]?project=([^\n]+)")
      if main_project_in_notes then
        main_project_in_notes = main_project_in_notes:match("^%s*(.-)%s*$")
        notes_found = true
        break
      end
    end
  end
  
  if not notes_found or main_project_in_notes ~= current_proj_filename then
    return
  end
  
  local parent_name = subproj_name .. " [subproject]"
  
  local r = reaper
  local track_exists = false
  local track_count = r.CountTracks(0)
  for i = 0, track_count - 1 do
      local track = r.GetTrack(0, i)
      local retval, track_name = r.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
      if track_name == parent_name then
          track_exists = true
          break
      end
  end
  
  if not track_exists then
      r.InsertTrackAtIndex(-1, false)
      local track = r.GetTrack(0, r.CountTracks(0)-1)
      r.GetSetMediaTrackInfo_String(track, "P_NAME", parent_name, true)
  end

  local current_proj_track_name = current_proj_filename:match("(.+)%.rpp$") .. " [subproject]"
  if parent_name == current_proj_track_name then return end

  local parent_idx = f.FindTrackIndexByName(parent_name)
  if parent_idx < 0 then return end

  local parent_tr = reaper.GetTrack(0, parent_idx)
  f.RemoveChildTracks(parent_tr)

  local tracks = root:findAllChunksByName("TRACK")
  if not tracks or #tracks == 0 then
    reaper.ShowMessageBox("В подпроекте нет треков!", "Внимание", 0)
    return
  end

  local inserted = {}
  local insert_idx = parent_idx + 1
  local skipNext = false
  for i, tr_chunk in ipairs(tracks) do
    local first_line = tr_chunk.children[1] and tr_chunk.children[1].line or ""
    if skipNext then
      skipNext = false
    elseif first_line:find("%[video%]") then
      skipNext = true
    elseif first_line:find("%[subproject%]") then
      -- пропускаем трек с [subproject]
    else
      -- Вставляем трек без смещения глубины
      local new_tr = f.InsertTrackFromChunk(tr_chunk, insert_idx, 0)
      f.RemoveParams(new_tr)
      table.insert(inserted, new_tr)
      insert_idx = insert_idx + 1
    end
  end
  
  -- Устанавливаем родительскому треку I_FOLDERDEPTH = 1
  reaper.SetMediaTrackInfo_Value(parent_tr, "I_FOLDERDEPTH", 1)
  
  -- Явно переопределяем I_FOLDERDEPTH для вставленных треков:
  for i, tr in ipairs(inserted) do
    if i == #inserted then
      reaper.SetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH", -1)  -- последний трек закрывает папку
    else
      reaper.SetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH", 0)
    end
  end
end


function f.AutoImportAllSubprojects()
  reaper.PreventUIRefresh(1)
  reaper.Undo_BeginBlock()
  
  local proj_dir = f.GetCurrentProjectPath()
  if not proj_dir then
    reaper.ShowMessageBox("Не удалось получить путь текущего проекта!", "Ошибка", 0)
    return
  end
  
  local rpp_files = f.ScanForRPPFiles(proj_dir)
  if #rpp_files == 0 then
    reaper.ShowMessageBox("Подпроекты (.rpp) не найдены!", "Информация", 0)
    return
  end

  for _, file in ipairs(rpp_files) do
    f.ImportSubproject(file.path)
  end
  
                                                        for i = 1, reaper.CountTracks() do
                                                        tr = reaper.GetTrack(0, i-1)
                                                        depth = reaper.GetTrackDepth(tr)
                                                        if depth == 0 then 
                                                        col = reaper.GetTrackColor( tr )
                                                                    else
                                                        reaper.SetMediaTrackInfo_Value( tr, 'I_CUSTOMCOLOR', col )
                                                        end
                                                        end

  reaper.Undo_EndBlock("Auto-import all subprojects", -1)
  reaper.PreventUIRefresh(-1)
  reaper.UpdateArrange()
end

-------------------------------------------------------
-- Создание подпроекта для выделенного трека
-------------------------------------------------------

function f.MarkAsParentProject(subproject_name)
  local current_notes = reaper.GetSetProjectNotes(0, false, "")
  if not current_notes:find("subprojects=") then
      -- If no subprojects section exists, create it
      if current_notes ~= "" and not current_notes:match("\n$") then
          current_notes = current_notes .. "\n"
      end
      current_notes = current_notes .. "subprojects=" .. subproject_name
  else
      -- If subprojects section exists, append to it
      local existing_subprojects = current_notes:match("subprojects=([^\n]*)")
      if not existing_subprojects:find(subproject_name) then
          current_notes = current_notes:gsub("subprojects=([^\n]*)", "subprojects=%1;" .. subproject_name)
      end
  end
  reaper.GetSetProjectNotes(0, true, current_notes)
end

function f.CreateSubprojectForTrack(sel_track, current_rpp, parent_dir)
  local _, orig_name = reaper.GetSetMediaTrackInfo_String(sel_track, "P_NAME", "", false)
  local trimmed_name = f.TrimEdges(orig_name)
  if trimmed_name == "" then
    reaper.ShowMessageBox("\n\nУ выбранного трека пустое имя!\n\n", "Ошибка", 0)
    return false
  end

  local name_no_sub = trimmed_name:gsub("%[subproject%]", "")
  name_no_sub = f.TrimEdges(name_no_sub)
  local new_project_path = parent_dir .. "\\" .. name_no_sub .. ".rpp"

  local root = ReadRPP(current_rpp)
  if not root or type(root) ~= "table" then
    reaper.ShowMessageBox("\n\nНе удалось распарсить проект!\n\n", "Ошибка", 0)
    return false
  end

  if not trimmed_name:lower():find("%[subproject%]") then
    reaper.GetSetMediaTrackInfo_String(sel_track, "P_NAME", trimmed_name .. " [subproject]", true)
  end

  local newproj = CreateRPP()

  for i, node in ipairs(root.children or {}) do
    local nm = node:getName()
    if nm == "MARKER" or nm == "REGION" then
      local copy_node = RNode:new({ line = node.line })
      newproj:addNode(copy_node)
    end
  end
  
  local main_proj_filename = current_rpp:match("([^/\\]+%.rpp)$") or "unknown.rpp"
  local notes_str = string.format("<NOTES 0 0\n  |main_project=%s\n>", main_proj_filename)
  local notes_node = RNode:new({ line = notes_str })
  newproj:addNode(notes_node)
  


  for i = 0, reaper.CountTracks(0) - 1 do
    local track = reaper.GetTrack(0, i)
    local _, track_name = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
    if track_name:lower():find("%[video%]") then
      local track_chunk = f.GetTrackChunk(track)
      if track_chunk then
        local new_track = ReadRPPChunk(track_chunk)
        if new_track then
          new_track:StripGUID()
          newproj:addNode(new_track)
        end
      end
      break
    end
  end

  local selected_track_chunk = f.GetTrackChunk(sel_track)
  if selected_track_chunk then
    local selected_new_track = ReadRPPChunk(selected_track_chunk)
    if selected_new_track then
      selected_new_track:StripGUID()
      newproj:addNode(selected_new_track)
    end
  end

  local EMPTY_TRACK_CHUNK = [[<TRACK
NAME ""
PEAKCOL 16576
BEAT -1
AUTOMODE 0
PANLAWFLAGS 3
VOLPAN 1 0 -1 -1 1
MUTESOLO 0 0 0
IPHASE 0
PLAYOFFS 0 1
ISBUS 0 0
BUSCOMP 0 0 0 0 0
SHOWINMIX 1 0.6667 0.5 1 0.5 0 0 0
FIXEDLANES 9 0 0 0 0
REC 1 0 0 0 0 0 0 0
VU 2
TRACKHEIGHT 0 0 0 0 0 0 0 0
INQ 0 0 0 0.5 100 0 0 100
NCHAN 2
FX 1
TRACKID {4D70B74F-BC1F-4748-B517-526849967BA4}
PERF 0
MIDIOUT -1
MAINSEND 1 0
>]]
  local new_track_name = name_no_sub .. " " .. string.format("%04d", math.random(1000, 9999))
  local modified_empty_chunk = EMPTY_TRACK_CHUNK:gsub('NAME ""', 'NAME "' .. new_track_name .. '"')
  local empty_track = ReadRPPChunk(modified_empty_chunk)
  if empty_track then
    empty_track:StripGUID()
    newproj:addNode(empty_track)
  end



  local ok, err = WriteRPP(new_project_path, newproj)
  if not ok then
    reaper.ShowMessageBox("\n\nОшибка записи проекта:\n" .. tostring(err) .. "\n\n", "Ошибка", 0)
    return false
  end

  local new_project_name = name_no_sub .. ".rpp"
  
  f.MarkAsParentProject(new_project_name)
  

  return true
end

-------------------------------------------------------
-- Работа с маркерами, регионами и импортом трека
-------------------------------------------------------
function f.get_parent_project()
  return reaper.GetSetProjectNotes(0, false, ""):match("main_project=([^\n]+)")
end

function f.RemoveAllMarkersAndRegions(proj)
  local num_markers, num_regions = reaper.CountProjectMarkers(proj)
  local total = num_markers + num_regions
  for i = total - 1, 0, -1 do
    local retval, isrgn, pos, rgnend, name, markrgnindexnumber = reaper.EnumProjectMarkers(proj, i)
    if retval then reaper.DeleteProjectMarker(proj, markrgnindexnumber, isrgn) end
  end
end

function f.ImportMarkersFromParent()
  local parent_proj_name = f.get_parent_project()
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
  f.RemoveAllMarkersAndRegions(0)
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

function f.ClearTrackAndItems(track)
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

function f.ImportTrackChunkFromParent()
  local parent_proj_name = f.get_parent_project()
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
  local track_idx = f.FindTrackIndexByName(target_track_name)
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
  f.ClearTrackAndItems(current_track)
  reaper.TrackList_AdjustWindows(false)
end

-------------------------------------------------------
-- Цвета и мелкие утилиты
-------------------------------------------------------
function f.rgb2uint(r, g, b)
  r = math.floor(math.max(0, math.min(255, r)))
  g = math.floor(math.max(0, math.min(255, g)))
  b = math.floor(math.max(0, math.min(255, b)))
  return (r << 16) | (g << 8) | b
end

function f.color_regions()
  reaper.Undo_BeginBlock()
  local _, num_markers, num_regions = reaper.CountProjectMarkers(0)
  local default_color = f.rgb2uint(135, 206, 235)
  local i = 0
  while i < (num_markers + num_regions) do
    local _, isrgn, pos, rgnend, name, markrgnindexnumber = reaper.EnumProjectMarkers3(0, i)
    if isrgn then reaper.SetProjectMarker3(0, markrgnindexnumber, isrgn, pos, rgnend, name, default_color) end
    i = i + 1
  end
  reaper.Undo_EndBlock("Set all regions to default color", -1)
  reaper.UpdateArrange()
end

-------------------------------------------------------
-- Дополнительные функции (если понадобятся)
-------------------------------------------------------
function f.ShowWarningDialog()
  local message = "\n\nВы уверены, что хотите импортировать подпроекты?\n" ..
                  "Все изменения, внесённые в ранее вставленные подпроекты, будут удалены!\n\n" ..
                  "Siz kichik loyihalarni import qilishga ishonchingiz komilmi?\n" ..
                  "Avval joylashtirilgan kichik loyihalarda qilingan barcha o'zgarishlar o'chiriladi!\n\n"
  local retval = reaper.ShowMessageBox(message, "Предупреждение / Ogohlantirish", 4)
  return retval == 6
end


function f.AddScriptStartup()
    local ac = {reaper.get_action_context()}
    local scriptPath = ac[2]
    if not scriptPath or scriptPath == "" then return end
  
    local cmdID = reaper.NamedCommandLookup(scriptPath)
    if cmdID == 0 then
      cmdID = reaper.AddRemoveReaScript(true, 0, scriptPath, true)
      if cmdID == 0 then return end
    end
  
    local scriptID = reaper.ReverseNamedCommandLookup(cmdID)
    if not scriptID or scriptID == "" then return end
  
    if scriptID:sub(1,1) ~= "_" then
      scriptID = "_" .. scriptID
    end
  
    local startupFile = reaper.GetResourcePath() .. '/Scripts/__startup.lua'
    local exists = false
    local f, err = io.open(startupFile, "r")
    if f then
      for line in f:lines() do
        if line:find('reaper%.NamedCommandLookup%("%s*' .. scriptID .. '%s*"%)') then
          exists = true
          break
        end
      end
      f:close()
    end
  
    if exists then return end
  
    local newCmd = string.format('reaper.Main_OnCommand(reaper.NamedCommandLookup("%s"), 0) -- %s erik', scriptID, scriptID)
    f, err = io.open(startupFile, "a")
    if f then
      f:write("\n" .. newCmd .. "\n")
      f:close()
      --reaper.ShowConsoleMsg("Command appended successfully\n")
    end
end
  

function f.checkDependencies()
  local missing = {}
  if not reaper.APIExists("JS_Window_Find") then
    table.insert(missing, "js_ReaScriptAPI: API functions for ReaScripts")
  end
  if not reaper.APIExists("ImGui_GetBuiltinPath") then
    table.insert(missing, "ReaImGui: ReaScript binding for Dear ImGui")
  end
  
  if #missing > 0 then
    local missing_str = table.concat(missing, "\n  - ")
    reaper.ReaPack_BrowsePackages("reascript api for :")
    local msg_ru = "Для работы скрипта требуется установить следующие расширения через ReaPack:\n" ..
                   "  - " .. missing_str .. "\n\n" ..
                   "Выдели их вместе, нажми правой кнопкой мыши -> Install, затем OK и перезагрузи Reaper."
    local msg_uz = "Skriptning to'g'ri ishlashi uchun quyidagi kengaytmalarni ReaPack orqali o'rnatishingiz kerak:\n" ..
                   "  - " .. missing_str .. "\n\n" ..
                   "Ularni birgalikda tanlang, o'ng tugmani bosib 'Install' ni tanlang, so'ng OK ni bosing va Reaper-ni qayta ishga tushiring."
    local msg = msg_ru .. "\n\n" .. msg_uz
    reaper.ShowMessageBox(msg, "Отсутствуют зависимости / Kamomillar yo'q", 0)
    
    return false
  end
  
  return true
end

function f.get_regions()
  local regions = {}
  local count = reaper.CountProjectMarkers(0)
  for i = 0, count - 1 do
    local retval, isrgn, pos, rgnend, name = reaper.EnumProjectMarkers3(0, i)
    if isrgn then 
      regions[#regions+1] = {start = pos, endPos = rgnend, name = name} 
    end
  end
  return regions
end


local function lerp(a, b, t) 
  return a + (b - a) * t 
end

function f.getColorComponents(color)
  local a = math.floor(color / 0x1000000) % 256
  local b = math.floor(color / 0x10000) % 256
  local g = math.floor(color / 0x100) % 256
  local r = color % 256
  return a, b, g, r
end

local function combineColor(a, b, g, r)
  return ((a * 0x1000000) + (b * 0x10000) + (g * 0x100) + r)
end

function f.lerpColor(c1, c2, t)
  local a1, b1, g1, r1 = f.getColorComponents(c1)
  local a2, b2, g2, r2 = f.getColorComponents(c2)
  local a = math.floor(lerp(a1, a2, t) + 0.5)
  local b = math.floor(lerp(b1, b2, t) + 0.5)
  local g = math.floor(lerp(g1, g2, t) + 0.5)
  local r = math.floor(lerp(r1, r2, t) + 0.5)
  return combineColor(a, b, g, r)
end

function f.getBrightness(color)
  local a, b, g, r = f.getColorComponents(color)
  return (r + g + b) / 3
end

local function delete_marker_track()
    local num_tracks = r.CountTracks(0)
    for i = 0, num_tracks - 1 do
        local track = r.GetTrack(0, i)
        local retval, track_name = r.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
        if track_name == "### VIDEO MARKERS ###" then
            r.DeleteTrack(track)
            break
        end
    end
end

local function create_track()
    delete_marker_track()
    local new_track_index = r.CountTracks(0)
    r.InsertTrackAtIndex(new_track_index, false)
    local new_track = r.GetTrack(0, new_track_index)
    r.GetSetMediaTrackInfo_String(new_track, "P_NAME", "### VIDEO MARKERS ###", true)
    return new_track
end

function f.CreateVideoItemsInRegions()
    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)
    local marker_track = create_track()
    r.SetMediaTrackInfo_Value(marker_track, "D_PLAYOFFTIME", 0.030)
    local num_markers, num_regions = r.CountProjectMarkers(0)
    local total_regions = num_markers + num_regions

    for index = 0, total_regions - 1 do
        local retval, isRegion, pos, rgnend, name = r.EnumProjectMarkers3(0, index)
        if isRegion then            
            local item = r.AddMediaItemToTrack(marker_track)
            r.SetMediaItemInfo_Value(item, "D_POSITION", pos)
            r.SetMediaItemInfo_Value(item, "D_LENGTH", rgnend - pos + 0.05)
            local take = r.AddTakeToMediaItem(item)
            r.GetSetMediaItemTakeInfo_String(take, "P_NAME", name, true)
            r.ULT_SetMediaItemNote(item, name)
            local retval, chunk = r.GetItemStateChunk(item, "", false)
            chunk = chunk:gsub("<SOURCE EMPTY", [[<SOURCE VIDEOEFFECT
<CODE
|// Text/timecode overlay
|#text=""; font="Arial";
|//@param1:size 'text height' 0.06 0.01 0.2 0.1 0.001
|//@param2:ypos 'y position' 0.93 0 1 0.5 0.01
|//@param3:xpos 'x position' 0.5 0 1 0.5 0.01
|//@param4:border 'bg pad' 0.1 0 1 0.5 0.01
|//@param5:fgc 'text bright' 1.0 0 1 0.5 0.01
|//@param6:fga 'text alpha' 1.0 0 1 0.5 0.01
|//@param7:bgc 'bg bright' 0.35 0 1 0.5 0.01
|//@param8:bga 'bg alpha' 0.99 0 1 0.5 0.01
|//@param9:bgfit 'fit bg to text' 0 0 1 0.5 1
|//@param10:ignoreinput 'ignore input' 0 0 1 0.5 1
|//@param12:tc 'show timecode' 0 0 1 0.5 1
|//@param13:tcdf 'dropframe timecode' 0 0 1 0.5 1
|input = ignoreinput ? -2:0;
|project_wh_valid===0 ? input_info(input,project_w,project_h);
|gfx_a2=0;
|gfx_blit(input,1);
|gfx_setfont(size*project_h,font);
|tc>0.5 ? (
|  t = floor((project_time + project_timeoffs) * framerate + 0.0000001);
|  f = ceil(framerate);
|  tcdf > 0.5 && f != framerate ? (
|    period = floor(framerate * 600);
|    ds = floor(framerate * 60);
|    ds > 0 ? t += 18 * ((t / period)|0) + ((((t%%period)-2)/ds)|0)*2;
|  );
|  sprintf(#text,"%%02d:%%02d:%%02d:%%02d",(t/(f*3600))|0,(t/(f*60))%%60,(t/f)%%60,t%%f);
|) : strcmp(#text,"")==0 ? input_get_name(-1,#text);
|gfx_str_measure(#text,txtw,txth);
|b = (border*txth)|0;
|yt = ((project_h - txth - b*2)*ypos)|0;
|xp = (xpos * (project_w-txtw))|0;
|gfx_set(bgc,bgc,bgc,bga);
|bga>0?gfx_fillrect(bgfit?xp-b:0, yt, bgfit?txtw+b*2:project_w, txth+b*2);
|gfx_set(fgc,fgc,fgc,fga);
|gfx_str_draw(#text,xp,yt+b);
>
CODEPARM 0.06 0.93 0.5 0.1 1 1 0.35 0.99 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0]])
            r.SetItemStateChunk(item, chunk, false)
        end
    end
    r.PreventUIRefresh(-1)
    r.Undo_EndBlock("Create Video Markers Track", -1)
    r.UpdateArrange()
end

function f.GetSubprojectTracks()
  local notes = reaper.GetSetProjectNotes(0, false, "")
  local subprojects_str = notes:match("subprojects=(.+)")
  if not subprojects_str then return {} end

  local subproj_files = {}
  for file in subprojects_str:gmatch("([^;]+)") do
    subproj_files[#subproj_files+1] = file
  end

  local subproj_names = {}
  for _, fname in ipairs(subproj_files) do
    local base = fname:gsub("%.rpp$", "")
    subproj_names[base] = base .. " [subproject]"
  end

  local proj, projfn = reaper.EnumProjects(-1, "")
  if not projfn then return {} end
  local proj_dir = projfn:match("^(.*[\\/])")
  if not proj_dir then return {} end

  local found_bases = {}
  local i = 0
  while true do
    local file = reaper.EnumerateFiles(proj_dir, i)
    if not file then break end
    for base, _ in pairs(subproj_names) do
      if file:find(base) then
        found_bases[base] = true
      end
    end
    i = i + 1
  end

  local final_lookup = {}
  for base, _ in pairs(found_bases) do
    final_lookup[subproj_names[base]] = true
  end

  local matched_tracks = {}
  local track_count = reaper.CountTracks(0)
  for i = 0, track_count - 1 do
    local track = reaper.GetTrack(0, i)
    local retval, track_name = reaper.GetTrackName(track, "")
    if final_lookup[track_name] then
      table.insert(matched_tracks, track)
    end
  end
  return matched_tracks
end

function f.selectChildTracks(parentTrack)
  if not parentTrack then return {} end
  local isFolder = reaper.GetMediaTrackInfo_Value(parentTrack, "I_FOLDERDEPTH") == 1
  if not isFolder then return {} end
  local parentDepth = reaper.GetTrackDepth(parentTrack)
  local parentNumber = reaper.CSurf_TrackToID(parentTrack, false)
  local childTracks = {}
  for i = parentNumber, reaper.CountTracks(0) - 1 do
    local track = reaper.GetTrack(0, i)
    if track then
      local currentDepth = reaper.GetTrackDepth(track)
      if currentDepth > parentDepth then
        table.insert(childTracks, track)
      else
        if i > parentNumber then break end
      end
    end
  end
  return childTracks
end

function f.getAndRenameTrackItems(track)
  if not track then return {} end
  local items = {}
  local itemCount = reaper.GetTrackNumMediaItems(track)
  for i = 0, itemCount - 1 do
    local item = reaper.GetTrackMediaItem(track, i)
    if item then
      table.insert(items, item)
    end
  end
  return items
end

function f.CalculateUsefulSeconds(items, params)
  params = params or {}
  local coarse_dt        = params.coarse_dt       or 0.01
  local fine_dt          = params.fine_dt         or 0.001
  local silenceThreshDB  = params.silenceThreshDB or -50
  local silenceThreshAmp = params.silenceThreshAmp or 10^(silenceThreshDB/20)
  local silenceMinDur    = params.silenceMinDur   or 0.41

  local function getState(accessor, sr, nCh, t, sampleDur)
    sampleDur = sampleDur or fine_dt
    local numSamples = math.floor(sampleDur * sr)
    local buf = reaper.new_array(numSamples * nCh)
    local samplesRead = reaper.GetAudioAccessorSamples(accessor, sr, nCh, t, numSamples, buf)
    local maxAmp = 0
    for j = 1, samplesRead * nCh do
      local amp = math.abs(buf[j])
      if amp > maxAmp then maxAmp = amp end
    end
    return maxAmp < silenceThreshAmp
  end

  local function refineTransition(accessor, sr, nCh, tLow, tHigh)
    for i = 1, 10 do
      local mid = (tLow + tHigh) / 2
      if getState(accessor, sr, nCh, mid, fine_dt) then
        tLow = mid
      else
        tHigh = mid
      end
    end
    return (tLow + tHigh) / 2
  end

  local totalUseful = 0

  for _, item in ipairs(items) do
    local itemLen = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
    local take = reaper.GetActiveTake(item)
    if take and not reaper.TakeIsMIDI(take) then
      local source = reaper.GetMediaItemTake_Source(take)
      local sr = reaper.GetMediaSourceSampleRate(source)
      local nCh = reaper.GetMediaSourceNumChannels(source)
      local accessor = reaper.CreateTakeAudioAccessor(take)
      local silenceTotal = 0
      local t = 0
      local lastState = getState(accessor, sr, nCh, 0)
      local silenceStart = lastState and 0 or nil

      while t < itemLen do
        local currentState = getState(accessor, sr, nCh, t)
        if currentState ~= lastState then
          local boundary = refineTransition(accessor, sr, nCh, t - coarse_dt, t)
          if currentState then
            silenceStart = boundary
          else
            if silenceStart then
              local segDur = boundary - silenceStart
              if segDur >= silenceMinDur then silenceTotal = silenceTotal + segDur end
              silenceStart = nil
            end
          end
          lastState = currentState
        end
        t = t + coarse_dt
      end

      if lastState and silenceStart then
        local segDur = itemLen - silenceStart
        if segDur >= silenceMinDur then silenceTotal = silenceTotal + segDur end
      end

      reaper.DestroyAudioAccessor(accessor)
      local useful = itemLen - silenceTotal
      totalUseful = totalUseful + useful
    end
  end

  return math.floor(totalUseful + 0.5)
end

function f.GetSubprojectItems()
  local subprojectTracks = f.GetSubprojectTracks()
  local subprojectItems = {}
  for i, subProjTrack in ipairs(subprojectTracks) do
    local retval, trackName = reaper.GetTrackName(subProjTrack, "")
    local childTracks = f.selectChildTracks(subProjTrack)
    local items = {}
    for j, childTrack in ipairs(childTracks) do
      local trackItems = f.getAndRenameTrackItems(childTrack)
      for k, item in ipairs(trackItems) do
        table.insert(items, item)
      end
    end
    subprojectItems[trackName] = items
  end
  return subprojectItems
end

function f.ShowSubprojectUsefulSeconds()
  local subprojectItems = f.GetSubprojectItems()
  local results = {}
  for subProjName, items in pairs(subprojectItems) do
    local usefulSeconds = f.CalculateUsefulSeconds(items)
    table.insert(results, {
      name = subProjName,
      usefulSeconds = usefulSeconds
    })
  end
  return results
end


return f
