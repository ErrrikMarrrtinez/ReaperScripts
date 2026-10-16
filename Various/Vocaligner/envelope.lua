-- @noindex
local import=...;local Cleanup=import('cleanup');local M={}
local empty='<VOLENV\nACT 1 -1\nVIS 1 1 1\nLANEHEIGHT 0 0\nARM 0\nDEFSHAPE 0 -1 -1\nVOLTYPE 0\nPT 0 1 0\n>\n'
function M.read(r,take)
  if not r.GetTakeEnvelopeByName then return nil end
  local env=r.GetTakeEnvelopeByName(take,'Volume');if not env then return nil end
  local ok,chunk=r.GetEnvelopeStateChunk(env,'',false)
  assert(ok and chunk~='','Could not capture the take volume envelope.')
  return chunk
end
function M.describe(r,take)
  local env=r.GetTakeEnvelopeByName and r.GetTakeEnvelopeByName(take,'Volume')
  if not env then return nil end
  local out={}
  for i=0,r.CountEnvelopePoints(env)-1 do
    local ok,t,v,shape,tension=r.GetEnvelopePoint(env,i);assert(ok)
    out[#out+1]={t=t,v=v,shape=shape,tension=tension}
  end
  return out
end
function M.shift(chunk,delta)
  if not chunk or math.abs(delta)<1e-12 then return chunk end
  return chunk:gsub('(PT%s+)([%+%-%.%deE]+)',function(prefix,t) return prefix..string.format('%.17g',tonumber(t)+delta) end)
end
function M.shift_points(points,delta)
  if not points then return nil end
  local out={};for i,p in ipairs(points) do out[i]={t=p.t+delta,v=p.v,shape=p.shape,tension=p.tension} end;return out
end
function M.equivalent(a,b,len,pa,pb)
  if not a or not b then return a==b end
  local function mode(s,key,default) return tonumber(s:match(key..'%s+([%-%d]+)')) or default end
  if mode(a,'ACT',1)~=mode(b,'ACT',1) or mode(a,'VOLTYPE',0)~=mode(b,'VOLTYPE',0) then return false end
  local function parse(s)
    local out={};for t,v,shape in s:gmatch('PT%s+(%S+)%s+(%S+)%s+(%S+)') do
      out[#out+1]={t=tonumber(t),v=tonumber(v),shape=tonumber(shape),tension=0}
    end;return out
  end
  pa,pb=pa or parse(a),pb or parse(b)
  local function near(x,y) return math.abs(x-y)<=1e-7+math.abs(y)*2e-6 end
  local exact=#pa==#pb
  if exact then for i,p in ipairs(pa) do local q=pb[i]
    if not near(p.t,q.t) or not near(p.v,q.v) or p.shape~=q.shape or not near(p.tension,q.tension) then exact=false;break end
  end end
  if exact then return true end
  -- REAPER may insert boundary points on split. Our generated envelope is linear;
  -- compare its audible curve, not point count or points outside the new item.
  for _,points in ipairs({pa,pb}) do for _,p in ipairs(points) do if p.shape~=0 then return false end end end
  if #pa==0 or #pb==0 then return false end
  local function value(points,t)
    local lo,hi=1,#points
    if t<=points[lo].t then return points[lo].v end
    if t>=points[hi].t then return points[hi].v end
    while hi-lo>1 do local mid=(lo+hi)//2;if points[mid].t<=t then lo=mid else hi=mid end end
    return points[lo].v+(points[hi].v-points[lo].v)*(t-points[lo].t)/(points[hi].t-points[lo].t)
  end
  local times={0,len}
  for _,points in ipairs({pa,pb}) do for _,p in ipairs(points) do if p.t>0 and p.t<len then times[#times+1]=p.t end end end
  for _,t in ipairs(times) do if not near(value(pa,t),value(pb,t)) then return false end end
  return true
end
-- Only the top-level VOLENV belonging to the exact take GUID may be replaced.
-- Nested FX/source state and all other takes are copied verbatim.
function M.replace_chunk(chunk,guid,replacement)
  local lines={};for line in (chunk..'\n'):gmatch('(.-)\n') do lines[#lines+1]=line:gsub('\r$','') end
  local depth,start,finish,found=0,1,nil,false;local env_start,env_end,env_depth
  for i,line in ipairs(lines) do
    local text=line:match('^%s*(.-)%s*$')
    if depth==1 and (text:match('^TAKE%s') or text=='TAKE' or text=='>') then
      if found then finish=i-1;break end
      start=i;env_start,env_end=nil,nil
    end
    if depth==1 and text=='GUID '..guid then found=true end
    if depth==1 and (text=='<VOLENV' or text:match('^<VOLENV%s')) then
      assert(not env_start,'Multiple volume envelopes in one take are unsupported.')
      env_start=i;env_depth=depth+1
    end
    if text:sub(1,1)=='<' then depth=depth+1
    elseif text=='>' then
      if env_start and not env_end and depth==env_depth then env_end=i end
      depth=depth-1
    end
  end
  assert(found and finish and start<=finish,'Could not locate the captured take in the item state.')
  if not env_start and not replacement then return chunk end
  local out={}
  for i,line in ipairs(lines) do
    if env_start and i==env_start and replacement then out[#out+1]=replacement:gsub('[\r\n]+$','') end
    if not env_start or i<env_start or i>env_end then out[#out+1]=line end
    if not env_start and i==finish and replacement then out[#out+1]=replacement:gsub('[\r\n]+$','') end
  end
  return table.concat(out,'\n'):gsub('\n+$','\n')
end
function M.restore(r,s,chunk)
  if not r.GetTakeEnvelopeByName then assert(not chunk,'Volume envelope API unavailable.');return end
  local take=r.GetActiveTake(s.item);local _,guid=r.GetSetMediaItemTakeInfo_String(take,'GUID','',false)
  assert(guid==s.guid,'The active take changed while writing its envelope.')
  local env=r.GetTakeEnvelopeByName(take,'Volume')
  if chunk then
    local existing=env and M.read(r,take)
    local eguid=existing and existing:match('EGUID%s+(%b{})')
    if not eguid and r.genGuid then eguid=r.genGuid() end
    if eguid then chunk=chunk:gsub('(EGUID%s+)%b{}','%1'..eguid) end
  end
  if env and chunk then assert(r.SetEnvelopeStateChunk(env,chunk,false),'Could not restore take volume envelope.');return end
  if not env and not chunk then return end
  local ok,current=r.GetItemStateChunk(s.item,'',false);assert(ok,'Could not read item state for volume envelope.')
  local updated=M.replace_chunk(current,s.guid,chunk)
  assert(r.SetItemStateChunk(s.item,updated,false),'Could not update the take volume envelope.')
  take=r.GetActiveTake(s.item);local _,after=r.GetSetMediaItemTakeInfo_String(take,'GUID','',false)
  assert(after==s.guid,'Writing the volume envelope changed the active take.')
  assert((r.GetTakeEnvelopeByName(take,'Volume')~=nil)==(chunk~=nil),'REAPER did not accept the volume envelope state.')
end
-- Called inside the apply transaction with the captured envelope restored. Sample
-- its native curves BEFORE changing markers; then map both envelope and reduction
-- through the same timing plan. Repeated Apply never multiplies an earlier result.
function M.prepare(r,s,plan,cleanup,cfg)
  local Warp=import('warp')
  local attenuation=cleanup and (cleanup.max_db>.01 or cleanup.force_envelope)
  local baseline=s.volume_envelope
  if not baseline and not attenuation then return nil end
  if plan.unchanged and not attenuation then return baseline end
  local take=r.GetActiveTake(s.item);local current=r.GetTakeEnvelopeByName(take,'Volume')
  local env=baseline and current or nil
  local template=baseline or empty
  if not baseline and current then
    local ok,state=r.GetEnvelopeStateChunk(current,'',false)
    local guid=ok and state:match('EGUID%s+(%b{})')
    if guid then template=template:gsub('\nACT','\nEGUID '..guid..'\nACT',1) end
  end
  local active=baseline and not baseline:match('ACT%s+0[%s\r\n]')
  local mode=env and r.GetEnvelopeScalingMode(env) or 0
  local times={0,s.len};local originals={}
  for i=0,env and r.CountEnvelopePoints(env)-1 or -1 do
    local ok,time,value,shape,tension,selected=r.GetEnvelopePoint(env,i)
    assert(ok,'Could not read an original envelope point.')
    originals[#originals+1]={time=time,value=value,shape=shape,tension=tension,selected=selected}
    local t=time/s.rate
    if t>0 and t<s.len then times[#times+1]=t
      -- Preserve discontinuities (square segments) without replacing them with
      -- a full analysis-hop ramp. The native curve supplies either side's value.
      if i>0 and originals[#originals-1].shape==1 then times[#times+1]=math.max(0,t-1e-6) end
    end
  end
  for i=1,math.ceil(s.len/.01)-1 do times[#times+1]=i*.01 end
  for _,m in ipairs(plan.markers) do if m.t and m.t>0 and m.t<s.len then times[#times+1]=m.t end end
  for _,p in ipairs(cleanup and cleanup.points or {})do if p.t>0 and p.t<s.len then times[#times+1]=p.t end end
  table.sort(times)
  local samples={};local previous=-1
  local precision=cfg and (cfg.envelope_detail or cfg.deess_detail) and 10^(-1.5-(cfg.envelope_detail or cfg.deess_detail)*.025) or .001
  for _,t in ipairs(times) do if t>previous+1e-9 then
    local value=1
    if env and (active or not attenuation) then
      local _,v=r.Envelope_Evaluate(env,t*s.rate,0,0)
      assert(type(v)=='number' and v==v,'Could not evaluate the original volume envelope.')
      value=r.ScaleFromEnvelopeMode(mode,v)
    end
    local reduction=Cleanup.value(cleanup,t)
    value=r.ScaleToEnvelopeMode(mode,value*10^(-reduction/20))
    samples[#samples+1]={time=(Warp.target(plan,t)-plan.pos)*s.rate,value=value,
      active=math.abs(reduction)>.01,epsilon=math.max(.0001,math.abs(value)*(math.abs(reduction)>.01 and precision or .001))}
    previous=t
  end end
  -- Simplify in the envelope's interpolation domain; bound absolute/relative
  -- gain error instead of storing thousands of identical unity points.
  local keep={[1]=true,[#samples]=true}
  -- Independent dips split RDP into short sections. A whole-item RDP repeatedly
  -- scans the same silent spans when many similar sibilants share the same peak.
  for i=2,#samples do if samples[i].active~=samples[i-1].active then keep[i-1]=true;keep[i]=true end end
  local stack={};local boundary=1
  for i=2,#samples do if keep[i] then stack[#stack+1]={boundary,i};boundary=i end end
  while #stack>0 do
    local range=table.remove(stack);local a,b=samples[range[1]],samples[range[2]];local best,index=1,nil
    for i=range[1]+1,range[2]-1 do local p=samples[i]
      local v=a.value+(b.value-a.value)*(p.time-a.time)/(b.time-a.time)
      local error=math.abs(p.value-v)/p.epsilon
      if error>best then best,index=error,i end
    end
    if index then keep[index]=true;stack[#stack+1]={range[1],index};stack[#stack+1]={index,range[2]} end
  end
  local header={};for line in template:gmatch('[^\r\n]+') do
    if not line:match('^%s*PT%s') and not line:match('^%s*>%s*$') then
      if attenuation and line:match('^%s*ACT%s') then line=line:gsub('ACT%s+%d+','ACT '..tostring(cleanup.chain_active==0 and 0 or 1),1) end
      if attenuation and line:match('^%s*VIS%s') then line=line:gsub('VIS%s+%d+','VIS '..tostring(cleanup.chain_visible==0 and 0 or 1),1) end
      header[#header+1]=line
    end
  end
  local points={}
  for _,p in ipairs(originals) do if p.time<0 or p.time>s.len*s.rate then
    local t=p.time/s.rate
    points[#points+1]={time=(Warp.target(plan,t)-plan.pos)*s.rate,value=p.value,shape=p.shape,tension=p.tension}
  end end
  for i,p in ipairs(samples) do if keep[i] then points[#points+1]=p end end
  table.sort(points,function(a,b)return a.time<b.time end)
  header[#header+1]='>'
  return {header=table.concat(header,'\n')..'\n',points=points,bulk=plan.volume_only and cfg~=nil},#points
end
function M.write(r,s,prepared)
  if type(prepared)~='table' then
    M.restore(r,s,prepared)
    if not r.GetTakeEnvelopeByName then return 0 end
    local env=r.GetTakeEnvelopeByName(r.GetActiveTake(s.item),'Volume')
    return env and r.CountEnvelopePoints(env) or 0
  end
  -- Cleanup emits sorted linear points. Write those together instead of crossing
  -- the native API once per point; keep the existing path for original shapes.
  if prepared.bulk then
    local linear=true
    for _,p in ipairs(prepared.points)do if (p.shape or 0)~=0 or (p.tension or 0)~=0 then linear=false;break end end
    if linear then
      local header=assert(prepared.header:match('^(.*)\n>%s*$'),'Invalid volume envelope header.')
      local lines={header}
      assert(#prepared.points>0,'No volume envelope points were prepared.')
      for _,p in ipairs(prepared.points)do lines[#lines+1]=string.format('PT %.17g %.17g 0',p.time,p.value) end
      lines[#lines+1]='>\n';M.restore(r,s,table.concat(lines,'\n'))
      local env=r.GetTakeEnvelopeByName(r.GetActiveTake(s.item),'Volume')
      assert(env and r.CountEnvelopePoints(env)==#prepared.points,'REAPER did not retain the generated volume envelope.')
      return #prepared.points
    end
  end
  -- Item chunks may accept an empty VOLENV block without creating an envelope.
  -- Seed it with a real point before acquiring its handle for native point edits.
  local first=assert(prepared.points[1],'No volume envelope points were prepared.')
  local header,count=prepared.header:gsub('\n>%s*$',function()
    return string.format('\nPT %.17g %.17g 0\n>\n',first.time,first.value)
  end)
  assert(count==1,'Invalid volume envelope header.')
  M.restore(r,s,header)
  local env=r.GetTakeEnvelopeByName(r.GetActiveTake(s.item),'Volume')
  assert(env,'Could not create the take volume envelope.')
  assert(r.DeleteEnvelopePointRange(env,-1e30,1e30),'Could not clear the working volume envelope.')
  for _,p in ipairs(prepared.points) do
    assert(r.InsertEnvelopePoint(env,p.time,p.value,p.shape or 0,p.tension or 0,false,true),'Could not insert a volume envelope point.')
  end
  assert(r.Envelope_SortPoints(env),'Could not sort volume envelope points.')
  assert(r.CountEnvelopePoints(env)==#prepared.points,'REAPER did not retain the generated volume envelope.')
  return #prepared.points
end
return M
