-- @noindex
local import=...;local U=import('align/util');local DSP=import('dsp');local Defaults=import('align/advanced/defaults');local M={}
local log,sqrt,abs=math.log,math.sqrt,math.abs
-- The legacy analyzer is intentionally not used: its filter normalization, RMS
-- padding and cepstral statistics have different semantics.
function M.analyzer(cfg,r)
  local n,sr,nb=1024,cfg.sample_rate,32;local win,filters,dct={},{},{}
  for i=1,n do win[i]=.5-.5*math.cos(2*math.pi*(i-1)/n) end
  local function mel(f)return 2595*log(1+f/700)/log(10)end
  local function hz(m)return 700*(10^(m/2595)-1)end
  local lo,hi=mel(60),mel(7600);local edges={}
  for i=0,nb+1 do edges[i+1]=hz(lo+(hi-lo)*i/(nb+1))*n/sr end
  for b=1,nb do
    local row,total={},0;filters[b]=row
    for k=math.max(0,math.ceil(edges[b])),math.min(n//2,math.floor(edges[b+2]))do
      local w=math.max(0,math.min((k-edges[b])/(edges[b+1]-edges[b]),(edges[b+2]-k)/(edges[b+2]-edges[b+1])))
      row[#row+1]={k+1,w};total=total+w
    end
    assert(total>0);for _,v in ipairs(row)do v[2]=v[2]/total end
  end
  for c=1,12 do dct[c]={};for b=1,nb do dct[c][b]=math.cos(math.pi*c*(b-.5)/nb)*sqrt(2/nb)end end
  local native=r and r.new_array and r.new_array(n*2);local input={}
  local obj={backend=native and 'Lua + native FFT' or 'Lua reference FFT'}
  function obj:frame(samples,offset,channels,count)
    local power={};for k=1,n//2+1 do power[k]=0 end
    local energy,clipped,valid,minv,maxv=0,0,0,0,0
    for ch=1,channels do
      local re,im={},{}
      for i=1,n do
        local index=offset+i-1;local s=0
        if index>=0 and index<count then
          s=samples[index*channels+ch];assert(U.finite(s),'Invalid PCM sample')
          energy=energy+s*s;valid=valid+1;if abs(s)>=.999 then clipped=clipped+1 end
          minv=math.min(minv,s);maxv=math.max(maxv,s)
        end
        if native then input[i*2-1]=s*win[i];input[i*2]=0 else re[i]=s*win[i];im[i]=0 end
      end
      local spectrum
      if native then native.copy(input,1,n*2,1);native.fft(n,true);spectrum=native.table(1,n+2) else DSP.fft(re,im) end
      for k=1,n//2+1 do
        local a,b=native and spectrum[k*2-1] or re[k],native and spectrum[k*2] or im[k]
        power[k]=power[k]+(a*a+b*b)/(n*n*.375*channels)*(k>1 and k<n//2+1 and 2 or 1)
      end
    end
    local bands,cep,mean={},{},0
    for b=1,nb do local e=0;for _,p in ipairs(filters[b])do e=e+power[p[1]]*p[2]end;bands[b]=log(math.max(e,1e-12));mean=mean+bands[b]end
    mean=mean/nb;local shape={};for b=1,nb do shape[b]=bands[b]-mean end
    local spec,norm=U.unit(shape)
    for c=1,12 do local value=0;for b=1,nb do value=value+bands[b]*dct[c][b]end;cep[c]=value end
    local total,logs,bins=0,0,0
    for k=1,n//2+1 do local f=(k-1)*sr/n;if f>=80 and f<=7600 then local p=math.max(power[k],1e-12);total=total+p;logs=logs+log(p);bins=bins+1 end end
    local rms=sqrt(energy/math.max(1,valid))
    return {mel=bands,raw_cep=cep,spec=spec,spec_norm=norm,rms=rms,energy_db=20*log(math.max(rms,1e-8))/log(10),
      flatness=math.exp(logs/bins)/(total/bins),valid_fraction=valid/(n*channels),clip_fraction=clipped/math.max(1,valid),
      min=minv,max=maxv,missing=valid==0,voicing_available=false}
  end
  return obj
end
local function pitch_at(pitches,t)
  if not pitches or #pitches==0 then return nil end
  local i=U.nearest(pitches,t);if abs(pitches[i].t-t)>.02000001 then return nil end;return pitches[i]
end
function M.normalize(raw,cfg,job)
  local frames=raw.frames;assert(#frames<=cfg.max_frames,'Advanced feature frame cap')
  local levels,high={},{};local loudest=-math.huge;local f={};local data={frames=f,pos=raw.pos,len=raw.len,hop=raw.hop or .01,
    schema=Defaults.frontend,feature_version=Defaults.frontend,analysis_rate=cfg.sample_rate,accessor_scale=raw.accessor_scale,
    baseline_id=raw.baseline_id,snapshot=raw.snapshot,analysis_stats=raw.analysis_stats,peak=0,pitch_enabled=cfg.advanced_pitch==true}
  for i,v in ipairs(frames)do
    assert(U.finite(v.t) and (i==1 or v.t>frames[i-1].t),'Nonmonotone frame time')
    local a=U.copy(v);a.cep={};f[i]=a
    if not a.missing then levels[#levels+1]=a.energy_db;loudest=math.max(loudest,a.energy_db)end
    data.peak=math.max(data.peak,abs(a.min or 0),abs(a.max or 0))
  end
  for _,v in ipairs(levels)do if v>loudest-45 then high[#high+1]=v end end
  local top=U.quantile(high,.90);local floor=math.min(U.quantile(levels,.15),top-24)
  data.silent=#levels==0 or loudest<-100;data.floor_db=floor;data.top_db=top
  local fluxes,changes={},{}
  for i,a in ipairs(f)do
    a.r0=a.missing and 0 or a.valid_fraction*(1-a.clip_fraction)
    a.provisional=data.silent and 0 or U.clamp((a.energy_db-floor-3)/15,0,1)
    a.sound=a.provisional*a.r0;a.energy=U.clamp((a.energy_db-(top-40))/40,0,1)
    local prev=f[i-1];a.flux=0;a.raw_change=0;a.onset_valid=false
    if prev and not prev.missing and not a.missing and a.t-prev.t<=data.hop*1.51 then
      a.onset_valid=true
      for b=1,32 do a.flux=a.flux+math.max(0,a.mel[b]-prev.mel[b])/32 end
      a.raw_change=U.clamp((1-U.dot(a.spec,prev.spec))/2,0,1)
      if a.provisional>=.30 then fluxes[#fluxes+1]=a.flux;changes[#changes+1]=a.raw_change end
    end
    U.checkpoint(job,i/#f*.15,'Normalizing acoustic evidence')
  end
  local fs=math.max(.15,U.quantile(fluxes,.95));local cs=math.max(.05,U.quantile(changes,.95))
  for _,a in ipairs(f)do a.onset=U.clamp(a.flux/fs,0,1);a.change=U.clamp(a.raw_change/cs,0,1)end
  local center,scale={},{}
  for k=1,12 do
    local vals={};for _,a in ipairs(f)do if a.provisional>=.30 and a.r0>=.75 then vals[#vals+1]=a.raw_cep[k]end end
    center[k]=#vals>=4 and U.quantile(vals,.5) or 0
    local deviations={};for i,v in ipairs(vals)do deviations[i]=abs(v-center[k])end
    scale[k]=#vals>=4 and math.max(1.5,1.4826*U.quantile(deviations,.5)) or 1.5
    for _,a in ipairs(f)do a.cep[k]=U.clamp((a.raw_cep[k]-center[k])/scale[k],-4,4)end
    U.checkpoint(job,.15+k/12*.15)
  end
  for i,a in ipairs(f)do
    local context=0
    for j=i,#f do if f[j].t-a.t>.15000001 or f[j].missing then break end;context=math.max(context,f[j].onset*f[j].r0)end
    for j=i-1,1,-1 do if a.t-f[j].t>.15000001 or f[j].missing then break end;context=math.max(context,f[j].onset*f[j].r0)end
    a.texture=math.max(U.clamp((.65-a.flatness)/.45,0,1),context,.10)
    local p=cfg.advanced_pitch and pitch_at(raw.pitches,a.t) or nil
    a.voicing_available=p~=nil and not p.missing;a.voiced=0;a.pitch_reliability=0
    a.f0=nil;a.pitch=nil;a.pitch_delta=nil;a.pitch_stability=nil
    if a.voicing_available then
      a.f0=p.f0;a.voiced=p.voicing or 0;a.pitch_stability=p.stability or 0
      if a.f0 then a.pitch=69+12*log(a.f0/440)/log(2);a.pitch_reliability=a.sound*a.voiced*a.pitch_stability end
    end
    a.background=a.missing and 0 or 1-a.sound
    a.event=a.sound*(a.voicing_available and math.max(a.voiced,(1-a.voiced)*a.texture) or a.texture)
    a.uncertain=a.sound*(1-a.texture)*(a.voicing_available and (1-a.voiced) or 1)
    a.spectral_reliability=a.sound*a.texture*(a.spec_norm>1e-6 and 1 or 0)
    a.onset_reliability=a.sound*a.texture*(a.onset_valid and 1 or 0)
    a.energy_reliability=a.sound
    local ia,ib=U.nearest(f,a.t-.02),U.nearest(f,a.t+.02);local aa,bb=f[ia],f[ib]
    a.delta={0,0,0,0,0,0};a.delta_valid=aa and bb and aa.t<=a.t-.02+1e-7 and bb.t>=a.t+.02-1e-7
    if a.delta_valid then for j=ia,ib do if f[j].missing then a.delta_valid=false end end end
    if a.delta_valid then for k=1,6 do a.delta[k]=(bb.cep[k]-aa.cep[k])*.01/(bb.t-aa.t)end end
    a.cep_reliability=a.spectral_reliability*(a.delta_valid and 1 or .70)
    a.left=i==1 and 0 or (f[i-1].t+a.t)/2;a.right=i==#f and data.len or (a.t+f[i+1].t)/2
    a.mass=(a.right-a.left)/.01;assert(a.mass>0,'Invalid frame support')
    a.trustworthy=not a.missing and a.valid_fraction>=.75
    a.active=a.event>=.30
    if a.active then data.first=data.first or i;data.last=i end
    U.checkpoint(job,.30+i/#f*.50)
  end
  if cfg.advanced_pitch then for _,a in ipairs(f)do
    local ia,ib=U.nearest(f,a.t-.04),U.nearest(f,a.t+.04);local aa,bb=f[ia],f[ib]
    if aa and bb and aa.t<=a.t-.04+1e-7 and bb.t>=a.t+.04-1e-7 and aa.pitch and bb.pitch and aa.voiced>=.5 and bb.voiced>=.5 then
      local valid=true;for j=ia,ib do if f[j].missing then valid=false end end
      if valid then a.pitch_delta=bb.pitch-aa.pitch end
    end
  end end
  local peaks={{hop=data.hop,values={}}};for i,a in ipairs(f)do peaks[1].values[i]={a.min or 0,a.max or 0}end
  while #peaks[#peaks].values>512 do
    local prev=peaks[#peaks];local nextp={hop=prev.hop*4,values={}}
    for i=1,#prev.values,4 do local lo,hi=0,0;for j=i,math.min(i+3,#prev.values)do lo=math.min(lo,prev.values[j][1]);hi=math.max(hi,prev.values[j][2])end;nextp.values[#nextp.values+1]={lo,hi}end
    peaks[#peaks+1]=nextp;U.checkpoint(job)
  end
  data.peaks=peaks;data.estimated_bytes=#f*8192 -- Conservative table/vector/raw-derived storage estimate, not only double payload.
  if data.estimated_bytes>cfg.max_feature_bytes then U.fail('work_budget_exceeded','Feature memory estimate exceeds cap','features')end
  data.normalization={center=center,scale=scale,flux_scale=fs,change_scale=cs}
  return data
end
function M.coarse(data,first,last,factor,job)
  factor=factor or 4;first=first or 1;last=last or #data.frames
  local out={frames={},pos=data.pos,len=data.len,hop=data.hop*factor,schema=data.schema}
  local vectors={'spec','cep','delta'}
  for i=first,last,factor do
    local a={t=0,mass=0,event=0,background=0,energy=0,onset=0,change=0,valid_fraction=0,
      spectral_reliability=0,cep_reliability=0,onset_reliability=0,energy_reliability=0,pitch_reliability=0,
      voiced=0,delta_valid=true,voicing_available=false,trustworthy=true}
    for _,k in ipairs(vectors)do a[k]={}end
    local stop=math.min(last,i+factor-1);local pitchw,pitchsum=0,0
    for j=i,stop do local f=data.frames[j];local m=f.mass;a.mass=a.mass+m;a.t=a.t+f.t*m
      for _,k in ipairs({'event','background','energy','valid_fraction','spectral_reliability','cep_reliability','onset_reliability','energy_reliability','pitch_reliability','voiced'})do a[k]=a[k]+f[k]*m end
      for _,k in ipairs(vectors)do for b,v in ipairs(f[k])do a[k][b]=(a[k][b] or 0)+v*m end end
      a.onset=math.max(a.onset,f.onset);a.change=math.max(a.change,f.change);a.delta_valid=a.delta_valid and f.delta_valid
      a.missing=a.missing or f.missing;a.trustworthy=a.trustworthy and f.trustworthy;a.voicing_available=a.voicing_available or f.voicing_available
      if f.pitch then pitchw=pitchw+f.pitch_reliability*m;pitchsum=pitchsum+f.pitch*f.pitch_reliability*m end
    end
    for _,k in ipairs({'t','event','background','energy','valid_fraction','spectral_reliability','cep_reliability','onset_reliability','energy_reliability','pitch_reliability','voiced'})do a[k]=a[k]/a.mass end
    for _,k in ipairs(vectors)do for b,v in ipairs(a[k])do a[k][b]=v/a.mass end end
    a.spec=U.unit(a.spec);a.left=data.frames[i].left;a.right=data.frames[stop].right
    if pitchw>0 then a.pitch=pitchsum/pitchw end
    a.first_index=i;a.last_index=stop;out.frames[#out.frames+1]=a;U.checkpoint(job)
  end
  return out
end
function M.validate(data,cfg)
  if type(data)~='table' or data.schema~=Defaults.frontend or not U.finite(data.pos) or not U.finite(data.len) or data.len<=0 then return nil,'Invalid feature header' end
  if type(data.frames)~='table' or #data.frames==0 or #data.frames>cfg.max_frames then return nil,'Invalid feature frame count' end
  for i,f in ipairs(data.frames)do
    for _,k in ipairs({'t','mass','event','background','onset','change','energy','valid_fraction','spectral_reliability','cep_reliability','onset_reliability','energy_reliability'})do if not U.finite(f[k])then return nil,'Invalid feature scalar '..k end end
    if f.mass<=0 or f.t<0 or f.t>data.len or i>1 and f.t<=data.frames[i-1].t then return nil,'Invalid frame support' end
    for k,n in pairs({spec=32,cep=12,delta=6})do if type(f[k])~='table' or #f[k]~=n then return nil,'Invalid feature dimension '..k end;for _,v in ipairs(f[k])do if not U.finite(v)then return nil,'Invalid feature number' end end end
  end
  return true
end
return M
