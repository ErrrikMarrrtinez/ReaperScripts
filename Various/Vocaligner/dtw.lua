-- @noindex
local import=...;local DSP=import('dsp');local M={}
local inf=math.huge
local function aggregate(data,factor,job)
  data.scales=data.scales or {}
  if data.scales[factor] then return data.scales[factor] end
  local out={frames={},hop=data.hop*factor,pos=data.pos,len=data.len}
  local first=math.max(1,(data.first or 1)-4);local last=math.min(#data.frames,(data.last or #data.frames)+4)
  if factor==1 then
    for i=first,last do out.frames[#out.frames+1]=data.frames[i];if i%1024==0 then job:checkpoint() end end
    data.scales[factor]=out;return out
  end
  for i=first,last,factor do
    local f={cep={},spec={},chroma={},delta={},energy=0,onset=0,active=false,t=0}
    for k=1,12 do f.cep[k],f.chroma[k]=0,0 end
    for k=1,#data.frames[i].spec do f.spec[k]=0 end;for k=1,6 do f.delta[k]=0 end
    local count=math.min(factor,last-i+1)
    for j=i,i+count-1 do
      local a=data.frames[j];f.t=f.t+a.t;f.energy=f.energy+a.energy;f.onset=math.max(f.onset,a.onset)
      f.active=f.active or a.active
      for k=1,12 do f.cep[k]=f.cep[k]+a.cep[k];f.chroma[k]=f.chroma[k]+a.chroma[k] end
      for k=1,#f.spec do f.spec[k]=f.spec[k]+a.spec[k] end
      for k=1,6 do f.delta[k]=f.delta[k]+a.delta[k] end
    end
    f.t=f.t/count;f.energy=f.energy/count
    for _,key in ipairs({'cep','delta','spec','chroma'}) do for k=1,#f[key] do f[key][k]=f[key][k]/count end end
    for _,key in ipairs({'spec','chroma'}) do local n=0;for _,v in ipairs(f[key]) do n=n+v*v end;n=math.sqrt(n)+1e-12;for k=1,#f[key] do f[key][k]=f[key][k]/n end end
    out.frames[#out.frames+1]=f
    if #out.frames%256==0 then job:checkpoint() end
  end
  data.scales[factor]=out;return out
end
local function interpolate(path,t)
  if t<=path[1].dub then return path[1].ref+t-path[1].dub end
  if t>=path[#path].dub then return path[#path].ref+t-path[#path].dub end
  local lo,hi=1,#path;while hi-lo>1 do local m=(lo+hi)//2;if path[m].dub<=t then lo=m else hi=m end end
  local a,b=path[lo],path[hi];return a.ref+(b.ref-a.ref)*(t-a.dub)/(b.dub-a.dub)
end
M.interpolate=interpolate
local function frame_range(frames,low,high)
  -- Averaged groups have real timestamps. A final group of 1..3 frames is not
  -- on the nominal 40 ms grid; arithmetic rounding used to exclude it entirely.
  local lo,hi=1,#frames+1
  while lo<hi do
    local mid=(lo+hi)//2
    if frames[mid].t<low-1e-9 then lo=mid+1 else hi=mid end
  end
  local first=lo;lo,hi=1,#frames+1
  while lo<hi do
    local mid=(lo+hi)//2
    if frames[mid].t<=high+1e-9 then lo=mid+1 else hi=mid end
  end
  return first,lo-1
end
local function solve(ref,dub,cfg,job,guide,radius,stage)
  local r,d=ref.frames,dub.frames;local n,m=#d,#r
  if n<3 or m<3 then return nil,'Not enough audible frames.' end
  local ref0,dub0=ref.pos,dub.pos;local hop=ref.hop
  local directions,starts={},{};local prev,prev2={},{}
  -- Cover the shorter phrase and permit free prefixes/suffixes in the longer take.
  -- Penalizing those prefixes would pull a trimmed dub towards an unrelated earlier word.
  local dub_is_query=n<=m
  local endpoint,best=nil,inf;local cells=0
  local function rowget(row,j) return row[j] or inf end
  for i=1,n do
    local absdub=dub0+d[i].t
    local center=guide and interpolate(guide,d[i].t) or absdub
    local low=math.max(ref0+r[1].t,absdub-cfg.search_s,center-radius)
    local high=math.min(ref0+r[m].t,absdub+cfg.search_s,center+radius)
    local jmin,jmax=frame_range(r,low-ref0,high-ref0)
    local cur,bytes={},{};starts[i]=jmin
    for j=jmin,jmax do
      local cost=DSP.distance(d[i],r[j],cfg.profile)
      local prior=.018*math.abs(ref0+r[j].t-absdub)/cfg.search_s
      cost=cost+prior
      local v,dir=inf,0
      if (dub_is_query and i==1) or (not dub_is_query and j==1) then v=2*cost;dir=4 end
      local diag=rowget(prev,j-1)+2*cost
      if diag<v then v,dir=diag,1 end
      -- Symmetric compound steps include intermediate cost, preventing skipped attacks.
      if j>1 then
        local x=rowget(prev,j-2)+cost+2*DSP.distance(d[i],r[j-1],cfg.profile)+.11
        if x<v then v,dir=x,2 end
      end
      if i>1 then
        local x=rowget(prev2,j-1)+cost+2*DSP.distance(d[i-1],r[j],cfg.profile)+.11
        if x<v then v,dir=x,3 end
      end
      cur[j]=v;bytes[#bytes+1]=string.char(dir)
      if ((dub_is_query and i==n) or (not dub_is_query and j==m)) and v<inf then
        local score=v
        if score<best then best=score;endpoint={i,j} end
      end
      cells=cells+1
      if cells>cfg.max_cells then return nil,'Search exceeded the memory/work limit. Reduce the search range or capture shorter phrases.' end
      if cells%2048==0 then job:checkpoint(i/n,stage) end
    end
    directions[i]=table.concat(bytes);prev2,prev=prev,cur
    if i%16==0 then job:checkpoint(i/n,stage) end
  end
  if not endpoint then
    return nil,string.format('%s: No reachable alignment within +/- %.2f s. Ref %.3f..%.3f s, dub %.3f..%.3f s.',
      stage,cfg.search_s,ref0+r[1].t,ref0+r[m].t,dub0+d[1].t,dub0+d[n].t)
  end
  local i,j=endpoint[1],endpoint[2];local rev={}
  while i>=1 and j>=1 do
    rev[#rev+1]={dub=d[i].t,ref=ref0+r[j].t,di=i,ri=j,cost=DSP.distance(d[i],r[j],cfg.profile),
      active=d[i].active and r[j].active,audible=d[i].active or r[j].active}
    local dir=directions[i]:byte(j-starts[i]+1)
    if dir==4 then break elseif dir==1 then i,j=i-1,j-1 elseif dir==2 then i,j=i-1,j-2 elseif dir==3 then i,j=i-2,j-1 else return nil,'Incomplete alignment path.' end
    if #rev%512==0 then job:checkpoint() end
  end
  local path={};for k=#rev,1,-1 do path[#path+1]=rev[k] end
  local active,total,matched=0,0,0
  for _,p in ipairs(path) do
    if p.audible then active=active+1;total=total+p.cost end
    if p.active and p.cost<.8 then matched=matched+1 end
  end
  local covered=path[#path].dub-path[1].dub
  if matched<4 or covered<math.min(.12,math.min(ref.len,dub.len)*.6) then return nil,'Too little matching audio.' end
  return path,{cost=total/math.max(1,active),support=matched/math.max(1,active),
    coverage=covered/math.max(hop,d[#d].t-d[1].t),cells=cells}
end
function M.align(ref,dub,cfg,job)
  if ref.silent or dub.silent then return nil,'No usable audio above the adaptive noise floor.' end
  local coarse_ref,coarse_dub=aggregate(ref,4,job),aggregate(dub,4,job)
  local path,stats=solve(coarse_ref,coarse_dub,cfg,job:scope(0,.25),nil,cfg.search_s,'Coarse alignment')
  if not path then return nil,stats end
  local fine_ref,fine_dub=aggregate(ref,1,job),aggregate(dub,1,job)
  local fine,info=solve(fine_ref,fine_dub,cfg,job:scope(.25,.70),path,math.min(cfg.search_s,.14),'Detailed alignment')
  if not fine then
    -- A coarse guide can exclude a valid fine-grid endpoint. Retry inside the
    -- original user limit, without widening the allowed displacement.
    fine,info=solve(fine_ref,fine_dub,cfg,job:scope(.70,.85),nil,cfg.search_s,'Checking path boundaries')
    if not fine then return nil,info end
  end
  -- A narrow coarse guide can miss a local match: retry with a wider corridor when necessary.
  if info.cost>.65 and cfg.search_s>.14 then
    local retry,ri=solve(fine_ref,fine_dub,cfg,job:scope(.85,.99),path,math.min(cfg.search_s,.4),'Checking uncertain alignment')
    if retry and ri.cost<info.cost then fine,info=retry,ri end
  end
  local cost=info.cost;info.confidence=DSP.clamp(1-cost/.9,0,1)
  if cost>.95 then return nil,'The recordings do not match reliably. Check the reference or use a shorter phrase.' end
  job:checkpoint(1,'Alignment ready')
  return fine,info
end
return M
