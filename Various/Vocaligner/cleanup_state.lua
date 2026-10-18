-- @noindex
local import=...;local Envelope=import('envelope');local Cleanup=import('cleanup');local DSP=import('dsp');local Config=import('config')
local Audio=import('audio');local Curves=import('compressor/curves')
local M={}
local function same(a,b) return math.abs(a-b)<1e-7 end
function M.plan(s)
  return {snapshot=s,unchanged=true,volume_only=true,pos=s.pos,len=s.len,amount=0,
    markers={{t=0,target=s.pos},{t=s.len,target=s.pos+s.len}}}
end
-- Fields that change how the source sounds. Play rate, offset and length only
-- move the same audio; stretch markers warp it and need a new read.
local content_fields={'D_PITCH','B_PPITCH','I_CHANMODE','I_PITCHMODE','I_STRETCHFLAGS','F_STRETCHFADESIZE'}
local function content_key(s)
  local out={tostring(s.source_key),tostring(s.B_LOOPSRC)}
  for _,k in ipairs(content_fields) do out[#out+1]=string.format('%.17g',s[k] or 0) end
  return table.concat(out,'|')
end
local function same_markers(a,b)
  if #a.markers~=#b.markers then return false end
  for i,m in ipairs(a.markers) do local n=b.markers[i]
    if not same(m.pos,n.pos) or not same(m.src,n.src) or not same(m.slope,n.slope) then return false end
  end
  return true
end
-- Item time on one snapshot -> item time on another, through the source audio.
-- Covers trims, slips, play-rate changes and stretch markers alike.
local function mapper(old,current)
  return function(t) return Audio.item_time(current,Audio.source_time(old,t)) end,
    function(t) return Audio.item_time(old,Audio.source_time(current,t)) end
end
local function regrid(curve,fwd,inv,len,extra)
  if not curve then return nil end
  local out={points={},max_db=0,hop=curve.hop,detail=curve.detail}
  local times={0,len}
  for _,p in ipairs(curve.points or {})do local t=fwd(p.t);if t>0 and t<len then times[#times+1]=t end end
  for _,t in ipairs(extra or {})do if t>0 and t<len then times[#times+1]=t end end
  table.sort(times);local previous=-1
  for _,t in ipairs(times)do if t>previous+1e-9 then
    local db=Cleanup.value(curve,inv(t))
    out.points[#out.points+1]={t=t,db=db};out.max_db=math.max(out.max_db,math.abs(db));previous=t
  end end
  if curve.recipes then
    out.recipes={}
    for _,r in ipairs(curve.recipes)do
      local a,b=math.max(0,fwd(r.a)),math.min(len,fwd(r.b))
      if b>a then out.recipes[#out.recipes+1]={a=a,b=b,cfg=Config.copy(r.cfg)} end
    end
  end
  for _,shape in ipairs(curve.shapes or {})do
    local a,b=fwd(shape.a),fwd(shape.b)
    if a>=0 and b<=len and b>a then out.shapes=out.shapes or {};out.shapes[#out.shapes+1]={a=a,b=b,tension=shape.tension} end
  end
  out.frozen=regrid(curve.frozen,fwd,inv,len,extra)
  return out
end
local function map_layers(layers,fwd,inv,len,extra)
  if not layers then return nil end
  local out={};for mode,curve in pairs(layers)do out[mode]=regrid(curve,fwd,inv,len,extra) end;return out
end
local function copy(t) if not t then return nil end;local o={};for k,v in pairs(t)do o[k]=v end;return o end
-- The reduction we wrote, as one dB curve in item time.
function M.ours(layers,len)
  if not layers or not next(layers) then return nil end
  return Curves.sum({len=len,hop=.01},layers)
end
-- Spans where our reduction is not unity. Outside them the native envelope is
-- the user's own and is kept point for point.
local function spans(ours,len)
  local out,start={},nil;local points=ours.points
  for i,p in ipairs(points)do
    local on=math.abs(p.db)>1e-4
    if on and not start then start=i>1 and points[i-1].t or p.t end
    if not on and start then out[#out+1]={a=start,b=p.t};start=nil end
  end
  if start then out[#out+1]={a=start,b=len} end
  return out
end
-- The envelope was changed outside Vocaligner (a manual edit, a script, an
-- Undo state we never saw). Keep it: the new baseline is the current envelope
-- with our known reduction divided out, so the next apply multiplies the same
-- reduction onto the user's edit instead of replacing it.
function M.rebase(r,s,ours)
  local chunk=s.volume_envelope
  if not chunk or not ours or ours.max_db<1e-6 or not r.GetTakeEnvelopeByName then return chunk,s.volume_points end
  local env=r.GetTakeEnvelopeByName(s.take,'Volume');if not env then return chunk,s.volume_points end
  local mode=r.GetEnvelopeScalingMode(env);local rate,len=s.rate,s.len
  local active=spans(ours,len)
  local function inside(t,strict)
    local lo,hi=1,#active
    while lo<=hi do
      local mid=(lo+hi)//2;local e=active[mid]
      if t<e.a-1e-9 then hi=mid-1 elseif t>e.b+1e-9 then lo=mid+1
      else return not strict or t>e.a+1e-9 and t<e.b-1e-9,e end
    end
    return false
  end
  -- Native point lines are copied verbatim, so shapes and tension survive.
  local header,lines={},{};local described=s.volume_points or {}
  for line in chunk:gmatch('[^\r\n]+')do
    if line:match('^%s*PT%s') then lines[#lines+1]=line
    elseif not line:match('^%s*>%s*$') then header[#header+1]=line end
  end
  local exact=#lines==#described
  local rows={}
  for i,line in ipairs(lines)do
    local time=tonumber(line:match('^%s*PT%s+(%S+)'))
    if time and not inside(time/rate,true) then
      local p=exact and described[i] or {t=time,v=tonumber(line:match('^%s*PT%s+%S+%s+(%S+)')) or 1,shape=0,tension=0}
      rows[#rows+1]={time=time,line=line,point={t=p.t,v=p.v,shape=p.shape,tension=p.tension}}
    end
  end
  local shapes=ours.shapes or {}
  local function curved(t)
    for _,shape in ipairs(shapes)do if t>shape.a+1e-9 and t<shape.b-1e-9 then return true end end
  end
  for _,span in ipairs(active)do
    local times={span.a,span.b}
    for _,line in ipairs(lines)do local time=tonumber(line:match('^%s*PT%s+(%S+)'))
      if time and time/rate>span.a and time/rate<span.b then times[#times+1]=time/rate end
    end
    for _,p in ipairs(ours.points)do if p.t>span.a and p.t<span.b then times[#times+1]=p.t end end
    for t=math.ceil(span.a/.01)*.01,span.b,.01 do times[#times+1]=t end
    table.sort(times)
    local samples={};local previous=-1
    for _,t in ipairs(times)do if t>previous+1e-9 and t>=span.a-1e-9 and t<=span.b+1e-9 and not curved(t) then
      local _,v=r.Envelope_Evaluate(env,t*rate,0,0)
      local amp=r.ScaleFromEnvelopeMode(mode,v)*10^(Cleanup.value(ours,t)/20)
      local value=r.ScaleToEnvelopeMode(mode,amp)
      samples[#samples+1]={time=t*rate,value=value,epsilon=math.max(.0001,math.abs(value)*.001)};previous=t
    end end
    local keep=#samples>1 and Envelope.simplify(samples,{}) or {[1]=true}
    for i,p in ipairs(samples)do if keep[i] then
      rows[#rows+1]={time=p.time,sample=true,line=string.format('PT %.17g %.17g 0',p.time,p.value),point={t=p.time,v=p.value,shape=0,tension=0}}
    end end
  end
  -- A native point on a span edge gives way to the linear sample there.
  table.sort(rows,function(a,b)if a.time==b.time then return a.sample and not b.sample end;return a.time<b.time end)
  local kept={}
  for _,row in ipairs(rows)do
    local last=kept[#kept]
    if not last or row.time-last.time>=1e-9 then kept[#kept+1]=row
    elseif row.sample and not last.sample then kept[#kept]=row end
  end
  local out,points={},{};for _,line in ipairs(header)do out[#out+1]=line end
  for i,row in ipairs(kept)do out[#out+1]=row.line;points[i]=row.point end
  out[#out+1]='>'
  return table.concat(out,'\n')..'\n',points
end
local function entry(state) return {volume_envelope=state.volume_envelope,volume_points=state.volume_points} end
-- Dragging a point outside Vocaligner produces a new kept state per step.
-- Keep the newest ones so Undo/Redo stays recognisable without growing forever.
local function prune(outputs,limit)
  local list={};for key,out in pairs(outputs)do if type(out)=='table' then list[#list+1]={key=key,sequence=out.sequence or 0} end end
  if #list<=limit then return end
  table.sort(list,function(a,b)return a.sequence>b.sequence end)
  for i=limit+1,#list do outputs[list[i].key]=nil end
end
function M.check(r,d,current)
  local old=d.snapshot
  local gain_changed=old.item_gain~=current.item_gain or old.D_VOL~=current.D_VOL
  if old.guid~=current.guid then return false,'The active take changed. Select it again or press Get.' end
  local markers_changed=not same_markers(old,current)
  local geometry=not same(old.len,current.len) or not same(old.offset,current.offset) or not same(old.rate,current.rate) or markers_changed
  local shift=old.offset-current.offset
  local baseline=d.original_state or old
  local original=Envelope.shift(baseline.volume_envelope,shift)
  local original_points=Envelope.shift_points(baseline.volume_points,shift)
  local range=current.len*current.rate
  local matched,output=false,nil
  local function equal(state,delta)
    return Envelope.equivalent(current.volume_envelope,Envelope.shift(state.volume_envelope,delta),range,
      current.volume_points,Envelope.shift_points(state.volume_points,delta))
  end
  local function use(state,delta)
    original=Envelope.shift(state.volume_envelope,delta);original_points=Envelope.shift_points(state.volume_points,delta)
  end
  -- An output remembers the baseline it was built on; an Undo across a kept
  -- manual edit must return to that baseline, not to the newest one.
  local function identify(delta)
    use(baseline,delta)
    local best
    for _,out in pairs(d.outputs or {}) do
      if type(out)=='table' and out.volume_envelope and equal(out,delta) then
        if not best or (out.sequence or 0)>(best.sequence or 0) then best=out end
      end
    end
    if best then if best.baseline then use(best.baseline,delta) end;return true,best end
    if equal(baseline,delta) then return true,nil end
    for i=#(d.baselines or {}),1,-1 do
      local state=d.baselines[i]
      if equal(state,delta) then use(state,delta);return true,nil end
    end
    return false
  end
  local known=d.outputs and d.outputs[current.signature]
  -- Same native state as the last check: in-memory layers stay authoritative
  -- (a Bypass being lifted is staged in d.layers until it is written).
  local verified=shift==0 and d.verified_signature==current.signature
  if verified then matched=true;output=d.verified_output or nil
  elseif shift==0 and type(known)=='table' then matched=true;output=known;if known.baseline then use(known.baseline,0) end
  else matched,output=identify(shift) end
  if not matched and shift~=0 then
    -- A source slip can leave the native envelope at its original item time.
    -- Verify that actual curve before choosing its coordinate transform.
    matched,output=identify(0);if matched then shift=0 end
  end
  local adopted=false
  if not matched then
    -- Never lock the item: keep what is there and treat our last known result
    -- as the reduction inside it.
    adopted=true
    -- Another take's record: its stages are not in this envelope. Start clean.
    if d.foreign then output=nil
    elseif d.verified_signature then output=d.verified_output or nil
    else
      for _,out in pairs(d.outputs or {})do
        if type(out)=='table' and out.layers and (not output or (out.sequence or 0)>(output.sequence or 0)) then output=out end
      end
    end
  end
  local content_changed=content_key(old)~=content_key(current)
  local layers=output and output.layers or nil
  local bypassed=output and output.bypassed or d.bypassed
  local data=d.audio
  local fwd,inv
  if geometry or content_changed then
    fwd,inv=mapper(old,current)
    local no_wrap=old.source_length and old.offset>=0 and old.offset+old.len*old.rate<=old.source_length+.0001
    local linear=#old.markers==0 and #current.markers==0 and (no_wrap or old.B_LOOPSRC==0 and current.B_LOOPSRC==0)
    local covered=inv(0)>=-1e-7 and inv(current.len)<=old.len+1e-7
    if data and not content_changed and linear and covered then
      -- Trims and play-rate changes reuse the analysis through the time map.
      local sliced={frames={},len=current.len,pos=current.pos,hop=data.hop,dynamics_only=data.dynamics_only,analysis_rate=data.analysis_rate,accessor_scale=data.accessor_scale}
      for i=0,math.ceil(current.len/data.hop)-1 do
        local src=data.frames[math.max(1,math.min(#data.frames,math.floor(inv(i*data.hop)/data.hop+.5)+1))]
        local f={};for k,v in pairs(src) do f[k]=v end;f.t=i*data.hop;sliced.frames[#sliced.frames+1]=f
      end
      local cfg=Config.copy(d.cfg);cfg.cleanup_only=true;data=DSP.normalize(sliced,cfg)
      d.cache_status=same(old.rate,current.rate) and 'source slice reused (10 ms grid)' or 'source slice reused at the new play rate'
    else data=nil;d.cache_status=markers_changed and 'stretch markers changed; analysis queued' or 'audio changed; analysis queued' end
    -- Preserve source-relative cuts, also when a new read is required.
    local extra={};for _,m in ipairs(current.markers)do extra[#extra+1]=m.pos/current.rate end
    layers=map_layers(layers,fwd,inv,current.len,extra)
    bypassed=map_layers(bypassed,fwd,inv,current.len,extra)
    local exclusions={}
    for _,e in ipairs(d.exclusions or {})do
      local a,b=math.max(0,fwd(e.start)),math.min(current.len,fwd(e.finish))
      if b>a then exclusions[#exclusions+1]={kind=e.kind,start=a,finish=b} end
    end
    d.range={0,current.len};d.selected=false;d.view=nil;d.exclusions=exclusions;d.preview_valid=false
    d.outputs={};d.baselines=nil;d.audio_dirty=true
  elseif not adopted then d.cache_status='analysis reused' end
  if adopted then
    local ours=M.ours(layers,current.len)
    local chunk,points=M.rebase(r,current,ours)
    if not (geometry or content_changed) then
      -- Earlier states stay recognisable for Undo/Redo with their own baselines.
      for _,out in pairs(d.outputs or {})do if type(out)=='table' and not out.baseline then out.baseline=entry(baseline) end end
      d.baselines=d.baselines or {};d.baselines[#d.baselines+1]=entry(baseline)
      while #d.baselines>8 do table.remove(d.baselines,1) end
    end
    original,original_points=chunk,points
    if ours and current.volume_envelope then
      d.output_sequence=(d.output_sequence or 0)+1
      output={cleanup=ours,layers=layers,cfg=output and output.cfg or nil,bypassed=bypassed,
        volume_envelope=current.volume_envelope,volume_points=current.volume_points,
        envelope_points=#(current.volume_points or {}),sequence=d.output_sequence,baseline={volume_envelope=chunk,volume_points=points}}
    else output=nil;layers=nil end
    d.cache_status='kept an envelope edit made outside Vocaligner'
  end
  local moved=not same(old.pos,current.pos)
  if moved and d.view then d.view.start=d.view.start+current.pos-old.pos end
  current.channels=r.GetMediaSourceNumChannels(current.source)
  -- This is the baseline snapshot, never the already attenuated output.
  local now={};for k,v in pairs(current) do now[k]=v end
  now.cleanup_capture=true;current.cleanup_capture=true
  now.volume_envelope=original
  now.volume_points=original_points
  d.snapshot=now;d.plan=M.plan(now);d.original_state=now;d.read_snapshot=current
  d.audio=data;if data then data.pos=current.pos;data.snapshot=now end
  if geometry or content_changed then
    local ok,quick=pcall(import('audio').peaks,r,current);d.quick=not data and ok and quick or nil
  elseif d.quick then d.quick.pos=current.pos end
  -- Keep one applied curve per output: Cleaner compares its identity.
  local applied
  if output then
    if not (geometry or content_changed) and output.cleanup and output.cleanup.points then applied=output.cleanup
    else
      applied=M.ours(layers,current.len) or {points={},max_db=0,hop=.01}
      if not (geometry or content_changed) then output.cleanup=applied end
    end
  end
  if not verified then d.layers=layers end
  d.applied=output~=nil;d.applied_cleanup=applied
  if geometry or content_changed then d.bypassed=bypassed elseif output and output.bypassed and not verified then d.bypassed=copy(output.bypassed) end
  d.applied_cfg=output and output.cfg or nil;d.applied_plan=output and d.plan or nil
  if output and (geometry or content_changed or adopted) then
    d.outputs=d.outputs or {}
    d.outputs[current.signature]={volume_envelope=current.volume_envelope,volume_points=current.volume_points,layers=layers,cfg=output.cfg,
      cleanup=d.applied_cleanup,envelope_points=output.envelope_points,plan=d.plan,sequence=output.sequence,bypassed=bypassed,
      baseline=adopted and output.baseline or nil}
    if adopted then prune(d.outputs,40) end
  elseif moved then
    -- Other undo/redo variants keep the same source-relative envelope and layers.
    for _,out in pairs(d.outputs or {}) do out.plan=d.plan end
  end
  d.envelope_points=output and output.envelope_points or 0
  d.verified_signature=current.signature;d.foreign=nil
  d.verified_output=(geometry or content_changed or adopted) and (d.outputs and d.outputs[current.signature] or false) or (output or false)
  return true,nil,geometry or content_changed or moved,gain_changed,adopted
end
return M
