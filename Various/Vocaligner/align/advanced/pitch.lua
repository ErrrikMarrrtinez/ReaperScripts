-- @noindex
local import=...;local U=import('align/util');local DSP=import('dsp');local M={}
-- Optional autocorrelation evidence, independent of the Pitch editor/model.
-- Inverse transform uses conjugated forward FFT / N, making its scale explicit.
function M.new(r)
  local n,size,sr=2048,4096,32000;local window={}
  for i=1,n do window[i]=.5-.5*math.cos(2*math.pi*(i-1)/n)end
  local native=r and r.new_array and r.new_array(size*2);local input={}
  local function fft(re,im)
    if not native then DSP.fft(re,im);return re,im end
    for i=1,size do input[2*i-1]=re[i];input[2*i]=im[i]end
    native.copy(input,1,size*2,1);native.fft(size,true);local a=native.table(1,size*2)
    local rr,ii={},{};for i=1,size do rr[i]=a[2*i-1];ii[i]=a[2*i]end;return rr,ii
  end
  -- Native/library scale must agree with the reference impulse before use.
  if native then local re,im={},{};for i=1,size do re[i]=i==1 and 1 or 0;im[i]=0 end
    local a,b=fft(re,im);for i=1,size do assert(math.abs(a[i]-1)<1e-8 and math.abs(b[i])<1e-8,'Pitch FFT impulse calibration failed')end
  end
  local obj={}
  function obj:frame(samples,offset,channels,count)
    local corr,used={},0;for lag=39,534 do corr[lag]=0 end
    local valid=math.max(0,math.min(count,offset+n)-math.max(0,offset))/n
    for ch=1,channels do
      local re,im,prefix={},{},{[0]=0}
      for i=1,size do
        local s=0;local index=offset+i-1
        if i<=n and index>=0 and index<count then s=samples[index*channels+ch];assert(U.finite(s))end
        local v=i<=n and s*window[i] or 0;re[i]=v;im[i]=0
        if i<=n then prefix[i]=prefix[i-1]+v*v end
      end
      if prefix[n]>1e-12 then
        local rr,ii=fft(re,im);for i=1,size do rr[i]=rr[i]^2+ii[i]^2;ii[i]=0 end
        rr=fft(rr,ii);used=used+1
        for lag=39,534 do
          local den=math.sqrt(prefix[n-lag]*(prefix[n]-prefix[lag]))
          corr[lag]=corr[lag]+(den>1e-12 and U.clamp(rr[lag+1]/size/den,-1,1) or 0)
        end
      end
    end
    if used==0 or valid<.75 then return {voicing=0,stability=0,missing=valid==0}end
    for lag=39,534 do corr[lag]=corr[lag]/used end
    local lag,best=40,corr[40]
    for i=41,533 do if corr[i]>best then lag,best=i,corr[i]end end
    if best<.55 then return {voicing=0,stability=0}end
    local refined=lag
    if lag>40 and lag<533 then
      local den=corr[lag-1]-2*best+corr[lag+1]
      local dx=den<0 and .5*(corr[lag-1]-corr[lag+1])/den or 1
      if math.abs(dx)<=.5 then refined=lag+dx end
    end
    local f0=sr/refined;if f0<60 or f0>800 then return {voicing=0,stability=0}end
    local stability=1
    for i=40,533 do local ratio=i/lag
      if i~=lag and (ratio>=1.9 and ratio<=2.1 or ratio>=.475 and ratio<=.525)
        and corr[i]>=corr[i-1] and corr[i]>corr[i+1] and best-corr[i]<.03 then stability=.5 end
    end
    return {f0=f0,voicing=U.clamp((best-.55)/.35,0,1),stability=stability}
  end
  return obj
end
return M
