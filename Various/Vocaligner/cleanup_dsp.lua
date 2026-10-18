-- @noindex
-- The cleanup-only DSP from dsp.lua, evaluated in bounded blocks in a private VM.
-- Same Hann window, complex FFT, channel-power average and 500 Hz bands.
local import=...;local DSP=import('dsp');local M={};M.__index=M
M.code=[[
!reuse_input ? (
 invalid=0;input_peak=0;i=0;
 loop(samples_count*channels,
  x=input[i];!(abs(x)<=1000000) ? invalid=1;
  input_peak=max(input_peak,abs(x));i+=1;
 );
);
frame=0;
loop(frames,
  row=output+frame*42; memset(row,0,42); memset(power,0,513);
  energy=0; lo=0; hi=0; zc=0; channel=0;
  loop(channels,
    i=0; previous=0;
    loop(1024,
      at=offset+frame*hop+i;
      sample=at>=0 && at<samples_count ? input[at*channels+channel] : 0;
      energy+=sample*sample; lo=min(lo,sample); hi=max(hi,sample);
      i>0 && ((sample>=0)!=(previous>=0)) ? zc+=1;
      previous=sample;
      slot=fftbuf+reverse[floor(i/2)]*2+(i%2); slot[0]=sample*window[i]; i+=1;
    );
    width=2;
    loop(9,
      half=width/2; start=0; stride=1024/width;
      loop(512/width,
        j=0;
        loop(half,
          a=fftbuf+(start+j)*2; b=a+width;
          wr=twiddle[j*stride*2]; wi=twiddle[j*stride*2+1];
          vr=b[0]*wr-b[1]*wi; vi=b[0]*wi+b[1]*wr;
          b[0]=a[0]-vr; b[1]=a[1]-vi; a[0]+=vr; a[1]+=vi; j+=1;
        );
        start+=width;
      );
      width*=2;
    );
    // A 512-point complex FFT of even/odd samples gives the same 1024-point
    // real spectrum, without computing the redundant negative frequencies.
    power[0]+=(fftbuf[0]+fftbuf[1])^2/(1048576*channels);
    power[512]+=(fftbuf[0]-fftbuf[1])^2/(1048576*channels);
    k=1;
    loop(511,
      a=fftbuf+k*2; b=fftbuf+(512-k)*2;
      wr=twiddle[k*2]; wi=twiddle[k*2+1];
      xr=(a[0]+b[0]+wr*(a[1]+b[1])-wi*(b[0]-a[0]))*.5;
      xi=(a[1]-b[1]+wr*(b[0]-a[0])+wi*(a[1]+b[1]))*.5;
      power[k]+=(xr*xr+xi*xi)/(1048576*channels); k+=1;
    );
    channel+=1;
  );
  low=0; high=0; total=0; logs=0;
  nl=0; ns=0; nc=0; bl=0; bs=0; bc=0; bp=0;
  k=1;
  loop(511,
    e=power[k]; f=k*sr/1024; le=log(e+0.00000000000001); total+=e; logs+=le;
    band=min(31,floor(f/500)); row[10+band]+=e*2/.375;
    f>=1500 ? (ns+=e; nl+=le; nc+=1;);
    f>=80 && f<8000 ? (bs+=e; bl+=le; bc+=1; bp=max(bp,e););
    f<350 ? low+=e; f>3500 ? high+=e; k+=1;
  );
  row[0]=sqrt(energy/(1024*channels)); row[1]=zc/(1023*channels);
  row[2]=exp(nl/max(1,nc))/(ns/max(1,nc)+0.00000000000001);
  row[3]=exp(bl/max(1,bc))/(bs/max(1,bc)+0.00000000000001); row[4]=bp/(bs+0.00000000000001);
  row[5]=high/(total+0.000000000001); row[6]=low/(total+0.000000000001);
  row[7]=exp(logs/511)/(total/511+0.00000000000001); row[8]=lo; row[9]=hi;
  frame+=1;
);
]]
local fields={'rms','zcr','noise_flat','breath_flat','breath_tonal','air','low','flat','min','max'}
function M:execute(samples,offset,channels,count,frames,hop,sr,native,reuse_input)
  assert(frames>=1 and frames<=48 and channels>=1 and channels<=8 and #samples<=131072)
  local im,fn=self.im,self.fn
  if not reuse_input then im.Function_SetValue_Array(fn,'input',native and samples or self.r.new_array(samples)) end
  for key,value in pairs({offset=offset,channels=channels,samples_count=count,frames=frames,hop=hop,sr=sr,reuse_input=reuse_input and 1 or 0}) do im.Function_SetValue(fn,key,value) end
  local out=self.r.new_array(frames*42);local started=self.r.time_precise()
  im.Function_Execute(fn);self.kernel_ms=(self.kernel_ms or 0)+(self.r.time_precise()-started)*1000
  assert(im.Function_GetValue(fn,'invalid')==0,'Invalid PCM sample in cleanup analysis')
  local peak=im.Function_GetValue(fn,'input_peak')
  self.calls=(self.calls or 0)+1;im.Function_GetValue_Array(fn,'output',out)
  local values=out.table();local result={}
  for i=1,frames do
    local f={cep={},spec={},chroma={},flux=0,noise_bands={}};local at=(i-1)*42
    for j,key in ipairs(fields) do f[key]=values[at+j] end
    for b=1,32 do f.noise_bands[b]=values[at+10+b] end
    result[i]=f
  end
  return result,peak
end
-- Только энергии первых `bands` полос по 500 Hz, плоским массивом frames*bands (без таблиц на кадр).
-- Тот же EEL-проход, что execute(); нужен Mouth (click/spectral.lua), где остальные признаки не используются.
function M:band_rows(samples,offset,channels,count,frames,hop,sr,bands)
  assert(frames>=1 and frames<=48 and channels>=1 and channels<=8 and #samples<=131072 and bands>=1 and bands<=32)
  local im,fn=self.im,self.fn
  im.Function_SetValue_Array(fn,'input',self.r.new_array(samples))
  for key,value in pairs({offset=offset,channels=channels,samples_count=count,frames=frames,hop=hop,sr=sr,reuse_input=0}) do im.Function_SetValue(fn,key,value) end
  local out=self.r.new_array(frames*42);local started=self.r.time_precise()
  im.Function_Execute(fn);self.kernel_ms=(self.kernel_ms or 0)+(self.r.time_precise()-started)*1000
  assert(im.Function_GetValue(fn,'invalid')==0,'Invalid PCM sample in cleanup analysis')
  im.Function_GetValue_Array(fn,'output',out)
  local values=out.table();local result={}
  for i=1,frames do local at=(i-1)*42+10;for b=1,bands do result[#result+1]=values[at+b] end end
  return result
end
function M.new(im,ctx,r)
  local self=setmetatable({im=im,r=r,label='Lua + native FFT'},M)
  local ok,why=pcall(function()
    self.fn=im.CreateFunctionFromEEL(M.code);im.Attach(ctx,self.fn)
    for key,value in pairs({input=0,fftbuf=131072,power=134000,window=135000,twiddle=136100,reverse=137200,output=140000}) do
      im.Function_SetValue(self.fn,key,value)
    end
    local window,reverse,twiddle={},{},{}
    for i=0,1023 do
      window[i+1]=.5-.5*math.cos(2*math.pi*i/1024)
      if i<512 then local n,x=i,0;for _=1,9 do x=x*2+n%2;n=n//2 end;reverse[i+1]=x end
    end
    for i=0,511 do twiddle[2*i+1]=math.cos(-2*math.pi*i/1024);twiddle[2*i+2]=math.sin(-2*math.pi*i/1024) end
    for key,values in pairs({window=window,reverse=reverse,twiddle=twiddle}) do im.Function_SetValue_Array(self.fn,key,r.new_array(values)) end
    local samples={};for i=1,1200 do samples[2*i-1]=.2*math.sin(i*.137);samples[2*i]=-.1*math.sin(i*.291) end
    local cfg=import('config').copy(import('config').defaults);cfg.cleanup_only=true
    local expected=DSP.analyzer(cfg):frame(samples,-512,2,1200)
    local got=self:execute(samples,-512,2,1200,1,320,32000)[1]
    for _,key in ipairs(fields) do assert(math.abs(expected[key]-got[key])<1e-8,'Cleanup EEL self-check: '..key) end
    for b=1,32 do assert(math.abs(expected.noise_bands[b]-got.noise_bands[b])<1e-10,'Cleanup EEL spectrum self-check') end
    self.label='EEL cleanup DSP';self.calls=0;self.kernel_ms=0
  end)
  if not ok then
    if self.fn and im.Detach then pcall(im.Detach,ctx,self.fn) end
    self.fn=nil;self.reason=tostring(why)
  end
  return self
end
return M
