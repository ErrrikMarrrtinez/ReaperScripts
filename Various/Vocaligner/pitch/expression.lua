-- @noindex
local import=...;local Trace=import('pitch/trace');local M={}
local function clamp(x,a,b)return math.max(a,math.min(b,x))end
local function ease(x)x=clamp(x,0,1);return x*x*(3-2*x)end
local function frame_trend(data,i)
  data._trend=data._trend or {};if data._trend[i] then return data._trend[i] end
  local frames=data.frames;local f=frames[i];local sum,weight=0,0
  -- A local pitch-domain average, not an audio filter. Reject uncertain frames
  -- and octave outliers; never average through an unvoiced run.
  for direction=-1,1,2 do
    local j=i+(direction==1 and 1 or 0)
    while frames[j] and math.abs(frames[j].t-f.t)<=.16 do
      local v=frames[j]
      if v.confidence<.35 or (j~=i and math.abs(v.pitch-frames[j-direction].pitch)>3.5) then break end
      if math.abs(v.pitch-f.pitch)<3.5 then
        local w=math.exp(-.5*((v.t-f.t)/.075)^2)*v.confidence*v.confidence
        sum=sum+v.pitch*w;weight=weight+w
      end
      j=j+direction
    end
  end
  local result=weight>0 and sum/weight or f.pitch;data._trend[i]=result;return result
end
local function frame_trust(data,i)
  data._trust=data._trust or {};if data._trust[i]~=nil then return data._trust[i] end
  local frames=data.frames;local f=frames[i]
  local weight=ease((f.confidence-.35)/.4)*ease(((f.level_db or -20)+60)/20)
  if frames[i-1] and math.abs(f.pitch-frames[i-1].pitch)>3.5 or frames[i+1] and math.abs(f.pitch-frames[i+1].pitch)>3.5 then weight=0 end
  data._trust[i]=weight;return weight
end
function M.confident(f)return f and f.confidence>=.5 and (f.level_db or -20)>-60 end
-- One support policy for manual Draw and new links. No pitch operation may
-- interpolate an acoustic target through an unvoiced interval.
local function legacy_support(data,t)
  if not data then return nil end
  if data._source then return legacy_support(data._source,t+(data._offset or 0)) end
  local frames=data.frames or {}
  if not data._manual_runs or data._manual_frames~=frames or data._manual_count~=#frames then
    local runs={};local active,previous
    for _,f in ipairs(frames)do
      if M.confident(f) then
        if not active or not previous or f.t-previous.t>.0241 or math.abs(f.pitch-previous.pitch)>=3.5 then
          active={start=f.t,finish=f.t,id=#runs+1};runs[#runs+1]=active
        else active.finish=f.t end
        previous=f
      else active,previous=nil,nil end
    end
    data._manual_runs=runs;data._manual_frames=frames;data._manual_count=#frames
  end
  local runs=data._manual_runs;local lo,hi=1,#runs
  while lo<=hi do local mid=(lo+hi)//2;local s=runs[mid]
    if t<s.start then hi=mid-1 elseif t>s.finish then lo=mid+1
    else return s.id,ease((t-s.start)/.005)*ease((s.finish-t)/.005) end
  end
end
local function voiced_runs(data)
  local frames=data.frames or {};local hop=data.hop or .016
  if data._voiced_runs and data._voiced_frames==frames and data._voiced_count==#frames and data._voiced_hop==hop and data._voiced_len==data.len then return data._voiced_runs end
  local runs={};local active,previous
  for i,f in ipairs(frames)do
    if M.confident(f) then
      if not active or not previous or f.t-previous.t>.0241 or math.abs(f.pitch-previous.pitch)>=3.5 then
        active={start=f.t,first=i,last=i,id=#runs+1};runs[#runs+1]=active
      else active.last=i end
      previous=f
    else active,previous=nil,nil end
  end
  for _,s in ipairs(runs)do
    local last,next=frames[s.last],frames[s.last+1]
    s.finish=math.min(last.t+hop,next and next.t or math.huge,data.len or math.huge)
    if s.first==s.last then s.finish=s.start end -- no target on an isolated pitch spike
  end
  data._voiced_runs=runs;data._voiced_frames=frames;data._voiced_count=#frames;data._voiced_hop=hop;data._voiced_len=data.len
  return runs
end
local function voiced_run(data,t)
  local runs=voiced_runs(data);local lo,hi=1,#runs
  while lo<=hi do local mid=(lo+hi)//2;local s=runs[mid]
    if t<s.start then hi=mid-1 elseif t>=s.finish then lo=mid+1 else return s end
  end
end
-- A confident frame owns its full hop, with a 25 ms release. Saved v2 links
-- and unversioned Draw strokes retain their original 5 ms policy explicitly.
function M.support(data,t,policy)
  if policy==1 then return legacy_support(data,t) end
  if not data then return nil end
  if data._source then return M.support(data._source,t+(data._offset or 0),policy) end
  local s=voiced_run(data,t)
  if s then return s.id,ease((t-s.start)/.025)*ease((s.finish-t)/.025) end
end
function M.voiced_sample(data,t)
  if not data then return nil end
  if data._source then return M.voiced_sample(data._source,t+(data._offset or 0)) end
  local s=voiced_run(data,t);if not s then return nil end
  local frames=data.frames;local lo,hi=s.first,s.last
  while hi-lo>1 do local mid=(lo+hi)//2;if frames[mid].t<=t then lo=mid else hi=mid end end
  -- Hold the last trusted F0 to the frame's end; never blend it with the
  -- following untrusted pitch, even during the support release.
  if t>=frames[s.last].t then lo,hi=s.last,s.last end
  local a,b=frames[lo],frames[hi];local u=clamp((t-a.t)/math.max(1e-9,b.t-a.t),0,1)
  local raw=a.pitch+(b.pitch-a.pitch)*u
  local trend=frame_trend(data,lo)+(frame_trend(data,hi)-frame_trend(data,lo))*u
  local qa,qb=frame_trust(data,lo),frame_trust(data,hi)
  return raw,trend,qa+(qb-qa)*ease(u),s.id
end
function M.trusted(data,t,direction)
  if not data then return nil end
  if data._source then
    local p,trend,at,slope=M.trusted(data._source,t+(data._offset or 0),direction)
    return p,trend,at and at-(data._offset or 0),slope
  end
  local frames=data.frames or {};local lo,hi=1,#frames
  while lo<=hi do local mid=(lo+hi)//2;if frames[mid].t<t then lo=mid+1 else hi=mid-1 end end
  local index=direction<0 and (frames[lo] and math.abs(frames[lo].t-t)<1e-8 and lo or lo-1) or lo
  while frames[index] and math.abs(frames[index].t-t)<=.032001 do local f=frames[index]
    if M.confident(f) then
      local a,b=frames[index-1],frames[index+1];local slope=0
      if M.confident(a) and M.confident(b) and math.abs(a.pitch-f.pitch)<3.5 and math.abs(b.pitch-f.pitch)<3.5 then
        slope=(frame_trend(data,index+1)-frame_trend(data,index-1))/(b.t-a.t)
      end
      return f.pitch,frame_trend(data,index),f.t,slope
    end
    index=index+direction
  end
end
function M.sample(data,t)
  if not data or not data.frames or #data.frames==0 then return nil end
  if data._source then return M.sample(data._source,t+(data._offset or 0)) end
  local frames=data.frames;local lo,hi=1,#frames
  while hi-lo>1 do local mid=(lo+hi)//2;if frames[mid].t<=t then lo=mid else hi=mid end end
  local a,b=frames[lo],frames[hi];local u=clamp((t-a.t)/math.max(1e-9,b.t-a.t),0,1)
  local function lerp(x,y)return x+(y-x)*u end
  local pitch=lerp(a.pitch,b.pitch);local trend=lerp(frame_trend(data,lo),frame_trend(data,hi))
  local qa,qb=frame_trust(data,lo),frame_trust(data,hi)
  local trust=qa+(qb-qa)*ease(u)
  return pitch,trend,trust
end
function M.extra(n,t,data,anchor)
  local mod,drift,flat=n.modulation or 1,n.drift or 1,n.flatten or 0
  local depth=n.vibrato_depth or 0
  if mod==1 and drift==1 and flat==0 and depth==0 then return 0 end
  local at=clamp(t,n.start,n.finish);local raw,trend,trust
  if n.expression_version==2 then
    -- Confidence decides whether a pitch is supported, not how far a fully
    -- requested correction moves a reliable vowel. Keep saved edits unchanged.
    local measured,weight,lo,hi,u=Trace.control(data,at)
    if not measured then return 0 end
    raw=measured;local source=data;while source._source do source=source._source end
    local a,b=frame_trend(source,lo),frame_trend(source,hi);trend=a+(b-a)*u
    trust=weight
  else raw,trend,trust=M.sample(data,at) end
  if not raw then return 0 end
  local residual=clamp(raw-trend,-3.5,3.5);local slow=clamp(trend-n.center,-12,12)
  if n.vibrato_replace and depth~=0 then mod=0 end
  local correction=(mod-1)*residual+(drift-1)*slow
  if n.expression_version==2 then
    correction=correction*(1-flat)+((n.flat_offset or 0)+n.center-raw-(anchor or 0))*flat
  else
    correction=correction*(1-flat)+((n.flat_offset or 0)-slow-residual-(anchor or 0))*flat
  end
  if depth~=0 then
    local start,finish=n.expression_start or n.start,n.expression_finish or n.finish
    local elapsed=at-start;local duration=math.max(.032,finish-start)
    local onset=duration*(n.vibrato_onset or .25)
    local gate=ease(elapsed/math.max(.02,onset))*ease((finish-at)/(n.vibrato_release or .02))
    local growth=n.vibrato_growth or 0
    gate=gate*(1+growth*(clamp(elapsed/duration,0,1)*2-1))
    correction=correction+depth*math.sin(2*math.pi*(n.vibrato_rate or 5.5)*(at-(n.phase_origin or start)))*gate
  end
  return correction*trust
end
function M.initialize(n)
  n.expression_start=n.expression_start or n.start;n.expression_finish=n.expression_finish or n.finish
  n.phase_origin=n.phase_origin or n.start
end
function M.edit(n)
  M.initialize(n);n.expression_version=2
end
function M.reset(n)
  n.shift=0;n.anchors={};n.target_anchors=nil;n.drawings=nil;n.link=nil;n.transition=.08
  for _,key in ipairs({'modulation','drift','flatten','flat_offset','vibrato_depth','vibrato_rate','vibrato_onset','vibrato_release','vibrato_growth','vibrato_replace',
    'expression_start','expression_finish','phase_origin','expression_version','transition_amount','transition_shape','transition_bias','transition_link','visual_offset'}) do n[key]=nil end
end
function M.edited(n)
  return (n.modulation or 1)~=1 or (n.drift or 1)~=1 or (n.flatten or 0)~=0 or (n.vibrato_depth or 0)~=0 or (n.transition_amount or 0)~=0 or #(n.drawings or {})>0 or #(n.target_anchors or {})>0 or n.link~=nil
end
return M
