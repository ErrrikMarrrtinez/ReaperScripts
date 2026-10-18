-- @noindex
local import=...;local Audio=import('audio');local Analysis=import('pitch/analysis');local Store=import('pitch/store');local Algorithm=import('pitch/algorithm');local Workspace=import('pitch/workspace')
local Expression=import('pitch/expression');local Scale=import('pitch/scale');local Notes=import('pitch/notes');local Curve=import('pitch/curve');local FX=import('pitch/fx');local Job=import('job');local M={};M.__index=M
local function restore_after_failure(r,item,chunk,why)
  -- Rollback may itself raise (for example, a pointer invalidated by a host
  -- callback). Keep that error inside the UI/Undo cleanup path too.
  local ok,restored=pcall(r.SetItemStateChunk,item,chunk,false)
  if not ok or not restored then return tostring(why)..'\nRollback failed; use REAPER Undo.'..(not ok and '\n'..tostring(restored) or '')end
  return why
end
function M.new(app)
  return setmetatable({app=app,r=app.r,selected={},snap=false,root=0,scale=1,tool='notes',hold_ms=100,cache={},message='Select audio items or a track, then Analyze.'},M)
end
function M:fail(why)
  self.error=tostring(why);self.message=self.error
  if self.last_reported_error~=self.error then self.app:report('Pitch: '..self.error);self.last_reported_error=self.error;if self.app.console then self.app:console('Vocaligner Pitch error',self.error)end end
end
function M:measure(key,started)
  local ms=(self.r.time_precise()-started)*1000
  self.performance=self.performance or {};local p=self.performance[key] or {count=0,total=0,max=0}
  p.count=p.count+1;p.total=p.total+ms;p.last=ms;p.max=math.max(p.max,ms);self.performance[key]=p
  p.samples=p.samples or {};p.samples[#p.samples+1]=ms;if #p.samples>128 then table.remove(p.samples,1) end
  return ms
end
function M:cancel()
  -- A native insertion is atomic. Finish its pending coroutine reply instead
  -- of presenting an already committed take as a cancelled render.
  if self.job and self.job.committed then self:tick();return end
  if self.job then self.job:cancel();self.job=nil;self.partial=nil end
  self:cancel_gesture();self:refresh(true)
end
function M:cancel_gesture()
  local before=self.drag and self.drag.before or self.control_before
  if before then self.state=before;self.notes=before.notes;self.display=nil end
  self.drag=nil;self.control_before=nil;self.control_key=nil;self.gesture=false
end
function M:busy() return self.job~=nil or self.app.job~=nil or self.app.cleaner.job~=nil end
function M:remember(project,id,cached)
  self.cache_clock=(self.cache_clock or 0)+1;cached.touch=self.cache_clock
  self.cache[project]=self.cache[project] or {};self.cache[project][id]=cached
  local count=0;local entries={}
  for p,values in pairs(self.cache) do
    if not Audio.project_open(self.r,p) then self.cache[p]=nil
    else for key,value in pairs(values) do count=count+#value.data.frames;entries[#entries+1]={p=p,key=key,value=value} end end
  end
  table.sort(entries,function(a,b)return (a.value.touch or 0)<(b.value.touch or 0) end)
  for _,entry in ipairs(entries) do if count<=120000 then break end
    self.cache[entry.p][entry.key]=nil;count=count-#entry.value.data.frames
  end
end
function M:refresh(force)
  local r=self.r;local project=r.EnumProjects(-1)
  if not project then return end
  local previous_track=self.track;local previous_pos=self.snapshot and self.snapshot.pos
  local item=Workspace.focus(self,project)
  if not item then
    self:cancel_gesture()
    self.no_selection=true;self.project=project;self.item=nil;self.take=nil;self.snapshot=nil;self.data=nil;self.notes={};self.state=nil;self.selected={};self.view=nil;self.display=nil
    self.partial=nil;self.prepared_cache=nil;self.contour_cache=nil;self.source_display=nil;self.glyphs=nil;self.saved_text=nil
    self.algorithm_value=nil;self.algorithm_error=nil;self.last_analysis=nil;self.last_analysis_id=nil
    self.error=nil;self.stale=nil;self.last_reported_error=nil;self.vocal_origin=nil
    self.message=self.track_row and #self.track_row.items==0 and 'No audio items on this track.' or 'Select audio items or a track, then Analyze.'
    return
  end
  local take=r.GetActiveTake(item);if not take or r.TakeIsMIDI(take) then self.no_selection=true;return end
  self.no_selection=nil
  local count=r.GetProjectStateChangeCount(project)
  if not force and project==self.project and item==self.item and take==self.take and count==self.project_count then return end
  if self.gesture or self.job then return end
  local refresh_started=r.time_precise()
  local ok,why=pcall(function()
    local s=Analysis.capture(r,project,item)
    -- Recreated pointers after Undo still identify the same edited take.
    local changed=project~=self.project or not self.snapshot or s.guid~=self.snapshot.guid
    local state,text=Store.read(r,take)
    self.vocal_origin=import('pitch/vocal_render').origin(r,take)
    self.snapshot=s;self.project=project;self.item=item;self.take=take
    self.error=nil;self.stale=nil
    if state then
      local valid,reason=FX.rebind(r,s,state);if not valid then self.stale=true;self.error=reason end
      self.cache[project]=self.cache[project] or {}
      local cached=self.cache[project][state.analysis]
      if not cached then local data,geometry=Store.load_analysis(r,project,state.analysis);if data then cached={data=data,geometry=geometry};self:remember(project,state.analysis,cached) end end
      local data,notes
      if cached then data,reason=Store.adapt(cached.data,{},cached.geometry,s) end
      if data then
        local _,mapped=Store.adapt({frames={},hop=data.hop,len=state.geometry.len,model=data.model},state.notes,state.geometry,s)
        if type(mapped)=='table' then
          notes=mapped;for _,n in ipairs(notes)do n.last=math.min(#data.frames,math.ceil(n.finish/data.hop)) end
        else self.stale=true;self.error=mapped end
      else self.stale=true;self.error=reason or 'Saved analysis is missing. Analyze again to rebuild it.' end
      self.data=data;self.notes=notes or state.notes;state.notes=self.notes;if valid then state.geometry=Store.geometry(s) end;self.state=state
      self.message=self.error or string.format('%d notes · %s',#self.notes,s.name)
    else
      self.data=nil;self.notes={};self.state={version=1,notes=self.notes,geometry=Store.geometry(s)}
      self.message=s.name
    end
    if self.state.scale then self.root=self.state.scale.root;self.scale=self.state.scale.mode;self.snap=self.state.scale.snap==true end
    self.algorithm_error=nil
    if self.state.fx_guid then
      local fx=FX.find(r,take,self.state.fx_guid)
      local info,why;if fx then info,why=Algorithm.read(r,take,fx) end
      self.algorithm_value=info and info.value;self.algorithm_error=not info and why or nil
    else self.algorithm_value=self.state.algorithm or Algorithm.default(r) end
    if self.last_analysis_id~=self.state.analysis then
      self.last_analysis=Notes.copy(self.state.analysis_stats);self.last_analysis_id=self.state.analysis
    end
    self.saved_text=text;self.peaks=Audio.peaks(r,s);self.display=nil
    self.last_reported_error=nil
    if changed then
      self.selected={};self.prepared_cache=nil;self.contour_cache=nil
      if previous_track and previous_track==self.track and self.view and previous_pos then
        self.view.start=self.view.start+previous_pos-s.pos
      else self.fit_pending=true end
    end
  end)
  self.project_count=count
  self:measure('refresh',refresh_started)
  if not ok then self.snapshot=nil;self.data=nil;self.notes={};self:fail(why) end
end
function M:analyze(mode,items)
  return import('pitch/batch').start(self,mode,items or Workspace.targets(self))
end
function M:activate(item)return Workspace.activate(self,item) end
function M:reset_all(items,clear)
  if self:busy() or self.gesture or self.no_selection then return end
  local r=self.r;local project=r.EnumProjects(-1);items=items or {self.item}
  self.job=Job.new(r,function(job)
    for i,item in ipairs(items) do
      job:call(function()
        local s=Analysis.capture(r,project,item);local state=Store.read(r,s.take)
        if not state then return end
        local ok,chunk=r.GetItemStateChunk(item,'',false);assert(ok,'Cannot snapshot Pitch reset')
        r.Undo_BeginBlock2(project);r.PreventUIRefresh(1)
        local success,why=xpcall(function()
          FX.remove(r,s,state)
          for _,n in ipairs(state.notes)do Expression.reset(n);n.formant=0 end
          Store.write(r,s.take,not clear and state or nil) -- clear: полный сброс, анализ item забывается
        end,debug.traceback)
        if not success then why=restore_after_failure(r,item,chunk,why)end
        r.PreventUIRefresh(-1);r.Undo_EndBlock2(project,'Vocaligner: reset pitch corrections',-1);r.UpdateArrange();assert(success,why)
      end)
      job:checkpoint(i/#items,'Reset pitch corrections')
    end
  end,.008)
  self.job.kind='reset';self.prepared_cache=nil;self.error=nil;if clear then self.view=nil;self.fit_pending=true end
end
function M:begin_edit(keep_version)
  if self:busy() or self.stale or not self.data or self.no_selection then return nil end
  local before=Notes.copy(self.state);if not keep_version then self.state.curve_version=4 end;self.display=nil;self.gesture=true;return before
end
function M:commit(before,label,mode)
  self.gesture=false;if not before or self:busy() then return end
  local s=self.snapshot;local saved=self.saved_text;local state=Notes.copy(self.state)
  self.display=nil
  self.job=Job.new(self.r,function(job)
    local prepared;if not mode then
      local began=self.r.time_precise()
      prepared,job.prepared_cache=FX.prepare(state.notes,s.len,job,state.curve_version or 1,self.data,self.prepared_cache)
      job.prepare_elapsed_ms=self:measure('prepare_elapsed',began)
      job.pitch_points=#prepared.pitch;job.formant_points=#prepared.formant
      job.rebuilt_cells=job.prepared_cache.rebuilt_cells;job.reused_cells=job.prepared_cache.reused_cells
    end
    job:call(function()
      local native_started=self.r.time_precise()
      local current,why=Analysis.check(self.r,s);assert(current,why)
      local _,text=Store.read(self.r,s.take);assert(text==saved,'Pitch item changed before applying')
      local ok,chunk=self.r.GetItemStateChunk(s.item,'',false);assert(ok,'Cannot create Pitch rollback snapshot')
      self.r.Undo_BeginBlock2(s.project);self.r.PreventUIRefresh(1)
      local success,err=xpcall(function()
        if mode=='remove' then
          FX.remove(self.r,s,state)
          for _,n in ipairs(state.notes) do Expression.reset(n);n.formant=0 end
        elseif mode=='bypass' then
          local fx=assert(FX.find(self.r,s.take,state.fx_guid),'No Pitch FX to compare')
          self.r.TakeFX_SetEnabled(s.take,fx,not self.r.TakeFX_GetEnabled(s.take,fx))
          state.bypassed=not self.r.TakeFX_GetEnabled(s.take,fx)
          state.fx_fingerprint=FX.fingerprint(self.r,s.take,fx);state.fx_static=FX.fingerprint(self.r,s.take,fx,true)
        elseif mode=='metadata' then
          -- Segmentation-only edits do not add an inaudible FX.
        elseif mode=='algorithm' then
          FX.set_algorithm(self.r,s,state,Notes.copy(before))
        else
          self.last_native_write=FX.apply(self.r,s,state,prepared)
        end
        state.geometry=Store.geometry(current)
        local save_started=self.r.time_precise();Store.write(self.r,s.take,state);self:measure('save_state',save_started)
      end,debug.traceback)
      if not success then err=restore_after_failure(self.r,s.item,chunk,err)end
      self.r.PreventUIRefresh(-1);self.r.Undo_EndBlock2(s.project,'Vocaligner: '..label,-1);self.r.UpdateArrange()
      self:measure('native_transaction',native_started)
      assert(success,err)
    end)
  end,.008)
  self.job.kind='apply';self.job.before=before;self.error=nil
end
function M:remove()
  if self:busy() or not self.state or self.no_selection then return end
  self:commit(Notes.copy(self.state),'remove pitch edits','remove')
end
function M:set_algorithm(value)
  if self:busy() or self.gesture or self.no_selection or self.stale or not self.snapshot or not self.data then return end
  if not Algorithm.valid(self.r,value) then self:fail('The selected ReaPitch algorithm is unavailable');return end
  if self.algorithm_value==value then return end
  local before=Notes.copy(self.state);self.state.algorithm=value
  self:commit(before,'set ReaPitch algorithm','algorithm')
end
function M:export_case()
  if self:busy() or self.gesture then return end
  self:refresh(true);if self.no_selection or not self.data then self:fail('Analyze the selected item before exporting a case.');return end
  local Export=import('pitch/case_export')
  self.job=Job.new(self.r,function(job)
    local case,chunk=job:call(Export.capture,self)
    local suffix=os.date('%Y%m%d-%H%M%S')..'-'..Store.hash(case.source.guid..tostring(self.r.time_precise()))
    local folder=self.r.GetResourcePath()..'/Data/VocalignerPitchCases/'..suffix
    job:call(self.r.RecursiveCreateDirectory,folder,0)
    local path=Export.write(self,folder,case,chunk,job)
    job:call(function()self.r.ShowConsoleMsg('Pitch case saved: '..path..'\n')end)
    return path
  end,.008)
  self.job.kind='export';self.error=nil
end
function M:render_vocal(im,ctx)
  if self:busy() or self.gesture or self.stale or self.no_selection or not self.data then return end
  self.vocal_view={guid=self.snapshot.guid,view=Notes.copy(self.view),selected=Notes.copy(self.selected)}
  self.job=Job.new(self.r,function(job)return import('pitch/vocal_render').run(self,im,ctx,job)end,.008)
  self.job.kind='vocal_render';self.error=nil
end
function M:edit_vocal_source()
  if self:busy() or self.gesture or not self.vocal_origin or not self.item then return end
  local take=import('pitch/vocal_render').find_source(self.r,self.item,self.vocal_origin)
  if not take then self:fail('The original vocal take was removed from this item.');return end
  self.r.Undo_BeginBlock2(self.project);self.r.SetActiveTake(take)
  self.r.Undo_EndBlock2(self.project,'Vocaligner: edit original vocal take',-1);self.r.UpdateArrange();self:refresh(true)
  self:restore_vocal_view()
end
function M:restore_vocal_view()
  local saved=self.vocal_view
  if saved and self.snapshot and self.snapshot.guid==saved.guid then
    self.view=saved.view or self.view;self.selected=saved.selected or {};self.fit_pending=nil;self.vocal_view=nil
  end
end
function M:compare()
  if self.state and self.state.fx_guid and not self.stale and not self.no_selection then self:commit(Notes.copy(self.state),'compare original pitch','bypass') end
end
function M:has_selection() for _,selected in pairs(self.selected) do if selected then return true end end;return false end
function M:reset_selected()
  if not self:has_selection() then return end
  local before=self:begin_edit();if not before then return end
  for _,n in ipairs(self.notes) do if self.selected[n.id] then Expression.reset(n);n.formant=0 end end
  self:commit(before,'reset selected pitch')
end
function M:split(t)
  local _,index=Notes.at(self.notes or {},t);if not index then return end
  local before=self:begin_edit(true);if not before then return end
  local function target(at)
    local raw=Expression.sample(self.data,at)
    return (raw or self.notes[index].center)+Curve.at(before.notes,at,'shift',before.curve_version or 1,self.data)
  end
  local ok,right=Notes.split(self.notes,index,t,self.data,target)
  if ok then
    self.selected={[right.id]=true}
    -- Identical children evaluate as their original parent; native FX points
    -- remain byte-for-byte unchanged. No legacy curve upgrade on plain Split.
    self:commit(before,'split pitch note','metadata')
  else self.state=before;self.notes=before.notes;self.display=nil;self.gesture=false end
end
function M:join(index)
  local before=self:begin_edit();if not before then return end
  local joined,why=Notes.join(self.notes,index)
  local mode;if not self.state.fx_guid then mode='metadata' end
  if joined then self:commit(before,'join pitch notes',mode)
  else self.state=before;self.notes=before.notes;self.display=nil;self.gesture=false;if why then self:fail(why) end end
end
function M:undo(redo)
  if self:busy() or not self.project then return end
  local project,guid=self.project,self.snapshot and self.snapshot.guid
  local vocal_origin=self.vocal_origin;local source_view
  if self.last_vocal and self.last_vocal.source_guid==guid then source_view={guid=guid,view=Notes.copy(self.view),selected=Notes.copy(self.selected)}end
  local can=redo and self.r.Undo_CanRedo2 or self.r.Undo_CanUndo2
  local description=can and can(project) or nil
  local result;if redo then result=self.r.Undo_DoRedo2(project) else result=self.r.Undo_DoUndo2(project)end
  local rebound=Workspace.restore_focus(self,project,guid)
  if not rebound and vocal_origin then rebound=Workspace.restore_focus(self,project,vocal_origin)end
  if not rebound and source_view then rebound=Workspace.restore_focus(self,project,self.last_vocal.rendered_guid)end
  self:refresh(true)
  if source_view and self.vocal_origin==source_view.guid then self.vocal_view=source_view end
  self:restore_vocal_view()
  self.last_undo={redo=redo==true,description=description,result=result,guid=guid,rebound=rebound,
    notes=#(self.notes or {}),analysis=self.state and self.state.analysis,restored_guid=self.snapshot and self.snapshot.guid}
end
function M:tick()
  if self.job then
    local job=self.job;job:step()
    if job.done then
      self.job=nil;self.partial=nil;self.gesture=false
      if self.last_analysis and job.kind=='analysis' then self.last_analysis.max_step_ms=job.max_step_ms;self.last_analysis.work_ms=job.work_ms;self.last_analysis.steps=job.steps end
      if job.kind=='apply' then
        self.last_apply={work_ms=job.work_ms,max_step_ms=job.max_step_ms,steps=job.steps,elapsed_ms=(self.r.time_precise()-job.created_at)*1000,
          pitch_points=job.pitch_points,formant_points=job.formant_points,rebuilt_cells=job.rebuilt_cells,reused_cells=job.reused_cells}
        if not job.error and job.prepared_cache then self.prepared_cache=job.prepared_cache end
      end
      self:refresh(true)
      if job.kind=='analysis' and self.batch_result then
        local b=self.batch_result;self.message=string.format('Analyzed %d / %d items%s',b.completed,b.total,b.failed>0 and ('; '..b.failed..' skipped — Copy report') or '')
        if b.failed>0 then self.error=b.errors[1] end
      end
      if job.kind=='export' and not job.error then self.last_case=job.result;self.message='Pitch case saved: '..job.result end
      if job.kind=='vocal_render' and not job.error then
        self.last_vocal=job.result;self.last_vocal.work_ms=job.work_ms;self.last_vocal.max_step_ms=job.max_step_ms
        self.message='Vocal render is the active take. Edit source returns to the original notes; Undo removes this take.'
      end
      if job.error then self:fail(job.error) end
    end
  elseif self.app.tab=='pitch' then self:refresh() end
end
function M:diagnostics()
  local lines={'PITCH: '..(self.engine and self.engine.label or 'not initialized'),self.message or ''}
  lines[#lines+1]='Display: predicted source F0 + requested correction; yellow Check line = measured output when enabled.'
  if self.last_vocal then local v=self.last_vocal;lines[#lines+1]=string.format('Vocal render v%d: %d regions, %d source / %d output periods, %.0f ms work, %.1f ms max step; %s',v.version,v.regions,v.source_pulses,v.output_pulses,v.work_ms or 0,v.max_step_ms or 0,v.path)end
  if self.check_on then lines[#lines+1]=import('pitch/check').report(self) end
  if self.last_undo then local u=self.last_undo
    lines[#lines+1]=string.format('Pitch last %s: %s | result %s | focus rebound %s | take %s -> %s | notes %d | analysis %s',
      u.redo and 'Redo' or 'Undo',u.description or 'unknown',tostring(u.result),tostring(u.rebound),u.guid or 'none',u.restored_guid or 'none',u.notes,u.analysis or 'none')
  end
  local strokes=0;for _,n in ipairs(self.notes or {}) do strokes=strokes+#(n.drawings or {}) end
  lines[#lines+1]='Draw strokes: '..strokes
  lines[#lines+1]=string.format('Lua memory: %.1f MiB (includes caches; not a REAPER process memory measurement)',collectgarbage('count')/1024)
  for _,key in ipairs({'canvas','contour','drag','refresh','workspace_scan','prepare_elapsed','native_transaction','save_state'})do
    local p=self.performance and self.performance[key]
    if p then
      local samples=Notes.copy(p.samples or {p.last});table.sort(samples)
      lines[#lines+1]=string.format('Pitch %s: last %.2f ms | avg %.2f | max %.2f | calls %d | recent p50 %.2f / p95 %.2f',key,p.last,p.total/p.count,p.max,p.count,
        samples[math.max(1,math.ceil(#samples*.5))],samples[math.max(1,math.ceil(#samples*.95))])
    end
  end
  if self.last_native_write then for _,key in ipairs({'pitch','formant'})do local p=self.last_native_write[key]
    lines[#lines+1]=string.format('Pitch native %s: inserted %d / removed %d / total %d',key,p.inserted,p.deleted,p.total)
  end end
  if self.last_apply then local p=self.last_apply
    lines[#lines+1]=string.format('Pitch last apply: elapsed %.1f ms | work %.1f | max step %.1f | steps %d | points %d/%d | rebuilt/reused cells %d/%d',
      p.elapsed_ms or 0,p.work_ms or 0,p.max_step_ms or 0,p.steps or 0,p.pitch_points or 0,p.formant_points or 0,p.rebuilt_cells or 0,p.reused_cells or 0)
  end
  if self.engine and self.engine.reason then lines[#lines+1]=self.engine.reason end
  if self.engine and self.engine.fast_reason then lines[#lines+1]='Native dot fallback: '..self.engine.fast_reason end
  if self.engine then lines[#lines+1]='EEL startup check: '..tostring(self.engine.self_test==true) end
  if self.data then
    lines[#lines+1]='Stored model: '..tostring(self.data.model)..' | frames '..#self.data.frames
    local visible,outside=0,0
    local Trace=import('pitch/trace')
    for _,f in ipairs(self.data.frames)do if Trace.sample(self.data,f.t) then
      visible=visible+1;if not Notes.at(self.notes or {},f.t)then outside=outside+1 end
    end end
    lines[#lines+1]=string.format('Pitch visible measured frames: %d | outside note blocks: %d (display and segmentation use different rules)',visible,outside)
  end
  if self.state then lines[#lines+1]='Correction curve: '..tostring(self.state.curve_version or 1)..' | scale '..Scale.roots[(self.root or 0)+1]..' '..Scale.scales[self.scale or 1][1]..' | snap '..tostring(self.snap) end
  local expression_v2,link_v7=0,0
  for _,n in ipairs(self.notes or {})do
    if n.expression_version==2 then expression_v2=expression_v2+1 end
    if n.link and n.link.version==7 then link_v7=link_v7+1 end
  end
  lines[#lines+1]=string.format('Expression v2 notes: %d | Transition v7 links: %d',expression_v2,link_v7)
  if self.algorithm_value then lines[#lines+1]=(self.state and self.state.fx_guid and 'ReaPitch algorithm: ' or 'ReaPitch algorithm for new FX: ')..Algorithm.label(self.r,self.algorithm_value)..' | value '..self.algorithm_value end
  if self.algorithm_error then lines[#lines+1]='ReaPitch algorithm: '..self.algorithm_error end
  if self.track_row then lines[#lines+1]=string.format('Pitch track: %s | items %d | selected items %d',self.track_row.name,#self.track_row.items,#(self.selected_items or {})) end
  if self.state and self.state.mapping then
    for field,map in pairs(self.state.mapping) do lines[#lines+1]=string.format('ReaPitch %s: %.3f .. %.3f st',field,map.lo,map.hi) end
  end
  if self.last_analysis then for k,v in pairs(self.last_analysis) do lines[#lines+1]=k..' = '..tostring(v) end end
  local s=self.snapshot
  if s then lines[#lines+1]='Source: '..tostring(s.source_key) end
  if s then lines[#lines+1]=string.format('take %s | offset %.9f | rate %.9f | length %.9f | stretch markers %d',s.guid,s.offset,s.rate,s.len,#s.markers) end
  for _,n in ipairs(self.notes or {}) do lines[#lines+1]=string.format('note %d: %.3f..%.3f | center %.3f | shift %.3f | formant %.3f | transition %.3f',n.id,n.start,n.finish,n.center,n.shift,n.formant,n.transition)..string.format(' | modulation %.3f | drift %.3f | flat %.3f | vibrato %.3f/%.3f | edge %.3f/%.3f | anchors %d',n.modulation or 1,n.drift or 1,n.flatten or 0,n.vibrato_depth or 0,n.vibrato_rate or 5.5,n.transition_amount or 0,n.transition_shape or 1,#(n.anchors or {})) end
  if self.error then lines[#lines+1]=self.error end
  return table.concat(lines,'\n')
end
function M:set_scale(root,mode,snap)
  if self:busy() or self.gesture then return end
  if snap==nil then snap=self.snap end;snap=snap==true
  self.root,self.scale,self.snap=root,mode,snap
  if not self.data or self.stale or self.no_selection then return end
  local before=Notes.copy(self.state)
  self.state.scale={root=root,mode=mode,snap=snap}
  self:commit(before,'set pitch scale','metadata')
end
function M:parameter(field,value,alt,before)
  local original=before and before.notes or self.notes;local selected={};local sum,weight=0,0
  for _,n in ipairs(original) do if self.selected[n.id] then selected[n.id]=n;local w=n.finish-n.start;sum=sum+(Scale.center(n)+n.shift)*w;weight=weight+w end end
  for i,n in ipairs(self.notes) do if selected[n.id] then
    local old=selected[n.id];Expression.initialize(n)
    if field=='flatten' or field=='modulation' or field=='drift' or field:sub(1,8)=='vibrato_' then Expression.edit(n) end
    if field:sub(1,5)=='link_' then
      if Curve.can_link(self.notes[i-1],n) then
        local L=import('pitch/link');local link=(field=='link_amount' or field=='link_width') and L.edit_tilt(self.notes[i-1],n,self.data) or L.edit(self.notes[i-1],n,self.data);link[field:sub(6)]=value
        if link.version>=5 then link.curve_notes=Curve.capture_anchors(original)end
      end
    elseif field=='shift' then n.shift=Scale.shift(self,n,value,alt)
    elseif field=='flatten' then
      n.flatten=value;n.visual_offset=0
      n.flat_offset=math.max(-48,math.min(48,Scale.pitch(self,sum/math.max(weight,.001),alt)-old.center-old.shift))
      n.shift=Scale.shift(self,n,old.shift,alt)
    else n[field]=value end
    if (field=='transition' or field=='transition_shape' or field=='transition_amount' and value>0) and Curve.can_link(self.notes[i-1],n) then n.transition_link=true end
  end end
  self.display=nil
end
function M:nudge(direction,alt)
  if not self:has_selection() then return end
  local before=self:begin_edit();if not before then return end
  for _,n in ipairs(self.notes) do if self.selected[n.id] then
    local pitch=Scale.center(n)+n.shift
    local target=self.snap and not alt and Scale.next(pitch,direction,self.root,self.scale) or pitch+direction*(alt and .1 or 1)
    n.shift=Scale.shift(self,n,n.shift+target-pitch,alt)
  end end
  self:commit(before,'nudge pitch notes')
end
function M:copy_shape()
  if not self.data then return end
  local n;for _,note in ipairs(self.notes) do if self.selected[note.id] then n=note;break end end;if not n then return end
  local points={};local count=math.max(2,math.min(256,math.ceil((n.finish-n.start)/.016)))
  for i=0,count do local u=i/count;local t=n.start+u*(n.finish-n.start);local raw,_,trust=Expression.sample(self.data,t)
    points[#points+1]={u=u,value=raw and trust>.5 and raw+Curve.at(self.notes,t,'shift',self.state.curve_version,self.data)-Scale.center(n)-n.shift or 0}
  end
  self.shape_clipboard=points;self.message='Pitch shape copied.'
end
function M:paste_shape(alt)
  if not self.shape_clipboard or not self:has_selection() then return end
  local before=self:begin_edit();if not before then return end
  for _,n in ipairs(self.notes) do if self.selected[n.id] then
    n.shift=math.max(-24,math.min(24,n.shift+(n.visual_offset or 0)+(n.flat_offset or 0)*(n.flatten or 0)));n.visual_offset=0;n.modulation=0;n.drift=0;n.flatten=0;n.vibrato_depth=0;n.anchors={};n.target_anchors=nil;n.drawings=nil
    n.shift=Scale.shift(self,n,n.shift,alt)
    Expression.edit(n)
    for _,p in ipairs(self.shape_clipboard) do n.anchors[#n.anchors+1]={t=n.start+p.u*(n.finish-n.start),value=math.max(-12,math.min(12,p.value))} end
  end end
  self:commit(before,'paste pitch shape')
end
function M:dispose()self:cancel()end
return M
