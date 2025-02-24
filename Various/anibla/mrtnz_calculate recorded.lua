--@noindex
--NoIndex: true


if not reaper.CF_ShellExecute then
    reaper.MB("Missing dependency: SWS extension.", "Error", 0)
    return
  end
  
  -- Функция Tooltip для вывода сообщения (по желанию)
  function Tooltip(message)
    local x, y = reaper.GetMousePosition()
    reaper.TrackCtl_SetToolTip(tostring(message), x+17, y+17, false)
  end
  
  local os_sep = package.config:sub(1,1)
  
  -- Подключаем утилиты и получаем данные
  local utils = dofile(debug.getinfo(1, "S").source:match([[^@?(.*[\/])[^\/]-$]]) .. 'mrtnz_utils.lua')
  local results = utils.ShowSubprojectUsefulSeconds()
  
  -- Убираем " [subproject]" из имени каждого результата
  for i, r in ipairs(results) do
    r.name = r.name:gsub(" %[subproject%]", "")
  end
  
  -- Получаем имя проекта и удаляем только расширение .rpp
  local project_full_name = reaper.GetProjectName(0, "")
  if project_full_name == "" then
    reaper.MB("Проект не сохранён!", "Ошибка", 0)
    return
  end
  local project_clean_name = project_full_name:gsub("%.rpp", "")
  
  -- Формируем данные для текущего проекта
  local data = {}
  for _, result in ipairs(results) do
    table.insert(data, {
      Name = result.name,
      Seconds = result.usefulSeconds,
      Calculated = result.usefulSeconds * 150
    })
  end
  
  -- Получаем путь к файлу проекта и извлекаем директорию
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
  
  -- Генерируем HTML с таблицей и полем ввода множителя
  local function generate_html(data)
    local html = [[
  <!DOCTYPE html>
  <html lang="en">
  <head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>]] .. project_clean_name .. [[</title>
  <style>
    body { font-family: Arial, sans-serif; margin: 20px; background-color: #f9f9f9; }
    .multiplier-container { text-align: center; margin: 20px; }
    .multiplier-container input { padding: 5px; font-size: 1em; width: 80px; }
    table { width: 90%; border-collapse: collapse; margin: 20px auto; background-color: #fff; border-radius: 8px; overflow: hidden; box-shadow: 0 2px 5px rgba(0,0,0,0.2); }
    th, td { border: 1px solid #dddddd; text-align: left; padding: 8px; }
    th { background-color: #4CAF50; color: white; }
    tr:nth-child(even) { background-color: #f2f2f2; }
    .project-header { background-color: #333; color: #fff; text-align: center; font-size: 1.2em; }
  </style>
  </head>
  <body>
  <div class="multiplier-container">
    <label for="multiplier">Multiplier:</label>
    <input type="number" id="multiplier" value="150" />
  </div>
  <table id="projectTable">
    <tr class="project-header"><th colspan="3">]] .. project_clean_name .. [[</th></tr>
    <tr>
      <th>Name</th>
      <th>Seconds</th>
      <th>Calculated</th>
    </tr>
  ]]
    for _, row in ipairs(data) do
      html = html .. "  <tr>\n"
      html = html .. "    <td>" .. tostring(row.Name) .. "</td>\n"
      html = html .. "    <td>" .. tostring(row.Seconds) .. "</td>\n"
      html = html .. string.format('    <td data-seconds="%s">%s</td>\n', tostring(row.Seconds), tostring(row.Calculated))
      html = html .. "  </tr>\n"
    end
    html = html .. [[
  </table>
  <script>
  document.getElementById('multiplier').addEventListener('input', function() {
    var multiplier = parseFloat(this.value) || 0;
    var table = document.getElementById('projectTable');
    var rows = table.getElementsByTagName('tr');
    for (var i = 0; i < rows.length; i++) {
      var cells = rows[i].getElementsByTagName('td');
      if (cells.length === 3) {
        var seconds = parseFloat(cells[1].innerText) || 0;
        cells[2].innerText = seconds * multiplier;
      }
    }
  });
  </script>
  </body>
  </html>
  ]]
    return html
  end
  
  local html_content = generate_html(data)
  
  -- Сохраняем HTML-файл (перезаписывая целиком)
  local html_file = project_path .. os_sep .. "project_table.html"
  local f = io.open(html_file, "w")
  if not f then
    reaper.MB("Невозможно записать HTML-файл", "Ошибка", 0)
    return
  end
  f:write(html_content)
  f:close()
  
  -- Открываем HTML-файл в браузере
  reaper.CF_ShellExecute(html_file)