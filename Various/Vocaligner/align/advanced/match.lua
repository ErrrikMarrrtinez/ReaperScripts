-- @noindex
local import=...;local U=import('align/util');local F=import('align/advanced/features');local Phrases=import('align/advanced/phrases')
local Candidates=import('align/advanced/candidates');local Solver=import('align/advanced/solver');local Confidence=import('align/advanced/confidence');local Constraints=import('align/advanced/constraints');local M={}
local INF=math.huge
local function scoped(budget,job,first,last)
  return budget:scope(job and job:scope(first,last)or nil)
end
local function boundaries(result,ref,dub,phrase,cfg)
  local fine,hard=0,0
  for _,p in ipairs(result.path)do if p.supported then
    local u=dub.frames[p.i].t;local v=ref.frames[p.j].t;local shift=(ref.pos-dub.pos)+(v-u)
    local guide=(dub.pos-ref.pos)+phrase.u0+result.candidate.shift+result.candidate.beta*(u-phrase.u0)
    if math.abs(v-guide)>=result.half_band-.005 then fine=fine+1 end
    if math.abs(shift)>=cfg.search_s-.005 then hard=hard+1 end
  end end
  return fine>0,hard>0
end
local function one(ref,dub,phrase,candidate,cfg,budget,constraints,forbidden)
  local function run(band,macro,first,last)
    local pass=scoped(budget,budget.job,first,last)
    local result,why=Solver.run(ref,dub,phrase,candidate,cfg,pass,{half_band=band,macro=macro,constraints=constraints,forbidden=forbidden})
    if result then Confidence.measure(result,ref,dub,phrase,cfg)end
    return result,why
  end
  local result,err=run(cfg.fine_band,false,0,.5)
  local hit,hard=result and boundaries(result,ref,dub,phrase,cfg) or false,false
  if result then hit,hard=boundaries(result,ref,dub,phrase,cfg)end
  if not result or hit then
    budget.retries=budget.retries+1;result,err=run(cfg.expanded_band,false,.5,.75)
    if result then hit,hard=boundaries(result,ref,dub,phrase,cfg)end
  end
  if not result or not Confidence.eligible(result,cfg)then
    budget.retries=budget.retries+1
    local retry,why=run(cfg.expanded_band,true,.75,1)
    if retry and (not result or retry.score<result.score)then result,err=retry,nil;hit,hard=boundaries(result,ref,dub,phrase,cfg)
    elseif not result then err=why end
  end
  if result then result.search_incomplete=hit or hard;result.hard_boundary=hard;result.fine_boundary=hit end
  budget:checkpoint(1,'Candidate compared')
  return result,err
end
local function chain(units,ref,dub,cfg)
  local prefix={[0]=0};local bg={[0]=0}
  for i,f in ipairs(ref.frames)do prefix[i]=prefix[i-1]+f.mass*f.event;bg[i]=bg[i-1]+f.mass*f.background end
  local not_quiet={[0]=0}
  for i,f in ipairs(dub.frames)do not_quiet[i]=not_quiet[i-1]+((f.missing or f.background<.80)and 1 or 0)end
  local nodes={};local total_mass=0
  for i,u in ipairs(units)do
    total_mass=total_mass+u.phrase.mass;nodes[i]={}
    if not u.search_incomplete then for _,r in ipairs(u.results)do
      if r.eligible and not r.search_incomplete then nodes[i][#nodes[i]+1]={result=r,cost=r.raw_cost,
        a=r.start_project,b=r.end_project,beta=r.candidate.beta}end
    end end
    nodes[i][#nodes[i]+1]={unmatched=true,cost=.75*u.phrase.mass,a=dub.pos+u.phrase.u0,b=dub.pos+u.phrase.u1,beta=1}
  end
  local function edge(a,b,index)
    if b.a<=a.b+1e-9 then return INF end
    local gap=units[index].phrase.u0-units[index-1].phrase.u1
    local target=b.a-a.b;local ratio=math.max(cfg.max_ratio,cfg.shoulder_ratio)
    if gap<=0 or target<gap/ratio-1e-6 or target>gap*ratio+1e-6 then return INF end
    local cost=.05*math.min(units[index-1].phrase.mass,units[index].phrase.mass)*math.min(4,math.log(b.beta/a.beta)^2)
    if not a.unmatched and not b.unmatched then
      local lo=U.lower(ref.frames,a.b-ref.pos+1e-8);local hi=U.lower(ref.frames,b.a-ref.pos-1e-8)-1
      local da=U.lower(dub.frames,units[index-1].phrase.u1+1e-8);local db=U.lower(dub.frames,units[index].phrase.u0-1e-8)-1
      local silent_context=cfg.sparse_guide_context and db>=da and not_quiet[db]==not_quiet[da-1]
      -- A verified silent query interval is where sparse backing vocals omit
      -- Guide phrases by design. Charging those Guide events can otherwise make
      -- a perfect second backing phrase costlier than leaving it unmatched.
      -- Internal active gaps and unknown/missing query context retain their cost.
      if lo<=hi then cost=cost+(silent_context and 0 or .80)*(prefix[hi]-prefix[lo-1])+.05*(bg[hi]-bg[lo-1])end
    end
    return cost
  end
  for i,row in ipairs(nodes)do for j,node in ipairs(row)do
    node.fwd=i==1 and node.cost or INF;node.prev=nil
    if i>1 then for k,p in ipairs(nodes[i-1])do local cost=p.fwd+edge(p,node,i)+node.cost
      if cost<node.fwd then node.fwd=cost;node.prev=k end
    end end
  end end
  if #nodes==0 then return {},nil,total_mass end
  local best,index=INF,nil
  for j,n in ipairs(nodes[#nodes])do if n.fwd<best then best,index=n.fwd,j end end
  if not index then return {},nodes,total_mass end
  local selected={}
  for i=#nodes,1,-1 do selected[i]=nodes[i][index];index=selected[i].prev end
  for i=#nodes,1,-1 do for _,node in ipairs(nodes[i])do
    node.bwd=i==#nodes and node.cost or INF
    if i<#nodes then for _,nextn in ipairs(nodes[i+1])do node.bwd=math.min(node.bwd,node.cost+edge(node,nextn,i+1)+nextn.bwd)end end
    node.forced_cost=node.fwd+node.bwd-node.cost
  end end
  for i,n in ipairs(selected)do if n.result then
    local second=INF
    for _,alt in ipairs(nodes[i])do if alt.result and alt~=n and Confidence.distinct(n.result,alt.result,cfg)then second=math.min(second,alt.forced_cost)end end
    n.result.margin=second<INF and (second-best)/math.max(1e-12,total_mass) or nil
    n.result.margin_status=second<INF and 'distinct_competitor' or 'declared_search_exhausted_no_competitor'
  end end
  return selected,nodes,total_mass,best
end
local function replay_window(ref,dub,phrase,result,event,cfg,budget,constraints)
  local radius=cfg.local_replay_s*.5
  local first=math.max(phrase.first,U.lower(dub.frames,event.u-radius))
  local last=math.min(phrase.last,U.lower(dub.frames,event.u+radius)-1)
  local p={id=phrase.id,first=first,last=last,u0=dub.frames[first].t,u1=dub.frames[last].t,
    left=dub.frames[first].left,right=dub.frames[last].right,mass=0,content_mass=0}
  local entry={dub_s=event.u,start_s=p.left,end_s=p.right,scope='local_window'}
  for i=first,last do p.mass=p.mass+dub.frames[i].mass;p.content_mass=p.content_mass+dub.frames[i].mass*dub.frames[i].event end
  local function guide(u)
    local obs=result.observations;local left=obs[1]
    if u<=left.u then return left.guide_project_s+u-left.u end
    for k=2,#obs do local right=obs[k]
      if right.u>=u then return left.guide_project_s+(right.guide_project_s-left.guide_project_s)*(u-left.u)/(right.u-left.u)end
      left=right
    end
    return left.guide_project_s+u-left.u
  end
  local a,b=guide(p.u0),guide(p.u1);local beta=(b-a)/math.max(1e-12,p.u1-p.u0)
  if beta<=0 then entry.status='unsupported_window';return false,entry end
  local candidate={id='local-'..tostring(event.i),shift=a-dub.pos-p.u0,beta=beta,start_project=a,end_project=b}
  local base,why=one(ref,dub,p,candidate,cfg,scoped(budget,budget.job,0,.5),constraints)
  if not base or base.search_incomplete or not Confidence.eligible(base,cfg)then entry.status='unsupported_window';entry.code=why and why.code;return false,entry end
  local alt,err=one(ref,dub,p,candidate,cfg,scoped(budget,budget.job,.5,1),constraints,
    {dub_s=event.u,dub_radius=.02,guide_project_s=event.guide_project_s,ref_radius=cfg.distinct_s})
  if not alt then entry.status='no_reachable_alternative';entry.code=err and err.code;return true,entry end
  entry.margin=alt.score-base.score
  if alt.search_incomplete and Confidence.eligible(alt,cfg)then entry.status='search_incomplete';return false,entry end
  if Confidence.eligible(alt,cfg) and entry.margin<cfg.margin_min then
    local center=false;for _,o in ipairs(alt.observations)do if o.i==event.i then center=true;break end end
    if not center or Confidence.distinct(base,alt,cfg)then entry.status='local_ambiguity';return false,entry end
  end
  entry.status='tested';return true,entry
end
function M.run(ref,dub,cfg,constraints,job,budget)
  local ok,why=F.validate(ref,cfg);if not ok then return nil,U.error('no_usable_evidence',why,'features')end
  ok,why=F.validate(dub,cfg);if not ok then return nil,U.error('no_usable_evidence',why,'features')end
  budget=budget or U.budget(cfg,job)
  if budget.native_solver and budget.native_solver.fn then budget.native_solver:begin_match(ref,dub,cfg,budget)end
  -- Candidate corridors overlap heavily. Acoustic pair costs depend only on
  -- these immutable features/settings, not on the candidate or replay mask.
  -- Masks are checked before lookup in Solver; the cache has a separate cap.
  local pair_cache={rows={},count=0,hits=0,limit=math.floor((cfg.max_pair_cache_bytes or 64*1024*1024)/160)}
  budget.pair_cache=pair_cache
  local regions,err=Constraints.validate(constraints,dub.snapshot or {pos=dub.pos,len=dub.len,rate=1,offset=0,markers={}},
    ref.snapshot or {pos=ref.pos,len=ref.len},cfg)
  if not regions then return nil,err end
  local phrases=Phrases.find(dub,regions,job);local coarse_ref=F.coarse(ref,nil,nil,4,job)
  local units={};local count=0
  for i,p in ipairs(phrases)do
    local phase=job and job:scope(.02+.78*(i-1)/#phrases,.02+.78*i/#phrases)
    budget.detail={phase='coarse',phrase=i,phrases=#phrases}
    local candidates=Candidates.generate(ref,dub,p,cfg,scoped(budget,phase,0,.15),coarse_ref)
    local unit={phrase=p,candidates=candidates,results={},variants={},failed={},search_incomplete=#candidates.unresolved>0};units[i]=unit
    for k,c in ipairs(candidates.shortlist)do
      budget.detail={phase='candidate',phrase=i,phrases=#phrases,candidate=k,candidates=#candidates.shortlist}
      count=count+1;if count>cfg.max_candidates_total then U.fail('work_budget_exceeded','Candidate count cap reached','match')end
      local result,error=one(ref,dub,p,c,cfg,scoped(budget,phase,.15+.85*(k-1)/#candidates.shortlist,.15+.85*k/#candidates.shortlist),regions)
      if result then
        result.eligible,result.rejection_reasons=Confidence.eligible(result,cfg)
        unit.variants[#unit.variants+1]=result
        local duplicate
        for k,old in ipairs(unit.results)do if not Confidence.distinct(old,result,cfg)then duplicate=k;break end end
        if duplicate then if result.score<unit.results[duplicate].score then unit.results[duplicate]=result end
        else unit.results[#unit.results+1]=result end
      else unit.failed[#unit.failed+1]={candidate=c.id,code=error and error.code or 'no_reachable_path'}end
      U.checkpoint(job,nil,'Compared phrase '..i..' / '..#phrases)
    end
    table.sort(unit.results,function(a,b)if a.score~=b.score then return a.score<b.score end;return a.candidate.id<b.candidate.id end)
  end
  local selected,nodes,total_mass,chain_cost=chain(units,ref,dub,cfg)
  local out={schema_version=1,engine_id='advanced_v1',engine_version=cfg.algorithm_version,direction='dub_local_to_guide_project',
    baseline_id=dub.baseline_id,guide_baseline_id=ref.baseline_id,segments={},unmatched={},phrases=units,constraints=regions,
    diagnostics={candidate_count=count,heuristic_pruning_used=false,chain_cost=chain_cost,query_mass=total_mass},status='no_match'}
  local accepted,ambiguous,total_content,accepted_content=0,0,0,0
  for _,f in ipairs(dub.frames)do total_content=total_content+f.mass*f.event end
  for i,unit in ipairs(units)do
    out.diagnostics.heuristic_pruning_used=out.diagnostics.heuristic_pruning_used or unit.candidates.heuristic_pruning_used
    local node=selected[i];local result=node and node.result;local status='unmatched';local reason='no_usable_evidence'
    local local_islands,local_evidence
    if unit.search_incomplete then status='ambiguous';reason='search_incomplete'
    elseif result then
      local sole=result.margin==nil
      local eligible=Confidence.eligible(result,cfg,sole)
      if not eligible then reason=sole and 'sole_candidate_support' or 'insufficient_support'
      elseif not sole and result.margin<cfg.margin_min then
        status='ambiguous';reason='ambiguous_phrase'
        local_islands,local_evidence=Confidence.consensus(result,unit.variants,dub,unit.phrase,cfg)
        if #local_islands>0 then
          local events={};for _,s in ipairs(local_islands)do for _,o in ipairs(s.observations)do
            if o.onset>=.65 and o.reliability>=.65 and (#events==0 or o.u-events[#events].u>=.12)then events[#events+1]=o end
          end end
          if #events==0 then for _,s in ipairs(local_islands)do events[#events+1]=s.observations[math.ceil(#s.observations/2)]end end
          local chosen={};for k=1,math.min(3,#events)do chosen[#chosen+1]=events[math.floor((k-.5)*#events/math.min(3,#events))+1]end
          local blocked={};result.local_alternatives={}
          for k,event in ipairs(chosen)do
            budget.detail={phase='local_ambiguity',phrase=i,phrases=#units,event=k,events=#chosen}
            local progress=.80+.19*(i-1)/#units;local span=.19/#units
            local safe,entry=replay_window(ref,dub,unit.phrase,result,event,cfg,scoped(budget,job,progress+span*(k-1)/#chosen,progress+span*k/#chosen),regions)
            result.local_alternatives[#result.local_alternatives+1]=entry
            if not safe then blocked[#blocked+1]={start_s=entry.start_s,end_s=entry.end_s}end
          end
          local_islands,local_evidence=Confidence.consensus(result,unit.variants,dub,unit.phrase,cfg,blocked)
          if #local_islands>0 then status='partial';reason='local_consensus'end
        end
      else
        status='accepted';result.local_alternatives={}
        -- Bounded, explicitly charged replay at up to three separated events.
        local events={}
        for _,o in ipairs(result.observations)do
          if o.onset>=.65 and o.reliability>=.65 and (#events==0 or o.u-events[#events].u>=.12)then events[#events+1]=o end
        end
        if #events==0 and #result.observations>0 then events={result.observations[math.ceil(#result.observations/2)]}end
        local chosen={};for k=1,math.min(3,#events)do chosen[#chosen+1]=events[math.floor((k-.5)*#events/math.min(3,#events))+1]end
        for k,event in ipairs(chosen)do
          budget.detail={phase='ambiguity',phrase=i,phrases=#units,event=k,events=#chosen}
          local progress=.80+.19*(i-1)/#units;local span=.19/#units
          local alt,replay_error=one(ref,dub,unit.phrase,result.candidate,cfg,scoped(budget,job,progress+span*(k-1)/#chosen,progress+span*k/#chosen),regions,
            {dub_s=event.u,dub_radius=.02,guide_project_s=event.guide_project_s,ref_radius=cfg.distinct_s})
          local entry={dub_s=event.u,status=alt and 'tested' or 'no_reachable_alternative',code=replay_error and replay_error.code}
          if alt and Confidence.eligible(alt,cfg) and Confidence.distinct(result,alt,cfg)then
            entry.margin=alt.score-result.score
            if alt.search_incomplete then status='ambiguous';reason='search_incomplete'
            elseif entry.margin<cfg.margin_min then status='ambiguous';reason='local_ambiguity' end
          end
          result.local_alternatives[#result.local_alternatives+1]=entry
        end
      end
    end
    unit.selected=result;unit.status=status;unit.reason=status~='accepted' and reason or nil
    if status=='accepted'or status=='partial'then
      local islands=status=='partial'and local_islands or Confidence.islands(result,dub,unit.phrase)
      for _,island in ipairs(islands)do island.evidence=result.evidence;island.margin=result.margin;island.margin_status=result.margin_status;out.segments[#out.segments+1]=island end
      accepted=accepted+1;accepted_content=accepted_content+(status=='partial'and local_evidence.content_mass or result.evidence.coverage*result.evidence.content_mass)
      if status=='partial'then
        ambiguous=ambiguous+1;unit.local_evidence=local_evidence
        local first
        for k=unit.phrase.first,unit.phrase.last+1 do
          local included=false
          for _,s in ipairs(islands)do if k>=s.first and k<=s.last then included=true;break end end
          if k<=unit.phrase.last and not included then first=first or k
          elseif first then out.unmatched[#out.unmatched+1]={start_s=dub.frames[first].left,end_s=dub.frames[k-1].right,status='ambiguous',reason='local_disagreement'};first=nil end
        end
      end
      for _,g in ipairs(result.gaps)do if g.side=='dub'then out.unmatched[#out.unmatched+1]={start_s=dub.frames[g.first].left,end_s=dub.frames[g.last].right,status='unmatched',reason='dub_extra',macro=g.macro}end end
    else
      if status=='ambiguous'then ambiguous=ambiguous+1 end
      out.unmatched[#out.unmatched+1]={start_s=unit.phrase.left,end_s=unit.phrase.right,status=status,reason=reason}
    end
  end
  -- Variants retain evidence only while checking consensus; do not duplicate
  -- every DP path in the retained correspondence or diagnostic export.
  for _,unit in ipairs(units)do unit.variant_count=#unit.variants;unit.variants=nil end
  out.diagnostics.coverage=total_content>0 and accepted_content/total_content or 0
  out.diagnostics.content_duration=total_content*.01;out.diagnostics.accepted_phrases=accepted;out.diagnostics.ambiguous_phrases=ambiguous
  out.diagnostics.cells=budget.cells;out.diagnostics.states=budget.states;out.diagnostics.coarse_work=budget.coarse
  out.diagnostics.traceback_bytes=budget.trace_peak;out.diagnostics.retries=budget.retries
  out.diagnostics.pair_cache_entries=pair_cache.count;out.diagnostics.pair_cache_hits=pair_cache.hits
  if budget.native_solver and budget.native_solver.fn then
    out.diagnostics.backend='EEL';out.diagnostics.native_bytes=budget.native_bytes
    out.diagnostics.pair_cache_entries=budget.native_solver:get('cache_entries');out.diagnostics.pair_cache_hits=budget.native_solver:get('cache_hits')
  else out.diagnostics.backend='Lua'end
  if accepted>0 then out.status=accepted==#units and out.diagnostics.coverage>.98 and #out.unmatched==0 and 'matched' or 'partial'
  elseif ambiguous>0 then out.status='ambiguous' end
  U.checkpoint(job,1,'Matching complete')
  budget.pair_cache=nil
  return out
end
M.chain=chain
return M
