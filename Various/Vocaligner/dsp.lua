-- @noindex
local M={}
local abs, sqrt, log = math.abs, math.sqrt, math.log
function M.clamp(x,a,b) return math.max(a,math.min(b,x)) end
function M.percentile(values,q)
  local t={};for i,v in ipairs(values) do t[i]=v end;table.sort(t)
  return t[math.max(1,math.ceil(#t*q))] or 0
end
function M.median5(values,i)
  local t={};for k=math.max(1,i-2),math.min(#values,i+2) do t[#t+1]=values[k] end
  table.sort(t);return t[math.ceil(#t/2)]
end
-- Radix-2 fallback also lets the DSP run outside REAPER. Production uses native FFT.
function M.fft(re,im)
  local n=#re;local j=0
  for i=0,n-1 do
    if i<j then re[i+1],re[j+1]=re[j+1],re[i+1];im[i+1],im[j+1]=im[j+1],im[i+1] end
    local bit=n//2;while bit>0 and j>=bit do j=j-bit;bit=bit//2 end;j=j+bit
  end
  local len=2
  while len<=n do
    local ar,ai=math.cos(-2*math.pi/len),math.sin(-2*math.pi/len)
    for start=1,n,len do
      local wr,wi=1,0
      for k=0,len//2-1 do
        local a,b=start+k,start+k+len//2
        local vr,vi=re[b]*wr-im[b]*wi,re[b]*wi+im[b]*wr
        re[a],im[a],re[b],im[b]=re[a]+vr,im[a]+vi,re[a]-vr,im[a]-vi
        wr,wi=wr*ar-wi*ai,wr*ai+wi*ar
      end
    end
    len=len*2
  end
end
function M.analyzer(cfg,r)
  local n,sr,nb=cfg.fft_size,cfg.sample_rate,cfg.mel_bands
  local win,filters,dct={},{},{}
  for i=1,n do win[i]=0.5-0.5*math.cos(2*math.pi*(i-1)/n) end
  local function mel(f) return 2595*log(1+f/700)/log(10) end
  local function hz(m) return 700*(10^(m/2595)-1) end
  local lo,hi=mel(60),mel(math.min(7600,sr*0.48));local edges={}
  for i=0,nb+1 do edges[i+1]=hz(lo+(hi-lo)*i/(nb+1))*n/sr end
  for b=1,nb do
    local f={};filters[b]=f
    for k=math.max(1,math.ceil(edges[b])),math.min(n//2-1,math.floor(edges[b+2])) do
      f[#f+1]={k+1,math.max(0,math.min((k-edges[b])/(edges[b+1]-edges[b]),(edges[b+2]-k)/(edges[b+2]-edges[b+1])))}
    end
  end
  for c=1,12 do dct[c]={};for b=1,nb do dct[c][b]=math.cos(math.pi*c*(b-.5)/nb)*sqrt(2/nb) end end
  local fft=r and r.new_array(n*2) or nil
  local fft_input={}
  local obj={previous=nil,n=n,nb=nb,sr=sr}
  function obj:frame(samples,offset,channels,count)
    local power={};for k=1,n//2+1 do power[k]=0 end
    local energy,minv,maxv,zc=0,0,0,0
    for ch=1,channels do
      local re,im={},{};local prev=0
      for i=1,n do
        local s=0;local index=offset+i-1
        if index>=0 and index<count then s=samples[index*channels+ch] or 0 end
        energy=energy+s*s;minv=math.min(minv,s);maxv=math.max(maxv,s)
        if i>1 and (s>=0)~=(prev>=0) then zc=zc+1 end;prev=s
        if fft then fft_input[2*i-1]=s*win[i];fft_input[2*i]=0 else re[i]=s*win[i];im[i]=0 end
      end
      local spectrum
      if fft then
        -- Bulk transfers avoid thousands of Lua/userdata crossings per frame.
        fft.copy(fft_input,1,n*2,1);fft.fft(n,true);spectrum=fft.table(1,n+2)
      else M.fft(re,im) end
      for k=1,n//2+1 do
        local a,b;if fft then a,b=spectrum[2*k-1],spectrum[2*k] else a,b=re[k],im[k] end
        power[k]=power[k]+(a*a+b*b)/(n*n*channels)
      end
    end
    local bands,cep,flux,mean={}, {},0,0
    local spectral,chroma={},{}
    if not cfg.cleanup_only then
    for b=1,nb do
      local e=0;for _,f in ipairs(filters[b]) do e=e+power[f[1]]*f[2] end
      bands[b]=log(e+1e-12);mean=mean+bands[b]
      if self.previous then flux=flux+math.max(0,bands[b]-self.previous[b]) end
    end
    self.previous=bands;mean=mean/nb
    for c=1,12 do local s=0;for b=1,nb do s=s+bands[b]*dct[c][b] end;cep[c]=s end
    local norm=0
    for b=1,nb do spectral[b]=bands[b]-mean;norm=norm+spectral[b]^2 end
    norm=sqrt(norm)+1e-9;for b=1,nb do spectral[b]=spectral[b]/norm end
    for k=1,12 do chroma[k]=0 end
    end
    local low,high,total,logs=0,0,0,0
    -- Fixed 500 Hz bands retain detector energy above the alignment feature range.
    -- One FFT serves both matching and cleanup; moving the detector cutoff needs no reread.
    local noise_bands={};for k=1,math.ceil(sr/1000) do noise_bands[k]=0 end
    local noise_log,noise_sum,noise_count=0,0,0
    local breath_log,breath_sum,breath_count,breath_peak=0,0,0,0
    for k=2,n//2 do
      local e=power[k];local f=(k-1)*sr/n;local le=log(e+1e-14);total=total+e;logs=logs+le
      local band=math.min(#noise_bands,math.floor(f/500)+1)
      noise_bands[band]=noise_bands[band]+e*2/.375
      if f>=1500 then noise_sum=noise_sum+e;noise_log=noise_log+le;noise_count=noise_count+1 end
      if f>=80 and f<8000 then
        breath_log=breath_log+le;breath_sum=breath_sum+e
        breath_count=breath_count+1;breath_peak=math.max(breath_peak,e)
      end
      if f<350 then low=low+e end;if f>3500 then high=high+e end
      if not cfg.cleanup_only and f>=80 and f<=4000 then
        local pc=math.floor(69+12*log(f/440)/log(2)+.5)%12+1;chroma[pc]=chroma[pc]+sqrt(e)
      end
    end
    if not cfg.cleanup_only then
      local cn=0;for k=1,12 do cn=cn+chroma[k]^2 end;cn=sqrt(cn)+1e-9
      for k=1,12 do chroma[k]=chroma[k]/cn end
    end
    return {cep=cep,spec=spectral,chroma=chroma,flux=flux/nb,
      rms=sqrt(energy/(n*channels)),zcr=zc/((n-1)*channels),
      noise_bands=noise_bands,noise_flat=math.exp(noise_log/math.max(1,noise_count))/(noise_sum/math.max(1,noise_count)+1e-14),
      breath_flat=math.exp(breath_log/math.max(1,breath_count))/(breath_sum/math.max(1,breath_count)+1e-14),
      breath_tonal=breath_peak/(breath_sum+1e-14),
      air=high/(total+1e-12),low=low/(total+1e-12),
      flat=math.exp(logs/(n//2-1))/(total/(n//2-1)+1e-14),min=minv,max=maxv}
  end
  return obj
end
function M.normalize(data,cfg,job)
  local frames=data.frames;local levels,fluxes={},{}
  for i,f in ipairs(frames) do levels[i]=f.rms;fluxes[i]=f.flux end
  local top=M.percentile(levels,.95);local loudest=0;data.peak=0
  for _,v in ipairs(levels) do loudest=math.max(loudest,v) end
  -- A short phrase in a long silent item must not disappear below the 95th percentile.
  if top<loudest*.05 then
    local audible={};for _,v in ipairs(levels) do if v>loudest*.02 then audible[#audible+1]=v end end
    top=M.percentile(audible,.8)
  end
  for _,f in ipairs(frames) do data.peak=math.max(data.peak,abs(f.min),abs(f.max)) end
  if top<1e-7 then data.silent=true;return data end
  local noise=M.percentile(levels,.15)
  local gate=math.max(top*.012,math.min(top*.12,noise*2.5))
  data.gate=gate;data.level_top=top
  if not cfg.cleanup_only then
  local flux_scale=math.max(.15,M.percentile(fluxes,.95))
  local means,stds={},{};local count=0
  for k=1,12 do means[k],stds[k]=0,0 end
  for i,f in ipairs(frames) do
    f.active=f.rms>=gate
    if f.active then count=count+1;for k=1,12 do means[k]=means[k]+f.cep[k] end end
    if job and i%1024==0 then job:checkpoint() end
  end
  if count<4 then data.silent=true;return data end
  for k=1,12 do means[k]=means[k]/count end
  for i,f in ipairs(frames) do
    if f.active then for k=1,12 do stds[k]=stds[k]+(f.cep[k]-means[k])^2 end end
    if job and i%1024==0 then job:checkpoint() end
  end
  for k=1,12 do stds[k]=math.max(1.5,sqrt(stds[k]/count)) end
  for i,f in ipairs(frames) do
    for k=1,12 do f.cep[k]=M.clamp((f.cep[k]-means[k])/stds[k],-3,3) end
    f.energy=M.clamp(log(1+f.rms/top*20)/log(21),0,1.5)
    f.onset=M.clamp(f.flux/flux_scale,0,2)
    if f.active then data.first=data.first or i;data.last=i end
    if job and i%512==0 then job:checkpoint() end
  end
  for i,f in ipairs(frames) do
    local a,b=frames[math.max(1,i-2)],frames[math.min(#frames,i+2)]
    f.delta={};for k=1,6 do f.delta[k]=(b.cep[k]-a.cep[k])*.25 end
    if job and i%1024==0 then job:checkpoint() end
  end
  data.gate=gate;data.level_top=top;data.active_count=count
  end
  local levels={{hop=data.hop,values={}}}
  for i,f in ipairs(frames) do levels[1].values[i]={f.min,f.max};if job and i%1024==0 then job:checkpoint() end end
  while #levels[#levels].values>512 do
    local prev=levels[#levels];local nextp={hop=prev.hop*4,values={}}
    for i=1,#prev.values,4 do
      local lo,hi=0,0
      for j=i,math.min(i+3,#prev.values) do lo=math.min(lo,prev.values[j][1]);hi=math.max(hi,prev.values[j][2]) end
      nextp.values[#nextp.values+1]={lo,hi}
      if job and i%1024==1 then job:checkpoint() end
    end
    levels[#levels+1]=nextp
  end
  data.peaks=levels
  return data
end
-- Group-normalized costs: changing the number of MFCCs does not silently change its weight.
function M.distance(a,b,profile)
  if not a.active and not b.active then return .015 end
  if a.active~=b.active then return 1.15+.25*abs(a.energy-b.energy) end
  local ce,sp,de,ch=0,0,0,0
  for k=1,12 do ce=ce+math.min(4,(a.cep[k]-b.cep[k])^2);ch=ch+a.chroma[k]*b.chroma[k] end
  for k=1,#a.spec do sp=sp+a.spec[k]*b.spec[k] end
  for k=1,6 do de=de+math.min(4,(a.delta[k]-b.delta[k])^2) end
  local cw=profile=='Harmony / different voice' and 0 or (profile=='Speech' and .02 or .08)
  return .38*ce/12+.22*math.max(0,1-sp)+.12*de/6+cw*math.max(0,1-ch)
    +.18*math.min(2,abs(a.onset-b.onset))+.08*abs(a.energy-b.energy)
end
return M
