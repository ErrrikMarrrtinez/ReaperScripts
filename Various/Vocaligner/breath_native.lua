-- @noindex
-- Breaths в C++ (reaper_vocaligner_native.dll): признаки, деревья, адаптация к примерам, события и кривая снижения —
-- те же формулы и тот же порядок вычислений, что в breath_features / breath_engine / breath_profile / breath_regions /
-- breath.lua (сверка бит в бит: native/test_breath.py). Главный поток только отдаёт кадры порциями (t, rms, zcr, flat,
-- tonal, 16 полос) и забирает результаты; признаки и модель считает пул потоков DLL по кускам параллельно.
-- Нет DLL / старая DLL / другая модель / провал самотеста — прежний Lua-путь (причина в M.reason).
local import=...;local Model=import('breath_model');local M={}
local section='Vocaligner Breath native 1'
local API={'VN_BreathVersion','VN_BreathModel','VN_BreathSelfTest','VN_BreathCreate','VN_BreathAppend','VN_BreathSeal','VN_BreathPoll',
  'VN_BreathInfo','VN_BreathError','VN_BreathRelease','VN_BreathClassify','VN_BreathDetect','VN_BreathCurve','VN_BreathRead'}
M.FRAME=21          -- значений во входной строке кадра
M.BLOCK=256         -- кадров за один вызов Append: 256*21 значений — шаг главного потока 1–2 мс и небольшой всплеск выделений памяти
M.READ=16384        -- строк за один вызов Read
M.PENDING_LIMIT=256*1024*1024 -- вход в очереди DLL: отдача кадров ждёт, пока пул не разгребёт
local checked=setmetatable({},{__mode='k'})
function M.available(r)
  if not r then return false,'No REAPER API' end
  local c=checked[r];if c then return c[1],c[2] end
  for _,name in ipairs(API)do
    if type(r[name])~='function' then c={false,'C++ Breaths are not in the installed extension. Install the new reaper_vocaligner_native.dll and restart REAPER.'};checked[r]=c;return false,c[2] end
  end
  local ok,version=pcall(r.VN_BreathVersion)
  if not ok or version~=1 then c={false,'C++ Breaths ABI mismatch.'}
  elseif r.VN_BreathModel()~=Model.version then c={false,'C++ Breaths model differs from breath_model.lua; using Lua.'}
  elseif r.VN_BreathSelfTest()~=1 then c={false,'C++ Breaths self-test failed; using Lua.'}
  else c={true} end
  checked[r]=c;return c[1],c[2]
end
function M.preference(r)return r.GetExtState and r.GetExtState(section,'backend')=='lua' and 'lua' or 'cpp' end
function M.select(r,value)if r.SetExtState then r.SetExtState(section,'backend',value=='lua' and 'lua' or 'cpp',true) end end
-- C++ путь для этого запуска: не выключен в ExtState и DLL прошла проверку
function M.active(r)return r~=nil and M.preference(r)=='cpp' and (M.available(r)) or false end
-- REAPER API: из EEL-движка дыханий (engine.r) или глобальный reaper
function M.host(engine)return engine and engine.r or rawget(_G,'reaper') end

-- Владение дескриптором DLL: явный release или сборщик мусора (кеш живёт на data, дольше задачи)
local Handle={};Handle.__index=Handle
Handle.__gc=function(h)if not h.released then h.released=true;pcall(h.r.VN_BreathRelease,h.id)end end
function Handle:release()if not self.released then self.released=true;self.r.VN_BreathRelease(self.id)end end
local function own(r,id)return setmetatable({r=r,id=id},Handle)end
local function live(h)return h and not h.released end

-- Вызовы DLL идут через job:call (главный цикл), как у Align/Poly; без задачи — напрямую
local function call(job,fn,...)if job and job.call then return job:call(fn,...) end return fn(...) end
-- Отдать кадр, пока пул потоков DLL работает (пакетная обработка вешает на задачу job.wait: читать аудио следующего айтема)
local function idle(job)
  if job and job.wait then job:wait() elseif coroutine.isyieldable() then coroutine.yield() end
end
local function wait(r,job,h,label)
  while true do
    local st=call(job,r.VN_BreathPoll,h.id)
    if st==1 then return end
    if st~=0 then error(st==-2 and 'Native breath handle was released' or tostring(call(job,r.VN_BreathError,h.id)),0) end
    if job and job.checkpoint then job:checkpoint(nil,label) end
    idle(job)
  end
end
local function create(r,job,fn,...)
  local args=table.pack(...)
  return call(job,function()
    local id=fn(table.unpack(args,1,args.n));if not id or id<=0 then error(tostring(r.VN_BreathError(0)),0) end
    return own(r,id)
  end)
end
local function info(r,h,job)
  return call(job,function()local a=r.new_array(16);local n=r.VN_BreathInfo(h.id,a);return a.table(1,math.max(1,n))end)
end
-- Все строки result (what) в плоскую таблицу: count строк по width значений
local function read_all(r,h,what,count,width,job)
  local out={}
  for first=0,count-1,M.READ do
    local n=math.min(M.READ,count-first)
    local got,values=call(job,function()
      local buf=r.new_array(n*width);local got=r.VN_BreathRead(h.id,what,first,buf)
      return got,got>0 and buf.table(1,got*width) or {}
    end)
    if got~=n then error('Native breath result is incomplete',0) end
    table.move(values,1,n*width,#out+1,out)
    if job and job.checkpoint then job:checkpoint() end
  end
  return out
end
-- Ошибка DLL (не отмена) — запомнить причину и вернуть false: вызывающий идёт по Lua-пути
function M.try(fn,...)
  local result=table.pack(pcall(fn,...))
  if result[1] then return table.unpack(result,1,result.n) end
  if result[2]=='Cancelled' then error('Cancelled',0) end
  M.reason=tostring(result[2]);return false
end

-- Очередь DLL переполнена: отдать шаг главному циклу (вне корутины — просто ждать следующую проверку)
local function wait_step(job)
  if job.checkpoint then job:checkpoint(nil,'Breaths: C++ workers busy') end
  idle(job)
end
-- Освободить дескрипторы Breaths данных кадров (кеш признаков и последняя классификация)
function M.release(data)
  if not data then return end
  local cache=data.breath_native;if cache and cache.handle then cache.handle:release() end
  local adapted=data.breath_adapted;if adapted and adapted.native then adapted.native:release() end
  data.breath_native,data.breath_adapted,data.breath_events=nil,nil,nil
end
-- Признаки и оценки модели для кадров data (кеш data.breath_native — только для этой таблицы кадров)
function M.analysis(r,data,job)
  local cache=data.breath_native
  if cache and cache.frames==data.frames and cache.count==#data.frames and cache.version==Model.version and live(cache.handle) then return cache end
  local frames=data.frames;local n=#frames;local started=r.time_precise and r.time_precise()
  local store=data.frame_store -- кадры в колонках (cleanup_frames.lua): строки берутся страницами, без таблиц кадров
  if n<1 then error('No frames to analyze',0) end
  local top=math.max(1e-9,data.level_top or .1)
  local h=create(r,job,r.VN_BreathCreate,r.new_array({0,n,data.hop,data.len or 0,top,0,0}))
  if job and job.resources then job.resources[h]=Handle.release end
  for first=1,n,M.BLOCK do
    local last=math.min(n,first+M.BLOCK-1);local flat={};local k=0
    if store then flat=store:breath_rows(first,last)
    else
    for i=first,last do
      local f=frames[i];local b=f.noise_bands or {}
      flat[k+1]=f.t;flat[k+2]=f.rms or 0;flat[k+3]=f.zcr or 0;flat[k+4]=f.breath_flat or f.flat or 0;flat[k+5]=f.breath_tonal or 0
      for j=1,16 do flat[k+5+j]=b[j] or 0 end
      k=k+M.FRAME
    end
    end
    while job and info(r,h,job)[11]>M.PENDING_LIMIT do wait_step(job) end
    call(job,function()
      if r.VN_BreathAppend(h.id,r.new_array(flat),last-first+1)==0 then error(tostring(r.VN_BreathError(0)),0) end
    end)
    if job and job.checkpoint then job:checkpoint(nil,'Breaths: frames') end
  end
  call(job,function()if r.VN_BreathSeal(h.id)~=1 then error(tostring(r.VN_BreathError(0)),0) end end)
  wait(r,job,h,'Breaths: C++ features')
  if job and job.resources then job.resources[h]=nil end
  local v=info(r,h,job)
  cache={handle=h,frames=frames,count=n,version=Model.version}
  data.breath_native=cache
  -- для диагностики (Copy report); версия с префиксом не даёт Lua-пути принять этот кеш за свои оценки
  data.breath_model_scores={version='native '..Model.version,elapsed_ms=started and (r.time_precise()-started)*1000 or nil,kernel_ms=v[9],backend='C++'}
  return cache
end
-- breath.lua classify: оценки после адаптации к примерам и запрет (veto) — таблицы Lua длиной #frames
function M.classify(r,data,profile,job)
  local base=M.analysis(r,data,job);local n=base.count
  local v={0};local count=0
  for _,e in ipairs(profile and profile.examples or {})do
    count=count+1;v[#v+1]=e.kind
    for k=1,19 do v[#v+1]=e.mean[k] end
    for k=1,19 do v[#v+1]=e.variance[k] end
  end
  v[1]=count
  local h=create(r,job,r.VN_BreathClassify,base.handle.id,r.new_array(v))
  if job and job.resources then job.resources[h]=Handle.release end
  wait(r,job,h,'Breaths: C++ classification')
  local scores=read_all(r,h,5,n,1,job);local flags=read_all(r,h,6,n,1,job);local veto={}
  for i=1,n do veto[i]=flags[i]~=0;if job and i%8192==0 and job.checkpoint then job:checkpoint() end end
  if job and job.resources then job.resources[h]=nil end
  return scores,veto,h
end
-- breath.lua detect (гистерезис + breath_regions.refine): события в форме Regions.refine
function M.detect(r,data,adapted,cfg,threshold,job)
  local h=create(r,job,r.VN_BreathDetect,adapted.native.id,r.new_array({threshold,cfg.breath_min_ms or 80,cfg.breath_join_ms or 160,cfg.breath_edge_ms or 120}))
  local count=info(r,h,job)[3]
  local rows=read_all(r,h,8,count,10,job);call(job,function()h:release()end)
  local events={}
  for j=0,count-1 do
    local b=j*10;local parts=math.tointeger(rows[b+5])
    events[j+1]={first=math.tointeger(rows[b+1]),last=math.tointeger(rows[b+2]),score=rows[b+3],core_frames=math.tointeger(rows[b+4]),
      parts=parts and parts>0 and parts or nil,core_start=rows[b+6],core_finish=rows[b+7],start=rows[b+8],finish=rows[b+9],level_db=rows[b+10],kind='breath'}
  end
  return events
end
-- breath.lua build: снижение по кадрам (breath_db) и точки огибающей / фигуры Безье для уже собранных событий
local nan=0/0
function M.curve(r,data,cfg,templates,events,bezier,tension_in,tension_out,job)
  local base=M.analysis(r,data,job)
  local v={cfg.breath_pre_ms or 10,cfg.breath_release_ms or 20,cfg.breath_curve or 50,tension_in,tension_out,bezier and 1 or 0,#events}
  for j,out in ipairs(events)do
    local e=templates[j]
    v[#v+1]=e.first;v[#v+1]=e.last;v[#v+1]=e.start;v[#v+1]=e.finish;v[#v+1]=out.excluded and 1 or 0;v[#v+1]=out.reduction
    v[#v+1]=out.a or nan;v[#v+1]=out.b or nan;v[#v+1]=out.fin or nan;v[#v+1]=out.fout or nan
  end
  local h=create(r,job,r.VN_BreathCurve,base.handle.id,r.new_array(v))
  local i=info(r,h,job);local npoints,nshapes,peak=i[3],i[4],i[5]
  local values=read_all(r,h,9,base.count,1,job);local flat=read_all(r,h,10,npoints,2,job)
  local sflat=nshapes>0 and read_all(r,h,11,nshapes,3,job) or {}
  call(job,function()h:release()end)
  local points={};for k=0,npoints-1 do points[k+1]={t=flat[2*k+1],db=flat[2*k+2]} end
  local shapes={};for k=0,nshapes-1 do shapes[k+1]={a=sflat[3*k+1],b=sflat[3*k+2],tension=sflat[3*k+3]} end
  return values,points,peak,shapes
end
-- Признаки 1..19 кадров a..b (1-based) для breath_profile.learn: rows[i][k]
function M.rows(r,data,a,b,job)
  local base=M.analysis(r,data,job);local rows={}
  if b<a then return rows end
  local flat=call(job,function()
    local buf=r.new_array((b-a+1)*22);local got=r.VN_BreathRead(base.handle.id,1,a-1,buf)
    if got~=b-a+1 then error('Native breath rows are not ready',0) end
    return buf.table(1,got*22)
  end)
  for i=a,b do local row={};local o=(i-a)*22+2;for k=1,20 do row[k]=flat[o+k] end;rows[i]=row end
  return rows
end
return M
