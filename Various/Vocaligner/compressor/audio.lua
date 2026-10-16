-- @noindex
local import=...;local Audio=import('audio');local DSP=import('dsp');local Config=import('config');local M={}
local resident={};local bytes=0;local limit=384*1024*1024
local function key(s) return table.concat({s.guid,s.render_key,s.offset,s.len},'|') end
function M.ensure(c,d,job)
 assert(c.app.engine and c.app.engine.dynamics and c.app.engine.dynamics.fn,
  'Compressor / Gate require the ReaImGui EEL engine. '..tostring(c.app.engine and c.app.engine.dynamics and c.app.engine.dynamics.reason or 'Engine not initialized.'))
 local r=c.r;local s=job:call(Audio.capture,r,c.project,d.snapshot.item,'cleanup');local identity=key(s)
 if d.pcm and d.pcm.key==identity then return d.pcm end
 local cache={key=identity,blocks={},channels=s.channels,len=s.len,bytes=0}
 local aa=job:call(r.CreateTakeAudioAccessor,s.take);assert(aa,'Cannot open dynamics audio accessor')
 job.resources[aa]=r.DestroyAudioAccessor
 local start=job:call(r.GetAudioAccessorStartTime,aa);local finish=job:call(r.GetAudioAccessorEndTime,aa)
 assert(math.abs(start)<1e-4,'Unexpected dynamics accessor time origin')
 local scale=1
 if math.abs(s.rate-1)>1e-6 and math.abs(finish-s.len*s.rate)<1e-4 and math.abs(finish-s.len)>1e-4 then scale=s.rate end
 local desired=math.max(48000,math.min(192000,s.source_rate or 48000));local read_sr=math.floor(desired/scale+.5)
 assert(read_sr>=1000 and read_sr<=192000,'Unsupported dynamics accessor/play rate')
 cache.sr=read_sr*scale;assert(cache.sr<=192000,'Dynamics rate exceeds 192 kHz')
 local total=math.ceil(s.len*cache.sr);local chunk=math.floor(32768/s.channels)
 assert(total*s.channels*8<=limit,'This item exceeds the 384 MB dynamics cache. Split it into shorter items.')
 local nil_reads,nonzero=0,false
 for first=0,total-1,chunk do
  local n=math.min(chunk,total-first)
  local b,status=job:call(function()
   Audio.validate_accessor(r,s,aa)
   local b=r.new_array(n*s.channels);b.clear()
   local status=r.GetAudioAccessorSamples(aa,read_sr,s.channels,first/cache.sr*scale,n,b)
   if status==0 then b.clear() end
   assert(status==nil or type(status)=='number' and status>=0,'Dynamics audio read failed')
   return b,status
  end)
  -- EEL validates PCM and supplies the initial light waveform, without an FFT.
  local cfg=Config.copy(d.cfg);cfg.compressor_threshold=6;cfg.compressor_ratio=1;cfg.compressor_gain=0
  cfg.compressor_rms_ms=0;cfg.compressor_attack_ms=0;cfg.compressor_release_ms=0
  cfg.compressor_hp=0;cfg.compressor_lp=20000;cfg.compressor_interval_ms=10;cfg.capture_wave=true
  local values,peak=job:call(c.app.engine.dynamics.run,c.app.engine.dynamics,b,n,s.channels,cache.sr,cfg,'compressor',{1,1},n+1,first==0)
  nonzero=nonzero or peak>1e-12
  cache.frames=cache.frames or {}
  for j=1,#values,6 do
   local f={t=values[j],rms=values[j+5],min=values[j+3],max=values[j+4],cep={},spec={},chroma={},noise_bands={},flux=0}
   cache.frames[#cache.frames+1]=f;if f.rms>1e-12 then nonzero=true end
  end
  if status==nil then nil_reads=nil_reads+1 end
  cache.blocks[#cache.blocks+1]={buffer=b,count=n,first=first};cache.bytes=cache.bytes+n*s.channels*8
  job:checkpoint((first+n)/total,'Caching dynamics · '..s.name)
 end
 job:call(r.DestroyAudioAccessor,aa);job.resources[aa]=nil
 local ok,why=job:call(Audio.unchanged,r,s);assert(ok,why)
 assert(nil_reads~=#cache.blocks or nonzero,'Accessor returned nil and no dynamics audio was received')
 while bytes+cache.bytes>limit and #resident>0 do
  local old=table.remove(resident,1);if old.owner.pcm==old.cache then old.owner.pcm=nil end
  bytes=bytes-old.cache.bytes
 end
 if d.pcm then
  for i=#resident,1,-1 do if resident[i].owner==d then bytes=bytes-resident[i].cache.bytes;table.remove(resident,i) end end
 end
 d.pcm=cache;bytes=bytes+cache.bytes;resident[#resident+1]={owner=d,cache=cache}
 return cache
end
function M.light(c,d,job)
 local pcm=M.ensure(c,d,job)
 local data={frames=pcm.frames,hop=.01,len=pcm.len,pos=d.snapshot.pos,snapshot=d.snapshot,
  dynamics_only=true,analysis_rate=pcm.sr,analysis_stats={backend='EEL dynamics / no FFT',read_ms=0,validation_ms=0,feature_ms=0,kernel_ms=0}}
 -- Only waveform normalization is required; no spectral feature construction.
 data.peaks={{hop=.01,values={}}};data.peak=0
 for i,f in ipairs(data.frames) do
  data.peaks[1].values[i]={f.min,f.max};data.peak=math.max(data.peak,-f.min,f.max)
 end
 return data
end
return M
