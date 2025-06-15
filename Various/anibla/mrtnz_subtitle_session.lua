--@noindex
--NoIndex: true

local SessionManager = {}
local r = reaper

local EXTNAME = "MRTNZ_SUBTITLE_EDITOR"

function SessionManager.saveSession(columns, columnOrder)
  r.SetProjExtState(0, EXTNAME, "version", "1.1")  -- Увеличиваем версию
  
  -- Сохраняем порядок колонок
  if columnOrder then
    for i = 1, #columnOrder do
      r.SetProjExtState(0, EXTNAME, "order" .. i, tostring(columnOrder[i]))
    end
    r.SetProjExtState(0, EXTNAME, "orderCount", tostring(#columnOrder))
  end
  
  for i = 1, #columns do
    local col = columns[i]
    local prefix = "col" .. i .. "_"
    
    r.SetProjExtState(0, EXTNAME, prefix .. "enabled", col.enabled and "1" or "0")
    r.SetProjExtState(0, EXTNAME, prefix .. "name", col.name or "")
    r.SetProjExtState(0, EXTNAME, prefix .. "filepath", col.filePath or "")
    r.SetProjExtState(0, EXTNAME, prefix .. "deactivated", col.deactivated and "1" or "0")
    
    if col.enabled and #col.subtitles > 0 then
      r.SetProjExtState(0, EXTNAME, prefix .. "count", tostring(#col.subtitles))
      
      for j, sub in ipairs(col.subtitles) do
        local subPrefix = prefix .. "sub" .. j .. "_"
        r.SetProjExtState(0, EXTNAME, subPrefix .. "start", tostring(sub.start))
        r.SetProjExtState(0, EXTNAME, subPrefix .. "end", tostring(sub._end))
        r.SetProjExtState(0, EXTNAME, subPrefix .. "text", col.values[j] or sub.text or "")
      end
    else
      r.SetProjExtState(0, EXTNAME, prefix .. "count", "0")
    end
  end
end

function SessionManager.loadSession()
  local retval, version = r.GetProjExtState(0, EXTNAME, "version")
  if retval == 0 then
    return nil, nil
  end
  
  local columns = {}
  local columnOrder = nil
  
  -- Загружаем порядок колонок для версии 1.1+
  if version == "1.1" then
    local _, orderCountStr = r.GetProjExtState(0, EXTNAME, "orderCount")
    local orderCount = tonumber(orderCountStr) or 5
    columnOrder = {}
    
    for i = 1, orderCount do
      local _, orderStr = r.GetProjExtState(0, EXTNAME, "order" .. i)
      local orderValue = tonumber(orderStr) or i
      columnOrder[i] = orderValue
    end
  end
  
  -- Если порядок не загружен, используем по умолчанию
  if not columnOrder then
    columnOrder = {1, 2, 3, 4, 5}
  end
  
  for i = 1, 5 do
    local prefix = "col" .. i .. "_"
    local _, enabled = r.GetProjExtState(0, EXTNAME, prefix .. "enabled")
    local _, name = r.GetProjExtState(0, EXTNAME, prefix .. "name")
    local _, filepath = r.GetProjExtState(0, EXTNAME, prefix .. "filepath")
    local _, deactivated = r.GetProjExtState(0, EXTNAME, prefix .. "deactivated")
    local _, countStr = r.GetProjExtState(0, EXTNAME, prefix .. "count")
    
    columns[i] = {
      enabled = (enabled == "1"),
      name = name ~= "" and name or ("Language " .. i),
      filePath = filepath,
      deactivated = (deactivated == "1"),
      subtitles = {},
      values = {},
      selected = {}
    }
    
    local count = tonumber(countStr) or 0
    if columns[i].enabled and count > 0 then
      for j = 1, count do
        local subPrefix = prefix .. "sub" .. j .. "_"
        local _, startStr = r.GetProjExtState(0, EXTNAME, subPrefix .. "start")
        local _, endStr = r.GetProjExtState(0, EXTNAME, subPrefix .. "end")
        local _, text = r.GetProjExtState(0, EXTNAME, subPrefix .. "text")
        
        local start = tonumber(startStr) or 0
        local _end = tonumber(endStr) or 0
        
        columns[i].subtitles[j] = {
          start = start,
          _end = _end,
          text = text
        }
        columns[i].values[j] = text
      end
    end
  end
  
  return columns, columnOrder
end

function SessionManager.clearSession()
  local idx = 0
  while true do
    local retval, key = r.EnumProjExtState(0, EXTNAME, idx)
    if not retval then break end
    r.SetProjExtState(0, EXTNAME, key, "")
    idx = idx + 1
  end
end

return SessionManager