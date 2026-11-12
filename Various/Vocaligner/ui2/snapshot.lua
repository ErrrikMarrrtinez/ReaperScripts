-- @noindex
-- Bypass «как было до скрипта» через состояние chunk айтема, без пересчёта стадий:
--   * Перед ПЕРВОЙ записью скрипта в проект (все записи начинаются с Undo_BeginBlock2) состояние выделенных айтемов
--     запоминается как «оригинал» — в ProjExtState проекта (не глобально, переживает перезапуск REAPER).
--   * Bypass включён (для выделенных айтемов): текущее состояние сохраняется как «обработанное», в айтем кладётся оригинал — одной записью.
--   * Bypass выключен: «обработанное» возвращается. Если айтем меняли руками, пока bypass был включён, его не трогаем:
--     обработку придётся сделать заново.
-- Cleanup-огибающие, правки сэмплов DeClick, ReaPitch, тайминг Align — всё это часть chunk, отдельной логики на стадию нет.
-- Хранение: chunk режется на текст и блоки правок сэмплов (<SPLS>); блоки уходят в общий пул проекта по хэшу
-- содержимого ('b:<хэш>') — одинаковые (разрезанные айтемы несут одни и те же SPLS) лежат один раз. Остальное —
-- сжатыми байтами одним слоем (pack.lua). Старые значения (экранированный текст) читаются как раньше.
local import=...;local Pack=import('pack');local Codec=import('codec')
local M={}
local SECTION='VocalignerBypass'
local LIMIT=16*1024*1024 -- chunk больше не кладём (с пулом и сжатием в проекте он занимает в разы меньше)
local POOL_MIN=2048      -- блоки SPLS короче — прямо в значении
M.busy=false

local function esc(s) return (s:gsub('[\\\r\n]',{['\\']='\\\\',['\r']='\\r',['\n']='\\n'})) end
local function unesc(s) return (s:gsub('\\([\\rn])',{['\\']='\\',r='\r',n='\n'})) end
-- Сравнение без выделения item (SEL меняется кликом и звука не касается)
local function norm(chunk) return (chunk:gsub('\r',''):gsub('\nSEL %d','\nSEL')) end
local function with_selection(chunk,current)
  local sel=current:match('\nSEL (%d)')
  if not sel then return chunk end
  return (chunk:gsub('\nSEL %d','\nSEL '..sel,1))
end
local function guid_of(r,item)
  local ok,guid=r.GetSetMediaItemInfo_String(item,'GUID','',false)
  return ok and guid~='' and guid or nil
end
local function chunk_of(r,item)
  local ok,text=r.GetItemStateChunk(item,'',false)
  return ok and text or nil
end
local function items(r,project,selected_only)
  local out={}
  if selected_only then
    for i=0,r.CountSelectedMediaItems(project)-1 do out[#out+1]=r.GetSelectedMediaItem(project,i) end
  else
    for i=0,r.CountMediaItems(project)-1 do out[#out+1]=r.GetMediaItem(project,i) end
  end
  return out
end
local pool_text={}  -- ref -> текст блока (содержимое неизменно: ключ = хэш)
local pool_known={} -- project -> {ref=true}: блок уже лежит в проекте
local function pool_get(r,project,ref)
  local t=pool_text[ref];if t then return t end
  local ok,v=r.GetProjExtState(project,SECTION,'b:'..ref);assert(ok~=0 and v~='','Bypass data is incomplete (missing block)')
  t=Pack.unwrap(v);assert(Pack.hash64(t)==ref,'Bypass data is damaged');pool_text[ref]=t;return t
end
-- значение из проекта -> chunk (новый формат или старый экранированный текст)
function M.decode(r,project,raw)
  if not Pack.is_wrapped(raw) then return unesc(raw) end
  local v=Codec.decode(Pack.unwrap(raw));assert(type(v)=='table' and v.v==1 and type(v.parts)=='table','Invalid bypass data')
  local out={}
  for i,p in ipairs(v.parts) do out[i]=type(p)=='string' and p or pool_get(r,project,p.ref) end
  return table.concat(out)
end
-- ссылки на пул в значении (для сборки мусора пула)
function M.refs(raw,set)
  if not Pack.is_wrapped(raw) then return set end
  local ok,v=pcall(function() return Codec.decode(Pack.unwrap(raw)) end)
  if ok and type(v)=='table' and type(v.parts)=='table' then for _,p in ipairs(v.parts) do if type(p)=='table' and p.ref then set[p.ref]=true end end end
  return set
end
-- chunk -> части: текст и блоки <SPLS ...> ... > целыми строками
function M.split(chunk)
  local parts={};local pos=1
  while true do
    local s=chunk:find('<SPLS',pos,true);if not s then break end
    local ls=s;while ls>1 and chunk:sub(ls-1,ls-1)~='\n' do ls=ls-1 end
    local _,c=chunk:find('\n[ \t]*>[^\n]*',s)
    if not c then break end
    if ls>pos then parts[#parts+1]=chunk:sub(pos,ls-1) end
    parts[#parts+1]={text=chunk:sub(ls,c)};pos=c+1
  end
  if pos<=#chunk then parts[#parts+1]=chunk:sub(pos) end
  return parts
end
function M.encode(r,project,chunk)
  local known=pool_known[project] or {};pool_known[project]=known
  local parts={}
  for _,p in ipairs(M.split(chunk)) do
    if type(p)=='table' and #p.text>=POOL_MIN then
      local ref=Pack.hash64(p.text)
      if not known[ref] then
        local ok,v=r.GetProjExtState(project,SECTION,'b:'..ref)
        if ok==0 or v=='' then Pack.put_proj(r,project,SECTION,'b:'..ref,p.text) end
        known[ref]=true;pool_text[ref]=p.text
      end
      parts[#parts+1]={ref=ref}
    else
      local t=type(p)=='table' and p.text or p
      if type(parts[#parts])=='string' then parts[#parts]=parts[#parts]..t else parts[#parts+1]=t end
    end
  end
  return Codec.encode({v=1,parts=parts})
end
local function get(r,project,key)
  local ok,value=r.GetProjExtState(project,SECTION,key)
  if ok~=0 and value~='' then return M.decode(r,project,value) end
end
local function put(r,project,key,value)
  if not value then r.SetProjExtState(project,SECTION,key,'');return end
  Pack.put_proj(r,project,SECTION,key,M.encode(r,project,value))
end
M.get,M.put,M.SECTION=get,put,SECTION

-- Запомнить оригинал выделенных айтемов, если он ещё не запомнен. Вызывается перед записью скрипта — а в редакторе
-- высоты тона это каждая правка, поэтому уже известные айтемы пропускаются по таблице в памяти: без чтения
-- ProjExtState и без распаковки большого chunk на каждую запись.
local status_cache={}
local known={} -- guid -> true: оригинал этого айтема уже запомнен (или запомнен раньше, в проекте)
function M.remember(r,project)
  if M.busy then return 0 end
  local n=0
  for _,item in ipairs(items(r,project,true)) do
    local guid=guid_of(r,item)
    if guid and not known[guid] then
      local ok,stored=r.GetProjExtState(project,SECTION,'o:'..guid)
      local ok2,processed=r.GetProjExtState(project,SECTION,'p:'..guid)
      if (ok~=0 and stored~='') or (ok2~=0 and processed~='') then known[guid]=true
      else
        local text=chunk_of(r,item)
        if text and #text<=LIMIT then put(r,project,'o:'..guid,text);known[guid]=true;n=n+1;status_cache={} end
      end
    end
  end
  return n
end

-- Состояние для выделенных айтемов (кнопка рисуется по нему): engaged — хотя бы у одного включён bypass,
-- available — есть что переключать (у айтема запомнен оригинал и текущее состояние от него отличается, либо bypass уже включён).
-- Считается только при смене выделения или изменении проекта: сравнение chunk — не бесплатное.
M.throttle=0.4 -- не чаще: во время правок (редактор высоты тона) счётчик проекта меняется каждый кадр, а chunk большой
local orig_norm={}   -- guid -> {raw=<значение из проекта>,norm=<нормализованный оригинал>}: без повторной распаковки и gsub
local function original_norm(r,project,guid)
  local ok,raw=r.GetProjExtState(project,SECTION,'o:'..guid)
  if ok==0 or raw=='' then orig_norm[guid]=nil;return nil end
  local c=orig_norm[guid]
  if not c or c.raw~=raw then c={raw=raw,norm=norm(M.decode(r,project,raw))};orig_norm[guid]=c end
  return c.norm
end
function M.invalidate() status_cache={} end
function M.status(r,project)
  local guids={}
  for _,item in ipairs(items(r,project,true)) do local g=guid_of(r,item);if g then guids[#guids+1]=g end end
  local gkey=table.concat(guids,',')
  local count=r.GetProjectStateChangeCount and r.GetProjectStateChangeCount(project) or 0
  local now=r.time_precise and r.time_precise() or 0
  local c=status_cache
  -- смена выделения — сразу; изменения проекта — не чаще M.throttle
  if c.gkey==gkey and (c.count==count or now-c.t<M.throttle) then return c.value end
  local engaged,available=false,false
  for _,item in ipairs(items(r,project,true)) do
    local guid=guid_of(r,item)
    if guid then
      if get(r,project,'p:'..guid) then engaged,available=true,true
      else
        local original=original_norm(r,project,guid)
        local current=original and chunk_of(r,item)
        if current and norm(current)~=original then available=true end
      end
    end
  end
  status_cache={gkey=gkey,count=count,t=now,value={engaged=engaged,available=available}}
  return status_cache.value
end

-- Включить bypass. Возвращает число айтемов, вернувшихся к оригиналу, и сколько не удалось.
-- Только выделенные айтемы.
function M.engage(r,project)
  M.busy=true;status_cache={}
  local reverted,failed=0,0
  r.Undo_BeginBlock2(project);r.PreventUIRefresh(1)
  for _,item in ipairs(items(r,project,true)) do
    local guid=guid_of(r,item);local original=guid and get(r,project,'o:'..guid)
    if original and not get(r,project,'p:'..guid) then
      local current=chunk_of(r,item)
      if current and norm(current)~=norm(original) then
        if #current<=LIMIT then
          put(r,project,'p:'..guid,current)
          if r.SetItemStateChunk(item,with_selection(original,current),false) then reverted=reverted+1
          else put(r,project,'p:'..guid,nil);failed=failed+1 end
        else failed=failed+1 end
      end
    end
  end
  r.PreventUIRefresh(-1);r.UpdateArrange();r.Undo_EndBlock2(project,'Vocaligner: bypass',-1)
  M.busy=false
  return reverted,failed
end

-- Выключить bypass: вернуть обработанное состояние. conflicts — айтемы, изменённые руками во время bypass.
function M.release(r,project)
  M.busy=true;status_cache={}
  local restored,conflicts=0,0
  r.Undo_BeginBlock2(project);r.PreventUIRefresh(1)
  for _,item in ipairs(items(r,project,true)) do
    local guid=guid_of(r,item);local processed=guid and get(r,project,'p:'..guid)
    if processed then
      local original=get(r,project,'o:'..guid);local current=chunk_of(r,item)
      if current and original and norm(current)==norm(original) then
        if r.SetItemStateChunk(item,with_selection(processed,current),false) then restored=restored+1 end
      else conflicts=conflicts+1 end
      put(r,project,'p:'..guid,nil)
    end
  end
  r.PreventUIRefresh(-1);r.UpdateArrange();r.Undo_EndBlock2(project,'Vocaligner: restore processing',-1)
  M.busy=false
  return restored,conflicts
end

-- Перехват начала любой записи скрипта: перед ней запоминаем оригинал (один раз за запуск)
function M.hook(r)
  if r.__vocaligner_bypass_hook then return end
  local original=r.Undo_BeginBlock2
  r.Undo_BeginBlock2=function(project,...)
    if not M.busy then pcall(M.remember,r,project) end
    return original(project,...)
  end
  r.__vocaligner_bypass_hook=true
end
return M
