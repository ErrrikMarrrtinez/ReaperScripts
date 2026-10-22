-- @noindex
local import=...;local Notes=import('pitch/notes');local Store=import('pitch/store')
local Curve=import('pitch/curve');local Trace=import('pitch/trace');local FX=import('pitch/fx');local Algorithm=import('pitch/algorithm');local M={}
local function quote(s)
  return '"'..s:gsub('[%z\1-\31\\"]',function(c)
    local escapes={['"']='\\"',['\\']='\\\\',['\n']='\\n',['\r']='\\r',['\t']='\\t'}
    return escapes[c] or string.format('\\u%04x',c:byte())
  end)..'"'
end
-- Keep item-relative coordinates in every CSV, including a cropped export.
function M.range(r,s,project)
  local a,b=0,0
  if r.GetSet_LoopTimeRange2 then a,b=r.GetSet_LoopTimeRange2(project or 0,false,false,0,0,false)
  elseif r.GetSet_LoopTimeRange then a,b=r.GetSet_LoopTimeRange(false,false,0,0,false) end
  local selected=a and b and b>a
  local first,last=0,s.len
  if selected then
    first=math.max(0,a-s.pos);last=math.min(s.len,b-s.pos)
    -- выделение времени где-то в другом месте проекта — не ошибка: берём весь айтем
    if last<=first then selected=false;first,last=0,s.len end
  end
  return {kind=selected and 'time_selection' or 'whole_item',item_start_s=first,item_end_s=last,
    project_start_s=s.pos+first,project_end_s=s.pos+last,duration_s=last-first,
    csv_time_origin='item_start',full_item_state_retained=true}
end
function M.json(value,job)
  local seen,operations={},0
  local function encode(v)
    operations=operations+1;if job and operations%256==0 then job:checkpoint(nil,'Saving Pitch case') end
    local kind=type(v)
    if kind=='nil' then return 'null' end
    if kind=='boolean' then return tostring(v) end
    if kind=='number' then assert(v==v and math.abs(v)<math.huge,'Nonfinite case value');return string.format('%.17g',v) end
    if kind=='string' then return quote(v) end
    assert(kind=='table' and not seen[v],'Unsupported case value');seen[v]=true
    local array,count=true,0;local keys={}
    for k in pairs(v) do count=count+1;keys[#keys+1]=k;if type(k)~='number' or k%1~=0 or k<1 then array=false end end
    array=array and count==#v;local parts={}
    if array then for i=1,#v do parts[#parts+1]=encode(v[i]) end
    else
      table.sort(keys,function(a,b)return tostring(a)<tostring(b)end)
      for _,k in ipairs(keys) do parts[#parts+1]=quote(tostring(k))..':'..encode(v[k]) end
    end
    seen[v]=nil;return (array and '[' or '{')..table.concat(parts,',')..(array and ']' or '}')
  end
  return encode(value)
end
-- Read only: capture actual native points, full item/plugin state and source
-- identity before any file work. This never glues, renders, edits or reanalyses.
function M.capture(e)
  local r,s=e.r,e.snapshot;assert(s and e.data,'Analyze the selected item before exporting a case.')
  local range=M.range(r,s,e.project)
  local ok,chunk=r.GetItemStateChunk(s.item,'',false);assert(ok,'Cannot read the test item')
  local source={}
  for _,key in ipairs({'guid','source_key','render_key','pitch_key','name','pos','offset','len','rate','channels','sr',
    'source_rate','source_length','D_PITCH','B_PPITCH','B_LOOPSRC','B_MUTE','I_CHANMODE','D_VOL','I_PITCHMODE','I_STRETCHFLAGS','F_STRETCHFADESIZE'}) do source[key]=s[key] end
  source.file=r.GetMediaSourceFileName(s.source,'');source.markers=Notes.copy(s.markers)
  source.chain={};local parent=s.source
  for _=1,8 do
    local path=r.GetMediaSourceFileName(parent,'');local entry={file=path}
    if path~='' then source.file=path end
    if r.PCM_Source_GetSectionInfo then local yes,offset,len,reverse=r.PCM_Source_GetSectionInfo(parent)
      if yes then entry.section={offset=offset,len=len,reverse=reverse} end
    end
    source.chain[#source.chain+1]=entry
    parent=r.GetMediaSourceParent and r.GetMediaSourceParent(parent);if not parent then break end
  end
  local fx={}
  for index=0,r.TakeFX_GetCount(s.take)-1 do
    local _,name=r.TakeFX_GetFXName(s.take,index,'')
    local f={index=index,name=name,guid=r.TakeFX_GetFXGUID(s.take,index),enabled=r.TakeFX_GetEnabled(s.take,index),
      offline=r.TakeFX_GetOffline(s.take,index),params={},config={}}
    for p=0,r.TakeFX_GetNumParams(s.take,index)-1 do
      local _,label=r.TakeFX_GetParamName(s.take,index,p,'');local value=r.TakeFX_GetParamNormalized(s.take,index,p)
      local _,formatted=r.TakeFX_FormatParamValueNormalized(s.take,index,p,value,'')
      f.params[#f.params+1]={index=p,name=label,normalized=value,formatted=formatted}
    end
    if r.TakeFX_GetNamedConfigParm then for _,key in ipairs({'pdc','fx_ident','fx_type','chain_pdc_mode','instance_oversample_shift','chain_oversample_shift'}) do
      local yes,v=r.TakeFX_GetNamedConfigParm(s.take,index,key);if yes then f.config[key]=v end
    end end
    if f.guid==e.state.fx_guid then
      f.owned=true;f.envelopes=FX.envelopes(r,s.take,index)
      local info,why=Algorithm.read(r,s.take,index)
      if info then f.algorithm={value=info.value,mode=info.mode,submode=info.submode,label=Algorithm.label(r,info.value)} else f.algorithm_error=why end
    end
    fx[#fx+1]=f
  end
  local device={};if r.GetAudioDeviceInfo then for _,key in ipairs({'SRATE','BSIZE'}) do local yes,v=r.GetAudioDeviceInfo(key);if yes then device[key]=v end end end
  local _,project_file=r.EnumProjects(-1,'')
  local trackfx={};if r.GetMediaItemTrack and r.TrackFX_GetCount then
    local track=r.GetMediaItemTrack(s.item)
    for i=0,r.TrackFX_GetCount(track)-1 do local _,name=r.TrackFX_GetFXName(track,i,'');trackfx[#trackfx+1]=name end
  end
  -- Pitch Meter measurement of this item (after ReaPitch), if one is linked.
  local ok_meter,meter=pcall(function()return import('pitch/check').series(e)end)
  if not ok_meter then meter={found=false,status='Check unavailable: '..tostring(meter),frames={}} end
  local report=e.app:diagnostics()
  return {format='Vocaligner pitch case 1',created=os.date('%Y-%m-%d %H:%M:%S'),version=report:match('Vocaligner ([%d.]+)'),
    reaper=r.GetAppVersion(),project_file=project_file,source=source,state=Notes.copy(e.state),
    take_fx=fx,track_fx=trackfx,device=device,analysis=Notes.copy(e.last_analysis),report=report,
    analysis_model=e.data.model,hop=e.data.hop,frame_count=#e.data.frames,export_range=range,
    target_semantics='Predicted source F0 plus requested correction; not measured ReaPitch output.',
    target_support='Trace v3: blank source/target in unsupported audio; trust column is the voiced edge gate. CSV rows are limited to export_range; times remain item-relative.',
    stale=e.stale==true,editor_error=e.error,source_audio_copied=false,meter=meter,
    auto=e.state and e.state.auto and {config=Notes.copy(e.state.auto),stats=e.auto_layer and Notes.copy(e.auto_layer.stats),amount=e.auto_layer and e.auto_layer.amount,
      build_ms=e.auto_layer and e.auto_layer.build_ms,note=e.auto_note,root=e.root,scale=e.scale} or nil},chunk
end
local function number(v) return v~=nil and string.format('%.12g',v) or '' end
function M.write(e,folder,case,chunk,job)
  local range=case.export_range or {item_start_s=0,item_end_s=case.source.len,kind='whole_item'}
  local first,last=range.item_start_s,range.item_end_s
  local function included(t)return t>=first-1e-9 and t<=last+1e-9 end
  local function file(name)
    local f=assert(io.open(folder..'/'..name,'wb'),'Cannot write Pitch case: '..name)
    job.resources[f]=function(v)v:close()end;return f
  end
  local function close(f) assert(f:close());job.resources[f]=nil end
  local function put(name,text)local f=file(name);assert(f:write(text));close(f)end
  put('item.chunk',chunk);put('report.txt',case.report);case.report=nil
  local raw=file('analysis.csv');assert(raw:write('time_s,pitch_midi,confidence,level_db\n'))
  local analysis_count=0
  for i,f in ipairs(e.data.frames) do
    if included(f.t) then
      assert(raw:write(table.concat({number(f.t),number(f.pitch),number(f.confidence),number(f.level_db)},',')..'\n'))
      analysis_count=analysis_count+1
    end
    if i%256==0 then job:checkpoint(nil,'Saving Pitch analysis') end
  end;close(raw)
  local target=file('target.csv');assert(target:write('time_s,source_midi,target_midi,correction_st,trust,auto_st\n'))
  local Auto=import('pitch/auto');local layer=e.data and e.data._auto
  local at=Curve.evaluator(case.state.notes,'shift',case.state.curve_version or 1,e.data)
  case.analysis_frames_written=analysis_count
  local count=math.ceil((last-first)/.005-1e-9)
  for i=0,count do
    local t=math.min(first+i*.005,last);local source=Trace.sample(e.data,t);local _,trust=Trace.support(e.data,t)
    local correction=at(t)
    local auto=layer and Auto.value(layer,t)*(layer.amount or 1) or nil -- Auto до учёта ручных приоритетов (они уже в correction_st)
    assert(target:write(table.concat({number(t),number(source),number(source and source+correction),number(correction),number(trust),number(auto)},',')..'\n'))
    if i%128==0 then job:checkpoint(nil,'Saving Pitch target') end
  end;close(target)
  -- measured.csv: the meter's frames beside the prediction and the source at the same times.
  local meter=case.meter or {frames={}};local frames=meter.frames or {};meter.frames=nil
  local errors={};local measured_count=0
  local measured=file('measured.csv');assert(measured:write('time_s,project_time_s,measured_midi,measured_conf,state,predicted_midi,source_midi,delta_cents\n'))
  for i,f in ipairs(frames)do
    if included(f.t) then
    local source=Trace.sample(e.data,f.t);local predicted=source and source+at(f.t)
    local state=f.ambiguous and 'other_item' or not f.current and 'older_state' or f.provisional and 'provisional' or 'current'
    local delta=f.midi and predicted and (f.midi-predicted)*100
    if delta and state=='current' then errors[#errors+1]=math.abs(delta) end
    assert(measured:write(table.concat({number(f.t),number(f.t+case.source.pos),number(f.midi),number(f.conf),state,number(predicted),number(source),number(delta)},',')..'\n'))
    measured_count=measured_count+1
    end
    if i%256==0 then job:checkpoint(nil,'Saving Pitch measurement') end
  end;close(measured)
  table.sort(errors)
  local function q(x)return #errors>0 and errors[math.max(1,math.min(#errors,math.floor(#errors*x+.5)))] or nil end
  meter.frames_written=measured_count;meter.compared=#errors;meter.median_abs_cents=q(.5);meter.p95_abs_cents=q(.95)
  case.meter=meter
  put('source.txt',table.concat({
    'file='..(case.source.file or ''),
    string.format('item_position_s=%.9f',case.source.pos or 0),
    string.format('take_offset_s=%.9f',case.source.offset or 0),
    string.format('length_s=%.9f',case.source.len or 0),
    string.format('playrate=%.9f',case.source.rate or 1),
    'channels='..tostring(case.source.channels or ''),
    'export_range='..range.kind,
    string.format('export_item_start_s=%.9f',first),
    string.format('export_item_end_s=%.9f',last),
    'CSV time_s remains relative to the original item start; item.chunk and state retain the full item.',
    'The item plays file from take_offset_s for length_s*playrate seconds of source.',''},'\n'))
  put('case.json',M.json(case,job))
  put('COMPLETE.txt','Export complete. Audio files remain at source.file in case.json.\nCSV rows follow export_range; time_s remains item-relative. Full item state is retained for reconstruction.\nitem.chunk includes native FX configuration; target.csv is a prediction, analysis.csv is the measured input.\n')
  return folder
end
return M
