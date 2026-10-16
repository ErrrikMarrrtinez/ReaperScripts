-- @noindex
local import=...;local Audio=import('audio');local Envelope=import('envelope');local State=import('cleanup_state');local U=import('align/util');local Warp=import('warp');local M={}
local reference_apps=setmetatable({},{__mode='k'})
-- Geometry and Volume have separate owners. Only a verified Cleaner output may
-- advance the Volume owner while an Align source baseline remains immutable.
function M.geometry(s)
  local out={s.guid,tostring(s.source)}
  for _,k in ipairs({'D_POSITION','D_LENGTH','B_LOOPSRC','B_MUTE','C_LOCK','D_STARTOFFS','D_PLAYRATE','D_PITCH','B_PPITCH','I_CHANMODE','D_VOL','I_PITCHMODE','I_STRETCHFLAGS','F_STRETCHFADESIZE'})do
    out[#out+1]=string.format('%.17g',s[k]or 0)
  end
  for _,m in ipairs(s.markers)do out[#out+1]=string.format('%.17g:%.17g:%.17g',m.pos,m.src,m.slope or 0)end
  return table.concat(out,'|')
end
-- Native item-chunk writes can replace PCM pointers and round marker text.
-- Source identity and the numeric map remain authoritative, including every
-- child of a grouped role. Volume is verified separately against Cleaner.
function M.same_geometry(a,b)
  if not a or not b or a.guid~=b.guid or a.composite~=b.composite then return false end
  if a.composite then
    if #a.parts~=#b.parts then return false end
    for i,p in ipairs(a.parts)do if not M.same_geometry(p,b.parts[i])then return false end end
    return true
  end
  if a.source_key~=b.source_key then return false end
  local function same(x,y)return math.abs((x or 0)-(y or 0))<=1e-7 end
  for _,k in ipairs({'D_POSITION','D_LENGTH','B_LOOPSRC','B_MUTE','C_LOCK','D_STARTOFFS','D_PLAYRATE','D_PITCH','B_PPITCH','I_CHANMODE','D_VOL','I_PITCHMODE','I_STRETCHFLAGS','F_STRETCHFADESIZE','item_gain','fade_in','fade_out'})do
    if not same(a[k],b[k])then return false end
  end
  if #a.markers~=#b.markers then return false end
  for i,p in ipairs(a.markers)do local q=b.markers[i]
    if not same(p.pos,q.pos)or not same(p.src,q.src)or not same(p.slope,q.slope)then return false end
  end
  return true
end
local function source_local(s,source)
  if #s.markers==0 then return (source-s.offset)/s.rate end
  local a=s.markers;local lo,hi=1,#a
  while hi-lo>1 do local mid=(lo+hi)//2;if a[mid].src<=source then lo=mid else hi=mid end end
  return (a[lo].pos+(a[hi].pos-a[lo].pos)*(source-a[lo].src)/(a[hi].src-a[lo].src))/s.rate
end
function M.transport(from,to)
  local points={0,from.len}
  for _,m in ipairs(from.markers)do points[#points+1]=m.pos/from.rate end
  for _,m in ipairs(to.markers)do points[#points+1]=source_local(from,m.source)end
  table.sort(points);local markers={};local unchanged=math.abs(from.len-to.len)<1e-8
  local at=import('align/advanced/validate').source_target
  for _,t in ipairs(points)do if t>=-1e-8 and t<=from.len+1e-8 and (#markers==0 or t-markers[#markers].t>1e-9)then
    t=U.clamp(t,0,from.len);local source=Audio.source_time(from,t);local target=assert(at(to.markers,source),'Timing transport lost source content')
    markers[#markers+1]={t=t,target=target,source=source};unchanged=unchanged and math.abs(target-to.pos-t)<1e-8
  end end
  return {snapshot=from,pos=to.pos,len=to.len,markers=markers,unchanged=unchanged}
end
local function find(app,d,current)
  local c=app.cleaner;local bucket=c.cache[current.project or app.project]
  for _,cd in ipairs(bucket and bucket.items or c.items or {})do
    if cd.snapshot.guid==d.snapshot.guid and cd.snapshot.item==d.snapshot.item and not cd.stale and not cd.restore_value then
      if M.same_geometry(cd.snapshot,current)and Audio.check_dub(app.r,cd)then return cd end
    end
  end
end
M.find=find
local function verified_volume(app,known,current)
  local before,after=Audio.parts(known),Audio.parts(current)
  if #before~=#after then return false end
  for i,p in ipairs(before)do local now=after[i]
    if p.guid~=now.guid then return false end
    if p.signature~=now.signature and not find(app,{snapshot=p},now)then return false end
  end
  return true
end
function M.remember(app)
  local revision=app.r.GetProjectStateChangeCount and app.r.GetProjectStateChangeCount(app.project)
  if revision and revision==app.align_remember_revision then return end
  app.align_remember_revision=revision
  for _,d in ipairs(app.dubs)do
    local ok,now=pcall(Audio.current,app.r,d.snapshot)
    if ok and d.outputs and type(d.outputs[now.signature])=='table'then d.outputs[now.signature].native_state=now end
  end
end
function M.reconcile(app)
  if not app.project or not Audio.project_open(app.r,app.project)then return end
  if app.ref then reference_apps[app.ref]=app end
  local revision=app.r.GetProjectStateChangeCount and app.r.GetProjectStateChangeCount(app.project)
  if revision and revision==app.align_reconcile_revision then return end
  app.align_reconcile_revision=revision
  for _,d in ipairs(app.dubs)do
    local yes,current=pcall(Audio.current,app.r,d.snapshot)
    local owned=yes and d.outputs and d.outputs[current.signature]
    if yes and current.signature==d.snapshot.signature then d.align_volume_state=nil
    elseif type(owned)=='table'then d.align_volume_state=owned.volume_origin end
    if yes and current.signature~=d.snapshot.signature and not owned then
      local known=M.same_geometry(current,d.snapshot)and {timing_applied=false,native_state=d.snapshot}or nil
      for _,out in pairs(d.outputs or {})do if type(out)=='table'and out.native_state and M.same_geometry(out.native_state,current)
        and (not known or (out.sequence or 0)>=(known.sequence or 0))then known=out end end
      if known and verified_volume(app,known.native_state,current)then
        d.align_volume_state=current;d.align_volume_revision=(d.align_volume_revision or 0)+1
        d.outputs=d.outputs or {};d.output_sequence=(d.output_sequence or 0)+1
        d.outputs[current.signature]={plan=known.plan,timing_applied=known.timing_applied,volume_envelope=current.volume_envelope,
          volume_points=current.volume_points,envelope_points=#(current.volume_points or {}),native_state=current,sequence=d.output_sequence,
          volume_owner='cleanup_chain',volume_origin=current}
        Audio.check_dub(app.r,d)
      end
    end
  end
end
function M.read_snapshot(app,s)
  for _,d in ipairs(app.dubs)do if d.snapshot==s and d.align_volume_state then
    local now=Audio.current(app.r,s)
    if M.same_geometry(now,s)and d.outputs and d.outputs[now.signature]then return now end
  end end
  return s
end
local function chunk(prepared)
  if type(prepared)~='table'then return prepared end
  local rows={prepared.header:gsub('\n>%s*$','')}
  for _,p in ipairs(prepared.points)do rows[#rows+1]=string.format('PT %.17g %.17g %d %.17g',p.time,p.value,p.shape or 0,p.tension or 0)end
  return table.concat(rows,'\n')..'\n>\n'
end
local function map_curve(curve,transport)
  if not curve then return nil end
  local out=U.copy(curve);out.points={}
  for i,p in ipairs(curve.points or {})do local v=U.copy(p);v.t=Warp.target(transport,p.t)-transport.pos;out.points[i]=v end
  if curve.recipes then out.recipes={};for i,r in ipairs(curve.recipes)do out.recipes[i]={a=Warp.target(transport,r.a)-transport.pos,b=Warp.target(transport,r.b)-transport.pos,cfg=U.copy(r.cfg)}end end
  out.frozen=map_curve(curve.frozen,transport);out.levels=nil
  return out
end
local function logical(cd,current)
  return {snapshot=cd.snapshot,original_state=cd.original_state,plan=cd.plan,layers=cd.layers,applied=cd.applied,
    applied_cleanup=cd.applied_cleanup,applied_cfg=cd.applied_cfg,cfg=cd.cfg,current=current,range=cd.range,processed_modes=cd.processed_modes}
end
local function restore_logical(cd,value)
  for _,k in ipairs({'snapshot','original_state','plan','layers','applied','applied_cleanup','applied_cfg','cfg','range','processed_modes'})do cd[k]=value[k]end
  cd.read_snapshot=value.current;cd.audio=nil;cd.pcm=nil;cd.compressor_follower=nil;cd.gate_follower=nil;cd.chain_inputs=nil
  cd.audio_file=nil;cd.audio_dirty=true;cd.detector_levels=nil;cd.tool_preview=nil;cd.preview=nil;cd.preview_valid=false
  cd.want_apply=false;cd.stale=nil;cd.save_pending=true;cd.view=nil;cd.exclusions={};cd.selected=false
  cd.applied_plan=cd.applied and cd.plan or nil
  cd.cache_status='Align timing changed; processing settings retained, audio read required'
  cd.align_timing_active=value.current.signature
  cd.verified_signature=value.current.signature;cd.verified_output=cd.outputs[value.current.signature]or false
end
-- Runs inside the renderer's bounded, rollback-protected native transaction.
function M.prepare(app,entry,target,restore_state)
  local d=entry.dub;local r=app.r;local cd=find(app,d,entry.before)
  local volume=d.align_volume_state or d.original_state or d.snapshot
  restore_state(r,volume)
  local prepared=Envelope.prepare(r,volume,M.transport(volume,target),nil)
  if not cd then return prepared end
  local baseline=cd.original_state or cd.snapshot
  restore_state(r,baseline)
  local transport=M.transport(baseline,target)
  local clean_baseline=Envelope.prepare(r,baseline,transport,nil)
  local mapped={};for mode,curve in pairs(cd.layers or {})do mapped[mode]=map_curve(curve,transport)end
  local range=cd.range or {0,baseline.len}
  entry.cleanup_bridge={dub=cd,before=logical(cd,entry.before),baseline_chunk=chunk(clean_baseline),layers=mapped,
    cleanup=map_curve(cd.applied_cleanup,transport),range={Warp.target(transport,range[1])-target.pos,Warp.target(transport,range[2])-target.pos}}
  return prepared
end
function M.publish(entry)
  local bridge=entry.cleanup_bridge;if not bridge then return end
  local cd,after=bridge.dub,entry.after;local baseline=U.copy(after)
  baseline.cleanup_capture=true;baseline.channels=cd.snapshot.channels
  baseline.volume_envelope=bridge.baseline_chunk
  if bridge.baseline_chunk then
    baseline.volume_points={}
    for t,v,shape,tension in bridge.baseline_chunk:gmatch('PT%s+(%S+)%s+(%S+)%s+(%S+)([^\r\n]*)')do
      baseline.volume_points[#baseline.volume_points+1]={t=tonumber(t),v=tonumber(v),shape=tonumber(shape),tension=tonumber(tension)or 0}
    end
  else baseline.volume_points=nil end
  -- The native baseline chunk is authoritative; point descriptions are optional
  -- acceleration data in Envelope.equivalent and can be rebuilt from its text.
  local plan=State.plan(baseline);local output={plan=plan,cleanup=bridge.cleanup,layers=bridge.layers,cfg=cd.applied_cfg or cd.cfg,
    volume_envelope=after.volume_envelope,volume_points=after.volume_points,envelope_points=#(after.volume_points or {}),sequence=(cd.output_sequence or 0)+1}
  cd.outputs=cd.outputs or {};cd.outputs[after.signature]=output;cd.output_sequence=output.sequence
  local value={snapshot=baseline,original_state=baseline,plan=plan,layers=bridge.layers,applied=cd.applied,applied_cleanup=bridge.cleanup,
    applied_cfg=cd.applied_cfg,cfg=cd.cfg,current=after,range=bridge.range,processed_modes=cd.processed_modes}
  cd.align_timing_history=cd.align_timing_history or {};cd.align_timing_history[bridge.before.current.signature]=bridge.before
  cd.align_timing_history[after.signature]=value
  restore_logical(cd,value)
end
local installed=false
function M.install()
  if installed then return end;installed=true
  local unchanged=Audio.unchanged
  Audio.unchanged=function(r,s,expected)
    local yes,why=unchanged(r,s,expected)
    local app=not expected and reference_apps[s]
    if not yes and app and Audio.project_open(r,s.project)then
      local ok,current=pcall(Audio.current,r,s)
      if ok and M.same_geometry(s,current)and verified_volume(app,s,current)then return true end
    end
    return yes,why
  end
  local check=State.check
  State.check=function(r,d,current)
    local history=d.align_timing_history;local value=history and history[current.signature]
    if value and d.align_timing_active~=current.signature then restore_logical(d,value);return true,nil,false end
    return check(r,d,current)
  end
end
return M
