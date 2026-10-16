-- @noindex
local import=...;local U=import('align/util');local Job=import('job');local D=import('align/advanced/defaults');local M={}
local function pick(t,keys)local out={};for _,k in ipairs(keys)do if t then out[k]=t[k]end end;return out end
local function clean(v,depth)
  depth=depth or 0;assert(depth<32,'Case nesting limit')
  if type(v)=='number'then return U.finite(v)and v or nil end
  if type(v)=='string'or type(v)=='boolean'then return v end
  if type(v)~='table'then return nil end
  -- Index-keyed tables are only JSON arrays when they are dense sequences.
  -- Sparse knot flags such as plan.problem.mandatory become string-keyed
  -- objects instead of failing the whole export.
  local n=0;for _ in pairs(v)do n=n+1 end
  local sequence=n==#v;if sequence then for i=1,n do if v[i]==nil then sequence=false;break end end end
  local out={}
  for k,x in pairs(v)do
    local value=clean(x,depth+1)
    if type(k)=='string'then out[k]=value
    elseif type(k)=='number'then
      if sequence then out[k]=value==nil and false or value else out[string.format(k%1==0 and '%d' or '%.17g',k)]=value end
    end
  end
  return out
end
local function snapshot(s,id)
  local out=pick(s,{'pos','len','rate','offset','channels','source_rate','source_length','D_PITCH','B_PPITCH','B_LOOPSRC','I_CHANMODE','D_VOL','I_PITCHMODE','I_STRETCHFLAGS','F_STRETCHFADESIZE','markers','volume_points'})
  out.guid=id;out.capture_fingerprint=U.hash(s.signature)
  if s.composite then
    out.parts={}
    for k,p in ipairs(s.parts)do out.parts[k]={index=k,pos=p.pos,len=p.len,offset=p.offset,rate=p.rate,markers=p.markers,capture_fingerprint=U.hash(p.signature)}end
  end
  return clean(out)
end
function M.capture(app)
  assert(app.ref and #app.dubs>0,'Capture a reference and dubs first')
  local a=app.alignment;local case={format='Vocaligner Align case',schema_version=1,version=import('version').version,
    created=os.date('!%Y-%m-%dT%H:%M:%SZ'),engine_id=app.align_engine,feature_schema=app.align_engine=='advanced_v1'and D.frontend or 'legacy_v012',
    reaper=app.host_version,session_id=U.hash(a.session_id),baseline_revision=a.baseline_revision,request_id=a.request_id,
    settings=clean(app.align_engine=='advanced_v1'and D.config(app.cfg)or app.cfg),source_audio_copied=false,paths_included=false,
    semantics='Captured features and planned maps; no measurement of rendered output. Evidence is not probability.',
    reference=snapshot(app.ref,'guide'),dubs={},last_job=clean(a.last_job),last_error=app.error,
    reference_ownership=clean(a.guide_owner and pick(a.guide_owner.extra,{'fades','channels','take_count'}))}
  local diagnostic=app.align_engine=='advanced_v1'and a.diagnostic_features or {}
  diagnostic=diagnostic or {}
  local features={{id='guide',data=app.ref_audio or diagnostic[app.ref.guid]}}
  case.reference_analysis=clean(features[1].data and features[1].data.analysis_stats)
  for i,d in ipairs(app.dubs)do
    local c=d.correspondence;local p=d.plan
    local entry={id='dub-'..i,capture=snapshot(d.snapshot,'dub-'..i),status=d.status,applied=d.applied==true,
      applied_is_current=d.applied_plan==p,error_code=d.align_error and d.align_error.code,
      constraints=clean(a.constraints[d.snapshot.guid]or {}),plan=clean(pick(p,{'engine_id','engine_version','renderer_id','pos','len','amount','status','unchanged','exact_baseline','markers','dense','problem','regions','solver','validation','diagnostics','native_readback','hybrid','pieces','summary'})),
      evidence=clean(c and c.diagnostics),segments=clean(c and c.segments),unmatched=clean(c and c.unmatched),phrases={},
      ownership=clean(d.align_owner and pick(d.align_owner.extra,{'fades','channels','take_count'})),error=d.error}
    for _,constraint in ipairs(entry.constraints)do if constraint.guide_guid then constraint.guide_guid='guide'end end
    for _,phrase in ipairs(c and c.phrases or {})do
      local row={phrase=clean(phrase.phrase),status=phrase.status,reason=phrase.reason,candidates=clean(phrase.candidates),local_evidence=clean(phrase.local_evidence),variant_count=phrase.variant_count,results={}}
      for _,result in ipairs(phrase.results)do row.results[#row.results+1]=clean(pick(result,{'candidate','score','raw_cost','evidence','margin','margin_status','search_incomplete','eligible','rejection_reasons','path','gaps','local_alternatives'}))end
      entry.phrases[#entry.phrases+1]=row
    end
    case.dubs[#case.dubs+1]=entry;features[#features+1]={id=entry.id,data=d.audio or diagnostic[d.snapshot.guid]}
    entry.feature_analysis=clean(features[#features].data and features[#features].data.analysis_stats)
  end
  return case,features
end
local scalar={'t','left','right','mass','event','background','onset','change','energy','valid_fraction','missing','voicing_available','voiced','pitch','pitch_delta','pitch_reliability','spectral_reliability','cep_reliability','onset_reliability','energy_reliability','delta_valid','trustworthy'}
function M.write(folder,case,features,job)
  local files={};local total=0
  local function write(name,body)
    assert(#body<=64*1024*1024,'Case file limit');total=total+#body;assert(total<=256*1024*1024,'Case size limit')
    local f=assert(io.open(folder..'/'..name,'wb'));if job then job.resources[f]=function(v)v:close()end end
    assert(f:write(body));assert(f:close());if job then job.resources[f]=nil end
    files[#files+1]={name=name,bytes=#body,fnv1a32=U.hash(body)}
  end
  for _,entry in ipairs(features)do if entry.data then
    local rows={table.concat(scalar,',')..',spec_1_to_32,cep_1_to_12,delta_1_to_6,raw_cep_1_to_12,mel_1_to_32'}
    -- Explicit columns permit replay without executing Lua or evaluating text.
    local header={};for _,k in ipairs(scalar)do header[#header+1]=k end
    for _,v in ipairs({{'spec',32},{'cep',12},{'delta',6},{'raw_cep',12},{'mel',32}})do for j=1,v[2]do header[#header+1]=v[1]..'_'..j end end
    rows[1]=table.concat(header,',')
    for i,f in ipairs(entry.data.frames or {})do
      local values={};local function add(v)values[#values+1]=type(v)=='boolean'and (v and '1'or '0')or U.finite(v)and string.format('%.17g',v)or ''end
      for _,k in ipairs(scalar)do add(f[k])end
      for _,v in ipairs({{'spec',32},{'cep',12},{'delta',6},{'raw_cep',12},{'mel',32}})do for j=1,v[2]do add(f[v[1]]and f[v[1]][j])end end
      rows[#rows+1]=table.concat(values,',');if i%128==0 then U.checkpoint(job,nil,'Exporting Align features')end
    end
    write(entry.id..'-features.csv',table.concat(rows,'\n')..'\n')
  end end
  write('case.json',U.json(case))
  -- Consumers accept the folder only after this final manifest is present and
  -- every declared byte count/checksum agrees. FNV is an integrity check, not security.
  write('complete.json',U.json({schema_version=1,complete=true,files=files,checksum='fnv1a32'}))
  return folder
end
function M.run(app)
  if app.job or app.align_export_job or not app.ref then return end
  local ok,case,features=pcall(M.capture,app);if not ok then app:fail(case);return end
  local folder=app.r.GetResourcePath()..'/Data/VocalignerAlignCases/'..os.date('%Y%m%d-%H%M%S')..'-'..U.hash(app.alignment.session_id..tostring(app.r.time_precise()))
  app.align_export_job=Job.new(app.r,function(job)
    job:call(app.r.RecursiveCreateDirectory,folder,0)
    return M.write(folder,case,features,job)
  end,.008)
end
return M
