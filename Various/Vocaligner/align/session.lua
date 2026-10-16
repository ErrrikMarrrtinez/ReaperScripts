-- @noindex
local import=...;local Registry=import('align/registry');local Defaults=import('align/advanced/defaults')
local Preferences=import('align/preferences');local Config=import('config');local Apply=import('apply');local Audio=import('audio');local U=import('align/util')
local M={};local serial=0
local Bridge=import('align/cleanup_bridge')
local app_fields={'ref_audio','analyzed','dirty','replan','error','view'}
local dub_fields={'audio','path','stats','plan','full_plan','error','status','enabled','match_profile','match_search','correspondence','advanced_feature_key','advanced_match_key','align_error'}
local function copy_keys(from,keys)local out={};for _,k in ipairs(keys)do out[k]=from[k]end;return out end
local function put(to,from,keys)for _,k in ipairs(keys)do to[k]=from and from[k]end end
local function busy(app)return app.job or app.cleaner.job or app.pitch.job or app.mutation_lease end
local function save_branch(app)
  local a=app.alignment;if not a then return end
  local entry=Registry.get(app.align_engine)
  if entry then a.settings[entry.id]=copy_keys(app.cfg,entry.settings_keys)end
  local branch=copy_keys(app,app_fields);branch.dubs={}
  for _,d in ipairs(app.dubs)do d.align_app=app;branch.dubs[d.snapshot.guid]=copy_keys(d,dub_fields)end
  a.branches[app.align_engine]=branch
end
local function load_branch(app,id)
  app.align_reconcile_revision=nil;app.align_remember_revision=nil
  local a=app.alignment;local branch=a.branches[id];put(app,branch,app_fields)
  for _,d in ipairs(app.dubs)do
    d.align_app=app
    put(d,branch and branch.dubs[d.snapshot.guid],dub_fields)
    if not branch then d.status='Analyze '..(Registry.get(id)and Registry.get(id).display_name or 'supported algorithm');d.enabled=true end
  end
  local entry=Registry.get(id)
  if entry then for _,k in ipairs(entry.settings_keys)do app.cfg[k]=a.settings[id][k]end end
  a.ready_request=nil;app.pending_apply=false;app.live_due=nil;app.operation=nil
end
local function fresh(app,old)
  serial=serial+1
  local pref=app.align_preferences or Preferences.load(app.r)
  local settings=old and old.settings or {
    legacy_v012=copy_keys(app.cfg,Registry.get('legacy_v012').settings_keys),
    advanced_v1=copy_keys(Defaults.config(pref.advanced),Defaults.settings_keys)}
  local a={session_id=string.format('%.6f:%d',app.r.time_precise(),serial),baseline_revision=old and old.baseline_revision+1 or 1,
    request_id=0,features={},constraints={},constraints_revision=0,settings=settings,branches={}}
  app.alignment=a;app.align_engine=app.align_engine or pref.selected_engine
  load_branch(app,app.align_engine)
end
local function persist(app)
  save_branch(app);Preferences.save(app.r,app.align_engine,app.alignment.settings.advanced_v1)
  -- The original preference section continues to contain Classic values.
  local cfg=Config.copy(app.cfg);for k,v in pairs(app.alignment.settings.legacy_v012)do cfg[k]=v end
  Config.save(app.r,cfg);app.save_at=nil
end
local function constraints_present(app)
  for _,list in pairs(app.alignment.constraints)do if #list>0 then return true end end
  return false
end
function M.install(App)
  Bridge.install()
  local legacy={};for k,v in pairs(App)do if type(v)=='function'then legacy[k]=v end end
  App.new=function(r,config)
    local app=legacy.new(r,config);app.align_preferences=Preferences.load(r);fresh(app)
    local tick=app.cleaner.tick
    app.cleaner.tick=function(c,...)local out=table.pack(tick(c,...));Bridge.reconcile(app);return table.unpack(out,1,out.n)end
    return app
  end
  for _,method in ipairs({'start','tick','settings_changed','control_released','apply','restore','cancel','diagnostics'})do
    App[method]=function(app,...)
      if method=='start'or method=='apply'or method=='restore'then Bridge.reconcile(app)end
      if method=='tick'and app.align_export_job then
        local j=app.align_export_job;j:step()
        if j.done then app.align_export_job=nil;if j.error then app:fail(j.error)else app:report('Align case saved: '..j.result);app.r.ShowConsoleMsg('Align case saved: '..j.result..'\n')end end
      end
      if method=='tick'and app.save_at and app.r.time_precise()>=app.save_at then persist(app)end
      if method=='restore'then
        if import('align/hybrid/render').active(app.dubs)then return legacy.restore(app,...)end
        for _,d in ipairs(app.dubs)do if d.align_owner and d.applied then return Registry.get('advanced_v1').controller.restore(app,legacy,...)end end
        return legacy.restore(app,...)
      end
      if method=='cancel'then
        app.alignment.request_id=app.alignment.request_id+1
      end
      local entry=Registry.get(app.align_engine)
      if not entry then
        if method=='tick'then app.cleaner:tick();app.pitch:tick();return end
        if method=='cancel'then return legacy.cancel(app)end
        if method=='diagnostics'then return 'Unsupported Align engine: '..tostring(app.align_engine)..'\nChoose Classic or Advanced explicitly.'end
        app:fail('Unsupported Align algorithm. Choose a supported algorithm explicitly.');return
      end
      if entry.id=='legacy_v012'and (method=='start'or method=='apply')then
        if constraints_present(app)then app.pending_apply=false;app:fail('This group has Advanced constraints. Remove them in Advanced before using Classic.');return end
        if method=='start'then
          for _,d in ipairs(app.dubs)do if d.applied and (not app.ref_audio or not d.audio)then
            app:fail(d.snapshot.name..' still carries timing applied by another analysis. Press Restore (returns the captured timing), then Analyze with Classic.');return
          end end
        end
      end
      local result=table.pack(entry.controller[method](app,legacy,...))
      if method=='apply'or method=='tick'then Bridge.remember(app)end
      return table.unpack(result,1,result.n)
    end
  end
  function App:select_engine(id)
    if id==self.align_engine or busy(self)then return end
    if import('align/hybrid/render').active(self.dubs)then self:fail('Press Restore before switching from applied Hybrid edits.');return end
    if not Registry.get(id)then self:fail('Unsupported Align algorithm: '..tostring(id));return end
    Apply.finish(self.r,self.edit_transaction);self.edit_transaction=nil
    save_branch(self);self.alignment.request_id=self.alignment.request_id+1;self.align_engine=id
    load_branch(self,id);self.gesture=false;self:preferences_changed();self:save_group()
    self:report(Registry.get(id).display_name..' selected. The project timing has not changed.')
  end
  function App:save_group()save_branch(self);legacy.save_group(self)end
  function App:select_group(index)
    if busy(self)then return end
    legacy.select_group(self,index)
    local failure=self.error
    if self.alignment then load_branch(self,self.align_engine)end
    if failure then self.error=failure end
  end
  function App:reference_selected()
    if busy(self)then return end
    local previous=self.ref;legacy.reference_selected(self)
    if self.ref~=previous then fresh(self,self.alignment)end
  end
  function App:dubs_selected()
    if busy(self)then return end
    local previous=self.dubs;local old=self.alignment;legacy.dubs_selected(self)
    if self.dubs~=previous then
      local reused=self.group and self.group.alignment~=old and self.group.alignment
      -- Existing group selection already restored its own immutable context.
      if not reused then
        local same=#self.dubs==#previous
        for i,d in ipairs(self.dubs)do same=same and previous[i]and d.snapshot==previous[i].snapshot end
        if not same then fresh(self,old);self:save_group()end
      end
    end
  end
  function App:recapture_changed()
    local ref=self.ref;local snapshots={};for i,d in ipairs(self.dubs)do snapshots[i]=d.snapshot end
    legacy.recapture_changed(self)
    local changed=self.ref~=ref
    for i,d in ipairs(self.dubs)do changed=changed or d.snapshot~=snapshots[i]end
    if changed then
      local kept=self.align_engine=='legacy_v012'and copy_keys(self,app_fields);local dubs={}
      if kept then for i,d in ipairs(self.dubs)do dubs[i]=copy_keys(d,dub_fields)end end
      fresh(self,self.alignment)
      -- Legacy already invalidates precisely the changed captures. Keep its
      -- reference and unchanged-dub caches, matching the original read policy.
      if kept then put(self,kept,app_fields);for i,d in ipairs(self.dubs)do put(d,dubs[i],dub_fields)end end
      self:save_group()
    end
  end
  function App:remove_group()
    if busy(self)then return end
    legacy.remove_group(self);if not self.group then fresh(self,self.alignment)end
  end
  function App:set_align_constraints(dub,list)
    if busy(self)or self.align_engine~='advanced_v1'then return end
    local valid,err=import('align/advanced/constraints').validate(list,dub.snapshot,self.ref,Defaults.config(self.cfg))
    if not valid then self:fail(tostring(err));return false end
    self.alignment.constraints[dub.snapshot.guid]=valid;self.alignment.constraints_revision=self.alignment.constraints_revision+1
    self:settings_changed('constraints');self:control_released();self:save_group();return true
  end
  function App:refresh_align_source()
    if busy(self)then return end
    for _,d in ipairs(self.dubs)do if d.applied then self:fail('Restore first, then Refresh source and Analyze.');return end end
    fresh(self,self.alignment);self:save_group();self:report('Source caches and constraints cleared. Analyze to read the media again.')
  end
  function App:export_align_case()return import('align/export').run(self)end
  function App:align_read_snapshot(snapshot)return Bridge.read_snapshot(self,snapshot)end
  function App:dispose()
    if self.align_export_job then self.align_export_job:cancel();self.align_export_job=nil end
    if self.save_at then persist(self)end
    return legacy.dispose(self)
  end
  return App
end
return M
