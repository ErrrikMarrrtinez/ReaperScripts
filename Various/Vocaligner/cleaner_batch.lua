-- @noindex
local import=...;local Job=import('job');local Config=import('config');local Audio=import('audio');local Apply=import('apply')
local M={}
-- ---- Конвейер чтения: пока пул потоков DLL считает текущий айтем (детектор, классификация Breaths), главный поток читает
-- аудио следующего. Чтение идёт отдельной сопрограммой-«дорожкой» с теми же вызовами job:call / job:checkpoint, что и
-- обычное; кадр бюджета общий: дорожка получает управление только когда основная ждёт DLL (job.wait ниже) или сама читает.
-- Дальше одного айтема вперёд не читаем: память под PCM/колонки кадров ограничена и так (KEEP_LIMIT в DLL).
local Lane={};Lane.__index=Lane
function Lane:call(fn,...)
  local result=coroutine.yield({call=fn,args=table.pack(...)})
  if not result[1] then error(result[2],0) end
  return table.unpack(result,2,result.n)
end
function Lane:checkpoint()
  local parent=self.parent
  if parent.cancelled then error('Cancelled',0) end
  if parent.r.time_precise()>=(parent.deadline or 0) then coroutine.yield('budget') end
end
function Lane:wait() coroutine.yield('wait') end
function Lane:scope() return self end
local function start_reader(parent,index,fn)
  local lane=setmetatable({parent=parent,r=parent.r,resources=parent.resources},Lane)
  return {index=index,done=false,co=coroutine.create(function()return fn(lane)end)}
end
-- Дорожка идёт до первой остановки: 'budget' (кадр исчерпан), 'wait' (ждёт DLL) или 'done'. Вызовы REAPER она отдаёт
-- основной задаче через parent:call — они исполняются в главном цикле, как у обычной задачи.
local function advance(parent,reader)
  while not reader.done do
    local ok,value=coroutine.resume(reader.co,reader.reply);reader.reply=nil
    if not ok then reader.done=true;reader.error=value;return 'done' end
    if coroutine.status(reader.co)=='dead' then reader.done=true;return 'done' end
    if type(value)=='table' and value.call then
      local res=table.pack(pcall(parent.call,parent,value.call,table.unpack(value.args,1,value.args.n)))
      if res[1] then reader.reply=table.pack(true,table.unpack(res,2,res.n)) else reader.reply=table.pack(false,res[2]) end
      reader.slices=(reader.slices or 0)+1
    else return value end
  end
  return 'done'
end
M.Lane,M.start_reader,M.advance=Lane,start_reader,advance
function M.start(c,explicit,remove)
  if c.job or c.app.job then return end
  local targets={};for _,d in ipairs(c.targets or {})do targets[#targets+1]=d end
  if #targets<2 then return end
  local revision=c.revision;local mode=c.mode;local configs={};local total=0
  for i,d in ipairs(targets)do configs[i]=Config.copy(d.cfg);total=total+math.max(.01,d.snapshot.len) end
  local transaction=c.edit_transaction
  c.pending=nil;c.error=nil
  c.job=Job.new(c.r,function(job)
    local results={};local elapsed=0
    local Dynamics=import('compressor/settings')
    local function needs_read(d) return not d.audio or d.audio.dynamics_only and not Dynamics.dynamic(mode) end
    -- Читатель следующего айтема: стартует, как только текущий прочитан, и работает в паузах, пока основная дорожка ждёт DLL
    local reader
    job.wait=function(self)
      if reader and not reader.done then advance(self,reader) end
      coroutine.yield()
    end
    local function prefetch(j)
      local d=targets[j]
      if not d or reader or not needs_read(d) or c.cfg.batch_prefetch==0 then return end
      reader=start_reader(job,j,function(lane)
        local ok,why=true,nil
        if not d.restore_value then ok,why=lane:call(Audio.check_dub,c.r,d) end
        if not ok then d.stale=true;d.want_apply=false;error(why,0) end
        c:read_audio(d,lane)
      end)
      job.prefetched=(job.prefetched or 0)+1
    end
    for i,d in ipairs(targets)do
      local a,b=elapsed/total,(elapsed+math.max(.01,d.snapshot.len))/total;elapsed=b*total
      local part=job:scope(a*.94,b*.94)
      local ok,why=true,nil
      if not d.restore_value then ok,why=job:call(Audio.check_dub,c.r,d) end
      if not ok then d.stale=true;d.want_apply=false;error(why,0) end
      if reader and reader.index==i then
        -- дочитываем то, что дорожка уже начала (кадры отдаём интерфейсу между её остановками)
        while not reader.done do
          if advance(job,reader)~='done' then job:checkpoint(.72*(a+b)/2,'Reading '..i..' / '..#targets);coroutine.yield() end
        end
        local failure=reader.error;reader=nil
        if failure then error(failure,0) end
      elseif needs_read(d) then c:read_audio(d,part:scope(0,.72)) else d.analysis_reuses=(d.analysis_reuses or 0)+1 end
      part:checkpoint(.72,'Processing '..i..' / '..#targets)
      prefetch(i+1)
      -- Loaded session settings precede the explicit current group controls.
      local cfg=configs[i]
      local range={d.range[1],d.range[2]}
      if d~=c:current() then
        local x,y=c.r.GetSet_LoopTimeRange2(c.project,false,false,0,0,false)
        if y>x and y>d.snapshot.pos and x<d.snapshot.pos+d.snapshot.len then
          range={math.max(0,x-d.snapshot.pos),math.min(d.snapshot.len,y-d.snapshot.pos)}
        else range={0,d.snapshot.len} end
      end
      local out;local started=c.r.time_precise()
      if remove then
        out=c:build_preview(d,cfg,mode,range,part,true)
      else out=c:build_preview(d,cfg,mode,range,part:scope(.72,1)) end
      d.compute_ms=(c.r.time_precise()-started)*1000;results[i]=out;part:checkpoint(1,'Processed '..i..' / '..#targets)
    end
    job.wait=nil
    if revision~=c.revision then return end -- controls moved during the read; keep its cache, discard the stale preview
    job:checkpoint(.95,'Applying '..#targets..' items')
    job:call(function()
      if revision~=c.revision then return end
      for _,d in ipairs(targets)do
        local ok,why,geometry,gain_changed=Audio.check_dub(c.r,d);assert(ok,why)
        if geometry or gain_changed and d.layers and (d.layers.compressor or d.layers.gate) then
          c:request(true);return -- rebuild changed input before any native write
        end
      end
      c.job.writing=true
      local changed={};local before={};local detail=0
      for i,d in ipairs(targets)do
        local out=results[i];c:accept_preview(d,out,revision)
        if out.changed then
          before[d]={cleanup=d.cleanup,cfg=d.cleanup_cfg}
          d.cleanup=out.combined;d.next_layers=out.layers;d.cleanup_cfg=out.cfg
          for kind,layer in pairs(out.layers)do detail=math.max(detail,layer.detail or out.cfg[kind..'_detail'] or 70)end
          changed[#changed+1]=d
        end
      end
      if #changed>0 then
        local cfg=Config.copy(configs[1]);cfg.envelope_detail=detail
        local started=c.r.time_precise()
        local n,why=Apply.run(c.r,c.project,nil,changed,cfg,transaction)
        c.job.apply_ms=(c.r.time_precise()-started)*1000
        for _,d in ipairs(changed)do d.next_layers=nil end
        for _,d in ipairs(targets)do d.next_bypassed=nil end
        if not n then
          for _,d in ipairs(changed)do d.cleanup=before[d].cleanup;d.cleanup_cfg=before[d].cfg end
          error(why,0)
        end
      end
      for _,d in ipairs(targets)do
        d.want_apply=false;d.preview_changed=false;d.preview_valid=revision==c.revision
        d.processed_modes=d.processed_modes or {};d.processed_modes[mode]=not remove;d.save_pending=true
      end
      c.project_state=c.r.GetProjectStateChangeCount(c.project)
    end)
    -- Persistence is a separate, cancellable idle job; a new slider value must
    -- not wait for old metadata to finish saving before it reaches the audio.
    if explicit then c.app:report(string.format('%s: processed %d selected items.',mode,#targets))end
  end,.004)
  c.job.kind='batch';c.job.dub=c:current();c.job.mode=mode;c.job.live=not explicit;c.job.revision=revision;c.job.item_count=#targets
  for _,d in ipairs(targets)do if not d.audio then c.job.live=false end end
end
return M
