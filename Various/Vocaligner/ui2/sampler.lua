-- @noindex
-- Сэмплирующий профайлер Lua: debug.sethook раз в N инструкций запоминает текущую строку и функцию.
-- Видит время самих Lua-функций (контуры, силуэты, разбор нот), которое cfillion-профайлер не показывает.
-- Запуск на несколько секунд, результат — в консоль REAPER (топ строк и функций с долей сэмплов).
local M={}
local state

function M.running() return state~=nil end

function M.start(seconds,every)
  if state then return end
  local lines,funcs,total={},{},0
  state={until_t=reaper.time_precise()+(seconds or 5),lines=lines,funcs=funcs,started=reaper.time_precise(),frames=0}
  debug.sethook(function()
    local info=debug.getinfo(2,'Sl')
    if not info then return end
    local src=info.short_src or '?'
    local lk=src..':'..tostring(info.currentline or 0)
    lines[lk]=(lines[lk] or 0)+1
    local fk=src..':'..tostring(info.linedefined or 0)
    funcs[fk]=(funcs[fk] or 0)+1
    total=total+1;state.total=total
  end,'',every or 1000)
end

local function top(t,total,n)
  local list={}
  for k,c in pairs(t) do list[#list+1]={k,c} end
  table.sort(list,function(a,b) return a[2]>b[2] end)
  local out={}
  for i=1,math.min(n,#list) do out[#out+1]=string.format('%5.1f%%  %6d  %s',list[i][2]/total*100,list[i][2],list[i][1]) end
  return table.concat(out,'\n')
end

-- вызывать раз в кадр: считает кадры и по истечении времени снимает хук и печатает отчёт
function M.tick()
  if not state then return end
  state.frames=state.frames+1
  if reaper.time_precise()<state.until_t then return end
  debug.sethook()
  local s=state;state=nil
  local total=math.max(1,s.total or 0)
  local secs=reaper.time_precise()-s.started
  reaper.ShowConsoleMsg(string.format('\n=== Vocaligner Lua sampler: %d samples, %d frames, %.1f s (%.1f fps) ===\n',total,s.frames,secs,s.frames/math.max(.001,secs)))
  reaper.ShowConsoleMsg('--- functions (file:line where defined) ---\n'..top(s.funcs,total,25)..'\n')
  reaper.ShowConsoleMsg('--- hot lines ---\n'..top(s.lines,total,40)..'\n')
end

return M
