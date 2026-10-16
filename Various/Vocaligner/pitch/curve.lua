-- @noindex
local import=...;local Notes=import('pitch/notes');local Expression=import('pitch/expression');local Draw=import('pitch/draw');local Link=import('pitch/link');local Trace=import('pitch/trace');local M={}
local function clamp(x,a,b) return math.max(a,math.min(b,x)) end
function M.ease(x) x=clamp(x,0,1);return x*x*x*(x*(x*6-15)+10) end
function M.anchor(note,t)
  local points=note.anchors or {};if #points==0 then return 0 end
  if t<=points[1].t then return points[1].value end
  for i=2,#points do if t<=points[i].t then
    local a,b=points[i-1],points[i];local u=M.ease((t-a.t)/math.max(1e-8,b.t-a.t));return a.value+(b.value-a.value)*u
  end end
  return points[#points].value
end
local function value(n,t,field,data)
  if not n then return 0 end
  local anchor=field=='shift' and M.anchor(n,t) or 0
  local result=(n[field] or 0)+anchor+(field=='shift' and data and Expression.extra(n,t,data,anchor) or 0)
  return field=='shift' and data and Draw.apply(n,t,data,result) or result
end
local function evaluate(notes,t,field)
  field=field or 'shift'
  -- The correction is blended, not the measured vocal pitch. Its sum with the
  -- untouched F0 retains vibrato/melisma. No connection across long unvoiced gaps.
  local n,i=Notes.at(notes,t)
  if n then
    local first,last;n,first,last=Notes.voice_group(notes,i)
    local prev,next=Notes.voice_group(notes,first-1),Notes.voice_group(notes,last+1);local duration=n.finish-n.start
    local left=math.min(n.transition or .08,duration*.45)
    if prev and n.start-prev.finish<=.048 then
      local width=math.min(left,(prev.finish-prev.start)*.45)
      local boundary=(n.start+prev.finish)*.5
      if width>0 and t<boundary+width then
        return value(prev,t,field)+(value(n,t,field)-value(prev,t,field))*M.ease((t-boundary+width)/(2*width))
      end
    elseif left>0 and t<n.start+left then return value(n,t,field)*M.ease((t-n.start)/left) end
    local right=math.min(next and next.transition or n.transition or .08,duration*.45)
    if next and next.start-n.finish<=.048 then
      local width=math.min(right,(next.finish-next.start)*.45)
      local boundary=(n.finish+next.start)*.5
      if width>0 and t>boundary-width then
        return value(n,t,field)+(value(next,t,field)-value(n,t,field))*M.ease((t-boundary+width)/(2*width))
      end
    elseif right>0 and t>n.finish-right then return value(n,t,field)*M.ease((n.finish-t)/right) end
    return value(n,t,field)
  end
  for j=math.max(1,i-1),math.min(#notes-1,i-1) do
    local a,b=Notes.voice_group(notes,j),Notes.voice_group(notes,j+1)
    if t>=a.finish and t<b.start and b.start-a.finish<=.048 then
      local w=math.min(b.transition or .08,(a.finish-a.start)*.45,(b.finish-b.start)*.45)
      if w<=0 then return 0 end
      local boundary=(a.finish+b.start)*.5
      return value(a,t,field)+(value(b,t,field)-value(a,t,field))*M.ease((t-boundary+w)/(2*w))
    end
  end
  return 0
end
-- Version 2: retain the full requested shift throughout an isolated note.
-- Its ramps occupy the surrounding gap. Connected notes share one transition,
-- limited to 20% of each voiced body (v1 used up to 45% at BOTH ends).
local function can_link(a,b) return a and b and b.start>=a.finish-1e-8 and b.start-a.finish<=.3000001 end
local function connected(a,b,field) return can_link(a,b) and (b.start-a.finish<=.0480001 or b.transition_link==true or field~='formant' and Link.legacy(b)) end
M.can_link=can_link
local function bridge(a,b,field)
  if field~='formant' and Link.legacy(b) then return Link.window(a,b) end
  local gap=math.max(0,b.start-a.finish);local mid=(a.finish+b.start)*.5
  local fraction=(b.transition_amount or 0)>0 and .45 or .2
  local width=math.min((b.transition or .08)*.5,gap*.5+(a.finish-a.start)*fraction,gap*.5+(b.finish-b.start)*fraction)
  local bias=clamp(b.transition_bias or 0,-.75,.75)*width
  if (b.transition_amount or 0)>0 then
    return math.max(mid-width+bias,a.start+(a.finish-a.start)*.5),math.min(mid+width+bias,b.start+(b.finish-b.start)*.5)
  end
  return mid-width,mid+width
end
local function fade_in(prev,n)
  return math.max(0,n.start-math.min((n.transition or .08)*.5,prev and math.max(0,n.start-prev.finish)*.5 or math.huge)),n.start
end
local function fade_out(n,next)
  return n.finish,n.finish+math.min((n.transition or .08)*.5,next and math.max(0,next.start-n.finish)*.5 or math.huge)
end
local function blend(a,b,t,lo,hi,field,data,context)
  local u=hi>lo and M.ease((t-lo)/(hi-lo)) or (t>=hi and 1 or 0)
  local base=value(a,t,field,data)*(1-u)+value(b,t,field,data)*u
  if context and data and field=='shift' and a and b and Link.legacy(b) then
    local c=context[b]
    if not c then c=Link.prepare(a,b,lo,hi,function(at)return Expression.sample(data,at)end,
      function(n,at)return value(n,at,field,data)end);context[b]=c or false end
    return Link.at(c,b.link,t,Expression.sample(data,t),base)
  end
  if data and field=='shift' and a and b and t>lo and t<hi and (b.transition_amount or 0)>0 then
    local raw,_,trust=Expression.sample(data,t)
    local pa=Expression.sample(data,lo);local pb=Expression.sample(data,hi)
    if raw and pa and pb then
      local v=clamp((t-lo)/math.max(1e-9,hi-lo),0,1)
      local shape=b.transition_shape or 1
      -- Positive bias moves the midpoint; shape changes steepness without
      -- changing either endpoint. Quintic endpoints keep the edit continuous.
      local x=v^shape;local y=(1-v)^shape;local shaped=M.ease(x/(x+y))
      local left=pa+value(a,lo,field,data);local right=pb+value(b,hi,field,data)
      local target=left+(right-left)*shaped-raw
      base=base+(target-base)*(b.transition_amount or 0)*trust
    end
  end
  return base
end
function M.window(a,b,data)
  if Link.active(b) then return Link.window(a,b,data) end
  return bridge(a,b)
end
M.connected=connected
M.value=value
local function current(notes,t,field,data,context)
  local n,i=Notes.at(notes,t)
  if n then
    local first,last;n,first,last=Notes.voice_group(notes,i)
    local prev,next=Notes.voice_group(notes,first-1),Notes.voice_group(notes,last+1)
    if connected(prev,n,field) then local a,b=bridge(prev,n,field);if t<b then return blend(prev,n,t,a,b,field,data,context) end end
    if connected(n,next,field) then local a,b=bridge(n,next,field);if t>a then return blend(n,next,t,a,b,field,data,context) end end
    return value(n,t,field,data)
  end
  local prev,next=Notes.voice_group(notes,i-1),Notes.voice_group(notes,i)
  if connected(prev,next,field) then local a,b=bridge(prev,next,field);return blend(prev,next,t,a,b,field,data,context) end
  if prev then local a,b=fade_out(prev,next);if t<b then return blend(prev,nil,t,a,b,field,data) end end
  if next then local a,b=fade_in(prev,next);if t>a then return blend(nil,next,t,a,b,field,data) end end
  return 0
end
local function post(points,t)return M.anchor({anchors=points},t)end
local function captured_offset(notes,edit,t,context)
  context.captured=context.captured or {};local baseline=context.captured[edit]
  if not baseline then
    baseline={_resolved=true}
    for _,v in ipairs(Notes.resolve(notes))do
      local copy={};for key,value in pairs(v)do copy[key]=value end;copy.target_anchors={}
      for _,q in ipairs(edit.curve_notes or {})do if q.id==v.id or v.start>=q.start-1e-8 and v.finish<=q.finish+1e-8 then copy.target_anchors=q.points;break end end
      baseline[#baseline+1]=copy
    end
    context.captured[edit]=baseline
  end
  return M.manual_offset(baseline,t)
end
local function new_links(notes,t,data,base,context)
  local n,i=Notes.at(notes,t);local a,b
  local paired,prior,prior_link=0
  if n then local first,last;n,first,last=Notes.voice_group(notes,i);a,b=Notes.voice_group(notes,first-1),Notes.voice_group(notes,last+1)
  else a,b=Notes.voice_group(notes,i-1),Notes.voice_group(notes,i) end
  local function wide(right)return Link.active(right) and right.link.version>=6 and right.link.amount>0 end
  local expanded=wide(n) or wide(b)
  local function apply(left,right)
    if not can_link(left,right) or not Link.active(right) or right.link.version<2 or right.link.mix==0 or right.link.version>=4 and right.link.amount==0 then return end
    context.links=context.links or {};local cached=context.links[right]
    if not cached then
      local lo,hi=Link.window(left,right,data)
      local prepare=right.link.version>=5 and Link.prepare_pair or right.link.version==4 and Link.prepare_tilt or nil
      local curve;local correction_context={}
      if prepare then curve=prepare(left,right,data,function(_,at)return current(notes,at,'shift',data,correction_context)+
        (right.link.version>=5 and captured_offset(notes,right.link,at,context) or M.manual_offset(notes,at))end)
      else curve=Link.prepare_v2(left,right,lo,hi,data,function(v,at)return value(v,at,'shift',data)end)end
      cached={lo=curve and curve.lo or lo,hi=curve and curve.hi or hi,curve=curve}
      context.links[right]=cached
    end
    if t>cached.lo and t<cached.hi then
      if expanded and right.link.version>=5 then
        local delta=Link.at_tilt(cached.curve,right.link,t,data,0)
        if prior then
          -- Crossfade the two requested offsets inside their shared span.
          -- Amount weights let either neighbour fade to zero independently.
          local lo,hi=math.max(prior.lo,cached.lo),math.min(prior.hi,cached.hi)
          local u=M.ease((t-lo)/(hi-lo));local wa,wb=(1-u)*prior_link.amount,u*right.link.amount
          paired=(paired*wa+delta*wb)/(wa+wb)
        else paired,prior,prior_link=delta,cached,right.link end
      else base=(right.link.version>=4 and Link.at_tilt or Link.at_v2)(cached.curve,right.link,t,data,base)end
    end
  end
  if n then apply(a,n);apply(n,b)else apply(a,b)end
  return base+paired
end
function M.manual_offset(notes,t)
  local n,i=Notes.at(notes,t);local a,b
  if n then
    local first,last;n,first,last=Notes.voice_group(notes,i);a,b=Notes.voice_group(notes,first-1),Notes.voice_group(notes,last+1)
    if connected(a,n) then local lo,hi=bridge(a,n);if t<hi then local u=M.ease((t-lo)/math.max(1e-9,hi-lo));return post(a.target_anchors or {},t)*(1-u)+post(n.target_anchors or {},t)*u end end
    if connected(n,b) then local lo,hi=bridge(n,b);if t>lo then local u=M.ease((t-lo)/math.max(1e-9,hi-lo));return post(n.target_anchors or {},t)*(1-u)+post(b.target_anchors or {},t)*u end end
    return post(n.target_anchors or {},t)
  end
  a,b=Notes.voice_group(notes,i-1),Notes.voice_group(notes,i)
  if connected(a,b) then local lo,hi=bridge(a,b);local u=M.ease((t-lo)/math.max(1e-9,hi-lo));return post(a.target_anchors or {},t)*(1-u)+post(b.target_anchors or {},t)*u end
  if a then local lo,hi=fade_out(a,b);if t<hi then return post(a.target_anchors or {},t)*(1-M.ease((t-lo)/math.max(1e-9,hi-lo))) end end
  if b then local lo,hi=fade_in(a,b);if t>lo then return post(b.target_anchors or {},t)*M.ease((t-lo)/math.max(1e-9,hi-lo)) end end
  return 0
end
function M.capture_offset(notes,lo,hi)
  local found=false;for _,n in ipairs(notes)do if #(n.target_anchors or {})>0 then found=true;break end end
  if not found then return {} end
  local times={lo,hi}
  local function edge(t)if t>lo and t<hi then times[#times+1]=t end end
  for i,n in ipairs(notes)do edge(n.start);edge(n.finish);for _,p in ipairs(n.target_anchors or {})do edge(p.t) end
    if connected(notes[i-1],n) then local a,b=bridge(notes[i-1],n);edge(a);edge(b) end
  end
  table.sort(times);local out={{t=lo,value=M.manual_offset(notes,lo)}}
  local function refine(a,b,depth)
    local split=false
    for i=1,3 do local u=i/4;local t=a.t+(b.t-a.t)*u
      if math.abs(M.manual_offset(notes,t)-(a.value+(b.value-a.value)*u))>.0001 then split=true end
    end
    if split and depth<12 and b.t-a.t>.00001 then local t=(a.t+b.t)*.5;local m={t=t,value=M.manual_offset(notes,t)};refine(a,m,depth+1);refine(m,b,depth+1)
    else out[#out+1]=b end
  end
  for i=2,#times do local a=out[#out];local b={t=times[i],value=M.manual_offset(notes,times[i])};if b.t>a.t+1e-9 then refine(a,b,0) end end
  return out
end
function M.capture_anchors(notes)
  local out={};for _,n in ipairs(notes)do if #(n.target_anchors or {})>0 then
    out[#out+1]={id=n.id,start=n.start,finish=n.finish,points=Notes.copy(n.target_anchors)}
  end end;return out
end
local function manual(notes,t,data,base,context)
  local n,i=Notes.at(notes,t);local a,b
  if n then local first,last;n,first,last=Notes.voice_group(notes,i);a,b=Notes.voice_group(notes,first-1),Notes.voice_group(notes,last+1)
  else a,b=Notes.voice_group(notes,i-1),Notes.voice_group(notes,i) end
  local left,right,u
  if n and connected(a,n) then local lo,hi=bridge(a,n);if t<hi then left,right,u=a,n,M.ease((t-lo)/math.max(1e-9,hi-lo)) end end
  if n and not left and connected(n,b) then local lo,hi=bridge(n,b);if t>lo then left,right,u=n,b,M.ease((t-lo)/math.max(1e-9,hi-lo)) end end
  if not n and connected(a,b) then local lo,hi=bridge(a,b);left,right,u=a,b,M.ease((t-lo)/math.max(1e-9,hi-lo)) end
  -- A stroke owns its interval, even at a boundary. Shared stroke copies have
  -- identical absolute trajectories; only subsequent per-note moves are mixed.
  local owner=n
  if not owner then owner=left or a or b end
  local latest=Draw.owns(owner,t)
  for _,candidate in pairs({a,b})do local s=Draw.owns(candidate,t)
    if s and (not latest or s.id>latest.id)then owner,latest=candidate,s end
  end
  if owner then
    local function captured(stroke,at)
      return captured_offset(notes,stroke,at,context)
    end
    local function drawn(v)return Draw.apply_target(v,t,data,base,post,captured)end
    local shared=false
    if left and right then
      for _,s in ipairs(left.drawings or {})do if s.target and s.id and t>s.start and t<s.finish then
        for _,q in ipairs(right.drawings or {})do if q.id==s.id and q.target then shared=true;break end end
      end end
    end
    if shared then base=drawn(left)*(1-u)+drawn(right)*u else base=drawn(owner) end
  end
  return base+M.manual_offset(notes,t)
end
function M.at(notes,t,field,version,data,context,unclamped)
  field=field or 'shift'
  if version==4 then context=context or {};if context.manual==nil then
    context.manual=false;for _,n in ipairs(notes)do
      if #(n.target_anchors or {})>0 then context.manual=true;break end
      for _,s in ipairs(n.drawings or {})do if s.target then context.manual=true;break end end
      if context.manual then break end
    end
  end end
  local result=(version==1 and evaluate or current)(notes,t,field,(version or 1)>=3 and data or nil,version==4 and (context or {}) or nil)
  if version==4 and field=='shift' and data then result=new_links(notes,t,data,result,context) end
  if version==4 and field=='shift' and data and context.manual then result=manual(notes,t,data,result,context) end
  return unclamped and result or clamp(result,-24,24)
end
function M.evaluator(notes,field,version,data)
  local resolved=Notes.resolve(notes);local context={}
  return function(t)return M.at(resolved,t,field,version,data,context)end
end
-- Linear envelope simplification with a strict <=0.25 cent error at sampled
-- points; mandatory note edges prevent ramps crossing untouched gaps.
function M.points(notes,len,field,job,version,data,range)
  notes=Notes.resolve(notes)
  local from,to=range and range[1] or 0,range and range[2] or len
  if field=='formant' then
    local silent=true;for _,n in ipairs(notes)do if (n.formant or 0)~=0 then silent=false;break end end
    if silent then return {{t=from,value=0},{t=to,value=0}} end
  end
  local samples={};local context={}
  local function sample(t)
    local v=samples[t];if v==nil then v=M.at(notes,t,field,version,data,context);samples[t]=v end;return v
  end
  local times={from,to};local edges={[from]=true,[to]=true}
  local function edge(t) if t>=from and t<=to then times[#times+1]=t;edges[t]=true end end
  local function ramp(a,b,delta)
    -- Short notes can have sub-5ms transitions. Add bounded local samples so
    -- the host's linear envelope follows the smooth preview between frames.
    local steps=(version or 1)>=3 and 8 or math.max(8,math.ceil(40*math.sqrt(math.abs(delta))))
    for i=0,steps do local t=a+(b-a)*i/steps;if t>=from and t<=to then times[#times+1]=t end end
  end
  for index,n in ipairs(notes) do
    edge(n.start);edge(n.finish)
    edge(math.max(0,n.start-.005));edge(math.min(len,n.finish+.005))
    for _,p in ipairs(n.anchors or {}) do edge(p.t) end
    for _,p in ipairs(n.target_anchors or {}) do edge(p.t) end
    if (field or 'shift')=='shift' then for _,s in ipairs(n.drawings or {}) do edge(s.start);edge(s.finish);for _,p in ipairs(s.points) do edge(p.t) end end end
    if version==4 and field=='shift' and data and index>1 and Link.active(n) and n.link.version>=2 then
      local lo,hi=Link.window(notes[index-1],n,data);edge(lo);edge(hi);ramp(lo,hi,0)
    end
    if version~=1 then
      local prev,next=notes[index-1],notes[index+1]
      local a,b
      if connected(prev,n,field) then a,b=bridge(prev,n,field);ramp(a,b,value(n,n.start,field or 'shift')-value(prev,prev.finish,field or 'shift'))
      else a,b=fade_in(prev,n);ramp(a,b,value(n,n.start,field or 'shift')) end
      if not connected(n,next,field) then a,b=fade_out(n,next);ramp(a,b,value(n,n.finish,field or 'shift')) end
    end
    if job and index%16==0 then job:checkpoint(nil,'Preparing pitch transitions') end
  end
  if (version or 1)>=3 and field=='shift' and data then
    local first=range and math.max(1,math.floor(from/data.hop)) or 1
    local last=range and math.min(#data.frames,math.ceil(to/data.hop)+2) or #data.frames
    for i=first,last do local t=data.frames[i].t;if t>=from and t<=to then times[#times+1]=t end end
  end
  table.sort(times);local points,keep,stack={},{},{};local edge,grid,last=1,math.ceil(from/.005-1e-8)*.005,1
  -- Merge the fixed grid and mandatory edges without sorting 120,000 samples.
  while edge<=#times or grid<=to do
    local et=times[edge] or math.huge;local t=math.min(et,grid);local from_times=et<=grid;local mandatory=from_times and edges[t]
    if from_times then edge=edge+1 else grid=grid+.005 end
    if t>=from and t<=to then
      if not points[#points] or t-points[#points].t>1e-8 then points[#points+1]={t=t,value=sample(t)}
      elseif mandatory then points[#points]={t=t,value=sample(t)} end
      if mandatory then keep[#points]=true;if #points>last then stack[#stack+1]={last,#points};last=#points end end
    end
    if job and (#points%256==0) then job:checkpoint(nil,'Preparing pitch envelope') end
  end
  if (version or 1)>=3 and field=='shift' and data then
    -- F0/trust changes can be faster than the 5 ms seed grid. Refine against
    -- the same continuous target function before simplifying for the host.
    -- Quarter probes catch symmetric bends that a midpoint alone would miss.
    local refined={points[1]};local refined_keep={[1]=true};local operations=0
    local function refine(a,b,depth)
      local dt=b.t-a.t;local split=false;local middle
      for j=1,3 do
        local t=a.t+dt*j/4;local p={t=t,value=sample(t)}
        if j==2 then middle=p end
        if math.abs(p.value-(a.value+(b.value-a.value)*j/4))>.001 then split=true end
      end
      operations=operations+1;if job and operations%64==0 then job:checkpoint(nil,'Detailing pitch curve') end
      if split and depth<9 and dt>.00001 then refine(a,middle,depth+1);refine(middle,b,depth+1)
      else refined[#refined+1]=b end
    end
    for i=2,#points do refine(points[i-1],points[i],0);if keep[i] then refined_keep[#refined]=true end end
    points,keep,stack=refined,refined_keep,{};last=1
    for i=2,#points do if keep[i] then stack[#stack+1]={last,i};last=i end end
  end
  keep[1]=true;keep[#points]=true
  if last<#points then stack[#stack+1]={last,#points} end
  local operations=0
  while #stack>0 do
    local pair=table.remove(stack);local a,b=pair[1],pair[2];local p,q=points[a],points[b]
    local error,id=.0025,nil
    for i=a+1,b-1 do local v=p.value+(q.value-p.value)*(points[i].t-p.t)/(q.t-p.t);local e=math.abs(points[i].value-v)
      if e>error then error,id=e,i end
      operations=operations+1;if job and operations%256==0 then job:checkpoint() end
    end
    if id then keep[id]=true;stack[#stack+1]={a,id};stack[#stack+1]={id,b} end
  end
  local result={};for i,p in ipairs(points) do if keep[i] then result[#result+1]=p end;if job and i%512==0 then job:checkpoint() end end
  if range then
    local constant=true;for i=2,#result do if result[i].value~=result[1].value then constant=false;break end end
    if constant then return {result[1],result[#result]} end
  end
  return result
end
function M.add_anchor(note,t,value)
  local limit=note.limit or 12;value=clamp(value,-limit,limit)
  local p=note.anchors or {};note.anchors=p
  if #p==0 then p[1]={t=note.start,value=0};p[2]={t=note.finish,value=0} end
  for _,v in ipairs(p) do if math.abs(v.t-t)<.008 then v.value=value;return end end
  p[#p+1]={t=clamp(t,note.start,note.finish),value=value};table.sort(p,function(a,b)return a.t<b.t end)
end
function M.set_target(notes,n,t,target,data)
  -- Solve the final evaluator, not an approximate Flatten/trust gain. The new
  -- anchor layer also works where Flatten or a Draw has zero legacy gain.
  n.target_anchors=n.target_anchors or {}
  local proxy={start=n.start,finish=n.finish,anchors=n.target_anchors,limit=24}
  M.add_anchor(proxy,t,0);n.target_anchors=proxy.anchors
  local zero=M.at(notes,t,'shift',4,data,nil,true)
  M.add_anchor(proxy,t,1);local one=M.at(notes,t,'shift',4,data,nil,true)
  local raw=Trace.sample(data,t) or Expression.sample(data,t);local gain=one-zero
  if raw and math.abs(gain)>.001 then M.add_anchor(proxy,t,(target-raw-zero)/gain)
  else M.add_anchor(proxy,t,0) end
end
return M
