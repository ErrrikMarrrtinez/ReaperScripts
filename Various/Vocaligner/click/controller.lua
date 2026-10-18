-- @noindex
local import=...;local SE=import('click/sample_edits');local Wave=import('click/wave')
local Detector=import('click/detector');local Spectral=import('click/spectral');local Repair=import('click/repair');local Job=import('job')
local M={};M.__index=M
local Diagnostics=import('click/diagnostics');local Session=import('click/session')
function M.new(r,engine,fft,repair)
 local cfg={};for k,v in pairs(import('click/settings').defaults)do cfg[k]=v end
 return setmetatable({r=r,engine=engine,fft=fft,repair=repair,cfg=cfg,mode='click',events={},message='Select one audio item and analyze.',excluded={}},M)
end
function M:cancel()if self.job then self.job:cancel();self.job=nil end end
function M:launch(fn,done,operation)
 self:cancel();self.error=nil
 self.recent_diagnostics=self.recent_diagnostics or {}
 if self.diag then table.insert(self.recent_diagnostics,self.diag:summary());if #self.recent_diagnostics>3 then table.remove(self.recent_diagnostics,1)end end
 self.diag=Diagnostics.new(self.r,operation or 'preview');self.diag:mark('start');self.job=Job.new(self.r,fn,self.budget or .025);self.finished=done
end
function M:fail(why)
 self.after_restore=nil
 self.error=tostring(why);self.message='Operation stopped; see error below.'
 if self.diag then self.diag:save(self.error)end
 self.last_failure=self.diag and self.diag:summary() or self.error
 if self.r.ShowConsoleMsg then self.r.ShowConsoleMsg(self:diagnostics()..'\n')end
end
function M:diagnostics()
 local lines={('DECLICK mode=%s ready=%s candidates=%d skipped=%d'):format(self.mode,tostring(self.ready),#self.events,self.skipped or 0)}
 if self.s then lines[#lines+1]=('source=%s | rate=%d channels=%d offset_samples=%d frames=%d'):format(self.s.path,self.s.sr,self.s.channels,self.s.first,self.s.count)end
 for _,control in ipairs(import('click/settings').controls[self.mode])do lines[#lines+1]=control[1]..'='..tostring(self.cfg[control[1]])end
 for _,summary in ipairs(self.recent_diagnostics or {})do lines[#lines+1]=summary end
 if self.diag then lines[#lines+1]=self.diag:summary()end
 if self.work_ms then lines[#lines+1]=('Job active time: %.1f ms | longest deferred step: %.1f ms'):format(self.work_ms,self.max_step_ms or 0)end
 if self.last_failure and not self.error then lines[#lines+1]='LAST FAILURE:\n'..self.last_failure end
 if self.error then lines[#lines+1]='ERROR: '..self.error end
 return table.concat(lines,'\n')
end
function M:tick()
 if self.job then
  self.job:step()
  if self.job.done then
   local j=self.job;self.job=nil
   self.work_ms=j.work_ms;self.max_step_ms=j.max_step_ms
   if j.error then self:fail(j.error)
   else self.diag:mark('complete');self.diag.snapshots={};self.finished(j.result)end
  end
 elseif self.pending and self.r.time_precise()>=self.pending then self.pending=nil;self:preview()
 elseif self.apply_due and not self.hold and not self.pending then
  self.apply_due=nil;if self.ready and not self.bypassed then self:apply(false) end
 end
end
function M:request()
 self:cancel();self.ready=false;self.pending=self.r.time_precise()+.15
end
local function readpcm(pcm,first,count)
 local out={};local last=first+count
 local index=math.floor(first/pcm.block_size)+1
 while first<last do
  local b=assert(pcm.blocks[index]);local n=math.min(last-first,b.first+b.count-first)
  local values=b.buffer.table((first-b.first)*pcm.channels+1,n*pcm.channels)
  for _,v in ipairs(values)do out[#out+1]=v end
  first=first+n;index=index+1
 end
 return out
end
-- Analyze со сбросом: сначала снимаем все правки этой сессии (item возвращается к исходному), затем новый анализ.
-- Без этого новый анализ взял бы уже исправленные сэмплы как исходные.
-- Продолжить работу после перезапуска скрипта: настройки и состояние из сохранённой сессии, затем анализ.
function M:resume(saved)
 if type(saved.cfg)=='table' then for k,v in pairs(saved.cfg) do if self.cfg[k]~=nil and type(v)==type(self.cfg[k]) then self.cfg[k]=v end end end
 if saved.mode=='click' or saved.mode=='mouth' then self.mode=saved.mode end
 self.bypassed=saved.bypassed==true
 self.resume_excluded=type(saved.excluded)=='table' and saved.excluded or nil
 self:analyze()
end
function M:reset_and_analyze()
 self.bypassed=false;self.error=nil
 if self.s and next(self.s.owned or {}) then
  self.after_restore=function() self:analyze() end
  self:apply(true)
 else self:analyze() end
end
function M:analyze()
 self.pending=nil;self.ready=false
 self:launch(function(job)
  local r=self.r
  local s=job:call(function()
   local project=r.EnumProjects(-1,'');assert(r.CountSelectedMediaItems(project)==1,'Select exactly one audio item for the prototype')
   local item=r.GetSelectedMediaItem(project,0);local take=r.GetActiveTake(item);assert(take and not r.TakeIsMIDI(take),'An audio take is required')
   assert(r.GetTakeNumStretchMarkers(take)==0,'Stretch markers are not supported by this prototype')
   assert(r.GetMediaItemTakeInfo_Value(take,'D_PLAYRATE')==1,'Use a take with playback rate 1.0 for this prototype')
   assert(r.GetMediaItemTakeInfo_Value(take,'D_PITCH')==0,'Pitched takes are not supported by this prototype')
   assert(r.GetMediaItemTakeInfo_Value(take,'I_CHANMODE')==0,'Use the original source channel mode')
   local src=r.GetMediaItemTake_Source(take);assert(not r.GetMediaSourceParent(src),'Section/reversed sources are unsupported')
   local _,guid=r.GetSetMediaItemTakeInfo_String(take,'GUID','',false)
   local ok,chunk=r.GetItemStateChunk(item,'',false);assert(ok,'Cannot read item state')
   local s={project=project,item=item,guid=guid,expected=chunk,baseline=SE.parse(chunk,guid),owned={},
    path=r.GetMediaSourceFileName(src,''),offset=r.GetMediaItemTakeInfo_Value(take,'D_STARTOFFS'),
    len=r.GetMediaItemInfo_Value(item,'D_LENGTH'),pos=r.GetMediaItemInfo_Value(item,'D_POSITION')}
   -- Правки прошлого запуска скрипта (сессия REAPER): наши точки — не исходник. Под ними возвращаем то,
   -- что было до нас, а сами точки помечаем своими, чтобы следующая запись их заменила, а сброс снял.
   local saved=Session.load(r,guid)
   if saved and saved.path==s.path and type(saved.owned)=='table' then
    for ch,pts in pairs(saved.owned) do
     s.baseline.channels[ch]=s.baseline.channels[ch] or {}
     local base=type(saved.base)=='table' and saved.base[ch] or {}
     for idx in pairs(pts) do s.baseline.channels[ch][idx]=base[idx] end
    end
    s.owned=saved.owned
   end
   return s
  end)
  self.diag:mark('read source WAV');local w=Wave.open(s.path);job.resources[w]=Wave.close
  assert(not s.baseline.rate or s.baseline.rate==w.sr,'Sample edit rate differs from source')
  assert(not s.baseline.a or s.baseline.a=='1' and s.baseline.b=='1','Enable existing sample edits before analysis')
  -- Item может выходить за источник (растянут за конец файла, сдвинут левее начала): анализируем и правим только
  -- ту часть, где есть настоящие отсчёты исходника; индексы SAMPLEEDITS и время считаются от неё.
  local first=math.ceil(s.offset*w.sr-1e-7);local last=math.min(w.frames,math.floor((s.offset+s.len)*w.sr+1e-7))
  first=math.max(0,first)
  assert(last-first>=128,('The part of the item inside its source file is too short (%d samples; item offset %.3f s, length %.3f s, source %.3f s)')
    :format(math.max(0,last-first),s.offset,s.len,w.frames/w.sr))
  s.pos=s.pos+(first/w.sr-s.offset);s.first=first;s.count=last-first;s.len=s.count/w.sr
  assert(s.count*w.channels*8<=64*1024*1024,'Prototype PCM cache limit is 64 MB; split the item')
  assert(s.count/w.sr<=30,'Prototype analysis limit is 30 seconds per item; split longer items')
  s.sr,s.channels,s.source_frames=w.sr,w.channels,w.frames
  local pcm={sr=w.sr,channels=w.channels,len=s.count/w.sr,frames=s.count,blocks={},block_size=math.floor(32768/w.channels)}
  for first=0,s.count-1,pcm.block_size do
   local n=math.min(pcm.block_size,s.count-first);local values,raw=w:read(s.first+first,n,s.baseline)
   local buffer=job:call(r.new_array,values);pcm.blocks[#pcm.blocks+1]={first=first,count=n,buffer=buffer,source_bytes=raw}
   job:checkpoint(first/s.count,'Reading source PCM')
  end
  self.diag:mark('EEL waveform features');s.pcm=pcm;s.data=Detector.features(pcm,self.engine,job);return s
 end,function(s)self.s=s;self.excluded=self.resume_excluded or {};self.resume_excluded=nil;self:request();self.message='Source analyzed; locating candidates.'end,'analyze')
end
function M:preview()
 if not self.s then return end
 local s,mode=self.s,self.mode;local cfg={};for k,v in pairs(self.cfg)do cfg[k]=v end
 self:launch(function(job)
  local events
  if mode=='mouth' and Detector.mouth_method=='transient' then
   -- Mouth: короткий локальный контраст (без FFT и без длинного контекста), см. Detector.mouth_events
   self.diag:mark('mouth transient contrast / candidates');events=Detector.mouth_events(s.data,cfg,{},job,self.engine)
  else
   self.diag:mark('context / candidate scores');local key=mode..':'..cfg[mode..'_skew']..':'..cfg[mode..'_protect']
   s.scores=s.scores or {};local cached=s.scores[mode]
   if not cached or cached.key~=key then cached={key=key,value=Detector.score(s.data,mode,cfg[mode..'_skew'],cfg[mode..'_protect'],job,self.engine)};s.scores[mode]=cached end
   self.diag:mark('spectral analysis / candidate selection')
   if mode=='mouth' then events=Spectral.events(Spectral.ensure(s.pcm,self.fft,job,self.engine),s.data,cached.value,cfg,{},job)
   else events=Detector.events(s.data,cached.value,cfg,mode,{},job)end
  end
  for _,e in ipairs(events)do for _,x in ipairs(self.excluded[mode] or {})do if x.finish>e.start and x.start<e.finish then e.excluded=true end end end
  -- Выделенный диапазон (секунды от начала item) ограничивает правку: события вне него не трогаем.
  local range=self.range
  if range then for _,e in ipairs(events)do if e.finish<=range[1] or e.start>=range[2] then e.excluded=true;e.outside=true end end end
  self.diag:mark('EEL repair / patch build');local patch,skipped=Repair.build(self.repair,function(first,count)return job:call(readpcm,s.pcm,first,count)end,
   events,cfg,mode,s.sr,s.channels,s.count,s.first,job,(function() s.repair_cache=s.repair_cache or {};s.repair_cache[mode]=s.repair_cache[mode] or {};return s.repair_cache[mode] end)())
  return {events=events,patch=patch,skipped=skipped,mode=mode}
 end,function(result)
  self.events,self.patch,self.skipped,self.preview_mode=result.events,result.patch,result.skipped,result.mode
  self.ready=true;self.message=('%d candidates; %d repairs skipped (context/length). Preview ready.'):format(#result.events,result.skipped)
  -- Живое применение: каждое готовое превью сразу пишется в проект, если стадия не выключена.
  -- Пока слайдер зажат (hold), только превью; запись в проект — по отпусканию (без потока Undo и подвисаний).
  if self.auto_apply and not self.bypassed then if self.hold then self.apply_due=true else self:apply(false) end end
 end)
end
-- Вкл/выкл стадии (тоггл плитки): выкл снимает правку этой сессии, вкл снова применяет текущее превью.
function M:set_bypass(on)
 if not self.s then self.bypassed=on;return end
 self.bypassed=on
 if on then
  if next(self.s.owned or {}) then self:apply(true) end
 elseif self.ready then self:apply(false)
 else self:request() end
end
function M:exclude(index)
 local e=self.events[index];if not e then return end
 self.excluded[self.mode]=self.excluded[self.mode] or {};local list=self.excluded[self.mode]
 if e.excluded then for i=#list,1,-1 do if list[i].finish>e.start and list[i].start<e.finish then table.remove(list,i)end end
 else list[#list+1]={start=e.start,finish=e.finish}end
 self:request()
end
function M:apply(restore)
 assert(self.s and (restore or self.ready),'No valid repair preview')
 local s=self.s;local desired=restore and {} or self.patch;local preview_ready=self.ready
 self.pending=nil;self.ready=false
 self:launch(function(job)
  assert(SE.supported(self.r.GetAppVersion()),'Sample repair requires REAPER 7.71 or newer')
  -- Re-read the immutable source before writing. No plugin/accessor samples are baked in.
  self.diag:mark('verify original source bytes');local w=Wave.open(s.path);job.resources[w]=Wave.close
  assert(w.frames==s.source_frames and w.channels==s.channels and w.sr==s.sr,'Source format changed; analyze again')
  for _,b in ipairs(s.pcm.blocks)do
   assert(w:read_raw(s.first+b.first,b.count)==b.source_bytes,'Source audio changed; analyze again')
   job:checkpoint(nil,'Verifying source')
  end
  -- Проверка, сборка и запись — один вызов без yield: между ними REAPER не может изменить item.
  self.diag:mark('verify, serialize and write SAMPLEEDITS');local count=job:call(function()
   assert(self.r.ValidatePtr2(s.project,s.item,'MediaItem*'),'Item no longer exists')
   local ok,text=self.r.GetItemStateChunk(s.item,'',false);assert(ok,'Cannot read item')
   self.diag.snapshots.expected=s.expected;self.diag.snapshots.current=text
   if not(text==s.expected or SE.same_item(text,s.expected,s.guid))then error('Item changed; analyze again\n'..Diagnostics.difference(s.expected,text),0)end
   local replacement,count,wanted=SE.build(text,s.guid,s.sr,s.channels,s.source_frames,desired,s.owned,s.baseline)
   local actual,parsed=SE.commit(self.r,s.project,s.item,text,replacement,s.guid,desired,self.diag,wanted)
   parsed=parsed or SE.parse(actual,s.guid);local owned={}
   for ch,pts in pairs(desired)do owned[ch]={};for idx in pairs(pts)do owned[ch][idx]=SE.get(parsed,ch,idx)end end
   s.expected,s.owned=actual,owned
   return count
  end)
  return count
 end,function(count)self.ready=preview_ready;self.applied=not restore;self.message=restore and 'This session\'s sample repair restored.' or ('Applied %d source samples. REAPER Undo is available.'):format(count)
  pcall(function() Session.save(self.r,s.guid,Session.state(self)) end) -- переживёт перезапуск скрипта
  if restore and self.after_restore then local next_step=self.after_restore;self.after_restore=nil;next_step() end
 end,restore and 'restore' or 'apply')
end
return M
