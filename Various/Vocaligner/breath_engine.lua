-- @noindex
local import=...;local Model=import('breath_model');local M={};M.__index=M
-- Only bounded numerical inference runs in this private EEL VM. No shared gmem.
M.code=[[
i=0;
loop(count,
  row=input+i*feature_count; score=baseline; tree=0;
  loop(trees,
    node=roots[tree]; depth=0;
    while(
      p=nodes+(node-1)*5; feature=p[0];
      feature>0 && depth<8 ? (
        node=row[feature-1]<=p[1] ? p[2] : p[3]; depth+=1; 1;
      ) : (score+=p[4]; 0;);
    );
    tree+=1;
  );
  output[i]=1/(1+exp(-max(-30,min(30,score)))); i+=1;
);
]]
function M.predict(row)
  local score=Model.baseline
  for _,root in ipairs(Model.roots) do
    local node=Model.nodes[root]
    while node[1]>0 do node=Model.nodes[row[node[1]]<=node[2] and node[3] or node[4]] end
    score=score+node[5]
  end
  return 1/(1+math.exp(-math.max(-30,math.min(30,score))))
end
function M.new(im,ctx,r)
  local self=setmetatable({im=im,r=r,label='Lua breath trees'},M)
  local ok,why=pcall(function()
    self.fn=im.CreateFunctionFromEEL(M.code);im.Attach(ctx,self.fn)
    for key,value in pairs({nodes=0,roots=65536,input=69632,output=81920,baseline=Model.baseline,trees=#Model.roots,feature_count=Model.feature_size or 24}) do
      im.Function_SetValue(self.fn,key,value)
    end
    assert(#Model.nodes*5<65536 and #Model.roots<4096 and (Model.feature_size or 24)*128<81920-69632,'Breath model exceeds EEL layout')
    local nodes={};for _,n in ipairs(Model.nodes) do for _,v in ipairs(n) do nodes[#nodes+1]=v end end
    im.Function_SetValue_Array(self.fn,'nodes',r.new_array(nodes))
    im.Function_SetValue_Array(self.fn,'roots',r.new_array(Model.roots))
    local input,rows={},{}
    for i=1,4 do rows[i]={};for k=1,Model.feature_size or 24 do local v=(i-2)*k*.19;rows[i][k]=v;input[#input+1]=v end end
    local got=self:execute(input,4)
    for i,row in ipairs(rows) do assert(math.abs(got[i]-M.predict(row))<1e-9,'Breath EEL self-check failed') end
    self.label='EEL breath trees'
  end)
  if not ok then self.fn=nil;self.reason=tostring(why) end
  return self
end
function M:execute(values,count)
  local im,fn=self.im,self.fn
  im.Function_SetValue_Array(fn,'input',self.r.new_array(values))
  im.Function_SetValue(fn,'count',count)
  local out=self.r.new_array(count);local started=self.r.time_precise()
  im.Function_Execute(fn);self.kernel_ms=(self.kernel_ms or 0)+(self.r.time_precise()-started)*1000
  self.calls=(self.calls or 0)+1;im.Function_GetValue_Array(fn,'output',out)
  return out.table()
end
function M.scores(data,features,job,engine)
  local cached=data.breath_model_scores
  if cached and cached.version==Model.version then cached.reuses=(cached.reuses or 0)+1;return cached.values end
  local started=engine and engine.r.time_precise();local kernel=engine and engine.kernel_ms or 0
  local rows=features.rows;local result={}
  for first=1,#rows,128 do
    local last=math.min(#rows,first+127);local values
    if engine and engine.fn then
      local input={};for i=first,last do for k=1,Model.feature_size or 24 do input[#input+1]=rows[i][k] end end
      local function run() return engine:execute(input,last-first+1) end
      local ok
      if job then ok,values=job:call(pcall,run) else ok,values=pcall(run) end
      if not ok then engine.fn=nil;engine.label='Lua breath trees';engine.reason=tostring(values);values=nil end
    end
    for i=first,last do result[i]=values and values[i-first+1] or M.predict(rows[i]) end
    if job then job:checkpoint() end
  end
  data.breath_model_scores={version=Model.version,values=result,
    elapsed_ms=started and (engine.r.time_precise()-started)*1000 or nil,kernel_ms=engine and (engine.kernel_ms or 0)-kernel or nil}
  return result
end
return M
