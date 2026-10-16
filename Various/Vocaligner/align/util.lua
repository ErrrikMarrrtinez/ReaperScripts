-- @noindex
local M={}
function M.finite(x) return type(x)=='number' and x==x and math.abs(x)<math.huge end
function M.clamp(x,a,b) return math.max(a,math.min(b,x)) end
function M.copy(t) local o={};for k,v in pairs(t or {})do o[k]=v end;return o end
function M.quantile(t,q)
  if #t==0 then return 0 end
  local a={};for i,x in ipairs(t)do a[i]=x end;table.sort(a)
  return a[math.max(1,math.ceil(q*#a))]
end
function M.lower(frames,t)
  local lo,hi=1,#frames+1
  while lo<hi do local m=(lo+hi)//2;if frames[m].t<t then lo=m+1 else hi=m end end
  return lo
end
function M.nearest(frames,t)
  if #frames==0 then return nil end
  local i=M.lower(frames,t)
  if i>#frames then return #frames end
  if i>1 and t-frames[i-1].t<=frames[i].t-t then return i-1 end
  return i
end
function M.dot(a,b) local v=0;for i,x in ipairs(a)do v=v+x*b[i] end;return v end
function M.unit(a)
  local norm=math.sqrt(M.dot(a,a));local out={}
  for i,x in ipairs(a)do out[i]=norm>1e-6 and x/norm or 0 end
  return out,norm
end
function M.checkpoint(job,p,label) if job then job:checkpoint(p,label) end end
function M.call(job,fn,...) if job then return job:call(fn,...) end;return fn(...) end
function M.error(code,message,stage,extra)
  local e=extra or {};e.code=code;e.message=message or code;e.stage=stage;e.recoverable=true
  return setmetatable(e,{__tostring=function(v)return v.code..': '..v.message end})
end
function M.fail(code,message,stage) error(M.error(code,message,stage),0) end
local function quote(s)
  return '"'..s:gsub('[%z\1-\31\\"]',function(c)
    local escapes={['"']='\\"',['\\']='\\\\',['\n']='\\n',['\r']='\\r',['\t']='\\t'}
    return escapes[c] or string.format('\\u%04x',c:byte())
  end)..'"'
end
-- Canonical, data-only JSON also defines settings keys. No executable cache imports.
function M.json(value)
  local seen={}
  local function encode(v,depth)
    assert(depth<40,'JSON depth limit')
    local kind=type(v)
    if kind=='nil' then return 'null' end
    if kind=='boolean' then return v and 'true' or 'false' end
    if kind=='number' then assert(M.finite(v),'Nonfinite JSON number');return string.format('%.17g',v) end
    if kind=='string' then return quote(v) end
    assert(kind=='table' and not seen[v],'Invalid JSON value');seen[v]=true
    local keys,n={},0
    for k in pairs(v)do keys[#keys+1]=k;n=n+1 end
    local out={};local array=n>0 and n==#v
    if array then for i=1,n do out[i]=encode(v[i],depth+1) end
    else
      table.sort(keys,function(a,b)return tostring(a)<tostring(b) end)
      for i,k in ipairs(keys)do assert(type(k)=='string','JSON object key is not a string: '..tostring(k)..' (sparse index table?)');out[i]=quote(k)..':'..encode(v[k],depth+1) end
    end
    seen[v]=nil;return (array and '[' or '{')..table.concat(out,',')..(array and ']' or '}')
  end
  return encode(value,0)
end
function M.hash(text)
  local h=2166136261
  for i=1,#text do h=((h~text:byte(i))*16777619)&0xffffffff end
  return string.format('%08x',h)
end
function M.key(value) return M.json(value) end -- Full canonical key, not a collision-prone digest.
function M.budget(cfg,job)
  local b={states=0,cells=0,coarse=0,reduce=0,retries=0,trace_peak=0,job=job,cfg=cfg}
  function b:add(kind,n)
    self[kind]=(self[kind] or 0)+n
    local cap=kind=='states' and self.cfg.max_states or kind=='coarse' and self.cfg.max_coarse_work or kind=='reduce' and self.cfg.max_reduce_work or kind=='regularize' and self.cfg.max_regularize_work
    if cap and self[kind]>cap then M.fail('work_budget_exceeded',kind..' budget exceeded','budget') end
  end
  function b:trace(n)
    if n>self.cfg.max_trace_bytes then M.fail('work_budget_exceeded','Packed traceback budget exceeded','match') end
    self.trace_peak=math.max(self.trace_peak,n)
  end
  function b:checkpoint(p,label) M.checkpoint(self.job,p,label) end
  function b:scope(job)
    -- Every progress scope shares the original budget directly. Nesting scope
    -- proxies made every DP counter/cache access traverse several Lua closures.
    return setmetatable({job=job},{__index=b,__newindex=function(_,key,value)b[key]=value end})
  end
  return b
end
return M
