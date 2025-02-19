--@noindex
--NoIndex: true

local r = reaper
local f = dofile(debug.getinfo(1, "S").source:match([[^@?(.*[\/])[^\/]-$]]) .. 'mrtnz_utils.lua')
math.randomseed(os.time())
r.Main_OnCommand(40026, 0)

local track = r.GetTrack(0, 0)
if track then
    local retval, track_name = r.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
    if not track_name:find("%[video%]") then
        r.GetSetMediaTrackInfo_String(track, "P_NAME", track_name.." [video]" , true)
    end
end

local _, current_rpp = r.EnumProjects(-1, "")
if not current_rpp or current_rpp == "" then
  r.ShowMessageBox("\n\nСохрани проект перед запуском скрипта!\n\n\nIltimos, skriptni ishga tushirishdan oldin loyihani saqlang!\n\n", "Ошибка / Xato", 0)
  return
end

local num_selected = r.CountSelectedTracks(0)
if num_selected == 0 then
  r.ShowMessageBox("\n\nНет выделенных треков!\n\n\nTanlangan treklar mavjud emas!\n\n", "Ошибка / Xato", 0)
  return
end

local parent_dir = current_rpp:match("(.*)[/\\].-$") or ""

local tracksToProcess = {}
local overwriteProjects = {}
local newProjects = {}

for i = 0, num_selected - 1 do
  local sel_track = r.GetSelectedTrack(0, i)
  if sel_track then
    local _, orig_name = r.GetSetMediaTrackInfo_String(sel_track, "P_NAME", "", false)
    local trimmed_name = f.TrimEdges(orig_name)
    if trimmed_name == "" then
      r.ShowMessageBox("\n\nУ выбранного трека пустое имя!\n\n\nTanlangan trekingiz nomi bo'sh!\n\n", "Ошибка / Xato", 0)
      return
    end
    local name_no_sub = trimmed_name:gsub("%[subproject%]", "")
    name_no_sub = f.TrimEdges(name_no_sub)
    local new_project_path = parent_dir .. "\\" .. name_no_sub .. ".rpp"
    
    local exists = false
    local file = io.open(new_project_path, "r")
    if file then
      exists = true
      io.close(file)
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
                  "\nВ случае перезаписи все записи, созданные в них, будут удалены.\n\n\n" ..
                  "Quyidagi kichik loyihalarni qayta yozishni xohlaysizmi:\n" ..
                  table.concat(overwriteProjects, "\n") ..
                  "\nAgar qayta yozilsa, undagi barcha yozuvlar o'chiriladi.\n\n"
  local retval = r.ShowMessageBox(message, "Подтверждение перезаписи / Tasdiqlash", 4)
  if retval ~= 6 then
    overwriteConfirmed = false
  end
end

local createdSubprojects = {}
for _, item in ipairs(tracksToProcess) do
  if item.exists and not overwriteConfirmed then
  else
    local success = f.CreateSubprojectForTrack(item.track, current_rpp, parent_dir)
    if success and not item.exists then
      table.insert(createdSubprojects, item.name_no_sub)
    end
  end
end

if #createdSubprojects > 0 then
  local message = "\n\nПодпроекты успешно созданы:\n" .. table.concat(createdSubprojects, "\n") .. "\n\n\n" ..
                  "Kichik loyihalar muvaffaqiyatli yaratildi:\n" .. table.concat(createdSubprojects, "\n") .. "\n\n"
  r.ShowMessageBox(message, "Успех / Muvaffaqiyat", 0)
end
r.Main_OnCommand(40026, 0)
