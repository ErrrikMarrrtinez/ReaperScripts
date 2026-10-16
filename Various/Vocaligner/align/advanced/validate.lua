-- @noindex
local import=...;local U=import('align/util');local Audio=import('audio');local M={}
local function source_target(markers,source)
  local lo,hi=1,#markers
  if source<markers[1].source-1e-8 or source>markers[hi].source+1e-8 then return nil end
  while hi-lo>1 do local m=(lo+hi)//2;if markers[m].source<=source then lo=m else hi=m end end
  local a,b=markers[lo],markers[hi]
  return a.target+(b.target-a.target)*(source-a.source)/(b.source-a.source)
end
M.source_target=source_target
local function time_target(markers,t)
  local lo,hi=1,#markers
  if t<markers[1].t-1e-8 or t>markers[hi].t+1e-8 then return nil end
  while hi-lo>1 do local m=(lo+hi)//2;if markers[m].t<=t then lo=m else hi=m end end
  local a,b=markers[lo],markers[hi]
  return a.target+(b.target-a.target)*(t-a.t)/(b.t-a.t)
end
local function source_limit(s)
  local source_end=s.source_length
  if source_end then
    local captured_end=Audio.source_time(s,s.len)
    local sample_slack=2/(s.source_rate and s.source_rate>0 and s.source_rate or 44100)
    -- Preserve the sub-sample item tail accepted by Audio.capture (e.g. Glue).
    -- This permits only the existing endpoint; it cannot extend source content.
    if captured_end>source_end and captured_end-source_end<=sample_slack then source_end=captured_end end
  end
  return source_end
end
function M.run(plan,cfg,budget)
  local p,s,markers=plan.problem,plan.snapshot,plan.markers
  if not p or not s or not markers or #markers<2 or #markers>cfg.max_markers then return nil,'Invalid marker count' end
  if not U.finite(plan.pos) or not U.finite(plan.len) or plan.pos<0 or plan.len<=0 then return nil,'Invalid item bounds' end
  local tol=cfg.geometry_tolerance;local composite=s.composite
  local source_end=not composite and source_limit(s)
  local limits={};if composite then for k,part in ipairs(s.parts)do limits[k]=source_limit(part)end end
  local function same_part(t1,t2)local a=Audio.part_index(s,t1);return a~=nil and a==Audio.part_index(s,t2)end
  if math.abs(markers[1].t)>tol or math.abs(markers[#markers].t-s.len)>tol then return nil,'Missing source endpoints' end
  for i,m in ipairs(markers)do
    if not U.finite(m.t) or not U.finite(m.target) or not U.finite(m.source) then return nil,'Nonfinite marker' end
    local limit=source_end;if composite then local k=Audio.part_index(s,m.t);limit=k and limits[k] end
    if m.source < -tol or limit and m.source>limit+tol then return nil,'Marker exceeds physical source bounds' end
    if math.abs(Audio.source_time(s,m.t)-m.source)>tol then return nil,'Marker source domain mismatch' end
    if i>1 and (m.t<=markers[i-1].t or m.target<=markers[i-1].target or (not composite or same_part(markers[i-1].t,m.t)) and m.source<=markers[i-1].source)then return nil,'Nonmonotone marker map' end
    local native=(m.target-plan.pos)*s.rate
    if not U.finite(native) or native<0 or native>plan.len*s.rate+tol then return nil,'Invalid native marker coordinate' end
  end
  if math.abs(markers[1].target-plan.pos)>tol or math.abs(markers[#markers].target-plan.pos-plan.len)>tol then return nil,'Item and marker endpoints disagree' end
  local max_error,min_ratio,max_ratio,min_source,max_source,shift=0,math.huge,0,math.huge,0,0
  local previous;local marker_index=1
  for i,u in ipairs(p.u)do
    local source=Audio.source_time(s,u);local y=composite and time_target(markers,u) or source_target(markers,source)
    if not y then return nil,'Sparse map lost source content',{i}end
    local delta=y-(s.pos+u);local error=math.abs(y-plan.dense[i].target)
    if not U.finite(delta)then return nil,'Nonfinite sparse displacement',{i}end
    local allowed=p.attack[i] and cfg.attack_error or cfg.map_error
    if error>allowed+tol then return nil,'Sparse map exceeds its representation error',{i}end
    if delta<p.lower[i]-tol or delta>p.upper[i]+tol then return nil,'Sparse map violates protection or displacement bounds',{i}end
    if p.mandatory[i]then
      while marker_index<#markers and markers[marker_index].t<u-1e-10 do marker_index=marker_index+1 end
      if math.abs(markers[marker_index].t-u)>1e-9 then return nil,'Missing mandatory source/pin/protection knot',{i}end
      if error>tol then return nil,'Mandatory target moved during reduction',{i}end
    end
    if previous then
      local h=u-p.u[i-1];local dy=y-previous.y;local ds=source-previous.source
      local within=not composite or same_part(p.u[i-1],u)
      if dy<=0 or within and ds<=0 then return nil,'Nonpositive elementary map interval',{i-1,i}end
      local ddelta=delta-previous.delta
      if ddelta<p.dlower[i-1]-tol or ddelta>p.dupper[i-1]+tol then return nil,'Sparse map violates a local rate bound',{i-1,i}end
      min_ratio=math.min(min_ratio,h/dy);max_ratio=math.max(max_ratio,h/dy)
      if within then min_source=math.min(min_source,ds/dy);max_source=math.max(max_source,ds/dy)end
    end
    max_error=math.max(max_error,error);shift=math.max(shift,math.abs(delta));previous={y=y,source=source,delta=delta}
    if budget then budget:add('reduce',1);if i%256==0 then budget:checkpoint(nil,'Validating source-time map')end end
  end
  return {max_map_error=max_error,min_ratio=min_ratio,max_ratio=max_ratio,min_source_rate=min_source,max_source_rate=max_source,
    max_shift=shift,points_checked=#p.u,markers=#markers,geometry_tolerance_s=tol,map_error_s=cfg.map_error,
    source_cap_enabled=cfg.abs_rate_min>0 and cfg.abs_rate_max>0}
end
return M
