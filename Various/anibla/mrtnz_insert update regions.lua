--@noindex
--NoIndex: true



dofile(debug.getinfo(1, "S").source:match [[^@?(.*[\/])[^\/]-$]]..'Reateam_RPP-Parser.lua')


function get_parrent_project()
  local r = reaper
  local main_project = r.GetSetProjectNotes(0, false, ""):match("main_project=([^\n]+)")
  if main_project then return main_project end
end

function RemoveAllMarkersAndRegions(proj)
  local num_markers, num_regions = reaper.CountProjectMarkers(proj)
  local total = num_markers + num_regions
  for i = total - 1, 0, -1 do
    local retval, isrgn, pos, rgnend, name, markrgnindexnumber = reaper.EnumProjectMarkers(proj, i)
    if retval then
      reaper.DeleteProjectMarker(proj, markrgnindexnumber, isrgn)
    end
  end
end

function ImportMarkersFromParent()
  local parent_proj_name = get_parrent_project()
  if not parent_proj_name then
    reaper.ShowMessageBox("Не найден родительский проект в NOTES!", "Ошибка", 0)
    return
  end

  local cur_proj, cur_proj_path = reaper.EnumProjects(-1, "")
  if not cur_proj_path or cur_proj_path == "" then
    reaper.ShowMessageBox("Сохрани проект перед запуском скрипта!", "Ошибка", 0)
    return
  end

  local cur_proj_dir = cur_proj_path:match("(.*)[/\\]") or ""
  local parent_path = cur_proj_dir .. "\\" .. parent_proj_name

  local parent_root = ReadRPP(parent_path)
  if not parent_root then
    reaper.ShowMessageBox("Ошибка парсинга родительского проекта:\n" .. parent_path, "Ошибка", 0)
    return
  end

  RemoveAllMarkersAndRegions(0)

  -- Устанавливаем фиксированный оранжевый цвет для маркеров/регионов
  local custom_color = reaper.ColorToNative(255, 165, 0) -- оранжевый

  local children = parent_root.children or {}
  local i = 1
  while i <= #children do
    local node = children[i]
    local nm = node:getName()
    if nm == "MARKER" or nm == "REGION" then
      local tokens = node:getTokens()
      if #tokens >= 4 then
        local pos = tonumber(tokens[3]:getString()) or 0
        local name = tokens[4]:getString() or ""
        -- Если токен 8 равен "R" считаем, что это начало региона
        if #tokens >= 8 and tokens[8]:getString() == "R" then
          local region_start = pos
          local region_end = nil
          if i < #children then
            local next_node = children[i+1]
            if next_node:getName() == "MARKER" then
              local next_tokens = next_node:getTokens()
              if next_tokens[2] and next_tokens[2]:getString() == tokens[2]:getString() then
                region_end = tonumber(next_tokens[3]:getString()) or 0
                i = i + 1 -- пропускаем закрывающий маркер
              end
            end
          end
          if region_end and region_end > region_start then
            reaper.AddProjectMarker2(0, true, region_start, region_end, name, custom_color, -1)
          else
            reaper.AddProjectMarker2(0, false, region_start, 0, name, custom_color, -1)
          end
        else
          reaper.AddProjectMarker2(0, false, pos, 0, name, custom_color, -1)
        end
      end
    end
    i = i + 1
  end
end

local function rgb2uint(r, g, b)
  r = math.floor(math.max(0, math.min(255, r)))
  g = math.floor(math.max(0, math.min(255, g)))
  b = math.floor(math.max(0, math.min(255, b)))
  return (r << 16) | (g << 8) | b
end

-- Основная функция
function color_regions()
  reaper.Undo_BeginBlock()
  local _, num_markers, num_regions = reaper.CountProjectMarkers(0)
  local default_color = rgb2uint(135, 206, 235)
  local i = 0
  while i < (num_markers + num_regions) do
    local _, isrgn, pos, rgnend, name, markrgnindexnumber = reaper.EnumProjectMarkers3(0, i)
    if isrgn then
      reaper.SetProjectMarker3(0, markrgnindexnumber, isrgn, pos, rgnend, name, default_color)
    end
    
    i = i + 1
  end
  reaper.Undo_EndBlock("Set all regions to default color", -1)
  reaper.UpdateArrange()
end
reaper.PreventUIRefresh(-1)
reaper.Undo_BeginBlock()
ImportMarkersFromParent()
color_regions()
reaper.Undo_EndBlock("Импорт маркеров/регионов из родительского проекта", -1)
reaper.UpdateArrange()
reaper.PreventUIRefresh(0)
