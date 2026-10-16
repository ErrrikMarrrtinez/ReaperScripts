-- @noindex
local import=...;local Breath=import('breath_engine');local M={};M.__index=M
-- Fixed-size blocks keep Function_Execute bounded. This VM only does math;
-- accessors, FFT, drawing and project edits remain on the Lua/main-thread side.
M.code=[[
b=0;
loop(32,
  f=(b+0.5)*500;
  weights[b]=1/(1+(cutoff/f)^4);
  b+=1;
);
i=0;
loop(count,
  p=input+i*32; b=0; high=0;
  loop(32, high+=p[b]*weights[b]; b+=1;);
  output[i]=high; i+=1;
);
]]
function M.new(im,ctx,r)
  local self=setmetatable({im=im,r=r,label='Lua (cached bands)'},M)
  local ok,why=pcall(function()
    self.fn=im.CreateFunctionFromEEL(M.code);im.Attach(ctx,self.fn)
    im.Function_SetValue(self.fn,'input',0)
    im.Function_SetValue(self.fn,'output',32768)
    im.Function_SetValue(self.fn,'weights',33792)
    local input={};for i=1,64 do input[i]=i*.00001 end
    local got=self:execute(r.new_array(input),2,6500)
    for i=1,2 do
      local expected=0
      for b=1,32 do expected=expected+input[(i-1)*32+b]/(1+(6500/((b-.5)*500))^4) end
      assert(math.abs(got[i]-expected)<1e-10,'EEL array/math self-check failed')
    end
    self.label='EEL (ReaImGui, cached bands)'
  end)
  if not ok then self.fn=nil;self.reason=tostring(why) end
  self.breath=Breath.new(im,ctx,r)
  self.cleanup_dsp=import('cleanup_dsp').new(im,ctx,r)
  self.dynamics=import('compressor/engine').new(im,ctx,r)
  self.align=import('align/advanced/native').new(im,ctx,r)
  return self
end
function M:execute(buffer,count,cutoff)
  local im,fn=self.im,self.fn
  im.Function_SetValue_Array(fn,'input',buffer)
  im.Function_SetValue(fn,'count',count);im.Function_SetValue(fn,'cutoff',cutoff)
  local output=self.r.new_array(count)
  im.Function_Execute(fn);im.Function_GetValue_Array(fn,'output',output)
  return output.table()
end
function M:power(data,cutoff,job)
  if not self.fn then return nil end
  local result={};local blocks=data.detector_blocks or {};data.detector_blocks=blocks
  for first=1,#data.frames,1024 do
    local count=math.min(1024,#data.frames-first+1)
    local function run()
      local buffer=blocks[first]
      if not buffer then
        local values={}
        for i=first,first+count-1 do
          local bands=data.frames[i].noise_bands or {}
          for b=1,32 do values[#values+1]=bands[b] or 0 end
        end
        buffer=self.r.new_array(values);blocks[first]=buffer
      end
      return self:execute(buffer,count,cutoff)
    end
    local ok,values
    if job then ok,values=job:call(pcall,run) else ok,values=pcall(run) end
    if not ok then self.fn=nil;self.label='Lua (cached bands)';self.reason=tostring(values);return nil end
    for j=1,count do result[first+j-1]=values[j] end
    if job then job:checkpoint() end
  end
  return result
end
return M
