-- @noindex
-- Уплотнение данных скрипта в открытом проекте (один раз за сессию REAPER на проект, в фоне; и пунктом меню).
--   * Анализы Pitch (ProjExtState), на которые не ссылается ни один тейк (в том числе неактивный), ни копия
--     для BYPASS, и которые созданы не в этой сессии REAPER (на них может вернуть Undo), — удаляются.
--   * Оставшиеся анализы старого формата перепаковываются: волна 8 бит, сжатие, один слой кодирования.
--   * Состояния тейков (Pitch, Polyphonic) старого формата перепаковываются; открытый в редакторе айтем не трогается.
--   * Копии для BYPASS старого формата перепаковываются (общий пул одинаковых SPLS); блоки пула без ссылок удаляются.
-- Значения пишутся с проверкой чтением обратно (pack.lua). Undo REAPER это не затрагивает; проект помечается
-- изменённым — уменьшение попадёт в файл при следующем сохранении.
local import=...;local Pack=import('pack');local Codec=import('codec');local Store=import('pitch/store')
local Wave=import('pitch/waveform');local Snap=import('ui2/snapshot');local M={}
local POLY_KEY='P_EXT:VocalignerPoly1'

-- значения P_EXT внутри текста chunk айтема: строка «Имя значение» или блок <BIN Имя> с base64
function M.chunk_pext(chunk,name)
  local out={}
  for v in chunk:gmatch('\n[ \t]*'..name..' ([^\r\n]+)') do out[#out+1]=v end
  for body in chunk:gmatch('<BIN '..name..'[^\n]*\n(.-)\n[ \t]*>') do out[#out+1]=Pack.unb64(body) end
  return out
end
local function ref_of(text,set)
  if not text or text=='' then return end
  local ok,v=pcall(Store.decode,text)
  if ok and type(v)=='table' and type(v.analysis)=='string' then set[v.analysis:lower()]=true end
end
local function keys(r,project,section)
  local out={};local i=0
  while true do
    local ok,k=r.EnumProjExtState(project,section,i);if not ok or not k or k=='' then break end
    out[#out+1]=k;i=i+1
  end
  return out
end
local function call(job,fn,...) if job then return job:call(fn,...) end;return fn(...) end
local function check(job) if job then job:checkpoint() end end

-- opts.skip(item) -> true: этот айтем не перепаковывать (открыт в редакторе). Возвращает статистику.
function M.compact(r,project,job,opts)
  opts=opts or {}
  local st={before=0,after=0,removed=0,repacked=0,pool_removed=0}
  local refs={}
  -- 1) тейки: ссылки на анализы + перепаковка состояний старого формата
  local count=call(job,r.CountMediaItems,project)
  for i=0,count-1 do
    call(job,function()
      local item=r.GetMediaItem(project,i);if not item then return end
      local skip=opts.skip and opts.skip(item)
      for t=0,r.CountTakes(item)-1 do
        local take=r.GetTake(item,t)
        if take then
          for _,key in ipairs({Store.key,POLY_KEY}) do
            local ok,text=r.GetSetMediaItemTakeInfo_String(take,key,'',false)
            if ok and text~='' then
              if key==Store.key then ref_of(text,refs) end
              if not skip and not Pack.is_wrapped(text) then
                local good,v=pcall(Store.decode,text)
                if good and type(v)=='table' then
                  local now=Store.put_take(r,take,key,v);st.before=st.before+#text;st.after=st.after+#now;st.repacked=st.repacked+1
                end
              end
            end
          end
        end
      end
    end)
    check(job)
  end
  -- 2) копии BYPASS: перепаковка старых, ссылки на анализы внутри копий, ссылки на пул
  local SEC=Snap.SECTION;local pool_refs={};local pool_keys={}
  for _,k in ipairs(call(job,keys,r,project,SEC)) do
    local lk=k:lower()
    if lk:sub(1,2)=='b:' then pool_keys[#pool_keys+1]=k
    elseif lk:sub(1,2)=='o:' or lk:sub(1,2)=='p:' then
      call(job,function()
        local _,raw=r.GetProjExtState(project,SEC,k);if raw=='' then return end
        local ok,chunk=pcall(Snap.decode,r,project,raw);if not ok then return end
        for _,v in ipairs(M.chunk_pext(chunk,'VocalignerPitch1')) do ref_of(v,refs) end
        if not Pack.is_wrapped(raw) then
          Snap.put(r,project,k,chunk);local _,now=r.GetProjExtState(project,SEC,k)
          st.before=st.before+#raw;st.after=st.after+#now;st.repacked=st.repacked+1;raw=now
        end
        Snap.refs(raw,pool_refs)
      end)
      check(job)
    end
  end
  for _,k in ipairs(pool_keys) do
    if not pool_refs[k:sub(3):lower()] and not pool_refs[k:sub(3)] then
      call(job,function() local _,v=r.GetProjExtState(project,SEC,k);st.before=st.before+#v;r.SetProjExtState(project,SEC,k,'') end)
      st.pool_removed=st.pool_removed+1
    end
  end
  -- 3) анализы: без ссылок и не из этой сессии — удалить; старого формата — перепаковать
  local created=Store.created_set(r)
  for _,k in ipairs(call(job,keys,r,project,Store.section)) do
    local lk=k:lower()
    if not refs[lk] and not created[lk] then
      call(job,function() local _,v=r.GetProjExtState(project,Store.section,k);st.before=st.before+#v;r.SetProjExtState(project,Store.section,k,'') end)
      st.removed=st.removed+1
    else
      local _,text=call(job,r.GetProjExtState,project,Store.section,k)
      if text~='' and not Pack.is_wrapped(text) then
        local ok,v=pcall(Store.decode,text,job)
        if ok and type(v)=='table' then
          if v.waveform then local w=Wave.unpack(v.waveform,v.len,job);v.waveform_q,v.wpeak=Wave.pack_q(w,job);v.waveform=nil end
          local bytes=Codec.encode(v,job);local packed=Pack.wrap(bytes,job) -- сжатие в фоне, запись — коротким вызовом
          call(job,function()
            local now=Pack.put_proj(r,project,Store.section,k,bytes,nil,packed)
            st.before=st.before+#text;st.after=st.after+#now;st.repacked=st.repacked+1
          end)
        end
      end
    end
    check(job)
  end
  if (st.removed>0 or st.repacked>0 or st.pool_removed>0) and r.MarkProjectDirty then call(job,r.MarkProjectDirty,project) end
  return st
end
-- ===== Неслышимые правки сэмплов =====
-- REAPER при разрезании айтема копирует в каждый кусок ВСЕ правки сэмплов (SAMPLEEDITS) исходника, хотя звучит только
-- своя часть источника. Здесь точки SPL вне звучащего диапазона тейка (с запасом margin секунд) убираются.
-- Тейки со stretch-маркерами, с зацикленным источником, реверсом/секцией и с нестандартной скоростью не трогаются.
-- Возвращает новый chunk (или nil — нечего убрать) и число убранных байт.
function M.trim_chunk(chunk,ranges)
  -- ranges[k] = {a,b} в секундах источника для k-й секции тейка (nil — секцию не трогать)
  local out={};local pos=1;local depth=0;local section=1;local cur_rate;local removed=0
  local n=#chunk;local in_spls=false
  while pos<=n do
    local nl=chunk:find('\n',pos,true);local stop=nl or n
    local line=chunk:sub(pos,stop);local t=line:match('^%s*(.-)%s*$')
    local keep=true
    if in_spls then
      if t=='>' then in_spls=false;depth=depth-1
      else
        local idx=t:match('^SPL%s+(%d+)%s')
        local rg=ranges[section]
        if idx and rg and cur_rate then
          local s=tonumber(idx)/cur_rate
          if s<rg[1] or s>rg[2] then keep=false;removed=removed+#line end
        end
      end
    else
      if t:sub(1,1)=='<' then depth=depth+1;if t:match('^<SPLS%s') then in_spls=true end
      elseif t=='>' then depth=depth-1
      elseif depth==1 and (t=='TAKE' or t:match('^TAKE%s')) then section=section+1;cur_rate=nil
      elseif depth==1 then local rate=t:match('^SAMPLEEDITS%s+%S+%s+%S+%s+(%d+)$');if rate then cur_rate=tonumber(rate) end end
    end
    if keep then out[#out+1]=line end
    pos=stop+1
  end
  if removed==0 then return nil,0 end
  return table.concat(out),removed
end
-- диапазоны источника тейков айтема по API (секции chunk идут в порядке тейков)
function M.take_ranges(r,item,margin)
  local ranges={};local len=r.GetMediaItemInfo_Value(item,'D_LENGTH');local loop=r.GetMediaItemInfo_Value(item,'B_LOOPSRC')~=0
  for k=0,r.CountTakes(item)-1 do
    local take=r.GetTake(item,k)
    if take and not r.TakeIsMIDI(take) then
      local src=r.GetMediaItemTake_Source(take)
      local offs=r.GetMediaItemTakeInfo_Value(take,'D_STARTOFFS');local rate=r.GetMediaItemTakeInfo_Value(take,'D_PLAYRATE')
      local srclen=src and select(1,r.GetMediaSourceLength(src)) or 0
      local plain=src and not (r.GetMediaSourceParent and r.GetMediaSourceParent(src))
      local a,b=offs,offs+len*rate
      -- stretch-маркеры (Align): srcpos — абсолютное время источника; берём охват с запасом по всем маркерам
      for m=0,r.GetTakeNumStretchMarkers(take)-1 do
        local _,_,sp=r.GetTakeStretchMarker(take,m);if sp then a=math.min(a,sp);b=math.max(b,sp) end
      end
      if plain and rate>0 and srclen>0 and not (loop and (b>srclen+1e-6 or a<-1e-6)) then ranges[k+1]={a-margin,b+margin} end
    end
  end
  return ranges
end
-- Убрать неслышимые точки во всех айтемах проекта (одно действие Undo). opts.skip(item) — не трогать.
function M.trim_sample_edits(r,project,job,opts)
  opts=opts or {};local margin=opts.margin or 1;local st={items=0,bytes=0}
  local count=call(job,r.CountMediaItems,project);local todo={}
  for i=0,count-1 do
    call(job,function()
      local item=r.GetMediaItem(project,i);if not item or (opts.skip and opts.skip(item)) then return end
      local ok,chunk=r.GetItemStateChunk(item,'',false)
      if ok and chunk:find('<SPLS',1,true) then
        local new,removed=M.trim_chunk(chunk,M.take_ranges(r,item,margin))
        if new then todo[#todo+1]={item=item,old=chunk,new=new,removed=removed} end
      end
    end)
    check(job)
  end
  if #todo==0 then return st end
  call(job,function()
    r.Undo_BeginBlock2(project);r.PreventUIRefresh(1)
    for _,x in ipairs(todo) do
      local ok,now=r.GetItemStateChunk(x.item,'',false)
      if ok and now==x.old and r.SetItemStateChunk(x.item,x.new,false) then st.items=st.items+1;st.bytes=st.bytes+x.removed end
    end
    r.PreventUIRefresh(-1);r.Undo_EndBlock2(project,'Vocaligner: remove inaudible sample edits',-1);r.UpdateArrange()
  end)
  return st
end
-- уже уплотняли этот проект в этой сессии REAPER?
local SECTION='Vocaligner compact'
function M.key(r,project)
  local _,path=r.EnumProjects(-1,'');return tostring(project)..'|'..tostring(path)
end
-- Проект открыли заново (в той же сессии REAPER) — счётчик изменений проекта у REAPER начинается сначала:
-- если он стал меньше запомненного, уплотняем ещё раз. Счётчик запоминается не чаще раза в 2 с.
local seen_at=0
function M.done(r,project)
  local key=M.key(r,project);local count=r.GetProjectStateChangeCount and r.GetProjectStateChangeCount(project) or 0
  local last=tonumber(r.GetExtState(SECTION,key..'#count'))
  if last and count<last then r.SetExtState(SECTION,key,'',false);r.SetExtState(SECTION,key..'#count',tostring(count),false);return false end
  local now=r.time_precise and r.time_precise() or 0
  if now-seen_at>2 then seen_at=now;r.SetExtState(SECTION,key..'#count',tostring(count),false) end
  return r.GetExtState(SECTION,key)=='1'
end
function M.mark(r,project) r.SetExtState(SECTION,M.key(r,project),'1',false) end
function M.report(st)
  local mb=function(x) return x/1048576 end
  return string.format('Project data compacted: %d unused analyses removed, %d values repacked (%.1f → %.1f MB)%s. Save the project to keep it smaller.',
    st.removed,st.repacked,mb(st.before),mb(st.after),st.pool_removed>0 and string.format(', %d unused bypass blocks removed',st.pool_removed) or '')
end
return M
