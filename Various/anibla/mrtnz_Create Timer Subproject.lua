--@noindex
--NoIndex: true

local l = {}
function l.da()
    local r = reaper
    local f = dofile(debug.getinfo(1, "S").source:match([[^@?(.*[\/])[^\/]-$]]) .. 'mrtnz_utils.lua')
    math.randomseed(os.time())
    
    -- Получаем путь и имя текущего проекта
    local _, current_rpp = r.EnumProjects(-1, "")
    if not current_rpp or current_rpp == "" then
      r.ShowMessageBox("\n\nСохрани проект перед запуском скрипта!\n\n", "Ошибка", 0)
      return
    end
    local parent_dir = current_rpp:match("(.*)[/\\].-$") or ""
    local current_proj_name = current_rpp:match("([^/\\]+)%.rpp$")
    if not current_proj_name then
      r.ShowMessageBox("\n\nНе удалось определить имя проекта!\n\n", "Ошибка", 0)
      return
    end
    
    -- Собираем треки: первый трек и все дочерние треки подпроектов (по NOTES)
    local tracks_to_move = {}
    --local first_track = r.GetTrack(0, 0)
    --if first_track then table.insert(tracks_to_move, first_track) end
    
    local subproj_tracks = f.FindSubprojectTracksByNotes()
    for _, track in ipairs(subproj_tracks) do
      local childs = f.selectChildTracks(track)
      for _, child in ipairs(childs) do
        table.insert(tracks_to_move, child)
      end
    end
    
    -- Создаём новый подпроект с именем "current_proj_name TIMER"
    local new_subproj_name = current_proj_name .. " [TIMER]"
    
    local new_proj_dir = parent_dir .. "\\" .. new_subproj_name
    
    reaper.RecursiveCreateDirectory(new_proj_dir, 0)
    
    local new_project_path = new_proj_dir .. "\\" .. new_subproj_name .. ".rpp"
    
    local newproj = CreateRPP()
    
    -- Копируем MARKER и REGION из текущего проекта
    local current_root = ReadRPP(current_rpp)
    if current_root then
      for _, node in ipairs(current_root.children or {}) do
        local nm = node:getName()
        if nm == "MARKER" or nm == "REGION" then
          newproj:addNode(RNode:new({ line = node.line }))
        end
      end
    end
    
    -- Добавляем NOTES с информацией о главном проекте
    local notes_str = string.format("<NOTES 0 0\n  |main_project=%s\n>", current_rpp:match("([^/\\]+%.rpp)$") or "unknown.rpp")
    newproj:addNode(RNode:new({ line = notes_str }))
    
    -- Добавляем пустой трек в конец
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
    REC 0 0 0 0 0 0 0 0
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
    local new_track_name = 'video'
    local modified_empty_chunk = EMPTY_TRACK_CHUNK:gsub('NAME ""', 'NAME "' .. new_track_name .. '"')
    local empty_track = ReadRPPChunk(modified_empty_chunk)
    if empty_track then
      empty_track:StripGUID()
      newproj:addNode(empty_track)
    end
    
    for _, tr in ipairs(tracks_to_move) do
      local chunk = f.GetTrackChunk(tr)
      if chunk then
        local new_tr = ReadRPPChunk(chunk)
        if new_tr then
          new_tr:StripGUID()
          newproj:addNode(new_tr)
        end
      end
    end
    
    
    
    -- Записываем новый подпроект и отмечаем его в NOTES главного проекта
    local ok, err = WriteRPP(new_project_path, newproj)
    if not ok then
      r.ShowMessageBox("\n\nОшибка записи подпроекта:\n" .. tostring(err) .. "\n\n", "Ошибка", 0)
    else
      f.MarkAsParentProject(new_subproj_name .. ".rpp")
      r.ShowMessageBox("\n\nПодпроект '" .. new_subproj_name .. "' успешно создан.\n\n", "Успех", 0)
    end
    
    r.UpdateArrange()
end

function l.net()
reaper.ShowConsoleMsg = print
local FileCopier = {}
FileCopier.__index = FileCopier

function FileCopier:new(copy_buffer_size)
  local self = setmetatable({}, FileCopier)
  self.copy_queue = {}
  self.copy_buffer_size = copy_buffer_size or (1024 * 1024) -- 1 МБ буфер
  return self
end

-- Проверка существования папки
function FileCopier:folder_exists(path)
  local sep = package.config:sub(1,1)
  if path:sub(-1) ~= sep then path = path .. sep end
  return os.rename(path, path) and true or false
end

-- Получить размер файла
function FileCopier:get_file_size(filepath)
  local f = io.open(filepath, "rb")
  if not f then return 0 end
  local size = f:seek("end")
  f:close()
  return size
end

-- Добавление одного файла в очередь
function FileCopier:add_file(src, dst, overwrite)
  overwrite = overwrite or false
  local total = self:get_file_size(src)
  table.insert(self.copy_queue, {src = src, dst = dst, overwrite = overwrite, offset = 0, total = total})
end

-- Добавление файлов из массива в очередь (target_folder – папка назначения)
function FileCopier:add_files(file_array, target_folder, overwrite)
  for i, src in ipairs(file_array) do
    local filename = src:match("([^/\\]+)$")
    local dst = target_folder .. "/" .. filename
    self:add_file(src, dst, overwrite)
  end
end

-- Фоновая обработка очереди копирования с reaper.defer
function FileCopier:process_queue()
  if #self.copy_queue == 0 then 
    reaper.ShowConsoleMsg("Копирование завершено.\n")
    return 
  end

  local item = self.copy_queue[1]
  if item.offset == 0 and not item.overwrite and reaper.file_exists(item.dst) then
    reaper.ShowConsoleMsg("Файл уже существует: " .. item.dst .. "\n")
    table.remove(self.copy_queue, 1)
    reaper.defer(function() self:process_queue() end)
    return
  end

  local src_file = io.open(item.src, "rb")
  if not src_file then
    reaper.ShowConsoleMsg("Не удалось открыть исходный файл: " .. item.src .. "\n")
    table.remove(self.copy_queue, 1)
    reaper.defer(function() self:process_queue() end)
    return
  end

  local mode = (item.offset == 0) and "wb" or "ab"
  local dst_file = io.open(item.dst, mode)
  if not dst_file then
    reaper.ShowConsoleMsg("Не удалось открыть целевой файл: " .. item.dst .. "\n")
    src_file:close()
    table.remove(self.copy_queue, 1)
    reaper.defer(function() self:process_queue() end)
    return
  end

  src_file:seek("set", item.offset)
  local data = src_file:read(self.copy_buffer_size)
  if data then
    dst_file:write(data)
    item.offset = item.offset + #data
    reaper.ShowConsoleMsg("Копирование " .. item.src .. ": " .. math.floor(100 * item.offset / item.total) .. "%\n")
  end

  src_file:close()
  dst_file:close()

  if item.offset >= item.total then
    reaper.ShowConsoleMsg("Файл скопирован: " .. item.src .. "\n")
    table.remove(self.copy_queue, 1)
  end

  reaper.defer(function() self:process_queue() end)
end

dofile(debug.getinfo(1, "S").source:match([[^@?(.*[\/])[^\/]-$]]) .. 'Reateam_RPP-Parser.lua')

if not RChunk then return end

local sep = package.config:sub(1,1)

-- Получить путь проекта и его директорию
local current_project = reaper.GetProjectPath()
local project_folder = current_project:match("(.*" .. sep .. ")")
if not project_folder or project_folder == "" then
  reaper.ShowConsoleMsg("Не удалось определить директорию проекта.\n")
  return reaper.defer(function() end)
end

-- Функция для перечисления .rpp файлов (без .rpp-bak)
local function GetProjectFiles(dir)
  local files = {}
  local i = 0
  repeat
    local file = reaper.EnumerateFiles(dir, i)
    if file then
      i = i + 1
      local lower = file:lower()
      if lower:match("%.rpp$") and not lower:match("%.rpp%-bak$") then
        files[#files+1] = dir .. sep .. file
      end
    end
  until not file
  return files
end

local projects = GetProjectFiles(project_folder)
if #projects == 0 then
  reaper.ShowConsoleMsg("Нет файлов .rpp в директории: " .. project_folder .. "\n")
  return reaper.defer(function() end)
end

-- Поддерживаемые расширения медиафайлов
local media_extensions = {".wav", ".mp3", ".ogg", ".flac", ".aiff", ".m4a", ".mp4", ".mov", ".avi", ".mkv"}
local function table_contains(tbl, element)
  for _, v in ipairs(tbl) do
    if v == element then return true end
  end
  return false
end

-- Собираем используемые медиафайлы и определяем медиа-папки
local used_media_set = {}
local media_dirs_set = {}

for i, proj in ipairs(projects) do
  local root = ReadRPP(proj)
  if root then
    reaper.ShowConsoleMsg("Анализ проекта: " .. proj .. "\n")
    local tracks = root:findAllChunksByName("TRACK")
    if tracks then
      for _, track in ipairs(tracks) do
        local items = track:findAllChunksByName("ITEM")
        if items then
          for _, item in ipairs(items) do
            local sources = item:findAllChunksByName("SOURCE")
            if sources then
              for _, source in ipairs(sources) do
                local node = source:findFirstNodeByName("FILE")
                if node then
                  local file_token = node:getToken(2).token
                  local full_path = file_token
                  if not file_token:match('^.:[\\/].*') then
                    full_path = project_folder .. file_token
                    local rel_dir = file_token:match("^(.*)[\\/]")
                    if rel_dir then
                      local abs_dir = project_folder .. rel_dir
                      media_dirs_set[abs_dir] = true
                    end
                  end
                  used_media_set[full_path:lower()] = full_path
                end
              end
            end
          end
        end
      end
    end
  end
end

local used_media_files = {}
local skip_exts = { m4a=1, mp4=1, mov=1, avi=1, mkv=1, flv=1, wmv=1, webm=1 }

for _, path in pairs(used_media_set) do
  local ext = path:match("%.([^%.\\/:]+)$")
  if not (ext and skip_exts[ext:lower()]) then
    table.insert(used_media_files, path)
  end
end

-- Имя проекта без расширения
local proj_name_with_ext = reaper.GetProjectName("", "")
local base_name = proj_name_with_ext:gsub("%.rpp$", "")

-- Определяем имя медиа-папки (например, "Sample"), берём первое найденное
local media_folder_name = nil
for abs_dir, _ in pairs(media_dirs_set) do
  media_folder_name = abs_dir:match("([^"..sep.."]+)$")
  break
end
if not media_folder_name then media_folder_name = "Sample" end

-- Формируем итоговые папки: "ИмяПроекта [TIMER]" и внутри неё папку медиа (например, "Sample")
local target_folder = project_folder .. sep .. base_name .. " [TIMER]"
local final_target = target_folder .. sep .. media_folder_name

if not reaper.file_exists(target_folder) then
  reaper.RecursiveCreateDirectory(target_folder, 0)
end
if not reaper.file_exists(final_target) then
  reaper.RecursiveCreateDirectory(final_target, 0)
end

local copier = FileCopier:new(1024 * 1024)
copier:add_files(used_media_files, final_target, false)
copier:process_queue()

--reaper.ShowConsoleMsg("\nСкопировано " .. #used_media_files .. " медиафайлов в: " .. final_target .. "\n")
reaper.defer(function() end)


end

l.da()l.net()