-- @noindex
-- Dynamics в C++ (reaper_vocaligner_native.dll, VN_Dyn*): детектор компрессора/гейта, передаточная кривая, гейт,
-- захват волны, спектр Cleanup и ядра De-ess — те же формулы и тот же порядок вычислений, что в compressor/engine.lua,
-- compressor/chain.lua, cleanup_dsp.lua и cleanup.lua (сверка: native/test_dynamics.py, native/test_dynamics_lua.py).
-- Главный поток только читает PCM теми же блоками, что Lua-кэш, и копирует его в DLL; пул потоков считает по мере
-- поступления, результат забирается опросом без блокировки интерфейса. PCM айтема держит DLL (до KEEP_LIMIT на все
-- айтемы), поэтому смена Attack/RMS/фильтров не перечитывает звук; длиннее — потоковое перечитывание без хранения.
-- Уровни детектора остаются в DLL: короткие возвращаются таблицами {t,db}, длинные — прокси (#, [i], ipairs, pairs).
-- Нет API / старая DLL / провал самопроверки / ExtState backend=lua — прежний путь EEL/Lua.
-- Лицензия: детектор и передаточная кривая — производная работа (GPL-3.0), см. compressor/NOTICE.md.
local import=...;local Frames=import('cleanup_frames');local M={}
M.section='Vocaligner Dynamics native 1'
M.KEEP_LIMIT=1536*1024*1024  -- PCM айтемов, который держит DLL (вместо 384 МБ Lua-кэша)
M.PENDING_LIMIT=256*1024*1024 -- потоковый PCM в очереди DLL: чтение ждёт пул (backpressure)
M.PLAIN_LEVELS=65536 -- больше точек детектора — прокси вместо Lua-таблиц (65536 таблиц {t,db} — ещё ≈4 МБ кучи)
M.PAGE=8192 -- строк за шаг: перевод в Lua-таблицы не держит кадр интерфейса
M.BULK=16384 -- значений за один вызов моста таблица <-> массив: 360 тысяч одним вызовом — ≈9 мс в шаге интерфейса
local API={'VN_DynVersion','VN_DynSelfTest','VN_DynSource','VN_DynAppend','VN_DynSeal','VN_DynRun','VN_DynCurve','VN_DynPoll',
  'VN_DynInfo','VN_DynRows','VN_DynError','VN_DynRelease','VN_DynStats','VN_DynSpectrum','VN_DynDeessFeatures','VN_DynDeessScore','VN_DynSoften'}
local checked=setmetatable({},{__mode='k'})
function M.available(r)
  if type(r)~='table' then return false,'REAPER API is unavailable.' end
  local c=checked[r];if c then return c[1],c[2] end
  for _,name in ipairs(API)do
    if type(r[name])~='function' then c={false,'C++ dynamics are not in the installed extension; using EEL/Lua.'};checked[r]=c;return false,c[2] end
  end
  local ok,version=pcall(r.VN_DynVersion)
  if not ok or version~=1 then c={false,'C++ dynamics ABI mismatch; using EEL/Lua.'}
  elseif r.VN_DynSelfTest()~=1 then c={false,'C++ dynamics self-test failed; using EEL/Lua.'}
  else c={true} end
  checked[r]=c;return c[1],c[2]
end
-- C++ по умолчанию; ExtState backend=lua — принудительно прежний путь (для сравнения и отката)
function M.active(r)
  r=r or reaper
  if type(r)~='table' then return false end
  if r.GetExtState and r.GetExtState(M.section,'backend')=='lua' then return false end
  return (M.available(r))
end
function M.select(r,value)r.SetExtState(M.section,'backend',value=='lua' and 'lua' or 'cpp',true);checked[r]=nil end

-- Владение дескриптором DLL: явный release, ресурсы задачи или сборщик мусора (кэш фолловера живёт дольше задачи)
local Handle={};Handle.__index=Handle
Handle.__gc=function(h)if not h.released then h.released=true;pcall(h.r.VN_DynRelease,h.id)end end
function Handle:release()if not self.released then self.released=true;self.r.VN_DynRelease(self.id)end end
local function own(r,id,what)
  if not id or id<=0 then error(tostring(r.VN_DynError(0)~='' and r.VN_DynError(0) or what),0) end
  return setmetatable({r=r,id=id},Handle)
end
M.own=own
local function stats(r)local a=r.new_array(4);r.VN_DynStats(a);local v=a.table();return {kept=v[1],pending=v[2],workers=v[3],queued=v[4]}end
M.stats=stats
local function info(r,h)local a=r.new_array(8);if r.VN_DynInfo(h.id,a)~=8 then return nil end;return a.table()end
M.info=info
-- Отдать кадр, пока пул потоков DLL работает. Пакетная обработка (cleaner_batch.lua) вешает на задачу job.wait: в это время
-- главный поток читает аудио следующего айтема, а не простаивает.
local function idle(job) if job.wait then job:wait() else coroutine.yield() end end
M.idle=idle
-- Ждать готовности дескриптора, отдавая кадры интерфейсу (опрос раз в цикл defer)
local function wait(r,h,job,label)
  while true do
    local st=r.VN_DynPoll(h.id)
    if st==1 then return end
    if st~=0 then error(st==-1 and tostring(r.VN_DynError(h.id)) or 'Native dynamics handle was lost.',0) end
    job:checkpoint(nil,label);idle(job)
  end
end
M.wait=wait

-- ---- чтение айтема в источник DLL: тот же accessor, те же блоки и проверки, что в compressor/audio.lua M.ensure
local function identity(s) return table.concat({s.guid,s.render_key,s.offset,s.len},'|') end
local resident={} -- {owner=d,cache=cache} удерживаемые DLL источники, старые выгружаются первыми
local function evict(r,need)
  while #resident>0 and stats(r).kept+need>M.KEEP_LIMIT do
    local old=table.remove(resident,1)
    if old.owner.pcm==old.cache then old.owner.pcm=nil end
    if old.cache.source then old.cache.source:release();old.cache.source=nil end
  end
end
local function forget(d)
  for i=#resident,1,-1 do if resident[i].owner==d then
    local cache=resident[i].cache;table.remove(resident,i)
    if cache.source then cache.source:release();cache.source=nil end
  end end
end
-- Айтем выброшен из кэша (закрыт проект, замена захвата, выход): PCM и прогоны детектора освобождаются сразу, а не когда
-- сборщик мусора дойдёт до дескрипторов (список resident иначе держал бы PCM до вытеснения следующими чтениями)
function M.release_item(d)
  forget(d)
  local pcm=d.pcm;d.pcm=nil
  if pcm and pcm.source then pcm.source:release();pcm.source=nil end
  for _,name in ipairs({'compressor_follower','gate_follower'}) do
    local f=d[name];if f and f.run then f.run:release() end;d[name]=nil
  end
end
-- attach(source,geometry) — создать прогоны до первого Append (потоковый источник PCM не хранит)
function M.read(c,d,job,keep,attach,label)
  local r=c.r;local Audio=import('audio')
  local s=job:call(Audio.capture,r,c.project,d.snapshot.item,'cleanup')
  local aa=job:call(r.CreateTakeAudioAccessor,s.take);assert(aa,'Cannot open dynamics audio accessor')
  job.resources[aa]=r.DestroyAudioAccessor
  local start=job:call(r.GetAudioAccessorStartTime,aa);local finish=job:call(r.GetAudioAccessorEndTime,aa)
  assert(math.abs(start)<1e-4,'Unexpected dynamics accessor time origin')
  local scale=1
  if math.abs(s.rate-1)>1e-6 and math.abs(finish-s.len*s.rate)<1e-4 and math.abs(finish-s.len)>1e-4 then scale=s.rate end
  local desired=math.max(48000,math.min(192000,s.source_rate or 48000));local read_sr=math.floor(desired/scale+.5)
  assert(read_sr>=1000 and read_sr<=192000,'Unsupported dynamics accessor/play rate')
  local sr=read_sr*scale;assert(sr<=192000,'Dynamics rate exceeds 192 kHz')
  local total=math.ceil(s.len*sr);local chunk=math.floor(32768/s.channels)
  local bytes=total*s.channels*8
  if keep then if bytes<=M.KEEP_LIMIT then job:call(evict,r,bytes) else keep=false end end
  local g={sr=sr,channels=s.channels,total=total,chunk=chunk,len=s.len,key=identity(s),snapshot=s}
  local source=job:call(function()
    return own(r,r.VN_DynSource(r.new_array({sr,s.channels,total,keep and 1 or 0,M.KEEP_LIMIT})),'Cannot create the dynamics source')
  end)
  job.resources[source]=Handle.release
  local runs=attach and attach(source,g) or {}
  local kept=job:call(info,r,source)[5]==1
  local buffer=job:call(r.new_array,chunk*s.channels)
  local nil_reads,nonzero,blocks=0,false,0
  for first=0,total-1,chunk do
    local n=math.min(chunk,total-first)
    if not kept then while job:call(stats,r).pending>M.PENDING_LIMIT do job:checkpoint(nil,label);idle(job) end end
    local status,appended=job:call(function()
      Audio.validate_accessor(r,s,aa)
      buffer.clear()
      local status=r.GetAudioAccessorSamples(aa,read_sr,s.channels,first/sr*scale,n,buffer)
      if status==0 then buffer.clear() end
      assert(status==nil or type(status)=='number' and status>=0,'Dynamics audio read failed')
      return status,r.VN_DynAppend(source.id,buffer,n)
    end)
    if appended==0 then error(tostring(job:call(r.VN_DynError,0)),0) end
    nonzero=nonzero or appended==2;blocks=blocks+1
    if status==nil then nil_reads=nil_reads+1 end
    job:checkpoint((first+n)/total,label)
  end
  job:call(r.DestroyAudioAccessor,aa);job.resources[aa]=nil
  local ok,why=job:call(Audio.unchanged,r,s);assert(ok,why)
  assert(nil_reads~=blocks or nonzero,'Accessor returned nil and no dynamics audio was received')
  job:call(function()if r.VN_DynSeal(source.id)~=1 then error(tostring(r.VN_DynError(0)),0) end end)
  g.kept=kept;g.bytes=kept and bytes or 0
  return source,g,runs
end

-- ---- настройки детектора: те же выражения, что в engine.lua M:run (vars)
local function run_settings(cfg,mode,sr,channels,step)
  local p=mode..'_'
  return {cfg.capture_wave and 2 or mode=='gate' and 1 or 0,
    math.max(1,math.floor(sr*(cfg[p..'rms_ms'] or 5)/1000+.5)),
    cfg[p..'threshold'],cfg.compressor_ratio,cfg.compressor_knee,cfg.compressor_gain,
    cfg[p..'attack_ms']/1000,cfg[p..'release_ms']/1000,
    cfg.gate_range,cfg.gate_hysteresis,math.floor(sr*cfg.gate_hold_ms/1000),
    cfg[p..'hp'],cfg[p..'lp'],math.max(1,math.floor(sr*cfg[p..'interval_ms']/1000+.5)),
    cfg.input_gain or 1,step,math.floor(32768/channels)}
end
local function create_run(r,source,settings,upstream,job)
  local values={};for i,v in ipairs(settings)do values[i]=v end
  local points=upstream and upstream.points or {}
  values[#values+1]=#points
  for i,p in ipairs(points)do values[#values+1]=p.t;values[#values+1]=p.db;if i%4096==0 then job:checkpoint() end end
  return job:call(function()return own(r,r.VN_DynRun(source.id,r.new_array(values)),'Cannot start the dynamics detector')end)
end
local function rows_count(r,h)local v=info(r,h);return v and math.floor(v[5]) or 0 end

-- Захват волны и PCM айтема (замена compressor/audio.lua M.ensure): кадры 10 мс {t,rms,min,max} как в EEL mode 2
function M.ensure(c,d,job)
  local r=c.r;local Audio=import('audio')
  local s=job:call(Audio.capture,r,c.project,d.snapshot.item,'cleanup')
  if d.pcm and d.pcm.native and d.pcm.key==identity(s) then return d.pcm end
  local wave
  local source,g=M.read(c,d,job,true,function(src,g)
    local cfg={capture_wave=true,compressor_rms_ms=0,compressor_threshold=6,compressor_attack_ms=0,compressor_release_ms=0,
      compressor_hp=0,compressor_lp=20000,compressor_interval_ms=10,compressor_ratio=1,compressor_knee=0,compressor_gain=0,
      gate_range=60,gate_hysteresis=6,gate_hold_ms=80}
    wave=create_run(r,src,run_settings(cfg,'compressor',g.sr,g.channels,g.chunk+1),nil,job)
    job.resources[wave]=Handle.release;return {wave}
  end,'Caching dynamics · '..s.name)
  wait(r,wave,job,'Caching dynamics · '..s.name)
  local n=rows_count(r,wave);local frames={};local buf=job:call(r.new_array,M.PAGE*4)
  -- длинный айтем: кадры волны в колонках (cleanup_frames.lua) — без 360 тысяч таблиц с четырьмя пустыми подтаблицами
  local store=n>=(c.cfg and c.cfg.store_min_frames or 30000) and Frames.new(r,'wave',n) or nil
  for first=0,n-1,M.PAGE do
    local got=job:call(r.VN_DynRows,wave.id,first,buf)
    if store then job:call(store.put_wave,store,buf,got,first)
    else
      local v=job:call(buf.table,1,got*4)
      for j=1,got*4,4 do frames[#frames+1]={t=v[j],rms=v[j+3],min=v[j+1],max=v[j+2],cep={},spec={},chroma={},noise_bands={},flux=0} end
    end
    job:checkpoint()
  end
  if store then frames=store.frames end
  wave:release();job.resources[wave]=nil;job.resources[source]=nil
  forget(d)
  local cache={key=g.key,native=true,kept=g.kept,source=g.kept and source or nil,blocks={},channels=g.channels,len=g.len,sr=g.sr,
    total=g.total,chunk=g.chunk,bytes=g.bytes,frames=frames,frame_store=store}
  if g.kept then resident[#resident+1]={owner=d,cache=cache} else source:release() end
  d.pcm=cache;return cache
end

-- Прогон детектора (замена цикла engine.run в chain.lua M.dynamic). Возвращает дескриптор с уровнями.
function M.follow(c,d,pcm,cfg,mode,upstream,job,label)
  local r=c.r
  local step=math.max(1,math.floor(pcm.sr*.0005))
  local settings=run_settings(cfg,mode,pcm.sr,pcm.channels,step)
  local run
  if pcm.kept and pcm.source and not pcm.source.released then
    run=create_run(r,pcm.source,settings,upstream,job)
  else
    -- PCM не удержан (слишком длинный айтем или выгружен): потоковое перечитывание с прогоном, созданным до чтения
    local source=M.read(c,d,job,false,function(src)run=create_run(r,src,settings,upstream,job);job.resources[run]=Handle.release;return {run} end,label)
    job.resources[source]=nil;source:release()
  end
  job.resources[run]=Handle.release
  wait(r,run,job,label)
  job.resources[run]=nil
  return run,rows_count(r,run)
end
-- Уровни детектора {t,db}: таблицы, а для длинных айтемов — прокси с постраничным чтением из DLL
function M.levels(r,run,count,job)
  if count<=M.PLAIN_LEVELS then
    local out={};local buf=r.new_array(M.PAGE*2)
    for first=0,count-1,M.PAGE do
      local got=r.VN_DynRows(run.id,first,buf);local v=buf.table(1,got*2)
      for j=1,got*2,2 do out[#out+1]={t=v[j],db=v[j+1]} end
      if job then job:checkpoint() end
    end
    return out
  end
  local page,pages,cached=4096,{},0
  local function row(i)
    local p=(i-1)//page;local flat=pages[p]
    if not flat then
      if cached>=64 then pages={};cached=0 end
      local buf=r.new_array(page*2);local got=r.VN_DynRows(run.id,p*page,buf);flat=buf.table(1,got*2);pages[p]=flat;cached=cached+1
    end
    local k=(i-1-p*page)*2;return {t=flat[k+1],db=flat[k+2]}
  end
  return setmetatable({},{__len=function()return count end,
    __index=function(_,i)i=math.tointeger(i);if i and i>=1 and i<=count then return row(i) end end,
    __pairs=function(t)return function(_,i)i=(i or 0)+1;if i<=count then return i,row(i) end end,t,nil end,
    __native=run})
end
-- Кривая стадии из уровней: компрессор — передаточная кривая (M:transfer), гейт — M:gate; затем Pre-comp/Pre-open,
-- конечная точка и прореживание нулей (chain.lua). Возвращает точки и max |db|.
function M.curve(r,run,mode,cfg,len,job)
  local pre=cfg[mode..'_pre_ms']/1000
  local values={mode=='gate' and 1 or 0,cfg.compressor_threshold or 0,cfg.compressor_ratio or 1,cfg.compressor_knee or 0,cfg.compressor_gain or 0,
    cfg.gate_threshold or 0,cfg.gate_hysteresis or 0,cfg.gate_range or 0,cfg.gate_attack_ms or 0,cfg.gate_hold_ms or 0,cfg.gate_release_ms or 0,
    cfg.gate_interval_ms or 5,pre,len}
  local h=job:call(function()return own(r,r.VN_DynCurve(run.id,r.new_array(values)),'Cannot build the dynamics curve')end)
  job.resources[h]=Handle.release
  wait(r,h,job)
  local v=job:call(info,r,h);local n,max_db=math.floor(v[3]),v[4]
  local points={};local buf=job:call(r.new_array,M.PAGE*2)
  for first=0,n-1,M.PAGE do
    local got=job:call(r.VN_DynRows,h.id,first,buf);local x=job:call(buf.table,1,got*2)
    for j=1,got*2,2 do points[#points+1]={t=x[j],db=x[j+1]} end
    job:checkpoint()
  end
  job.resources[h]=nil;h:release()
  return points,max_db
end

-- ---- Мост «таблица Lua <-> массив reaper_array» страницами по M.BULK значений: один вызов на 360 тысяч значений
-- (часовой айтем) держал бы шаг интерфейса ≈10 мс только на копирование
local function to_array(r,values,n,job)
  local a=r.new_array(n)
  for first=1,n,M.BULK do
    a.copy(values,first,math.min(M.BULK,n-first+1),first)
    if job then job:checkpoint() end
  end
  return a
end
local function from_array(a,first,n,job,into)
  local out=into or {}
  for at=0,n-1,M.BULK do
    local count=math.min(M.BULK,n-at)
    table.move(a.table(first+at,count),1,count,at+1,out)
    if job then job:checkpoint() end
  end
  return out
end
M.to_array,M.from_array=to_array,from_array

-- ---- De-ess (cleanup.lua): синхронные ядра по массивам, каждое — миллисекунды даже на часовом айтеме
-- Мощность ВЧ, db и shape по кадрам; полосы кэшируются в data.detector_blocks в формате EEL (eel.lua M:power).
-- Кадры в колонках (cleanup_frames.lua) отдают страницы полос и пар (rms, noise_flat) без копий и таблиц кадров.
function M.deess_features(r,data,cutoff,job)
  local frames=data.frames;local store=data.frame_store;local db,shape={},{}
  local n=store and store.n or #frames
  local blocks=data.detector_blocks or {};data.detector_blocks=blocks
  local aux=data.detector_aux or {};data.detector_aux=aux
  for first=1,n,1024 do
    local count=math.min(1024,n-first+1)
    local function run()
      local buffer,a
      if store then buffer,a=store:deess_block(first)
      else
        buffer=blocks[first]
        if not buffer then
          local values={}
          for i=first,first+count-1 do local bands=frames[i].noise_bands or {};for b=1,32 do values[#values+1]=bands[b] or 0 end end
          buffer=r.new_array(values);blocks[first]=buffer
        end
        a=aux[first]
        if not a then
          local values={}
          for i=first,first+count-1 do local f=frames[i];values[#values+1]=f.rms or 0;values[#values+1]=f.noise_flat or f.flat or 0 end
          a=r.new_array(values);aux[first]=a
        end
      end
      local out=r.new_array(count*2)
      if r.VN_DynDeessFeatures(buffer,a,r.new_array({count,cutoff}),out)~=1 then error(tostring(r.VN_DynError(0)),0) end
      return out.table(1,count),out.table(count+1,count)
    end
    local d,s;if job then d,s=job:call(run) else d,s=run() end
    table.move(d,1,count,first,db);table.move(s,1,count,first,shape)
    if job then job:checkpoint() end
  end
  return db,shape
end
function M.deess_score(r,db,shape,n,k,cfg,job)
  if n==0 then return {},{} end
  local d,s=to_array(r,db,n,job),to_array(r,shape,n,job)
  local out=r.new_array(n*2)
  if r.VN_DynDeessScore(d,s,r.new_array({n,k,cfg.deess_threshold,cfg.deess_amount,cfg.deess_max_db}),out)~=1 then
    error(tostring(r.VN_DynError(0)),0)
  end
  return from_array(out,1,n,job),from_array(out,n+1,n,job)
end
function M.soften(r,values,hop,pre,release,job)
  local n=#values;if n==0 then return values end
  local a=to_array(r,values,n,job)
  if r.VN_DynSoften(a,r.new_array({n,hop,pre,release}))~=1 then error(tostring(r.VN_DynError(0)),0) end
  return from_array(a,1,n,job)
end
return M
