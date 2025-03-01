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
local function generate_html(data, total_seconds, total_calculated)
  local html = [[
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>]] .. project_clean_name .. [[ - Audio Duration</title>
<style>
  body { font-family: Arial, sans-serif; margin: 20px; background-color: #f9f9f9; }
  .header { text-align: center; margin: 20px; }
  .multiplier-container { text-align: center; margin: 20px; }
  .multiplier-container input { padding: 5px; font-size: 1em; width: 80px; }
  table { width: 90%; border-collapse: collapse; margin: 20px auto; background-color: #fff; border-radius: 8px; overflow: hidden; box-shadow: 0 2px 5px rgba(0,0,0,0.2); }
  th, td { border: 1px solid #dddddd; text-align: left; padding: 8px; }
  th { background-color: #4CAF50; color: white; }
  tr:nth-child(even) { background-color: #f2f2f2; }
  .rate-input { width: 60px; text-align: center; }
  .project-header { background-color: #333; color: #fff; text-align: center; font-size: 1.2em; }
  .total-row { font-weight: bold; background-color: #e6f7e6; }
</style>
</head>
<body>
<div class="header">
  <h2>]] .. project_clean_name .. [[ - Audio Duration Report</h2>
</div>
<div class="multiplier-container">
  <label for="default-rate">Default Rate:</label>
  <input type="number" id="default-rate" value="150" /> 
  <button onclick="applyDefaultRate()">Apply to All</button>
</div>
<table id="audioTable">
  <tr>
    <th>Name</th>
    <th>Seconds</th>
    <th>Rate</th>
    <th>Total</th>
  </tr>
]]

  for _, row in ipairs(data) do
    html = html .. [[
  <tr>
    <td>]] .. tostring(row.Name) .. [[</td>
    <td>]] .. string.format("%.2f", row.Seconds) .. [[</td>
    <td><input type="number" class="rate-input" value="150" oninput="updateCalculation(this)"></td>
    <td class="calculated" data-seconds="]] .. tostring(row.Seconds) .. [[">]] .. string.format("%.2f", row.Calculated) .. [[</td>
  </tr>
]]
  end

  html = html .. [[
  <tr class="total-row">
    <td>TOTAL</td>
    <td id="total-seconds">]] .. string.format("%.2f", total_seconds) .. [[</td>
    <td></td>
    <td id="total-calculated">]] .. string.format("%.2f", total_calculated) .. [[</td>
  </tr>
</table>

<script>
function updateCalculation(input) {
  const row = input.parentNode.parentNode;
  const seconds = parseFloat(row.querySelector('td:nth-child(2)').textContent);
  const rate = parseFloat(input.value) || 0;
  const calculatedCell = row.querySelector('.calculated');
  
  const calculated = seconds * rate;
  calculatedCell.textContent = calculated.toFixed(2);
  
  updateTotals();
}

function updateTotals() {
  let totalCalculated = 0;
  document.querySelectorAll('tr:not(.total-row) .calculated').forEach(cell => {
    totalCalculated += parseFloat(cell.textContent) || 0;
  });
  
  document.getElementById('total-calculated').textContent = totalCalculated.toFixed(2);
}

function applyDefaultRate() {
  const defaultRate = document.getElementById('default-rate').value;
  document.querySelectorAll('.rate-input').forEach(input => {
    input.value = defaultRate;
    updateCalculation(input);
  });
}
</script>
</body>
</html>
]]
  return html
end

local html_content = generate_html(data, total_seconds, total_calculated)

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