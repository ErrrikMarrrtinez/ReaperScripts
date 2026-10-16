-- @noindex
local import=...;local U=import('align/util');local M={}
-- All variables/bounds here are displacement in seconds. Absolute project time
-- never enters the linear system. A has box rows followed by neighbor differences.
function M.feasible(p)
  local n=#p.u;local lo,hi={},{}
  if n<2 then return nil,U.error('render_map_invalid','A timing grid needs two endpoints','constraints')end
  for i=1,n do
    if not U.finite(p.lower[i]) or not U.finite(p.upper[i]) or p.lower[i]>p.upper[i] then return nil,U.error('constraints_conflict','Conflicting bounds at '..tostring(p.u[i]),'constraints')end
    if i==1 then lo[i],hi[i]=p.lower[i],p.upper[i]
    else
      if not U.finite(p.dlower[i-1]) or not U.finite(p.dupper[i-1]) or p.dlower[i-1]>p.dupper[i-1] then return nil,U.error('constraints_conflict','Conflicting rate bounds','constraints')end
      lo[i]=math.max(p.lower[i],lo[i-1]+p.dlower[i-1]);hi[i]=math.min(p.upper[i],hi[i-1]+p.dupper[i-1])
      if lo[i]>hi[i]+1e-12 then return nil,U.error('constraints_conflict',string.format('No feasible timing between %.6f and %.6f s',p.u[i-1],p.u[i]),'constraints',{index=i})end
      if lo[i]>hi[i]then lo[i],hi[i]=(lo[i]+hi[i])*.5,(lo[i]+hi[i])*.5 end
    end
  end
  local delta={};delta[n]=U.clamp(0,lo[n],hi[n])
  for i=n-1,1,-1 do
    local a,b=math.max(lo[i],delta[i+1]-p.dupper[i]),math.min(hi[i],delta[i+1]-p.dlower[i])
    if a>b+1e-12 then return nil,U.error('constraints_conflict','Backward feasibility failed','constraints')end
    delta[i]=U.clamp(0,a,b)
  end
  return delta
end
function M.validate(p,delta,tolerance)
  local worst=0;local where
  for i,v in ipairs(delta)do
    if not U.finite(v) then return nil,'Nonfinite displacement' end
    local e=math.max(p.lower[i]-v,v-p.upper[i],0)
    if i>1 then local d=v-delta[i-1];e=math.max(e,p.dlower[i-1]-d,d-p.dupper[i-1])end
    if e>worst then worst,where=e,i end
  end
  if #delta~=#p.u or worst>tolerance then return nil,'Timing constraint residual at '..tostring(where),worst end
  return true,nil,worst
end
local function add_row(q,a,b,c,k,weight)
  q.diag[k-1]=q.diag[k-1]+weight*a*a;q.diag[k]=q.diag[k]+weight*b*b;q.diag[k+1]=q.diag[k+1]+weight*c*c
  q.one[k-1]=q.one[k-1]+weight*a*b;q.one[k]=q.one[k]+weight*b*c;q.two[k-1]=q.two[k-1]+weight*a*c
end
function M.matrix(p,cfg)
  local n=#p.u;local q={diag={},one={},two={},rhs={}}
  for i=1,n do
    if not U.finite(p.u[i])or i>1 and p.u[i]<=p.u[i-1]then return nil,U.error('render_map_invalid','Invalid timing grid','regularize')end
    local w=p.weights[i] or 0;local target=p.target[i] or 0
    if not U.finite(w) or w<0 or not U.finite(target)then return nil,U.error('render_map_invalid','Invalid QP observation','regularize')end
    q.diag[i]=w+cfg.epsilon;q.rhs[i]=w*target;q.one[i]=0;q.two[i]=0
    if i>1 and (not U.finite(p.u[i]) or p.u[i]-p.u[i-1]<1e-6-1e-12)then return nil,U.error('numeric_resolution_unsupported','Mandatory grid knots are less than 1 microsecond apart','regularize')end
  end
  for i=2,n-1 do
    local region=p.region
    if not region or region[i]~=0 and region[i-1]==region[i] and region[i+1]==region[i] then
      local left,right=p.u[i]-p.u[i-1],p.u[i+1]-p.u[i]
      local scale=2*.01^2/(left+right)
      add_row(q,scale/left,-scale*(1/left+1/right),scale/right,i,cfg.lambda)
    end
  end
  return q
end
function M.factor(diag,one,two)
  local f={d={},l1={},l2={}};local maxp,minp=0,math.huge
  for i=1,#diag do
    local l2=i>2 and two[i-2]/f.d[i-2] or 0
    local l1=i>1 and (one[i-1]-(i>2 and l2*f.d[i-2]*f.l1[i-1] or 0))/f.d[i-1] or 0
    local d=diag[i]-(i>1 and l1*l1*f.d[i-1] or 0)-(i>2 and l2*l2*f.d[i-2] or 0)
    if not U.finite(d) or d<=1e-14 then return nil,U.error('numeric_resolution_unsupported','Nonpositive QP factor pivot','regularize')end
    f.d[i],f.l1[i],f.l2[i]=d,l1,l2;maxp=math.max(maxp,d);minp=math.min(minp,d)
  end
  f.pivot_ratio=maxp/minp
  if f.pivot_ratio>1e16 then return nil,U.error('numeric_resolution_unsupported','QP pivot range exceeds the numerical guard','regularize')end
  return f
end
function M.linear_solve(f,b,work,out)
  work,out=work or {},out or {};local n=#b
  for i=1,n do work[i]=b[i]-(i>1 and f.l1[i]*work[i-1] or 0)-(i>2 and f.l2[i]*work[i-2] or 0)end
  for i=n,1,-1 do out[i]=work[i]/f.d[i]-(i<n and f.l1[i+1]*out[i+1] or 0)-(i<n-1 and f.l2[i+2]*out[i+2] or 0)end
  return out
end
local function product(q,x,i)
  return q.diag[i]*x[i]+(i>1 and q.one[i-1]*x[i-1] or 0)+(i<#x and q.one[i]*x[i+1] or 0)
    +(i>2 and q.two[i-2]*x[i-2] or 0)+(i<#x-1 and q.two[i]*x[i+2] or 0)
end
function M.objective(q,x)
  local value=0;for i,v in ipairs(x)do value=value+.5*v*product(q,x,i)-q.rhs[i]*v end;return value
end
local try_polish
-- Nearest point (coordinate-wise clamp) that satisfies every box and
-- neighbor-difference bound: forward reachable intervals, backward clamp.
function M.project(p,x)
  local n=#p.u;local lo,hi={},{}
  for i=1,n do
    if i==1 then lo[i],hi[i]=p.lower[i],p.upper[i]
    else lo[i]=math.max(p.lower[i],lo[i-1]+p.dlower[i-1]);hi[i]=math.min(p.upper[i],hi[i-1]+p.dupper[i-1])end
    if lo[i]>hi[i]+1e-12 then return nil end
    if lo[i]>hi[i]then lo[i],hi[i]=(lo[i]+hi[i])*.5,(lo[i]+hi[i])*.5 end
  end
  local out={};out[n]=U.clamp(U.finite(x[n])and x[n]or 0,lo[n],hi[n])
  for i=n-1,1,-1 do
    local a,b=math.max(lo[i],out[i+1]-p.dupper[i]),math.min(hi[i],out[i+1]-p.dlower[i])
    if a>b+1e-12 then return nil end
    out[i]=U.clamp(U.finite(x[i])and x[i]or 0,a,math.max(a,b))
  end
  return out
end
local function solve_system(p,q,cfg,budget,approximate)
  local delta,err=M.feasible(p);if not delta then return nil,err end
  local n=#p.u;local rho=cfg.rho;local diag,one,two={},{},{}
  local free_factor=M.factor(q.diag,q.one,q.two)
  if free_factor then delta=M.linear_solve(free_factor,q.rhs)end
  local function factorize()
    for i=1,n do
      diag[i]=q.diag[i]+rho*(1+(i>1 and 1 or 0)+(i<n and 1 or 0))
      one[i]=q.one[i]-rho;two[i]=q.two[i]
    end
    return M.factor(diag,one,two)
  end
  local factor;factor,err=factorize();if not factor then return nil,err end
  local zb,zd,db,dd,cb,cd,rhs,work={},{},{},{},{},{},{},{}
  for i=1,n do zb[i]=U.clamp(delta[i],p.lower[i],p.upper[i]);db[i]=0;if i<n then zd[i]=U.clamp(delta[i+1]-delta[i],p.dlower[i],p.dupper[i]);dd[i]=0 end end
  local report={iterations=0,pivot_ratio=factor.pivot_ratio,primal=math.huge,dual=math.huge,variables=n,
    backend='Lua pentadiagonal LDL / ADMM',rho=rho,rho_updates=0,relaxation=1.6}
  for iter=1,cfg.iterations do
    if budget then budget:add('regularize',n)end
    for i=1,n do rhs[i]=q.rhs[i]+rho*(zb[i]-db[i]+(i>1 and zd[i-1]-dd[i-1] or 0)-(i<n and zd[i]-dd[i] or 0))end
    M.linear_solve(factor,rhs,work,delta)
    local primal,norma,normz=0,0,0
    for i=1,n do
      if not U.finite(delta[i])then return nil,U.error('solver_not_converged','Nonfinite QP iterate','regularize')end
      local relaxed=1.6*delta[i]-.6*zb[i]
      local nextz=U.clamp(relaxed+db[i],p.lower[i],p.upper[i]);cb[i]=nextz-zb[i];zb[i]=nextz
      local res=delta[i]-nextz;db[i]=db[i]+relaxed-nextz;primal=math.max(primal,math.abs(res));norma=math.max(norma,math.abs(delta[i]));normz=math.max(normz,math.abs(nextz))
      if i<n then
        local d=delta[i+1]-delta[i];relaxed=1.6*d-.6*zd[i];nextz=U.clamp(relaxed+dd[i],p.dlower[i],p.dupper[i]);cd[i]=nextz-zd[i];zd[i]=nextz
        res=d-nextz;dd[i]=dd[i]+relaxed-nextz;primal=math.max(primal,math.abs(res));norma=math.max(norma,math.abs(d));normz=math.max(normz,math.abs(nextz))
      end
    end
    local dual,normq,normb,normd=0,0,0,0
    for i=1,n do
      dual=math.max(dual,math.abs(rho*(cb[i]+(i>1 and cd[i-1] or 0)-(i<n and cd[i] or 0))))
      normq=math.max(normq,math.abs(product(q,delta,i)));normb=math.max(normb,math.abs(q.rhs[i]))
      normd=math.max(normd,math.abs(rho*(db[i]+(i>1 and dd[i-1] or 0)-(i<n and dd[i] or 0))))
    end
    report.iterations=iter;report.primal=primal;report.dual=dual
    local pstop=cfg.primal_abs+cfg.residual_rel*math.max(norma,normz)
    local dstop=cfg.dual_abs+cfg.residual_rel*math.max(normq,normb,normd)
    if primal<=pstop and dual<=dstop then
      local ok,why,worst=M.validate(p,delta,cfg.geometry_tolerance)
      if not ok then return nil,U.error('render_map_invalid',why,'regularize')end
      report.max_constraint_error=worst;report.objective=M.objective(q,delta);report.converged=true
      return delta,report
    end
    -- ADMM identifies active bounds before its residual has fully settled.
    -- Solve that equality-constrained problem exactly, then require primal,
    -- stationarity and dual-sign certificates against the ORIGINAL inequalities.
    if iter%50==0 then
      if budget then budget:add('regularize',n*5)end
      local polished,certificate=try_polish(p,q,zb,zd,db,dd,cfg)
      if polished then
        report.polished=true;report.primal=certificate.primal;report.dual=certificate.dual
        report.max_constraint_error=certificate.primal;report.objective=M.objective(q,polished);report.converged=true
        return polished,report
      end
    end
    -- Deterministic residual balancing changes convergence speed, not the QP or
    -- its stopping/geometry tolerances. Re-scale duals to preserve multipliers.
    if iter%25==0 and primal>0 and dual>0 then
      local ratio=math.sqrt(primal/dual);local next_rho=rho
      if ratio>2 or ratio<.5 then next_rho=U.clamp(rho*U.clamp(ratio,.25,4),.001,10000)end
      if next_rho~=rho then
        local scale=rho/next_rho;for i=1,n do db[i]=db[i]*scale;if i<n then dd[i]=dd[i]*scale end end
        rho=next_rho;factor,err=factorize();if not factor then return nil,err end
        report.rho=rho;report.rho_updates=report.rho_updates+1;report.pivot_ratio=factor.pivot_ratio
      end
    end
    if budget then budget:checkpoint(nil,'Solving bounded timing map')end
  end
  report.converged=false
  if approximate then
    -- Guided maps: the last iterate, projected onto the exact constraints and
    -- validated independently, replaces a refusal. Reported as approximate.
    local y=M.project(p,delta)
    local ok,_,worst=y and M.validate(p,y,cfg.geometry_tolerance)
    if ok then report.approximate=true;report.max_constraint_error=worst;report.objective=M.objective(q,y);return y,report end
  end
  return nil,U.error('solver_not_converged','Timing optimizer reached its iteration budget; correction was not applied','regularize',report)
end
-- Exact equalities are eliminated algebraically before ADMM. This preserves the
-- same QP objective and constraints, fixes padding/protection to machine precision,
-- and avoids spending the iteration budget rediscovering a known constant edge.
-- Contiguous equality groups and fixed boxes do not increase the bandwidth.
local function condense(p,q)
  local group,offset,groups={},{},{};local count=0
  for i=1,#p.u do
    if i>1 and p.dlower[i-1]==p.dupper[i-1]then group[i]=count;offset[i]=offset[i-1]+p.dlower[i-1]
    else count=count+1;group[i]=count;offset[i]=0;groups[count]={first=i,last=i,lo=-math.huge,hi=math.huge}end
    local g=groups[count];g.last=i;g.lo=math.max(g.lo,p.lower[i]-offset[i]);g.hi=math.min(g.hi,p.upper[i]-offset[i])
  end
  local gq={diag={},one={},two={},rhs={}}
  for i=1,count do gq.diag[i]=0;gq.one[i]=0;gq.two[i]=0;gq.rhs[i]=0 end
  local function add(matrix,i,j,value)
    if i==j then matrix.diag[i]=matrix.diag[i]+value
    elseif j-i==1 then matrix.one[i]=matrix.one[i]+value
    elseif j-i==2 then matrix.two[i]=matrix.two[i]+value
    else assert(value==0,'Equality condensation changed QP bandwidth')end
  end
  for i=1,#p.u do
    local g=group[i];gq.diag[g]=gq.diag[g]+q.diag[i];gq.rhs[g]=gq.rhs[g]+q.rhs[i]-product(q,offset,i)
    for d=1,2 do if i+d<=#p.u then
      local h=group[i+d];local value=d==1 and q.one[i] or q.two[i]
      add(gq,g,h,value*(g==h and 2 or 1))
    end end
  end
  local free,fixed={},{};local n=0
  for i,g in ipairs(groups)do
    if g.lo>g.hi+1e-12 then return nil,U.error('constraints_conflict','Conflicting exact timing constraints','constraints')end
    if g.hi-g.lo<=1e-12 then fixed[i]=(g.lo+g.hi)*.5 else n=n+1;free[i]=n end
  end
  local rp={u={},lower={},upper={},dlower={},dupper={}};local rq={diag={},one={},two={},rhs={}}
  for g,k in pairs(free)do
    rp.u[k]=p.u[groups[g].first];rp.lower[k]=groups[g].lo;rp.upper[k]=groups[g].hi
    rq.diag[k]=gq.diag[g];rq.one[k]=0;rq.two[k]=0;rq.rhs[k]=gq.rhs[g]
  end
  for g=1,count do for d=1,2 do if g+d<=count then
    local h=g+d;local value=d==1 and gq.one[g] or gq.two[g]
    local a,b=free[g],free[h]
    if a and b then add(rq,a,b,value)
    elseif a then rq.rhs[a]=rq.rhs[a]-value*fixed[h]
    elseif b then rq.rhs[b]=rq.rhs[b]-value*fixed[g]end
  end end end
  for g=1,count-1 do
    local left,right=groups[g].last,groups[g+1].first
    local lo=p.dlower[left]-(offset[right]-offset[left]);local hi=p.dupper[left]-(offset[right]-offset[left])
    local a,b=free[g],free[g+1]
    if a and b then rp.dlower[a]=lo;rp.dupper[a]=hi
    elseif a then rp.lower[a]=math.max(rp.lower[a],fixed[g+1]-hi);rp.upper[a]=math.min(rp.upper[a],fixed[g+1]-lo)
    elseif b then rp.lower[b]=math.max(rp.lower[b],fixed[g]+lo);rp.upper[b]=math.min(rp.upper[b],fixed[g]+hi)
    elseif fixed[g+1]-fixed[g]<lo-1e-12 or fixed[g+1]-fixed[g]>hi+1e-12 then return nil,U.error('constraints_conflict','Fixed timing nodes violate a rate limit','constraints')end
  end
  for i=1,n-1 do if not rp.dlower[i]then
    -- A fixed group separates these variables. This redundant finite interval
    -- imposes no additional restriction beyond their already-intersected boxes.
    rp.dlower[i]=rp.lower[i+1]-rp.upper[i];rp.dupper[i]=rp.upper[i+1]-rp.lower[i]
  end end
  local function expand(values)
    local result={};for i,g in ipairs(group)do result[i]=(fixed[g]or values[free[g]])+offset[i]end;return result
  end
  return {p=rp,q=rq,expand=expand,n=n,groups=count}
end
try_polish=function(p,q,zb,zd,db,dd,cfg)
  local n=#p.u;local a={u=p.u,lower={},upper={},dlower={},dupper={}};local boxes,edges={},{}
  local function active(z,y,lo,hi)
    if lo==hi then return 2 end
    if y< -1e-10 and z==lo then return -1 end
    if y>1e-10 and z==hi then return 1 end
    return 0
  end
  for i=1,n do
    local k=active(zb[i],db[i],p.lower[i],p.upper[i]);boxes[i]=k
    a.lower[i]=k==1 and p.upper[i]or p.lower[i];a.upper[i]=k==-1 and p.lower[i]or p.upper[i]
    if i<n then
      k=active(zd[i],dd[i],p.dlower[i],p.dupper[i]);edges[i]=k
      a.dlower[i]=k==1 and p.dupper[i]or p.dlower[i];a.dupper[i]=k==-1 and p.dlower[i]or p.dupper[i]
    end
  end
  local reduced=condense(a,q);if not reduced then return end
  local values={}
  if reduced.n>0 then
    local f=M.factor(reduced.q.diag,reduced.q.one,reduced.q.two);if not f then return end
    values=M.linear_solve(f,reduced.q.rhs)
  end
  local x=reduced.expand(values);local normx,normq,normb=0,0,0;local residual={}
  for i=1,n do
    if not U.finite(x[i])then return end
    local v=product(q,x,i);residual[i]=v-q.rhs[i]
    normx=math.max(normx,math.abs(x[i]),i>1 and math.abs(x[i]-x[i-1])or 0)
    normq=math.max(normq,math.abs(v));normb=math.max(normb,math.abs(q.rhs[i]))
  end
  local pstop=cfg.primal_abs+cfg.residual_rel*normx
  local feasible,_,primal=M.validate(p,x,pstop);if not feasible then return end
  local dstop=cfg.dual_abs+cfg.residual_rel*math.max(normq,normb)
  local function interval(k)
    if k==2 then return -math.huge,math.huge end
    if k==-1 then return -math.huge,0 end
    if k==1 then return 0,math.huge end
    return 0,0
  end
  -- For a chain, KKT multipliers are a one-dimensional feasible flow:
  -- edge[i] = gradient[i] + box[i] + edge[i-1]. This also covers redundant
  -- active constraints and multiple fixed anchors without a dense KKT solve.
  local lo,hi={[0]=0},{[0]=0}
  for i=1,n do
    local bl,bh=interval(boxes[i]);local el,eh=interval(edges[i]or 0)
    lo[i]=math.max(el,lo[i-1]+residual[i]+bl);hi[i]=math.min(eh,hi[i-1]+residual[i]+bh)
    if lo[i]>hi[i]+dstop then return end
    if lo[i]>hi[i]then local mid=(lo[i]+hi[i])*.5;lo[i]=mid;hi[i]=mid end
  end
  local nexty=0;local dual=0
  for i=n,1,-1 do
    local bl,bh=interval(boxes[i]);local el,eh=interval(edges[i]or 0)
    local low=math.max(lo[i-1],nexty-residual[i]-bh)
    local high=math.min(hi[i-1],nexty-residual[i]-bl)
    if low>high+dstop then return end
    local previous=low>high and (low+high)*.5 or U.clamp(0,low,high)
    local box=nexty-residual[i]-previous
    dual=math.max(dual,bl-box,box-bh,el-nexty,nexty-eh,math.abs(residual[i]+box+previous-nexty))
    nexty=previous
  end
  dual=math.max(dual,math.abs(nexty))
  if dual>dstop then return end
  return x,{primal=primal,dual=dual}
end
local function solve_components(p,q,cfg,budget,approximate)
  local ends={}
  for i=1,#p.u-1 do
    local uncoupled=q.one[i]==0 and (i==1 or q.two[i-1]==0)and q.two[i]==0
    local redundant=p.dlower[i]<=p.lower[i+1]-p.upper[i] and p.dupper[i]>=p.upper[i+1]-p.lower[i]
    if uncoupled and redundant then ends[#ends+1]=i end
  end
  if #ends==0 then return solve_system(p,q,cfg,budget,approximate)end
  ends[#ends+1]=#p.u
  local out={};local first=1
  local report={backend='Lua banded LDL / independent ADMM components',components=#ends,iterations=0,total_iterations=0,
    primal=0,dual=0,pivot_ratio=0,rho_updates=0,polished_components=0,converged=true}
  for _,last in ipairs(ends)do
    local sub={u={},lower={},upper={},dlower={},dupper={}};local matrix={diag={},one={},two={},rhs={}}
    for i=first,last do local k=i-first+1
      sub.u[k]=p.u[i];sub.lower[k]=p.lower[i];sub.upper[k]=p.upper[i]
      if i<last then sub.dlower[k]=p.dlower[i];sub.dupper[k]=p.dupper[i]end
      matrix.diag[k]=q.diag[i];matrix.rhs[k]=q.rhs[i];matrix.one[k]=i<last and q.one[i]or 0;matrix.two[k]=i<last-1 and q.two[i]or 0
    end
    local values,part
    if first==last then values={U.clamp(matrix.rhs[1]/matrix.diag[1],sub.lower[1],sub.upper[1])};part={iterations=0,primal=0,dual=0}
    else values,part=solve_system(sub,matrix,cfg,budget,approximate)end
    if not values then part.component_first=first;part.component_last=last;return nil,part end
    if part.approximate then report.approximate=true;report.converged=false;report.approximate_components=(report.approximate_components or 0)+1 end
    for _,v in ipairs(values)do out[#out+1]=v end
    report.iterations=math.max(report.iterations,part.iterations);report.total_iterations=report.total_iterations+part.iterations
    report.primal=math.max(report.primal,part.primal);report.dual=math.max(report.dual,part.dual)
    report.pivot_ratio=math.max(report.pivot_ratio,part.pivot_ratio or 0);report.rho_updates=report.rho_updates+(part.rho_updates or 0)
    if part.polished then report.polished_components=report.polished_components+1 end
    first=last+1
  end
  return out,report
end
function M.solve(p,cfg,budget)
  local feasible,err=M.feasible(p);if not feasible then return nil,err end
  local q;q,err=M.matrix(p,cfg);if not q then return nil,err end
  local reduced;reduced,err=condense(p,q);if not reduced then return nil,err end
  local values,report
  if reduced.n==0 then values={};report={iterations=0,primal=0,dual=0,converged=true}
  elseif reduced.n==1 then
    local rp,rq=reduced.p,reduced.q
    values={U.clamp(rq.rhs[1]/rq.diag[1],rp.lower[1],rp.upper[1])};report={iterations=0,primal=0,dual=0,converged=true}
  else values,report=solve_components(reduced.p,reduced.q,cfg,budget,p.allow_approximate);if not values then return nil,report end end
  local delta=reduced.expand(values);local ok,why,worst=M.validate(p,delta,cfg.geometry_tolerance)
  if not ok then return nil,U.error('render_map_invalid',why,'regularize')end
  report.original_variables=#p.u;report.variables=reduced.n;report.equality_eliminated=#p.u-reduced.n
  report.max_constraint_error=worst;report.objective=M.objective(q,delta)
  return delta,report
end
return M
