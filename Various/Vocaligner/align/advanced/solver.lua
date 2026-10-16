-- @noindex
local import=...;local U=import('align/util');local Distance=import('align/advanced/distance');local Constraints=import('align/advanced/constraints');local Phrases=import('align/advanced/phrases');local M={}
local INF=math.huge;local START=254
local function quantize(v,cfg)
  if not U.finite(v) or v<0 then return INF end
  local n=math.floor(v/cfg.quantum+.5)
  if n>=9007199254740992 then U.fail('work_budget_exceeded','DP integer score overflow','match')end
  return n
end
local function better(c,g,d,bc,bg,bd)
  return c<bc or c==bc and (g<bg or g==bg and d<bd)
end
M.quantize=quantize
M.better=better
-- Query-oriented semi-global DP. Costs use rolling rows; traceback is packed
-- bytes (43 regular states; 47 bytes/cell including optional macro edge IDs).
function M.run(ref,dub,phrase,candidate,cfg,budget,options)
  options=options or {};cfg.weights=cfg.weights or Distance.weights(cfg)
  budget=budget or U.budget(cfg)
  local first,last=phrase.first,phrase.last;local N=last-first+1;local frames,rf=dub.frames,ref.frames
  local G=cfg.max_gap;local S=3+2*G+(options.macro and 2 or 0);local bytes=S+(options.macro and 2 or 0)
  local D0,R0,DM,RM=3,3+G,4+2*G,5+2*G
  local limits=Constraints.compile(options.constraints,dub,ref,first,last)
  local dmax,rmax={},{}
  for i=first,last do
    dmax[i]=0
    for length=1,math.min(G,i-first+1)do
      if not limits.gap_allowed('dub',i-length+1,i,cfg)then break end
      dmax[i]=length
    end
  end
  for j=1,#rf do
    rmax[j]=0
    for length=1,math.min(G,j)do
      if not limits.gap_allowed('ref',j-length+1,j,cfg)then break end
      rmax[j]=length
    end
  end
  local half=options.half_band or cfg.fine_band;local region={};local cells=0;local max_width=0
  local A=0;for i=first,last do A=A+frames[i].mass end
  if N<1 or A<=0 then return nil,U.error('no_reachable_path','Empty query','match')end
  local shift=candidate.shift or candidate.start_project-dub.pos-frames[first].t
  local guide_start=(dub.pos-ref.pos)+frames[first].t+shift
  local beta=candidate.beta or 1;local guide_end=guide_start+beta*(frames[last].t-frames[first].t)
  local reference_start=math.max(0,guide_start-half)
  local reference_end=math.min(ref.len,guide_end+half)
  local evaluated=0
  for i=1,N do
    local f=frames[first+i-1];local x=(dub.pos-ref.pos)+f.t;local guide=guide_start+beta*(f.t-frames[first].t)
    local lo=math.max(reference_start,x-cfg.search_s,guide-half)
    local hi=math.min(reference_end,x+cfg.search_s,guide+half)
    local a=U.lower(rf,lo-1e-10);local b=U.lower(rf,hi+1e-10)-1
    a=math.max(1,a);b=math.min(#rf,b)
    region[i]={lo=a,hi=b,guide=guide};cells=cells+math.max(0,b-a+1);max_width=math.max(max_width,b-a+1)
    for j=a,b do evaluated=evaluated+3+dmax[first+i-1]+rmax[j]+(options.macro and 2 or 0)end
  end
  local payload=cells*bytes
  budget:trace(payload+N*64+max_width*bytes*2)
  if budget.states+evaluated>cfg.max_states then U.fail('work_budget_exceeded','Not enough remaining state budget for this candidate','match')end
  local costs={};local checks=0;local pending_cells,pending_states=0,0
  local shared_pairs=not options.cost and budget.pair_cache
  local function in_region(i,j)
    local row=region[i]
    if not row or j<row.lo or j>row.hi then return false end
    local ai=first+i-1
    if limits.pair_forbidden(ai,j)then return false end
    local forbidden=options.forbidden
    if forbidden and math.abs(frames[ai].t-forbidden.dub_s)<=forbidden.dub_radius and math.abs(ref.pos+rf[j].t-forbidden.guide_project_s)<=forbidden.ref_radius then return false end
    return true
  end
  local function cost(i,j)
    if not in_region(i,j)then return INF,0,false end
    local row=costs[i];local cached=row and row[j]
    if cached then return cached[1],cached[2],cached[3] end
    local c,q,support;local value
    local ai=first+i-1;local shared=shared_pairs
    local known=shared and shared.rows[ai]and shared.rows[ai][j]
    if known then c,q,support=known[1],known[2],known[3];value=known;shared.hits=shared.hits+1
    else
      if options.cost then c,q,support=options.cost(ai,j)else c,q,support=Distance.at(dub,ref,ai,j,cfg)end
      if shared and shared.count<shared.limit then
        local memo=shared.rows[ai];if not memo then memo={};shared.rows[ai]=memo end
        value={c,q,support};memo[j]=value;shared.count=shared.count+1
      end
    end
    if not U.finite(c)then c=INF end
    if row then row[j]=value or {c,q,support}end
    return c,q or 0,support or false
  end
  local function gap_price(side,index)
    local f=side=='dub' and frames[index] or rf[index]
    return f.mass*(cfg.gap_floor+cfg.gap_active*f.event+cfg.gap_onset*f.onset)
  end
  local dp,rp=limits.dub,limits.ref
  local qdg,qrg,qdo,qro={},{},{},{}
  for i,f in ipairs(frames)do dp.gap[i]=dp.gap[i-1]+gap_price('dub',i)end
  for i,f in ipairs(rf)do rp.gap[i]=rp.gap[i-1]+gap_price('ref',i)end
  for i in ipairs(frames)do local price=gap_price('dub',i);qdg[i]=quantize(price,cfg);qdo[i]=quantize(cfg.gap_open+price,cfg)end
  for i in ipairs(rf)do local price=gap_price('ref',i);qrg[i]=quantize(price,cfg);qro[i]=quantize(cfg.gap_open+price,cfg)end
  local dland,rland
  if options.macro then dland=Phrases.landmarks(frames,first,last);rland=Phrases.landmarks(rf,math.max(1,U.lower(rf,reference_start)),math.min(#rf,U.lower(rf,reference_end)))end
  local function macro_boundary(i,j)
    local c,q=cost(i,j)
    if q<.65 or c>.30 then return false end
    local before=cost(i-1,j-1);local after=cost(i+1,j+1)
    return (before+c+after)/3<=.40
  end
  local function slope(state,i,j)
    local di=state==3 and 2 or 1;local dj=state==2 and 2 or 1
    if i-di+1<1 or j-dj+1<1 then return beta end
    local am,bm=0,0
    for k=i-di+1,i do am=am+frames[first+k-1].mass end
    for k=j-dj+1,j do bm=bm+rf[k].mass end
    return bm/am
  end
  local uniform_d,uniform_r={},{}
  for i=3,N do uniform_d[i]=frames[first+i-1].mass==1 and frames[first+i-2].mass==1 and frames[first+i-3].mass==1 end
  for j=3,#rf do uniform_r[j]=rf[j].mass==1 and rf[j-1].mass==1 and rf[j-2].mass==1 end
  local slopes={1,2,.5};local transitions={};local priors={}
  for state=1,3 do
    local mass=state==3 and 2 or 1;local sigma=slopes[state];transitions[state]={}
    priors[state]=.025*mass*math.min(4,math.log(sigma/beta)^2)
    for ps=1,3 do transitions[state][ps]=.020*mass*math.min(4,math.log(sigma/slopes[ps])^2)end
  end
  local function edge(i,j,state)
    local a,b=frames[first+i-1],rf[j];local c=cost(i,j)
    if c==INF then return nil end
    local offset=dub.pos-ref.pos
    local am,bm,ac,disp=a.mass,b.mass,a.mass*c,math.floor(math.abs(offset+(a.t-b.t))/.00001+.5)
    if state==2 then
      if j<2 then return nil end
      local prev=rf[j-1];local cc=cost(i,j-1);if cc==INF then return nil end
      bm=bm+prev.mass;ac=a.mass*(prev.mass*cc+b.mass*c)/bm
      disp=math.floor((math.abs(offset+(a.t-prev.t))*prev.mass+math.abs(offset+(a.t-b.t))*b.mass)/bm/.00001+.5)
    elseif state==3 then
      if i<2 then return nil end
      local prev=frames[first+i-2];local cc=cost(i-1,j);if cc==INF then return nil end
      am=am+prev.mass;ac=ac+prev.mass*cc
      disp=disp+math.floor(math.abs(offset+(prev.t-b.t))/.00001+.5)
    end
    local sigma=bm/am
    local prior=(uniform_d[i]and uniform_r[j]and priors[state]or .025*am*math.min(4,math.log(sigma/beta)^2))+.018*am*math.abs(-offset+(b.t-a.t))/cfg.search_s
    return ac,am,sigma,prior,disp
  end
  local trace,history={},{};local prev,prev2
  local function read(row,j,state)
    if not row or j<row.lo or j>row.hi then return INF,0,0 end
    local k=(j-row.lo)*S+state
    return row.c[k] or INF,row.g[k] or 0,row.d[k] or 0
  end
  local function mread(row,j,state)
    if not row or j<row.lo or j>row.hi then return INF,0,0 end
    local k=(j-row.lo)*3+state;return row.c[k] or INF,row.g[k] or 0,row.d[k] or 0
  end
  -- Every regular gap predecessor has the same closing price. Its exact
  -- lexicographic minimum can be cached once, instead of scanning forty gap
  -- states again for each of the three match transitions in the next cells.
  local function gapread(row,j,macro)
    if not row or j<row.lo or j>row.hi then return INF,0,0,0 end
    local k=j-row.lo+1
    if macro then return row.mc[k]or INF,row.mg[k]or 0,row.md[k]or 0,row.mp[k]or 0 end
    return row.gc[k]or INF,row.gg[k]or 0,row.gd[k]or 0,row.gp[k]or 0
  end
  local pred={}
  local native=budget.native_solver
  if native and native.fn and not options.disable_native then
    trace,prev=native:run({ref=ref,dub=dub,phrase=phrase,candidate=candidate,cfg=cfg,budget=budget,options=options,
      first=first,N=N,S=S,bytes=bytes,region=region,max_width=max_width,evaluated=evaluated,A=A,beta=beta,guide_start=guide_start,
      limits=limits,dmax=dmax,rmax=rmax,qdg=qdg,qdo=qdo,qrg=qrg,qro=qro,dland=dland,rland=rland,dp=dp,rp=rp,quantize=quantize})
  else
  for i=1,N do
    local bounds=region[i];local row={lo=bounds.lo,hi=bounds.hi,c={},g={},d={},gc={},gg={},gd={},gp={},mc={},mg={},md={},mp={}};local packed={}
    costs[i]={};if i>2 then costs[i-2]=nil end
    for j=row.lo,row.hi do
      for s=1,bytes do pred[s]=0 end
      local base=(j-row.lo)*S
      local function put(state,c,g,d,p)
        if c<INF then
          if c>=9007199254740992 then U.fail('work_budget_exceeded','DP integer sum overflow','match')end
          row.c[base+state]=c;row.g[base+state]=g;row.d[base+state]=d;pred[state]=p
        end
      end
      for state=1,3 do
        local di,dj=state==3 and 2 or 1,state==2 and 2 or 1
        local pi,pj=i-di,j-dj
        local acoustic,mass,sigma,prior,displacement=edge(i,j,state)
        if acoustic then
          local bc,bg,bd,bp=INF,INF,INF,0
          if pi==0 and pj>=0 then
            local start_j=j-dj+1;local distance=math.abs(rf[start_j].t-guide_start)
            if distance<=.08000001 then bc=quantize(acoustic+(prior+.025*A*distance/.080),cfg);bg=0;bd=displacement;bp=START end
          end
          local previous=prev;if di==2 then previous=prev2 end
          for ps=1,3 do
            local pc,pg,pd=read(previous,pj,ps)
            if pc<INF then
              local extra=uniform_d[i]and uniform_r[j]and uniform_d[pi]and uniform_r[pj]and transitions[state][ps]or .020*mass*math.min(4,math.log(sigma/slope(ps,pi,pj))^2)
              local c=pc+quantize(acoustic+(prior+extra),cfg);local g,d=pg,pd+displacement
              if better(c,g,d,bc,bg,bd)then bc,bg,bd,bp=c,g,d,ps end
            end
          end
          local close=quantize(acoustic+(prior+cfg.gap_close),cfg)
          local pc,pg,pd,ps=gapread(previous,pj,false)
          if pc<INF then local c,d=pc+close,pd+displacement
            if better(c,pg,d,bc,bg,bd)then bc,bg,bd,bp=c,pg,d,ps end
          end
          if options.macro then
            pc,pg,pd,ps=gapread(previous,pj,true)
            if pc<INF and macro_boundary(i-di+1,j-dj+1)then local c,d=pc+close,pd+displacement
              if better(c,pg,d,bc,bg,bd)then bc,bg,bd,bp=c,pg,d,ps end
            end
          end
          put(state,bc,bg,bd,bp)
        end
      end
      -- Gap endpoints need geometry, but do not need a paired acoustic cell.
      -- Their entire consumed run must satisfy caps and forbidden-boundary masks.
      for side=1,2 do
        local isdub=side==1;local offset=isdub and D0 or R0;local previous=row;if isdub then previous=prev end
        local pj=isdub and j or j-1;local index=isdub and first+i-1 or j
        for length=1,(isdub and dmax[index]or rmax[index])do
            local bc,bg,bd,bp=INF,INF,INF,0
            if length==1 then
              for ps=1,3 do local pc,pg,pd=read(previous,pj,ps)
                local c=pc+(isdub and qdo[index]or qro[index])
                if better(c,pg+1,pd,bc,bg,bd)then bc,bg,bd,bp=c,pg+1,pd,ps end
              end
            else
              local pc,pg,pd=read(previous,pj,offset+length-1)
              bc=pc+(isdub and qdg[index]or qrg[index]);bg=pg+1;bd=pd;bp=offset+length-1
            end
            put(offset+length,bc,bg,bd,bp)
        end
      end
      if options.macro then
        local function macro(side,land,state)
          local index=side=='dub' and first+i-1 or j
          local incoming=land.incoming[index];if not incoming then return end
          local bc,bg,bd,bp,be=INF,INF,INF,0,0
          for eid,e in ipairs(incoming)do
            local oi,oj=side=='dub' and e.origin-first+1 or i,side=='ref' and e.origin or j
            if limits.gap_allowed(side,e.origin+1,index,cfg,true) and macro_boundary(oi,oj)then
              local prefix=side=='dub' and dp.gap or rp.gap
              local price=quantize(cfg.macro_open+prefix[index]-prefix[e.origin],cfg)
              for ps=1,3 do
                local pc,pg,pd
                if side=='dub'then pc,pg,pd=mread(history[oi],j,ps)else pc,pg,pd=read(row,oj,ps)end
                local c,g=pc+price,pg+index-e.origin
                if better(c,g,pd,bc,bg,bd)then bc,bg,bd,bp,be=c,g,pd,ps,eid end
              end
            end
          end
          put(state,bc,bg,bd,bp);pred[S+(side=='dub' and 1 or 2)]=be
        end
        macro('dub',dland,DM);macro('ref',rland,RM)
      end
      local bc,bg,bd,bp=INF,INF,INF,0
      for side=1,2 do
        local offset=side==1 and D0 or R0
        for length=1,(side==1 and dmax[first+i-1]or rmax[j])do local ps=offset+length;local c,g,d=read(row,j,ps)
          if better(c,g,d,bc,bg,bd)then bc,bg,bd,bp=c,g,d,ps end
        end
      end
      local k=j-row.lo+1;row.gc[k],row.gg[k],row.gd[k],row.gp[k]=bc,bg,bd,bp
      if options.macro then
        bc,bg,bd,bp=INF,INF,INF,0
        for ps=DM,RM do local c,g,d=read(row,j,ps)
          if better(c,g,d,bc,bg,bd)then bc,bg,bd,bp=c,g,d,ps end
        end
        row.mc[k],row.mg[k],row.md[k],row.mp[k]=bc,bg,bd,bp
      end
      packed[#packed+1]=string.char(table.unpack(pred,1,bytes))
      pending_cells=pending_cells+1;pending_states=pending_states+3+dmax[first+i-1]+rmax[j]+(options.macro and 2 or 0);checks=checks+1
      if checks%32==0 then
        budget:add('cells',pending_cells);budget:add('states',pending_states);pending_cells,pending_states=0,0
        budget:checkpoint((i-1)/N,'Fine matching with explicit gaps')
      end
    end
    trace[i]={lo=row.lo,hi=row.hi,bytes=table.concat(packed)}
    if options.macro and dland.origins[first+i-1]then
      local m={lo=row.lo,hi=row.hi,c={},g={},d={}}
      for j=row.lo,row.hi do for s=1,3 do local k=(j-row.lo)*3+s;m.c[k],m.g[k],m.d[k]=read(row,j,s)end end
      history[i]=m
    end
    if options.macro then for origin in pairs(history)do if dland.origins[first+origin-1]<=first+i-1 then history[origin]=nil end end end
    budget:add('cells',pending_cells);budget:add('states',pending_states);pending_cells,pending_states=0,0
    prev2,prev=prev,row;budget:checkpoint(i/N,'Fine matching with explicit gaps')
  end
  end
  local bc,bg,bd,bj,bs=INF,INF,INF,nil,nil
  for j=prev.lo,prev.hi do
    local distance=math.abs(rf[j].t-guide_end)
    if distance<=.08000001 then for state=1,3+G do
      local pc,pg,pd=read(prev,j,state);local c=pc+quantize(.025*A*distance/.080,cfg)
      if better(c,pg,pd,bc,bg,bd)then bc,bg,bd,bj,bs=c,pg,pd,j,state end
    end end
  end
  if not bj or bc==INF then return nil,U.error('no_reachable_path','No complete query path inside the declared corridor','match')end
  local i,j,state=N,bj,bs;local steps={};local path,gaps={},{}
  while i>0 do
    local row=trace[i];if not row or j<row.lo or j>row.hi then return nil,U.error('no_reachable_path','Traceback left the computed corridor','match')end
    local offset=(j-row.lo)*bytes;local ps=row.bytes:byte(offset+state)
    if not ps or ps==0 then return nil,U.error('no_reachable_path','Incomplete traceback','match')end
    if state<=3 then
      local di,dj=state==3 and 2 or 1,state==2 and 2 or 1
      steps[#steps+1]={i=i,j=j,state=state,di=di,dj=dj}
      i,j=i-di,j-dj
    elseif state<=D0+G then
      gaps[#gaps+1]={side='dub',first=first+i-1,last=first+i-1};i=i-1
    elseif state<=R0+G then
      gaps[#gaps+1]={side='ref',first=j,last=j};j=j-1
    else
      local side=state==DM and 'dub' or 'ref';local id=row.bytes:byte(offset+S+(side=='dub' and 1 or 2))
      local index=side=='dub' and first+i-1 or j;local land=side=='dub' and dland or rland
      local e=land.incoming[index] and land.incoming[index][id]
      if not e then return nil,U.error('no_reachable_path','Invalid macro-gap traceback','match')end
      gaps[#gaps+1]={side=side,first=e.origin+1,last=index,macro=true}
      if side=='dub'then i=e.origin-first+1 else j=e.origin end
    end
    if ps==START then if i~=0 then return nil,U.error('no_reachable_path','Traceback discarded a query prefix','match')end;break end
    state=ps
  end
  for k=#steps,1,-1 do
    local step=steps[k];local ai=first+step.i-1;local j=step.j
    local function append(ii,jj,weight)
      local c,q,support
      if options.cost then c,q,support=options.cost(ii,jj)else c,q,support=Distance.at(dub,ref,ii,jj,cfg)end
      path[#path+1]={i=ii,j=jj,dub_s=frames[ii].t,guide_project_s=ref.pos+rf[jj].t,
        cost=c,reliability=q or 0,supported=support==true,mass=weight,step=step.state,phrase_id=phrase.id}
    end
    if step.state==2 then
      local sum=rf[j-1].mass+rf[j].mass
      append(ai,j-1,frames[ai].mass*rf[j-1].mass/sum);append(ai,j,frames[ai].mass*rf[j].mass/sum)
    elseif step.state==3 then append(ai-1,j,frames[ai-1].mass);append(ai,j,frames[ai].mass)
    else append(ai,j,frames[ai].mass)end
  end
  table.sort(gaps,function(a,b)if a.side~=b.side then return a.side<b.side end;return a.first<b.first end)
  local merged={}
  for _,g in ipairs(gaps)do local prev=merged[#merged]
    if prev and prev.side==g.side and prev.last+1==g.first then prev.last=g.last;prev.macro=prev.macro or g.macro
    else merged[#merged+1]=g end
  end
  local boundary=0;for _,p in ipairs(path)do local bounds=region[p.i-first+1]
    if p.j==bounds.lo or p.j==bounds.hi then boundary=boundary+1 end
  end
  return {path=path,gaps=merged,integer_score=bc,raw_cost=bc*cfg.quantum,score=bc*cfg.quantum/A,query_mass=A,
    gap_frames=bg,displacement_ticks=bd,traceback_bytes=payload,cells=cells,states=evaluated,packed_state_slots=cells*S,
    boundary_fraction=boundary/math.max(1,#path),half_band=half,macro_retry=options.macro==true,
    start_project=path[1] and path[1].guide_project_s,end_project=path[#path] and path[#path].guide_project_s,
    candidate=candidate,region_width=max_width,history_policy='landmark M rows, at most 13 origins'}
end
return M
