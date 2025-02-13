--@noindex
--NoIndex: true

dofile(debug.getinfo(1, "S").source:match [[^@?(.*[\/])[^\/]-$]]..'Reateam_RPP-Parser.lua')

local function TrimEdges(str)
  return (str or ""):match("^%s*(.-)%s*$")
end

-- Get track chunk
local function GetTrackChunk(track)
  if not track then return nil end
  local _, chunk = reaper.GetTrackStateChunk(track, "", false)
  return chunk
end

-- Empty track template
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
TRACKHEIGHT 0 0 0 0 0 0 0
INQ 0 0 0 0.5 100 0 0 100
NCHAN 2
FX 1
TRACKID {4D70B74F-BC1F-4748-B517-526849967BA4}
PERF 0
MIDIOUT -1
MAINSEND 1 0
>]]

local function CreateSubproject(sel_track, current_rpp, parent_dir)
  -- Получаем имя трека и убираем лишние пробелы
  local _, orig_name = reaper.GetSetMediaTrackInfo_String(sel_track, "P_NAME", "", false)
  local trimmed_name = TrimEdges(orig_name)
  if trimmed_name == "" then
    reaper.ShowMessageBox("\n\nУ выбранного трека пустое имя!\n\nTanlangan trek nomi bo'sh!\n\n", "Ошибка / Xato", 0)
    return false
  end

  -- Имя подпроекта без "[subproject]"
  local name_no_sub = trimmed_name:gsub("%[subproject%]", "")
  name_no_sub = TrimEdges(name_no_sub)
  local new_project_path = parent_dir .. "\\" .. name_no_sub .. ".rpp"

  -- Парсим текущий проект
  local root = ReadRPP(current_rpp)
  if not root or type(root) ~= "table" then
    reaper.ShowMessageBox("\n\nНе удалось распарсить проект!\n\nLoyiha tahlil qilinmadi!\n\n", "Ошибка / Xato", 0)
    return false
  end

  -- Создаём пустой RPP объект
  local newproj = CreateRPP()

  -- Копируем маркеры и регионы
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

  -- Копируем видеотрек
  for i = 0, reaper.CountTracks(0) - 1 do
    local track = reaper.GetTrack(0, i)
    local _, track_name = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
    if track_name:lower():find("%[video%]") then
      local track_chunk = GetTrackChunk(track)
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

  -- Копируем выделенный трек
  local selected_track_chunk = GetTrackChunk(sel_track)
  if selected_track_chunk then
    local selected_new_track = ReadRPPChunk(selected_track_chunk)
    if selected_new_track then
      selected_new_track:StripGUID()
      newproj:addNode(selected_new_track)
    end
  end

  -- Добавляем пустой трек с именем проекта + 4-значный айди
  local new_track_name = name_no_sub .. " " .. string.format("%04d", math.random(1000, 9999))
  local modified_empty_chunk = EMPTY_TRACK_CHUNK:gsub('NAME ""', 'NAME "' .. new_track_name .. '"')
  local empty_track = ReadRPPChunk(modified_empty_chunk)
  if empty_track then
    empty_track:StripGUID()
    newproj:addNode(empty_track)
  end

  -- Добавляем [subproject] к имени выделенного трека, если его там нет
  if not trimmed_name:lower():find("%[subproject%]") then
    reaper.GetSetMediaTrackInfo_String(sel_track, "P_NAME", trimmed_name .. " [subproject]", true)
  end

  -- Сохраняем и открываем новый проект
  local ok, err = WriteRPP(new_project_path, newproj)
  if not ok then
    reaper.ShowMessageBox("\n\nОшибка записи проекта:\n" .. tostring(err) .. "\n\nLoyiha yozish xatosi:\n" .. tostring(err) .. "\n\n", "Ошибка / Xato", 0)
    return false
  end

  return true
end

function main()
  math.randomseed(os.time())
  local _, current_rpp = reaper.EnumProjects(-1, "")
  if not current_rpp or current_rpp == "" then
    reaper.ShowMessageBox("\n\nСохрани проект перед запуском скрипта!\n\nSkriptni ishga tushurishdan oldin loyihani saqlang!\n\n", "Ошибка / Xato", 0)
    return
  end

  local num_selected = reaper.CountSelectedTracks(0)
  if num_selected == 0 then
    reaper.ShowMessageBox("\n\nНет выделенных треков!\n\nTanlangan treklar yo'q!\n\n", "Ошибка / Xato", 0)
    return
  end

  local parent_dir = current_rpp:match("(.*)[/\\].-$") or ""
  
  -- Предварительный проход: собираем данные о выбранных треках
  local tracksToProcess = {}
  local overwriteProjects = {} -- подпроекты, которые уже существуют
  local newProjects = {}       -- подпроекты, которых ещё нет
  for i = 0, num_selected - 1 do
    local sel_track = reaper.GetSelectedTrack(0, i)
    if sel_track then
      local _, orig_name = reaper.GetSetMediaTrackInfo_String(sel_track, "P_NAME", "", false)
      local trimmed_name = TrimEdges(orig_name)
      if trimmed_name == "" then
        reaper.ShowMessageBox("\n\nУ выбранного трека пустое имя!\n\nTanlangan trek nomi bo'sh!\n\n", "Ошибка / Xato", 0)
        return
      end
      local name_no_sub = trimmed_name:gsub("%[subproject%]", "")
      name_no_sub = TrimEdges(name_no_sub)
      local new_project_path = parent_dir .. "\\" .. name_no_sub .. ".rpp"
      
      local exists = false
      local f = io.open(new_project_path, "r")
      if f then
        exists = true
        io.close(f)
      end
      
      table.insert(tracksToProcess, { track = sel_track, name_no_sub = name_no_sub, new_project_path = new_project_path, exists = exists })
      
      if exists then
        table.insert(overwriteProjects, name_no_sub)
      else
        table.insert(newProjects, name_no_sub)
      end
    end
  end

  local overwriteConfirmed = true
  if #overwriteProjects > 0 then
    local message = "\n\nВы уверены, что хотите перезаписать следующие подпроекты:\n" ..
                    table.concat(overwriteProjects, "\n") ..
                    "\nВ случае перезаписи все записи, созданные в них, будут удалены.\n\n" ..
                    "Quyidagi kichik loyihalarni qayta yozishga ishonchingiz komilmi:\n" ..
                    table.concat(overwriteProjects, "\n") ..
                    "\nQayta yozish holatida, ularda yaratilgan barcha yozuvlar o'chiriladi.\n\n"
    local retval = reaper.ShowMessageBox(message, "Подтверждение перезаписи / Qayta yozishni tasdiqlash", 4)
    if retval ~= 6 then
      overwriteConfirmed = false
    end
  end

  local createdSubprojects = {}
  for _, item in ipairs(tracksToProcess) do
    if item.exists and not overwriteConfirmed then
      -- Пропускаем перезапись для этого подпроекта
    else
      local success = CreateSubproject(item.track, current_rpp, parent_dir)
      -- Добавляем в список созданных только те подпроекты, которые создаются впервые (не перезаписываются)
      if success and not item.exists then
        table.insert(createdSubprojects, item.name_no_sub)
      end
    end
  end

  if #createdSubprojects > 0 then
    local message = "\n\nПодпроекты успешно созданы:\n" .. table.concat(createdSubprojects, "\n") .. "\n\n" ..
                    "Kichik loyihalar muvaffaqiyatli yaratildi:\n" .. table.concat(createdSubprojects, "\n") .. "\n\n"
    reaper.ShowMessageBox(message, "Успех / Muvaffaqiyat", 0)
  end
end

reaper.Undo_BeginBlock()
local first_track = reaper.GetTrack(0, 0)  -- Получаем первый трек
if first_track then
  local _, current_name = reaper.GetTrackName(first_track, "")
  if not current_name:lower():find("%[video%]") then
    reaper.GetSetMediaTrackInfo_String(first_track, "P_NAME", current_name .. " [video]", true)
  end
end
main()
reaper.Undo_EndBlock("Create subprojects from selected tracks", -1)
