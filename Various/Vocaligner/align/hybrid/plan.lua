-- @noindex
local import=...;local DSP=import('dsp');local Audio=import('audio');local M={}
local presets={
  {name='Natural',error=.020,strain=18,compression=20},
  {name='Balanced',error=.012,strain=8,compression=45},
  {name='Tight',error=.006,strain=2,compression=80},
}
M.presets=presets
local function clamp(x,a,b)return math.max(a,math.min(b,x))end
local function copy(t)local out={};for k,v in pairs(t)do out[k]=v end;return out end
local function at(data,t)return data.frames[clamp(math.floor(t/data.hop+.5)+1,1,#data.frames)]end
-- This is an edit planner, not a new audio stretcher. It fits the raw match
-- evidence, then compares rigid motion with attack-preserving duration edits.
-- The renderer leaves actual time-scale modification to REAPER.
local function segments(data,cfg,no_split)
  local s=data.snapshot;local out={};local quiet=math.min((data.gate or 0)*.35,(data.level_top or 0)*.004)
  local preset=clamp(math.floor(cfg.hybrid_preset or 2),1,3)
  -- A cut preserves both sides, whereas a trim removes a shoulder. Use separate
  -- evidence thresholds so continuous recordings do not require digital silence
  -- for every cut. The stricter trimming threshold never follows this preference.
  local cut_level=math.min((data.gate or 0)*({.4,.55,.7})[preset],(data.level_top or 0)*({.02,.045,.07})[preset])
  local margin=math.max(.035,data.hop*3);local minimum=({.11,.065,.045})[preset]
  local function silent(t)local f=at(data,t);return f and f.rms<=quiet and (f.onset or 0)<.15 end
  local function cuttable(t)local f=at(data,t);return f and f.rms<=cut_level and (f.onset or 0)<({.15,.25,.35})[preset]end
  for part_index,part in ipairs(Audio.parts(s))do
    local a=part.pos-s.pos;local b=a+part.len;local cuts={a};local run
    for i=math.max(1,math.floor(a/data.hop)+1),math.min(#data.frames,math.ceil(b/data.hop))do
      local t=(i-1)*data.hop
      if cuttable(t)then run=run or t
      elseif run then
        if not no_split and t-run>=minimum and run-a>math.max(.10,part.fade_in or 0) and b-t>math.max(.10,part.fade_out or 0) then cuts[#cuts+1]=(run+t)*.5 end
        run=nil
      end
    end
    cuts[#cuts+1]=b
    for i=2,#cuts do
      local left,right=cuts[i-1],cuts[i];local active_a,active_b=left,right
      while active_a<right-margin and silent(active_a)do active_a=active_a+data.hop end
      while active_b>active_a+margin and silent(active_b)do active_b=active_b-data.hop end
      out[#out+1]={a=left,b=right,part=part_index,
        trim_a=i>2 and math.max(left,active_a-margin)or left,
        trim_b=i<#cuts and math.min(right,active_b+margin)or right}
    end
  end
  return out
end
local function protected(data,a,b,part)
  local ranges={};local last=-math.huge
  for i=math.max(2,math.floor(a/data.hop)+1),math.min(#data.frames-1,math.ceil(b/data.hop))do
    local f=data.frames[i];local t=(i-1)*data.hop
    if f.active and (f.onset or 0)>.6 and f.onset>=(data.frames[i-1].onset or 0)
      and f.onset>(data.frames[i+1].onset or 0)and t-last>.07 then
      local lo,hi=math.max(a,t-.018),math.min(b,t+.032)
      if hi>lo then
        if ranges[#ranges]and ranges[#ranges][2]>=lo then ranges[#ranges][2]=hi
        else ranges[#ranges+1]={lo,hi}end
      end
      last=t
    end
  end
  if part then
    local origin=part.pos-data.snapshot.pos
    if (part.fade_in or 0)>0 and a<origin+part.fade_in then ranges[#ranges+1]={a,math.min(b,origin+part.fade_in)}end
    if (part.fade_out or 0)>0 and b>origin+part.len-part.fade_out then ranges[#ranges+1]={math.max(a,origin+part.len-part.fade_out),b}end
  end
  table.sort(ranges,function(x,y)return x[1]<y[1]end);local merged={}
  for _,p in ipairs(ranges)do local last=merged[#merged]
    if last and last[2]>=p[1]then last[2]=math.max(last[2],p[2])else merged[#merged+1]=p end
  end
  return merged
end
local function compliant(ranges,a,t)
  local amount=t-a
  for _,p in ipairs(ranges)do amount=amount-math.max(0,math.min(t,p[2])-math.max(a,p[1]))end
  return amount
end
local function map(markers,t)
  if t<=markers[1].t then return markers[1].target+t-markers[1].t end
  local last=markers[#markers];if t>=last.t then return last.target+t-last.t end
  local lo,hi=1,#markers
  while hi-lo>1 do local mid=(lo+hi)//2;if markers[mid].t<=t then lo=mid else hi=mid end end
  local a,b=markers[lo],markers[hi];return a.target+(b.target-a.target)*(t-a.t)/(b.t-a.t)
end
local function candidate(data,seg,evidence,cfg,preset,ratio,trim,ranges)
  if math.abs(ratio-1)<1e-6 then ratio=1 end
  local s=data.snapshot;local a,b=trim and seg.trim_a or seg.a,trim and seg.trim_b or seg.b
  local function shape(t)return t+(ratio-1)*compliant(ranges,seg.a,t)end
  local sum,weight=0,0
  for _,e in ipairs(evidence)do sum=sum+e.w*(e.y-s.pos-shape(e.t));weight=weight+e.w end
  local shift=weight>0 and sum/weight or 0
  local knots={a,b};if math.abs(ratio-1)>1e-9 then for _,p in ipairs(ranges)do for _,t in ipairs(p)do if t>a and t<b then knots[#knots+1]=t end end end end
  local part=Audio.parts(s)[seg.part];local offset=part.pos-s.pos
  for _,m in ipairs(part.markers)do local t=offset+m.pos/part.rate;if t>a and t<b then knots[#knots+1]=t end end
  table.sort(knots);local markers={};local maxshift=0
  for _,t in ipairs(knots)do if #markers==0 or t-markers[#markers].t>1e-8 then
    local target=s.pos+shape(t)+shift;maxshift=math.max(maxshift,math.abs(target-s.pos-t))
    markers[#markers+1]={t=t,target=target,source=Audio.source_time(part,t-offset),confidence=1}
  end end
  local pos=markers[1].target;local finish=markers[#markers].target
  if pos<0 or maxshift>(cfg.search_s or 1)+1e-7 then return end
  local loss=0
  for _,e in ipairs(evidence)do
    local residual=math.abs(s.pos+shape(e.t)+shift-e.y)
    loss=loss+e.w*(math.max(0,residual-(cfg.tolerance_ms or 0)/1000)/preset.error)^2
  end
  loss=loss/math.max(1,weight)
  local compression=clamp((cfg.hybrid_compression or preset.compression)/100,0,1)
  local strain=preset.strain*(ratio<1 and (1.4-1.35*compression)or 1.5)*math.log(ratio)^2*100
  local cost=loss+strain+(math.abs(shift)>.001 and .02 or 0)+(trim and .2 or 0)
  return {a=a,b=b,split_a=seg.a,split_b=seg.b,part=seg.part,markers=markers,pos=pos,len=finish-pos,
    cost=cost,ratio=ratio,trim=trim,max_shift=maxshift,protected=ranges}
end
-- A continuous phrase may contain several differently timed words. It needs
-- local elastic edits even when there is no quiet place to split it. These
-- candidates keep one item and distribute deformation between protected attacks.
local function local_candidate(data,seg,evidence,cfg,preset,trim,ranges,job)
  local s=data.snapshot;local a,b=trim and seg.trim_a or seg.a,trim and seg.trim_b or seg.b
  local times={a,b};local step=.08
  if (b-a)/step>24000 then return nil,'work_budget'end
  for t=a+step,b-step*.5,step do times[#times+1]=t end
  for _,g in ipairs(ranges)do for _,t in ipairs(g)do if t>a and t<b then times[#times+1]=t end end end
  local part=Audio.parts(s)[seg.part];local origin=part.pos-s.pos
  for _,m in ipairs(part.markers)do local t=origin+m.pos/part.rate;if t>a and t<b then times[#times+1]=t end end
  table.sort(times);local markers={};local left,right=1,0;local sw,sd=0,0
  local radius=({.070,.050,.035})[clamp(math.floor(cfg.hybrid_preset or 2),1,3)]
  for _,t in ipairs(times)do if #markers==0 or t-markers[#markers].t>1e-8 then
    while right<#evidence and evidence[right+1].t<=t+radius do right=right+1;local e=evidence[right];sw=sw+e.w;sd=sd+e.w*(e.y-s.pos-e.t)end
    while left<=right and evidence[left].t<t-radius do local e=evidence[left];sw=sw-e.w;sd=sd-e.w*(e.y-s.pos-e.t);left=left+1 end
    local nearest=evidence[math.max(1,math.min(#evidence,left))]
    local delta=sw>1e-8 and sd/sw or nearest.y-s.pos-nearest.t
    markers[#markers+1]={t=t,target=s.pos+t+delta,source=Audio.source_time(part,t-origin),confidence=1}
  end end
  local fraction=clamp((cfg.strength or 100)/100,0,1)
  local compression=clamp((cfg.hybrid_compression or preset.compression)/100,0,1)
  local lo=math.max(1/cfg.max_ratio,1-(.04+.46*compression)*fraction);local hi=math.min(cfg.max_ratio,1+.25*fraction)
  local bounds={};local guard=1
  for i=2,#markers do local p,q=markers[i-1],markers[i];local dx=q.t-p.t
    while ranges[guard]and ranges[guard][2]<=p.t+1e-9 do guard=guard+1 end
    local g=ranges[guard];local locked=g and p.t>=g[1]-1e-8 and q.t<=g[2]+1e-8
    bounds[i]={locked and dx or dx*lo,locked and dx or dx*hi}
  end
  -- Alternating projections enforce every interval, including unit-rate attack
  -- blocks. If the bounded solve has not converged, omit this candidate.
  for pass=1,192 do
    local error=0
    for k=2,#markers do local i=pass%2==0 and #markers-k+2 or k;local p,q=markers[i-1],markers[i]
      local dy=q.target-p.target;local correction=clamp(dy,bounds[i][1],bounds[i][2])-dy
      p.target=p.target-correction*.5;q.target=q.target+correction*.5;error=math.max(error,math.abs(correction))
    end
    if job then job:checkpoint()end
    if error<1e-10 then break end
  end
  local strain,variation,maxshift=0,0,0;local previous;local minratio,maxratio=1,1
  for i,m in ipairs(markers)do
    maxshift=math.max(maxshift,math.abs(m.target-s.pos-m.t))
    if i>1 then local p=markers[i-1];local dx=m.t-p.t;local dy=m.target-p.target
      if dy<bounds[i][1]-dx*1e-7 or dy>bounds[i][2]+dx*1e-7 then return nil,'projection_did_not_converge'end
      local ratio=dy/dx;minratio=math.min(minratio,ratio);maxratio=math.max(maxratio,ratio)
      strain=strain+dx*preset.strain*(ratio<1 and (1.4-1.35*compression)or 1.5)*math.log(ratio)^2*100
      if previous then variation=variation+math.abs(math.log(ratio/previous))end;previous=ratio
    end
  end
  if markers[1].target<0 or maxshift>cfg.search_s+1e-7 then return nil,'search_limit'end
  local loss,weight=0,0
  for _,e in ipairs(evidence)do loss=loss+e.w*(math.max(0,math.abs(map(markers,e.t)-e.y)-(cfg.tolerance_ms or 0)/1000)/preset.error)^2;weight=weight+e.w end
  return {a=a,b=b,split_a=seg.a,split_b=seg.b,part=seg.part,markers=markers,pos=markers[1].target,
    len=markers[#markers].target-markers[1].target,ratio=(markers[#markers].target-markers[1].target)/(b-a),
    cost=loss/math.max(1,weight)+strain/(b-a)+variation*.06+.15+(trim and .2 or 0),
    trim=trim,max_shift=maxshift,protected=ranges,local_edit=true,min_ratio=minratio,max_ratio=maxratio}
end
function M.build(ref,data,path,stats,cfg,job,no_split)
  local s=data.snapshot
  if s.overlap_s and s.overlap_s>1e-7 then return nil,'Hybrid needs non-overlapping source items. Use Classic Stretch for existing crossfaded groups.'end
  local preset=presets[clamp(math.floor(cfg.hybrid_preset or 2),1,3)];local spans=segments(data,cfg,no_split)
  if #spans>256 then return nil,'Hybrid found more than 256 fragments. Work on a shorter selection.'end
  local fraction=clamp((cfg.strength or 100)/100,0,1)
  local lists={};local cursor=1;local trusted=0
  local diagnostics={local_candidates=0,local_rejected={},segments=#spans}
  for k,seg in ipairs(spans)do
    local ev={}
    while cursor<=#path and path[cursor].dub<seg.a do cursor=cursor+1 end
    local j=cursor
    while j<=#path and path[j].dub<=seg.b do
      local p=path[j];local f=at(data,p.dub)
      if p.active and p.cost<.55 and f.active then
        local shift=clamp(p.ref-s.pos-p.dub,-cfg.search_s,cfg.search_s)*fraction
        ev[#ev+1]={t=p.dub,y=s.pos+p.dub+shift,w=(1-p.cost/.6)^2*(1+2*math.min(1,f.onset or 0))}
      end
      j=j+1
    end
    cursor=j;trusted=trusted+#ev
    local ranges=protected(data,seg.a,seg.b,Audio.parts(s)[seg.part]);local choices={}
    -- A true no-edit alternative remains feasible even when correspondence is weak.
    local unchanged=candidate(data,seg,{},cfg,preset,1,false,ranges)
    if unchanged then
      local loss,weight=0,0
      for _,e in ipairs(ev)do loss=loss+e.w*(math.max(0,math.abs(s.pos+e.t-e.y)-(cfg.tolerance_ms or 0)/1000)/preset.error)^2;weight=weight+e.w end
      unchanged.cost=loss/math.max(1,weight);choices[1]=unchanged
    end
    if #ev>=4 and ev[#ev].t-ev[1].t>.06 then
      local sw,sx,sy,sxx,sxy=0,0,0,0,0
      for _,e in ipairs(ev)do local x=compliant(ranges,seg.a,e.t);local y=e.y-s.pos-e.t
        sw=sw+e.w;sx=sx+e.w*x;sy=sy+e.w*y;sxx=sxx+e.w*x*x;sxy=sxy+e.w*x*y end
      local slope=(sw*sxy-sx*sy)/math.max(1e-12,sw*sxx-sx*sx)
      local compression=clamp((cfg.hybrid_compression or preset.compression)/100,0,1)
      local lo=math.max(1/cfg.max_ratio,1-(.04+.46*compression)*fraction)
      local hi=math.min(cfg.max_ratio,1+.25*fraction)
      local best=clamp(1+slope,lo,hi)
      for _,ratio in ipairs({1,1+(best-1)*.5,best})do for _,trim in ipairs({false,true})do
        local p=candidate(data,seg,ev,cfg,preset,ratio,trim,ranges)
        if p then choices[#choices+1]=p end
      end end
      for _,trim in ipairs({false,true})do local p,why=local_candidate(data,seg,ev,cfg,preset,trim,ranges,job)
        if p then choices[#choices+1]=p;diagnostics.local_candidates=diagnostics.local_candidates+1
        else diagnostics.local_rejected[why or 'unavailable']=(diagnostics.local_rejected[why or 'unavailable']or 0)+1 end
      end
    end
    if #choices==0 then return nil,'No safe Hybrid edit fits inside project time.'end
    lists[k]=choices
    if job then job:checkpoint()end
  end
  if trusted<4 then return nil,'Too few trustworthy correspondences for Hybrid.'end
  -- Joint selection prevents a locally attractive move from colliding with the
  -- next word. Unsafe candidates are excluded, never repaired by clipping voice.
  for k,choices in ipairs(lists)do for _,p in ipairs(choices)do
    local weighted=p.cost*(p.split_b-p.split_a)/s.len
    p.total=k==1 and weighted or math.huge
    if k>1 then for i,previous in ipairs(lists[k-1])do
      if previous.pos+previous.len<=p.pos+1e-8 then
        local seam=.015;local total=previous.total+weighted+seam
        if total<p.total then p.total=total;p.previous=i end
      end
    end end
  end end
  local index,best=nil,math.huge
  for i,p in ipairs(lists[#lists])do if p.total<best then best=p.total;index=i end end
  if not index then return nil,'Hybrid could not find a collision-free edit.'end
  local pieces={};for k=#lists,1,-1 do local p=lists[k][index];pieces[k]=p;index=p.previous end
  local markers={};local maxshift,compressed,moved,trimmed,stretch=0,0,0,0,0
  for _,p in ipairs(pieces)do
    maxshift=math.max(maxshift,p.max_shift);compressed=compressed+((p.min_ratio or p.ratio)<1-1e-6 and 1 or 0)
    stretch=stretch+((p.max_ratio or p.ratio)>1+1e-6 and 1 or 0);moved=moved+(p.max_shift>.001 and not p.local_edit and p.ratio==1 and 1 or 0)
    trimmed=trimmed+(p.a-p.split_a+p.split_b-p.b)
    for _,m in ipairs(p.markers)do if #markers==0 or m.t>markers[#markers].t+1e-8 then markers[#markers+1]=m end end
  end
  local pos=pieces[1].pos;local finish=pieces[#pieces].pos+pieces[#pieces].len
  local base={hybrid=true,snapshot=s,pieces=pieces,markers=markers,pos=pos,len=finish-pos,stats=stats,
    amount=cfg.strength,max_shift=maxshift,diagnostics=diagnostics,objective=best,unchanged=fraction==0 or maxshift<.001 and trimmed<.001,
    min_ratio=1,max_ratio=1,limited=0,review=(stats.confidence or 1)<.4 or (stats.coverage or 1)<.55,
    summary={moved=moved,compressed=compressed,stretched=stretch,trimmed_ms=trimmed*1000,fragments=#pieces},
    hybrid_input={ref=ref,data=data,path=path,stats=stats,cfg=copy(cfg)}}
  for _,p in ipairs(pieces)do base.min_ratio=math.min(base.min_ratio,1/(p.max_ratio or p.ratio));base.max_ratio=math.max(base.max_ratio,1/(p.min_ratio or p.ratio))end
  if not no_split and #pieces>#Audio.parts(s)then
    local intact=M.build(ref,data,path,stats,cfg,job,true)
    if intact and intact.objective<=base.objective then
      intact.diagnostics.split_alternative={fragments=#pieces,objective=base.objective}
      return intact,nil,intact
    end
  end
  return base,nil,base
end
function M.blend(base,amount)
  local i=base.hybrid_input;local cfg=copy(i.cfg);cfg.strength=amount
  local plan,why=M.build(i.ref,i.data,i.path,i.stats,cfg);assert(plan,why);return plan
end
function M.target(plan,t)
  local piece=plan.pieces[#plan.pieces]
  for _,p in ipairs(plan.pieces)do if t<=p.b then piece=p;break end end
  local a=piece.markers
  if t<=a[1].t then return a[1].target+t-a[1].t end
  for i=2,#a do if t<=a[i].t then local p,q=a[i-1],a[i];return p.target+(q.target-p.target)*(t-p.t)/(q.t-p.t)end end
  return a[#a].target+t-a[#a].t
end
function M.inverse(plan,target)
  for _,piece in ipairs(plan.pieces)do if target>=piece.pos and target<=piece.pos+piece.len then
    local a=piece.markers
    for i=2,#a do if target<=a[i].target then local p,q=a[i-1],a[i];return p.t+(q.t-p.t)*(target-p.target)/(q.target-p.target)end end
    return piece.b
  end end
  return -1e12
end
function M.validate(plan,cfg)
  assert(plan.hybrid and plan.hybrid_input and plan.snapshot==plan.hybrid_input.data.snapshot,'Invalid Hybrid capture')
  if plan.unchanged then return true end
  local s=plan.snapshot;local data=plan.hybrid_input.data;local previous;local ends={}
  local quiet=math.min((data.gate or 0)*.35,(data.level_top or 0)*.004)
  local preset=clamp(math.floor(cfg.hybrid_preset or 2),1,3)
  local cut_level=math.min((data.gate or 0)*({.4,.55,.7})[preset],(data.level_top or 0)*({.02,.045,.07})[preset])
  local function silence(a,b)
    for i=math.max(1,math.ceil(a/data.hop)+1),math.min(#data.frames,math.floor(b/data.hop)+1)do
      local f=data.frames[i];assert(f.rms<=quiet and (f.onset or 0)<.15,'Hybrid trim crosses audible content')
    end
  end
  for _,p in ipairs(plan.pieces)do
    local part=assert(Audio.parts(s)[p.part],'Unknown Hybrid source item');local origin=part.pos-s.pos
    if p.split_a>origin+1e-7 then
      local radius=({.11,.065,.045})[preset]*.4
      for i=math.max(1,math.ceil((p.split_a-radius)/data.hop)+1),math.min(#data.frames,math.floor((p.split_a+radius)/data.hop)+1)do
        local f=data.frames[i];assert(f.rms<=cut_level and (f.onset or 0)<({.15,.25,.35})[preset],'Hybrid split lacks a quiet boundary')
      end
    end
    assert(p.a>=p.split_a-1e-8 and p.b<=p.split_b+1e-8 and p.b>p.a,'Invalid Hybrid trim bounds')
    assert(math.abs(p.split_a-(ends[p.part]or origin))<1e-7,'Hybrid split omits source content')
    ends[p.part]=p.split_b
    assert(p.split_b<=origin+part.len+1e-7 and p.pos>=0 and p.len>0,'Invalid Hybrid item bounds')
    assert(not previous or previous.pos+previous.len<=p.pos+1e-7,'Hybrid fragments overlap');previous=p
    silence(p.split_a,p.a-1e-8);silence(p.b+1e-8,p.split_b)
    local markers=p.markers;assert(#markers>=2,'Hybrid needs explicit source endpoints')
    assert(math.abs(markers[1].t-p.a)<1e-7 and math.abs(markers[#markers].t-p.b)<1e-7,'Invalid Hybrid source endpoints')
    assert(math.abs(markers[1].target-p.pos)<1e-7 and math.abs(markers[#markers].target-p.pos-p.len)<1e-7,'Invalid Hybrid output endpoints')
    for i,m in ipairs(markers)do
      assert(m.t==m.t and m.target==m.target and math.abs(m.target)<math.huge,'Nonfinite Hybrid timing')
      assert(math.abs(m.source-Audio.source_time(part,m.t-origin))<1e-7,'Hybrid source map changed')
      assert(math.abs(m.target-s.pos-m.t)<=cfg.search_s+1e-7,'Hybrid exceeds Search range')
      if i>1 then local a=markers[i-1];local dx=m.t-a.t;local dy=m.target-a.target
        assert(dx>0 and dy>0 and m.source>a.source,'Nonmonotonic Hybrid source map')
        assert(dy/dx>=1/cfg.max_ratio-1e-6 and dy/dx<=cfg.max_ratio+1e-6,'Hybrid exceeds Stretch limit')
        for _,g in ipairs(p.protected)do if a.t>=g[1]-1e-8 and m.t<=g[2]+1e-8 then
          assert(math.abs(dy-dx)<1e-7,'Hybrid deforms a protected attack/fade')
        end end
      end
    end
  end
  for k,part in ipairs(Audio.parts(s))do assert(ends[k]and math.abs(ends[k]-(part.pos-s.pos+part.len))<1e-7,'Hybrid lost a source item')end
  return true
end
return M
