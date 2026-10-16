-- @noindex
-- Measured F0 support for display and newly authored edits. Saved DSP keeps
-- its older support policy. A fast monotonic glide is not an isolated spike.
local M={}
local function ease(x)x=math.max(0,math.min(1,x));return x*x*(3-2*x)end
local function usable(f)return f and f.confidence>=.3 and (f.level_db or -20)>-60 end
function M.runs(data)
  local frames=data.frames or {};local hop=data.hop or .016
  if data._trace and data._trace.frames==frames and data._trace.count==#frames and data._trace.hop==hop and data._trace.len==data.len then return data._trace.runs,data._trace.ids end
  local runs,ids={},{};local active,previous
  for i,f in ipairs(frames)do
    local a,b=frames[i-1],frames[i+1]
    local spike=usable(a) and usable(b) and math.abs(f.pitch-a.pitch)>=3.5 and math.abs(f.pitch-b.pitch)>=3.5 and math.abs(a.pitch-b.pitch)<2
    if usable(f) and not spike then
      if not active or not previous or f.t-previous.t>hop*1.51 then
        active={start=f.t,first=i,last=i,id=#runs+1,seeds=0};runs[#runs+1]=active
      else active.last=i end
      if f.confidence>=.5 then active.seeds=active.seeds+1 end
      previous=f
    else active,previous=nil,nil end
  end
  for _,s in ipairs(runs)do
    local last,next=frames[s.last],frames[s.last+1]
    s.finish=math.min(last.t+hop,next and next.t or math.huge,data.len or math.huge)
    if s.seeds<2 then s.finish=s.start else for i=s.first,s.last do ids[i]=s.id end end
  end
  data._trace={frames=frames,count=#frames,hop=hop,len=data.len,runs=runs,ids=ids}
  return runs,ids
end
local function run_at(data,t)
  local runs=M.runs(data);local lo,hi=1,#runs
  while lo<=hi do local mid=(lo+hi)//2;local s=runs[mid]
    if t<s.start then hi=mid-1 elseif t>=s.finish then lo=mid+1 else return s end
  end
end
function M.support(data,t)
  if not data or data.len and (t<0 or t>data.len) then return nil end
  if data._source then return M.support(data._source,t+(data._offset or 0))end
  local s=run_at(data,t)
  if s then return s.id,ease((t-s.start)/.025)*ease((s.finish-t)/.025)end
end
function M.detail(data,t)
  if not data or data.len and (t<0 or t>data.len) then return nil end
  if data._source then return M.detail(data._source,t+(data._offset or 0))end
  local s=run_at(data,t);if not s then return nil end
  local frames=data.frames;local lo,hi=s.first,s.last
  while hi-lo>1 do local mid=(lo+hi)//2;if frames[mid].t<=t then lo=mid else hi=mid end end
  if t>=frames[s.last].t then return frames[s.last].pitch,s.id,frames[s.last].confidence,s.last,s.last,0 end
  local a,b=frames[lo],frames[hi];local u=(t-a.t)/math.max(1e-9,b.t-a.t)
  return a.pitch+(b.pitch-a.pitch)*u,s.id,a.confidence+(b.confidence-a.confidence)*u,lo,hi,u
end
function M.sample(data,t)
  local pitch,id=M.detail(data,t);return pitch,id
end
-- New expression/continuous-transition edits share this reliability policy.
-- Full strength at confidence >= .5; uncertain frames and run edges fade out.
function M.control(data,t)
  local raw,_,confidence,lo,hi,u=M.detail(data,t);if not raw then return nil end
  local _,support=M.support(data,t)
  return raw,ease((confidence-.3)/.2)*(support or 0),lo,hi,u
end
-- Full control at measured endpoints; fade only outside measured voicing.
-- This gates a correction envelope, never supplies missing F0 to the display.
function M.edge_support(data,t)
  if not data or data.len and (t<0 or t>data.len) then return 0 end
  if data._source then return M.edge_support(data._source,t+(data._offset or 0))end
  local remaining=1
  for _,s in ipairs(M.runs(data))do if s.finish>s.start and t>s.start-.012 and t<s.finish+.012 then
    remaining=remaining*(1-ease((t-s.start+.012)/.012)*ease((s.finish+.012-t)/.012))
  end end
  return 1-remaining
end
function M.edge_span(data,lo,hi,last)
  if data._source then
    local offset=data._offset or 0;local a,b,id=M.edge_span(data._source,lo+offset,hi+offset,last)
    if a then return math.max(0,a-offset),math.min(data.len,b-offset),id end;return
  end
  local found
  for _,s in ipairs(M.runs(data))do if s.finish>s.start and s.finish>lo and s.start<hi then
    found=s;if not last then break end
  end end
  if found then return found.start,found.finish,found.id end
end
return M
