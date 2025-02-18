--@noindex
--NoIndex: true

-- Импорт RPP-парсера (файл Reateam_RPP-Parser.lua должен быть в той же папке)
dofile(debug.getinfo(1, "S").source:match([[^@?(.*[\/])[^\/]-$]]) .. 'Reateam_RPP-Parser.lua')

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
      main_project_in_notes = notes_str:match("|main_project=([%w%.%-_]+)")
      if main_project_in_notes then
        notes_found = true
        break
      end
    end
  end
  
  if not notes_found or main_project_in_notes ~= current_proj_filename then
    return
  end

  local parent_name = subproj_name .. " [subproject]"
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
      local new_tr = f.InsertTrackFromChunk(tr_chunk, insert_idx, 1)
      f.RemoveParams(new_tr)
      table.insert(inserted, new_tr)
      insert_idx = insert_idx + 1
    end
  end
  
  reaper.SetMediaTrackInfo_Value(parent_tr, "I_FOLDERDEPTH", 1)
  if #inserted > 0 then
    local last_tr = inserted[#inserted]
    local last_depth = reaper.GetMediaTrackInfo_Value(last_tr, "I_FOLDERDEPTH")
    reaper.SetMediaTrackInfo_Value(last_tr, "I_FOLDERDEPTH", last_depth - 1)
  else
    reaper.SetMediaTrackInfo_Value(parent_tr, "I_FOLDERDEPTH", 0)
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
  -- Проверка ReaPack
  if not reaper.ReaPack_BrowsePackages then
    local msg = "Для работы скрипта требуется ReaPack.\n" ..
                "Skript ishlashi uchun ReaPack kerak.\n\n" ..
                "Хотите перейти на страницу загрузки?\n" ..
                "Yuklab olish sahifasiga o'tishni xohlaysizmi?"
    
    local ret = reaper.ShowMessageBox(msg, "ReaPack не установлен / ReaPack o'rnatilmagan", 4)
    
    if ret == 6 then -- Yes
      reaper.CF_ShellExecute("https://reapack.com/upload/reascript")
    end
    return false
  end
  
  -- Проверка ReaImGui
  if not reaper.APIExists("ImGui_GetBuiltinPath") then
    local msg = "Для работы скрипта требуется ReaImGui.\n" ..
                "Skript ishlashi uchun ReaImGui kerak.\n\n" ..
                "Хотите установить его через ReaPack?\n" ..
                "Uni ReaPack orqali o'rnatishni xohlaysizmi?"
                
    local ret = reaper.ShowMessageBox(
      msg,
      "Требуется ReaImGui / ReaImGui kerak",
      4 -- Yes/No
    )
    
    if ret == 6 then 
      reaper.ReaPack_BrowsePackages("ReaImGui: ReaScript binding for Dear ImGui")
      return false
    else
      return false
    end
  end
  
  -- Проверка js_ReaScriptAPI
  if not reaper.APIExists("JS_Window_Find") then
    local msg = "Для работы скрипта требуется js_ReaScriptAPI.\n" ..
                "Skript ishlashi uchun js_ReaScriptAPI kerak.\n\n" ..
                "Хотите установить его через ReaPack?\n" ..
                "Uni ReaPack orqali o'rnatishni xohlaysizmi?"
                
    local ret = reaper.ShowMessageBox(
      msg,
      "Требуется js_ReaScriptAPI / js_ReaScriptAPI kerak",
      4 -- Yes/No
    )
    
    if ret == 6 then 
      reaper.ReaPack_BrowsePackages("js_ReaScriptAPI: API functions for ReaScripts")
      return false
    else
      return false
    end
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
  
return f
