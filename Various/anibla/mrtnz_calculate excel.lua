--@noindex
--NoIndex: true

local DEBUG_MODE = true

if not reaper.CF_ShellExecute then
  reaper.MB("Missing dependency: SWS extension.", "Error", 0)
  return
end

local script_path = debug.getinfo(1, "S").source:match([[^@?(.*[\/])[^\/]-$]])
local json_file_path = script_path .. 'ivory-mountain-387219-e4bc2546492f.json'
local start_time = reaper.time_precise()

local function removeEmptyLines(str)
  local res = {}
  for line in str:gmatch("[^\r\n]+") do
    if line:match("%S") then table.insert(res, line) end
  end
  return table.concat(res, "\n")
end

local function get_date_created(filePath)
  local _, _, _, _, cdate = reaper.JS_File_Stat( filePath )
  return cdate
end

-- Основная функция, выполняющая всю логику после инициализации
local function goReal()
  local os_sep = package.config:sub(1,1)
  local utils = dofile(script_path .. 'mrtnz_utils.lua')
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

  local python_script_path = script_path .. "create_exc.py"
  local creation_ts = get_date_created(proj_file)

  local python_cmd = string.format('python "%s" "%s" "%s" "%s" "%s"', 
                                   python_script_path, 
                                   directory_name, 
                                   csv_file,
                                   project_clean_name,
                                   creation_ts)

                                   
  if DEBUG_MODE then
    reaper.ShowConsoleMsg("Executing: " .. python_cmd .. "\n")
  end
  local ret = utf8.fix(reaper.ExecProcess(python_cmd, 0))
  if DEBUG_MODE then
    if ret ~= "" then
      reaper.ShowConsoleMsg("Python result: " .. utf8.fix(ret) .. "\n")
    else
      reaper.ShowConsoleMsg("Python script executed with no output\n")
    end
  end

  os.remove(csv_file)
end

-- Функция проверки буфера обмена и создания json-файла
local function checkClipboard()
  local elapsed = reaper.time_precise() - start_time
  local remaining = math.floor(50 - elapsed)
  reaper.ClearConsole()
  reaper.ShowConsoleMsg("осталось " .. remaining .. " секунд, скопируйте json файл\n")
  if elapsed > 50 then 
    reaper.ClearConsole() 
    return 
  end
  local clip = reaper.CF_GetClipboard()
  if clip then
    clip = removeEmptyLines(clip)
    if clip:match('"type"%s*:%s*"service_account"') and 
       clip:match('"project_id"%s*:%s*"ivory%-mountain%-387219"') and 
       clip:match('"private_key_id"%s*:%s*".-"') and 
       clip:match('"private_key"%s*:%s*".-"') then
      local f = io.open(json_file_path, "w")
      if f then 
        f:write(clip) 
        f:close() 
      end
      reaper.ClearConsole()
      goReal()
      return
    end
  end
  reaper.defer(checkClipboard)
end

if reaper.file_exists(json_file_path) then
  reaper.ClearConsole()
  goReal()
else
  checkClipboard()
end
