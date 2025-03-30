--@noindex
--NoIndex: true

local DEBUG_MODE = true

if not reaper.CF_ShellExecute then
  reaper.MB("Missing dependency: SWS extension.", "Error", 0)
  return
end



local os_sep = package.config:sub(1,1)

local script_path_suka = debug.getinfo(1, "S").source:match([[^@?(.*[\/])[^\/]-$]])


local utils = dofile(script_path_suka .. 'mrtnz_utils.lua')
local results = utils.ShowSubprojectUsefulSeconds()

for i, r in ipairs(results) do
  r.name = r.name:gsub(" %[subproject%]", "")
end

local project_full_name = reaper.GetProjectName(0, "")
if project_full_name == "" then
  reaper.MB("Проект не сохранён!", "Ошибка", 0)
  return
end
local project_clean_name = project_full_name:gsub("%.rpp", "")

local data = {}
local total_seconds = 0
local total_calculated = 0
for _, result in ipairs(results) do
  local calculated = result.usefulSeconds * 150
  total_seconds = total_seconds + result.usefulSeconds
  total_calculated = total_calculated + calculated
  
  table.insert(data, {
    Name = result.name,
    Seconds = result.usefulSeconds,
    Calculated = calculated
  })
end

local retval, proj_file = reaper.EnumProjects(-1)
if proj_file == "" then
  reaper.MB("Проект не сохранён!", "Ошибка", 0)
  return
end

local project_path = proj_file:match("^(.*)[\\/]") or ""
if project_path == "" then
  reaper.MB("Невозможно определить директорию проекта", "Ошибка", 0)
  return
end

local parent_path = project_path:match("^(.*)[\\/][^\\/]+$") or project_path
local directory_name = parent_path:match("([^" .. os_sep .. "]+)$") or project_clean_name
if DEBUG_MODE then
  reaper.ShowConsoleMsg("Directory name (book name): " .. directory_name .. "\n")
  reaper.ShowConsoleMsg("Project name (sheet name): " .. project_clean_name .. "\n")
end

local csv_file = project_path .. os_sep .. "project_data.csv"
local f = io.open(csv_file, "w")
if not f then
  reaper.MB("Невозможно создать временный CSV-файл", "Ошибка", 0)
  return
end

f:write("Name,Seconds,Rate,Calculated\n")

for _, row in ipairs(data) do
  f:write(string.format("%s,%.2f,%.2f,%.2f\n", 
    row.Name:gsub(",", " "),
    row.Seconds,
    150,
    row.Calculated))
end

f:write(string.format("TOTAL,%.2f,,%.2f\n", total_seconds, total_calculated))
f:close()


local python_script_path = script_path_suka.."create_exc.py"

local python_cmd = string.format('python "%s" "%s" "%s" "%s"', 
                               python_script_path, 
                               directory_name, 
                               csv_file,
                               project_clean_name)

if DEBUG_MODE then
 -- Tooltip("Executing: " .. python_cmd)
  reaper.ShowConsoleMsg("Executing: " .. python_cmd .. "\n")
end

local ret = reaper.ExecProcess(python_cmd, 0)

if DEBUG_MODE then
  if ret ~= "" then
   -- Tooltip("Python result: " .. ret)
    reaper.ShowConsoleMsg("Python result: " .. utf8.fix(ret) .. "\n")
  else
   -- Tooltip("Python script executed with no output")
    reaper.ShowConsoleMsg("Python script executed with no output\n")
  end
end

os.remove(csv_file)