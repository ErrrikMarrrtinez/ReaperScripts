-- @noindex
-- Classic Align в C++ (reaper_vocaligner_native.dll): признаки кадров и coarse/fine DTW — те же формулы и тот же
-- порядок вычислений, что в dsp.lua / dtw.lua (сверка: native/test_align.py). Главный поток только читает PCM
-- порциями и отдаёт копию в DLL; пул потоков считает признаки по мере поступления, сопоставление дубля стартует,
-- как только готовы он и референс. Референс читается один раз и делится всеми дублями пачки. В Lua возвращаются
-- путь и лёгкие кадры (t, energy, onset, active, rms, flux, zcr, min, max) — полные признаки живут в DLL.
local import=...;local Audio=import('audio');local Warp=import('warp');local M={}
local section='Vocaligner Align native 1'
local API={'VN_AlignVersion','VN_AlignSelfTest','VN_AlignWorkers','VN_AlignCreate','VN_AlignAppend','VN_AlignSeal','VN_AlignPoll',
  'VN_AlignInfo','VN_AlignFrames','VN_AlignMatch','VN_AlignMatchInfo','VN_AlignMatchPath','VN_AlignError','VN_AlignRelease','VN_AlignCompact','VN_AlignStats',
  'VN_AlignPlan','VN_AlignPlanInfo','VN_AlignPlanMarkers'}
M.LITE=9
M.PENDING_LIMIT=384*1024*1024 -- PCM в очереди DLL: чтение ждёт, пока пул не разгребёт (backpressure)
M.KEEP_LIMIT=1536*1024*1024 -- полные признаки дублей сверх этого сжимаются до лёгких (смена Profile/Search перечитает их)
local checked
function M.available(r)
  if checked~=nil then return checked[1],checked[2] end
  for _,name in ipairs(API)do
    if type(r[name])~='function' then checked={false,'C++ Align is not in the installed extension. Install the new reaper_vocaligner_native.dll and restart REAPER.'};return false,checked[2] end
  end
  local ok,version=pcall(r.VN_AlignVersion)
  if not ok or version~=1 then checked={false,'C++ Align ABI mismatch.'}
  elseif r.VN_AlignSelfTest()~=1 then checked={false,'C++ Align self-test failed; using Lua.'}
  else checked={true} end
  return checked[1],checked[2]
end
function M.preference(r)return r.GetExtState(section,'backend')=='lua' and 'lua' or 'cpp' end
function M.select(r,value)r.SetExtState(section,'backend',value=='lua' and 'lua' or 'cpp',true)end
-- 0 = авто (логические CPU − 1, не больше 12)
function M.thread_setting(r)return math.tointeger(tonumber(r.GetExtState(section,'threads'))or 0)or 0 end
function M.set_threads(r,n)n=math.max(0,math.min(32,math.floor(n or 0)));r.SetExtState(section,'threads',tostring(n),true);if n>0 and M.available(r) then r.VN_AlignWorkers(n) end end
-- Готов ли C++ путь для этого запуска (выбран в Settings и DLL прошла проверку)
function M.active(r)return M.preference(r)=='cpp' and (M.available(r)) end

-- Владение дескриптором DLL: явный release или сборщик мусора (кеш ref_audio/d.audio живёт дольше задачи)
local Handle={};Handle.__index=Handle
Handle.__gc=function(h)if not h.released then h.released=true;pcall(h.r.VN_AlignRelease,h.id)end end
function Handle:release()if not self.released then self.released=true;self.r.VN_AlignRelease(self.id)end end
local function own(r,id)return setmetatable({r=r,id=id},Handle)end
local function weight(profile)return profile=='Harmony / different voice' and 0 or (profile=='Speech' and .02 or .08)end

local stat_buf
local function stats(r)stat_buf=stat_buf or r.new_array(5);r.VN_AlignStats(stat_buf);local v=stat_buf.table();return {workers=v[1],queued=v[2],handles=v[3],stored=v[4],pending=v[5]}end
M.stats=stats

-- Чтение одной роли (айтем или группа айтемов) в DLL. Тот же разбор accessor/play rate/групп, что в Audio.analyze;
-- блоки идут подряд без перекрытия, признаки считает DLL. wait() вызывается, пока очередь DLL переполнена.
function M.read(r,s,cfg,job,label,wait)
  if s.len>cfg.max_seconds then error('Capture sections shorter than '..cfg.max_seconds..' seconds.',0) end
  local valid,why=Audio.unchanged(r,s);if not valid then error(why,0) end
  local readers={}
  for i,p in ipairs(Audio.parts(s)) do
    local aa=r.CreateTakeAudioAccessor(p.take);if not aa then error('Cannot read '..p.name,0) end
    job.resources[aa]=r.DestroyAudioAccessor
    readers[i]={aa=aa,part=p,first=math.floor((p.pos-s.pos)*cfg.sample_rate+.5),
      accessor_start=r.GetAudioAccessorStartTime(aa),accessor_end=r.GetAudioAccessorEndTime(aa)}
  end
  local primary=readers[1];local aa=primary.aa
  local sr,hop,n=cfg.sample_rate,cfg.hop,cfg.fft_size
  for _,reader in ipairs(readers) do
    local p=reader.part;reader.scale=1
    if math.abs(reader.accessor_start)>1e-4 then error('Unexpected take accessor time origin: '..p.name,0) end
    if math.abs(p.rate-1)>1e-6 and math.abs(reader.accessor_end-p.len*p.rate)<1e-4
      and math.abs(reader.accessor_end-p.len)>1e-4 then reader.scale=p.rate end
  end
  local time_scale=primary.scale
  local read_rate=math.floor(sr/time_scale+.5)
  if read_rate<1000 or read_rate>192000 then error('Unsupported accessor/play-rate combination.',0) end
  local effective_rate=read_rate*time_scale
  if math.abs(effective_rate-sr)>1e-8 then sr=effective_rate end
  for _,reader in ipairs(readers) do
    reader.read_rate=math.floor(sr/reader.scale+.5);reader.count=math.ceil(reader.part.len*sr)
    if #readers>1 and math.abs(reader.read_rate*reader.scale-sr)>1e-8 then
      error('Grouped items need play rates that share one analysis grid: '..reader.part.name,0)
    end
  end
  local total=math.ceil(s.len*sr);local num=math.max(1,math.ceil(total/hop))
  local reads={calls=0,nil_status=0,no_audio=0,nonzero_blocks=0,peak=0,
    sample_rate=read_rate,channels=s.channels,start_time=primary.accessor_start,end_time=primary.accessor_end}
  s.read_diagnostics=reads
  local block=math.min(65536,math.floor(131072/s.channels))
  local f={s=s,sr=sr,hop=hop,num=num,total=total,reads=reads,accessor_scale=time_scale,read_ms=0,began=r.time_precise()}
  local buffer,scratch,handle=job:call(function()
    local id=r.VN_AlignCreate(r.new_array({sr,n,hop,cfg.mel_bands,s.channels,total,num,s.pos,s.len}))
    if not id or id<=0 then error(r.VN_AlignError(0),0) end
    local h=own(r,id);job.resources[h]=Handle.release
    return r.new_array(block*s.channels),#readers>1 and r.new_array(block*s.channels) or nil,h
  end)
  f.handle=handle;job.resources[handle]=Handle.release
  local function read_block(read_start,count)
    buffer.clear()
    if #readers==1 then
      local status=r.GetAudioAccessorSamples(aa,read_rate,s.channels,read_start/sr*time_scale,count,buffer)
      if status==0 then buffer.clear() end
      return status
    end
    local status;local filled=read_start
    for _,reader in ipairs(readers) do
      local a=math.max(read_start,reader.first);local b=math.min(read_start+count,reader.first+reader.count)
      if b>a then
        scratch.clear()
        local st=r.GetAudioAccessorSamples(reader.aa,reader.read_rate,s.channels,(a-reader.first)/sr*reader.scale,b-a,scratch)
        if type(st)=='number' and st<0 then return st end
        if st~=0 then
          local shared=math.min(b,filled)
          if shared>a then
            local base=(a-read_start)*s.channels
            for k=1,(shared-a)*s.channels do buffer[base+k]=buffer[base+k]+scratch[k] end
          end
          local from=math.max(a,shared)
          if b>from then buffer.copy(scratch,(from-a)*s.channels+1,(b-from)*s.channels,(from-read_start)*s.channels+1) end
        end
        if type(st)=='number' then status=math.max(status or 0,st) end
        filled=math.max(filled,b)
      end
    end
    return status
  end
  local state_count=r.GetProjectStateChangeCount(s.project)
  for read_start=0,total-1,block do
    while wait and job:call(stats,r).pending>M.PENDING_LIMIT do wait() end
    for _,reader in ipairs(readers) do
      if not r.ValidatePtr2(s.project,reader.part.take,'MediaItem_Take*') then error('Captured take was deleted.',0) end
      job:call(Audio.validate_accessor,r,reader.part,reader.aa)
    end
    local now=r.GetProjectStateChangeCount(s.project)
    if now~=state_count then local yes,msg=Audio.unchanged(r,s);if not yes then error(msg,0) end;state_count=now end
    local count=math.min(block,total-read_start);local read_time=read_start/sr*time_scale
    reads.calls=reads.calls+1;reads.last_time=read_time;reads.last_count=count
    local result,appended=job:call(function()
      local at=r.time_precise();local st=read_block(read_start,count)
      local ok=(type(st)~='number' or st>=0) and r.VN_AlignAppend(handle.id,buffer,count) or nil
      f.read_ms=f.read_ms+(r.time_precise()-at)*1000;return st,ok
    end)
    reads.last_status=tostring(result)
    if type(result)=='number' then
      if result<0 then error(string.format('Audio read failed for %s at %.3f s (status %s).',s.name,read_time,result),0) end
      if result==0 then reads.no_audio=reads.no_audio+1 end
    elseif result==nil then reads.nil_status=reads.nil_status+1
    else error('Unexpected audio read status: '..tostring(result)..' ('..s.name..')',0) end
    if appended==0 then
      local why=job:call(r.VN_AlignError,0)
      error(why=='Invalid PCM sample' and 'Invalid PCM sample in '..s.name or tostring(why),0)
    end
    if appended==2 then reads.nonzero_blocks=reads.nonzero_blocks+1 end
    job:checkpoint((read_start+count)/total,label)
  end
  for _,reader in ipairs(readers) do job.resources[reader.aa]=nil;r.DestroyAudioAccessor(reader.aa) end
  local yes,msg=Audio.unchanged(r,s);if not yes then error(msg,0) end
  if reads.nil_status==reads.calls and reads.nonzero_blocks==0 then
    error('No audio received for '..s.name..': the accessor returned nil and every buffer was zero. Copy report for read diagnostics.',0)
  end
  job:call(function()if r.VN_AlignSeal(handle.id)~=1 then error(r.VN_AlignError(0),0) end end)
  return f
end
function M.poll(r,id)local st=r.VN_AlignPoll(id);if st==-1 then return -1,r.VN_AlignError(id) end;return st end

-- Лёгкие кадры: плоский массив + прокси, кадр-таблица собирается при первом обращении (#, ipairs, [i] работают)
local function frames(flat,count)
  return setmetatable({},{__len=function()return count end,__index=function(t,i)
    if type(i)~='number' or i<1 or i>count or i%1~=0 then return nil end
    local k=(i-1)*9;local v={t=flat[k+1],energy=flat[k+2],onset=flat[k+3],active=flat[k+4]~=0,rms=flat[k+5],flux=flat[k+6],zcr=flat[k+7],min=flat[k+8],max=flat[k+9]}
    rawset(t,i,v);return v
  end})
end
-- Итог анализа роли в форме Audio.analyze + DSP.normalize (для Warp, Hybrid, UI, диагностики)
function M.summary(r,f,job)
  local s=f.s;local id=f.handle.id
  local info,flat=job:call(function()
    local a=r.new_array(14);assert(r.VN_AlignInfo(id,a)==14,'Native Align summary is not ready');local info=a.table()
    local flat={};local chunk=8192;local buf=r.new_array(chunk*M.LITE)
    for first=0,f.num-1,chunk do
      local got=r.VN_AlignFrames(id,first,buf);assert(got>0,'Native Align frames are not ready')
      table.move(buf.table(1,got*M.LITE),1,got*M.LITE,#flat+1,flat)
    end
    return info,flat
  end)
  local data={hop=f.hop/f.sr,len=s.len,pos=s.pos,snapshot=s,accessor_scale=f.accessor_scale,analysis_rate=f.sr,reads=f.reads,
    native=f.handle,native_lite=true,frames=frames(flat,f.num),peak=info[8]}
  f.reads.peak=info[9]
  data.analysis_stats={backend='C++ Align',feature_ms=info[10],read_ms=f.read_ms,validation_ms=0,kernel_ms=info[10]}
  if info[14]==1 then data.gate=info[3];data.level_top=info[4] end
  if info[2]==1 then data.silent=true;return data end
  data.active_count=info[5];data.first=info[6];data.last=info[7]
  local levels={{hop=data.hop,values={}}};local base=levels[1].values
  for i=1,f.num do base[i]={flat[(i-1)*9+8],flat[(i-1)*9+9]};if i%4096==0 then job:checkpoint() end end
  while #levels[#levels].values>512 do
    local prev=levels[#levels];local nextp={hop=prev.hop*4,values={}}
    for i=1,#prev.values,4 do
      local lo,hi=0,0
      for j=i,math.min(i+3,#prev.values) do lo=math.min(lo,prev.values[j][1]);hi=math.max(hi,prev.values[j][2]) end
      nextp.values[#nextp.values+1]={lo,hi}
    end
    levels[#levels+1]=nextp
  end
  data.peaks=levels
  return data
end
function M.match(r,ref,dub,cfg,snapshot_pos,job)
  return job:call(function()
    local id=r.VN_AlignMatch(ref.id,dub.id,r.new_array({cfg.search_s,cfg.max_cells,weight(cfg.profile),snapshot_pos}))
    if not id or id<=0 then error(r.VN_AlignError(0),0) end
    local h=own(r,id);job.resources[h]=Handle.release;return h
  end)
end
-- Путь и статистика в форме DTW.align (плюс orig/onset точки — Warp.build берёт их вместо кадров)
function M.path(r,m,job)
  return job:call(function()
    local a=r.new_array(7);assert(r.VN_AlignMatchInfo(m.id,a)==7,'Native Align match is not ready');local v=a.table()
    local path={};local chunk=4096;local buf=r.new_array(chunk*9)
    for first=0,v[1]-1,chunk do
      local got=r.VN_AlignMatchPath(m.id,first,buf);local x=buf.table(1,got*9)
      for k=0,got-1 do local b=k*9;local orig=x[b+8]
        path[#path+1]={dub=x[b+1],ref=x[b+2],di=math.tointeger(x[b+3]),ri=math.tointeger(x[b+4]),cost=x[b+5],active=x[b+6]~=0,audible=x[b+7]~=0,
          orig=orig==orig and orig or nil,onset=x[b+9]}
      end
    end
    return path,{cost=v[2],support=v[3],coverage=v[4],cells=math.tointeger(v[5]),confidence=v[6],match_ms=v[7]}
  end)
end

-- План Classic (warp.lua M.build без Hybrid) в DLL по уже сохранённому там пути. Тот же результат, что Warp.build
-- (сверка: native/test_align.py); Hybrid и Strength (Warp.blend) остаются в Lua.
local function live(h)return h and not h.released end
function M.can_plan(r,d,cfg)return (cfg.hybrid or 0)==0 and live(d.native_match) and M.active(r) and true or false end
function M.submit_plan(r,app,d,cfg,job)
  local s=d.snapshot;local parts=Audio.parts(s)
  local v={cfg.smooth_ms or 0,cfg.tolerance_ms,cfg.search_s,cfg.max_ratio,cfg.detail_ms,cfg.marker_density or 50,cfg.hide_1x or 0,
    s.pos,s.len,app.ref_audio.pos,app.ref_audio.len,s.composite and 1 or 0,#parts}
  for _,p in ipairs(parts)do
    v[#v+1]=p.pos;v[#v+1]=p.len;v[#v+1]=p.offset;v[#v+1]=p.rate;v[#v+1]=#p.markers
    for _,m in ipairs(p.markers)do v[#v+1]=m.pos;v[#v+1]=m.src end
  end
  return job:call(function()
    local id=r.VN_AlignPlan(d.native_match.id,r.new_array(v));if not id or id<=0 then error(r.VN_AlignError(0),0) end
    local h=own(r,id);job.resources[h]=Handle.release;return h
  end)
end
-- Готовый план: та же форма, что у base из Warp.build, затем Warp.blend по Strength
function M.read_plan(r,h,d,cfg,job)
  local info,rows=job:call(function()
    local a=r.new_array(8);assert(r.VN_AlignPlanInfo(h.id,a)==8,'Native Align plan is not ready');local info=a.table()
    local buf=r.new_array(math.max(1,info[1])*6);local got=r.VN_AlignPlanMarkers(h.id,0,buf);assert(got==info[1],'Incomplete native plan')
    return info,buf.table(1,got*6)
  end)
  local out={}
  for k=0,info[1]-1 do local b=k*6
    out[k+1]={t=rows[b+1],target=rows[b+2],source=rows[b+3],confidence=rows[b+4],edge=rows[b+5]~=0 or nil,boundary=rows[b+6]~=0 or nil}
  end
  local stats=d.stats
  local base={markers=out,pos=info[7],len=info[8],snapshot=d.snapshot,stats=stats,limited=math.tointeger(info[2]),hidden_1x=math.tointeger(info[3]),
    min_ratio=info[4],max_ratio=info[5],max_shift=info[6],unchanged=info[6]<.001,
    review=stats.confidence<.4 or stats.coverage<.55 or (stats.support or 1)<.65}
  return Warp.blend(base,cfg.strength),base
end
-- Пересчёт планов после движения ручек (app.lua, задача 'timing'): все дубли с путём в DLL — одновременно в пуле,
-- остальные (Hybrid, Lua-путь) — прежним Warp.build. Возвращает тот же список, что строил Lua-цикл.
function M.replan(app,job,cfg)
  local r=app.r;local plans={};local wait={}
  for _,d in ipairs(app.dubs)do if d.path then
    local entry={dub=d};plans[#plans+1]=entry
    if M.can_plan(r,d,cfg) and app.ref_audio then
      local ok,h=pcall(M.submit_plan,r,app,d,cfg,job)
      if ok then entry.handle=h;job.resources[h]=Handle.release;wait[#wait+1]=entry else entry.error=tostring(h) end
    else
      local plan,err,base=Warp.build(app.ref_audio,d.audio,d.path,d.stats,cfg,job);entry.plan,entry.base,entry.error=plan,base,err
    end
  end end
  while #wait>0 do
    for k=#wait,1,-1 do local e=wait[k];local st,why=M.poll(r,e.handle.id)
      if st~=0 then
        table.remove(wait,k)
        if st==1 then local ok,plan,base=pcall(M.read_plan,r,e.handle,e.dub,cfg,job);if ok then e.plan,e.base=plan,base else e.error=tostring(plan) end
        else e.error=why end
        job.resources[e.handle]=nil;e.handle:release()
      end
    end
    if #wait>0 then job:checkpoint(nil,'C++ Align: planning');coroutine.yield() end
  end
  for _,e in ipairs(plans)do if not e.plan then app:fail(e.dub.snapshot.name..': '..tostring(e.error)) end end
  return plans
end

-- Вся пачка Classic: тот же результат и те же статусы, что у Lua-цикла в app.lua, но чтение, признаки, DTW и план
-- идут конвейером: пока DLL сопоставляет дубль A и считает признаки B, главный поток читает C.
function M.run(app,job,cfg)
  local r=app.r;local threads=M.thread_setting(r);if threads>0 then r.VN_AlignWorkers(threads) end
  local total=app.ref.len;for _,d in ipairs(app.dubs)do total=total+d.snapshot.len end
  local done_s=0;local function progress()return math.min(.99,done_s/total) end
  local ok,msg=Audio.unchanged(r,app.ref);if not ok then error(msg,0) end
  local ref=app.ref_audio and app.ref_audio.native_lite and live(app.ref_audio.native) and app.ref_audio or nil
  local ref_feature
  local pending={};local usable=0;local count=#app.dubs;local finished=0
  local function skip(d,why)
    d.status='Skipped';d.plan=nil;d.full_plan=nil;d.enabled=false;d.error=tostring(why)
    app:fail(d.snapshot.name..': '..tostring(why))
  end
  local function accept(d,plan,base)
    d.plan=plan;d.full_plan=base;d.enabled=true;d.error=nil
    d.status='Ready';usable=usable+1
    if plan.review then app:report(string.format('%s: low match %.1f%%; applying the calculated timing.',d.snapshot.name,100*(d.stats.confidence or 0))) end
  end
  -- План: в DLL (асинхронно, entry ждёт в очереди) или прежний Warp.build (Hybrid / путь из Lua)
  local function plan(d,entry)
    if M.can_plan(r,d,cfg) then
      entry=entry or {d=d};entry.match=nil;entry.feature=nil;entry.plan=M.submit_plan(r,app,d,cfg,job);job.resources[entry.plan]=Handle.release
      pending[#pending+1]=entry;return
    end
    local p,reason,base=Warp.build(app.ref_audio,d.audio,d.path,d.stats,cfg,job)
    if not p then error(reason,0) end
    accept(d,p,base);finished=finished+1
  end
  -- Ошибка референса роняет всю задачу (как в Lua-цикле), даже если впервые всплыла внутри pcall одного дубля
  local fatal
  local function ref_ready()
    if fatal then error(fatal,0) end
    if app.ref_audio==ref and ref then return true end
    local st,why=M.poll(r,ref_feature.handle.id)
    if st==-1 then fatal='Reference: '..tostring(why);error(fatal,0) end
    if st~=1 then return false end
    local data=M.summary(r,ref_feature,job);job.resources[ref_feature.handle]=nil
    if data.silent then app.ref_audio=nil;fatal='The reference is silent or too quiet to analyze.';error(fatal,0) end
    app.ref_audio=data;ref=data
    return true
  end
  local function feature_summary(d,e)
    if e.feature and not (d.audio and d.audio.native==e.feature.handle) then
      d.audio=M.summary(r,e.feature,job);d.audio.snapshot=d.snapshot;job.resources[e.feature.handle]=nil
    end
  end
  -- Забрать готовые результаты (не обязательно по порядку дублей — показываются по мере готовности)
  local function harvest()
    if not ref_ready() then return end
    local kept
    for k=#pending,1,-1 do
      local e=pending[k];local d=e.d
      local handle=e.plan or e.match or (e.feature and e.feature.handle)
      local st,why=1,nil;if handle then st,why=M.poll(r,handle.id) end -- без дескриптора: путь прежний, ждали только референс
      if st~=0 then
        table.remove(pending,k)
        local good,err=pcall(function()
          if e.match and e.feature and M.poll(r,e.feature.handle.id)==1 then feature_summary(d,e) end -- анализ сохраняется и при неудачном сопоставлении
          if st==-1 then error(why,0) end
          feature_summary(d,e)
          if e.plan then
            local p,base=M.read_plan(r,e.plan,d,cfg,job);job.resources[e.plan]=nil;e.plan:release();e.plan=nil
            accept(d,p,base);finished=finished+1
          else
            if e.match then
              local path,info=M.path(r,e.match,job);job.resources[e.match]=nil
              -- путь остаётся в DLL: пересчёт плана при движении ручек идёт там же, без передачи точек
              if d.native_match and d.native_match~=e.match then d.native_match:release() end
              d.native_match=e.match;d.path,d.stats=path,info;d.match_profile=cfg.profile;d.match_search=cfg.search_s
            end
            plan(d,e)
          end
          kept=kept or job:call(stats,r).stored
          -- Полные признаки нужны только для нового сопоставления (смена Profile/Search); при нехватке памяти — лёгкие
          if kept>M.KEEP_LIMIT and d.audio and live(d.audio.native) and not d.audio.native_compact and job:call(r.VN_AlignCompact,d.audio.native.id)==1 then d.audio.native_compact=true end
        end)
        if e.match and e.match~=d.native_match then job.resources[e.match]=nil;e.match:release() end
        if not good then
          if e.plan then job.resources[e.plan]=nil;e.plan:release() end
          skip(d,err);finished=finished+1
        end
        job:checkpoint(progress(),string.format('Matched %d / %d',finished,count))
      end
    end
  end
  local function wait()harvest();job:checkpoint(progress(),'C++ Align: workers busy');coroutine.yield()end
  if not ref then
    app.ref_audio=nil
    ref_feature=M.read(r,app.ref,cfg,job:scope(0,app.ref.len/total),'Reading reference',wait)
  end
  done_s=app.ref.len
  for i,d in ipairs(app.dubs) do
    d.status='Analyzing'
    local good,why=pcall(function()
      local valid,changed=Audio.check_dub(r,d);if not valid then error(changed,0) end
      local needs_match=not d.path or d.match_profile~=cfg.profile or d.match_search~=cfg.search_s
      local native=d.audio and d.audio.native_lite and live(d.audio.native) and not d.audio.native_compact
      local entry={d=d,i=i}
      if not needs_match and d.audio then
        -- путь прежний: только план (как в Lua-цикле), без чтения; если референс ещё читается — план после него
        if ref_ready() then plan(d) else pending[#pending+1]=entry end
        done_s=done_s+d.snapshot.len;return
      end
      if not d.audio or (needs_match and not native) then
        d.audio=nil;if needs_match then d.path=nil;d.stats=nil end
        local first=done_s/total
        entry.feature=M.read(r,app:align_read_snapshot(d.snapshot),cfg,job:scope(first,first+d.snapshot.len/total),'Reading dub '..i..' / '..count,wait)
      end
      if needs_match then
        d.path=nil;d.stats=nil
        local dub=entry.feature and entry.feature.handle or d.audio.native
        local reference=ref_feature and ref_feature.handle or app.ref_audio.native
        entry.match=M.match(r,reference,dub,cfg,d.snapshot.pos,job);job.resources[entry.match]=Handle.release
      end
      d.status=needs_match and 'Matching' or 'Analyzing';pending[#pending+1]=entry
      done_s=done_s+d.snapshot.len
    end)
    if not good then skip(d,why);finished=finished+1;done_s=done_s+d.snapshot.len end
    harvest()
  end
  while #pending>0 or not ref_ready() do
    harvest()
    if #pending>0 or not ref_ready() then job:checkpoint(progress(),string.format('C++ Align: matching %d / %d',finished,count));coroutine.yield() end
  end
  app.analyzed=usable>0
  job:checkpoint(1,'Alignment ready')
end
return M
