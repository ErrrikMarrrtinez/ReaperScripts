-- @noindex
local import=...;local Model=import('pitch/model');local Dot=import('pitch/neural_dot');local M={};M.__index=M
-- A numerical ReaImGui VM, not a JSFX/audio thread. Work is split by output
-- channel/frequency rows. All tensors use channel x frequency x time order.
M.legacy_code=[[
mode==3 ? (
  row=0;loop(cin*fin,
    src=input+row*frames;dst=output+row*frames;
    dst[0]=frames>1 ? src[1] : 0;
    t=1;loop(max(0,frames-2),dst[t]=src[t-1]+src[t+1];t+=1;);
    frames>1 ? dst[frames-1]=src[frames-2];row+=1;
  );
) : mode==1 ? (
  ci=0;loop(12,f=0;loop(96,t=0;loop(frames,
    output[(ci*96+f)*frames+t]=input[(ci*128+f)*frames+t];t+=1;);f+=1;);ci+=1;);
) : mode==2 ? (
  ci=0;loop(4,t=0;loop(frames,v=-1000000;f=0;loop(95,v=max(v,input[(ci*95+f)*frames+t]);f+=1;);
    output[ci*frames+t]=v;t+=1;);ci+=1;);
  t=0;loop(frames,v=0;j=0;loop(384,v+=features[j*frames+t];j+=1;);output[4*frames+t]=v/384;t+=1;);
) : (
loop(num_oc,
fo=first_f;
loop(num_f,
  outrow=output+(oc*fout+fo)*frames;
  t=0;loop(frames,
    outrow[t]=biases[oc]+(residual>=0 ? residual[(oc*fout+fo)*frames+t] : 0);
    t+=1;
  );
  ci=0;loop(cin,
    k=0;loop(kf,
      fi=fo+k*dilation-padding;
      fi>=0 && fi<fin ? (
        row=input+(ci*fin+fi)*frames;
        wp=weights+((oc*cin+ci)*kf+k)*kt;
        kt==3 && symmetric ? (
          pair=neighbors+(ci*fin+fi)*frames;
          a=wp[0];b=wp[1];t=0;
          loop(frames,outrow[t]+=pair[t]*a+row[t]*b;t+=1;);
        ) : kt==3 ? (
          // All exported temporal filters are symmetric. Keep the general
          // expression for parity if a future weight file changes that fact.
          a=wp[0];b=wp[1];c=wp[2];
          outrow[0]+=row[0]*b+(frames>1 ? row[1]*c : 0);
          t=1;loop(max(0,frames-2),outrow[t]+=row[t-1]*a+row[t]*b+row[t+1]*c;t+=1;);
          frames>1 ? outrow[frames-1]+=row[frames-2]*a+row[frames-1]*b;
        ) : (
          a=wp[0];t=0;loop(frames,outrow[t]+=row[t]*a;t+=1;);
        );
      );
      k+=1;
    );ci+=1;
  );
  relu ? (t=0;loop(frames,outrow[t]=max(0,outrow[t]);t+=1;););
  fo+=1;
);
oc+=1;);
);
]]
M.code=Dot.code..M.legacy_code
local function native(job,fn,...) if job then return job:call(fn,...) end;return fn(...) end
function M.new(im,ctx,r)
  local self=setmetatable({im=im,r=r,label='Lua neural',model=Model},M)
  local function initialize(fast)
    self.fast=fast
    self.fn=im.CreateFunctionFromEEL(fast and M.code or M.legacy_code);im.Attach(ctx,self.fn)
    local weights={};self.offsets={}
    for i,l in ipairs(Model.layers) do
      local p={weight=#weights};for _,v in ipairs(l.weight) do weights[#weights+1]=v end
      p.bias=#weights;for _,v in ipairs(l.bias) do weights[#weights+1]=v end;self.offsets[i]=p
      p.symmetric=l.kt==3
      if p.symmetric then for j=1,#l.weight,3 do if l.weight[j]~=l.weight[j+2] then p.symmetric=false;break end end end
    end
    assert(#weights<=32768,'Pitch weights exceed their buffer')
    im.Function_SetValue(self.fn,'weights',0)
    im.Function_SetValue_Array(self.fn,'weights',r.new_array(weights))
    if fast then Dot.upload(self) end
    -- Verify native VM memory transfer and convolution before trusting it.
    local input={};for i=1,384*3 do input[i]=math.sin(i*.13)*2-4 end
    local address=self:upload(input,65536)
    local output=self:conv(address,1,128,128,3,nil,true,nil,262144)
    local actual=self:download(output,12*128*3)
    local expected=self:conv_lua(input,1,128,128,3,nil,true)
    for i,v in ipairs(expected) do assert(actual[i] and math.abs(v-actual[i])<1e-7,'Pitch EEL self-test failed at '..i) end
    self.self_test=true
    self.label=fast and 'EEL neural (native dot)' or 'EEL neural (legacy)'
  end
  local ok,why=pcall(initialize,true)
  if not ok then
    self.fast_reason=tostring(why)
    -- Older ReaImGui/WDL builds may not expose mem_multiply_sum. Preserve the
    -- working EEL path if either compilation or the numerical self-test fails.
    if self.fn and im and im.Detach then pcall(im.Detach,ctx,self.fn) end
    self.fn=nil;ok,why=pcall(initialize,false)
  end
  if not ok then self.fn=nil;self.reason=tostring(why) end
  return self
end
function M:conv_lua(x,index,fin,fout,n,residual,relu,job)
  local l=Model.layers[index];local y={}
  for oc=0,l.cout-1 do
    for fo=0,fout-1 do
      local outrow=(oc*fout+fo)*n
      for t=0,n-1 do y[outrow+t+1]=l.bias[oc+1]+(residual and residual[outrow+t+1] or 0) end
      for ci=0,l.cin-1 do for k=0,l.kf-1 do
        local fi=fo+k*l.df-l.pad
        if fi>=0 and fi<fin then
          local row=(ci*fin+fi)*n;local wp=((oc*l.cin+ci)*l.kf+k)*l.kt
          if l.kt==3 then
            local a,b,c=l.weight[wp+1],l.weight[wp+2],l.weight[wp+3]
            for t=0,n-1 do
              y[outrow+t+1]=y[outrow+t+1]+(t>0 and x[row+t]*a or 0)+x[row+t+1]*b+(t+1<n and x[row+t+2]*c or 0)
            end
          else local a=l.weight[wp+1];for t=1,n do y[outrow+t]=y[outrow+t]+x[row+t]*a end end
        end
      end end
      if relu then for t=1,n do y[outrow+t]=math.max(0,y[outrow+t]) end end
      if job and fo%4==0 then job:checkpoint() end
    end
  end
  return y
end
function M:conv(x,index,fin,fout,n,residual,relu,job,dest)
  if not self.fn then return self:conv_lua(x,index,fin,fout,n,residual,relu,job) end
  if self.fast then return Dot.conv(self,x,index,fin,fout,n,residual,relu,job,dest) end
  local l,im,fn=Model.layers[index],self.im,self.fn
  local symmetric=self.offsets[index].symmetric
  if symmetric then native(job,function()
    for k,v in pairs({mode=3,input=x,output=851968,frames=n,cin=l.cin,fin=fin}) do im.Function_SetValue(fn,k,v) end
    im.Function_Execute(fn)
  end) end
  local function configure()
    for k,v in pairs({input=x,output=dest,weights=self.offsets[index].weight,biases=self.offsets[index].bias,
      residual=residual or -1,cin=l.cin,fin=fin,fout=fout,frames=n,kf=l.kf,kt=l.kt,dilation=l.df,padding=l.pad,relu=relu and 1 or 0,mode=0,
      symmetric=symmetric and 1 or 0,neighbors=851968}) do
      im.Function_SetValue(fn,k,v)
    end
  end
  native(job,configure)
  local function execute(oc,f,count,channels)
    im.Function_SetValue(fn,'oc',oc);im.Function_SetValue(fn,'first_f',f);im.Function_SetValue(fn,'num_f',count)
    im.Function_SetValue(fn,'num_oc',channels)
    local start=self.r.time_precise();im.Function_Execute(fn)
    self.kernel_ms=(self.kernel_ms or 0)+(self.r.time_precise()-start)*1000
    self.kernel_calls=(self.kernel_calls or 0)+1
  end
  local rows=math.min(128,math.max(16,math.floor(300000/math.max(1,n*l.cin*l.kf*l.kt)/16)*16))
  local channels=math.max(1,math.min(l.cout,math.floor(300000/math.max(1,n*l.cin*l.kf*l.kt*math.min(rows,fout)))))
  for oc=0,l.cout-1,channels do for f=0,fout-1,rows do
    native(job,execute,oc,f,math.min(rows,fout-f),math.min(channels,l.cout-oc))
    if job then job:checkpoint() end
  end end
  return dest
end
function M:upload(values,address,job)
  if not self.fn then return values end
  native(job,function()
    self.im.Function_SetValue(self.fn,'input',address)
    self.im.Function_SetValue_Array(self.fn,'input',self.r.new_array(values))
  end)
  return address
end
function M:download(address,count,job)
  if not self.fn then return address end
  return native(job,function()
    self.im.Function_SetValue(self.fn,'output',address)
    local a=self.r.new_array(count);self.im.Function_GetValue_Array(self.fn,'output',a);return a.table()
  end)
end
function M:operation(mode,input,output,n,job,features)
  native(job,function()
    for k,v in pairs({mode=mode,input=input,output=output,frames=n,features=features or 0}) do self.im.Function_SetValue(self.fn,k,v) end
    self.im.Function_Execute(self.fn)
  end)
  return output
end
-- features are log(sum(abs(FFT)*filter)+1e-8), three resolutions, 128 bins.
function M:infer(features,n,job,trace)
  assert(n>=1 and n<=128,'Pitch neural block outside 1..128 frames')
  local raw=self:upload(features,65536,job)
  local a,b,c=262144,458752,655360
  local x=self:conv(raw,1,128,128,n,nil,true,job,a)
  if trace then trace.v356=self:download(x,12*128*n,job) end
  for i=2,12,2 do
    local y=self:conv(x,i,128,128,n,nil,true,job,b)
    x=self:conv(y,i+1,128,128,n,x,true,job,c)
    a,c=c,a
    if trace and i==2 then trace.v365=self:download(x,12*128*n,job) end
    if trace and i==4 then trace.v374=self:download(x,12*128*n,job) end
  end
  if trace then trace.v410=self:download(x,12*128*n,job) end
  -- Slice the first 96 frequency rows while retaining the 128-row input stride.
  -- The final convolution must see zeros beyond row 95, not rows 96..127.
  local narrow
  if self.fn then narrow=self:operation(1,x,b,n,job)
  else
    narrow={};for ci=0,11 do for f=0,95 do for t=1,n do narrow[#narrow+1]=x[(ci*128+f)*n+t] end end end
  end
  local head=self:conv(narrow,14,96,95,n,nil,true,job,c)
  if trace then trace.v416=self:download(head,4*95*n,job) end
  -- Graph order: frequency confidence head, pitch head, temporal confidence head.
  local conf=self:conv(head,15,95,95,n,nil,false,job,a)
  local pitches=self:conv(head,16,95,95,n,nil,false,job,b)
  local pv=self:download(pitches,95*n,job)
  if trace then trace.v429=pv end
  local pooled
  if self.fn then pooled=self:operation(2,conf,c,n,job,raw)
  else
    pooled={};for ci=0,3 do for t=1,n do
      local v=-math.huge;for f=0,94 do v=math.max(v,conf[(ci*95+f)*n+t]) end;pooled[ci*n+t]=v
    end end
    for t=1,n do local v=0;for i=0,383 do v=v+features[i*n+t] end;pooled[4*n+t]=v/384 end
  end
  if trace then trace.v420=self:download(pooled,4*n,job) end
  local y=self:conv(pooled,17,1,1,n,nil,true,job,b)
  local z=self:conv(y,18,1,1,n,nil,false,job,c)
  local confidence=self:download(z,n,job)
  if trace then trace.v437=confidence end
  local out={}
  for t=1,n do
    local best,score=0,-math.huge
    for f=0,94 do local v=pv[f*n+t];if v>score then score,best=v,f end end
    local total,weighted=0,0
    for f=math.max(0,best-1),math.min(94,best+1) do
      local v=math.exp(pv[f*n+t]-score);total=total+v;weighted=weighted+v*Model.log_bins[f+1]
    end
    out[t]={hz=math.exp(weighted/total),confidence=1/(1+math.exp(-math.max(-50,math.min(50,confidence[t]))))}
  end
  return out
end
return M
