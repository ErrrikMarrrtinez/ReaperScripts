--@noindex
--NoIndex: true

--dofile(reaper.GetResourcePath() .. "\\Scripts\\Reateam Scripts\\Development\\RPP-Parser\\Reateam_RPP-Parser.lua")
dofile(debug.getinfo(1, "S").source:match [[^@?(.*[\/])[^\/]-$]]..'Reateam_RPP-Parser.lua')

local function ShowWarningDialog()
  local message = "\n\nВы уверены, что хотите импортировать подпроекты?\n" ..
                  "Все изменения, внесённые в ранее вставленные подпроекты, будут удалены!\n\n" ..
                  "Siz kichik loyihalarni import qilishga ishonchingiz komilmi?\n" ..
                  "Avval joylashtirilgan kichik loyihalarda qilingan barcha o'zgarishlar o'chiriladi!\n\n"

  local retval = reaper.ShowMessageBox(message, "Предупреждение / Ogohlantirish", 4)
  return retval == 6 -- true, если пользователь нажал "ОК"
end

-- local confirmed = ShowWarningDialog()
--if not confirmed then
--  return -- Отменяем импорт
--end

----------------------------------------------------------------
-- ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ
----------------------------------------------------------------
function RemoveChildTracks(parentTrack)
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

local function MakeTrackStateChunk(rpp_chunk, depth_offset)
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

local function InsertTrackFromChunk(rpp_chunk, idx, depth_offset)
  reaper.InsertTrackAtIndex(idx, true)
  local tr = reaper.GetTrack(0, idx)
  local chunk = MakeTrackStateChunk(rpp_chunk, depth_offset or 0)
  reaper.SetTrackStateChunk(tr, chunk, true)
  return tr
end

local function FindTrackIndexByName(name)
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

----------------------------------------------------------------
-- ФУНКЦИИ СКАНИРОВАНИЯ ДИРЕКТОРИИ
----------------------------------------------------------------
local function GetCurrentProjectPath()
  local project_path = reaper.GetProjectPath("")
  if project_path == "" then return nil end
  
  local directory = project_path:match("(.*[/\\])")
  return directory
end

local function ScanForRPPFiles(directory)
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
    local subdir_files = ScanForRPPFiles(subdir_path)
    for _, file in ipairs(subdir_files) do
      table.insert(rpp_files, file)
    end
    
    subdir_idx = subdir_idx + 1
  end
  
  return rpp_files
end

local function RemoveParams(tr)
    reaper.SetMediaTrackInfo_Value(tr, "I_RECARM", 0)
    reaper.SetMediaTrackInfo_Value(tr, "I_RECMON", 0)
    reaper.SetTrackSelected(tr, false)
end

----------------------------------------------------------------
-- ФУНКЦИЯ ИМПОРТА ПОДПРОЕКТА
----------------------------------------------------------------
function ImportSubproject(subproj_path)
  local subproj_name = subproj_path:match("([^/\\]+)%.rpp$")
  if not subproj_name then return end
  
  local current_proj_filename = reaper.GetProjectName(0, "") -- с расширением, например "perdunslav.rpp"
  if not current_proj_filename or current_proj_filename == "" then return end
  
  local root = ReadRPP(subproj_path)
  if not root or type(root) ~= "table" then
    reaper.ShowMessageBox("Не удалось прочесть подпроект:\n" .. tostring(subproj_path),
                          "Ошибка", 0)
    return
  end
  
  -- Проверка NOTES на принадлежность к текущему проекту
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
    return  -- Пропускаем подпроект, если нет NOTES или он принадлежит другому проекту
  end

  local parent_name = subproj_name .. " [subproject]"
  local current_proj_track_name = current_proj_filename:match("(.+)%.rpp$") .. " [subproject]"
  if parent_name == current_proj_track_name then return end
  
  local parent_idx = FindTrackIndexByName(parent_name)
  if parent_idx < 0 then return end
  
  local parent_tr = reaper.GetTrack(0, parent_idx)
  RemoveChildTracks(parent_tr)
  
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
      skipNext = true  -- пропускаем сразу следующий трек после видео
    elseif first_line:find("%[subproject%]") then
      -- пропускаем трек с [subproject]
    else
      local new_tr = InsertTrackFromChunk(tr_chunk, insert_idx, 1)
      RemoveParams(new_tr)
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

----------------------------------------------------------------
-- ГЛАВНАЯ ФУНКЦИЯ: АВТОМАТИЧЕСКИЙ ИМПОРТ ВСЕХ ПОДПРОЕКТОВ
----------------------------------------------------------------
function AutoImportAllSubprojects()
  reaper.PreventUIRefresh(1)
  reaper.Undo_BeginBlock()
  
  local proj_dir = GetCurrentProjectPath()
  if not proj_dir then
    reaper.ShowMessageBox("Не удалось получить путь текущего проекта!", "Ошибка", 0)
    return
  end
  
  local rpp_files = ScanForRPPFiles(proj_dir)
  if #rpp_files == 0 then
    reaper.ShowMessageBox("Подпроекты (.rpp) не найдены!", "Информация", 0)
    return
  end

  for _, file in ipairs(rpp_files) do
    ImportSubproject(file.path)
  end
  
  reaper.Undo_EndBlock("Auto-import all subprojects", -1)
  reaper.PreventUIRefresh(-1)
  reaper.UpdateArrange()
end

AutoImportAllSubprojects()
