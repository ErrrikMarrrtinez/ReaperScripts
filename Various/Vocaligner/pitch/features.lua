-- @noindex
local import=...;local DSP=import('dsp');local Model=import('pitch/model');local M={};M.__index=M
function M.new(r)
  local self=setmetatable({r=r,windows={},scratch={},filters={}},M)
  for _,filter in ipairs(Model.filters) do
    local w={};for i=0,filter.size-1 do w[i+1]=.5-.5*math.cos(2*math.pi*i/filter.size) end
    self.windows[filter.size]=w
    self.scratch[filter.size]={data={},re={},im={},mag={}}
    local plan={size=filter.size,indices={},weights={},ends={}}
    for i,bin in ipairs(filter.bins) do
      for _,p in ipairs(bin) do local k=#plan.indices+1;plan.indices[k]=p[1]+1;plan.weights[k]=p[2] end
      plan.ends[i]=#plan.indices
    end
    self.filters[#self.filters+1]=plan
  end
  self.buffer=r and r.new_array(4096) or nil
  return self
end
function M:frame(samples,center)
  local values={}
  for _,filter in ipairs(self.filters) do
    local size=filter.size;local win=self.windows[size];local scratch=self.scratch[size]
    local data,re,im=scratch.data,scratch.re,scratch.im
    for i=1,size do
      local x=(samples[center-size//2+i] or 0)*win[i]
      if self.buffer then data[2*i-1]=x;data[2*i]=0 else re[i]=x;im[i]=0 end
    end
    local spectrum
    if self.buffer then self.buffer.copy(data,1,size*2,1);self.buffer.fft(size,true);spectrum=self.buffer.table(1,size+2)
    else DSP.fft(re,im) end
    local mag=scratch.mag
    for k=0,size//2 do
      local a,b;if spectrum then a,b=spectrum[k*2+1],spectrum[k*2+2] else a,b=re[k+1],im[k+1] end
      mag[k+1]=math.sqrt(a*a+b*b)
    end
    local first=1;local indices,weights=filter.indices,filter.weights
    for _,last in ipairs(filter.ends) do
      local sum=0;for k=first,last do sum=sum+mag[indices[k]]*weights[k] end;first=last+1
      values[#values+1]=math.log(sum+1e-8)
    end
  end
  return values
end
return M
