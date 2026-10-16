-- @noindex
local import=...;local Expression=import('pitch/expression');local Notes=import('pitch/notes');local Trace=import('pitch/trace');local M={}
local function ease(x)x=math.max(0,math.min(1,x));return x*x*(3-2*x)end
-- Revisiting an interval paints over that interval, preserving the rest.
function M.paint(points,last,t,value)
  local lo,hi=t,t;if last then lo,hi=math.min(t,last.t),math.max(t,last.t) end
  for i=#points,1,-1 do if points[i].t>=lo-1e-8 and points[i].t<=hi+1e-8 then table.remove(points,i) end end
  if last and math.abs(t-last.t)>1e-8 then points[#points+1]={t=last.t,value=last.value} end
  points[#points+1]={t=t,value=value};table.sort(points,function(a,b)return a.t<b.t end)
  return {t=t,value=value}
end
function M.stroke(points,n)
  if #points<2 or points[#points].t-points[1].t<.002 then return nil end
  local keep={[1]=true,[#points]=true};local stack={{1,#points}}
  while #stack>0 do local pair=table.remove(stack);local a,b=points[pair[1]],points[pair[2]];local worst,id=.01
    for i=pair[1]+1,pair[2]-1 do local p=points[i];local expected=a.value+(b.value-a.value)*(p.t-a.t)/(b.t-a.t)
      local err=math.abs(p.value-expected);if err>worst then worst,id=err,i end
    end
    if id then keep[id]=true;stack[#stack+1]={pair[1],id};stack[#stack+1]={id,pair[2]} end
  end
  local out={};for i,p in ipairs(points) do if keep[i] then out[#out+1]={t=p.t,value=p.value} end end
  return {start=math.max(n.start,out[1].t-.025),finish=math.min(n.finish,out[#out].t+.025),points=out}
end
local function tangent(points,i)
  local p=points[i];local a,b=points[i-1],points[i+1]
  if not a then return (b.value-p.value)/(b.t-p.t) end
  if not b then return (p.value-a.value)/(p.t-a.t) end
  local h0,h1=p.t-a.t,b.t-p.t;local d0,d1=(p.value-a.value)/h0,(b.value-p.value)/h1
  if d0*d1<=0 then return 0 end
  local w0,w1=2*h1+h0,h1+2*h0;return (w0+w1)/(w0/d0+w1/d1)
end
function M.sample(s,t)
  local p=s.points;if t<=p[1].t then return p[1].value end;if t>=p[#p].t then return p[#p].value end
  local lo,hi=1,#p;while hi-lo>1 do local mid=(lo+hi)//2;if p[mid].t<=t then lo=mid else hi=mid end end
  local a,b=p[lo],p[hi];local h=b.t-a.t;local u=(t-a.t)/h;local u2,u3=u*u,u*u*u
  return (2*u3-3*u2+1)*a.value+(u3-2*u2+u)*h*tangent(p,lo)+(-2*u3+3*u2)*b.value+(u3-u2)*h*tangent(p,hi)
end
function M.apply(n,t,data,base)
  if not n or not n.drawings or #n.drawings==0 then return base end
  local raw,trust
  for _,s in ipairs(n.drawings) do if not s.target and t>s.start and t<s.finish then
    if not raw then local pitch,_,q=Expression.sample(data,t);raw,trust=pitch,q;if not raw then return base end end
    local first,last=s.points[1].t,s.points[#s.points].t
    local left=math.max(.001,first-s.start);local right=math.max(.001,s.finish-last)
    local weight=ease((t-s.start)/left)*ease((s.finish-t)/right)*trust
    local flat=n.flatten or 0
    local target=M.sample(s,t)*(1-flat)+(n.center+(n.flat_offset or 0))*flat+(n.shift or 0)-raw
    base=base+(target-base)*weight
  end end
  return base
end
-- New strokes have one trajectory and one pair of fades, shared across note
-- boundaries. Confidence selects voiced support; it does not scale the pitch
-- requested inside that support. Legacy strokes above remain unchanged.
function M.support(data,t)
  return Trace.support(data,t)
end
function M.owner(notes,t)
  local n,i=Notes.at(notes,t);if n then return n,i end
  local a,b=notes[i-1],notes[i];local da=a and t-a.finish or math.huge;local db=b and b.start-t or math.huge
  if da<=db and da<=.150001 then return a,i-1 end
  if db<=.150001 then return b,i end
end
function M.owns(n,t)
  local latest
  for _,s in ipairs(n and n.drawings or {})do if s.target and t>s.start and t<s.finish and (not latest or (s.id or 0)>latest.id) then latest=s end end
  return latest
end
function M.apply_target(n,t,data,base,post,captured)
  if not n or not n.drawings then return base end
  for _,s in ipairs(n.drawings)do if s.target and t>s.start and t<s.finish then
    local policy=s.support_version or 1
    local raw
    if policy==3 then raw=Trace.sample(data,t)elseif policy==2 then raw=Expression.voiced_sample(data,t)else raw=Expression.sample(data,t)end
    local _,support
    if policy==3 then _,support=Trace.support(data,t)else _,support=Expression.support(data,t,policy)end
    if raw and support and support>0 then
    local first,last=s.points[1].t,s.points[#s.points].t
    local weight=ease((t-s.start)/math.max(.001,first-s.start))*ease((s.finish-t)/math.max(.001,s.finish-last))*support
    -- Subtract the Curve layer captured with the stroke. Later Curve gestures
    -- may move it; changing Flatten/Modulation/Transition leaves it absolute.
    local offset=s.curve_notes and captured and captured(s,t) or post and post(s.curve or {},t) or 0
    if not s.curve_notes and s.curve_linear and #(s.curve or {})>0 then
      local p=s.curve;local lo,hi=1,#p
      while hi-lo>1 do local mid=(lo+hi)//2;if p[mid].t<=t then lo=mid else hi=mid end end
      local a,b=p[lo],p[hi];local u=math.max(0,math.min(1,(t-a.t)/math.max(1e-9,b.t-a.t)));offset=a.value+(b.value-a.value)*u
    end
    local target=M.sample(s,t)+(n.shift or 0)-raw-offset
    base=base+(target-base)*weight
    end
  end end
  return base
end
return M
