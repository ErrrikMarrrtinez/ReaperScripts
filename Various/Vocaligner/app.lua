-- @noindex
local import=...;local Config=import('config');local Audio=import('audio');local Job=import('job')
local DTW=import('dtw');local Warp=import('warp');local Apply=import('apply');local Cleaner=import('cleaner');local Pitch=import('pitch/editor')
local M={};M.__index=M
function M.new(r,config)
  local self=setmetatable({r=r,cfg=config or Config.load(r),dubs={},groups={},message='Capture a reference, then select the dubs.',
    focus=1,log={},live_amount=true,host_version=r.GetAppVersion and r.GetAppVersion() or 'unknown'},M)
  self.cleaner=Cleaner.new(self)
  self.pitch=Pitch.new(self)
  return self
end
function M:report(message)
  self.message=tostring(message);self.log[#self.log+1]=self.message
  if #self.log>80 then table.remove(self.log,1) end
end
-- Errors also go to the REAPER console at once, with their traceback when
-- there is one, so a failure is readable without opening Diagnostics.
function M:console(prefix,text)
  if self.last_console==text then return end
  self.last_console=text
  if self.r.ShowConsoleMsg then self.r.ShowConsoleMsg(os.date('%H:%M:%S')..' '..prefix..': '..text..'\n')end
end
function M:fail(message)
  self.error=tostring(message);self:report(self.error);self:console('Vocaligner error',self.error)
end
function M:diagnostics()
  local lines={'Vocaligner '..import('version').version..' | REAPER '..self.host_version,os.date('%Y-%m-%d %H:%M:%S'),''}
  local function add(s) lines[#lines+1]=s end
  for _,key in ipairs({'profile','strength','tolerance_ms','search_s','max_ratio','detail_ms','smooth_ms','fade_ms',
    'deess_hz','deess_threshold','deess_amount','deess_max_db','deess_pre_ms','deess_release_ms',
    'deess_detail','marker_density','breath_sensitivity','breath_db','breath_min_ms'}) do
    add(key..' = '..tostring(self.cfg[key]))
  end
  local function item(label,s,audio)
    add(string.format('%s: %s | position %.6f | length %.6f | offset %.6f | rate %.6f | original markers %d',
      label,s.name,s.pos,s.len,s.offset,s.rate,#s.markers))
    if s.composite then for k,p in ipairs(s.parts) do
      add(string.format('  item %d: %s | position %.6f | length %.6f | offset %.6f | rate %.6f | markers %d',k,p.name,p.pos,p.len,p.offset,p.rate,#p.markers))
    end end
    add(string.format('  pitch %.3f | preserve pitch %s | channel mode %s | channels %s',
      s.D_PITCH,tostring(s.B_PPITCH),tostring(s.I_CHANMODE),tostring(s.channels)))
    if s.source_length then add(string.format('  source %.9f s | source rate %.0f Hz | loop flag %s | edge overrun %.6f ms',
      s.source_length,s.source_rate or 0,tostring(s.B_LOOPSRC),s.source_overrun*1000)) end
    if audio then add(string.format('  frames %d | hop %.6f | accessor scale %.6f | silent %s',
      #audio.frames,audio.hop,audio.accessor_scale or 1,tostring(audio.silent or false))) end
    if audio and audio.first and audio.last then
      add(string.format('  active frames %d..%d | active project time %.6f..%.6f',
        audio.first,audio.last,audio.pos+audio.frames[audio.first].t,audio.pos+audio.frames[audio.last].t))
      local coarse=audio.scales and audio.scales[4]
      if coarse and #coarse.frames>0 then add(string.format('  coarse frames %d | coarse project time %.6f..%.6f',
        #coarse.frames,coarse.pos+coarse.frames[1].t,coarse.pos+coarse.frames[#coarse.frames].t)) end
    end
    local reads=s.read_diagnostics
    if reads then
      add(string.format('  audio reads %d | nil status %d | no-audio status %d | nonzero blocks %d | peak %.8f',
        reads.calls,reads.nil_status,reads.no_audio,reads.nonzero_blocks,reads.peak))
      add(string.format('  accessor %.6f..%.6f | read rate %d | last time %.6f | samples/channel %d | status %s',
        reads.start_time,reads.end_time,reads.sample_rate,reads.last_time or 0,reads.last_count or 0,reads.last_status or 'not read'))
    end
  end
  if self.ref then add('');item('REFERENCE',self.ref,self.ref_audio) end
  for _,g in ipairs(self.groups) do
    add(string.format('GROUP %d%s: %s | %d dubs | analyzed %s',g.id,g==self.group and ' *' or '',
      g.ref.name,#g.dubs,tostring(g.analyzed or false)))
  end
  for i,d in ipairs(self.dubs) do
    add('');item('DUB '..i,d.snapshot,d.audio)
    add(string.format('  status %s | enabled %s | applied %s',d.status,tostring(d.enabled),tostring(d.applied or false)))
    if d.stats then add(string.format('  match %.4f | support %.4f | coverage %.4f | cost %.4f | fine cells %d',
      d.stats.confidence,d.stats.support or 0,d.stats.coverage,d.stats.cost,d.stats.cells)) end
    if d.plan then
      local p=d.plan
      add(string.format('  target position %.6f | length %.6f | max shift %.1f ms | stretch %.4f..%.4f | markers %d | review %s',
        p.pos,p.len,p.max_shift*1000,p.min_ratio,p.max_ratio,#p.markers,tostring(p.review)))
      add(string.format('  amount %.1f%% | mean log-rate change %.5f | limited points %d',p.amount or self.cfg.strength,p.rate_variation or 0,p.limited or 0))
      add('  marker: original relative time -> target project time / source time')
      for k,m in ipairs(p.markers) do
        if k<=10 or k>#p.markers-10 then add(string.format('  %d: %.6f -> %.6f / %.6f',k,m.t,m.target,m.source))
        elseif k==11 then add('  ... middle markers omitted ...') end
      end
    end
    if d.cleanup then
      add(string.format('  sibilant candidates %d | exclusions %d | max reduction %.2f dB | written envelope points %d',
        #(d.cleanup.sibilants or {}),#(d.exclusions or {}),d.cleanup.max_db,d.envelope_points or 0))
      for _,kind in ipairs({'sibilants'}) do
        for k,event in ipairs(d.cleanup[kind] or {}) do if k<=8 then
          add(string.format('    %s %.3f..%.3f s (original item time) | score %.3f | requested %.2f dB | excluded %s',
            event.kind,event.start,event.finish,event.score,event.reduction,tostring(event.excluded)))
        end end
      end
    end
    if d.applied_plan then add(string.format('  amount currently applied %.1f%% | current preview differs %s',
      d.applied_plan.amount or 0,tostring(d.applied_plan~=d.plan or d.applied_cleanup~=d.cleanup))) end
    if d.error then add('  ERROR: '..d.error) end
  end
  if self.error then add('');add('LAST ERROR: '..self.error) end
  add('');add('LOG:');for _,message in ipairs(self.log) do add(message) end
  if self.job then add('Current phase: '..self.job.label) end
  add('');add(self.cleaner:diagnostics());add('');add(self.pitch:diagnostics())
  if self.click_cleanup then add('');add(self.click_cleanup:diagnostics())end
  return table.concat(lines,'\n')
end
local group_fields={'project','ref','ref_audio','ref_quick','dubs','view','error','analyzed','dirty','replan','alignment','align_engine'}
local align_keys={'profile','strength','tolerance_ms','search_s','max_ratio','detail_ms','smooth_ms','fade_ms','marker_density','hybrid','hybrid_preset','hybrid_compression'}
function M:save_group()
  local g=self.group;if not g then return end
  for _,k in ipairs(group_fields) do g[k]=self[k] end
  g.cfg=Config.copy(self.cfg)
end
function M:select_group(index)
  if self.job or self.cleaner.job then return end
  Apply.finish(self.r,self.edit_transaction);self.edit_transaction=nil
  local g=self.groups[index];if not g then return end
  self:save_group();self.pending_apply=false;self.gesture=false
  self.group=g
  for _,k in ipairs(group_fields) do self[k]=g[k] end
  for _,k in ipairs(align_keys) do self.cfg[k]=g.cfg[k] end
  self.project_state=nil
  if not Audio.project_open(self.r,self.project) then self:fail('This group belongs to a closed project.');return end
  local ok,why=Audio.unchanged(self.r,self.ref)
  if not ok then self:fail(why);return end
  for _,d in ipairs(self.dubs) do
    ok,why=Audio.check_dub(self.r,d);if not ok then self:fail(why);return end
  end
end
function M:is_reference_item(item)
  if not self.ref then return false end
  for _,p in ipairs(Audio.parts(self.ref)) do if p.item==item then return true end end
  return false
end
-- Selected items grouped per track (consecutive items on one track become one
-- role). With grouping off every item is its own role, as before.
function M:selected_roles(exclude_reference)
  local r=self.r;local roles={};local by_track={}
  for i=0,r.CountSelectedMediaItems(0)-1 do
    local item=r.GetSelectedMediaItem(0,i)
    if not (exclude_reference and self:is_reference_item(item)) then
      local track=(self.cfg.group_items or 1)~=0 and r.GetMediaItemTrack and r.GetMediaItemTrack(item) or nil
      local role=track and by_track[track]
      if not role then
        role={track=track,items={},order=#roles+1};roles[#roles+1]=role
        if track then by_track[track]=role end
      end
      role.items[#role.items+1]=item
    end
  end
  table.sort(roles,function(a,b)
    local ia=a.track and r.GetMediaTrackInfo_Value(a.track,'IP_TRACKNUMBER') or 0
    local ib=b.track and r.GetMediaTrackInfo_Value(b.track,'IP_TRACKNUMBER') or 0
    if ia~=ib then return ia<ib end;return a.order<b.order
  end)
  return roles
end
function M:reference_selected()
  if self.job or self.cleaner.job then return end
  Apply.finish(self.r,self.edit_transaction);self.edit_transaction=nil
  local r=self.r
  local roles=self:selected_roles(false)
  if #roles~=1 then
    self:fail(#roles==0 and 'Select a reference item.' or ((self.cfg.group_items or 1)~=0
      and 'Select the reference on one track: one item, or several consecutive items.'
      or 'Select exactly one reference item, or enable "Group items per track" for several consecutive items.'));return
  end
  local project=r.EnumProjects(-1)
  local ok,s=pcall(Audio.capture_group,r,project,roles[1].items,false)
  if not ok then
    self.loop_items=tostring(s):find('Looped source repetitions',1,true) and 'reference' or nil
    self:fail('Reference: '..tostring(s));return
  end
  self.loop_items=nil
  self:save_group();self.group=nil
  for i=#self.groups,1,-1 do if not Audio.project_open(r,self.groups[i].project) then table.remove(self.groups,i) end end
  self.project=project;self.ref=s;self.ref_audio=nil;self.ref_quick=Audio.peaks(r,s)
  self.edge_items=nil
  self.dubs={};self.view=nil;self.error=nil;self.analyzed=false;self.dirty=false
  self.replan=false;self.pending_apply=false
  self:report('Reference: '..s.name)
end
function M:dubs_selected()
  if self.job or self.cleaner.job then return end
  local r=self.r
  if not self.ref then self:fail('Select a reference first.');return end
  if self.project~=r.EnumProjects(-1) then self:fail('Select dubs in the same project as the reference.');return end
  local dubs={}
  for _,role in ipairs(self:selected_roles(true)) do
    local ok,s=pcall(Audio.capture_group,r,self.project,role.items,true)
    if not ok then
      if tostring(s):find('explicit markers at both item edges',1,true) then self.edge_items=true else self.edge_items=nil end
      self.loop_items=tostring(s):find('Looped source repetitions',1,true) and 'dubs' or nil
      self:fail(s);return
    end
    dubs[#dubs+1]={snapshot=s,quick=Audio.peaks(r,s),enabled=true,status='Unprocessed'}
  end
  if #dubs==0 then self:fail('Select at least one dub other than the reference.');return end
  self.edge_items=nil;self.loop_items=nil
  -- Reuse an existing group's baseline even if its dubs currently carry our markers.
  for index,g in ipairs(self.groups) do
    local same=g.project==self.project and g.ref.guid==self.ref.guid and #g.dubs==#dubs
    for i,d in ipairs(dubs) do same=same and g.dubs[i].snapshot.guid==d.snapshot.guid end
    if same then
      local valid=Audio.unchanged(r,g.ref)
      for _,d in ipairs(g.dubs)do valid=Audio.check_dub(r,d) and valid end
      if valid then self:select_group(index);return end
      -- Same takes can have new trim, source or marker geometry. Selecting
      -- them again is an explicit new capture, not a request for stale caches.
      self:save_group();self.group=g;self.dubs=dubs;self.ref_audio=nil;self.view=nil
      self.pending_apply=false;self.replan=false;self.dirty=false;self.analyzed=false;self.error=nil
      self:save_group();self:report('Recaptured changed items for this group. Analyze to rebuild timing.');return
    end
  end
  self:save_group()
  self.dubs=dubs;self.view=nil;self.pending_apply=false;self.replan=false;self.dirty=false
  self.analyzed=false;self.error=nil
  self.next_group_id=(self.next_group_id or 0)+1
  local g={id=self.next_group_id};self.group=g;self.groups[#self.groups+1]=g
  self:save_group()
end
function M:recapture_changed()
  local r=self.r;local ref_changed=not Audio.unchanged(r,self.ref)
  local ref=ref_changed and Audio.recapture(r,self.ref,false) or self.ref
  local dubs={};local changed=ref_changed
  for i,d in ipairs(self.dubs)do
    if not Audio.check_dub(r,d) then
      local s=Audio.recapture(r,d.snapshot,true)
      dubs[i]={snapshot=s,quick=Audio.peaks(r,s),enabled=true,status='Unprocessed'};changed=true
    else dubs[i]=d end
  end
  self.ref=ref;self.dubs=dubs
  if ref_changed then
    self.ref_audio=nil;self.ref_quick=Audio.peaks(r,ref)
    for _,d in ipairs(dubs)do d.path=nil;d.stats=nil;d.plan=nil;d.full_plan=nil end
  end
  if changed then self.view=nil;self.analyzed=false;self:report('Analyzing changed items from their current timing. Restore will return to this new capture.') end
end
function M:add_edge_anchors()
  if self.job or self.cleaner.job or not self.edge_items then return end
  local r=self.r;local project=r.EnumProjects(-1);if project~=self.project then return end
  local batch={}
  for i=0,r.CountSelectedMediaItems(project)-1 do
    local item=r.GetSelectedMediaItem(project,i)
    if not self:is_reference_item(item) then
      local ok,s=pcall(Audio.state,r,project,item)
      if not ok then self:fail(s);return end
      if s.C_LOCK~=0 then self:fail(s.name..' is locked.');return end
      for _,m in ipairs(s.markers)do if math.abs(m.slope)>1e-9 then self:fail('Curved stretch markers are not supported yet: '..s.name);return end end
      if #s.markers>0 then
        local yes,chunk=r.GetItemStateChunk(item,'',false);if not yes then self:fail('Cannot snapshot stretch markers.');return end
        batch[#batch+1]={s=s,chunk=chunk}
      end
    end
  end
  if #batch==0 then self.edge_items=nil;return end
  r.Undo_BeginBlock2(project);r.PreventUIRefresh(1)
  local ok,why=xpcall(function()
    for _,entry in ipairs(batch)do
      local s=entry.s
      for _,edge in ipairs({0,s.len*s.rate})do
        local exists=false;for _,m in ipairs(s.markers)do if math.abs(m.pos-edge)<1e-7 then exists=true end end
        if not exists then
          -- Omit srcpos: REAPER interpolates its own existing stretch map.
          -- Do not guess source positions outside the first/last marker.
          local index=r.SetTakeStretchMarker(s.take,-1,edge)
          assert(index>=0,'REAPER could not add an edge anchor to '..s.name)
          local _,pos=r.GetTakeStretchMarker(s.take,index);assert(math.abs(pos-edge)<1e-6,'REAPER constrained an edge anchor')
        end
      end
      r.UpdateItemInProject(s.item)
    end
  end,debug.traceback)
  if not ok then for _,entry in ipairs(batch)do if not r.SetItemStateChunk(entry.s.item,entry.chunk,false) then why=why..'\nRollback failed; use REAPER Undo.' end end end
  r.PreventUIRefresh(-1);r.Undo_EndBlock2(project,'Vocaligner: add stretch edge anchors',-1);r.UpdateArrange()
  if not ok then self:fail(why);return end
  self.edge_items=nil;self:dubs_selected()
end
-- Items that play past the end of a looped source repeat the file start in
-- their tail. Trim each such selected item to the end of its file (inside one
-- Undo block, rolled back on failure), then repeat the selection that failed.
local function loop_trim_point(s,length)
  if #s.markers==0 then return (length-s.offset)/s.rate end
  for k=2,#s.markers do local a,b=s.markers[k-1],s.markers[k]
    if b.src>=length then return (a.pos+(b.pos-a.pos)*(length-a.src)/(b.src-a.src))/s.rate end
  end
end
function M:trim_loop_tails()
  if self.job or self.cleaner.job or not self.loop_items then return end
  local r=self.r;local project=r.EnumProjects(-1);local role=self.loop_items
  if role=='dubs' and project~=self.project then self:fail('Switch back to the captured project.');return end
  local batch={}
  for i=0,r.CountSelectedMediaItems(project)-1 do
    local item=r.GetSelectedMediaItem(project,i)
    if role=='reference' or not self:is_reference_item(item) then
      local ok,s=pcall(Audio.state,r,project,item);if not ok then self:fail(s);return end
      local length,is_qn=r.GetMediaSourceLength(s.source)
      local source_rate=r.GetMediaSourceSampleRate and r.GetMediaSourceSampleRate(s.source) or 0
      local tolerance=2/(source_rate>0 and source_rate or 44100)
      local source_end=#s.markers>0 and s.markers[#s.markers].src or s.offset+s.len*s.rate
      if s.B_LOOPSRC~=0 and not is_qn and length and length>0 and source_end-length>tolerance then
        if s.C_LOCK~=0 then self:fail(s.name..' is locked.');return end
        for _,m in ipairs(s.markers)do if math.abs(m.slope)>1e-9 then self:fail('Curved stretch markers are not supported yet: '..s.name);return end end
        local t=loop_trim_point(s,length)
        if not t or t<.06 or t>=s.len then self:fail('Cannot trim the looped tail of '..s.name..'; shorten the item manually.');return end
        local yes,chunk=r.GetItemStateChunk(item,'',false);if not yes then self:fail('Cannot snapshot '..s.name);return end
        batch[#batch+1]={s=s,len=t,length=length,chunk=chunk,tolerance=tolerance}
      end
    end
  end
  if #batch==0 then self.loop_items=nil;if role=='reference' then self:reference_selected() else self:dubs_selected() end;return end
  r.Undo_BeginBlock2(project);r.PreventUIRefresh(1)
  local ok,why=xpcall(function()
    for _,entry in ipairs(batch)do
      local s=entry.s
      if #s.markers>0 then
        -- Keep the markers inside the trimmed item and end it with an explicit
        -- edge marker exactly at the end of the file.
        local n=r.GetTakeNumStretchMarkers(s.take);assert(r.DeleteTakeStretchMarkers(s.take,0,n)==n,'Could not edit stretch markers of '..s.name)
        local edge=entry.len*s.rate
        for _,m in ipairs(s.markers)do if m.pos<edge-1e-7 then
          local ix=r.SetTakeStretchMarker(s.take,-1,m.pos,m.src);assert(ix>=0,'REAPER refused a marker in '..s.name)
          r.SetTakeStretchMarkerSlope(s.take,ix,m.slope)
        end end
        assert(r.SetMediaItemInfo_Value(s.item,'D_LENGTH',entry.len))
        assert(r.SetTakeStretchMarker(s.take,-1,edge,entry.length)>=0,'REAPER refused the end marker in '..s.name)
      else assert(r.SetMediaItemInfo_Value(s.item,'D_LENGTH',entry.len)) end
      r.UpdateItemInProject(s.item)
      local now=Audio.state(r,project,s.item)
      local finish=#now.markers>0 and now.markers[#now.markers].src or now.offset+now.len*now.rate
      assert(finish-entry.length<=entry.tolerance,'REAPER did not keep the trimmed end of '..s.name)
    end
  end,debug.traceback)
  if not ok then for _,entry in ipairs(batch)do if not r.SetItemStateChunk(entry.s.item,entry.chunk,false) then why=why..'\nRollback failed; use REAPER Undo.' end end end
  r.PreventUIRefresh(-1);r.Undo_EndBlock2(project,'Vocaligner: trim looped item tails',-1);r.UpdateArrange()
  if not ok then self:fail(why);return end
  self.loop_items=nil
  self:report(string.format('Trimmed looped tails of %d item(s) to the end of their files.',#batch))
  if role=='reference' then self:reference_selected() else self:dubs_selected() end
end
function M:start(recover)
  if self.job or self.cleaner.job or not self.ref or #self.dubs==0 then return end
  local r=self.r;local cfg=Config.copy(self.cfg)
  if r.EnumProjects(-1)~=self.project then self:fail('Switch back to the captured project before analyzing.');return end
  if recover~=false then local ok,why=pcall(self.recapture_changed,self);if not ok then self:fail(why);return end end
  local seconds=0
  for _,g in ipairs(self.groups) do
    if Audio.project_open(r,g.project) then
      seconds=seconds+g.ref.len;for _,d in ipairs(g.dubs) do seconds=seconds+d.snapshot.len end
    end
  end
  if #self.groups==0 then seconds=self.ref.len;for _,d in ipairs(self.dubs) do seconds=seconds+d.snapshot.len end end
  if seconds*cfg.sample_rate/cfg.hop>cfg.max_total_frames then
    self:fail('Group audio cache exceeds 20 minutes. Remove a group to free it.');return
  end
  self.error=nil;self.pending_apply=false;self.replan=false;self.dirty=false
  self.operation={progress=0,created_at=r.time_precise()}
  self.job=Job.new(r,function(job)
    local total=self.ref.len;for _,d in ipairs(self.dubs)do total=total+2*d.snapshot.len end
    local reference_end=self.ref.len/total
    local ok,msg=Audio.unchanged(r,self.ref);if not ok then error(msg,0) end
    if not self.ref_audio then self.ref_audio=Audio.analyze(r,self.ref,cfg,job:scope(0,reference_end),'Reading reference') end
    job:checkpoint(reference_end,'Reference ready')
    if self.ref_audio.silent then error('The reference is silent or too quiet to analyze.',0) end
    local usable=0;local elapsed=self.ref.len
    for i,d in ipairs(self.dubs) do
      local first,last=elapsed/total,(elapsed+2*d.snapshot.len)/total;elapsed=last*total
      local part=job:scope(first,last)
      d.status='Analyzing'
      local good,why=pcall(function()
        local valid,changed=Audio.check_dub(r,d);if not valid then error(changed,0) end
        if not d.audio then
          d.audio=Audio.analyze(r,self:align_read_snapshot(d.snapshot),cfg,part:scope(0,.45),'Reading dub '..i..' / '..#self.dubs)
          d.audio.snapshot=d.snapshot
        end
        part:checkpoint(.45,'Matching dub '..i..' / '..#self.dubs)
        -- Only search/profile changes require another match; all other knobs reuse this path.
        if not d.path or d.match_profile~=cfg.profile or d.match_search~=cfg.search_s then
          d.path=nil;d.stats=nil
          local path,stats=DTW.align(self.ref_audio,d.audio,cfg,part:scope(.45,.95))
          if not path then error(stats,0) end
          d.path,d.stats=path,stats;d.match_profile=cfg.profile;d.match_search=cfg.search_s
        end
        local plan,reason,base=Warp.build(self.ref_audio,d.audio,d.path,d.stats,cfg,part:scope(.95,1))
        if not plan then error(reason,0) end
        d.plan=plan;d.full_plan=base;d.enabled=true;d.error=nil
        d.status='Ready';usable=usable+1
        if plan.review then self:report(string.format('%s: low match %.1f%%; applying the calculated timing.',d.snapshot.name,100*(d.stats.confidence or 0))) end
      end)
      if not good then
        d.status='Skipped';d.plan=nil;d.full_plan=nil;d.enabled=false;d.error=tostring(why)
        self:fail(d.snapshot.name..': '..tostring(why))
      end
      part:checkpoint(1,'Matched '..i..' / '..#self.dubs)
    end
    self.analyzed=usable>0
  end,cfg.frame_budget)
  self.job.kind='analysis'
end
function M:settings_changed(key)
  self:preferences_changed();self.revision=(self.revision or 0)+1
  self.pending_apply=self.analyzed==true
  self.live_due=self.live_due or self.r.time_precise()+.035
  if self.analyzed then self.edit_transaction=self.edit_transaction or {} end
  if key=='strength' and (self.cfg.hybrid or 0)==0 then
    for _,d in ipairs(self.dubs) do if d.full_plan then d.plan=Warp.blend(d.full_plan,self.cfg.strength) end end
  elseif key=='profile' or key=='search_s' then self.dirty=true;self.pending_apply=false
  elseif key~='fade_ms' then self.replan=true end
end
function M:preferences_changed() self.save_at=self.r.time_precise()+.8 end
function M:control_released()
  if self.analyzed then
    self.pending_apply=self.pending_apply or self.dirty or self.replan or self.applied_revision~=(self.revision or 0)
    self.live_due=nil
  end
end
function M:amount_released() self:control_released() end
function M:tick()
  if self.save_at and self.r.time_precise()>=self.save_at then Config.save(self.r,self.cfg);self.save_at=nil end
  self.cleaner:tick()
  self.pitch:tick()
  if self.project and Audio.project_open(self.r,self.project) then
    local state=self.r.GetProjectStateChangeCount(self.project)
    if state~=self.project_state then
      for _,d in ipairs(self.dubs) do if d.original_state then
        local ok,why=Audio.check_dub(self.r,d)
        if not ok then self.pending_apply=false;self:fail(why) end
      end end
      self.project_state=state
    end
  end
  if self.job then
    local job=self.job;job:step()
    if self.operation then self.operation.progress=math.max(self.operation.progress,(job.progress or 0)*.98) end
    if job.done then
      self.job=nil
      if job.error then
        self.pending_apply=false;self.operation=nil;Apply.finish(self.r,self.edit_transaction);self.edit_transaction=nil;self:fail(job.error)
        for _,d in ipairs(self.dubs) do if not d.plan then d.status='Analysis failed' end end
      elseif job.kind=='timing' then
        local newer=(self.revision or 0)~=job.revision
        if (job.cfg.hybrid or 0)~=0 and (self.gesture or newer)then
          self.pending_apply=true
        else
          local applied=self:apply(job.cfg,true,job.revision)
          self.pending_apply=applied and newer or false
        end
        if newer then self.replan=true;self.live_due=self.r.time_precise()+.035 end
      else self.pending_apply=true end
      self:save_group()
    end
  elseif self.pending_apply and not self.cleaner.job and not ((self.cfg.hybrid or 0)~=0 and self.gesture) and (not self.live_due or self.r.time_precise()>=self.live_due) then
    self.live_due=nil
    if self.dirty then if not self.gesture then self:start(false) end
    elseif self.replan then
      self.replan=false;local cfg=Config.copy(self.cfg)
      self.job=Job.new(self.r,function(job)
        local plans={}
        for _,d in ipairs(self.dubs) do if d.path then
          local plan,err,base=Warp.build(self.ref_audio,d.audio,d.path,d.stats,cfg,job)
          plans[#plans+1]={dub=d,plan=plan,base=base,error=err}
          if not plan then self:fail(d.snapshot.name..': '..tostring(err)) end
        end end
        for _,entry in ipairs(plans)do
          local d=entry.dub;d.plan=entry.plan;d.full_plan=entry.base;d.error=entry.error;d.enabled=entry.plan~=nil
        end
      end,cfg.frame_budget)
      self.job.kind='timing';self.job.live=true;self.job.cfg=cfg;self.job.revision=self.revision or 0
    else self.pending_apply=false;self:apply() end
  end
  if not self.job and not self.pending_apply and not self.gesture then
    self.operation=nil;Apply.finish(self.r,self.edit_transaction);self.edit_transaction=nil
  end
end
function M:cancel()
  self.pending_apply=false;self.live_due=nil;self.operation=nil
  if self.job then self.job:cancel();self.job=nil end
  Apply.finish(self.r,self.edit_transaction);self.edit_transaction=nil
  self:save_group()
end
function M:apply(cfg,prepared,revision)
  if self.job or self.cleaner.job or (self.dirty or self.replan) and not prepared then return end
  local ready=false
  for _,d in ipairs(self.dubs) do if d.enabled and d.plan and (d.applied or not d.plan.unchanged) then ready=true end end
  if not ready then self.applied_revision=revision or self.revision or 0;self:save_group();return true end
  local n,why=Apply.run(self.r,self.project,self.ref,self.dubs,cfg or self.cfg,self.edit_transaction)
  if n then
    self.applied_revision=revision or self.revision or 0
    if not self.gesture then self:report('Applied timing to '..n..' dub(s).') end
  else self:fail(why);Apply.finish(self.r,self.edit_transaction);self.edit_transaction=nil end
  self:save_group()
  return n~=nil
end
function M:restore()
  self.pending_apply=false
  if self.job or self.cleaner.job then return end
  Apply.finish(self.r,self.edit_transaction);self.edit_transaction=nil
  local n,why=Apply.restore(self.r,self.project,self.dubs)
  if n then self.error=nil;self:report('Restored '..n..' original take(s).') else self:fail(why) end
  self:save_group()
end
function M:remove_group()
  if self.job or self.cleaner.job or not self.group then return end
  for i,g in ipairs(self.groups) do if g==self.group then table.remove(self.groups,i);break end end
  self.group=nil;self.ref=nil;self.ref_audio=nil;self.ref_quick=nil;self.dubs={};self.view=nil
  self.pending_apply=false;self.analyzed=false;self.error=nil
  if #self.groups>0 then self:select_group(#self.groups) end
end
function M:dispose()
  self:cancel();self.cleaner:dispose();self.pitch:dispose()
  if self.save_at then Config.save(self.r,self.cfg);self.save_at=nil end
end
return import('align/session').install(M)
