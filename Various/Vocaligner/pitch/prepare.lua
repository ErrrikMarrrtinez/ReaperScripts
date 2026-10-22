-- @noindex
local import=...;local Notes=import('pitch/notes');local Curve=import('pitch/curve');local M={}
-- Keep only the preceding preparation. Fixed one-second cells have mandatory
-- endpoints, so reusing one never changes the neighbouring cell's interpolation.
local function source(data)
  local offset=0
  while data and data._source do offset=offset+(data._offset or 0);data=data._source end
  return data,offset
end
function M.run(notes,len,job,version,data,previous)
  local resolved=Notes.resolve(notes);local original,offset=source(data)
  local auto=data and data._auto_key or ''
  local cache={notes=Notes.copy(resolved),len=len,version=version,source=original,offset=offset,cells={},auto=auto}
  -- Auto-слой меняет поправку везде: другой ключ — пересобрать все ячейки
  local valid=previous and previous.len==len and previous.version==version and previous.source==original and previous.offset==offset and previous.auto==auto
  local dirty={};local count=math.ceil(len)
  if valid then
    for _,range in ipairs(Notes.changed_ranges(previous.notes,resolved))do
      for k=math.max(1,math.floor(range[1])+1),math.min(count,math.floor(range[2])+1)do dirty[k]=true end
    end
  end
  local result={pitch={},formant={}};cache.rebuilt_cells=0;cache.reused_cells=0
  for k=1,count do
    local cell=valid and not dirty[k] and previous.cells[k]
    if cell then cache.reused_cells=cache.reused_cells+1
    else
      local range={k-1,math.min(k,len)}
      cell={pitch=Curve.points(resolved,len,'shift',job,version,data,range),formant=Curve.points(resolved,len,'formant',job,version,data,range)}
      cache.rebuilt_cells=cache.rebuilt_cells+1
    end
    cache.cells[k]=cell
    for _,field in ipairs({'pitch','formant'})do local out=result[field]
      for i,p in ipairs(cell[field])do if i>1 or #out==0 then out[#out+1]=p end end
    end
    if job then job:checkpoint(k/math.max(1,count),'Preparing pitch changes') end
  end
  return result,cache
end
return M
