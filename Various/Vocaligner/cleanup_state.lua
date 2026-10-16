-- @noindex
local import=...;local Envelope=import('envelope');local Cleanup=import('cleanup');local DSP=import('dsp');local Config=import('config')
local M={}
local function same(a,b) return math.abs(a-b)<1e-7 end
function M.plan(s)
  return {snapshot=s,unchanged=true,volume_only=true,pos=s.pos,len=s.len,amount=0,
    markers={{t=0,target=s.pos},{t=s.len,target=s.pos+s.len}}}
end
local function regrid(curve,data,shift,ratio)
  if not curve then return nil end
  local out={points={},max_db=0,hop=curve.hop/ratio,detail=curve.detail}
  local times={0,data.len}
  for _,p in ipairs(curve.points)do local t=(p.t-shift)/ratio;if t>0 and t<data.len then times[#times+1]=t end end
  table.sort(times)
  for i,t in ipairs(times)do
    local db=Cleanup.value(curve,shift+t*ratio)
    out.points[i]={t=t,db=db};out.max_db=math.max(out.max_db,math.abs(db))
  end
  if curve.recipes then
    out.recipes={}
    for _,r in ipairs(curve.recipes)do
      local a,b=math.max(0,(r.a-shift)/ratio),math.min(data.len,(r.b-shift)/ratio)
      if b>a then out.recipes[#out.recipes+1]={a=a,b=b,cfg=Config.copy(r.cfg)} end
    end
  end
  out.frozen=regrid(curve.frozen,data,shift,ratio)
  return out
end
function M.check(r,d,current)
  local old=d.snapshot
  local gain_changed=old.item_gain~=current.item_gain
  if old.guid~=current.guid then return false,'The active take changed. Select it again or press Get.' end
  local geometry=not same(old.len,current.len) or not same(old.offset,current.offset) or not same(old.rate,current.rate)
  local shift=old.offset-current.offset
  local baseline=d.original_state or old
  local original=Envelope.shift(baseline.volume_envelope,shift)
  local original_points=Envelope.shift_points(baseline.volume_points,shift)
  local range=current.len*current.rate
  local matched,output=false,nil
  local function identify(delta)
    original=Envelope.shift(baseline.volume_envelope,delta)
    original_points=Envelope.shift_points(baseline.volume_points,delta)
    local best
    for _,out in pairs(d.outputs or {}) do
      if out.volume_envelope and Envelope.equivalent(current.volume_envelope,Envelope.shift(out.volume_envelope,delta),range,
        current.volume_points,Envelope.shift_points(out.volume_points,delta)) then
        if not best or (out.sequence or 0)>(best.sequence or 0) then best=out end
      end
    end
    if best then return true,best end
    if Envelope.equivalent(current.volume_envelope,original,range,current.volume_points,original_points) then return true,nil end
    return false
  end
  local known=d.outputs and d.outputs[current.signature]
  if shift==0 and d.verified_signature==current.signature then matched=true;output=d.verified_output or nil
  elseif shift==0 and type(known)=='table' then matched=true;output=known
  else matched,output=identify(shift) end
  if not matched and shift~=0 then
    -- A source slip can leave the native envelope at its original item time.
    -- Verify that actual curve before choosing its coordinate transform.
    matched,output=identify(0);if matched then shift=0 end
  end
  if not matched then return false,'The take volume envelope was edited outside Vocaligner. Undo that envelope edit to recover its saved baseline.' end
  local render_changed=old.render_key~=current.render_key or old.source_key~=current.source_key
  local layers=output and output.layers or nil
  local data=d.audio
  if geometry or render_changed then
    local no_wrap=old.source_length and old.offset>=0 and old.offset+old.len*old.rate<=old.source_length+.0001
    local linear=#old.markers==0 and #current.markers==0 and (no_wrap or old.B_LOOPSRC==0 and current.B_LOOPSRC==0)
    local first=(current.offset-old.offset)/old.rate
    local ratio=current.rate/old.rate
    local covered=first>=-1e-7 and first+current.len*ratio<=old.len+1e-7
    if data and not render_changed and linear and covered then
      local sliced={frames={},len=current.len,pos=current.pos,hop=data.hop,dynamics_only=data.dynamics_only,analysis_rate=data.analysis_rate,accessor_scale=data.accessor_scale}
      for i=0,math.ceil(current.len/data.hop)-1 do
        local src=data.frames[math.max(1,math.min(#data.frames,math.floor((first+i*data.hop)/data.hop+.5)+1))]
        local f={};for k,v in pairs(src) do f[k]=v end;f.t=i*data.hop;sliced.frames[#sliced.frames+1]=f
      end
      local cfg=Config.copy(d.cfg);cfg.cleanup_only=true;data=DSP.normalize(sliced,cfg)
      d.cache_status='source slice reused (10 ms grid)'
    else data=nil;d.cache_status='audio changed; analysis queued' end
    if layers then
      -- Preserve source-relative cuts even when a rate change requires a new read.
      local grid=data or {frames={},hop=.01,len=current.len}
      if not data then for i=0,math.ceil(current.len/.01)-1 do grid.frames[#grid.frames+1]={t=i*.01} end end
      local mapped={};for mode,curve in pairs(layers) do mapped[mode]=regrid(curve,grid,-shift/old.rate,ratio) end;layers=mapped
    end
    d.range={0,current.len};d.selected=false;d.view=nil;d.exclusions={};d.preview_valid=false
    d.outputs={};d.audio_dirty=true
  else d.cache_status='analysis reused' end
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
  if geometry or render_changed then
    local ok,quick=pcall(import('audio').peaks,r,current);d.quick=not data and ok and quick or nil
  elseif d.quick then d.quick.pos=current.pos end
  d.layers=layers;d.applied=output~=nil;d.applied_cleanup=output and output.cleanup or nil
  d.applied_cfg=output and output.cfg or nil;d.applied_plan=output and d.plan or nil
  if geometry or render_changed then
    if output then d.outputs[current.signature]={volume_envelope=current.volume_envelope,volume_points=current.volume_points,layers=layers,cfg=output.cfg,
      cleanup=output.cleanup,envelope_points=output.envelope_points,plan=d.plan,sequence=output.sequence} end
  elseif moved then
    -- Other undo/redo variants keep the same source-relative envelope and layers.
    for _,out in pairs(d.outputs or {}) do out.plan=d.plan end
  end
  d.envelope_points=output and output.envelope_points or 0
  d.verified_signature=current.signature
  d.verified_output=(geometry or render_changed) and (d.outputs[current.signature] or false) or (output or false)
  return true,nil,geometry or render_changed or moved,gain_changed
end
return M
