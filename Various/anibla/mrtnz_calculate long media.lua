--@noindex
--NoIndex: true




local f = dofile(debug.getinfo(1, "S").source:match([[^@?(.*[\/])[^\/]-$]]) .. 'mrtnz_utils.lua')

local removeGaps = f.RemoveGaps

function getTrackName(track)
  local ok, name = reaper.GetTrackName(track)
  if ok and name then return name
  else return "Unnamed Track" end
end

function getTrackItems()
  local trackItems = {}
  local itemCount = reaper.CountSelectedMediaItems(0)
  
  for i = 0, itemCount - 1 do
    local item = reaper.GetSelectedMediaItem(0, i)
    local track = reaper.GetMediaItem_Track(item)
    local trackName = getTrackName(track)
    
    if not trackItems[trackName] then
      trackItems[trackName] = {}
    end
    
    table.insert(trackItems[trackName], item)
  end
  
  return trackItems
end

function calculateDuration(items)
  local totalLen = 0
  for _, item in ipairs(items) do
    totalLen = totalLen + reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
  end
  return totalLen
end

function generateHTML(data)
  local project_name = reaper.GetProjectName(0, "") or "Project"
  project_name = project_name:gsub("%.rpp", "")
  
  local html = [[
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>]] .. project_name .. [[ - Audio Duration</title>
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
  <h2>]] .. project_name .. [[ - Audio Duration Report</h2>
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

  local total_seconds = 0
  local total_calculated = 0
  
  for name, seconds in pairs(data) do
    total_seconds = total_seconds + seconds
    local calculated = seconds * 150
    total_calculated = total_calculated + calculated
    
    html = html .. [[
  <tr>
    <td>]] .. name .. [[</td>
    <td>]] .. string.format("%.2f", seconds) .. [[</td>
    <td><input type="number" class="rate-input" value="150" oninput="updateCalculation(this)"></td>
    <td class="calculated" data-seconds="]] .. seconds .. [[">]] .. string.format("%.2f", calculated) .. [[</td>
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

function saveHTMLandOpen(html)
  if not reaper.CF_ShellExecute then
    reaper.MB("Missing dependency: SWS extension.", "Error", 0)
    return false
  end
  
  -- Получаем путь к проекту
  local retval, proj_file = reaper.EnumProjects(-1)
  local project_path = ""
  
  if proj_file ~= "" then
    project_path = proj_file:match("^(.*)[\\/]") or ""
  end
  
  -- Если проект не сохранен, используем временную директорию
  if project_path == "" then
    if reaper.GetOS():match("^Win") then
      project_path = os.getenv("TEMP") or "C:\\"
    else
      project_path = os.getenv("TMPDIR") or "/tmp"
    end
  end
  
  -- Определяем разделитель для операционной системы
  local os_sep = package.config:sub(1,1)
  
  -- Создаем имя файла
  local filename = project_path .. os_sep .. "audio_durations.html"
  
  -- Сохраняем HTML в файл
  local file = io.open(filename, "w")
  if not file then
    reaper.MB("Cannot write to file: " .. filename, "Error", 0)
    return false
  end
  
  file:write(html)
  file:close()
  
  -- Открываем файл в браузере
  reaper.CF_ShellExecute(filename)
  
  return true
end

function main()
  reaper.Undo_BeginBlock()
  
  -- Запуск действия по удалению тишины (Dynamic split items)
  reaper.Main_OnCommand(40315, 0)
  
  local trackItems = getTrackItems()
  local durations = {}
  
  for trackName, items in pairs(trackItems) do
    removeGaps(items)
    local duration = calculateDuration(items)
    durations[trackName] = duration
  end
  
  reaper.UpdateArrange()
  reaper.Undo_EndBlock("Remove Gaps Between Items", -1)
  
  -- Генерируем HTML
  local html = generateHTML(durations)
  
  -- Сохраняем и открываем HTML
  if not saveHTMLandOpen(html) then
    -- Выводим результаты в консоль, если не удалось сохранить HTML
    local results = ""
    for name, duration in pairs(durations) do
      results = results .. name .. ": " .. string.format("%.2f", duration) .. " сек.\n"
    end
    reaper.ShowConsoleMsg(results)
  end
end

main()