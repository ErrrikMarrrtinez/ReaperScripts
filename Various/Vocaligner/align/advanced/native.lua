-- @noindex
local import=...;local U=import('align/util');local Distance=import('align/advanced/distance');local M={};M.__index=M
local INF=1e100;local LIMIT=8*1024*1024 -- EEL's default 64 MiB address budget.
local Trace={};Trace.__index=Trace
function Trace:byte(index)
  local cell=(index-1)//self.bytes;local field=(index-1)%self.bytes
  if self.cell~=cell then
    self.values=self.engine:read(self.base+cell*self.words,self.words,self.job);self.cell=cell
  end
  return math.floor(self.values[field//6+1]/256^(field%6))%256
end
local function finite(v)return U.finite(v)and v or INF end
local function flags(f)
  return (f.missing and 1 or 0)+(f.delta_valid and 2 or 0)+(f.voicing_available and 4 or 0)+
    (f.trustworthy and 8 or 0)+(f.pitch and 16 or 0)+(f.pitch_delta and 32 or 0)
end
function M.new(im,ctx,r)
  local self=setmetatable({im=im,r=r,label='Lua'},M)
  local ok,why=pcall(function()
    self.fn=im.CreateFunctionFromEEL(import('align/advanced/native_code'));im.Attach(ctx,self.fn)
    assert(self.fn,'Advanced EEL compilation returned no function')
    self:set({INF=INF,mode=-1});im.Function_Execute(self.fn)
    self.label='EEL'
  end)
  if not ok then self.fn=nil;self.reason=tostring(why)end
  return self
end
function M:host(fn,...)
  if self.job and coroutine.isyieldable()then return self.job:call(fn,...)end
  return fn(...)
end
function M:set(values)
  self:host(function()for k,v in pairs(values)do self.im.Function_SetValue(self.fn,k,v)end end)
end
function M:get(key)return self:host(self.im.Function_GetValue,self.fn,key)end
function M:allocate(name,count)
  assert(count>=0 and count%1==0,'Invalid native allocation')
  local at=self.top;self.top=at+count
  if self.top>LIMIT then U.fail('work_budget_exceeded','Advanced EEL memory exceeds 64 MiB','match')end
  self:set({[name]=at});self.address[name]=at;return at
end
function M:write(name,values,job)
  local base=self.address[name];assert(base)
  for first=1,#values,32768 do
    local last=math.min(#values,first+32767);local block={}
    for i=first,last do block[#block+1]=values[i]end
    U.call(job,function()
      self:set({transfer=base+first-1});self.im.Function_SetValue_Array(self.fn,'transfer',self.r.new_array(block))
    end)
    U.checkpoint(job)
  end
end
function M:read(at,count,job)
  return U.call(job,function()
    self:set({transfer=at});local a=self.r.new_array(count)
    self.im.Function_GetValue_Array(self.fn,'transfer',a);return a.table()
  end)
end
local function pack(data,job)
  local values={}
  for i,f in ipairs(data.frames)do
    local head={f.t,f.mass,f.event or 0,f.background or 0,f.onset or 0,f.energy or 0,f.spectral_reliability or 0,f.cep_reliability or 0,
      f.onset_reliability or 0,f.energy_reliability or 0,f.pitch_reliability or 0,f.voiced or 0,f.pitch or 0,f.pitch_delta or 0,flags(f)}
    for _,v in ipairs(head)do values[#values+1]=v end
    for k=1,32 do values[#values+1]=f.spec and f.spec[k]or 0 end
    for k=1,12 do values[#values+1]=f.cep and f.cep[k]or 0 end
    for k=1,6 do values[#values+1]=f.delta and f.delta[k]or 0 end
    if i%128==0 then U.checkpoint(job)end
  end
  assert(#values==#data.frames*65,'Invalid native frame packing');return values
end
function M:begin_match(ref,dub,cfg,budget)
  if not self.fn then return false end
  local job=budget.job;self.job=job;self.top=0;self.address={};self.ref=ref;self.dub=dub
  self:allocate('dframes',#dub.frames*65);self:allocate('rframes',#ref.frames*65)
  self:write('dframes',pack(dub,job),job);self:write('rframes',pack(ref,job),job)
  local metadata={};local cells=0
  for _,f in ipairs(dub.frames)do
    local x=dub.pos-ref.pos+f.t
    local lo=math.max(1,U.lower(ref.frames,x-cfg.search_s-1e-9))
    local hi=math.min(#ref.frames,U.lower(ref.frames,x+cfg.search_s+1e-9)-1)
    metadata[#metadata+1]=lo;metadata[#metadata+1]=hi;metadata[#metadata+1]=cells
    cells=cells+math.max(0,hi-lo+1)
  end
  -- Cache is optional; reserve at least half of the VM for DP/trace/history.
  local cached=self.top+#metadata+cells*2<=LIMIT/2 and cells*16<=(cfg.max_pair_cache_bytes or 64*1024*1024)
  self:allocate('cache_rows',cached and #metadata or 0)
  self:allocate('pair_c',cached and cells or 0);self:allocate('pair_q',cached and cells or 0)
  if cached then self:write('cache_rows',metadata,job)end
  local w=cfg.weights or Distance.weights(cfg)
  self:set({nd=#dub.frames,nr=#ref.frames,dubpos=dub.pos,refpos=ref.pos,quantum=cfg.quantum,
    w1=w[1],w2=w[2],w3=w[3],w4=w[4],w5=w[5],wfull=w.full,min_pair=cfg.min_pair,
    unknown_cost=cfg.unknown_cost,missing_penalty=cfg.missing_penalty,max_cost=cfg.max_cost,silence_cost=cfg.silence_cost,
    has_cache=cached and 1 or 0,cache_count=cached and cells or 0,mode=0})
  U.call(job,self.im.Function_Execute,self.fn)
  self.match_top=self.top;self.peak_bytes=self.top*8;return true
end
function M:run(x)
  local cfg,budget,options=x.cfg,x.budget,x.options;local job=budget.job;self.job=job
  if self.ref~=x.ref or self.dub~=x.dub then self:begin_match(x.ref,x.dub,cfg,budget)end
  self.top=self.match_top
  local regions,masked,overrides={},{},{}
  local has_mask=options.constraints and #options.constraints>0
  local slots={};local slot_count=0
  if x.dland then for i=1,x.N do if x.dland.origins[x.first+i-1]then slots[i]=slot_count;slot_count=slot_count+1 end end end
  local cells=0
  for i,bounds in ipairs(x.region)do
    for _,v in ipairs({bounds.lo,bounds.hi,cells,0,slots[i]or -1})do regions[#regions+1]=v end
    for j=bounds.lo,bounds.hi do
      if has_mask then masked[#masked+1]=x.limits.pair_forbidden(x.first+i-1,j)and 1 or 0 end
      if options.cost then local c,q=options.cost(x.first+i-1,j);overrides[#overrides+1]=finite(c);overrides[#overrides+1]=q or 0 end
      cells=cells+1
    end
    if i%64==0 then budget:checkpoint(nil,'Preparing native matching')end
  end
  local words=math.ceil(x.bytes/6);local RS=x.S*3+8;local row_stride=x.max_width*RS;local history_stride=x.max_width*9
  self:allocate('regions',#regions);self:allocate('masks',#masked);self:allocate('overrides',#overrides)
  self:allocate('dmax',#x.dub.frames);self:allocate('rmax',#x.ref.frames)
  self:allocate('dopen',#x.qdo);self:allocate('dstep',#x.qdg);self:allocate('ropen',#x.qro);self:allocate('rstep',#x.qrg)
  self:allocate('rolling',row_stride*3);self:allocate('history',slot_count*history_stride)
  self:allocate('trace',cells*words)
  local dm,rm={},{ }
  if options.macro then
    for i=1,x.N do
      local edges=x.dland.incoming[x.first+i-1]or {};local row={#edges}
      for k=1,3 do
        local e=edges[k]
        if e then
          local origin=e.origin-x.first+1;local allowed=x.limits.gap_allowed('dub',e.origin+1,x.first+i-1,cfg,true)
          row[#row+1]=origin;row[#row+1]=allowed and slots[origin]or -1
          row[#row+1]=x.quantize(cfg.macro_open+x.dp.gap[x.first+i-1]-x.dp.gap[e.origin],cfg)
          row[#row+1]=x.first+i-1-e.origin
        else for _=1,4 do row[#row+1]=0 end end
      end
      for _,v in ipairs(row)do dm[#dm+1]=v end
    end
    for j=1,#x.ref.frames do
      local edges=x.rland.incoming[j]or {};rm[#rm+1]=#edges
      for k=1,3 do local e=edges[k]
        if e then
          rm[#rm+1]=e.origin
          rm[#rm+1]=x.limits.gap_allowed('ref',e.origin+1,j,cfg,true)and x.quantize(cfg.macro_open+x.rp.gap[j]-x.rp.gap[e.origin],cfg)or INF
          rm[#rm+1]=j-e.origin
        else for _=1,3 do rm[#rm+1]=0 end end
      end
    end
  end
  self:allocate('dmacro',#dm);self:allocate('rmacro',#rm)
  self.peak_bytes=math.max(self.peak_bytes,self.top*8)
  self:write('regions',regions,job);self:write('masks',masked,job);self:write('overrides',overrides,job)
  local dx={};for i=1,#x.dub.frames do dx[i]=x.dmax[i]or 0 end
  for name,values in pairs({dmax=dx,rmax=x.rmax,dopen=x.qdo,dstep=x.qdg,ropen=x.qro,rstep=x.qrg,dmacro=dm,rmacro=rm})do self:write(name,values,job)end
  local f=options.forbidden or {}
  self:set({first=x.first,N=x.N,G=cfg.max_gap,S=x.S,RS=RS,DM=4+2*cfg.max_gap,RM=5+2*cfg.max_gap,
    A=x.A,beta=x.beta,guide_start=x.guide_start,search_s=cfg.search_s,gap_close=cfg.gap_close,
    row_stride=row_stride,history_stride=history_stride,history_size=slot_count*history_stride,
    total_cells=cells,words=words,macro_enabled=options.macro and 1 or 0,has_mask=has_mask and 1 or 0,override=options.cost and 1 or 0,
    has_forbidden=options.forbidden and 1 or 0,forbidden_dub=f.dub_s or 0,forbidden_dr=f.dub_radius or 0,
    forbidden_ref=f.guide_project_s or 0,forbidden_rr=f.ref_radius or 0,mode=1})
  U.call(job,self.im.Function_Execute,self.fn)
  self:set({mode=2,block_cells=256})
  local charged_cells,charged_states=0,0
  while self:get('done')==0 do
    U.call(job,self.im.Function_Execute,self.fn)
    if self:get('overflow')~=0 then U.fail('work_budget_exceeded','Native DP integer sum overflow','match')end
    local vc,vs=self:get('visited'),self:get('states_visited')
    budget:add('cells',vc-charged_cells);budget:add('states',vs-charged_states);charged_cells,charged_states=vc,vs
    budget:checkpoint(math.min(x.N,self:get('i'))/x.N,'Matching in EEL')
  end
  assert(charged_cells==cells and charged_states==x.evaluated,'Native work accounting differs')
  -- Only the winning path needs to cross the native/Lua boundary. Fetching the
  -- whole corridor converted millions of unused trace bytes into Lua tables.
  local trace={};local at=self.address.trace
  for i,bounds in ipairs(x.region)do
    local width=math.max(0,bounds.hi-bounds.lo+1)
    trace[i]={lo=bounds.lo,hi=bounds.hi,bytes=setmetatable({engine=self,base=at,words=words,bytes=x.bytes,job=job},Trace)}
    at=at+width*words
  end
  local last=x.region[x.N];local width=math.max(0,last.hi-last.lo+1)
  local ptr=self.address.rolling+((x.N-1)%3)*row_stride
  local values=width>0 and self:read(ptr,width*RS,job)or {};local row={lo=last.lo,hi=last.hi,c={},g={},d={}}
  for k=0,width-1 do for state=1,x.S do
    local src=k*RS+(state-1)*3;local dst=k*x.S+state;local c=values[src+1]
    if c<INF then row.c[dst]=c;row.g[dst]=values[src+2];row.d[dst]=values[src+3]end
  end end
  budget.native_bytes=math.max(budget.native_bytes or 0,self.peak_bytes)
  return trace,row
end
return M
