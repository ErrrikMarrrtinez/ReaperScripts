-- @noindex
local import=...;local U=import('align/util');local Audio=import('audio');local C=import('align/advanced/constraints')
local QP=import('align/advanced/regularize');local Reduce=import('align/advanced/reduce');local M={}
local function soft(d,tolerance)return (d>=0 and 1 or -1)*math.max(0,math.abs(d)-tolerance)end
M.tolerance=soft
function M.baseline(s,correspondence,cfg)
  local markers={{t=0,target=s.pos,source=Audio.source_time(s,0)}}
  if s.composite then
    local knots={}
    for _,p in ipairs(s.parts)do local a=p.pos-s.pos;knots[#knots+1]=a;knots[#knots+1]=a+p.len;for _,m in ipairs(p.markers)do knots[#knots+1]=a+m.pos/p.rate end end
    table.sort(knots)
    for _,u in ipairs(knots)do if u>1e-10 and u<s.len-1e-10 and u-markers[#markers].t>1e-9 then markers[#markers+1]={t=u,target=s.pos+u,source=Audio.source_time(s,u),mandatory=true}end end
  end
  for _,m in ipairs(s.markers)do local u=m.pos/s.rate;if u>1e-10 and u<s.len-1e-10 then markers[#markers+1]={t=u,target=s.pos+u,source=m.src,mandatory=true}end end
  markers[#markers+1]={t=s.len,target=s.pos+s.len,source=Audio.source_time(s,s.len)}
  return {engine_id='advanced_v1',engine_version=cfg.algorithm_version,renderer_id='reaper_stretch_v2',snapshot=s,
    baseline_id=correspondence and correspondence.baseline_id,guide_baseline_id=correspondence and correspondence.guide_baseline_id,
    pos=s.pos,len=s.len,markers=markers,unchanged=true,exact_baseline=true,amount=cfg.strength,max_shift=0,min_ratio=1,max_ratio=1,
    status=correspondence and correspondence.status or 'matched',regions={},rate_variation=0,limited=0,
    validation={exact_baseline=true,source_cap_asserted=false},diagnostics={identity=true,reason=cfg.strength==0 and 'zero_strength' or 'within_tolerance'}}
end
local function index_of(grid,t)
  local lo,hi=1,#grid
  while lo<hi do local m=(lo+hi)//2;if grid[m]<t-1e-10 then lo=m+1 else hi=m end end
  assert(math.abs(grid[lo]-t)<=1e-9,'Required grid knot missing');return lo
end
local function observation(segment,u)
  local p=segment.observations;local lo,hi=1,#p
  if u<=p[1].u then return p[1].guide_project_s+u-p[1].u,p[1].weight/p[1].mass end
  if u>=p[hi].u then return p[hi].guide_project_s+u-p[hi].u,p[hi].weight/p[hi].mass end
  while hi-lo>1 do local m=(lo+hi)//2;if p[m].u<=u then lo=m else hi=m end end
  local a,b=p[lo],p[hi];local k=(u-a.u)/(b.u-a.u)
  return a.guide_project_s+(b.guide_project_s-a.guide_project_s)*k,a.weight/a.mass+(b.weight/b.mass-a.weight/a.mass)*k
end
local function in_interval(u,a,b)return u>=a-1e-10 and u<=b+1e-10 end
-- Item fade lengths from the captured ownership record. Audio inside a fade
-- must keep rate 1 relative to its item edge, or the host fade is deformed.
function M.fade_lengths(fades,len)
  local f=fades or {}
  local fi=math.max(0,f.D_FADEINLEN or 0,f.D_FADEINLEN_AUTO or 0)
  local fo=math.max(0,f.D_FADEOUTLEN or 0,f.D_FADEOUTLEN_AUTO or 0)
  if len then fi=math.min(fi,len);fo=math.min(fo,len)end
  return fi,fo
end
function M.build(ref,dub,correspondence,cfg,constraints,job,budget,options)
  local s=dub.snapshot
  if not s then return nil,U.error('unsupported_source_mapping','No captured source map','plan')end
  if cfg.strength==0 then return M.baseline(s,correspondence,cfg)end
  -- Rigid zones keep rate 1 against their item edge: item fades (per item of a
  -- grouped role). Their boundaries become mandatory knots below.
  local zones={}
  local owner=options and options.owner
  for k,p in ipairs(Audio.parts(s))do
    local a=s.composite and p.pos-s.pos or 0
    local fades=s.composite and owner and owner.parts and owner.parts[k] and owner.parts[k].fades or not s.composite and (options and options.fades or owner and owner.fades)
    local fi,fo=M.fade_lengths(fades,p.len)
    if fi>0 then zones[#zones+1]={a,a+fi}end
    if fo>0 then zones[#zones+1]={a+p.len-fo,a+p.len}end
  end
  if not correspondence or #correspondence.segments==0 then return nil,U.error(correspondence and correspondence.status=='ambiguous' and 'ambiguous_phrase' or 'no_usable_evidence','No accepted timing regions; captured timing is preserved','plan')end
  local list,err=C.validate(constraints or correspondence.constraints,s,ref.snapshot or {pos=ref.pos,len=ref.len},cfg)
  if not list then return nil,err end
  budget=budget or U.budget(cfg,job)
  local alpha,tol=cfg.strength/100,cfg.tolerance_ms/1000
  local grid,mandatory={},{}
  local function add(u,required)
    if not U.finite(u) or u<0 or u>s.len then U.fail('render_map_invalid','Invalid grid coordinate','plan')end
    grid[#grid+1]=u;if required then mandatory[#mandatory+1]=u end
  end
  add(0,true);add(s.len,true)
  for _,f in ipairs(dub.frames)do add(f.t,false)end
  for _,m in ipairs(s.markers)do add(m.pos/s.rate,true)end
  -- Item edges and each item's own source knots in a grouped role.
  local edges={}
  if s.composite then for _,p in ipairs(s.parts)do
    local a=p.pos-s.pos;edges[#edges+1]={value=a};edges[#edges+1]={value=a+p.len}
    for _,m in ipairs(p.markers)do edges[#edges+1]={value=a+m.pos/p.rate}end
  end end
  for _,seg in ipairs(correspondence.segments)do add(seg.start_s,true);add(seg.end_s,true);for _,o in ipairs(seg.observations)do add(o.u,false)end end
  for _,c in ipairs(list)do if c.dub_s then add(c.dub_s,true)else add(c.start_s,true);add(c.end_s,true)end end
  -- Fade boundaries are mandatory knots so the reduced marker map keeps the
  -- exact rate-1 fade intervals, not an interpolation across them. A boundary
  -- within 1 µs of an existing knot reuses that knot instead of creating a
  -- second node the resolution check below would reject.
  for _,z in ipairs(zones)do edges[#edges+1]={value=z[1],zone=z,side=1};edges[#edges+1]={value=z[2],zone=z,side=2}end
  for _,edge in ipairs(edges)do
    local value=math.max(0,math.min(s.len,edge.value))
    local snapped;for _,u in ipairs(grid)do if math.abs(u-value)<1e-6 then snapped=u;break end end
    if snapped then mandatory[#mandatory+1]=snapped;value=snapped else add(value,true)end
    if edge.zone then edge.zone[edge.side]=value end
  end
  table.sort(grid)
  local merged={};for _,u in ipairs(grid)do if #merged==0 or u-merged[#merged]>1e-10 then merged[#merged+1]=u end end;grid=merged
  for i=2,#grid do if grid[i]-grid[i-1]<1e-6-1e-12 then return nil,U.error('numeric_resolution_unsupported','Two required timing nodes are less than 1 microsecond apart','plan')end end
  local required={};for _,u in ipairs(mandatory)do required[index_of(grid,u)]=true end
  -- Source time increases strictly inside each item; it restarts between the
  -- items of a grouped role (part index nil = gap between items).
  local src,pidx={},{}
  for i,u in ipairs(grid)do
    src[i]=Audio.source_time(s,u);pidx[i]=Audio.part_index(s,u)
    if not U.finite(src[i])or i>1 and pidx[i] and pidx[i]==pidx[i-1] and src[i]<=src[i-1]then return nil,U.error('unsupported_source_mapping','Captured source map is not strictly increasing','plan')end
  end
  local function same_part(i,j)return pidx[i]~=nil and pidx[i]==pidx[j]end
  local absolute=cfg.abs_rate_min>0 or cfg.abs_rate_max>0
  if absolute then
    if cfg.abs_rate_min<=0 or cfg.abs_rate_max<cfg.abs_rate_min then return nil,U.error('constraints_conflict','Invalid absolute source-rate limits','plan')end
    for i=2,#grid do if same_part(i-1,i)then local rate=(src[i]-src[i-1])/(grid[i]-grid[i-1]);if rate<cfg.abs_rate_min-1e-9 or rate>cfg.abs_rate_max+1e-9 then return nil,U.error('constraints_conflict','Captured audio already exceeds the absolute source-rate limit','plan')end end end
  end
  local attacks={}
  for _,f in ipairs(dub.frames)do if f.onset>=.65 and f.onset_reliability>=.65 then attacks[#attacks+1]=f.t end end
  local function transient(u)
    -- Sorted event timestamps keep neighborhood lookup logarithmic on long takes.
    local lo,hi=1,#attacks+1;while lo<hi do local m=(lo+hi)//2;if attacks[m]<u then lo=m+1 else hi=m end end
    return attacks[lo] and attacks[lo]-u<=.02000001 or attacks[lo-1] and u-attacks[lo-1]<=.02000001 or false
  end
  local function in_fade(middle)
    for _,z in ipairs(zones)do if middle>=z[1]-1e-12 and middle<=z[2]+1e-12 then return true end end
    return false
  end
  local function rate_bounds(i,ratio)
    local h=grid[i+1]-grid[i];local middle=(grid[i+1]+grid[i])*.5
    if in_fade(middle)then return 0,0 end
    if transient(middle)then ratio=math.min(ratio,cfg.transient_ratio)end
    local lower,upper=h/ratio,h*ratio
    if absolute and same_part(i,i+1)then local ds=src[i+1]-src[i];lower=math.max(lower,ds/cfg.abs_rate_max);upper=math.min(upper,ds/cfg.abs_rate_min)end
    return lower-h,upper-h
  end
  local function protected(u)
    return C.inside(list,u,'protect_absolute') or C.inside(list,u,'exclude_match')
  end
  local function occupied(u,owner)
    for _,seg in ipairs(correspondence.segments)do if seg~=owner and in_interval(u,seg.start_s,seg.end_s)then return true end end
  end
  local function edge_continuation(seg,left)
    local at=left and seg.start_s or seg.end_s;local edge=left and 0 or s.len
    if math.abs(edge-at)>.01600001 then return false end
    local lo,hi=math.min(edge,at),math.max(edge,at)
    for _,c in ipairs(list)do
      if c.dub_s and in_interval(c.dub_s,lo,hi)or c.start_s and c.end_s>=lo and c.start_s<=hi then return false end
    end
    for _,z in ipairs(correspondence.unmatched or {})do if z.end_s>lo+1e-10 and z.start_s<hi-1e-10 then return false end end
    for _,f in ipairs(dub.frames)do if f.t>lo-1e-10 and f.t<hi+1e-10 and (left and f.t<at-1e-10 or not left and f.t>at+1e-10)then
      if f.missing or f.valid_fraction>=.75 then return false end
    end end
    return true
  end
  local shoulders,inferred,rejected,accepted={},{},{},{}
  local boundary_fixed={}
  local function shoulder(seg,left,desired)
    local inner=index_of(grid,left and seg.start_s or seg.end_s)
    if edge_continuation(seg,left)then return {start_s=left and 0 or seg.end_s,end_s=left and seg.start_s or s.len,inner=inner,kind='inferred_analysis_edge',owner=seg}end
    if math.abs(desired)<=cfg.geometry_tolerance then return {fixed=inner}end
    local sumlo,sumhi=0,0;local k=left and inner-1 or inner;local blocked=false
    while k>=1 and k<#grid do
      local outer=left and k or k+1;local span=math.abs(grid[outer]-grid[inner])
      -- The recruited audio is the frame at the outer knot. The interval
      -- midpoint sits exactly between two frame centres, so a float tie there
      -- could judge background by the phrase's own first frame.
      local mid=(grid[k]+grid[k+1])*.5;local frame=dub.frames[U.nearest(dub.frames,grid[outer])]
      if protected(mid)or protected(grid[outer])or occupied(mid,seg)or frame.missing or frame.valid_fraction<.75 or frame.background<.90 or frame.event>.10 or frame.onset>.20 then blocked=true;break end
      -- Stretching capacity is bounded by max_shoulder_s. Beyond that span the
      -- walk only checks whether eligible background continues to the item edge.
      if span<=cfg.max_shoulder_s+1e-9 then
        local a,b=rate_bounds(k,cfg.shoulder_ratio);sumlo=sumlo+a;sumhi=sumhi+b
        local need=left and desired or -desired
        if need>=sumlo-1e-9 and need<=sumhi+1e-9 then
          return {start_s=grid[math.min(inner,outer)],end_s=grid[math.max(inner,outer)],outer=outer,inner=inner,kind='background_shoulder',owner=seg,
            desired_endpoint=desired,available_s=span}
        end
      end
      k=k+(left and -1 or 1)
    end
    if not blocked then
      -- Only quiet, known background separates the phrase from the item edge
      -- and it cannot absorb the correction within its stretch bounds (for
      -- example the edge is inside a host fade, which must keep rate 1). The
      -- edge itself then moves: a rigid shift of background retains the fade,
      -- the same way an unknown analysis edge already travels with its phrase.
      local outer=left and 1 or #grid
      return {start_s=grid[math.min(inner,outer)],end_s=grid[math.max(inner,outer)],outer=outer,inner=inner,kind='background_shoulder',owner=seg,
        desired_endpoint=desired,available_s=math.abs(grid[outer]-grid[inner]),edge_free=true}
    end
    return nil
  end
  for _,seg in ipairs(correspondence.segments)do
    if seg.end_s>seg.start_s then
      local ga=observation(seg,seg.start_s);local gb=observation(seg,seg.end_s)
      local da=alpha*soft(ga-s.pos-seg.start_s,tol);local db=alpha*soft(gb-s.pos-seg.end_s,tol)
      local a=shoulder(seg,true,da);local b=shoulder(seg,false,db)
      -- Acoustic observations are soft targets. If neighboring audio must stay
      -- fixed, the supported region can ease to a fixed edge internally. The
      -- QP and independent validator still enforce every local stretch bound.
      -- No unknown/ambiguous sample is recruited as a transition shoulder.
      if seg.confidence_scope=='local_consensus' then
        if not a then a={fixed=index_of(grid,seg.start_s)};seg.internal_left=true end
        if not b then b={fixed=index_of(grid,seg.end_s)};seg.internal_right=true end
      end
      if a and b then
        accepted[#accepted+1]=seg
        for _,part in ipairs({a,b})do
          if part.fixed then boundary_fixed[part.fixed]=true
          elseif part.kind=='inferred_analysis_edge'then inferred[#inferred+1]=part;required[index_of(grid,part.start_s)]=true;required[index_of(grid,part.end_s)]=true
          else shoulders[#shoulders+1]=part;required[part.outer]=true;if not part.edge_free then boundary_fixed[part.outer]=true end end
        end
      else rejected[#rejected+1]={id=seg.id,reason='insufficient_background_shoulder',start_s=seg.start_s,end_s=seg.end_s,desired_left_s=da,desired_right_s=db}end
    else rejected[#rejected+1]={id=seg.id,reason='isolated_frame',start_s=seg.start_s,end_s=seg.end_s}end
    budget:checkpoint(nil,'Checking transition capacity')
  end
  if #accepted==0 then return nil,U.error('constraints_conflict','Accepted phrases have insufficient supported/background space for this correction','plan',{rejected_islands=rejected})end
  -- Two independent shoulders cannot claim the same unknown background. Reject
  -- their overlap rather than silently turning it into a third acoustic bridge.
  for i,a in ipairs(shoulders)do for j=i+1,#shoulders do local b=shoulders[j]
    if a.owner~=b.owner and math.max(a.start_s,b.start_s)<math.min(a.end_s,b.end_s)-1e-9 then
      return nil,U.error('constraints_conflict','Neighboring phrase transitions overlap; lower Strength or add constraints','plan')
    end
  end end
  local function region_at(u)
    if protected(u)then return nil,'protected' end
    for i,seg in ipairs(accepted)do if in_interval(u,seg.start_s,seg.end_s)then return i,'accepted',seg end end
    for _,part in ipairs(shoulders)do if in_interval(u,part.start_s,part.end_s)then for i,seg in ipairs(accepted)do if seg==part.owner then return i,'background_shoulder',part end end end end
    for _,part in ipairs(inferred)do if in_interval(u,part.start_s,part.end_s)then for i,seg in ipairs(accepted)do if seg==part.owner then return i,'inferred_analysis_edge',part end end end end
    return nil,'unmatched'
  end
  local p={u=grid,lower={},upper={},dlower={},dupper={},weights={},target={},region={},mandatory=required,attack={},status={},constraint_ids={}}
  local all_zero=true
  for i,u in ipairs(grid)do
    local id,kind,value=region_at(u);p.region[i]=id or 0;p.status[i]=kind;p.attack[i]=transient(u)
    p.lower[i]=math.max(-cfg.search_s,-s.pos-u);p.upper[i]=cfg.search_s;p.weights[i]=0;p.target[i]=0
    if not id or boundary_fixed[i]then p.lower[i]=0;p.upper[i]=0 end
    local width=((grid[i+1] or u)- (grid[i-1] or u))*.5/.01
    if kind=='accepted'then
      local target,trust=observation(value,u);p.target[i]=alpha*soft(target-s.pos-u,tol);p.weights[i]=width*trust
    elseif kind=='background_shoulder'then p.weights[i]=.02*width end
    if math.abs(p.target[i])>1e-10 then all_zero=false end
    if i>1 then
      local _,interval_kind=region_at((grid[i-1]+u)*.5)
      if interval_kind=='protected' or interval_kind=='unmatched' or interval_kind=='inferred_analysis_edge'then p.dlower[i-1]=0;p.dupper[i-1]=0
      else p.dlower[i-1],p.dupper[i-1]=rate_bounds(i-1,interval_kind=='background_shoulder' and cfg.shoulder_ratio or cfg.max_ratio)end
    end
    for _,c in ipairs(list)do
      if c.dub_s and math.abs(c.dub_s-u)<1e-9 then
        local target=alpha*(c.guide_project_s-s.pos-u);p.constraint_ids[i]=c.id
        if c.kind=='sync'then
          if target<p.lower[i]-1e-6 or target>p.upper[i]+1e-6 then return nil,U.error('constraints_conflict','Pin '..c.id..' conflicts with preserved timing','plan')end
          p.lower[i]=target;p.upper[i]=target
        else
          local w=10;local old=p.weights[i];p.target[i]=(old*p.target[i]+w*target)/(old+w);p.weights[i]=old+w
        end
        if math.abs(target)>1e-10 then all_zero=false end
      elseif c.start_s and in_interval(u,c.start_s,c.end_s)then p.constraint_ids[i]=c.id end
    end
  end
  if all_zero then return M.baseline(s,correspondence,cfg)end
  -- A guided correspondence is already a smooth, complete map. Its optimizer
  -- gets a shorter iteration budget and may finish with the validated nearest
  -- feasible point instead of refusing the whole dub.
  local qcfg=cfg
  if correspondence.matcher=='guided' then p.allow_approximate=true;qcfg=U.copy(cfg);qcfg.iterations=math.min(cfg.iterations,600)end
  local delta,solve=QP.solve(p,qcfg,budget);if not delta then return nil,solve end
  local dense={};for i,u in ipairs(grid)do dense[i]={t=u,source=src[i],target=s.pos+u+delta[i],status=p.status[i],mandatory=required[i]or false,constraint_ids=p.constraint_ids[i]}end
  local plan={engine_id='advanced_v1',engine_version=cfg.algorithm_version,renderer_id='reaper_stretch_v2',baseline_id=correspondence.baseline_id,
    guide_baseline_id=correspondence.guide_baseline_id,snapshot=s,pos=dense[1].target,len=dense[#dense].target-dense[1].target,
    amount=cfg.strength,dense=dense,problem=p,solver=solve,unchanged=false,status=#rejected>0 and 'partial' or correspondence.status,
    regions={},diagnostics={rejected_islands=rejected,shoulders=#shoulders,inferred_edges=#inferred,soft_pin_residuals={}}}
  for _,seg in ipairs(accepted)do plan.regions[#plan.regions+1]={start_s=seg.start_s,end_s=seg.end_s,status='accepted',id=seg.id,
    confidence_scope=seg.confidence_scope,internal_left=seg.internal_left,internal_right=seg.internal_right}end
  for _,group in ipairs({shoulders,inferred})do for _,part in ipairs(group)do plan.regions[#plan.regions+1]={start_s=part.start_s,end_s=part.end_s,status=part.kind,edge_free=part.edge_free}end end
  local moved=0;for _,part in ipairs(shoulders)do if part.edge_free then moved=moved+1 end end;plan.diagnostics.moved_edges=moved
  for _,c in ipairs(list)do if c.kind=='soft_sync'then local i=index_of(grid,c.dub_s);plan.diagnostics.soft_pin_residuals[#plan.diagnostics.soft_pin_residuals+1]={id=c.id,residual_s=delta[i]-alpha*(c.guide_project_s-s.pos-c.dub_s)}end end
  local reduced,reason=Reduce.run(plan,cfg,budget);if not reduced then return nil,reason end
  plan.max_shift=plan.validation.max_shift;plan.min_ratio=plan.validation.min_ratio;plan.max_ratio=plan.validation.max_ratio
  plan.min_source_rate=plan.validation.min_source_rate;plan.max_source_rate=plan.validation.max_source_rate
  local previous,jump=nil,0
  for i=2,#plan.markers do local a,b=plan.markers[i-1],plan.markers[i];local rate=(b.t-a.t)/(b.target-a.target)
    if previous then jump=jump+math.abs(math.log(rate/previous))end;previous=rate
  end
  plan.rate_variation=jump/math.max(1,#plan.markers-2);plan.limited=0
  return plan
end
return M
