-- @noindex
local import=...;local U=import('align/util');local DTW=import('dtw');local Warp=import('warp');local F=import('align/advanced/features')
local Constraints=import('align/advanced/constraints');local M={}
-- Guided matcher: the Classic DTW path, smoothed into the Classic timing map,
-- supplies one dense dub-to-guide correspondence; the Advanced planner,
-- validators and renderer then shape it under the usual rate bounds, pins,
-- protected intervals and fade rules. This replaces the strict candidate
-- search, which on real doubles declared most content ambiguous and left it
-- unmoved.
local function excluded(t,zones)
  for _,z in ipairs(zones or {})do if z.kind=='exclude_match' and t>=z.start_s and t<=z.end_s then return true end end
  return false
end
local function silent_job()local j={checkpoint=function()end};function j:scope()return self end;return j end
-- Correspondence from a dense path ({dub=t,ref=project_s,cost,active}...).
-- `map(t)` gives the guide project time for a dub time; by default the raw
-- path is interpolated. Observations sit on the Advanced frame grid. One region
-- spans the whole dub: unsupported audio follows the map, and the head/tail
-- continue at the original rate, exactly as the Classic warp does.
function M.from_path(ref,dub,path,stats,cfg,regions,map,map_kind)
  map=map or function(t)return DTW.interpolate(path,t)end
  local supports={}
  for _,p in ipairs(path)do if p.active and p.cost<.8 then supports[#supports+1]={t=p.dub,cost=p.cost}end end
  if #supports<4 then return nil,U.error('no_usable_evidence','Too few trustworthy correspondences','match')end
  local function nearest(t)
    local lo,hi=1,#supports
    while hi-lo>1 do local m=(lo+hi)//2;if supports[m].t<=t then lo=m else hi=m end end
    local a,b=supports[lo],supports[hi]
    if math.abs(b.t-t)<math.abs(a.t-t)then return b end;return a
  end
  local frames=dub.frames;local observations={};local supported={};local total_content,supported_content=0,0
  for i,f in ipairs(frames)do
    local content=f.mass*f.event;total_content=total_content+content
    if not f.missing and f.event>=.30 and not excluded(f.t,regions)then
      local s=nearest(f.t)
      if math.abs(s.t-f.t)<=.025 then
        local reliability=U.clamp(1-s.cost/.9,0,1)
        if reliability>=cfg.min_pair then
          supported[i]=true;supported_content=supported_content+content
          observations[#observations+1]={i=i,u=f.t,mass=f.mass,weight=f.mass*f.event*reliability,guide_project_s=map(f.t),
            onset=f.onset,reliability=reliability,cost=s.cost,left=f.left,right=f.right,spread=0}
        end
      end
    end
  end
  if #observations<4 then return nil,U.error('no_usable_evidence','Too few supported frames on the Advanced grid','match')end
  -- Edge observations: the map's own head/tail (original rate), low weight.
  local first,last=observations[1],observations[#observations]
  local function edge(i)
    local f=frames[i]
    return {i=i,u=f.t,mass=f.mass,weight=f.mass*.05,guide_project_s=map(f.t),onset=f.onset,reliability=.05,cost=.8,left=f.left,right=f.right,spread=0,synthetic=true}
  end
  if first.i>1 then table.insert(observations,1,edge(1))end
  if last.i<#frames then observations[#observations+1]=edge(#frames)end
  local len=dub.snapshot and dub.snapshot.len or dub.len
  local mass,cost=0,0;for _,o in ipairs(observations)do if not o.synthetic then mass=mass+o.mass;cost=cost+o.mass*o.cost end end
  local segment={id='guided:1',phrase_id=1,status='accepted',first=1,last=#frames,observations=observations,
    left=0,right=len,start_s=0,end_s=len,margin=nil,margin_status='classic_path',
    evidence={acoustic_mean=mass>0 and cost/mass or 0,coverage=total_content>0 and supported_content/total_content or 0,
      content_duration=total_content*.01,supported_duration=supported_content*.01,content_mass=total_content,observations=#observations}}
  -- Informational: content the path did not support (it follows the map).
  local unmatched={};local run_first
  for i,f in ipairs(frames)do
    local gap=f.event>=.30 and not f.missing and not supported[i]
    if gap and not run_first then run_first=i
    elseif not gap and run_first then unmatched[#unmatched+1]={start_s=frames[run_first].left,end_s=frames[i-1].right,status='interpolated',reason='no_path_support'};run_first=nil end
  end
  if run_first then unmatched[#unmatched+1]={start_s=frames[run_first].left,end_s=frames[#frames].right,status='interpolated',reason='no_path_support'}end
  local coverage=segment.evidence.coverage
  return {schema_version=1,engine_id='advanced_v1',engine_version=cfg.algorithm_version,direction='dub_local_to_guide_project',matcher='guided',
    baseline_id=dub.baseline_id,guide_baseline_id=ref.baseline_id,segments={segment},unmatched=unmatched,phrases={},constraints=regions,
    status=coverage>.98 and 'matched' or 'partial',
    diagnostics={backend='Classic path',matcher='guided',map=map_kind or 'raw_path',coverage=coverage,content_duration=total_content*.01,accepted_phrases=1,ambiguous_phrases=0,
      candidate_count=0,states=0,cells=stats and stats.cells or 0,coarse_work=0,retries=0,traceback_bytes=0,heuristic_pruning_used=false,
      path_points=#path,path_supports=#supports,path_cost=stats and stats.cost,path_support=stats and stats.support,
      path_coverage=stats and stats.coverage,path_confidence=stats and stats.confidence,interpolated_runs=#unmatched}}
end
-- The Classic timing map at full strength and zero tolerance: smoothed shifts,
-- median filtering and the stretch limit, without Classic's blend. Its
-- piecewise-linear map is what the Advanced optimizer refines.
function M.classic_map(classic_ref,classic_dub,path,stats,classic_cfg,job)
  local c={};for k,v in pairs(classic_cfg)do c[k]=v end
  c.strength=100;c.tolerance_ms=0;c.smooth_ms=math.max(40,c.smooth_ms or 0);c.hybrid=0
  local _,why,base=Warp.build(classic_ref,classic_dub,path,stats,c,job)
  if not base then return nil,why end
  return function(t)return Warp.target(base,t)end,base
end
function M.run(ref,dub,classic_ref,classic_dub,cfg,classic_cfg,constraints,job)
  local ok,why=F.validate(ref,cfg);if not ok then return nil,U.error('no_usable_evidence',why,'features')end
  ok,why=F.validate(dub,cfg);if not ok then return nil,U.error('no_usable_evidence',why,'features')end
  local regions,err=Constraints.validate(constraints,dub.snapshot or {pos=dub.pos,len=dub.len,rate=1,offset=0,markers={}},
    ref.snapshot or {pos=ref.pos,len=ref.len},cfg)
  if not regions then return nil,err end
  if not classic_ref or not classic_dub then return nil,U.error('no_usable_evidence','Classic features are not available for the guided matcher','features')end
  job=job or silent_job()
  local path,stats=DTW.align(classic_ref,classic_dub,classic_cfg,job:scope(0,.85))
  if not path then return nil,U.error('no_usable_evidence',tostring(stats),'match')end
  -- The raw DTW path is a 10 ms staircase whose local slopes (0.5, 1, 2)
  -- violate stretch limits everywhere; use the smoothed Classic map instead.
  local map,base=M.classic_map(classic_ref,classic_dub,path,stats,classic_cfg,job:scope(.85,.95))
  local out,e=M.from_path(ref,dub,path,stats,cfg,regions,map,map and 'classic_map' or 'raw_path')
  if not out then return nil,e end
  if not map then out.diagnostics.classic_map_error=tostring(base)end
  U.checkpoint(job,1,'Matching complete');return out
end
return M
