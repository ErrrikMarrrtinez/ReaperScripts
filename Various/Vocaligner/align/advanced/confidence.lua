-- @noindex
local import=...;local U=import('align/util');local M={}
function M.measure(result,ref,dub,phrase,cfg)
  local mass,weighted,sum,paired,content,supported=0,0,0,0,0,0
  local observations={};local by_frame={};local maxspread=0
  for i=phrase.first,phrase.last do content=content+dub.frames[i].mass*dub.frames[i].event end
  for _,p in ipairs(result.path)do
    local f=dub.frames[p.i];local cm=p.mass*f.event
    paired=paired+cm
    if p.reliability>=cfg.min_pair then sum=sum+cm*p.reliability*p.cost;weighted=weighted+cm*p.reliability end
    if p.supported and p.cost<=cfg.accept_mean then
      supported=supported+cm;local a=by_frame[p.i]
      if not a then a={i=p.i,u=f.t,mass=0,sum=0,weight=0,min=math.huge,max=-math.huge,cost=0,reliability=0,onset=f.onset};by_frame[p.i]=a end
      a.mass=a.mass+p.mass;a.sum=a.sum+p.mass*p.guide_project_s;a.weight=a.weight+cm*p.reliability
      a.min=math.min(a.min,p.guide_project_s);a.max=math.max(a.max,p.guide_project_s)
      a.cost=a.cost+p.mass*p.cost;a.reliability=a.reliability+p.mass*p.reliability
    end
  end
  local longest,run,previous=0,0,nil;local events=0;local last_event=-math.huge
  for i=phrase.first,phrase.last do
    local a=by_frame[i];local f=dub.frames[i]
    if a then
      a.guide_project_s=a.sum/a.mass;a.spread=a.max-a.min;a.cost=a.cost/a.mass;a.reliability=a.reliability/a.mass
      a.weight=a.weight/(1+a.spread/.02);a.left=f.left;a.right=f.right
      observations[#observations+1]=a;maxspread=math.max(maxspread,a.spread)
      run=(previous==i-1 and run or 0)+f.mass*.01*f.event;longest=math.max(longest,run);previous=i
      local prev,nextf=dub.frames[i-1],dub.frames[i+1]
      if prev and nextf and f.t-last_event>=.06 and (f.onset>=.65 and f.onset>=prev.onset and f.onset>nextf.onset or f.change>=.70 and f.change>=prev.change and f.change>nextf.change)then events=events+1;last_event=f.t end
    else run=0;previous=nil end
  end
  local gap_mass=0;for _,g in ipairs(result.gaps)do
    local data=g.side=='dub' and dub or ref
    for i=g.first,g.last do gap_mass=gap_mass+data.frames[i].mass end
  end
  result.observations=observations
  result.evidence={acoustic_mean=weighted>0 and sum/weighted or cfg.max_cost,coverage=content>0 and supported/content or 0,
    content_duration=content*.01,supported_duration=supported*.01,longest_support_s=longest,gap_burden=gap_mass/result.query_mass,
    paired_content_duration=paired*.01,distinct_events=events,within_frame_spread=maxspread,content_mass=content,
    evidence_score=content>0 and U.clamp(supported/content*(1-(weighted>0 and sum/weighted or cfg.max_cost)/cfg.max_cost),0,1) or 0}
  return result.evidence
end
function M.eligible(result,cfg,sole)
  local e=result.evidence;local reasons={}
  if e.acoustic_mean>(sole and cfg.sole_mean or cfg.accept_mean)then reasons[#reasons+1]='acoustic_fit' end
  if e.coverage<(sole and cfg.sole_coverage or cfg.accept_coverage)then reasons[#reasons+1]='content_coverage' end
  if e.gap_burden>(sole and cfg.sole_gap or cfg.accept_gap)then reasons[#reasons+1]='gap_burden' end
  if e.longest_support_s<cfg.min_support_s or e.content_duration<cfg.min_support_s then reasons[#reasons+1]='short_support' end
  return #reasons==0,reasons
end
function M.distinct(a,b,cfg)
  local ai,bi=1,1
  while ai<=#a.observations and bi<=#b.observations do
    local x,y=a.observations[ai],b.observations[bi]
    if x.i==y.i then if math.abs(x.guide_project_s-y.guide_project_s)>cfg.distinct_s+1e-9 then return true end;ai=ai+1;bi=bi+1
    elseif x.i<y.i then ai=ai+1 else bi=bi+1 end
  end
  return false
end
function M.islands(result,dub,phrase)
  local out,current={},nil
  for _,o in ipairs(result.observations)do
    if not current or o.i~=current.last+1 then
      current={id=tostring(phrase.id)..':'..tostring(#out+1),phrase_id=phrase.id,status='accepted',first=o.i,last=o.i,observations={}}
      out[#out+1]=current
    end
    current.last=o.i;current.observations[#current.observations+1]=o
  end
  for _,island in ipairs(out)do
    island.left=dub.frames[island.first].left;island.right=dub.frames[island.last].right
    island.start_s=island.left;island.end_s=island.right
  end
  return out
end
-- A close competitor need not invalidate the parts where every eligible
-- placement agrees. This is an intersection, never a vote or a lower margin.
function M.consensus(result,variants,dub,phrase,cfg,blocked)
  local competitors={};local maps={}
  for _,r in ipairs(variants)do
    if r.eligible and not r.search_incomplete and r.score-result.score<=cfg.margin_min+1e-12 then
      competitors[#competitors+1]=r;local map={};maps[#maps+1]=map
      for _,o in ipairs(r.observations)do map[o.i]=o end
    end
  end
  if #competitors<2 then return {},{competitors=#competitors,reason='insufficient_alternatives'}end
  local observations={}
  for _,o in ipairs(result.observations)do
    local lo,hi=math.huge,-math.huge;local agree=true
    for _,map in ipairs(maps)do local v=map[o.i]
      if not v then agree=false;break end
      lo=math.min(lo,v.guide_project_s);hi=math.max(hi,v.guide_project_s)
    end
    for _,z in ipairs(blocked or {})do if o.u>=z.start_s and o.u<=z.end_s then agree=false;break end end
    if agree and hi-lo<=cfg.consensus_s+1e-9 then
      local copy=U.copy(o);copy.consensus_spread=hi-lo;observations[#observations+1]=copy
    end
  end
  local runs=M.islands({observations=observations},dub,phrase);local out={};local mass=0
  for _,s in ipairs(runs)do if s.end_s-s.start_s>=cfg.consensus_min_s-1e-9 then
    s.confidence_scope='local_consensus';s.competitors=#competitors;s.max_spread=0
    for _,o in ipairs(s.observations)do mass=mass+o.mass*dub.frames[o.i].event;s.max_spread=math.max(s.max_spread,o.consensus_spread)end
    out[#out+1]=s
  end end
  return out,{competitors=#competitors,content_mass=mass,spread_limit_s=cfg.consensus_s}
end
return M
