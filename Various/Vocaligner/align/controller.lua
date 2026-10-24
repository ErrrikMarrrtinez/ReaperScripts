-- @noindex
local import=...;local U=import('align/util');local Config=import('config');local Audio=import('audio');local Job=import('job')
local D=import('align/advanced/defaults');local Reader=import('align/reader');local Features=import('align/advanced/features')
local Match=import('align/advanced/match');local Plan=import('align/advanced/plan');local Ownership=import('align/ownership');local Renderer=import('align/renderers/stretch')
local Guided=import('align/advanced/guided');local M={}
local function busy(app)return app.job or app.cleaner.job or app.pitch.job or app.mutation_lease end
local function config(app)return D.config(app.cfg)end
local function captured_key(a,s,pitch)return a.session_id..'|'..s.guid..'|'..s.signature..'|'..D.frontend..'|pitch='..tostring(pitch)end
local function baseline_id(a,s)return a.session_id..':'..a.baseline_revision..':'..s.guid..':'..U.hash(s.signature)end
local function job_report(app,job,outcome)
  local b=job.align_budget or {}
  return {outcome=outcome or 'running',phase=job.label or '',detail=b.detail,progress=job.progress or 0,dub=job.align_dub,
    elapsed_ms=(app.r.time_precise()-job.created_at)*1000,work_ms=job.work_ms or 0,steps=job.steps or 0,max_step_ms=job.max_step_ms or 0,
    states=b.states or 0,cells=b.cells or 0,coarse_work=b.coarse or 0,traceback_bytes=b.trace_peak or 0,
    regularize_work=b.regularize or 0,retries=b.retries or 0,backend=b.native_solver and b.native_solver.fn and 'EEL'or 'Lua',native_bytes=b.native_bytes,
    native_fallback=b.native_solver and b.native_solver.reason,totals=job.align_totals,
    error=job.error and tostring(job.error):match('^[^\r\n]+')or nil}
end
local function valid_request(app,token)
  local a=app.alignment
  return a==token.context and a.session_id==token.session_id and a.baseline_revision==token.baseline_revision
    and a.request_id==token.request_id and (app.revision or 0)==token.config_revision and app.align_engine=='advanced_v1'
end
local function token(app)
  local a=app.alignment;a.request_id=a.request_id+1
  return {context=a,session_id=a.session_id,baseline_revision=a.baseline_revision,request_id=a.request_id,config_revision=app.revision or 0}
end
local function check_source(app,d)
  local ok,why=Audio.check_dub(app.r,d);if not ok then U.fail('source_changed',why,'analysis')end
  local now=Audio.current(app.r,d.snapshot)
  local owner,err=Ownership.check(app.r,now,d.align_owner,true);if not owner then error(err,0)end
  return owner
end
local function features(app,s,cfg,job,label,owner)
  local a=app.alignment;local key=captured_key(a,s,cfg.advanced_pitch);local cached=a.features[key]
  if cached then return cached,key end
  -- Turning optional pitch off can derive the original acoustic-only view from
  -- immutable raw-derived fields, even while this take carries our timing map.
  local pitched=not cfg.advanced_pitch and a.features[captured_key(a,s,true)]
  if pitched then
    local derived=Features.normalize(pitched,cfg,job)
    derived.analysis_stats={backend='Cached acoustics (pitch evidence off)',acoustic_cache_hit=true,pitch_enabled=false,
      pitch_frames=0,reliable_pitch_frames=0,pitch_samples=0,read_calls=0,read_ms=0,feature_ms=0,pitch_ms=0}
    a.features[key]=derived;return derived,key
  end
  local count=math.ceil(s.len*100);local seen={}
  local function account(data)if data and data.frames and not seen[data]then seen[data]=true;count=count+#data.frames end end
  for _,g in ipairs(app.groups)do
    account(g.ref_audio);for _,d in ipairs(g.dubs)do account(d.audio)end
    if g.alignment then
      for _,value in pairs(g.alignment.features)do account(value)end
      for _,branch in pairs(g.alignment.branches)do account(branch.ref_audio);for _,d in pairs(branch.dubs)do account(d.audio)end end
    end
  end
  for _,value in pairs(a.features)do account(value)end
  if count>cfg.max_frames then U.fail('work_budget_exceeded','Pinned Advanced feature caches exceed 120,000 frames; remove an unused group','features')end
  if count*8192>cfg.max_feature_bytes then U.fail('work_budget_exceeded','Combined Align feature cache exceeds its conservative 384 MB estimate; remove an unused group','features')end
  local read_snapshot=import('align/cleanup_bridge').read_snapshot(app,s)
  local acoustic_cache=cfg.advanced_pitch and a.features[captured_key(a,s,false)]or nil
  local data=Reader.analyze(app.r,read_snapshot,cfg,job,label,baseline_id(a,s),function()
    local ok,why=Ownership.check(app.r,s,owner,s~=app.ref);if not ok then error(why,0)end
  end,acoustic_cache)
  data.snapshot=s
  a.features[key]=data
  return data,key
end
-- The guided matcher runs the Classic DTW on Classic features (one short
-- pass per item, cached by capture like the Advanced features).
local function classic_config(app,cfg)
  local classic=Config.copy(app.cfg);classic.profile=cfg.profile;classic.search_s=cfg.search_s;return classic
end
local function classic_features(app,s,cfg,job,label)
  local a=app.alignment;local key=captured_key(a,s,'classic');local cached=a.features[key]
  if cached then return cached end
  local data=Audio.analyze(app.r,import('align/cleanup_bridge').read_snapshot(app,s),classic_config(app,cfg),job,label)
  data.snapshot=s;a.features[key]=data;return data
end
local function prepare_job(app,kind,cfg,request)
  app.pending_apply=false;app.error=nil;app.operation={progress=0,created_at=app.r.time_precise()}
  for _,d in ipairs(app.dubs)do d.plan=nil;d.full_plan=nil;d.error=nil;d.status=kind=='analysis'and 'Analyzing' or 'Planning' end
  local a=app.alignment;local dubs=app.dubs;local reference=app.ref
  local job=Job.new(app.r,function(work)
    local outputs={};local guide_data=app.ref_audio;local guide_classic
    local totals={states=0,cells=0,coarse=0,regularize=0,retries=0,trace_peak=0};work.align_totals=totals
    local function dub_budget()
      -- Work caps apply to one dub. A batch-wide counter made a normal third
      -- dub fail after the first two had legitimately used the allowance.
      local b=U.budget(cfg,work);b.native_solver=app.engine and app.engine.align;work.align_budget=b;return b
    end
    local function account(b)
      for _,k in ipairs({'states','cells','coarse','regularize','retries'})do totals[k]=totals[k]+(b[k]or 0)end
      totals.trace_peak=math.max(totals.trace_peak,b.trace_peak or 0)
    end
    dub_budget()
    if kind=='analysis'then
      local same,why=Audio.unchanged(app.r,reference);if not same then U.fail('source_changed',why,'analysis')end
      local owner,err=Ownership.check(app.r,reference,a.guide_owner,false);if not owner then error(err,0)end
      a.guide_owner=owner
      guide_data=features(app,reference,cfg,work:scope(0,cfg.matcher=='strict'and .25 or .18),'Advanced reference features',owner)
      if cfg.matcher~='strict'then guide_classic=classic_features(app,reference,cfg,work:scope(.18,.25),'Classic reference features')end
      a.diagnostic_features=a.diagnostic_features or {};a.diagnostic_features[reference.guid]=guide_data
    end
    for i,d in ipairs(dubs)do
      work.align_dub=i
      local scope=work:scope(.25+(i-1)/#dubs*.70,.25+i/#dubs*.70)
      local owner=check_source(app,d);d.align_owner=d.align_owner or owner
      local budget=i==1 and work.align_budget or dub_budget()
      local data,key=d.audio,d.advanced_feature_key
      local constraints=a.constraints[d.snapshot.guid]or {}
      local matchkey=D.match_key(cfg,constraints)
      local ok,failure=pcall(function()
        local correspond=d.correspondence
        if kind=='analysis'then
          local strict=cfg.matcher=='strict'
          data,key=features(app,d.snapshot,cfg,scope:scope(0,strict and .35 or .25),'Advanced dub '..i..' / '..#dubs,d.align_owner)
          local dub_classic=not strict and classic_features(app,d.snapshot,cfg,scope:scope(.25,.35),'Classic dub '..i..' / '..#dubs)or nil
          a.diagnostic_features=a.diagnostic_features or {};a.diagnostic_features[d.snapshot.guid]=data
          if not correspond or d.advanced_match_key~=matchkey or d.advanced_feature_key~=key then
            local matching=scope:scope(.35,.85);local reason
            if strict then correspond,reason=Match.run(guide_data,data,cfg,constraints,matching,budget:scope(matching))
            else correspond,reason=Guided.run(guide_data,data,guide_classic,dub_classic,cfg,classic_config(app,cfg),constraints,matching)end
            if not correspond then error(reason or U.error('no_usable_evidence','Could not build Advanced correspondences','match'),0)end
          end
        end
        if not correspond and cfg.strength~=0 then U.fail('no_usable_evidence','Analyze before planning Advanced timing','plan')end
        local planning=scope:scope(.85,1)
        local plan,err=Plan.build(guide_data,data,correspond,cfg,constraints,planning,budget:scope(planning),{owner=d.align_owner.extra})
        -- The renderer repeats this fade guard for the whole batch; checking it
        -- here keeps one dub's fade conflict from blocking the other dubs.
        if plan then local okf,whyf=Ownership.fades(plan,d.align_owner);if not okf then plan,err=nil,whyf end end
        if plan then plan.input_revision=request.config_revision;plan.request_id=request.request_id;plan.constraints_revision=a.constraints_revision end
        outputs[#outputs+1]={dub=d,audio=data,feature_key=key,correspondence=correspond,match_key=matchkey,plan=plan,error=err}
      end)
      account(budget)
      if not ok then
        -- A budget or evidence failure belongs to this dub; the others still
        -- publish. Cancellation, source changes and program errors stop the job.
        if type(failure)~='table' or not failure.code or failure.code=='source_changed' then error(failure,0)end
        outputs[#outputs+1]={dub=d,audio=data,feature_key=key,correspondence=nil,match_key=matchkey,plan=nil,error=failure}
      end
      scope:checkpoint(1,'Planned '..i..' / '..#dubs)
    end
    work:checkpoint(.98,'Validating captured session')
    local same,why=Audio.unchanged(app.r,reference);if not same then U.fail('source_changed',why,'analysis')end
    for _,d in ipairs(dubs)do check_source(app,d)end
    return {outputs=outputs,ref_audio=guide_data,budget=work.align_budget}
  end,cfg.frame_budget)
  job.kind=kind;job.live=kind=='timing';job.align_request=request;job.cfg=cfg;app.job=job
  return job
end
function M.start(app,legacy,recover)
  if busy(app)or not app.ref or #app.dubs==0 then return end
  if app.r.EnumProjects(-1)~=app.project then app:fail('Switch back to the captured project before analyzing.');return end
  if recover~=false then local ok,why=pcall(app.recapture_changed,app);if not ok then app:fail(why);return end end
  local ok,cfg=pcall(config,app);if not ok then app:fail(cfg);return end
  local request=token(app);app.alignment.need_match=false;app.alignment.need_plan=false
  prepare_job(app,'analysis',cfg,request)
end
function M.settings_changed(app,legacy,key)
  app:preferences_changed();app.revision=(app.revision or 0)+1
  local a=app.alignment;a.request_id=a.request_id+1;a.need_plan=true
  if key=='profile'or key=='search_s'or key=='advanced_pitch'or key=='constraints'or key=='max_ratio'or key=='matcher'then a.need_match=true end
  local available=false;for _,d in ipairs(app.dubs)do available=available or d.correspondence~=nil end
  app.pending_apply=available;app.live_due=nil;a.released=false
end
function M.control_released(app)
  app.alignment.released=true
  for _,d in ipairs(app.dubs)do if d.correspondence then app.pending_apply=true end end
end
function M.cancel(app,legacy)
  if app.job then app.alignment.last_job=job_report(app,app.job,'cancelled')end
  app.alignment.request_id=app.alignment.request_id+1;app.alignment.released=false
  legacy.cancel(app)
  for _,d in ipairs(app.dubs)do if d.status=='Analyzing'or d.status=='Planning'then d.status='Cancelled';d.plan=nil end end
end
local function publish(app,job)
  local out=job.result;app.ref_audio=out.ref_audio;local usable=0
  for _,entry in ipairs(out.outputs)do
    local d=entry.dub;d.audio=entry.audio;d.advanced_feature_key=entry.feature_key;d.advanced_match_key=entry.match_key
    d.correspondence=entry.correspondence;d.plan=entry.plan;d.full_plan=nil;d.stats=nil
    d.error=entry.error and tostring(entry.error)or nil;d.align_error=entry.error
    local code=type(entry.error)=='table'and entry.error.code
    local evidence_only=code=='no_usable_evidence'or code=='ambiguous_phrase'
    d.enabled=entry.plan~=nil;d.status=entry.plan and (entry.plan.unchanged and 'Timing preserved' or entry.plan.status=='partial'and 'Partial match' or 'Ready')or entry.correspondence and entry.correspondence.status=='ambiguous'and 'Ambiguous - no timing change' or entry.error and not evidence_only and 'Calculation failed' or 'No accepted timing'
    if entry.plan and entry.plan.solver and entry.plan.solver.approximate then d.status=d.status..' · approximate optimizer' end
    if entry.plan then usable=usable+1 elseif entry.error then app:report(d.snapshot.name..': '..tostring(entry.error))end
  end
  app.analyzed=usable>0;app.alignment.last_job=job_report(app,job,'completed')
  app.alignment.ready_request=job.align_request;app.pending_apply=usable>0;app.alignment.released=true
end
function M.tick(app,legacy)
  app.cleaner:tick();app.pitch:tick()
  if app.project and Audio.project_open(app.r,app.project)then
    local count=app.r.GetProjectStateChangeCount(app.project)
    if count~=app.project_state then
      for _,d in ipairs(app.dubs)do if d.original_state then local ok,why=Audio.check_dub(app.r,d);if not ok then
        -- изменение вне скрипта — статус дуба и одна запись в лог, а не ошибка на каждый шаг проекта
        app.pending_apply=false;d.status='Changed outside — Analyze again or Restore'
        if app.last_external~=why then app.last_external=why;app:report(why) end
      end end end
      app.project_state=count
    end
  end
  local a=app.alignment
  if app.job then
    local job=app.job;job:step()
    if app.operation then app.operation.progress=math.max(app.operation.progress,(job.progress or 0)*.98);app.operation.label=job.label end
    if job.done then
      app.job=nil
      if valid_request(app,job.align_request)then
        if job.error then a.last_job=job_report(app,job,'failed');app.pending_apply=false;app.operation=nil;app:fail(job.error);for _,d in ipairs(app.dubs)do if not d.plan then d.status='Calculation failed' end end
        else publish(app,job)end
      end
      app:save_group()
    end
  elseif app.pending_apply and not app.cleaner.job and not app.pitch.job and a.released and not app.gesture then
    if a.need_match then M.start(app,legacy,false)
    elseif a.need_plan then
      a.need_plan=false;prepare_job(app,'timing',config(app),token(app))
    else app.pending_apply=false;M.apply(app,legacy);app.operation=nil end
  else if not app.pending_apply then app.operation=nil end end
end
function M.apply(app,legacy,cfg)
  if busy(app)then return end
  if app.alignment.ready_request and not valid_request(app,app.alignment.ready_request)then app:fail('This Advanced result is stale. Analyze or release the current control again.');return end
  local n,why=Renderer.run(app,cfg or config(app),false)
  if not n then app:fail(tostring(why));app.alignment.last_apply_error=why;return false end
  app.error=nil;app.alignment.last_apply_error=nil;app.applied_revision=app.revision or 0
  app:report(n>0 and 'Applied Advanced timing to '..n..' dub(s).' or 'Captured timing preserved.');app:save_group();return true
end
function M.restore(app,legacy)
  if busy(app)then return end
  app.pending_apply=false;app.alignment.request_id=app.alignment.request_id+1;app.alignment.ready_request=nil
  local n,why=Renderer.run(app,config(app),true)
  if n then app.error=nil;app:report('Restored '..n..' captured take(s).')else app:fail(tostring(why))end
  app:save_group()
end
function M.diagnostics(app)
  local lines={'Vocaligner '..import('version').version..' | REAPER '..app.host_version,'Advanced Align v1 (experimental)',
    'Features are captured before timing writes. Evidence is not a probability.',''}
  local cfg=config(app);lines[#lines+1]='Effective settings: '..U.json(cfg)
  local a=app.alignment;lines[#lines+1]='Session '..a.session_id..' / baseline '..a.baseline_revision..' / request '..a.request_id
  local reference=app.ref_audio or a.diagnostic_features and app.ref and a.diagnostic_features[app.ref.guid]
  if reference and reference.analysis_stats then lines[#lines+1]='Reference analysis: '..U.json(reference.analysis_stats)end
  lines[#lines+1]='Pitch evidence: '..(cfg.advanced_pitch and 'enabled (F0/voicing evidence only; no pitch correction)'or 'off')
  if app.job then lines[#lines+1]='Current calculation: '..U.json(job_report(app,app.job))end
  for i,d in ipairs(app.dubs)do
    lines[#lines+1]=string.format('\nDUB %d: %s | %s | applied %s',i,d.snapshot.name,d.status,tostring(d.applied or false))
    local data=d.audio or a.diagnostic_features and a.diagnostic_features[d.snapshot.guid]
    if data and data.analysis_stats then lines[#lines+1]='Feature analysis: '..U.json(data.analysis_stats)end
    if d.correspondence then lines[#lines+1]='Evidence: '..U.json(d.correspondence.diagnostics)end
    if d.plan then lines[#lines+1]='Geometry: '..U.json(d.plan.validation);if d.plan.solver then lines[#lines+1]='Optimizer: '..U.json(d.plan.solver)end end
    if d.align_owner then for _,warning in ipairs(d.align_owner.warnings)do lines[#lines+1]='Warning: '..warning end;lines[#lines+1]='Cache assumption: '..d.align_owner.extra.file.assumption end
    if d.applied_plan and d.applied_plan~=d.plan then lines[#lines+1]='The previous applied timing is still audible; this preview has not replaced it.' end
    if d.error then lines[#lines+1]='Result: '..d.error end
  end
  if a.last_job then lines[#lines+1]='\nLast calculation: '..U.json(a.last_job)end
  if app.error then lines[#lines+1]='Last error: '..app.error end
  return table.concat(lines,'\n')
end
M.config=config
return M
