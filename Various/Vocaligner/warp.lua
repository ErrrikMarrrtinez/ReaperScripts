-- @noindex
local import=...;local DSP=import('dsp');local Audio=import('audio');local Timing=import('timing');local M={}
local function at(data,t) return data.frames[DSP.clamp(math.floor(t/data.hop+.5)+1,1,#data.frames)] end
local function simplify(points,epsilon,mandatory,job)
  local keep={[1]=true,[#points]=true};local boundaries={1}
  for i=2,#points-1 do if mandatory[i] then boundaries[#boundaries+1]=i;keep[i]=true end end
  boundaries[#boundaries+1]=#points;local stack={}
  for i=2,#boundaries do stack[#stack+1]={boundaries[i-1],boundaries[i]} end
  while #stack>0 do
    local ab=table.remove(stack);local a,b=points[ab[1]],points[ab[2]];local best,index=epsilon,nil
    for i=ab[1]+1,ab[2]-1 do
      local p=points[i];local y=a.target+(b.target-a.target)*(p.t-a.t)/(b.t-a.t)
      local e=math.abs(p.target-y)
      if e>best then best,index=e,i end
    end
    if index then keep[index]=true;stack[#stack+1]={ab[1],index};stack[#stack+1]={index,ab[2]} end
    if job then job:checkpoint() end
  end
  local out={};for i,p in ipairs(points) do if keep[i] then out[#out+1]=p end end
  return out
end
function M.build(ref,dub,path,stats,cfg,job)
  if (cfg.hybrid or 0)~=0 then return import('align/hybrid/plan').build(ref,dub,path,stats,cfg,job)end
  local s=dub.snapshot;local points,delta={},{}
  for _,p in ipairs(path) do
    local f=at(dub,p.dub)
    if p.active and p.cost<.8 then
      local shift=p.ref-(s.pos+p.dub)
      local original_t=s.pos+p.dub-ref.pos
      local gain
      if original_t>=0 and original_t<ref.len and math.abs(shift)<.08 then
        local original=DSP.distance(f,at(ref,original_t),cfg.profile)
        gain=original-p.cost
        if (cfg.smooth_ms or 0)==0 and original<p.cost+.035 then shift=0 end
      end
      points[#points+1]={t=p.dub,shift=shift,gain=gain,cost=p.cost,onset=f.onset}
    end
  end
  if #points<4 then return nil,'Too few trustworthy correspondences.' end
  Timing.smooth(points,(cfg.smooth_ms or 0)/1000,job)
  for i,p in ipairs(points) do delta[i]=p.shift end
  local tol=cfg.tolerance_ms/1000
  for i,p in ipairs(points) do
    local shift=DSP.median5(delta,i)
    shift=(shift>=0 and 1 or -1)*math.max(0,math.abs(shift)-tol)
    p.target=s.pos+p.t+DSP.clamp(shift,-cfg.search_s,cfg.search_s)
  end
  -- Unmatched heads/tails continue at the original rate instead of being forced onto ref edges.
  local a,b=points[1],points[#points]
  if a.t>1e-9 then table.insert(points,1,{t=0,target=a.target-a.t,cost=a.cost,edge=true}) else a.t=0;a.edge=true end
  if b.t<s.len-1e-9 then points[#points+1]={t=s.len,target=b.target+s.len-b.t,cost=b.cost,edge=true} else b.edge=true end
  local limited=0;local ratio=cfg.max_ratio
  -- Both passes enforce each segment, including the very first and last segment.
  for pass=1,3 do
    for i=2,#points do
      local a,b=points[i-1],points[i];local dx=b.t-a.t
      local lo,hi=dx/ratio,dx*ratio
      local y=DSP.clamp(b.target,a.target+lo,a.target+hi)
      if math.abs(y-b.target)>.00001 and pass==1 then limited=limited+1 end;b.target=y
    end
    for i=#points-1,1,-1 do
      local a,b=points[i],points[i+1];local dx=b.t-a.t
      a.target=DSP.clamp(a.target,b.target-dx*ratio,b.target-dx/ratio)
    end
    if job then job:checkpoint() end
  end
  -- A grouped role keeps every item edge as a knot of its own, so the virtual
  -- map slices into exact per-item maps and gaps between items stay their own
  -- segments (bounded by the same stretch limit).
  local function insert_knot(list,t,flag)
    for i=2,#list do local a,b=list[i-1],list[i]
      if math.abs(t-a.t)<1e-7 then a[flag]=true;return end
      if math.abs(t-b.t)<1e-7 then b[flag]=true;return end
      if t>a.t and t<b.t then
        table.insert(list,i,{t=t,target=a.target+(b.target-a.target)*(t-a.t)/(b.t-a.t),cost=math.max(a.cost,b.cost),[flag]=true});return
      end
    end
  end
  if s.composite then for _,part in ipairs(s.parts) do
    insert_knot(points,part.pos-s.pos,'boundary');insert_knot(points,part.pos-s.pos+part.len,'boundary')
  end end
  local density=2^((50-(cfg.marker_density or 50))/25)
  local mandatory={};local last=0;local spacing=cfg.detail_ms/1000*density
  for i=2,#points-1 do
    local p=points[i];local prev,nextp=points[i-1],points[i+1]
    if p.boundary then mandatory[i]=true end
    if p.onset and p.onset>.55 and p.onset>=(prev.onset or 0) and p.onset>(nextp.onset or 0)
      and p.t-last>=spacing then mandatory[i]=true;last=p.t end
  end
  local reduced=simplify(points,(.006+(cfg.smooth_ms or 0)/1000*.035)*density,mandatory,job)
  -- RDP alone can retain almost adjacent points at abrupt path corners. Thin them first,
  -- then re-check every resulting segment rather than passing them unchecked to REAPER.
  local sparse={reduced[1]}
  for i=2,#reduced-1 do
    local p=reduced[i]
    if p.boundary or p.t-sparse[#sparse].t>=math.min(.04,spacing*.5) and s.len-p.t>=.025 then sparse[#sparse+1]=p end
  end
  sparse[#sparse+1]=reduced[#reduced]
  -- Retain the original map's knots so the zero/full blend also preserves an
  -- existing piecewise-linear source map between its original stretch markers.
  for _,part in ipairs(Audio.parts(s)) do
    for _,m in ipairs(part.markers) do insert_knot(sparse,(part.pos-s.pos)+m.pos/part.rate,'knot') end
  end
  -- Участки со скоростью 1x (смещение цели не меняется) не несут тайминга: внутри такого участка остаются только его
  -- первая и последняя точки. Края, границы айтемов и исходные маркеры тейка (edge/boundary/knot) не трогаются никогда —
  -- от них зависит связь и сохранение прежней карты. Допуск 20 мкс: карта звучит так же, ломаная та же.
  local hidden_1x=0
  if cfg.hide_1x~=0 then
    local tol=2e-5
    local function offset(p) return p.target-p.t end
    local function pinned(p) return p.edge or p.boundary or p.knot end
    local kept={sparse[1]};local ref=offset(sparse[1]);local pending
    for i=2,#sparse do
      local p=sparse[i];local last=i==#sparse
      if not last and not pinned(p) and math.abs(offset(p)-ref)<=tol then
        if pending then hidden_1x=hidden_1x+1 end;pending=p
      else
        if pending then kept[#kept+1]=pending;pending=nil end
        kept[#kept+1]=p;ref=offset(p)
      end
    end
    sparse=kept
  end
  local function part_index(t)
    if not s.composite then return 1 end
    for k,part in ipairs(s.parts) do local a=part.pos-s.pos;if t>=a-1e-9 and t<=a+part.len+1e-9 then return k end end
    return nil
  end
  local max_shift=0;local out={};local minratio,maxratio=math.huge,0
  for i,p in ipairs(sparse) do
    max_shift=math.max(max_shift,math.abs(p.target-(s.pos+p.t)))
    out[i]={t=p.t,target=p.target,source=Audio.source_time(s,p.t),confidence=DSP.clamp(1-p.cost/.9,0,1),edge=p.edge,boundary=p.boundary}
    if i>1 then
      local dt=p.target-sparse[i-1].target;local src=p.t-sparse[i-1].t
      local same_part=part_index(p.t)~=nil and part_index(p.t)==part_index(sparse[i-1].t)
      if dt<=1e-8 or same_part and out[i].source<=out[i-1].source then return nil,'Non-monotonic marker map was rejected.' end
      local v=src/dt;minratio=math.min(minratio,v);maxratio=math.max(maxratio,v)
      if v<1/ratio-1e-6 or v>ratio+1e-6 then return nil,'A stretch segment exceeded the configured limit.' end
    end
  end
  if max_shift>cfg.search_s+1e-5 then return nil,'The proposed shift exceeds the search limit.' end
  local newpos=out[1].target;local newlen=out[#out].target-newpos
  if newpos<0 then return nil,'The proposed item would start before project time zero.' end
  local base={markers=out,pos=newpos,len=newlen,snapshot=s,stats=stats,limited=limited,hidden_1x=hidden_1x,
    min_ratio=minratio,max_ratio=maxratio,max_shift=max_shift,unchanged=max_shift<.001,
    review=stats.confidence<.4 or stats.coverage<.55 or (stats.support or 1)<.65}
  return M.blend(base,cfg.strength),nil,base
end
function M.blend(base,amount)
  if base.hybrid then return import('align/hybrid/plan').blend(base,amount)end
  local fraction=DSP.clamp(amount/100,0,1);local s=base.snapshot
  local plan={};for k,v in pairs(base) do plan[k]=v end
  plan.markers={};plan.min_ratio,plan.max_ratio=math.huge,0;plan.max_shift=0
  local jump,previous=0,nil
  for i,m in ipairs(base.markers) do
    local target=s.pos+m.t+(m.target-s.pos-m.t)*fraction
    local p={t=m.t,target=target,source=m.source,confidence=m.confidence,edge=m.edge,boundary=m.boundary};plan.markers[i]=p
    plan.max_shift=math.max(plan.max_shift,math.abs(target-s.pos-m.t))
    if i>1 then local a=plan.markers[i-1];local ratio=(p.t-a.t)/(p.target-a.target)
      plan.min_ratio=math.min(plan.min_ratio,ratio);plan.max_ratio=math.max(plan.max_ratio,ratio)
      if previous then jump=jump+math.abs(math.log(ratio/previous)) end;previous=ratio
    end
  end
  plan.pos=plan.markers[1].target;plan.len=plan.markers[#plan.markers].target-plan.pos
  plan.unchanged=plan.max_shift<.001;plan.amount=amount
  plan.rate_variation=jump/math.max(1,#plan.markers-2)
  return plan
end
function M.target(plan,t)
  if plan.hybrid then return import('align/hybrid/plan').target(plan,t)end
  local p=plan.markers;local lo,hi=1,#p
  if t<=p[1].t then return p[1].target+t-p[1].t end
  if t>=p[#p].t then return p[#p].target+t-p[#p].t end
  while hi-lo>1 do local m=(lo+hi)//2;if p[m].t<=t then lo=m else hi=m end end
  return p[lo].target+(p[hi].target-p[lo].target)*(t-p[lo].t)/(p[hi].t-p[lo].t)
end
-- Per-item plans of a grouped role: each item gets the markers inside its own
-- span plus exact edge knots, with source time from its own take.
function M.slice(plan)
  local s=plan.snapshot
  if not s.composite then return {plan} end
  local out={}
  for _,part in ipairs(s.parts) do
    local a=part.pos-s.pos;local b=a+part.len
    local markers={{t=0,target=M.target(plan,a),edge=true}}
    for _,m in ipairs(plan.markers) do
      if m.t>a+1e-7 and m.t<b-1e-7 then markers[#markers+1]={t=m.t-a,target=m.target,confidence=m.confidence} end
    end
    markers[#markers+1]={t=part.len,target=M.target(plan,b),edge=true}
    for _,m in ipairs(markers) do m.source=Audio.source_time(part,m.t) end
    local pos=markers[1].target
    out[#out+1]={snapshot=part,pos=pos,len=markers[#markers].target-pos,markers=markers,unchanged=plan.unchanged,amount=plan.amount,parent=plan}
  end
  return out
end
return M
