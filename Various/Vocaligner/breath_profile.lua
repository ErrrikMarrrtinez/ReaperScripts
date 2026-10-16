-- @noindex
local import=...;local Features=import('breath_features');local Model=import('breath_model');local M={}
local namespace='mrtnz_Vocaligner_Breath1'
function M.new() return {revision=0,examples={}} end
-- Numeric, bounded project data only. Never execute serialized Lua.
function M.load(r,project,guid)
  local out=M.new();if not r.GetProjExtState then return out end
  local _,s=r.GetProjExtState(project,namespace,guid)
  if type(s)~='string' or #s>32000 or s:sub(1,3)~='v1\n' then return out end
  for line in s:sub(4):gmatch('[^\n]+') do
    local v={};for token in line:gmatch('[^,]+') do
      local n=tonumber(token);if not n or n~=n or math.abs(n)>1e6 then return M.new() end;v[#v+1]=n
    end
    if #v~=1+Features.profile_size*2 or (v[1]~=1 and v[1]~=-1) then return M.new() end
    local e={kind=v[1],mean={},variance={}}
    for k=1,Features.profile_size do
      e.mean[k]=v[k+1];e.variance[k]=v[k+1+Features.profile_size]
      if e.variance[k]<0 then return M.new() end
    end
    out.examples[#out.examples+1]=e;if #out.examples>16 then return M.new() end
  end
  return out
end
function M.save(r,project,guid,profile)
  if not r.SetProjExtState then return end
  local lines={'v1'}
  for _,e in ipairs(profile.examples) do
    local v={tostring(e.kind)}
    for _,a in ipairs({e.mean,e.variance}) do for k=1,Features.profile_size do v[#v+1]=string.format('%.9g',a[k]) end end
    lines[#lines+1]=table.concat(v,',')
  end
  r.SetProjExtState(project,namespace,guid,#profile.examples>0 and table.concat(lines,'\n') or '')
end
function M.learn(data,profile,range,kind,job)
  if range[2]-range[1]<.04 or range[2]-range[1]>2 then return nil,'Select 40 ms to 2 seconds of one sound to learn.' end
  local rows=Features.build(data,job).rows;local e={kind=kind,mean={},variance={}};local count=0
  for k=1,Features.profile_size do e.mean[k]=0;e.variance[k]=0 end
  local a=math.max(1,math.ceil(range[1]/data.hop)+1);local b=math.min(#rows,math.floor(range[2]/data.hop)+1)
  for i=a,b do
    if data.frames[i].rms>1e-7 then count=count+1;for k=1,Features.profile_size do e.mean[k]=e.mean[k]+rows[i][k] end end
  end
  if count<3 then return nil,'The selection contains too little audible sound to learn.' end
  for k=1,Features.profile_size do e.mean[k]=e.mean[k]/count end
  for i=a,b do if data.frames[i].rms>1e-7 then
    for k=1,Features.profile_size do e.variance[k]=e.variance[k]+(rows[i][k]-e.mean[k])^2/count end
  end end
  -- Bound adaptation cost and keep both positive and negative examples available.
  local same=0;for _,v in ipairs(profile.examples) do if v.kind==kind then same=same+1 end end
  if same>=8 then for i,v in ipairs(profile.examples) do if v.kind==kind then table.remove(profile.examples,i);break end end end
  profile.examples[#profile.examples+1]=e;profile.revision=profile.revision+1
  return true
end
function M.adjust(row,base,profile)
  if not profile or #profile.examples==0 then return base end
  local positive,negative=0,0
  for _,e in ipairs(profile.examples) do
    local distance=0
    for k=1,Features.profile_size do
      local scale=Model.scale[k];local variance=math.max(scale*scale*.18,math.min(scale*scale,e.variance[k]))
      distance=distance+math.min(25,(row[k]-e.mean[k])^2/variance)
    end
    local similarity=math.exp(-distance/Features.profile_size)
    if e.kind==1 then positive=math.max(positive,similarity) else negative=math.max(negative,similarity) end
  end
  local p=math.max(1e-6,math.min(1-1e-6,base+(1-base)*.98*positive))
  local logit=math.log(p/(1-p))-9*negative
  return 1/(1+math.exp(-math.max(-30,math.min(30,logit)))),negative
end
return M
