-- @noindex
local import=...;local U=import('align/util');local Features=import('align/advanced/features');local Distance=import('align/advanced/distance');local M={}
function M.distinct(a,b,threshold)
  return math.abs(a.start_project-b.start_project)>=threshold-1e-9 or math.abs(a.end_project-b.end_project)>=threshold-1e-9
end
function M.generate(ref,dub,phrase,cfg,budget,coarse_ref)
  local query=Features.coarse(dub,phrase.first,phrase.last,4,budget.job)
  local reference=coarse_ref or Features.coarse(ref,nil,nil,4,budget.job)
  local offsets={};local steps=math.floor(cfg.search_s/.04+1e-8)
  for k=-steps,steps do offsets[#offsets+1]=k*.04 end
  if math.abs(steps*.04-cfg.search_s)>1e-8 then table.insert(offsets,1,-cfg.search_s);offsets[#offsets+1]=cfg.search_s end
  local candidates={};local baseline;local count=0
  for _,shift in ipairs(offsets)do for _,beta in ipairs({.75,.875,1,1.125,1.25})do
    count=count+1
    local start_rel=(dub.pos-ref.pos)+phrase.u0+shift
    local end_rel=start_rel+beta*(phrase.u1-phrase.u0)
    local end_shift=shift+(beta-1)*(phrase.u1-phrase.u0)
    if start_rel>=-1e-9 and end_rel<=ref.len+1e-9 and math.abs(end_shift)<=cfg.search_s+1e-9 then
      local sum,mass,prior=0,0,0
      for i,a in ipairs(query.frames)do
        local target=start_rel+beta*(a.t-phrase.u0);local j=U.nearest(reference.frames,target)
        local c=Distance.pair(a,reference.frames[j],cfg,query.frames[i-1],reference.frames[j-1],query.frames[i+1],reference.frames[j+1])
        sum=sum+a.mass*c;mass=mass+a.mass;prior=prior+a.mass*math.abs(shift+(beta-1)*(a.t-phrase.u0))/cfg.search_s
        budget:add('coarse',1);if i%64==0 then budget:checkpoint(nil,'Comparing phrase placements')end
      end
      if mass>0 and U.finite(sum)then
        local c={shift=shift,beta=beta,start_project=ref.pos+start_rel,end_project=ref.pos+end_rel,
          coarse_score=sum/mass+.018*prior/mass+.025*math.log(beta)^2,coarse_mass=mass}
        candidates[#candidates+1]=c;if shift==0 and beta==1 then c.baseline=true;baseline=c end
      end
    end
    budget:checkpoint(count/(#offsets*5),'Comparing phrase placements')
  end end
  table.sort(candidates,function(a,b)
    if a.coarse_score~=b.coarse_score then return a.coarse_score<b.coarse_score end
    if math.abs(a.shift)~=math.abs(b.shift)then return math.abs(a.shift)<math.abs(b.shift)end
    if math.abs(math.log(a.beta))~=math.abs(math.log(b.beta))then return math.abs(math.log(a.beta))<math.abs(math.log(b.beta))end
    if a.shift~=b.shift then return a.shift<b.shift end;return a.beta<b.beta
  end)
  for i,c in ipairs(candidates)do c.id=i end
  local K=cfg.candidate_count
  if candidates[2] and candidates[2].coarse_score-candidates[1].coarse_score<cfg.candidate_near then K=cfg.candidate_expanded end
  local chosen={};local near_unresolved={}
  local function distinct(c,list)
    for _,v in ipairs(list)do if not M.distinct(c,v,cfg.candidate_separation)then return false end end;return true
  end
  for _,c in ipairs(candidates)do
    if #chosen<K and distinct(c,chosen)then chosen[#chosen+1]=c end
  end
  if baseline and distinct(baseline,chosen)then chosen[#chosen+1]=baseline end
  for _,c in ipairs(candidates)do
    if c.coarse_score-candidates[1].coarse_score<=cfg.candidate_near and distinct(c,chosen)then near_unresolved[#near_unresolved+1]=c end
  end
  return {shortlist=chosen,coarse=candidates,grid_count=count,coarse_complete=true,
    heuristic_pruning_used=#chosen<#candidates,unresolved=near_unresolved,expanded=K>cfg.candidate_count,baseline_available=baseline~=nil}
end
return M
