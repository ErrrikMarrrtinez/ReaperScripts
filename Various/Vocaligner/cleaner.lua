-- @noindex
local import=...;local Audio=import('audio');local Config=import('config');local Job=import('job')
local Cleanup=import('cleanup');local Curves=import('curves');local Apply=import('apply')
local BreathProfile=import('breath_profile');local BreathModel=import('breath_model');local Breath=import('breath')
local Session=import('session_cache');local State=import('cleanup_state');local Batch=import('cleaner_batch')
local Dynamics=import('compressor/settings');local Chain=import('compressor/chain');local PCM=import('compressor/audio')
local M={};M.__index=M
function M.new(app)
  local auto=not (app.r.GetExtState and app.r.GetExtState('Vocaligner session v7','auto')=='0')
  return setmetatable({app=app,r=app.r,cfg=Config.copy(app.cfg),cache={},items={},focus=1,revision=0,mode='deess',auto=auto},M)
end
function M:current() return self.items[self.focus] end
function M:fail(why) local text=tostring(why);if self.error~=text then self.app:report(text);if self.app.console then self.app:console('Vocaligner Cleanup error',text)end end;self.error=text end
function M:cancel()
  if self.job then self.job:cancel();self.job=nil end
  self.pending=nil;self.gesture=false;self.operation=nil
  Apply.finish(self.r,self.edit_transaction);self.edit_transaction=nil
end
function M:bind(project)
  if self.project==project then return end
  self:cancel();self.project=project;self.error=nil;self.project_state=nil;self.selection=nil;self.last_selected=nil
  local bucket=self.cache[project] or {items={},by_guid={},session=Session.new(self.r,project)};self.cache[project]=bucket
  self.session=bucket.session
  self.items=bucket.items;self.focus=bucket.focus or 1
  self.targets=nil;self.last_selection_key=nil;self.follow_key=nil;self.follow_due=nil;self.follow_target=nil;self.follow_guid=nil;self.last_selected_guid=nil
  local d=self:current();self.cfg=d and d.cfg or Config.copy(self.app.cfg)
  if d and not d.stale then
    if d.audio and not d.preview_valid then self:request(false) end
  end
end
function M:set_auto(value)
  self.auto=value;self.last_selected=nil;self.last_selected_guid=nil;self.last_selection_key=nil;self.follow_key=nil;self.follow_due=nil;self.follow_target=nil;self.follow_guid=nil
  if self.r.SetExtState then self.r.SetExtState('Vocaligner session v7','auto',value and '1' or '0',false) end
end
function M:dispose()
  self:cancel()
  local d=self:current()
  for _,target in ipairs(self.items)do
    if (target==d or target.save_pending) and target.audio_file and not target.audio_dirty then self:save(target);target.save_pending=nil end
  end
end
function M:save(d,job)
  if not self.session or not d or d.stale or d.restore_value then return end
  local started=self.r.time_precise()
  local ok,why=pcall(self.session.save,self.session,d,job)
  d.save_ms=(self.r.time_precise()-started)*1000;d.save_count=(d.save_count or 0)+1
  if not ok then self.cache_error='Session cache could not be saved: '..tostring(why);self:fail(self.cache_error)
  else self.cache_error=nil end
end
-- Последняя измеренная задержка обновления (пересчёт превью + запись в проект), мс; nil — ещё не измерялась.
function M:latency_ms()
  local d=self:current();if not d or not d.apply_ms then return nil end
  return (d.compute_ms or 0)+d.apply_ms
end
M.rt_max_ms=200 -- дольше — во время жеста не пишем, ждём отпускания
-- Можно ли сейчас писать в проект. Пока держат ручку или только что отпустили (quiet), запись откладывается:
-- тяжёлая запись в этот момент «подтормаживает» следующий захват ручки. RT Update разрешает писать и во время жеста,
-- но только если измеренная задержка мала, и не чаще, чем она позволяет.
function M:can_write_now()
  local now=self.r.time_precise()
  if not (self.gesture or now<(self.quiet_until or 0)) then return true end
  -- «Лёгкие» параметры (порог, ratio, attack…) идут по живому пути и без включённого RT Update (live_until ставит ui2/widgets).
  if (self.cfg.dynamics_rt or 0)<.5 and now>=(self.live_until or 0) then return false end
  local lat=self:latency_ms()
  if lat and lat>M.rt_max_ms then return false end -- слишком медленно: подождать отпускания
  if now<(self.rt_next or 0) then return false end
  self.rt_next=now+(lat and math.max(.03,lat*1.3/1000) or .05) -- темп записи = измеренная задержка (не чаще, чем она позволяет)
  return true
end
-- Задержка до следующего живого обновления во время жеста: подстраивается под измеренную скорость, пока не измерена — короткая.
function M:live_delay()
  local lat=self:latency_ms()
  return lat and math.max(.03,math.min(.25,lat*1.2/1000)) or .05
end
function M:request(auto)
  self.revision=self.revision+1
  local d=self:current();if not d then return end
  d.preview_valid=false;if auto then d.want_apply=true end
  if d.audio and not d.stale then self.pending=self.pending or self.r.time_precise()+.035 end
end
function M:settings_changed(key)
  self.quiet_until=self.r.time_precise()+.15
  local d=self:current();if d then
    d.want_apply=true
    if d.restore_value then d.pending_cfg=d.pending_cfg or {};d.pending_cfg[key]=self.cfg[key] end
  end
  for _,target in ipairs(self.targets or {})do
    target.cfg[key]=self.cfg[key]
    if target.restore_value then target.pending_cfg=target.pending_cfg or {};target.pending_cfg[key]=self.cfg[key] end
  end
  self.edit_transaction=self.edit_transaction or {}
  if self.job and (self.job.kind=='preview' or self.job.kind=='save'
    or self.job.kind=='batch' and self.job.live and not self.job.writing) then self.job:cancel();self.job=nil end
  self.app.cfg[key]=self.cfg[key];self.app:preferences_changed()
  if Dynamics.dynamic(self.mode) and self.cfg.dynamics_rt<.5 and self.gesture then
    if self.job and (self.job.kind=='preview' or self.job.kind=='batch' and self.job.live) then self.job:cancel();self.job=nil end
    self.revision=self.revision+1;self.pending=nil;self.deferred_controls=true
    for _,target in ipairs(self.targets or {d})do target.preview_valid=false;target.want_apply=false end
  else self:request(true) end
end
-- Сброс настроек текущей стадии (de-ess / breaths / compressor / gate) к умолчанию, без нового чтения и анализа аудио:
-- остальные стадии и сам анализ не трогаются, пересчитывается только эта стадия, как при её включении/выключении.
function M:reset_stage()
  local d=self:current();if not d or d.stale then return end
  local keys=Config[self.mode..'_keys'];if not keys then return end
  local n=0
  for _,key in ipairs(keys) do
    local def=Config.defaults[key]
    if def~=nil and self.cfg[key]~=def then self.cfg[key]=def;self:settings_changed(key);n=n+1 end
  end
  if n>0 then self:control_released() end
end
function M:control_released()
  self.save_after=self.r.time_precise()+1.5
  if self.approx_until then self.approx_until=nil;self:request(true) end -- после приближённых превью — точный пересчёт
  if self.deferred_controls then self.deferred_controls=nil;self:request(true) end
  local d=self:current();if not d or d.stale then return end
  d.want_apply=true
  d.save_pending=true
  if self.pending then self.pending=self.r.time_precise() end
  if not d.audio and not self.job then self:analyze() end
end
function M:set_mode(mode)
  if mode==self.mode then self.queued_mode=nil;return end
  if self.job and (self.job.kind=='apply' or self.job.kind=='batch') then self.queued_mode=mode;return end
  -- The initial read is shared by both cleanup tabs. Keep its progress and accessor.
  local reading=self.job and self.job.kind=='read'
  if not reading then self:cancel() end;self.mode=mode
  local d=self:current()
  if d then d.want_apply=self.auto;d.preview=nil;d.detected=nil
    if not reading then if self.auto then self:analyze(true) else self:request(false) end end
  end
end
function M:select_item(index,keep_targets)
  if self.job and self.job.kind=='apply' then return end
  self:cancel();self.focus=index;self.error=nil
  local d=self:current();if not d then return end
  if not keep_targets then self.targets={d} end
  self.cache[self.project].focus=index;self.cfg=d.cfg
  local previous=d.applied_cleanup
  local ok,why=true,nil;if not d.restore_value then ok,why=Audio.check_dub(self.r,d) end
  if not ok then d.stale=true;d.want_apply=false;self:fail(why);return end
  d.stale=nil
  if previous~=d.applied_cleanup then
    d.want_apply=false;d.preview_valid=false
    if d.applied_cfg then d.cfg=Config.copy(Config.defaults);for k,v in pairs(d.applied_cfg)do d.cfg[k]=v end;self.cfg=d.cfg end
  end
  self.selection=nil;self:sync_selection()
  if keep_targets then return end
  if self.auto then self:analyze(true)
  elseif d.audio and not d.preview_valid then self:request(false) end
end
-- Each captured take keeps its source cache, controls, undo ownership and view.
-- A verified cached original stays authoritative, including when Get is pressed.
function M:capture(preview_only)
  if self.app.job or (self.job and self.job.kind=='apply') then return end
  local r=self.r;local project=r.EnumProjects(-1);local captured={};local additions=0
  self:bind(project);local bucket=self.cache[project]
  for p,b in pairs(self.cache) do
    if not Audio.project_open(r,p) then self.cache[p]=nil
    else
      local focused=b.items[b.focus or 1]
      for i=#b.items,1,-1 do
        if not r.ValidatePtr2(p,b.items[i].snapshot.item,'MediaItem*') then table.remove(b.items,i) end
      end
      b.by_guid={}
      for i,d in ipairs(b.items) do b.by_guid[d.snapshot.guid]=i end
      b.focus=focused and b.by_guid[focused.snapshot.guid] or 1
    end
  end
  self.focus=bucket.focus or 1
  local total=0;for _,b in pairs(self.cache) do for _,d in ipairs(b.items) do total=total+d.snapshot.len end end
  local skipped=0
  for i=0,r.CountSelectedMediaItems(0)-1 do
    local item=r.GetSelectedMediaItem(0,i);local take=r.GetActiveTake(item)
    if not take or r.TakeIsMIDI(take) then skipped=skipped+1
    else
    local ok,s=pcall(Audio.capture,r,project,item,'cleanup')
    if not ok then self:fail(s);return end
    local index=bucket.by_guid[s.guid];local old=index and self.items[index]
    local reuse=old and old.snapshot.item==s.item and Audio.check_dub(r,old)
    if reuse then captured[#captured+1]={index=index,dub=old}
    else
      -- A replaced capture recovers its baseline and layers from the session cache.
      additions=additions+s.len-(old and old.snapshot.len or 0)
      local plan={snapshot=s,unchanged=true,volume_only=true,pos=s.pos,len=s.len,amount=0,
        markers={{t=0,target=s.pos},{t=s.len,target=s.pos+s.len}}}
      captured[#captured+1]={index=index,dub={snapshot=s,enabled=true,plan=plan,range={0,s.len},
        exclusions={},edits={},cfg=Config.copy(old and old.cfg or self.app.cfg),want_apply=not preview_only,
        breath_profile=old and old.breath_profile or BreathProfile.load(r,project,s.guid),
        quick=Audio.peaks(r,s)}}
      local d=captured[#captured].dub
      if self.session then
        local found,saved,why=pcall(self.session.find,self.session,s)
        if not found or why then self:fail('Cannot recover the session baseline: '..tostring(why or saved));return end
        d.restore_value=saved
        if saved then for k,v in pairs(saved.cfg)do d.cfg[k]=v end end
      end
    end
  end
  end
  if skipped>0 then self.app:report(string.format('Skipped %d selected empty or MIDI items.',skipped)) end
  if #captured==0 then self:fail('Select an audio item in REAPER.');return end
  if (total+additions)*self.cfg.sample_rate/self.cfg.hop>self.cfg.max_total_frames then
    self:fail('The session audio cache is full (20 minutes). Close unused project tabs or restart the script.');return
  end
  for _,entry in ipairs(captured) do
    local index=entry.index or (#self.items+1);entry.index=index
    self.items[index]=entry.dub;bucket.by_guid[entry.dub.snapshot.guid]=index
  end
  self.last_selected=r.CountSelectedMediaItems(0)==1 and captured[1].dub.snapshot.item or nil
  self.last_selected_guid=self.last_selected and captured[1].dub.snapshot.guid or nil
  self:select_item(captured[1].index,true)
  self.targets={};for _,entry in ipairs(captured)do self.targets[#self.targets+1]=entry.dub end
  self.last_selection_key=self:selection_key()
  if not preview_only then
    if #self.targets>1 then
      -- Capturing a group restores each item's controls; only an actual knob edit links them.
      Batch.start(self,true)
    else self:analyze(true) end
  end
end
-- Настройки совпадают с теми, при которых сохранены результаты разбора (числовые и строковые параметры)
local function same_cfg(saved,current)
  for k,v in pairs(saved or {}) do
    local t=type(v);if (t=='number' or t=='string' or t=='boolean') and current[k]~=v then return false end
  end
  return saved~=nil
end
function M:read_audio(d,job)
  local cfg=Config.copy(d.cfg);cfg.cleanup_only=true;local started=self.r.time_precise()
    if d.restore_value then
      local saved=d.restore_value;local current=d.snapshot
      local restored=self.session:attach(saved,current,job)
      current=job:call(Audio.capture,self.r,self.project,current.item,'cleanup')
      assert(current.guid==restored.snapshot.guid,'The active take changed during cache loading.')
      local ok,why=job:call(State.check,self.r,restored,current);if not ok then error(why,0) end
      local want=d.want_apply;local pending_cfg=d.pending_cfg
      for k in pairs(d) do d[k]=nil end;for k,v in pairs(restored) do d[k]=v end
      for key,value in pairs(pending_cfg or {}) do d.cfg[key]=value end
      d.want_apply=want;if d==self:current() then self.cfg=d.cfg end;cfg=Config.copy(d.cfg);cfg.cleanup_only=true
      d.cache_status=d.audio and 'restored from REAPER session cache' or 'restored settings; reading audio'
      -- Разбор этой стадии уже есть в кэше и настройки не менялись: берём его, а не считаем заново
      local saved_preview=d.audio and d.applied and not d.foreign and d.layers and d.layers[self.mode] and d.preview_store and d.preview_store[self.mode]
      if saved_preview and same_cfg(saved_preview.cfg,d.cfg) and not next(pending_cfg or {}) then
        d.detected,d.effect_regions,d.detector_levels=saved_preview.detected,saved_preview.regions,saved_preview.levels
        d.preview,d.preview_layers,d.tool_preview=d.applied_cleanup,d.layers,d.layers and d.layers[self.mode]
        d.preview_cfg=Config.copy(d.cfg);d.preview_valid=true;d.preview_changed=false
        d.restored_preview=true;d.cache_status='restored from REAPER session cache (analysis reused)'
      end
    end
    if not d.audio or d.audio.dynamics_only and not Dynamics.dynamic(self.mode) then
      local current=job:call(Audio.capture,self.r,self.project,d.snapshot.item,'cleanup')
      if Dynamics.dynamic(self.mode) and not (d.layers and (d.layers.deess or d.layers.breath)) then d.audio=PCM.light(self,d,job)
      else d.audio=Audio.analyze(self.r,current,cfg,job,'Reading '..d.snapshot.name,self.app.engine) end
      d.audio_dirty=true
      d.analysis_count=(d.analysis_count or 0)+1
    end
    d.read_ms=(self.r.time_precise()-started)*1000
    self:save(d,job);if d==self:current() then self.selection=nil;self:sync_selection() end
end
function M:analyze(auto)
  local d=self:current();if not d or d.stale then return end
  if auto then d.want_apply=true end
  if self.targets and #self.targets>1 then Batch.start(self,true);return end
  if d.audio and not (d.audio.dynamics_only and not Dynamics.dynamic(self.mode)) then d.analysis_reuses=(d.analysis_reuses or 0)+1;self:request(auto);return end
  if self.job and self.job.kind=='read' and self.job.dub==d then return end
  self:cancel();self.error=nil;local cfg=Config.copy(d.cfg);cfg.cleanup_only=true;local started=self.r.time_precise()
  self.operation={progress=0,created_at=started}
  self.job=Job.new(self.r,function(job)
    self:read_audio(d,job)
  end,cfg.frame_budget)
  self.job.kind='read';self.job.dub=d
end
function M:set_range(a,b,sync)
  local d=self:current();if not d then return end
  if a>b then a,b=b,a end
  local hop=d.audio and d.audio.hop or .01
  a=math.max(0,math.min(d.snapshot.len,math.floor(a/hop+.5)*hop))
  b=b>=d.snapshot.len and d.snapshot.len or math.max(0,math.min(d.snapshot.len,math.floor(b/hop+.5)*hop))
  if b-a<hop*.5 then return end
  d.selected=true
  if sync and self.r.EnumProjects(-1)==self.project then
    local x,y=d.snapshot.pos+a,d.snapshot.pos+b
    self.r.GetSet_LoopTimeRange2(self.project,true,false,x,y,false);self.selection={x,y}
  end
  if d.range[1]~=a or d.range[2]~=b then d.range={a,b};d.want_apply=false;self:request(false) end
end
function M:sync_selection()
  local d=self:current();if not d or self.gesture or self.r.EnumProjects(-1)~=self.project then return end
  local a,b=self.r.GetSet_LoopTimeRange2(self.project,false,false,0,0,false)
  if self.selection and math.abs(a-self.selection[1])<1e-8 and math.abs(b-self.selection[2])<1e-8 then return end
  self.selection={a,b};d.selected=b>a and b>d.snapshot.pos and a<d.snapshot.pos+d.snapshot.len
  local x,y=0,d.snapshot.len
  if d.selected then x=math.max(0,math.min(d.snapshot.len,a-d.snapshot.pos));y=math.max(x,math.min(d.snapshot.len,b-d.snapshot.pos)) end
  if y-x<(d.audio and d.audio.hop or .01)*.5 then x,y=0,d.snapshot.len;d.selected=false end
  if d.range[1]~=x or d.range[2]~=y then d.range={x,y};self:request(false) end
end
function M:clear_range()
  if not self.project or self.r.EnumProjects(-1)~=self.project then return end
  self.r.GetSet_LoopTimeRange2(self.project,true,false,0,0,false);self.selection=nil;self.gesture=false
  local d=self:current();if d then d.drag_start=nil;d.click_seek=nil;d.want_apply=false end
  self:sync_selection()
end
function M:seek(t)
  local d=self:current();if not d or self.r.EnumProjects(-1)~=self.project then return end
  self.r.SetEditCurPos2(self.project,d.snapshot.pos+math.max(0,math.min(d.snapshot.len,t)),false,false)
end
local function deep(t) if type(t)~='table' then return t end local o={};for k,v in pairs(t) do o[k]=deep(v) end;return o end
-- Правки отдельных событий (вкл/выкл, множитель, границы, кривая): пересчёт сразу, без паузы перед превью,
-- и запись по живому пути (как у кнобов) — не ждём отпускания мыши.
function M:edits_changed(d)
  d.edits_rev=(d.edits_rev or 0)+1
  -- идущий пересчёт не выбрасываем (иначе при непрерывном перетаскивании результат не доходит до проекта):
  -- он доедет, а следом сразу запустится свежий (pending)
  if not (self.job and self.job.kind=='preview') then self.revision=self.revision+1 end
  d.preview_valid=false;d.want_apply=true
  local now=self.r.time_precise();self.live_until=now+.6;self.fast_until=now+.8
  -- пока тянут: стадии после текущей (компрессор/гейт) не пересчитываем — берём прошлый результат; точный пересчёт на отпускании
  if self.gesture then self.approx_until=now+1 end
  self.save_after=now+1.5 -- кэш сессии (≈200 мс) пишем только после паузы в правках
  if d.audio and not d.stale then self.pending=math.min(self.pending or now,now) end
end
-- Отмена/повтор правок событий (Ctrl+Z / Ctrl+Shift+Z в ручном режиме): снимок до каждого действия
function M:edits_push(d)
  d.edit_hist=d.edit_hist or {undo={},redo={}};local h=d.edit_hist
  h.undo[#h.undo+1]={edits=deep(d.edits or {}),exclusions=deep(d.exclusions or {})}
  if #h.undo>200 then table.remove(h.undo,1) end
  h.redo={}
end
function M:edits_undo(d,redo)
  local h=d and d.edit_hist;if not h then return false end
  local from,to=redo and h.redo or h.undo,redo and h.undo or h.redo
  local snap=table.remove(from);if not snap then return false end
  to[#to+1]={edits=deep(d.edits or {}),exclusions=deep(d.exclusions or {})}
  d.edits,d.exclusions=snap.edits,snap.exclusions
  self:edits_changed(d);return true
end
function M:toggle_region(d,event)
  Cleanup.toggle(d.exclusions,event);self:edits_changed(d)
end
-- Ручная правка события (De-ess): найти/создать запись в d.edits, изменить через fn(x) и пересчитать.
-- fn может вернуть false — тогда запись удаляется (сброс правки).
function M:edit_region(d,event,fn)
  d.edits=d.edits or {}
  local x=Cleanup.find_edit(d.edits,event.kind,event.start,event.finish)
  if not x then x={kind=event.kind,start=event.start,finish=event.finish};d.edits[#d.edits+1]=x end
  if fn(x)==false then for i,y in ipairs(d.edits) do if y==x then table.remove(d.edits,i);break end end end
  self:edits_changed(d)
end
-- Нарисованная кривая без события (или поверх нескольких): отдельная запись на её отрезке
function M:add_curve(d,kind,curve)
  d.edits=d.edits or {}
  local a,b=curve[1].t,curve[#curve].t
  for i=#d.edits,1,-1 do local y=d.edits[i];if y.kind==kind and y.curve and y.curve[1].t<b and y.curve[#y.curve].t>a then table.remove(d.edits,i) end end
  local x=Cleanup.find_edit(d.edits,kind,a,b)
  if x then x.curve=curve else d.edits[#d.edits+1]={kind=kind,start=a,finish=b,curve=curve} end
  self:edits_changed(d)
end
function M:learn_breath(kind)
  local d=self:current()
  if self.mode~='breath' or not d or not d.audio or d.stale or not d.selected or self.app.job
    or (self.job and self.job.kind~='preview') then return end
  self:cancel();self.error=nil;d.want_apply=false
  local range={d.range[1],d.range[2]};local previous=d.breath_profile or BreathProfile.new()
  self.job=Job.new(self.r,function(job)
    local profile={revision=previous.revision,examples={}}
    for i,e in ipairs(previous.examples) do profile.examples[i]=e end
    local ok,why=BreathProfile.learn(d.audio,profile,range,kind,job)
    if not ok then error(why,0) end
    local sensitivity,note=d.cfg.breath_sensitivity
    if kind==1 then sensitivity,note=Breath.calibrate(d.audio,profile,range,sensitivity,job,self.app.engine and self.app.engine.breath) end
    job:call(function()
      BreathProfile.save(self.r,self.project,d.snapshot.guid,profile);d.breath_profile=profile
      if kind==1 then
        d.cfg.breath_sensitivity=sensitivity;d.calibration_note=note
        self.app.cfg.breath_sensitivity=sensitivity;self.app:preferences_changed()
        self.app:report(string.format('Learn breath: Sensitivity %.1f%s',sensitivity,note and ' · '..note or ''))
      end
    end)
  end,.004)
  self.job.kind='learn';self.job.dub=d
end
function M:reset_breath_learning()
  local d=self:current();if not d or self.job or self.app.job or d.stale then return end
  d.breath_profile=BreathProfile.new();BreathProfile.save(self.r,self.project,d.snapshot.guid,d.breath_profile)
  self:request(true)
end
function M:build_preview(d,cfg,mode,range,job,remove)
  return Chain.build(self,d,cfg,mode,range,job,remove)
end
function M:reorder(source,target)
  if source==target or not Dynamics.is_tool(source) or not Dynamics.is_tool(target) then return end
  local order=Dynamics.parse(self.cfg.chain_order);local found
  for i,key in ipairs(order)do if key==source then found=table.remove(order,i);break end end
  for i,key in ipairs(order)do if key==target then table.insert(order,i,found);break end end
  self.cfg.chain_order=table.concat(order,',');self:settings_changed('chain_order');self:control_released()
end
function M:accept_preview(d,out,revision)
  d.hf_features=out.hf_features;d.detector_levels=out.levels;d.detected=out.detected;d.preview_layers=out.layers;d.preview=out.combined;d.tool_preview=out.curve;d.effect_regions=out.regions
  d.preview_valid=true;d.preview_changed=out.changed;d.section_max_db=out.peak;d.preview_cfg=out.cfg;d.preview_revision=revision
  -- Результаты разбора по стадиям сохраняются в сессии REAPER: после перезапуска скрипта не пересчитываются
  d.preview_store=d.preview_store or {}
  d.preview_store[self.mode]={cfg=Config.copy(out.cfg or d.cfg),detected=out.detected,regions=out.regions,levels=out.levels}
end
function M:preview()
  local d=self:current();if not d or not d.audio or d.stale then return end
  local cfg=Config.copy(d.cfg);local mode=self.mode;local revision=self.revision;local range={d.range[1],d.range[2]}
  local started=self.r.time_precise()
  self.job=Job.new(self.r,function(job)
    if d.audio.dynamics_only and not Dynamics.dynamic(mode) then self:read_audio(d,job) end
    local out=self:build_preview(d,cfg,mode,range,job)
    if d~=self:current() or mode~=self.mode or revision~=self.revision then return end
    self:accept_preview(d,out,revision)
    d.compute_ms=(self.r.time_precise()-started)*1000
  end,started<(self.fast_until or 0) and .03 or .004) -- после ручной правки события считаем почти за кадр, а не кусочками по 4 мс
  self.job.kind='preview';self.job.dub=d
end
function M:apply(remove,live)
  if remove and self.targets and #self.targets>1 then Batch.start(self,true,true);return end
  local d=self:current();if not d or not d.audio or d.stale or self.app.job or self.job or self.pending and not live then return end
  if not remove and (not d.preview_valid or not d.preview_changed) then return end
  local ok,why,geometry,gain_changed=Audio.check_dub(self.r,d);if not ok then d.want_apply=false;d.stale=true;self:fail(why);return end
  if not remove and (geometry or gain_changed and d.layers and (d.layers.compressor or d.layers.gate)) then
    if not d.audio then self:analyze(true) else self:request(true) end;return
  end
  d.want_apply=false
  local mode=self.mode;local layers=Config.copy(remove and d.layers or d.preview_layers or {})
  if remove then layers[mode]=nil end
  local cfg=Config.copy(not remove and d.preview_cfg or d.cfg);cfg.envelope_detail=0
  local revision=d.preview_revision or self.revision;local transaction=self.edit_transaction
  for kind,layer in pairs(layers) do
    cfg.envelope_detail=math.max(cfg.envelope_detail,layer.detail or (d.applied_cfg or cfg)[kind..'_detail'] or 70)
  end
  self.job=Job.new(self.r,function(job)
    if remove then
      local out=self:build_preview(d,cfg,mode,{0,d.audio.len},job,true);layers=out.layers;d.cleanup=out.combined
    else d.cleanup=d.preview end
    d.next_layers=layers;d.cleanup_cfg=cfg
    local regions=remove and {} or d.effect_regions
    local n,err=job:call(function()
      local started=self.r.time_precise()
      local count,why=Apply.run(self.r,self.project,nil,{d},cfg,transaction)
      d.apply_ms=(self.r.time_precise()-started)*1000
      return count,why
    end)
    d.next_layers=nil;d.next_bypassed=nil
    if not n then error(err,0) end
    d.processed_modes=d.processed_modes or {};d.processed_modes[mode]=not remove
    d.save_pending=true
    d.effect_regions=regions
    if not self.gesture then self.app:report(string.format('%s: %s, %d envelope points, %.1f ms.',d.snapshot.name,
      (remove and 'removed ' or 'applied ')..mode,d.envelope_points or 0,d.apply_ms)) end
  end,self.r.time_precise()<(self.fast_until or 0) and math.max(.03,cfg.frame_budget or 0) or cfg.frame_budget)
  self.job.kind='apply';self.job.dub=d;self.job.mode=mode;self.job.remove=remove;self.job.live=transaction~=nil;self.job.revision=revision;self.error=nil
end
-- Bypass removes one stage from the written envelope and keeps its layer
-- (recipes, ranges) in d.bypassed. Undo, Redo and the session cache keep it.
function M:bypassed(d,mode)
  d=d or self:current();return d~=nil and d.bypassed~=nil and d.bypassed[mode or self.mode]~=nil
end
function M:can_bypass(d)
  d=d or self:current()
  return d~=nil and not d.stale and (d.layers~=nil and d.layers[self.mode]~=nil or self:bypassed(d))
end
function M:set_bypass(on)
  local d=self:current()
  if not d or d.stale or not d.audio or self.app.job or self.job and (self.job.kind=='apply' or self.job.kind=='batch' or self.job.kind=='read') then return end
  if self.job then self:cancel() end
  self.pending=nil;self.error=nil
  local mode=self.mode;local group=self.targets and #self.targets>1
  local targets=group and self.targets or {d}
  if on then
    local any=false
    for _,t in ipairs(targets)do if t.layers and t.layers[mode] and not t.stale then
      local bypassed={};for k,v in pairs(t.bypassed or {})do bypassed[k]=v end
      bypassed[mode]=t.layers[mode];t.next_bypassed=bypassed;any=true
    end end
    if any then self:apply(true) end
    if not self.job then for _,t in ipairs(targets)do t.next_bypassed=nil end end
    return
  end
  local any=false
  for _,t in ipairs(targets)do if t.bypassed and t.bypassed[mode] and not t.stale then
    local layers={};for k,v in pairs(t.layers or {})do layers[k]=v end;layers[mode]=t.bypassed[mode];t.layers=layers
    local bypassed={};for k,v in pairs(t.bypassed)do if k~=mode then bypassed[k]=v end end
    t.bypassed=next(bypassed) and bypassed or nil;t.want_apply=true;t.preview_valid=false;any=true
  end end
  if not any then return end
  self.edit_transaction=self.edit_transaction or {}
  if group then self.revision=self.revision+1;Batch.start(self,true) else self:request(true) end
end
-- Bypass стадии, которая не открыта во вкладке: режим cleaner подменяется только на время синхронного вызова
-- (apply захватывает mode при создании задачи), вкладка и анализ не трогаются. false — сейчас нельзя (идёт запись/анализ).
function M:set_bypass_stage(mode,on)
  local d=self:current()
  if not d or d.stale or not d.audio or self.app.job or self.job and (self.job.kind=='apply' or self.job.kind=='batch' or self.job.kind=='read') then return false end
  local old=self.mode;self.mode=mode
  local ok,err=pcall(function() if self:can_bypass(d) then self:set_bypass(on) end end)
  self.mode=old
  if not ok then error(err,0) end
  return true
end
function M:selection_key()
  local r=self.r;local ids={}
  for i=0,r.CountSelectedMediaItems(0)-1 do
    local item=r.GetSelectedMediaItem(0,i);local take=r.GetActiveTake(item)
    local guid='empty';if take then local _;_,guid=r.GetSetMediaItemTakeInfo_String(take,'GUID','',false) end
    ids[#ids+1]=tostring(item)..':'..tostring(guid)
  end
  return table.concat(ids,'|')
end
function M:follow_selection()
  if not self.auto or self.gesture or (self.job and (self.job.kind=='apply' or self.job.kind=='batch')) or not Dynamics.is_tool(self.app.tab) then return end
  if self.r.CountSelectedMediaItems(0)>1 then
    local key=self:selection_key()
    if key==self.last_selection_key then self.follow_due=nil;return end
    if key~=self.follow_key or not self.follow_due then
      self:cancel();local d=self:current();if d then d.want_apply=false end
      self.follow_key=key;self.follow_due=self.r.time_precise()+.08
    end
    if self.r.time_precise()<self.follow_due then return end
    -- Consume the selection even when capture fails. Get retries explicitly;
    -- a new selection schedules a new attempt without a nil deadline or loop.
    self.follow_due=nil;self.last_selection_key=key;self:capture();return
  end
  self.follow_key=nil;self.last_selection_key=nil
  local r=self.r;local selected=r.CountSelectedMediaItems(0)==1 and r.GetSelectedMediaItem(0,0) or nil
  local take=selected and r.GetActiveTake(selected);local guid
  if take then local _;_,guid=r.GetSetMediaItemTakeInfo_String(take,'GUID','',false) end
  if selected==self.last_selected and guid==self.last_selected_guid then self.follow_target=selected;self.follow_due=nil;return end
  if selected~=self.follow_target or guid~=self.follow_guid then
    self:cancel();local d=self:current();if d then d.want_apply=false end
    self.follow_target=selected;self.follow_guid=guid;self.follow_due=r.time_precise()+.08
  end
  if not self.follow_due or r.time_precise()<self.follow_due then return end
  self:cancel();self.follow_due=nil
  self.last_selected=selected;self.last_selected_guid=guid;if not selected or not take then return end
  local index=self.cache[self.project].by_guid[guid]
  if index and self.items[index].snapshot.item==selected then
    if index~=self.focus then self:select_item(index) end
  else self:capture() end
end
function M:tick()
  local project=self.r.EnumProjects(-1);if not project then return end
  self:bind(project)
  local d=self:current()
  local state=self.r.GetProjectStateChangeCount(project)
  if d and not d.restore_value and state~=self.project_state and not (self.job and self.job.kind=='batch') then
    local previous=d.applied_cleanup;local ok,why,geometry,gain_changed=Audio.check_dub(self.r,d)
    if not ok then
      d.stale=true;d.want_apply=false;d.preview_valid=false;self:cancel();self:fail(why)
    elseif geometry then
      d.stale=nil;self.error=nil;self.selection=nil;self:cancel();self:sync_selection()
      if self.auto then self:analyze(true) else self:request(false) end
    elseif gain_changed then
      -- Overall item volume does not change De-ess/Breath source features.
      -- Only level-dependent dynamics need a new preview, using the same PCM.
      if d.layers and (d.layers.compressor or d.layers.gate) then
        self:cancel();self:request(self.auto)
      end
      d.save_pending=true
    elseif previous~=d.applied_cleanup then
      -- Undo/Redo must not immediately trigger the inverse automatic edit.
      d.want_apply=false
      if d.applied_cfg then d.cfg=Config.copy(Config.defaults);for k,v in pairs(d.applied_cfg)do d.cfg[k]=v end;self.cfg=d.cfg end
      self:request(false)
    elseif d.stale then d.stale=nil;self.error=nil;self:request(false)
    end
  end
  self.project_state=state
  if Dynamics.is_tool(self.app.tab) then self:follow_selection();self:sync_selection() end
  if self.job then
    local job=self.job
    if job.kind=='read' or job.kind=='preview' or job.kind=='batch' then job.budget=self.gesture and .004 or .012 end
    job:step()
    if self.operation then
      local stages={read={0,.72},preview={.72,.90},apply={.90,.99},save={.99,1}}
      local phase=stages[job.kind]
      if phase then self.operation.progress=math.max(self.operation.progress,phase[1]+(phase[2]-phase[1])*(job.progress or 0)) end
    end
    if job.done then
      self.job=nil;d=job.dub
      if job.error then
        d.want_apply=false;d.next_bypassed=nil;self.pending=nil;self.operation=nil;
        for _,target in ipairs(self.targets or {})do target.want_apply=false;target.next_bypassed=nil end
        self.last_selection_key=self:selection_key();Apply.finish(self.r,self.edit_transaction);self.edit_transaction=nil;self:fail(job.error)
      elseif job.kind=='read' then
        if d.restored_preview and d.preview_valid then d.restored_preview=nil;d.want_apply=false else d.restored_preview=nil;self:request(false) end
      elseif job.kind=='learn' then self:request(true)
      elseif job.kind=='preview' then
        d.max_step_ms=job.max_step_ms;d.preview_ticks=job.steps;d.preview_work_ms=job.work_ms
        if d.want_apply and d.preview_valid and d.preview_changed and self:can_write_now() then self:apply(false,true) end
      elseif job.kind=='apply' then
        self.project_state=self.r.GetProjectStateChangeCount(self.project)
        d.preview_valid=job.revision==self.revision;d.preview_changed=false;d.preview=d.cleanup;d.preview_layers=d.layers
        if job.revision~=self.revision and not self.deferred_controls then d.want_apply=true;self.pending=self.pending or self.r.time_precise()+.035 end
        d.processed_modes=d.processed_modes or {};d.processed_modes[job.mode]=not job.remove
        d.tool_preview=d.layers and d.layers[self.mode]
        self.error=self.cache_error
      elseif job.kind=='batch' then
        self.batch_stats={mode=job.mode,count=job.item_count,elapsed_ms=(self.r.time_precise()-job.created_at)*1000,
          work_ms=job.work_ms,apply_ms=job.apply_ms or 0,steps=job.steps,max_step_ms=job.max_step_ms}
        if job.revision~=self.revision and not self.deferred_controls then self.pending=self.pending or self.r.time_precise()+.035 end
      end
      if self.queued_mode then local mode=self.queued_mode;self.queued_mode=nil;self:set_mode(mode) end
    end
  elseif self.pending and self.r.time_precise()>=self.pending then
    self.pending=nil
    if self.targets and #self.targets>1 then Batch.start(self,false) else self:preview() end
  elseif not self.pending then
    d=self:current()
    if d and d.want_apply and d.preview_valid and self:can_write_now() then
      if d.preview_changed then self:apply()
      else d.want_apply=false;d.processed_modes=d.processed_modes or {};d.processed_modes[self.mode]=true;d.save_pending=true end
    end
    if d and d.save_pending and not self.job and not self.gesture and self.r.time_precise()>=(self.save_after or 0) then
      local targets=self.targets or {d}
      self.job=Job.new(self.r,function(job)
        for _,target in ipairs(targets)do if target==d or target.save_pending then self:save(target,job);target.save_pending=nil end end
      end,.004);self.job.kind='save';self.job.dub=d;self.job.live=true
    end
  end
  if not self.job and not self.pending and not self.gesture then
    local current=self:current()
    if not current or not current.want_apply then
      if self.operation then self.operation.progress=1;self.operation.done=true;self.operation=nil end
      Apply.finish(self.r,self.edit_transaction);self.edit_transaction=nil
    end
  end
end
function M:diagnostics()
  local engine=self.app.engine
  local lines={'CLEANUP: '..self.mode..' / cached live apply (35 ms)','backend = '..(engine and engine.label or 'Lua (cached bands)')}
  lines[#lines+1]='chain = '..self.cfg.chain_order..' | RT update = '..tostring(self.cfg.dynamics_rt>=.5)
  lines[#lines+1]='dynamics = '..(engine and engine.dynamics and engine.dynamics.fn and 'EEL / cached PCM' or 'unavailable')
  lines[#lines+1]='selection = '..(self.auto and 'Auto' or 'Get manually')..' | cache = REAPER session / project'
  local batch=self.batch_stats
  if batch then lines[#lines+1]=string.format('last batch %s / %d items: elapsed %.1f ms | work %.1f ms | native apply %.1f ms | steps %d | max step %.2f ms',
    batch.mode,batch.count,batch.elapsed_ms,batch.work_ms,batch.apply_ms,batch.steps,batch.max_step_ms) end
  if engine and engine.reason then lines[#lines+1]='EEL fallback: '..engine.reason end
  lines[#lines+1]='breath model = '..BreathModel.version..' | '..(engine and engine.breath and engine.breath.label or 'Lua breath trees')
  if engine and engine.breath and engine.breath.reason then lines[#lines+1]='Breath fallback: '..engine.breath.reason end
  for i,d in ipairs(self.items) do
    lines[#lines+1]='cache status = '..(d.cache_status or 'new capture')
    lines[#lines+1]=string.format('ITEM %d%s: %s | %.3f s | position %.6f | offset %.6f | rate %.6f | scope %.3f..%.3f | frames %d',
      i,i==self.focus and ' *' or '',d.snapshot.name,d.snapshot.len,d.snapshot.pos,d.snapshot.offset,d.snapshot.rate,d.range[1],d.range[2],d.audio and #d.audio.frames or 0)
    for _,keys in ipairs({Config.deess_keys,Config.breath_keys,Config.compressor_keys,Config.gate_keys}) do
      for _,key in ipairs(keys) do lines[#lines+1]='  '..key..' = '..tostring(d.cfg[key]) end
    end
    lines[#lines+1]=string.format('  read %.1f ms | preview elapsed %.1f ms / work %.1f ms | native apply %.1f ms | steps %d | max step %.2f ms',
      d.read_ms or 0,d.compute_ms or 0,d.preview_work_ms or 0,d.apply_ms or 0,d.preview_ticks or 0,d.max_step_ms or 0)
    lines[#lines+1]=string.format('  audio analyses %d | shared analysis reuses %d | session save %.1f ms / count %d',
      d.analysis_count or 0,d.analysis_reuses or 0,d.save_ms or 0,d.save_count or 0)
    lines[#lines+1]=string.format('  chain %s | detector cache reuses %d | PCM %.1f MiB / %d blocks',
      d.cfg.chain_order or '',d.follower_reuses or 0,d.pcm and d.pcm.bytes/1048576 or 0,d.pcm and #d.pcm.blocks or 0)
    lines[#lines+1]='  unchanged stage reuses '..tostring(d.stage_reuses or 0)
    local bypassed={};for mode in pairs(d.bypassed or {})do bypassed[#bypassed+1]=mode end;table.sort(bypassed)
    lines[#lines+1]=string.format('  bypassed %s | kept baselines %d',#bypassed>0 and table.concat(bypassed,',') or 'none',#(d.baselines or {}))
    local stats=d.audio and d.audio.analysis_stats
    if stats then lines[#lines+1]=string.format('  DSP %s | accessor %.1f ms | validation %.1f ms | features %.1f ms | EEL kernel %.1f ms',
      stats.backend,stats.read_ms,stats.validation_ms,stats.feature_ms,stats.kernel_ms) end
    if engine and engine.cleanup_dsp and engine.cleanup_dsp.reason then lines[#lines+1]='  DSP fallback: '..engine.cleanup_dsp.reason end
    lines[#lines+1]=string.format('  candidates %d | points %d | applied %s | pending %s | stale %s',
      d.detected and #(self.mode=='breath' and d.detected.breaths or d.detected.sibilants or {}) or 0,d.envelope_points or 0,tostring(d.applied or false),tostring(d.want_apply or false),tostring(d.stale or false))
    local positive,negative=0,0
    for _,e in ipairs(d.breath_profile and d.breath_profile.examples or {}) do
      if e.kind==1 then positive=positive+1 else negative=negative+1 end
    end
    local breath_input=d.stage_cache and d.stage_cache.breath and d.stage_cache.breath.input or d.audio
    lines[#lines+1]=string.format('  learned breaths %d | keep sounds %d | feature cache %s | model cache %s',positive,negative,
      tostring(breath_input and breath_input.breath_features~=nil or false),tostring(breath_input and breath_input.breath_model_scores~=nil or false))
    local model=breath_input and breath_input.breath_model_scores
    if model then lines[#lines+1]=string.format('  breath inference elapsed %.1f ms | kernel %.1f ms',model.elapsed_ms or 0,model.kernel_ms or 0) end
    for k,e in ipairs(d.detected and d.detected.breaths or {}) do if k<=60 then
      lines[#lines+1]=string.format('  breath %.3f..%.3f | score %.3f | level %.1f dBFS | cut %.1f dB | excluded %s',
        e.start,e.finish,e.score,e.level_db or 0,e.reduction,tostring(e.excluded))
      if e.parts or e.core_start~=e.start or e.core_finish~=e.finish then
        lines[#lines+1]=string.format('    seed %.3f..%.3f | joined parts %d',e.core_start or e.start,e.core_finish or e.finish,e.parts or 1)
      end
    end end
  end
  if self.error then lines[#lines+1]=self.error end
  return table.concat(lines,'\n')
end
return M
